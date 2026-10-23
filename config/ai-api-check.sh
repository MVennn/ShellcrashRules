#!/bin/sh
# AI API 链路自检 —— 订阅更新后跑一次即可
# 用法: sh /etc/ShellCrash/ai-api-check.sh
# 退出码: 0 全部通过 / 1 有失败项

API="http://127.0.0.1:9999"
SECRET=$(grep -m1 "^secret=" /etc/ShellCrash/configs/ShellCrash.cfg 2>/dev/null | cut -d= -f2- | tr -d "'\"")
AUTH="Authorization: Bearer $SECRET"
G="%F0%9F%A4%96%20AI%E6%8E%A5%E5%8F%A3"   # 🤖 AI接口
KEYFILE=/etc/ShellCrash/opencode.key
UA="ShellCrash-AI-Check/1.0"
fail=0

echo "===== 1. 策略组状态 ====="
J=$(curl -s --max-time 8 -H "$AUTH" "$API/proxies/$G")
NOW=$(echo "$J" | jsonfilter -e '@.now' 2>/dev/null)
CNT=$(echo "$J" | jsonfilter -e '@.all[*]' 2>/dev/null | wc -l)
if [ -z "$NOW" ]; then
	echo "FAIL: 组不存在或没有可用节点"
	fail=1
else
	echo "OK: 候选 $CNT 个，当前出口 -> $NOW"
fi

echo ""
echo "===== 2. 组到 opencode.ai 的延迟 ====="
D=$(curl -s --max-time 15 -H "$AUTH" "$API/proxies/$G/delay?timeout=8000&url=https%3A%2F%2Fopencode.ai%2F")
echo "$D"
echo "$D" | grep -q '"delay"' || { echo "FAIL: 延迟测试失败"; fail=1; }

echo ""
echo "===== 3. opencode.ai 可达性（经 mihomo 代理口） ====="
CODE=$(curl -s -x http://127.0.0.1:7890 -o /dev/null -w '%{http_code}' --max-time 15 https://opencode.ai/)
echo "HTTP $CODE"
[ "$CODE" = "200" ] || { echo "FAIL: 不是 200"; fail=1; }

echo ""
echo "===== 4. 三种协议最小 token 测试（经 mihomo 代理口） ====="
if [ -f "$KEYFILE" ]; then
	KEY=$(cat "$KEYFILE")

	C1=$(curl -s -x http://127.0.0.1:7890 -o /tmp/aicheck.json -w '%{http_code}' --max-time 30 \
		https://opencode.ai/zen/go/v1/chat/completions \
		-H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
		-H "User-Agent: $UA" -H "x-opencode-session: router-check" \
		-d '{"model":"deepseek-v4.1-flash","messages":[{"role":"user","content":"hi"}],"max_tokens":8}')
	echo "chat/completions        HTTP $C1"
	[ "$C1" = "200" ] || { echo "  body: $(head -c 200 /tmp/aicheck.json)"; fail=1; }

	C2=$(curl -s -x http://127.0.0.1:7890 -o /tmp/aicheck.json -w '%{http_code}' --max-time 30 \
		https://opencode.ai/zen/go/v1/messages \
		-H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01" \
		-H "Content-Type: application/json" -H "User-Agent: $UA" \
		-H "x-opencode-session: router-check" \
		-d '{"model":"claude-haiku-5-5","messages":[{"role":"user","content":"hi"}],"max_tokens":8}')
	echo "anthropic/messages      HTTP $C2"
	[ "$C2" = "200" ] || { echo "  body: $(head -c 200 /tmp/aicheck.json)"; fail=1; }

	C3=$(curl -s -x http://127.0.0.1:7890 -o /tmp/aicheck.json -w '%{http_code}' --max-time 30 \
		https://opencode.ai/zen/go/v1/responses \
		-H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
		-H "User-Agent: $UA" -H "x-opencode-session: router-check" \
		-d '{"model":"gpt-6-luna","input":"hi","max_output_tokens":16}')
	echo "openai/responses        HTTP $C3"
	[ "$C3" = "200" ] || { echo "  body: $(head -c 200 /tmp/aicheck.json)"; fail=1; }
else
	echo "SKIP: 没有 $KEYFILE（只做网络层检查）"
fi

rm -f /tmp/aicheck.json

echo ""
echo "===== 5. 分组排序钩子 ====="
if grep -q "reorder-groups.sh" /etc/ShellCrash/starts/clash_modify.sh; then
	echo "OK: clash_modify.sh 钩子在"
else
	echo "WARN: 钩子丢失（ShellCrash 脚本可能更新过），正在重新添加"
	sed -i '/^    merger_yaml$/a\    [ -x "$CRASHDIR"/reorder-groups.sh ] && "$CRASHDIR"/reorder-groups.sh "$TMPDIR"/config.yaml' /etc/ShellCrash/starts/clash_modify.sh
	if sh -n /etc/ShellCrash/starts/clash_modify.sh; then
		echo "已修复，重启生效: /etc/ShellCrash/start.sh start"
	else
		echo "FAIL: 修复后语法错误，请从 /root/backup/pre-ai-api/clash_modify.sh.bak 恢复"
		fail=1
	fi
fi
# 机场伪节点：过滤掉N条线路 / 剩余流量 / 套餐 / 到期 / 官网 都不是可用线路。
# 「过滤掉14条线路」与日本-优化同 server/port/uuid，2026-10-23 被 url-test 选中后
# 健康检查一抖就把 🛟 主备自动 整组切到公共池，所以必须在生成阶段剔除。
if grep -q "丢弃机场伪节点" /etc/ShellCrash/reorder-groups.sh 2>/dev/null; then
	echo "OK: reorder-groups.sh 含机场伪节点过滤"
else
	echo "FAIL: reorder-groups.sh 缺少机场伪节点过滤"
	fail=1
fi
DECOY=$(grep -E '^ *- *\{ *name: .*(过滤掉|剩余流量|套餐|到期|官网)' /tmp/ShellCrash/config.yaml 2>/dev/null | head -1)
DECOY_M=$(grep -E '^      - .*(过滤掉|剩余流量|套餐|到期|官网)' /tmp/ShellCrash/config.yaml 2>/dev/null | head -1)
if [ -z "$DECOY" ] && [ -z "$DECOY_M" ]; then
	echo "OK: 运行配置无机场伪节点"
else
	echo "FAIL: 运行配置仍有伪节点: ${DECOY:-$DECOY_M}"
	fail=1
fi

FIRST=$(curl -s --max-time 8 -H "$AUTH" "$API/proxies/%F0%9F%9A%80%20%E8%8A%82%E7%82%B9%E9%80%89%E6%8B%A9" | jsonfilter -e '@.all[0]' 2>/dev/null)
if [ "$FIRST" = "🛟 主备自动" ]; then
	echo "OK: 节点选择首项 = 🛟 主备自动（机场优先，公共节点兜底）"
else
	echo "FAIL: 节点选择首项 = ${FIRST:-?}（应为 🛟 主备自动）"
	fail=1
fi

echo ""
echo "===== 6. hotupdate 重载路径 ====="
if grep -q '\$CRASHDIR/config\.\$format' /etc/ShellCrash/task/task.sh; then
	echo "OK: hotupdate 使用 SAFE_PATHS 内路径"
else
	echo "WARN: 路径被重置（ShellCrash 脚本可能更新过），正在修复"
	sed -i 's#\$TMPDIR/config\.\$format#\$CRASHDIR/config.\$format#' /etc/ShellCrash/task/task.sh
	if sh -n /etc/ShellCrash/task/task.sh && grep -q '\$CRASHDIR/config\.\$format' /etc/ShellCrash/task/task.sh; then
		echo "已修复，下次 hotupdate 生效"
	else
		echo "FAIL: 修复失败，请检查 /etc/ShellCrash/task/task.sh"
		fail=1
	fi
fi

echo ""
echo "===== 7. Chrome/Google 下载修复 ====="
if grep -q '^+\.googleusercontent\.com$' /etc/ShellCrash/configs/fake_ip_filter; then
	echo "OK: fake-ip 已排除 googleusercontent"
else
	echo "FAIL: fake_ip_filter 缺少 googleusercontent"
	fail=1
fi
if nft list table inet quicguard >/dev/null 2>&1; then
	echo "OK: quicguard 已加载"
else
	echo "WARN: quicguard 未加载，正在加载"
	nft -f /etc/quicguard.nft || { echo "FAIL: quicguard 加载失败"; fail=1; }
fi
if grep -q 'play.googleapis.com' /etc/ShellCrash/yamls/rules.yaml; then
	echo "OK: Google 出口覆盖规则在"
else
	echo "FAIL: rules.yaml 缺少 Google 覆盖规则"
	fail=1
fi

echo ""
echo "===== 8. CN 直连中间层（rules-mid） ====="
RM=/etc/ShellCrash/rules-mid.sh
if [ -x "$RM" ] && sh -n "$RM" 2>/dev/null; then
	echo "OK: rules-mid.sh 可执行且语法通过"
else
	echo "FAIL: rules-mid.sh 缺失、不可执行或语法错误"
	fail=1
fi
if grep -q 'rules-mid\.sh' /etc/ShellCrash/starts/clash_modify.sh; then
	echo "OK: clash_modify.sh 钩子在"
else
	echo "FAIL: clash_modify.sh 缺少 rules-mid 钩子"
	fail=1
fi
CFG=/tmp/ShellCrash/config.yaml
[ -f "$CFG" ] || CFG=/etc/ShellCrash/config.yaml
if [ -f "$CFG" ]; then
	EDGE=$(awk '/^rules:[ ]*$/{inr=1;next} inr&&/^[^ ]/{inr=0} inr&&index($0,"- DOMAIN-SUFFIX,edgedatg.com,🌍 国外媒体"){print NR;exit}' "$CFG")
	TG=$(awk -v edge="$EDGE" '/^rules:[ ]*$/{inr=1;next} inr&&/^[^ ]/{inr=0} inr&&NR<edge&&(index($0,"t.me")||index($0,"tdesktop.com")||index($0,"telegra.ph")||index($0,"telegram.me")||index($0,"telegram.org")){n=NR} END{print n+0}' "$CFG")
	CN=$(awk '/^rules:[ ]*$/{inr=1;next} inr&&/^[^ ]/{inr=0} inr{L=$0;sub(/^[ \t]+/,"",L);sub(/[ \t]+$/,"",L);sub(/[ \t]+#.*$/,"",L);sub(/[ \t]+$/,"",L);if(L=="- RULE-SET,cn,🎯 全球直连"){print NR;exit}}' "$CFG")
	if [ "$TG" -gt 0 ] && [ -n "$CN" ] && [ -n "$EDGE" ] && [ "$CN" -gt "$TG" ] && [ "$CN" -lt "$EDGE" ]; then
		echo "OK: RULE-SET,cn 在第 $CN 行（最后一条 Telegram 规则 $TG 之后、ProxyMedia $EDGE 之前）"
	else
		echo "FAIL: RULE-SET,cn 位置不对 (tg=$TG cn=${CN:-无} edge=${EDGE:-无})"
		fail=1
	fi
else
	echo "FAIL: 找不到运行配置 $CFG"
	fail=1
fi

echo ""
echo ""
echo "===== 9. 境外QUIC拦截 + TLS重新解析（Gemini地区限制修复） ====="
QF=/etc/ShellCrash/starts/fw_nftables.sh
CM=/etc/ShellCrash/starts/clash_modify.sh
FF=/etc/ShellCrash/configs/fake_ip_filter
CFG=/tmp/ShellCrash/config.yaml
QIC_RULE='[ "$quic_rj" = '"'"'ON'"'"' -a "$lan_proxy" = true ] && [ "$1" = '"'"'prerouting'"'"' ] && nft add rule inet shellcrash $1 udp dport {443, 8443} counter reject with icmpx type port-unreachable'

# 9.1 fw_nftables.sh 的 QUIC reject 钩子（ShellCrash 更新会覆盖本脚本）
if [ -f "$QF" ] && grep -q 'QUIC_BLOCK_MARKER' "$QF"; then
	echo "OK: fw_nftables.sh 含 QUIC reject 钩子"
else
	awk -v r="$QIC_RULE" '/#屏蔽quic/ && !done {
		print "    #QUIC_BLOCK_MARKER 境外QUIC真正reject（此前仅return，会让HTTP/3带国内出口IP直连逃逸）"
		print "    " r
		done=1
	} { print }' "$QF" > /tmp/fw.fix 2>/dev/null
	if [ -s /tmp/fw.fix ] && sh -n /tmp/fw.fix 2>/dev/null; then
		mv /tmp/fw.fix "$QF"
		echo "FIX: fw_nftables.sh 已补回 QUIC reject 钩子（下次 ShellCrash 启动生效）"
	else
		echo "FAIL: 无法补回 fw_nftables.sh 的 QUIC reject 钩子"
		fail=1
	fi
fi

# 9.2 运行中的 nft 表是否真的有 QUIC reject 规则
if nft list table inet shellcrash 2>/dev/null | grep -q 'udp dport { 443, 8443 } counter'; then
	echo "OK: live nft 表已有 QUIC reject 规则"
else
	H=$(nft -a list table inet shellcrash 2>/dev/null | awk '/udp dport \{ *443, *8443 *\} return/ {for(i=1;i<=NF;i++) if($i=="handle") {print $(i+1); exit}}' | tr -d ' ')
	if [ -n "$H" ]; then
		nft insert rule inet shellcrash prerouting handle "$H" udp dport {443, 8443} counter reject with icmpx type port-unreachable 2>/dev/null \
			&& echo "FIX: live nft 表已重新插入 QUIC reject 规则" \
			|| { echo "FAIL: 插入 QUIC reject 规则失败"; fail=1; }
	else
		echo "FAIL: live 表里找不到 QUIC return 规则，无法插入 reject"
		fail=1
	fi
fi

# 9.3 clash_modify.sh 的 TLS 嗅探 override-destination
if [ -f "$CM" ] && grep -q 'tls: {ports: \[443, 8443\], override-destination: true}' "$CM"; then
	echo "OK: clash_modify.sh 的 TLS 嗅探含 override-destination"
else
	sed -i 's/tls: {ports: \[443, 8443\]}/tls: {ports: [443, 8443], override-destination: true}/' "$CM" 2>/dev/null
	if grep -q 'tls: {ports: \[443, 8443\], override-destination: true}' "$CM" 2>/dev/null; then
		echo "FIX: clash_modify.sh 已补上 override-destination（需再跑一次 task.sh hotupdate 生效）"
	else
		echo "FAIL: 无法给 clash_modify.sh 补上 override-destination"
		fail=1
	fi
fi

# 9.4 运行配置里的 sniffer 是否已生效
if [ -f "$CFG" ] && grep -q 'tls: {ports: \[443, 8443\], override-destination: true}' "$CFG"; then
	echo "OK: 运行配置已含 TLS override-destination"
else
	echo "WARN: 运行配置未含 override-destination，跑一次 task.sh hotupdate 生效"
fi

# 9.5 fake_ip_filter 的 +.google.com（客户端拿全球边缘真实IP，避免落到国内边缘）
if [ -f "$FF" ] && grep -qx '+.google.com' "$FF"; then
	echo "OK: fake_ip_filter 含 +.google.com"
else
	echo '+.google.com' >> "$FF" 2>/dev/null && echo "FIX: fake_ip_filter 已补 +.google.com（需 hotupdate 生效）"
fi
echo ""

echo ""
echo "===== 10. Google 家族统一出口（全部指向 🤖 干净出口） ====="
RCFG=/tmp/ShellCrash/config.yaml
GEN=/etc/ShellCrash/ai-rules-update.sh
if [ -f "$RCFG" ]; then
	MP=$(grep -m1 -E "^mixed-port:" "$RCFG" | grep -oE "[0-9]+$")
	if [ -n "$MP" ]; then
		echo "OK: mixed-port = $MP（合法纯数字）"
	else
		echo "FAIL: mixed-port 非法（应为纯数字）→ 必然触发配置回退"
		fail=1
	fi
	TG=$(awk '/^rules:[ ]*$/{inr=1;next} inr&&/^[^ ]/{inr=0} inr{L=$0;sub(/^[ \t]+/,"",L);sub(/[ \t]+$/,"",L);if(L ~ /^- DOMAIN-SUFFIX,gstatic\.com/) {print NR;exit}}' "$RCFG")
	IC=$(awk '/^rules:[ ]*$/{inr=1;next} inr&&/^[^ ]/{inr=0} inr{L=$0;sub(/^[ \t]+/,"",L);if(L ~ /^- IP-CIDR,203\.208\.32\.0\/19/) {print NR;exit}}' "$RCFG")
	if [ -n "$TG" ] && [ -n "$IC" ] && [ "$TG" -lt "$IC" ]; then
		echo "OK: Google 家族规则（第 $TG 行）早于 IP-CIDR（第 $IC 行）"
	else
		echo "FAIL: Google 家族规则位置不对 (gstatic=${TG:-无} ipcidr=${IC:-无})"
		fail=1
	fi
	MISS=0
	for d in gstatic.com googleusercontent.com googleapis.com google.com gemini.google.com generativelanguage.googleapis.com clients6.google.com accounts.google.com youtube.com googlevideo.com; do
		grep -qF "$d,🤖 干净出口" "$RCFG" || MISS=$((MISS+1))
	done
	# GitHub 全族：2026-10-22 从干净出口拆到 🔗 GitHub 出口（独立 url-test，按 GitHub 可达性选路）
	for d in github.com githubusercontent.com githubassets.com githubapp.com; do
		grep -qF "DOMAIN-SUFFIX,$d,🔗 GitHub 出口" "$RCFG" || MISS=$((MISS+1))
	done
	if [ "$MISS" -eq 0 ]; then
		echo "OK: Google/YouTube 关键域名指向 🤖 干净出口，GitHub 全族指向 🔗 GitHub 出口"
	else
		echo "FAIL: 有 $MISS 个关键域名指向了错误的出口组"
		fail=1
	fi
	if grep -qE "IP-CIDR,203\.208\.32\.0/19,🎯 全球直连,no-resolve" "$RCFG"; then
		echo "OK: 203.208.32.0/19 带 no-resolve"
	else
		echo "FAIL: 203.208.32.0/19 缺 no-resolve（Google 端点会被按域名劫持）"
		fail=1
	fi
	if grep -q "ngstr-lra8j" "$RCFG"; then
		echo "OK: sniffer skip-domain 含 Play CDN 域名"
	else
		echo "FAIL: sniffer skip-domain 缺 CDN 域名（Play 下载会超时）"
		fail=1
	fi
	if grep -q 'OUT.tmp" #ATOMIC_WRITE_MARKER' "$GEN" && grep -q 'mv -f "$OUT.tmp" "$OUT"' "$GEN"; then
		echo "OK: 生成器为原子写（tmp → 校验 → mv）"
	else
		echo "FAIL: 生成器缺少原子写"
		fail=1
	fi
	if grep -q 'play.googleapis.com,$CL" "$OUT.tmp"' "$GEN"; then
		echo "OK: 生成器校验读的是临时文件"
	else
		echo "FAIL: 生成器校验读的不是临时文件（会在 mv 前误判退出）"
		fail=1
	fi
else
	echo "FAIL: 找不到运行配置 $RCFG"
	fail=1
fi

echo ""
echo "===== 11. 夜间加固项（cn_ip剔除 / sniffer跳过CDN / 组出口） ====="
FW=/etc/ShellCrash/starts/fw_nftables.sh
CM=/etc/ShellCrash/starts/clash_modify.sh
if [ -f "$FW" ] && grep -q 'CN_IP_EXCLUDE_203208' "$FW"; then
	echo "OK: fw_nftables.sh 含 CN_IP 剔除标记（重启后不会把 Google 国内边缘段加回 cn_ip）"
else
	echo "FAIL: fw_nftables.sh 缺 CN_IP_EXCLUDE_203208 标记"
	fail=1
fi
if nft list set inet shellcrash cn_ip 2>/dev/null | grep -q "203.208.32.0/19"; then
	echo "FAIL: live cn_ip 集合仍含 203.208.32.0/19"
	fail=1
else
	echo "OK: live cn_ip 集合不含 203.208.32.0/19"
fi
if [ -f "$CM" ] && grep -q "ngstr-lra8j" "$CM"; then
	echo "OK: clash_modify.sh 的 sniffer skip-domain 含 Play CDN 域名"
else
	echo "FAIL: clash_modify.sh 的 sniffer skip-domain 缺 CDN 域名"
	fail=1
fi

echo ""
echo "===== 12. 规则文件完整性（空组名 / 原子写 / AI_GROUP 定义） ====="
RULES=/etc/ShellCrash/yamls/rules.yaml
if [ -f "$RULES" ]; then
	BAD=$(awk '/^- [^,]+,[^,]*,\s*$/{c++} END{printf "%d", c+0}' "$RULES")
	if [ "$BAD" = "0" ]; then
		echo "OK: rules.yaml 无空组名规则"
	else
		echo "FAIL: rules.yaml 有 $BAD 条空组名规则（mihomo 会拒载）"
		fail=1
	fi
fi
if [ -f "$RCFG" ]; then
	BADC=$(awk '/^[[:space:]]*- [^,]+,[^,]*,\s*$/{c++} END{printf "%d", c+0}' "$RCFG")
	if [ "$BADC" = "0" ]; then
		echo "OK: 运行配置无空组名规则"
	else
		echo "FAIL: 运行配置有 $BADC 条空组名规则"
		fail=1
	fi
fi
if grep -q '^AI_GROUP="🤖 人工智能"' "$GEN"; then
	echo "OK: 生成器已定义 AI_GROUP"
else
	echo "FAIL: 生成器缺 AI_GROUP 定义"
	fail=1
fi
if grep -q '^CL="🤖 干净出口"' "$GEN"; then
	echo "OK: 生成器已定义 CL（干净出口组）"
else
	echo "FAIL: 生成器缺 CL 定义（规则会生成空组名）"
	fail=1
fi

echo ""
echo "===== 13. IPv6 fake-IP 旁路防护（fc00::/16 必须进代理） ====="
if nft list table inet googleroute 2>/dev/null | grep -q "ip6 daddr fc00::/16"; then
	echo "OK: googleroute 表含 fake-IPv6(fc00::/16) → :7892 的重定向"
else
	echo "FAIL: fake-IPv6 未被重定向进代理（IPv6 优先的客户端会间歇性超时）"
	fail=1
fi
if grep -q 'googleroute.nft' /etc/rc.local; then
	echo "OK: rc.local 含 googleroute 开机加载"
else
	echo "FAIL: rc.local 缺 googleroute 开机加载"
	fail=1
fi

echo ""
echo "===== 14. 干净出口组（唯一 Google 判为非 CN 的稳定出口） ====="
ASEC=$(sed -n "s/^secret=//p" /etc/ShellCrash/configs/ShellCrash.cfg 2>/dev/null | head -1)
CLE="%F0%9F%A4%96%20%E5%B9%B2%E5%87%80%E5%87%BA%E5%8F%A3"
if [ -f "$RCFG" ] && grep -q "name: 🤖 干净出口" "$RCFG"; then
	echo "OK: 运行配置含 🤖 干净出口 组"
	N=$(grep -cF ",🤖 干净出口" "$RCFG")
	if [ "$N" -ge 20 ]; then
		echo "OK: 指向干净出口的规则 $N 条"
	else
		echo "FAIL: 指向干净出口的规则只有 $N 条（应为 20+）"
		fail=1
	fi
	MEM=$(curl -s -m 5 -H "Authorization: Bearer $ASEC" "http://127.0.0.1:9999/proxies/$CLE" 2>/dev/null | grep -oE "\"all\":\[[^]]*\]" | head -1)
	case "$MEM" in
		*HY2*|*印度*) echo "OK: 干净出口候选含 HY2/印度节点" ;;
		*) echo "FAIL: 干净出口候选异常: ${MEM:-无}"; fail=1 ;;
	esac
	NOWC=$(curl -s -m 5 -H "Authorization: Bearer $ASEC" "http://127.0.0.1:9999/proxies/$CLE" 2>/dev/null | grep -oE "\"now\":\"[^\"]*\"" | head -1 | sed "s/\"now\":\"//;s/\"$//")
	case "$NOWC" in
		*HY2*|*印度*|*台湾-优化3*) echo "OK: 干净出口当前 = $NOWC" ;;
		*) echo "WARN: 干净出口当前 = ${NOWC:-空}（守护会在 5 分钟内复位）" ;;
	esac
else
	echo "FAIL: 运行配置缺 🤖 干净出口 组 → 配置可能已回退基础配置"
	fail=1
fi

echo ""
echo "===== 15. 出口组与守护进程 ====="
AIN="%F0%9F%A4%96%20%E4%BA%BA%E5%B7%A5%E6%99%BA%E8%83%BD"
AWE="%F0%9F%A4%96%20AI%E7%BD%91%E9%A1%B5"
NOWA=$(curl -s -m 5 -H "Authorization: Bearer $ASEC" "http://127.0.0.1:9999/proxies/$AIN" 2>/dev/null | grep -oE "\"now\":\"[^\"]*\"" | head -1 | sed "s/\"now\":\"//;s/\"$//")
if [ "$NOWA" = "🤖 AI网页" ]; then
	echo "OK: 🤖 人工智能 = 🤖 AI网页（出口固定，不会漂到被判 CN 的节点）"
else
	echo "WARN: 🤖 人工智能 当前 = ${NOWA:-空}（守护会在 5 分钟内复位）"
fi
NOWG=$(curl -s -m 5 -H "Authorization: Bearer $ASEC" "http://127.0.0.1:9999/proxies/$AWE" 2>/dev/null | grep -oE "\"now\":\"[^\"]*\"" | head -1 | sed "s/\"now\":\"//;s/\"$//")
case "$NOWG" in
	*HY2*|*台湾-优化3*|*台湾-优化2-GPT*) echo "OK: 🤖 AI网页 出口 = $NOWG" ;;
	*) echo "WARN: 🤖 AI网页 出口 = ${NOWG:-空}" ;;
esac
if [ -x /etc/ShellCrash/guardian.sh ] && grep -q "CLEAN" /etc/ShellCrash/guardian.sh; then
	echo "OK: 守护进程在位（含干净出口/回退/OOM 拉起逻辑）"
else
	echo "WARN: 守护进程缺失或不含干净出口逻辑"
fi

echo ""

echo ""
echo "===== 16. 全局 QUIC 阻断（Redir 模式无法代理 UDP，QUIC 会直出带国内 IP） ====="
QG=/etc/quicguard.nft
if [ -f "$QG" ] && grep -qE "udp dport \{ 443, 8443 \} counter reject" "$QG"; then
	echo "OK: quicguard.nft 含全局 QUIC reject（Chrome 的 HTTP/3 会被拦下并回落 TCP 走代理）"
else
	echo "FAIL: quicguard.nft 缺全局 QUIC reject（浏览器会用 QUIC 直连，UI 可能加载不全）"
	fail=1
fi
if nft list table inet quicguard 2>/dev/null | grep -q "udp dport { 443, 8443 } counter packets"; then
	echo "OK: live quicguard 表已加载全局 QUIC 阻断"
else
	nft -f "$QG" 2>/dev/null && echo "FIX: quicguard 表已重载" || { echo "FAIL: quicguard 表重载失败"; fail=1; }
fi
QP=$(nft list table inet quicguard 2>/dev/null | grep -oE "udp dport \{ 443, 8443 \} counter packets [0-9]+" | grep -oE "[0-9]+" | tail -1)
echo "INFO: QUIC 拦截累计 ${QP:-0} 包（说明浏览器仍在尝试 HTTP/3，属正常，每次都被拦下回落 TCP）"
# 国内豁免：CN 目标直连，QUIC 放行；缺失时 QQ/微信图片会等 QUIC 握手超时才回落 TCP。
# 豁免由 /etc/quicguard-sync.sh 生成（镜像 ShellCrash 的 cn_ip / cn_ip6）。
# 注意：镜像集合是快照 —— 订阅更新 / ShellCrash 重启后要重跑同步脚本。
if nft list chain inet quicguard prerouting 2>/dev/null | grep -q '@cn_ip_mirror return'; then
	CN4=$(nft list set inet quicguard cn_ip_mirror 2>/dev/null | tr -cd ',' | wc -c)
	CN6=$(nft list set inet quicguard cn_ip6_mirror 2>/dev/null | tr -cd ',' | wc -c)
	echo "OK: 国内 QUIC 豁免在位（cn_ip_mirror ${CN4} 项 / cn_ip6_mirror ${CN6} 项，含归并区间）"
else
	echo "WARN: 国内 QUIC 豁免缺失 —— QQ/微信图片会等 QUIC 握手超时（跑 sh /etc/quicguard-sync.sh）"
fi

echo ""
echo "===== 17. 高带宽直连（省机场流量：Google 下载 / Chrome 更新 / JetBrains） ====="
# 这几条在模板里会被带去代理组：dl.google.com 与 gvt1.com 被 google.com/gvt1.com 的
# 干净出口规则截走，gvt1-cn.com（Google 中国 CDN）根本不在 cn.mrs，jetbrains.com 落到 MATCH。
HB=/etc/ShellCrash/yamls/rules.yaml
for r in "DOMAIN,dl.google.com,🎯 全球直连" \
         "DOMAIN-SUFFIX,gvt1.com,🎯 全球直连" \
         "DOMAIN-SUFFIX,gvt1-cn.com,🎯 全球直连" \
         "DOMAIN-SUFFIX,jetbrains.com,🎯 全球直连" \
         "DOMAIN-SUFFIX,hf-mirror.com,🎯 全球直连" \
         "DOMAIN-SUFFIX,kuaishouzt.com,🎯 全球直连" \
         "DOMAIN-SUFFIX,images-cn.ssl-images-amazon.com,🎯 全球直连"; do
	if grep -qF -- "- $r" "$HB" 2>/dev/null; then
		echo "OK: rules.yaml 含 $r"
	else
		echo "FAIL: rules.yaml 缺 $r（重跑 ai-rules-update.sh）"
		fail=1
	fi
done
RCFG=${RCFG:-/tmp/ShellCrash/config.yaml}
if [ -f "$RCFG" ]; then
	DL=$(grep -nF -- "- DOMAIN,dl.google.com,🎯 全球直连" "$RCFG" | head -1 | cut -d: -f1)
	GG=$(grep -nF -- "- DOMAIN-SUFFIX,google.com," "$RCFG" | head -1 | cut -d: -f1)
	if [ -n "$DL" ] && [ -n "$GG" ] && [ "$DL" -lt "$GG" ]; then
		echo "OK: 运行配置里 dl.google.com 直连排在 google.com 代理之前 (#$DL < #$GG)"
	else
		echo "FAIL: 运行配置顺序异常（dl=#${DL:-无} google=#${GG:-无}）"
		fail=1
	fi
fi
# 2026-10-23 吸收段：AI / 大流量 / GitHub / 媒体 CDN（生成器校验之外的第二道）
for r in "DOMAIN-SUFFIX,image.civitai.com,📺 大流量" \
         "DOMAIN-SUFFIX,civitai.com,🚀 节点选择" \
         "DOMAIN,download2.epicgames.com,📺 大流量" \
         "DOMAIN-SUFFIX,cdn.blizzard.com,📺 大流量" \
         "DOMAIN-SUFFIX,dyn.riotcdn.net,📺 大流量" \
         "DOMAIN-SUFFIX,i.pximg.net,📺 大流量" \
         "DOMAIN-SUFFIX,replicate.delivery,📺 大流量" \
         "DOMAIN-SUFFIX,runway.com,🤖 人工智能" \
         "DOMAIN-SUFFIX,suno.com,🤖 人工智能" \
         "DOMAIN-SUFFIX,ai.com,🤖 人工智能" \
         "DOMAIN-SUFFIX,ghcr.io,🔗 GitHub 出口"; do
	if grep -qF -- "- $r" "$HB" 2>/dev/null; then
		echo "OK: rules.yaml 含 $r"
	else
		echo "FAIL: rules.yaml 缺 $r（重跑 ai-rules-update.sh）"
		fail=1
	fi
done
if [ -f "$RCFG" ]; then
	if grep -qF -- "- IP-CIDR,74.125.0.0/16,🤖 干净出口,no-resolve" "$RCFG" && \
	   grep -qF -- "- IP-CIDR,173.194.0.0/16,🤖 干净出口,no-resolve" "$RCFG"; then
		echo "OK: Google 兜底 IP-CIDR 带 no-resolve"
	else
		echo "FAIL: Google 兜底 IP-CIDR 缺 no-resolve（会触发真实 DNS 解析）"
		fail=1
	fi
fi

echo ""
echo "===== 18. 广告/追踪 carve-out（必须早于宽泛 Google 规则） ====="
# 宽泛 DOMAIN-KEYWORD,google / DOMAIN-SUFFIX,google.com 会遮蔽模板里的 Google 广告 REJECT。
# 这些规则必须存在，且在运行配置里排在 google.com / DOMAIN-KEYWORD,google 之前。
HB=${HB:-/etc/ShellCrash/yamls/rules.yaml}
RCFG=${RCFG:-/tmp/ShellCrash/config.yaml}
for r in "DOMAIN-SUFFIX,doubleclick.net,🛑 广告拦截" \
         "DOMAIN-SUFFIX,googlesyndication.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,googleadservices.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,google-analytics.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,googleadsserving.cn,🛑 广告拦截" \
         "DOMAIN-SUFFIX,ads.google.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,adservice.google.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,pagead.google.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,pagead.l.google.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,pagead-tpc.l.google.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,mobileads.google.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,afd.l.google.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,badad.googleplex.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,csi.gstatic.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,collector.githubapp.com,🛑 广告拦截" \
         "DOMAIN-SUFFIX,app-measurement.com,🛑 广告拦截"; do
	if grep -qF -- "- $r" "$HB" 2>/dev/null; then
		echo "OK: rules.yaml 含 $r"
	else
		echo "FAIL: rules.yaml 缺 $r（重跑 ai-rules-update.sh）"
		fail=1
	fi
done
for r in "DOMAIN-SUFFIX,envato.com,🚀 节点选择" \
         "DOMAIN-SUFFIX,envato-static.com,🚀 节点选择" \
         "DOMAIN-SUFFIX,envatousercontent.com,🚀 节点选择" \
         "DOMAIN-SUFFIX,themeforest.net,🚀 节点选择" \
         "DOMAIN-SUFFIX,liveperson.net,🚀 节点选择" \
         "DOMAIN-SUFFIX,lpsnmedia.net,🚀 节点选择" \
         "DOMAIN,browser-intake-datadoghq.com,🚀 节点选择" \
         "DOMAIN-SUFFIX,googletagmanager.com,🚀 节点选择" \
         "DOMAIN-SUFFIX,googletagservices.com,🚀 节点选择"; do
	if grep -qF -- "- $r" "$HB" 2>/dev/null; then
		echo "OK: rules.yaml 含 $r"
	else
		echo "FAIL: rules.yaml 缺 $r（重跑 ai-rules-update.sh）"
		fail=1
	fi
done
if [ -f "$RCFG" ]; then
	AD=$(grep -nF -- "- DOMAIN-SUFFIX,doubleclick.net,🛑 广告拦截" "$RCFG" | head -1 | cut -d: -f1)
	GG=$(grep -nF -- "- DOMAIN-SUFFIX,google.com," "$RCFG" | head -1 | cut -d: -f1)
	GK=$(grep -nF -- "- DOMAIN-KEYWORD,google," "$RCFG" | head -1 | cut -d: -f1)
	if [ -n "$AD" ] && [ -n "$GG" ] && [ -n "$GK" ] && [ "$AD" -lt "$GG" ] && [ "$AD" -lt "$GK" ]; then
		echo "OK: 广告 carve-out 在 google.com / google 关键词之前 (#$AD < #$GG / #$GK)"
	else
		echo "FAIL: 广告 carve-out 顺序异常（ad=#${AD:-无} google.com=#${GG:-无} keyword=#${GK:-无}）"
		fail=1
	fi
fi

if [ "$fail" -eq 0 ]; then
	echo "结果: 全部通过"
else
	echo "结果: 有失败项，检查上面输出"
fi
exit $fail
