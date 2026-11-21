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
LOGTMP=$LOG.tmp.$$
mkdir -p "$LOGDIR"

# 单实例锁：本脚本是唯一会触发 hotupdate 的地方。两次并发 = 两次 PUT /configs，
# 内存峰值翻倍（docs/PITFALLS.md §46：单次峰值已是常驻的两倍，239MB 上必被 OOM）。
# mkdir 原子加锁。锁里写持有者 pid：超时不等于持有者已死，接管前 kill -0 判活；
# pid 文件没写成（上次在写下 pid 前崩溃）算陈旧（PITFALLS §49）。
LOCKDIR=$LOGDIR/.auto-update.lock
LOCKPID="$LOCKDIR/pid"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
	_ts=$(cat "$LOCKDIR/ts" 2>/dev/null || echo 0)
	case "$_ts" in ''|*[!0-9]*) _ts=0 ;; esac
	if [ $(($(date +%s) - _ts)) -le 3600 ]; then
		echo "$(date) 已有实例在跑，跳过本次" >> "$LOG"
		exit 0
	fi
	HOLDER=$(cat "$LOCKPID" 2>/dev/null)
	if [ -n "$HOLDER" ] && kill -0 "$HOLDER" 2>/dev/null; then
		echo "$(date) 已有实例在跑（pid $HOLDER，超过窗口但未退出），跳过本次" >> "$LOG"
		exit 0
	fi
	rm -rf "$LOCKDIR" 2>/dev/null
	mkdir "$LOCKDIR" 2>/dev/null || { echo "$(date) 另一实例正在接管锁，跳过本次" >> "$LOG"; exit 0; }
fi
echo $$ > "$LOCKPID" 2>/dev/null
date +%s > "$LOCKDIR/ts"
# 只在自己仍是持有者时释放锁；临时日志仍无条件清理。
trap 'if [ "$(cat "$LOCKPID" 2>/dev/null)" = "$$" ]; then rm -rf "$LOCKDIR"; fi; rm -f "$LOGTMP"' EXIT INT TERM HUP

# 日志轮转: 超过 256KB 只保留尾部 200 行
if [ -f "$LOG" ]; then
	SZ=$(wc -c < "$LOG" 2>/dev/null || echo 0)
	# 临时名带 $$：固定名 $LOG.tmp 在两个实例同时截断时会互相覆盖。
	[ "$SZ" -gt 262144 ] && { tail -200 "$LOG" > "$LOGTMP" && mv -f "$LOGTMP" "$LOG"; }
fi

# 探活合成一次调用：原来循环里每轮跑两次 netstat|grep，10 轮最多 20 个子进程。
# 端口从配置动态读，不写死 7890；读不到时用默认值兜底。
_sc_cfg=$CRASHDIR/configs/ShellCrash.cfg
_mix_port=$(sed -n 's/^mix_port=//p' "$_sc_cfg" 2>/dev/null | head -1)
_redir_port=$(sed -n 's/^redir_port=//p' "$_sc_cfg" 2>/dev/null | head -1)
MIX_PORT=${_mix_port:-7890}
REDIR_PORT=${_redir_port:-7892}
core_up() {
	pidof CrashCore >/dev/null 2>&1 || return 1
	netstat -lnt 2>/dev/null | grep -qE ":($MIX_PORT|$REDIR_PORT)[[:space:]]"
}

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
			# 热更新走 PUT /configs 整份 reload，内存峰值约等于常驻的两倍：
			# 239MB 的 AX3000T 上实测被 OOM killer 杀掉（dmesg: Killed process
			# (CrashCore) anon-rss 66MB），guardian 每 5 分钟才拉起，期间全网断代理。
			# 这里探活 10s，不活就立刻 start.sh start，不等 guardian。
			i=0
			while [ "$i" -lt 10 ]; do
				core_up && break
				sleep 1; i=$((i+1))
			done
			if ! core_up; then
				echo "  热更新后核心未存活（疑似 OOM），立即重新拉起"
				sh "$CRASHDIR/start.sh" start
			fi
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
