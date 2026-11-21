#!/bin/sh
# 每日 AI 链路自检（自动版）
# 目的：此前 ai-api-check.sh 只能手动跑，失败无人知晓；这里让它每天自动跑并留痕
# 产物: /etc/ShellCrash/logs/ai-check.log（落 overlay，保留最近 14 份）
#       失败时写 /etc/ShellCrash/logs/LAST_FAILURE
# 2026-10-26: 修正日志轮转 —— 原写法从 .1 起逐个 mv，移动后又命中下一个序号，
#             结果把单个文件一路推到 .21，实际只保留 2 份。改为从 .14 倒序后移。

CRASHDIR=/etc/ShellCrash
LOGDIR=$CRASHDIR/logs
LOG=$LOGDIR/ai-check.log
mkdir -p "$LOGDIR"

# 单实例锁：cron 每天一次，但手动跑、开机补跑、上一次没跑完都会叠在一起。
# 两个实例同时跑 = 同一份日志被两边追加，末尾轮转还会互相 mv 对方正在写的文件，
# 结果是 .1 里混着两次运行的半截输出，失败原因读不出来。
# mkdir 是原子操作，用它当锁。锁里写持有者 pid：超时不等于持有者已死，
# 接管前必须 kill -0 判活；pid 文件没写成（上次在写下 pid 前崩溃）算陈旧。
# 全量跑完约 2-3 分钟，2 小时窗口足够宽松（PITFALLS §49）。
LOCKDIR=$LOGDIR/.ai-check.lock
LOCKPID="$LOCKDIR/pid"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
	_ts=$(cat "$LOCKDIR/ts" 2>/dev/null || echo 0)
	case "$_ts" in ''|*[!0-9]*) _ts=0 ;; esac
	if [ $(($(date +%s) - _ts)) -le 7200 ]; then
		echo "$(date '+%F %T') 已有实例在跑，跳过本次" >> "$LOG"
		exit 0
	fi
	HOLDER=$(cat "$LOCKPID" 2>/dev/null)
	if [ -n "$HOLDER" ] && kill -0 "$HOLDER" 2>/dev/null; then
		echo "$(date '+%F %T') 已有实例在跑（pid $HOLDER，超过窗口但未退出），跳过本次" >> "$LOG"
		exit 0
	fi
	# 陈旧锁（持有者已退出或 pid 文件没写成）：接管一次，仍失败就放弃。
	rm -rf "$LOCKDIR" 2>/dev/null
	mkdir "$LOCKDIR" 2>/dev/null || { echo "$(date '+%F %T') 另一实例正在接管锁，跳过本次" >> "$LOG"; exit 0; }
fi
echo $$ > "$LOCKPID" 2>/dev/null
date +%s > "$LOCKDIR/ts"
# 只在自己仍是持有者时释放，避免删掉接管者的锁。
trap 'if [ "$(cat "$LOCKPID" 2>/dev/null)" = "$$" ]; then rm -rf "$LOCKDIR"; fi' EXIT INT TERM HUP

{
	echo "===== $(date '+%F %T') 每日 AI 自检 ====="
} >> "$LOG"

if sh "$CRASHDIR/ai-api-check.sh" >> "$LOG" 2>&1; then
	echo "结果: 全部通过" >> "$LOG"
	# 只有当失败原因不是 weekly auto-update 造成时才清掉标记
	[ -f "$LOGDIR/LAST_FAILURE" ] && grep -qF "auto-update" "$LOGDIR/LAST_FAILURE" 2>/dev/null || rm -f "$LOGDIR/LAST_FAILURE"
else
	echo "结果: 有失败项（见上）" >> "$LOG"
	echo "$(date '+%F %T') daily ai-check FAILED" > "$LOGDIR/LAST_FAILURE"
fi

# 日志轮转: 只保留最近 14 份（.1 最新，.14 最旧）
# 必须从旧到新倒序移动：先 14→15、13→14 … 1→2，最后当前日志 → .1。
# 正序移动会把刚移走的文件又当成下一个序号，单个文件一路推到 .21。
i=14
while [ $i -ge 1 ]; do
	OLD="$LOGDIR/ai-check.$i.log"
	[ -f "$OLD" ] && mv -f "$OLD" "$LOGDIR/ai-check.$((i+1)).log"
	i=$((i-1))
done
# 清掉旧轮转逻辑留下的 .15+ 文件
i=15
while [ $i -le 30 ]; do
	rm -f "$LOGDIR/ai-check.$i.log"
	i=$((i+1))
done
[ -f "$LOG" ] && mv -f "$LOG" "$LOGDIR/ai-check.1.log"

exit 0
