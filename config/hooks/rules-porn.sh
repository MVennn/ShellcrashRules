#!/bin/sh
# rules-porn.sh - add the upstream category-porn rule-set provider
#
# Usage: rules-porn.sh /path/to/config.yaml
#
# Why
#   The hand-written adult-site list in rules.yaml only covers the big tube
#   sites; a site that is not in the list silently falls through to the
#   default exit. MetaCubeX's category-porn set (~6.5k domains, updated daily)
#   is the systematic coverage.
#
# What it does
#   Adds one child entry to the "rule-providers:" section, indented exactly
#   like the existing children so it can never turn into a duplicated top
#   level key (a duplicated top level key makes "CrashCore -t" fail with
#   "mapping key already defined").
#
#   The rule itself (- RULE-SET,porn,📺 大流量) is emitted by
#   ai-rules-update.sh section I, so this hook only manages the provider.
#   If the target group is missing the hook skips (the config would be
#   invalid anyway).
#
# Guarantees
#   * Idempotent - a second run reports "already present" and changes nothing.
#   * Writes a temporary file, verifies the line count, then replaces the
#     target with mv (atomic).
#   * Any failure leaves the input file untouched.

set -u

CFG="${1:-}"
GROUP='📺 大流量'
PROV_KEY="porn"
PROV_OPTS="{type: http, behavior: domain, format: mrs, path: ./ruleset/porn.mrs, interval: 86400, url: https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/category-porn.mrs}"

die() {
	echo "rules-porn: $*" >&2
	exit 1
}

[ -n "$CFG" ] || die "usage: $0 /path/to/config.yaml"
[ -f "$CFG" ] || die "no such file: $CFG"
[ -r "$CFG" ] || die "not readable: $CFG"
DIR=$(dirname "$CFG")
[ -w "$DIR" ] || die "directory not writable: $DIR"

# ---------- 1. pre-flight: target proxy group must exist ----------
awk -v tg="$GROUP" '
/^proxy-groups:[ ]*$/ { ing=1; next }
ing && /^[^ ]/ { ing=0 }
ing && index($0, "- name: " tg) { found=1 }
END { exit !found }
' "$CFG" || { echo "rules-porn: proxy group not found, skip"; exit 0; }

TMP="$CFG.rules-porn.$$"
ANA="$TMP.ana"
trap 'rm -f "$TMP" "$ANA"' EXIT HUP INT TERM

# ---------- 2. analysis: rule-providers bounds, child indent, existing key ----------
awk '
function ind(s) { match(s, /^[ ]*/); return RLENGTH }
/^rule-providers:[ ]*$/ { inrp=1; rp_first=NR; rp_last=NR; next }
inrp && /^[^ ]/ { inrp=0 }
inrp {
	rp_last=NR
	if (child_ind == 0) child_ind=ind($0)
	if ($0 ~ /^[ ]+porn:[ ]*/) has=1
	next
}
END { printf "%d %d %d %d\n", rp_first, rp_last, child_ind, has+0 }
' "$CFG" >"$ANA" || die "analysis failed"

read -r RP_FIRST RP_LAST CHILD_IND HAS <"$ANA"

if [ "$HAS" -eq 1 ]; then
	echo "rules-porn: provider already present, no change"
	exit 0
fi

# ---------- 3. build the block ----------
if [ "$RP_FIRST" -gt 0 ]; then
	PROV_IND="$CHILD_IND"
	[ "$PROV_IND" -gt 0 ] || PROV_IND=2
	PROV_AFTER="$RP_LAST"
	PROV_BLOCK="$(printf '%*s%s: %s' "$PROV_IND" '' "$PROV_KEY" "$PROV_OPTS")"
else
	PROV_AFTER=$(awk 'END { print NR }' "$CFG")
	PROV_BLOCK="rule-providers:|$(printf '  %s: %s' "$PROV_KEY" "$PROV_OPTS")"
fi
NPROV=$(printf '%s' "$PROV_BLOCK" | awk -F'|' '{ print NF }')

# ---------- 4. write + verify ----------
cp -p "$CFG" "$TMP" || die "failed to create $TMP"
awk -v after="$PROV_AFTER" -v block="$PROV_BLOCK" '
BEGIN { n=split(block, b, "|") }
{ print }
NR == after { for (i = 1; i <= n; i++) print b[i] }
' "$CFG" >"$TMP" || die "failed to write $TMP"

[ -s "$TMP" ] || die "output is empty"
NIN=$(awk 'END { print NR }' "$CFG")
NOUT=$(awk 'END { print NR }' "$TMP")
[ "$NOUT" -eq $((NIN + NPROV)) ] ||
	die "line count mismatch (expected $((NIN + NPROV)), got $NOUT)"
grep -q "^[ ]*$PROV_KEY:" "$TMP" || die "provider entry missing in output"

mv -f "$TMP" "$CFG" || die "mv failed"
echo "rules-porn: provider added ($PROV_KEY)"
