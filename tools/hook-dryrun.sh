#!/bin/sh
# hook-dryrun.sh - 在配置副本上试跑生成期钩子，打印 diff；线上配置一个字节都不碰。
#
# 为什么需要它：config/hooks/*.sh 是在 clash_modify.sh 里对 config.yaml 就地改写
# （sed -i / awk > tmp + mv）的，改坏了要等 mihomo 校验失败才发现，而校验失败后
# ShellCrash 会静默回退基础配置 —— 表现为"自定义分流全没了"，不是报错。
# 拿一份设备上存下来的 config.yaml 在 PC 上跑一遍钩子，diff 就是行为等价性的证据。
#
# 用法:
#   sh tools/hook-dryrun.sh SAVED_CONFIG [HOOK ...]
#
#   SAVED_CONFIG  设备上取回的 /tmp/ShellCrash/config.yaml（含节点信息，别进 git）
#   HOOK          可选。不传则按 clash_modify.sh 的顺序跑四个钩子；
#                 只测一个就显式传路径（可以是别的版本，用来做新旧对照）
#
# 退出码: 0 钩子没改动配置 / 1 有差异（diff 已打印）/ 2 用法或输入错误

set -u

case "${1:-}" in
-h | --help)
	sed -n '9,16p' "$0" | sed 's/^# \{0,1\}//'
	exit 0
	;;
esac

CFG=${1:-}
if [ -z "$CFG" ] || [ ! -f "$CFG" ]; then
	echo "用法: sh tools/hook-dryrun.sh SAVED_CONFIG [HOOK ...]" >&2
	echo "  SAVED_CONFIG 不存在或没给: ${CFG:-<空>}" >&2
	exit 2
fi
shift

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$SELF_DIR/../config/hooks/reorder-groups.sh" ]; then
	HDIR=$SELF_DIR/../config/hooks
else
	HDIR=${CRASHDIR:-/etc/ShellCrash}
fi

if [ "$#" -gt 0 ]; then
	HOOKS=$*
else
	HOOKS="$HDIR/reorder-groups.sh $HDIR/rules-porn.sh $HDIR/rules-mid.sh $HDIR/rules-cnip.sh"
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hook-dryrun.XXXXXX") || { echo "mktemp 失败" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM HUP

cp "$CFG" "$WORK/before.yaml" || exit 2
cp "$CFG" "$WORK/after.yaml" || exit 2

RAN=0
for h in $HOOKS; do
	[ -f "$h" ] || { echo "跳过（不存在）: $h" >&2; continue; }
	sh "$h" "$WORK/after.yaml"
	rc=$?
	RAN=$((RAN + 1))
	[ "$rc" -eq 0 ] || echo "钩子退出码 $rc: $h" >&2
done

if [ "$RAN" -eq 0 ]; then
	echo "没有可跑的钩子（HDIR=$HDIR）" >&2
	exit 2
fi

if diff -u "$WORK/before.yaml" "$WORK/after.yaml" > "$WORK/diff.txt" 2>&1; then
	echo "OK: $RAN 个钩子跑完，配置无变化"
	exit 0
fi
echo "DIFF: $RAN 个钩子跑完，配置有变化（+ 为钩子产物，- 为原始）"
cat "$WORK/diff.txt"
exit 1
