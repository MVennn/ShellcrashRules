#!/bin/sh
# rules-dedup.sh —— 删除同目标冗余、完全重复与永不命中的 PROCESS-NAME
#
# 用法: rules-dedup.sh /path/to/config.yaml
#       rules-dedup.sh --check /path/to/config.yaml   # 只统计，不改文件
#
# ⚠️ 离线工具，不要部署到路由器，也不要挂到 starts/clash_modify.sh！
#    2026-10-22 实测：在 4,154 条规则的运行配置上跑 --check，O(N²) 两两匹配
#    把路由器 CPU/内存拖垮，导致整网断流（看门狗/OOM 重启）。
#    只能在 PC 上对 scp 下来的 config.yaml 副本跑；结果也不要回灌到设备。
#
# 删除规则（行为不变）：
#   1) 前面已有同目标规则命中的域名规则（含完全重复）；
#   2) find-process-mode 显式为 off 时的 PROCESS-NAME 规则。
# 保留：
#   - 不同目标遮蔽的规则（模板意图/审计痕迹）；
#   - RULE-SET / IP / MATCH；
#   - 所有 CN 直连规则（不拿运行态 cn.mrs 当依据，mrs 可能滞后）。
#
# 特性：幂等；先写同目录临时文件并校验，通过后 mv 原子替换；--check 只读。

set -u

MODE=apply
CFG=
case "${1:-}" in
	--check) MODE=check; CFG="${2:-}" ;;
	*) CFG="${1:-}" ;;
esac
die(){ echo "rules-dedup: $*" >&2; exit 1; }

[ -n "$CFG" ] || die "usage: $0 [--check] /path/to/config.yaml"
[ -f "$CFG" ] || die "no such file: $CFG"
[ -r "$CFG" ] || die "not readable: $CFG"
DIR=$(dirname "$CFG")
if [ "$MODE" = apply ]; then
	[ -w "$DIR" ] || die "directory not writable: $DIR"
fi

# 只有显式 off 才删 PROCESS-NAME；缺省/其他模式一律保留
PMODE=$(awk '/^find-process-mode:[[:space:]]*/{
	v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'\'']/,"",v); print tolower(v); exit
}' "$CFG")
DROP_PROC=0
[ "$PMODE" = "off" ] && DROP_PROC=1

TMP="$CFG.rules-dedup.$$"
OUT="$TMP"
[ "$MODE" = check ] && OUT=/dev/null
trap 'rm -f "$TMP"' EXIT HUP INT TERM

# 两遍读同一个文件：第一遍收集 rules: 段的规则，第二遍按行号输出。
# 删除判定只依赖显式域名规则（DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD），
# 不把 RULE-SET,cn 当依据 —— 运行态 cn.mrs 可能滞后于文本列表。
awk -v drop_proc="$DROP_PROC" -v mode="$MODE" '
BEGIN {
	# 保护清单：广告 carve-out / Google 出口 / 模型 API / 高带宽直连。
	# 这些规则即使被更早的同目标规则覆盖，也不删 —— 它们是审计与顺序的锚点。
	n=split("DOMAIN-SUFFIX,doubleclick.net,🛑 广告拦截|DOMAIN-SUFFIX,googlesyndication.com,🛑 广告拦截|DOMAIN-SUFFIX,googleadservices.com,🛑 广告拦截|DOMAIN-SUFFIX,google-analytics.com,🛑 广告拦截|DOMAIN-SUFFIX,googleadsserving.cn,🛑 广告拦截|DOMAIN-SUFFIX,ads.google.com,🛑 广告拦截|DOMAIN-SUFFIX,adservice.google.com,🛑 广告拦截|DOMAIN-SUFFIX,pagead.google.com,🛑 广告拦截|DOMAIN-SUFFIX,pagead.l.google.com,🛑 广告拦截|DOMAIN-SUFFIX,pagead-tpc.l.google.com,🛑 广告拦截|DOMAIN-SUFFIX,mobileads.google.com,🛑 广告拦截|DOMAIN-SUFFIX,afd.l.google.com,🛑 广告拦截|DOMAIN-SUFFIX,badad.googleplex.com,🛑 广告拦截|DOMAIN-SUFFIX,csi.gstatic.com,🛑 广告拦截|DOMAIN-SUFFIX,collector.githubapp.com,🛑 广告拦截|DOMAIN-SUFFIX,app-measurement.com,🛑 广告拦截|DOMAIN-SUFFIX,google.com,🤖 干净出口|DOMAIN-KEYWORD,google,🤖 干净出口|DOMAIN-SUFFIX,opencode.ai,🤖 AI接口|DOMAIN,dl.google.com,🎯 全球直连|DOMAIN-SUFFIX,gvt1.com,🎯 全球直连|DOMAIN-SUFFIX,gvt1-cn.com,🎯 全球直连|DOMAIN-SUFFIX,jetbrains.com,🎯 全球直连|DOMAIN-SUFFIX,z.ai,🎯 全球直连|DOMAIN-SUFFIX,bigmodel.cn,🎯 全球直连", p, "|")
	for (i=1;i<=n;i++) prot[p[i]]=1
}
function is_suffix(d,s){
	if (d==s) return 1
	if (length(d)<=length(s)) return 0
	return substr(d, length(d)-length(s)) == "." s
}
function matches(t,v,d){
	if (t=="DOMAIN") return d==v
	if (t=="DOMAIN-SUFFIX") return is_suffix(d,v)
	if (t=="DOMAIN-KEYWORD") return index(d,v)>0
	return 0
}
function compute(   i,j) {
	for (i=1;i<=cnt;i++) {
		if (isproc[i] && drop_proc) { skip[ln[i]]=1; removed_proc++; continue }
		if (!isdom[i] || type[i]=="DOMAIN-KEYWORD") continue
		if ((type[i] "," val[i] "," target[i]) in prot) continue
		for (j=1;j<i;j++) {
			if (!isdom[j]) continue
			if (matches(type[j], val[j], val[i])) {
				if (target[j]==target[i]) { skip[ln[i]]=1; removed_same++ }
				break
			}
		}
	}
	removed=removed_same+removed_proc
}
FNR==NR {
	if ($0 ~ /^rules:[ ]*$/) { inr=1; next }
	if (inr && $0 !~ /^[ ]/) inr=0
	if (!inr) next
	if ($0 !~ /^[ \t]+- [A-Z]/) next
	line=$0
	sub(/^[ \t]+- /,"",line)
	sub(/[ \t]+#.*$/,"",line)
	sub(/[ \t]+$/,"",line)
	n=split(line,a,",")
	if (n<2) next
	t=a[1]; v=a[2]; tg=(n>=3?a[3]:"")
	gsub(/^[ \t]+|[ \t]+$/,"",t)
	gsub(/^[ \t]+|[ \t]+$/,"",v)
	gsub(/^[ \t]+|[ \t]+$/,"",tg)
	cnt++
	type[cnt]=t; val[cnt]=v; target[cnt]=tg; ln[cnt]=FNR
	isdom[cnt]=(t=="DOMAIN"||t=="DOMAIN-SUFFIX"||t=="DOMAIN-KEYWORD")
	isproc[cnt]=(t=="PROCESS-NAME")
	next
}
FNR==1 && NR!=1 { compute() }
{
	if (FNR in skip) next
	print
}
END {
	if (mode=="check")
		printf "rules-dedup: would remove %d rule(s) (same-target %d, process-name %d)\n", removed, removed_same, removed_proc > "/dev/stderr"
	else
		printf "rules-dedup: removed %d rule(s) (same-target %d, process-name %d)\n", removed, removed_same, removed_proc > "/dev/stderr"
	exit (mode=="check" && removed>0) ? 1 : 0
}
' "$CFG" "$CFG" > "$OUT" || {
	rc=$?
	if [ "$MODE" = check ] && [ "$rc" = 1 ]; then
		rm -f "$TMP"
		exit 1
	fi
	die "awk failed (rc=$rc)"
}

if [ "$MODE" = check ]; then
	rm -f "$TMP"
	exit 0
fi

# ---------- 校验 ----------
[ -s "$TMP" ] || die "output is empty"
NIN=$(awk 'END { print NR }' "$CFG")
NOUT=$(awk 'END { print NR }' "$TMP")
[ "$NOUT" -le "$NIN" ] || die "line count grew ($NIN -> $NOUT)"
grep -q '^rules:[ ]*$' "$TMP" || die "rules: section missing"
RIN=$(awk '/^rules:[ ]*$/{f=1;next} f&&/^[^ ]/{f=0} f&&/^[ ]+- /{n++} END{print n+0}' "$CFG")
ROUT=$(awk '/^rules:[ ]*$/{f=1;next} f&&/^[^ ]/{f=0} f&&/^[ ]+- /{n++} END{print n+0}' "$TMP")
[ "$ROUT" -le "$RIN" ] || die "rule count grew ($RIN -> $ROUT)"

# 关键规则不得被误删（广告 carve-out / Google 出口 / CN 中间层）
for r in "DOMAIN-SUFFIX,doubleclick.net,🛑 广告拦截" \
         "DOMAIN-SUFFIX,googlesyndication.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,google-analytics.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,csi.gstatic.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,collector.githubapp.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,app-measurement.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,google.com,🤖 干净出口" \
         "DOMAIN-KEYWORD,google,🤖 干净出口" \
         "DOMAIN-SUFFIX,opencode.ai,🤖 AI接口"; do
	if grep -qF -- "- $r" "$CFG" 2>/dev/null && ! grep -qF -- "- $r" "$TMP" 2>/dev/null; then
		die "critical rule removed: $r"
	fi
done
if grep -q 'RULE-SET,cn,🎯 全球直连' "$CFG" && ! grep -q 'RULE-SET,cn,🎯 全球直连' "$TMP"; then
	die "RULE-SET,cn removed"
fi

# 保留原文件权限：从 `ls -l` 截出的符号串（rw-r--r--）GNU chmod 不接受，
# 失败被吞后产物权限会落到 umask 默认值。先 cp -p 拿到原权限再写内容。
cp -p "$CFG" "$TMP.perm" 2>/dev/null || cp "$CFG" "$TMP.perm"
cat "$TMP" > "$TMP.perm" && mv -f "$TMP.perm" "$CFG" || die "failed to replace $CFG"
rm -f "$TMP"
echo "rules-dedup: rules $RIN -> $ROUT"
exit 0
