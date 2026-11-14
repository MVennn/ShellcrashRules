#!/bin/sh
# 结构化健康快照（只读）—— 路由器侧唯一输出，给控制台 / 运维工具消费
#
# 为什么要有这个：ai-api-check.sh 是「逐段断言 + 少量自动修复」，输出给人看、
# 退出码只有 0/1；控制台和运维工具需要的是**机器可读**的一份状态。这里只读不写，
# 不重启核心、不改任何配置、不碰 nft（只 list）。它把同一批事实一次采齐，
# 消费方不要再各自 curl / nft list / 读 /proc 重新实现一遍。
#
# 用法:
#   sh health-snapshot.sh                      # JSON 打到 stdout
#   sh health-snapshot.sh --out /tmp/h.json    # 原子写文件（tmp + mv，不留半截）
#   sh health-snapshot.sh --no-api             # 跳过 mihomo 控制 API 探测
#   sh health-snapshot.sh --help
#
# 退出码: 0 健康 / 1 有告警 / 2 严重（核心没跑、运行配置缺失、或内存低于 MEM_CRIT_KB）
# 契约: "schema": "shellcrash.health/1"；字段只增不改，新增字段消费方必须容忍缺省。
#       reasons 里只放 ASCII 枚举码（mem_critical / mem_low / tmp_high / core_down /
#       nft_missing:<表名> / api_unreachable / no_curl / no_runtime_config /
#       last_failure_present / no_secret），
#       不放句子 —— 句子随语言和措辞漂移，枚举码不会。
#
# 不输出主机名、内网 IP、节点名、secret：快照会被贴进 issue 和聊天窗口，
# 少一个字段就少一处泄露面。凭据只从 MIHOMO_SECRET 或设备 cfg 读，绝不回显。

CRASHDIR=${CRASHDIR:-/etc/ShellCrash}
MIHOMO_API=${MIHOMO_API:-http://127.0.0.1:9999}
MEM_WARN_KB=${MEM_WARN_KB:-40960}
MEM_CRIT_KB=${MEM_CRIT_KB:-20480}
TMP_WARN_PCT=${TMP_WARN_PCT:-80}

DO_API=1
OUT=''
while [ $# -gt 0 ]; do
	case "$1" in
		--no-api) DO_API=0 ;;
		--out)
			OUT=${2:-}
			# `--out --no-api` 不能把下一个选项当成文件名
			case "$OUT" in
				''|-*) echo "用法: $0 --out <文件>" >&2; exit 2 ;;
			esac
			shift ;;
		--help|-h)
			# 不写死行号：头部注释改一行就失效的用法说明等于没有
			awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
			exit 0 ;;
		*)
			echo "未知参数: $1（--help 看用法）" >&2
			exit 2 ;;
	esac
	shift
done

TMPOUT=''
if [ -n "$OUT" ]; then
	TMPOUT="$OUT.tmp.$$"
	trap 'rm -f "$TMPOUT"' EXIT INT TERM HUP
fi

# 数值兜底：grep -c 无命中会退 1 并打印 0，df/awk 也可能给空串
num() {
	case "$1" in
		''|*[!0-9]*) echo 0 ;;
		*) echo "$1" ;;
	esac
}

# JSON 字符串转义：值里可能带引号/反斜杠（版本号、错误串），直接拼会产出坏 JSON
jstr() {
	printf '%s' "$1" | tr -d '\r\n\t' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

boolz() {
	[ "$1" = "1" ] && printf true || printf false
}

REASONS=''
CRIT=0
WARN=0
add_reason() {
	REASONS="${REASONS:+$REASONS,}\"$1\""
	case "$1" in
		core_down|no_runtime_config|mem_critical) CRIT=1 ;;
		*) WARN=1 ;;
	esac
}

NOW=$(date +%s 2>/dev/null)
NOW=$(num "$NOW")
# RFC3339 要带冒号的偏移（+08:00）—— 不少消费方（浏览器 Date、Python
# fromisoformat）不接受 +0800 这种紧凑写法，宁可多一次 fork 也要给对格式。
TS=$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')
[ -z "$TS" ] && TS='1970-01-01T00:00:00+00:00'

UPTIME_S=0
if [ -r /proc/uptime ]; then
	UPTIME_S=$(num "$(cut -d. -f1 /proc/uptime 2>/dev/null)")
fi

# 老内核没有 MemAvailable（4.20 之前），退回 MemFree+Buffers+Cached；
# 两者都拿不到就保持 0 并跳过判定 —— 宁可少一个数，也不要报一个假的 100%。
MEM_TOTAL_KB=0
MEM_AVAIL_KB=0
if [ -r /proc/meminfo ]; then
	set -- $(awk '
		/^MemTotal:/     { t = $2 }
		/^MemAvailable:/ { a = $2 }
		/^MemFree:/      { f = $2 }
		/^Buffers:/      { b = $2 }
		/^Cached:/       { c = $2 }
		END {
			if (a == "") a = f + b + c
			if (a == "") a = 0
			print t + 0, a + 0
		}' /proc/meminfo 2>/dev/null)
	if [ $# -eq 2 ]; then
		MEM_TOTAL_KB=$(num "$1")
		MEM_AVAIL_KB=$(num "$2")
	fi
fi
MEM_USED_PCT=0
if [ "$MEM_TOTAL_KB" -gt 0 ] && [ "$MEM_AVAIL_KB" -gt 0 ]; then
	MEM_USED_PCT=$(( (MEM_TOTAL_KB - MEM_AVAIL_KB) * 100 / MEM_TOTAL_KB ))
fi
# 危急与偏低给两个码：都叫 mem_low 时 reasons 无法解释 status 为什么是 critical
if [ "$MEM_AVAIL_KB" -gt 0 ] && [ "$MEM_AVAIL_KB" -lt "$MEM_CRIT_KB" ]; then
	add_reason mem_critical
elif [ "$MEM_AVAIL_KB" -gt 0 ] && [ "$MEM_AVAIL_KB" -lt "$MEM_WARN_KB" ]; then
	add_reason mem_low
fi

# /tmp 是 tmpfs（116MB 量级），写满会 OOM 杀核心再触发整机重启 —— 必须盯住
TMP_TOTAL_KB=0
TMP_USED_KB=0
TMP_AVAIL_KB=0
TMP_USED_PCT=0
if command -v df >/dev/null 2>&1; then
	TMPDF=$(df -k /tmp 2>/dev/null)
	# 按挂载点列精确取 /tmp 那一行：同一设备挂了多份时 NR==2 会取到别的挂载点
	set -- $(printf '%s\n' "$TMPDF" | awk '$NF=="/tmp"{gsub("%","",$5); print $2, $3, $4, $5; exit}')
	[ $# -eq 4 ] || set -- $(printf '%s\n' "$TMPDF" | awk 'NR==2{gsub("%","",$5); print $2, $3, $4, $5; exit}')
	if [ $# -eq 4 ]; then
		TMP_TOTAL_KB=$(num "$1")
		TMP_USED_KB=$(num "$2")
		TMP_AVAIL_KB=$(num "$3")
		TMP_USED_PCT=$(num "$4")
	fi
fi
if [ "$TMP_USED_PCT" -ge "$TMP_WARN_PCT" ]; then
	add_reason tmp_high
fi

# 核心进程：pidof 拿 pid，VmRSS 拿真实驻留（不 ps 全表，省一次 fork）
CORE_RUN=0
CORE_PID=0
CORE_RSS_KB=0
if command -v pidof >/dev/null 2>&1; then
	CORE_PID=$(num "$(pidof CrashCore 2>/dev/null | awk '{print $1; exit}')")
fi
if [ "$CORE_PID" -gt 0 ] && [ -r "/proc/$CORE_PID/status" ]; then
	CORE_RUN=1
	CORE_RSS_KB=$(num "$(awk '/^VmRSS:/{print $2; exit}' "/proc/$CORE_PID/status" 2>/dev/null)")
fi
[ "$CORE_RUN" -eq 0 ] && add_reason core_down

# 运行配置：start.sh 生成到 /tmp/ShellCrash/config.yaml，缺了就是没代理
RUN_CFG=/tmp/ShellCrash/config.yaml
RUN_CFG_OK=0
[ -r "$RUN_CFG" ] && RUN_CFG_OK=1
[ "$RUN_CFG_OK" -eq 0 ] && add_reason no_runtime_config

# 规则条数：只在已有文件上数，不读全文进内存（grep -c 逐行流式）
RUN_RULES=$(num "$(grep -c '^  - ' "$RUN_CFG" 2>/dev/null)")
YAML_RULES=$(num "$(grep -c '^  - ' "$CRASHDIR/yamls/rules.yaml" 2>/dev/null)")

# 三张独立表：ShellCrash 每次重启重写 inet shellcrash 整表，所以这三张必须各自在
NFT=$(command -v nft 2>/dev/null)
[ -z "$NFT" ] && NFT=/usr/sbin/nft
NFT_OK=0
Q_NFT=0
G_NFT=0
C_NFT=0
if [ -x "$NFT" ]; then
	NFT_OK=1
	# 一次 list tables 拿全部表名，再在 shell 里逐行精确比对：原来每张表各起一次
	# nft（3 次 fork + 3 次 netlink dump），控制台轮询快照时是纯浪费。
	NFT_TABLES=$("$NFT" list tables 2>/dev/null)
	_oldifs=$IFS
	IFS='
'
	for _t in $NFT_TABLES; do
		case "$_t" in
			"table inet quicguard") Q_NFT=1 ;;
			"table inet googleroute") G_NFT=1 ;;
			"table inet googlecn") C_NFT=1 ;;
		esac
	done
	IFS=$_oldifs
fi
[ "$Q_NFT" -eq 0 ] && add_reason 'nft_missing:quicguard'
[ "$G_NFT" -eq 0 ] && add_reason 'nft_missing:googleroute'
[ "$C_NFT" -eq 0 ] && add_reason 'nft_missing:googlecn'

# 控制 API：-f 让 4xx/5xx 变成非零退出（原来只看 curl 退出码会把 401 当成功）
API_OK=0
API_VER=''
# 没有 curl 时 api.reachable 恒为 false，不给码就分不清「连不上」和「没工具」
if [ "$DO_API" -eq 1 ] && ! command -v curl >/dev/null 2>&1; then
	add_reason no_curl
fi
if [ "$DO_API" -eq 1 ] && command -v curl >/dev/null 2>&1; then
	SECRET=${MIHOMO_SECRET:-}
	if [ -z "$SECRET" ] && [ -r "$CRASHDIR/configs/ShellCrash.cfg" ]; then
		SECRET=$(grep -m1 '^secret=' "$CRASHDIR/configs/ShellCrash.cfg" 2>/dev/null \
			| cut -d= -f2- | tr -d "'\"")
	fi
	if [ -n "$SECRET" ]; then
		API_VER=$(curl -sf --connect-timeout 3 -m 5 \
			-H "Authorization: Bearer $SECRET" "$MIHOMO_API/version" 2>/dev/null \
			| sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
		[ -n "$API_VER" ] && API_OK=1
	else
		add_reason no_secret
	fi
	unset SECRET
	[ "$API_OK" -eq 0 ] && add_reason api_unreachable
fi

# 自检留痕与锁：LAST_FAILURE 在 = 上一次自检没过；锁在 = 正在跑或上次崩了没清
FAIL_PRESENT=0
[ -f "$CRASHDIR/logs/LAST_FAILURE" ] && FAIL_PRESENT=1
[ "$FAIL_PRESENT" -eq 1 ] && add_reason last_failure_present

LOG_AGE_S=-1
if [ -r "$CRASHDIR/logs/ai-check.log" ]; then
	MT=$(date -r "$CRASHDIR/logs/ai-check.log" +%s 2>/dev/null)
	case "$MT" in
		''|*[!0-9]*) LOG_AGE_S=-1 ;;
		*) LOG_AGE_S=$(( NOW - MT )) ;;
	esac
fi

AI_LOCK=0
AU_LOCK=0
[ -d "$CRASHDIR/logs/.ai-check.lock" ] && AI_LOCK=1
[ -d "$CRASHDIR/logs/.auto-update.lock" ] && AU_LOCK=1

# cron 生命线：订阅更新会重置 cron，两条生命线丢了就没人补核心
WD_CRON=0
TASK_CRON=0
if command -v crontab >/dev/null 2>&1; then
	CRON_DUMP=$(crontab -l 2>/dev/null)
	printf '%s\n' "$CRON_DUMP" | grep -qF 'start_legacy_wd.sh' && WD_CRON=1
	printf '%s\n' "$CRON_DUMP" | grep -qF 'task/task.sh' && TASK_CRON=1
fi

STATUS=ok
[ "$WARN" -eq 1 ] && STATUS=warn
[ "$CRIT" -eq 1 ] && STATUS=critical

emit() {
	cat <<EOF
{
  "schema": "shellcrash.health/1",
  "ts": "$TS",
  "epoch": $NOW,
  "uptime_s": $UPTIME_S,
  "mem": { "total_kb": $MEM_TOTAL_KB, "avail_kb": $MEM_AVAIL_KB, "used_pct": $MEM_USED_PCT },
  "tmp": { "total_kb": $TMP_TOTAL_KB, "used_kb": $TMP_USED_KB, "avail_kb": $TMP_AVAIL_KB, "used_pct": $TMP_USED_PCT },
  "core": { "running": $(boolz "$CORE_RUN"), "pid": $CORE_PID, "rss_kb": $CORE_RSS_KB },
  "api": { "enabled": $(boolz "$DO_API"), "reachable": $(boolz "$API_OK"), "version": "$(jstr "$API_VER")" },
  "nft": { "tool": $(boolz "$NFT_OK"), "quicguard": $(boolz "$Q_NFT"), "googleroute": $(boolz "$G_NFT"), "googlecn": $(boolz "$C_NFT") },
  "rules": { "runtime": $RUN_RULES, "yamls": $YAML_RULES, "runtime_config": $(boolz "$RUN_CFG_OK") },
  "checks": { "last_failure": $(boolz "$FAIL_PRESENT"), "ai_check_log_age_s": $LOG_AGE_S, "ai_check_lock": $(boolz "$AI_LOCK"), "auto_update_lock": $(boolz "$AU_LOCK") },
  "cron": { "lifeline_wd": $(boolz "$WD_CRON"), "lifeline_task": $(boolz "$TASK_CRON") },
  "status": "$STATUS",
  "reasons": [ $REASONS ]
}
EOF
}

if [ -n "$OUT" ]; then
	emit > "$TMPOUT" && mv -f "$TMPOUT" "$OUT" || exit 2
else
	emit
fi

[ "$CRIT" -eq 1 ] && exit 2
[ "$WARN" -eq 1 ] && exit 1
exit 0
