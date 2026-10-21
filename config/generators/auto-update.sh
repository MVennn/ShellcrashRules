#!/bin/sh
# ShellCrash weekly maintenance:
#   1) refresh AI routing rules from MetaCubeX
#   2) hot-update subscription (download + apply, no restart)
# 退出码: 0 全部成功 / 1 任一步失败（cron 与巡检脚本可见）
# 日志: /etc/ShellCrash/logs/auto-update.log（落 overlay，重启不丢；历史已修好
#       /tmp 会被清空导致失败无人知晓的问题）
CRASHDIR=/etc/ShellCrash
LOGDIR=$CRASHDIR/logs
LOG=$LOGDIR/auto-update.log
mkdir -p "$LOGDIR"

# 日志轮转: 超过 256KB 只保留尾部 200 行
if [ -f "$LOG" ]; then
	SZ=$(wc -c < "$LOG" 2>/dev/null || echo 0)
	[ "$SZ" -gt 262144 ] && { tail -200 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"; }
fi

rc=0
SKIP=0
{
	echo "=== $(date) start ==="
	if sh "$CRASHDIR/ai-rules-update.sh"; then
		echo "ai-rules-update: OK"
	else
		echo "ai-rules-update: FAILED —— 跳过 hotupdate，避免把半成品规则推到线上"
		rc=1
		SKIP=1
	fi
	if [ "$SKIP" -eq 0 ]; then
		if "$CRASHDIR/task/task.sh" hotupdate; then
			echo "hotupdate: OK"
		else
			echo "hotupdate: FAILED（订阅转换服务 api.v1.mk 间歇性失败，属免费公共服务限流）"
			echo "  改用本地 yaml 重建配置兜底：start.sh start 会用 yamls/ 重新生成并热加载"
			if sh "$CRASHDIR/start.sh" start; then
				echo "  本地重建配置: OK（规则已生效，只是订阅内容未更新）"
			else
				echo "  本地重建配置: FAILED"
				rc=1
			fi
		fi
	fi
	echo "=== $(date) done rc=$rc ==="
} >> "$LOG" 2>&1

# 失败留痕，便于巡检
if [ "$rc" -ne 0 ]; then
	echo "$(date) auto-update FAILED" > "$LOGDIR/LAST_FAILURE"
else
	rm -f "$LOGDIR/LAST_FAILURE"
fi

exit $rc
