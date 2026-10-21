#!/bin/sh
# 从机场原始订阅同步 Hysteria2 节点到 yamls/proxies.yaml
#
# 背景：ShellCrash 通过订阅转换器（url.v1.mk，target=clash）拉订阅，
# 转换器会把 hysteria2 整类节点静默丢掉 —— 不报错、不告警，只是少几个节点。
# 而 HY2 池是当前唯一被 Google 判为 cc=SG 的干净出口（xiaoyan/mobgslb 的
# vmess 池整池判 cc=CN），丢掉它 Gemini 就报「不支持此国家」。
#
# 本脚本在每次生成配置前（start / hotupdate 都会经过 clash_modify.sh）直接从
# 机场原始订阅取 HY2 定义，重写 proxies.yaml 里的 HY2-AUTO 块。取不到就保留
# 上一次的块，绝不阻断配置生成。
#
# 由 starts/clash_modify.sh 的 modify_yaml() 调用。
CRASHDIR=${CRASHDIR:-/etc/ShellCrash}
TARGET=$CRASHDIR/yamls/proxies.yaml
LOGDIR=$CRASHDIR/logs
LOG=$LOGDIR/hy2-sync.log
TSF=/tmp/ShellCrash/.hy2_sync_ts
BEGIN='# >>> HY2-AUTO'
END='# <<< HY2-AUTO'
INTERVAL=${HY2_SYNC_INTERVAL:-21600}
# 机场按精确 UA 给节点集：只有 "clash.meta" 才会返回 hysteria2 节点，
# "clash.meta/mihomo"（ShellCrash 转换器传的那个）会被藏掉。
UA=${HY2_SYNC_UA:-clash.meta}

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

TMP=/tmp/hy2sync.$$
if ! "$CURL" -sf --connect-timeout 3 -m 15 -A "$UA" "$URL" -o "$TMP.raw"; then
    rm -f "$TMP".raw
    log "WARN: 原始订阅拉取失败，保留现有 HY2 块"
    exit 0
fi

# 机场把「剩余流量 / 套餐到期 / 过滤掉N条线路」这类占位节点也定义成
# hysteria2，必须按名字排除，否则会被当成真节点导进来。
grep -i 'hysteria2' "$TMP.raw" \
    | grep -vE '剩余流量|套餐|到期|过滤掉|官网|流量' \
    | sed 's/^ *- *{ *name: */- {name: /' \
    | sed 's/ *} *$/}/' > "$TMP".nodes
N=$(wc -l < "$TMP".nodes)
rm -f "$TMP".raw
if [ "$N" -eq 0 ]; then
    rm -f "$TMP".nodes
    log "WARN: 原始订阅里没有 hysteria2 节点，保留现有 HY2 块"
    exit 0
fi

# 补国旗前缀，与订阅里其它节点的命名风格一致
sed -i -e 's/^- {name: 新加坡/- {name: 🇸🇬 新加坡/' \
       -e 's/^- {name: 日本/- {name: 🇯🇵 日本/' \
       -e 's/^- {name: 香港/- {name: 🇭🇰 香港/' \
       -e 's/^- {name: 韩国/- {name: 🇰🇷 韩国/' \
       "$TMP".nodes

# 重建 proxies.yaml：标记块之外的内容原样保留
if [ -f "$TARGET" ] && grep -qF "$BEGIN" "$TARGET"; then
    awk -v b="$BEGIN" -v e="$END" -v f="$TMP.nodes" '
        index($0, b) == 1 { print; while ((getline l < f) > 0) print l; close(f); skip = 1; next }
        index($0, e) == 1 { skip = 0 }
        !skip { print }
    ' "$TARGET" > "$TMP.new"
else
    cat "$TARGET" > "$TMP.new" 2>/dev/null
    printf '\n%s\n' "$BEGIN" >> "$TMP.new"
    cat "$TMP.nodes" >> "$TMP.new"
    printf '%s\n' "$END" >> "$TMP.new"
fi

mv -f "$TMP.new" "$TARGET"
rm -f "$TMP".nodes
echo "$NOW" > "$TSF"
log "OK: 同步 $N 个 hysteria2 节点"
exit 0
