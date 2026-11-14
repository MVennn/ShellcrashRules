#!/bin/sh
# 从机场原始订阅补齐「订阅转换器丢掉的节点」到 yamls/proxies.yaml
#
# 背景：ShellCrash 通过订阅转换器（url.v1.mk，target=clash）拉订阅，转换器不认的
# 节点类型会被**静默丢掉**（2026-10-22 实测：hysteria2 整类消失，50 条 → 46 条）。
# 机场又按客户端 UA 给节点集（只有 clash.meta 才返回 hysteria2），两层叠加后，
# 唯一被判 cc=SG 的干净出口在路由器上完全不可见，Gemini 报「不支持此国家」。
#
# 做法：把原始订阅（UA clash.meta）与**转换后的配置**逐节点比对，只把「转换后
# 没有的」追加进 proxies.yaml 的 SUB-SYNC 块。
#
# 比对基准有两份（2026-11-12）：转换器带 new_name=true，会把节点改名成
# 「🇯🇵 日本-优化」，原始订阅里还是「日本-优化」—— 只按名字比会把整批节点
# 判成「丢了」，11-09~11-12 每天都因此撞上限、块里 4 条 HY2 一直是旧服务器。
# 所以先比名字，再比 server:port（改名不改端点）。所以：
#   - 转换器支持了某类节点 → 块自动变空，不会重名；
#   - 机场将来又加一类节点 → 自动补上，不需要再改代码。
#
# 由 starts/clash_modify.sh 的 modify_yaml() 调用（start 与 hotupdate 都经过它）。
CRASHDIR=${CRASHDIR:-/etc/ShellCrash}
TARGET=$CRASHDIR/yamls/proxies.yaml
CONVERTED=${1:-$CRASHDIR/yamls/config.yaml}
LOGDIR=$CRASHDIR/logs
LOG=$LOGDIR/sub-sync.log
TSF=/tmp/ShellCrash/.sub_sync_ts
BEGIN='# >>> SUB-SYNC'
END='# <<< SUB-SYNC'
INTERVAL=${SUB_SYNC_INTERVAL:-21600}
# 机场按精确 UA 给节点集：只有 "clash.meta" 才会返回 hysteria2 节点，
# "clash.meta/mihomo"（ShellCrash 转换器传的那个）会被藏掉。
UA=${SUB_SYNC_UA:-clash.meta}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

mkdir -p "$LOGDIR" /tmp/ShellCrash 2>/dev/null

# 块已存在且未到刷新间隔 → 跳过（重启时不重复拉订阅）
NOW=$(date +%s)
LAST=$(cat "$TSF" 2>/dev/null || echo 0)
if [ -f "$TARGET" ] && grep -qF "$BEGIN" "$TARGET" && [ $((NOW - LAST)) -lt "$INTERVAL" ]; then
    exit 0
fi

URL=$(sed -n "s/^Url=//p" "$CRASHDIR"/configs/ShellCrash.cfg 2>/dev/null | head -1 | tr -d "'")
URL=$(echo "$URL" | sed 's/%26/\&/g')
[ -z "$URL" ] && { log "SKIP: ShellCrash.cfg 里没有 Url"; exit 0; }

CURL=/usr/bin/curl
[ -x "$CURL" ] || CURL=curl

# 中间文件放目标同目录：/tmp 是 tmpfs，与 /etc 的 UBIFS 跨文件系统，
# 跨设备 mv 是「复制 + 删除」而非原子 rename —— 断电时目标可能只剩半截
# （2026-11-04 筛节点写入途中硬复位，proxies.yaml 就这样变成空文件）。
TMP="${TARGET%/*}/.subsync.$$"
trap 'rm -f "$TMP".raw "$TMP".have "$TMP".all "$TMP".nodes "$TMP".new "$TMP".eps "$TMP".counts' EXIT

# 转换后配置是「已有什么」的基准；读不到就宁可不动
if [ ! -s "$CONVERTED" ]; then
    log "WARN: 转换后配置不存在（$CONVERTED），保留现有块"
    exit 0
fi
grep -oE "\{ ?name: [^,]+" "$CONVERTED" | awk -F'name: ' '{print $2}' \
    | sed "s/^ *//;s/ *$//" | sort -u > "$TMP.have"
HAVE_N=$(wc -l < "$TMP.have")
if [ "$HAVE_N" -lt 10 ]; then
    log "WARN: 转换后配置只解析到 $HAVE_N 个节点，疑似异常，保留现有块"
    exit 0
fi

# 端点基准：改名后的节点靠 server:port 认领，避免把「转换器已包含」当成「丢了」。
sed -n 's/.*server: *\([^,[:space:]]*\), *port: *\([0-9][0-9]*\).*/\1:\2/p' "$CONVERTED" \
    | sort -u > "$TMP.eps"
EPS_N=$(wc -l < "$TMP.eps")

if ! "$CURL" -sf --connect-timeout 3 -m 15 -A "$UA" "$URL" -o "$TMP.raw"; then
    log "WARN: 原始订阅拉取失败，保留现有块"
    exit 0
fi

# 只取一行式节点定义。两个必须的过滤：
#   - server: —— 策略组也是 `- { name: X, type: select, proxies: [...] }` 形状，
#     且列表里含 HY2 节点名，只按名字过滤会把整组当节点抓进来；
#   - 占位名 —— 机场把「剩余流量 / 套餐到期 / 过滤掉N条线路」也写成真节点。
grep -E "^ *- *\{ *name:" "$TMP.raw" \
    | grep -F 'server:' \
    | grep -vE '剩余流量|套餐|到期|过滤掉|官网' \
    | sed "s/^ *- *{ *name: */- {name: /" \
    | sed "s/ *} *$/}/" > "$TMP.all"

# 三分（名字命中 / 端点命中 / 待补）用一次 awk 完成：
#   原写法对每一行起 5 个子进程（echo|sed ×2 + grep ×2 + echo），订阅里 300 个节点
#   就是 1500 次 fork —— 在 239MB 的路由器上是秒级抖动，而且每个 grep 都要把基准表
#   重新读一遍。awk 把两张基准表读进数组，单进程一遍扫完，判定语义与原来逐行
#   grep -qxF 完全一致（精确整行匹配，不做正则）。
awk -v have="$TMP.have" -v eps="$TMP.eps" -v cnt="$TMP.counts" '
BEGIN {
	while ((getline l < have) > 0) H[l] = 1
	close(have)
	while ((getline l < eps) > 0) E[l] = 1
	close(eps)
}
{
	n = $0
	sub(/^- \{name: /, "", n)
	# 原 sed 要求 name 后面跟着逗号，否则整行不算节点（策略组/多行块）；保持一致。
	if (index(n, ",") == 0) next
	sub(/,.*$/, "", n)
	gsub(/^ +| +$/, "", n)
	if (n == "") next
	if (n in H) { sn++; next }
	ep = ""
	if (match($0, /server: *[^,[:space:]]+, *port: *[0-9]+/)) {
		ep = substr($0, RSTART, RLENGTH)
		sub(/^server: */, "", ep)
		sub(/, *port: */, ":", ep)
	}
	if (ep != "" && (ep in E)) { se++; next }
	print
}
END { print sn + 0, se + 0 > cnt }
' "$TMP.all" > "$TMP.nodes"
SEEN_NAME=0
SEEN_EP=0
[ -f "$TMP.counts" ] && read SEEN_NAME SEEN_EP < "$TMP.counts"
N=$(wc -l < "$TMP.nodes")

# 上限按基准比例判定：基准正常时「真丢」的节点只有个位数（转换器不认的协议类型），
# 绝不可能达到基准节点数的一半。固定 20 的写法在机场节点变多、或转换器改名时
# 会把正常差集也拦下（2026-11-09~11-12 连撞四天，HY2 的旧服务器一直刷不进来）。
LIMIT=$((HAVE_N / 2))
[ "$LIMIT" -gt 40 ] && LIMIT=40
[ "$LIMIT" -lt 10 ] && LIMIT=10
if [ "$N" -gt "$LIMIT" ]; then
    log "WARN: 待补节点 $N 个，超过上限 $LIMIT（基准 $HAVE_N），疑似基准解析异常，保留现有块"
    exit 0
fi
log "比对：名字命中 $SEEN_NAME，端点命中 $SEEN_EP（转换器改名），待补 $N 条"

# 补国旗前缀，与订阅里其它节点的命名风格一致（未知地区保持原名）
if [ "$N" -gt 0 ]; then
    sed -i -e 's/^- {name: 新加坡/- {name: 🇸🇬 新加坡/' \
           -e 's/^- {name: 日本/- {name: 🇯🇵 日本/' \
           -e 's/^- {name: 香港/- {name: 🇭🇰 香港/' \
           -e 's/^- {name: 韩国/- {name: 🇰🇷 韩国/' \
           "$TMP.nodes"
fi

# 重建 proxies.yaml：块之外的内容原样保留。
# 兼容旧标记 HY2-AUTO（首次升级时原地换成 SUB-SYNC）。
OLD_B='# >>> HY2-AUTO'
OLD_E='# <<< HY2-AUTO'
# 文件空了 / 没有公共节点时必须留下证据：2026-11-04 写入途中路由器硬复位，
# proxies.yaml 变成 0 字节，这里照常补 SUB-SYNC 块并把日志写成 OK ——
# 事故在日志里完全看不出来，公共池空了一整天。
if [ ! -s "$TARGET" ]; then
    log "WARN: $TARGET 为空或缺失（写入中断/断电？），本次只能补 SUB-SYNC 块；公共节点需 PC 侧重推"
elif ! grep -q '🆓 公共' "$TARGET"; then
    log "WARN: $TARGET 里没有公共节点（🆓 公共-*），公共池可能为空"
fi
if grep -qF "$BEGIN" "$TARGET"; then
    awk -v b="$BEGIN" -v e="$END" -v f="$TMP.nodes" '
        index($0, b) == 1 { print; while ((getline l < f) > 0) print l; close(f); skip = 1; next }
        index($0, e) == 1 { skip = 0 }
        !skip { print }
    ' "$TARGET" > "$TMP.new"
elif grep -qF "$OLD_B" "$TARGET"; then
    awk -v b="$OLD_B" -v e="$OLD_E" -v nb="$BEGIN" -v ne="$END" -v f="$TMP.nodes" '
        index($0, b) == 1 { print nb; while ((getline l < f) > 0) print l; close(f); skip = 1; next }
        index($0, e) == 1 { print ne; skip = 0 }
        !skip { print }
    ' "$TARGET" > "$TMP.new"
else
    cat "$TARGET" > "$TMP.new" 2>/dev/null
    printf '\n%s\n' "$BEGIN" >> "$TMP.new"
    cat "$TMP.nodes" >> "$TMP.new"
    printf '%s\n' "$END" >> "$TMP.new"
fi

sync
mv -f "$TMP.new" "$TARGET"
echo "$NOW" > "$TSF"
log "OK: 转换后缺 $N 个节点，已同步（基准 $HAVE_N 个 / 端点 $EPS_N 个）"
exit 0
