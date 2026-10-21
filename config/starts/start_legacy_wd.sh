
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
	LAGE=$(( $(date +%s) - $(stat -c %Y "$LOCKDIR" 2>/dev/null || echo 0) ))
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
    "$CRASHDIR"/start.sh start
else
    [ -f "$CRASHDIR/starts/start_legacy.sh" ] && . "$CRASHDIR/starts/start_legacy.sh"
    killall bot_tg.sh 2>/dev/null
    start_legacy "$CRASHDIR/menus/bot_tg.sh" "$1"
fi

rm -fr "$LOCKDIR" 2>/dev/null
