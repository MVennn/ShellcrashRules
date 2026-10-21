#!/bin/sh
# rules-mid.sh —— 在生成的 config.yaml 中插入 CN 直连中间层
#
# 用法: rules-mid.sh /path/to/config.yaml
#
# 插入位置: rules: 段内，ProxyMedia 第一条规则
#           "DOMAIN-SUFFIX,edgedatg.com,🌍 国外媒体" 之前。
# 目的:     让服务规则优先，同时让 CN 直连先于 ProxyMedia/ProxyLite 的宽泛代理规则。
# 锚点不再依赖 "📲 电报消息" 组名（该组已删除），改用
#           Telegram 域名规则 + ProxyMedia 首条规则双重定位。
#
# 由 starts/clash_modify.sh 在 merger_yaml 之后、test_yaml 之前调用。
# 特性: 幂等；先在原文件同目录写临时文件并做完整性校验，
#       全部通过后才用 mv 原子替换；任何失败都不改动原文件。

set -u

CFG="${1:-}"
RULE_LINE=' - RULE-SET,cn,🎯 全球直连'
EDGE_RULE='- DOMAIN-SUFFIX,edgedatg.com,🌍 国外媒体'
CN_RULE='- RULE-SET,cn,🎯 全球直连'

die() {
	echo "rules-mid: $*" >&2
	exit 1
}

[ -n "$CFG" ] || die "usage: $0 /path/to/config.yaml"
[ -f "$CFG" ] || die "no such file: $CFG"
[ -r "$CFG" ] || die "not readable: $CFG"
DIR=$(dirname "$CFG")
[ -w "$DIR" ] || die "directory not writable: $DIR"

# ---------- 1. 预检：rule-providers.cn 必须存在且 behavior: domain / format: mrs ----------
awk '
function indent(s) { match(s, /^[ ]*/); return RLENGTH }
/^rule-providers:[ ]*$/ { inrp=1; next }
inrp && /^[^ ]/ { inrp=0 }
inrp && !incn && /^[ ]+cn:[ ]*/ {
	incn=1
	cnind=indent($0)
	rest=$0
	sub(/^[ ]+cn:[ ]*/, "", rest)
	if (rest != "") {
		if (index(rest, "behavior: domain")) bd=1
		if (index(rest, "format: mrs")) fm=1
	}
	next
}
inrp && incn {
	if ($0 ~ /^[ ]*$/) next
	if (indent($0) <= cnind) { incn=0; next }
	if (index($0, "behavior: domain")) bd=1
	if (index($0, "format: mrs")) fm=1
}
END { exit !(bd && fm) }
' "$CFG" || die "rule-providers.cn missing or not (behavior: domain, format: mrs)"

# ---------- 2. 预检：目标策略组必须存在 ----------
awk '
/^proxy-groups:[ ]*$/ { ing=1; next }
ing && /^[^ ]/ { ing=0 }
ing && index($0, "- name: 🎯 全球直连") { found=1 }
END { exit !found }
' "$CFG" || die "proxy group not found: 🎯 全球直连"

# ---------- 3. 定位：第一条 ProxyMedia 规则（CN 直连插在它之前）----------
EDGE_LINE=$(awk -v edge="$EDGE_RULE" '
/^rules:[ ]*$/ { inr=1; next }
inr && /^[^ ]/ { inr=0 }
inr && index($0, edge) { print NR; exit }
' "$CFG")
[ -n "$EDGE_LINE" ] || die "ProxyMedia anchor not found: $EDGE_RULE"

# ---------- 4. 定位：它之前的最后一条 Telegram 域名规则（顺序校验）----------
LAST_TG=$(awk -v edge="$EDGE_LINE" '
/^rules:[ ]*$/ { inr=1; next }
inr && /^[^ ]/ { inr=0 }
inr && NR < edge && (index($0,"t.me") || index($0,"tdesktop.com") || index($0,"telegra.ph") || index($0,"telegram.me") || index($0,"telegram.org")) { n=NR }
END { print n+0 }
' "$CFG")
[ "$LAST_TG" -gt 0 ] || die "no Telegram rule found before ProxyMedia anchor"
[ "$LAST_TG" -lt "$EDGE_LINE" ] || die "anchor order invalid (edge=$EDGE_LINE, telegram=$LAST_TG)"

# ---------- 5. 幂等：目标区间内已有该规则则不重复插入 ----------
EXIST=$(awk -v s="$LAST_TG" -v e="$EDGE_LINE" -v cn="$CN_RULE" '
/^rules:[ ]*$/ { inr=1; next }
inr && /^[^ ]/ { inr=0 }
inr && NR > s && NR < e {
	L=$0
	sub(/^[ \t]+/, "", L)
	sub(/[ \t]+$/, "", L)
	sub(/[ \t]+#.*$/, "", L)
	sub(/[ \t]+$/, "", L)
	if (L == cn) { print NR; exit }
}
' "$CFG")
if [ -n "$EXIST" ]; then
	echo "rules-mid: already present at line $EXIST (between $LAST_TG and $EDGE_LINE), no change"
	exit 0
fi

# ---------- 6. 同规则若已出现在其他位置，也不制造重复 ----------
OTHER=$(awk -v cn="$CN_RULE" '
/^rules:[ ]*$/ { inr=1; next }
inr && /^[^ ]/ { inr=0 }
inr {
	L=$0
	sub(/^[ \t]+/, "", L)
	sub(/[ \t]+$/, "", L)
	sub(/[ \t]+#.*$/, "", L)
	sub(/[ \t]+$/, "", L)
	if (L == cn) { print NR; exit }
}
' "$CFG")
if [ -n "$OTHER" ]; then
	echo "rules-mid: WARN: $CN_RULE already exists at line $OTHER (outside target interval $LAST_TG..$EDGE_LINE), no change" >&2
	exit 0
fi

# ---------- 7. 生成临时文件（同目录，保证 mv 原子），失败自动清理 ----------
TMP="$CFG.rules-mid.$$"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
awk -v at="$EDGE_LINE" -v ins="$RULE_LINE" '
NR == at { print ins }
{ print }
' "$CFG" > "$TMP" || die "failed to write $TMP"

# ---------- 8. 校验：只多一行、位置正确、其余内容逐行一致 ----------
[ -s "$TMP" ] || die "output is empty"

NIN=$(awk 'END { print NR }' "$CFG")
NOUT=$(awk 'END { print NR }' "$TMP")
[ "$NOUT" -eq $((NIN + 1)) ] || die "line count mismatch ($NIN -> $NOUT)"

awk -v at="$EDGE_LINE" -v ins="$RULE_LINE" '
FNR == NR { a[FNR]=$0; n=FNR; next }
{
	if (FNR == at) {
		if ($0 != ins) bad=1
		next
	}
	j = (FNR > at) ? FNR - 1 : FNR
	if ($0 != a[j]) bad=1
}
END {
	if (FNR != n + 1) bad=1
	exit bad
}
' "$CFG" "$TMP" || die "content integrity check failed"

RIN=$(awk '/^rules:[ ]*$/ { inr=1; next } inr && /^[^ ]/ { inr=0 } inr && /^[ ]+- / { n++ } END { print n+0 }' "$CFG")
ROUT=$(awk '/^rules:[ ]*$/ { inr=1; next } inr && /^[^ ]/ { inr=0 } inr && /^[ ]+- / { n++ } END { print n+0 }' "$TMP")
[ "$ROUT" -eq $((RIN + 1)) ] || die "rule count mismatch ($RIN -> $ROUT)"

# 保持原权限位（ShellCrash 生成的配置通常是 644）
PERM=$(ls -l "$CFG" | awk '{ print substr($1, 2, 9) }')
chmod "$PERM" "$TMP" 2>/dev/null || true

# ---------- 9. 原子替换 ----------
mv -f "$TMP" "$CFG" || die "failed to replace $CFG"
echo "rules-mid: inserted '$RULE_LINE' at line $EDGE_LINE (after Telegram rule at line $LAST_TG)"
exit 0
