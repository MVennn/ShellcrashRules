#!/bin/sh
# rules-cnip.sh - collapse the inline CN IP-CIDR rules into a single RULE-SET rule
#
# Usage: rules-cnip.sh /path/to/config.yaml
#
# What it does
#   1. Adds a "cnip" child entry to the "rule-providers:" section. The entry is
#      indented exactly like the existing "cn:" child, so it can never turn into
#      a duplicated top level key (a duplicated top level key makes
#      "CrashCore -t" fail with "mapping key already defined").
#   2. Inside the "rules:" section every IP-CIDR / IP-CIDR6 rule whose target
#      is the direct-CN proxy group is removed and replaced by exactly one
#          - RULE-SET,cnip,<target>
#      placed at the position of the first removed rule, so the relative order
#      of the remaining rules is not changed.
#   3. Rules carrying a trailing comment (the hand written "#自定义规则"
#      entries of the user) are never removed, and every rule with another
#      target (DOMAIN*, other IP-CIDR targets, RULE-SET,cn, MATCH, ...) is
#      kept byte for byte.
#
# Guarantees
#   * Idempotent - a second run reports "already present" and changes nothing.
#   * Writes a temporary file in the same directory, verifies line counts,
#     rule counts, IP-CIDR counts and a full line by line reconstruction,
#     then replaces the target with mv (atomic).
#   * Any failure leaves the input file untouched.

set -u

CFG="${1:-}"
TARGET='🎯 全球直连'
RULE_LINE=" - RULE-SET,cnip,${TARGET}"
PROV_KEY="cnip"
PROV_OPTS="{type: file, behavior: ipcidr, format: mrs, path: ./ruleset/cnip.mrs}"

die() {
	echo "rules-cnip: $*" >&2
	exit 1
}

[ -n "$CFG" ] || die "usage: $0 /path/to/config.yaml"
[ -f "$CFG" ] || die "no such file: $CFG"
[ -r "$CFG" ] || die "not readable: $CFG"
DIR=$(dirname "$CFG")
[ -w "$DIR" ] || die "directory not writable: $DIR"

# The rule provider path is resolved relative to the core home directory
# (CrashCore -d /etc/ShellCrash), so the ruleset file must live there.
SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || SELF_DIR=/etc/ShellCrash
CNIP_FILE="$SELF_DIR/ruleset/cnip.mrs"
[ -s "$CNIP_FILE" ] || die "ruleset file missing or empty: $CNIP_FILE"

TMP="$CFG.rules-cnip.$$"
DEL="$TMP.del"
ANA="$TMP.ana"
trap 'rm -f "$TMP" "$DEL" "$ANA"' EXIT HUP INT TERM
: >"$DEL"

# ---------- 1. pre-flight: the target proxy group must exist ----------
awk -v tg="$TARGET" '
/^proxy-groups:[ ]*$/ { ing=1; next }
ing && /^[^ ]/ { ing=0 }
ing && index($0, "- name: " tg) { found=1 }
END { exit !found }
' "$CFG" || die "proxy group not found: $TARGET"

# ---------- 2. pre-flight: the rules: section must exist ----------
awk '/^rules:[ ]*$/ { f=1 } END { exit !f }' "$CFG" ||
	die "no rules: section in $CFG"

# ---------- 3. analysis pass ----------
# Collects the rule-providers block bounds, the indentation of its children,
# the rules: block bounds, the first removable line, the number of removable
# lines and whether RULE-SET,cnip is already there.
awk -v tg="$TARGET" -v delfile="$DEL" '
function ind(s) { match(s, /^[ ]*/); return RLENGTH }
BEGIN {
	rp_first=0; rp_last=0; cn_line=0; cn_ind=0; child_ind=0
	has_cnip=0; rules_first=0; rules_last=0
	del_first=0; del_n=0; keep_cust=0; already=0
}
/^rule-providers:[ ]*$/ { inrp=1; inr=0; rp_first=NR; rp_last=NR; next }
inrp && /^[^ ]/ { inrp=0 }
/^rules:[ ]*$/ { inr=1; inrp=0; rules_first=NR; rules_last=NR; next }
inr && /^[^ ]/ { inr=0 }
inrp {
	rp_last=NR
	if (child_ind == 0) child_ind=ind($0)
	if (cn_line == 0 && $0 ~ /^[ ]+cn:[ ]*/) { cn_line=NR; cn_ind=ind($0) }
	if ($0 ~ /^[ ]+cnip:[ ]*/) has_cnip=1
	next
}
inr {
	rules_last=NR
	L=$0
	sub(/^[ \t]+/, "", L)
	if (L ~ /^-[ \t]*RULE-SET,cnip,/) already=1
	if (L ~ /^-[ \t]*IP-CIDR6?(,|$)/) {
		split($0, a, ",")
		t=a[3]
		gsub(/^[ \t]+/, "", t)
		gsub(/[ \t]+$/, "", t)
		if (t == tg) {
			if (index($0, "#") > 0) keep_cust++
			else {
				if (del_first == 0) del_first=NR
				del_n++
				print NR > delfile
			}
		}
	}
}
END {
	printf "%d %d %d %d %d %d %d %d %d %d %d %d\n", rp_first, rp_last,
		cn_line, cn_ind, child_ind, has_cnip, rules_first, rules_last,
		del_first, del_n, keep_cust, already
}
' "$CFG" >"$ANA" || die "analysis failed"

RP_FIRST=0; RP_LAST=0; CN_LINE=0; CN_IND=0; CHILD_IND=0; HAS_CNIP=0
RULES_FIRST=0; RULES_LAST=0; DEL_FIRST=0; DEL_N=0; KEEP_CUST=0; ALREADY=0
read -r RP_FIRST RP_LAST CN_LINE CN_IND CHILD_IND HAS_CNIP RULES_FIRST \
	RULES_LAST DEL_FIRST DEL_N KEEP_CUST ALREADY <"$ANA"

[ "${RULES_FIRST}" -gt 0 ] || die "no rules: section found"

# ---------- 4. idempotency ----------
if [ "$ALREADY" -ne 0 ] && [ "$HAS_CNIP" -ne 0 ]; then
	echo "rules-cnip: RULE-SET,cnip already present, no change"
	exit 0
fi

NEED_PROV=0
[ "$HAS_CNIP" -eq 0 ] && NEED_PROV=1

INS_LINE=0
if [ "$ALREADY" -eq 0 ]; then
	[ "$DEL_N" -gt 0 ] || die "no removable IP-CIDR rule found for $TARGET"
	INS_LINE="$DEL_FIRST"
fi

# ---------- 5. build the rule-provider block ----------
if [ "$RP_FIRST" -gt 0 ]; then
	if [ "$CN_LINE" -gt 0 ]; then
		PROV_IND="$CN_IND"
		PROV_AFTER="$CN_LINE"
	elif [ "$CHILD_IND" -gt 0 ]; then
		PROV_IND="$CHILD_IND"
		PROV_AFTER="$RP_LAST"
	else
		PROV_IND=2
		PROV_AFTER="$RP_FIRST"
	fi
	PROV_BLOCK="$(printf '%*s%s: %s' "$PROV_IND" '' "$PROV_KEY" "$PROV_OPTS")"
else
	PROV_IND=2
	PROV_AFTER=$(awk 'END { print NR }' "$CFG")
	PROV_BLOCK="rule-providers:|$(printf '%*s%s: %s' "$PROV_IND" '' "$PROV_KEY" "$PROV_OPTS")"
fi

NPROV=$(printf '%s' "$PROV_BLOCK" | awk -F'|' '{ print NF }')

NIN=$(awk 'END { print NR }' "$CFG")
INS_ADD=0
[ "$INS_LINE" -gt 0 ] && INS_ADD=1
PROV_ADD=0
[ "$NEED_PROV" -eq 1 ] && PROV_ADD="$NPROV"

# ---------- 6. write the new file ----------
# cp -p first so the temporary file inherits the mode/owner of the original,
# the redirect below only truncates it and therefore keeps that mode.
cp -p "$CFG" "$TMP" || die "failed to create $TMP"
awk -v ins="$INS_LINE" -v provafter="$PROV_AFTER" -v provblock="$PROV_BLOCK" \
	-v needprov="$NEED_PROV" -v rule="$RULE_LINE" -v delfile="$DEL" '
BEGIN {
	while ((getline l < delfile) > 0) del[l]=1
	nprov=split(provblock, plines, "|")
}
NR == ins { print rule }
del[NR] { next }
{ print }
NR == provafter {
	if (needprov) for (k=1; k<=nprov; k++) print plines[k]
}
' "$CFG" >"$TMP" || die "failed to write $TMP"

[ -s "$TMP" ] || die "output is empty"

# ---------- 7. verification ----------
NOUT=$(awk 'END { print NR }' "$TMP")
EXP=$((NIN - DEL_N + INS_ADD + PROV_ADD))
[ "$NOUT" -eq "$EXP" ] ||
	die "line count mismatch (expected $EXP, got $NOUT)"

RIN=$(awk '/^rules:[ ]*$/ { inr=1; next } inr && /^[^ ]/ { inr=0 } inr && /^[ ]+- / { n++ } END { print n+0 }' "$CFG")
ROUT=$(awk '/^rules:[ ]*$/ { inr=1; next } inr && /^[^ ]/ { inr=0 } inr && /^[ ]+- / { n++ } END { print n+0 }' "$TMP")
[ "$ROUT" -eq $((RIN - DEL_N + INS_ADD)) ] ||
	die "rule count mismatch ($RIN - $DEL_N + $INS_ADD != $ROUT)"

IIN=$(awk '/^rules:[ ]*$/ { inr=1; next } inr && /^[^ ]/ { inr=0 } inr && /^[ ]*-[ ]*IP-CIDR6?(,|$)/ { n++ } END { print n+0 }' "$CFG")
IOUT=$(awk '/^rules:[ ]*$/ { inr=1; next } inr && /^[^ ]/ { inr=0 } inr && /^[ ]+-[ ]*IP-CIDR6?(,|$)/ { n++ } END { print n+0 }' "$TMP")
[ "$IOUT" -eq $((IIN - DEL_N)) ] ||
	die "IP-CIDR count mismatch ($IIN - $DEL_N != $IOUT)"

CIN=$(awk -v tg="$TARGET" '/^rules:[ ]*$/ { inr=1; next } inr && /^[^ ]/ { inr=0 } inr { L=$0; sub(/^[ \t]+/,"",L); if (L ~ /^-[ \t]*IP-CIDR6?(,|$)/) { split($0,a,","); t=a[3]; gsub(/^[ \t]+/,"",t); gsub(/[ \t]+$/,"",t); if (t==tg && index($0,"#")>0) n++ } } END { print n+0 }' "$CFG")
COUT=$(awk -v tg="$TARGET" '/^rules:[ ]*$/ { inr=1; next } inr && /^[^ ]/ { inr=0 } inr { L=$0; sub(/^[ \t]+/,"",L); if (L ~ /^-[ \t]*IP-CIDR6?(,|$)/) { split($0,a,","); t=a[3]; gsub(/^[ \t]+/,"",t); gsub(/[ \t]+$/,"",t); if (t==tg && index($0,"#")>0) n++ } } END { print n+0 }' "$TMP")
[ "$COUT" -eq "$CIN" ] || die "custom rules lost ($CIN -> $COUT)"

RSOUT=$(awk '/^rules:[ ]*$/ { inr=1; next } inr && /^[^ ]/ { inr=0 } inr { L=$0; sub(/^[ \t]+/,"",L); if (L ~ /^-[ \t]*RULE-SET,cnip,/) n++ } END { print n+0 }' "$TMP")
[ "$RSOUT" -eq 1 ] || die "expected exactly 1 RULE-SET,cnip rule, found $RSOUT"

PC=$(awk '/^rule-providers:[ ]*$/ { inrp=1; next } inrp && /^[^ ]/ { inrp=0 } inrp { L=$0; sub(/^[ \t]+/,"",L); if (L ~ /^cnip[ ]*:/) n++ } END { print n+0 }' "$TMP")
[ "$PC" -eq 1 ] || die "expected exactly 1 cnip rule-provider, found $PC"
awk '/^cnip[ ]*:/ { n++ } END { exit (n > 0) }' "$TMP" ||
	die "cnip ended up as a top level key"

awk -v ins="$INS_LINE" -v provafter="$PROV_AFTER" -v provblock="$PROV_BLOCK" \
	-v needprov="$NEED_PROV" -v rule="$RULE_LINE" -v delfile="$DEL" '
FNR==NR { inl[FNR]=$0; nin=FNR; next }
{ outl[FNR]=$0; nout=FNR }
END {
	while ((getline l < delfile) > 0) del[l]=1
	nprov=split(provblock, plines, "|")
	oi=0
	for (i=1; i<=nin; i++) {
		if (i==ins) { oi++; rb[oi]=rule }
		if (i in del) continue
		oi++; rb[oi]=inl[i]
		if (i==provafter && needprov) {
			for (k=1; k<=nprov; k++) { oi++; rb[oi]=plines[k] }
		}
	}
	if (oi != nout) {
		printf "reconstruct: %d lines rebuilt but %d lines in output\n", oi, nout > "/dev/stderr"
		exit 1
	}
	for (i=1; i<=nout; i++) {
		if (rb[i] != outl[i]) {
			printf "reconstruct: line %d differs\n", i > "/dev/stderr"
			exit 1
		}
	}
}
' "$CFG" "$TMP" || die "content integrity check failed"

# ---------- 8. replace atomically (the temp file already carries the
#               original mode and owner thanks to the cp -p above) ----------
mv -f "$TMP" "$CFG" || die "failed to replace $CFG"

echo "rules-cnip: removed $DEL_N inline rule(s) for $TARGET, inserted RULE-SET,cnip at line $INS_LINE"
if [ "$NEED_PROV" -eq 1 ]; then
	echo "rules-cnip: rule-provider cnip added after line $PROV_AFTER (indent $PROV_IND)"
else
	echo "rules-cnip: rule-provider cnip already present, not touched"
fi
echo "rules-cnip: lines $NIN -> $NOUT, rules $RIN -> $ROUT, IP-CIDR $IIN -> $IOUT, custom kept $COUT"
exit 0
