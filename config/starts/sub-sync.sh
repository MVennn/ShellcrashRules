#!/bin/sh
# 从机场原始订阅补齐「订阅转换器丢掉的节点」到 yamls/proxies.yaml
#
# 背景：ShellCrash 通过订阅转换器（url.v1.mk，target=clash）拉订阅，转换器不认的
# 节点类型会被**静默丢掉**（2026-10-22 实测：hysteria2 整类消失，50 条 → 46 条）。
# 机场又按客户端 UA 给节点集（只有 clash.meta 才返回 hysteria2），两层叠加后，
# 唯一被判 cc=SG 的干净出口在路由器上完全不可见，Gemini 报「不支持此国家」。
#
# 做法：把原始订阅（UA clash.meta）与**转换后的配置**逐节点比对，只把「转换后
# 没有的」追加进 proxies.yaml 的 SUB-SYNC 块。所以：
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

TMP=/tmp/subsync.$$
trap 'rm -f "$TMP".raw "$TMP".have "$TMP".all "$TMP".nodes "$TMP".new' EXIT

# 转换后配置是「已有什么」的基准；读不到就宁可不动
if [ ! -s "$CONVERTED" ]; then
    log "WARN: 转换后配置不存在（$CONVERTED），保留现有块"
    exit 0
fi
grep -oE "\{ ?name: [^,]+" "$CONVERTED" | awk -F'name: ' '{print $2}' \
    | sed "s/^[^ ]* //" | sed "s/^ *//;s/ *$//" | sort -u > "$TMP.have"
HAVE_N=$(wc -l < "$TMP.have")
if [ "$HAVE_N" -lt 10 ]; then
    log "WARN: 转换后配置只解析到 $HAVE_N 个节点，疑似异常，保留现有块"
    exit 0
fi

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
    | grep -vE '剩余流量|套餐|到期|过滤掉|官网|流量' \
    | sed "s/^ *- *{ *name: */- {name: /" \
    | sed "s/ *} *$/}/" > "$TMP.all"

: > "$TMP.nodes"
while IFS= read -r line; do
    n=$(echo "$line" | sed -n "s/^- {name: \([^,]*\),.*/\1/p" | sed "s/^ *//;s/ *$//")
    [ -z "$n" ] && continue
    grep -qxF "$n" "$TMP.have" && continue
    echo "$line" >> "$TMP.nodes"
done < "$TMP.all"
N=$(wc -l < "$TMP.nodes")

# 一次性补进 20 个以上说明基准解析错了（会与订阅重名），宁可不动
if [ "$N" -gt 20 ]; then
    log "WARN: 待补节点 $N 个，超过安全上限 20，疑似基准解析异常，保留现有块"
    exit 0
fi

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

mv -f "$TMP.new" "$TARGET"
echo "$NOW" > "$TSF"
log "OK: 转换后缺 $N 个节点，已同步（基准 $HAVE_N 个）"
exit 0
