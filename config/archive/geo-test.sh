#!/bin/sh
# 临时诊断：走 mihomo 代理口，逐节点测试 gpt-6-luna 的地区限制

API="http://127.0.0.1:9999"
SEL="%F0%9F%9A%80%20%E6%89%8B%E5%8A%A8%E5%88%87%E6%8D%A2"   # 🚀 手动切换
KEY=$(cat /etc/ShellCrash/opencode.key)
UA="ShellCrash-GeoTest/1.0"
CFG=/tmp/ShellCrash/config.yaml
TESTCFG=/tmp/geo-test.yaml

cp "$CFG" "$TESTCFG"
sed -i 's|^- DOMAIN-SUFFIX,opencode.ai,.*$|- DOMAIN-SUFFIX,opencode.ai,🚀 手动切换|' "$TESTCFG"

curl -s -X PUT "$API/configs?force=true" -H "Content-Type: application/json" \
	-d "{\"path\":\"$TESTCFG\"}" >/dev/null
sleep 2

printf "%-24s %-6s %s\n" "NODE" "HTTP" "RESULT"
for node in "🇭🇰 香港-优化2" "🇯🇵 日本-优化" "🇸🇬 新加坡-优化2-GPT" "🇺🇸 美国LA-优化-GPT" "🇹🇼 台湾-优化2-GPT" "🇬🇧 英国-优化-GPT" "🇮🇳 印度-优化" "🇨🇦 加拿大-优化" "🇩🇪 德国-优化"; do
	curl -s -X PUT "$API/proxies/$SEL" -H "Content-Type: application/json" \
		-d "{\"name\":\"$node\"}" >/dev/null
	sleep 1
	code=$(curl -s -x http://127.0.0.1:7890 -o /tmp/geo-resp.json -w '%{http_code}' --max-time 30 \
		https://opencode.ai/zen/go/v1/responses \
		-H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
		-H "User-Agent: $UA" -H "x-opencode-session: geo-test" \
		-d '{"model":"gpt-6-luna","input":"hi","max_output_tokens":16}')
	if [ "$code" = "200" ]; then
		printf "%-24s %-6s %s\n" "$node" "$code" "OK"
	else
		msg=$(grep -o 'unsupported_country_region_territory' /tmp/geo-resp.json 2>/dev/null)
		[ -z "$msg" ] && msg=$(head -c 90 /tmp/geo-resp.json)
		printf "%-24s %-6s %s\n" "$node" "$code" "$msg"
	fi
done

curl -s -X PUT "$API/configs?force=true" -H "Content-Type: application/json" \
	-d "{\"path\":\"$CFG\"}" >/dev/null
rm -f "$TESTCFG" /tmp/geo-resp.json
echo done
