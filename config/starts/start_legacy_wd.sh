
[ -z "$CRASHDIR" ] && CRASHDIR=$(cd "$(dirname "$0")"/.. && pwd)
PIDFILE="/tmp/ShellCrash/$1.pid"
LOCKDIR="/tmp/ShellCrash/start_$1.lock"

[ -f "$CRASHDIR"/.start_error ] && [ ! -f /tmp/ShellCrash/crash_start_time ] && exit 1 #当启动失败后禁止开机自启动
# /tmp/ShellCrash 在 tmpfs 上, 重启后整个目录不存在 —— 必须先建父目录。
# 否则下面 mkdir 锁目录永远失败, 看门狗每分钟 exit 1, 代理再也拉不起来
# (2026-10-20 09:36 重启实测: 开机自启失败后看门狗无法兜底, 代理离线 6 分钟)
mkdir -p /tmp/ShellCrash 2>/dev/null
mkdir "$LOCKDIR" 2>/dev/null || {
	# 陈旧锁自愈：上次运行被中断时锁会残留，导致看门狗永久失效
	LAGE=$(( $(date +%s) - $(date -r "$LOCKDIR" +%s 2>/dev/null || echo 0) ))
	[ "$LAGE" -gt 300 ] && rm -fr "$LOCKDIR" 2>/dev/null
	mkdir "$LOCKDIR" 2>/dev/null || exit 1
}

# 进程已经在跑就直接退出：pid 文件在 /tmp（tmpfs），重启后会丢，
# 旧逻辑会误判"没有进程"从而 stop 掉一个健康运行的代理再重启它
if [ "$1" = "shellcrash" ] && [ -n "$(pidof CrashCore 2>/dev/null)" ]; then
	rm -fr "$LOCKDIR" 2>/dev/null
	exit 0
fi

if [ -f "$PIDFILE" ]; then
    PID="$(cat "$PIDFILE")"
    if [ -n "$PID" ] && [ "$PID" -eq "$PID" ] 2>/dev/null; then
        if kill -0 "$PID" 2>/dev/null || [ -d "/proc/$PID" ]; then
            rm -fr "$LOCKDIR" 2>/dev/null
            exit 0
        fi
    else
        rm -f "$PIDFILE"
    fi
fi

#如果没有进程则拉起
if [ "$1" = "shellcrash" ]; then
    # ---- U13 memory gate (helper: /etc/ShellCrash/memgate.sh) ----
    # Break the self-exciting loop:
    #   OOM kills CrashCore -> this cron watchdog pulls it back up
    #     -> start.sh start -> check_core.sh -> core_webget / core_unzip
    #       -> ~57 MB core payload decompressed into /tmp (RAM tmpfs)
    #         -> OOM again -> 31 s without a watchdog kick -> router hard-reset
    # When MemAvailable (/proc/meminfo) is below MEM_GATE_KB
    # (/etc/ShellCrash/configs/memgate.conf, default 32768 kB) do NOT launch:
    # log one WARNING and exit 0 so cron stays quiet.  The next cron tick
    # (1 minute later) retries.  With enough memory the behaviour below is
    # exactly the same as before the gate was added.
    if [ -f "$CRASHDIR/memgate.sh" ]; then
        "$CRASHDIR/memgate.sh" check
        _memgate_rc=$?
        if [ "$_memgate_rc" -eq 1 ]; then
            rm -fr "$LOCKDIR" 2>/dev/null
            exit 0
        fi
    else
        # memgate.sh missing -> fail open (keep the pre-U13 behaviour) and
        # warn only once per boot (/tmp is a tmpfs, so the stamp is volatile).
        if [ ! -f /tmp/ShellCrash/.memgate_missing_warned ]; then
            logger -t ShellCrashMemGate "memgate.sh not found under $CRASHDIR; starting CrashCore WITHOUT the memory gate" 2>/dev/null
            touch /tmp/ShellCrash/.memgate_missing_warned 2>/dev/null
        fi
    fi
    "$CRASHDIR"/start.sh start
else
    [ -f "$CRASHDIR/starts/start_legacy.sh" ] && . "$CRASHDIR/starts/start_legacy.sh"
    killall bot_tg.sh 2>/dev/null
    start_legacy "$CRASHDIR/menus/bot_tg.sh" "$1"
fi

rm -fr "$LOCKDIR" 2>/dev/null
