#!/bin/sh
# 更新 AI 服务分流规则
# 源: MetaCubeX/meta-rules-dat  geosite category-ai-chat-!cn  (meta 分支, 日更)
# 目标: /etc/ShellCrash/yamls/rules.yaml  (ShellCrash 会把它插到 rules: 最前面)
# 用法: sh /etc/ShellCrash/ai-rules-update.sh
#       之后重启生效: /etc/ShellCrash/start.sh start
#
# 注意：opencode.ai（模型 API）固定指向 "🤖 AI接口" 专用组；
#       z.ai / bigmodel.cn（ZCode 账号/项目 Token）固定直连，避免落到默认代理
#       的香港出口（2026-10-22 实测：直连 0.34s，默认代理下 project token 15s 超时）。
#       这些覆盖必须写在最前面；opencode.ai 生成时跳过 geosite 同名条目，
#       z.ai/bigmodel.cn 靠“顶部优先 + 同键去重”保留。
#       Google 服务（Play/更新/FCM）固定指向 "🚀 节点选择"，
#       避免模板里 DOMAIN-SUFFIX,googleapis.com 把整段域带去 AI 组。
#       末尾的“分类修正层”用于修正模板 ai.list/ProxyLite/ChinaDomain 的
#       过宽规则与顺序冲突，必须保持在模板规则之前。

SRC="https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo/geosite/category-ai-chat-!cn.yaml"
OUT=/etc/ShellCrash/yamls/rules.yaml
GROUP="🤖 人工智能"
API_GROUP="🤖 AI接口"
GOOGLE_GROUP="🚀 节点选择"
# 干净出口组：唯一经 Google cc 实测判为非 CN 的稳定出口（印度）
CL="🤖 干净出口"
# AI_GROUP：Google 全家桶（API 族 + googleapis.com 宽泛域）统一走 AI 组，
# 保证同一个 Google 会话只有一个出口 IP，且该组不含被 Google 反滥用拦截的
# 香港WAP/加拿大/英国出口（那三个会 302 到 google.com/sorry/index）
AI_GROUP="🤖 人工智能"
TMP=/tmp/ai-rules-$$.yaml

uclient-fetch -q -O "$TMP" -T 30 "$SRC" 2>/dev/null
if [ ! -s "$TMP" ] || ! grep -q "payload:" "$TMP"; then
	echo "下载或校验失败，未做任何修改"
	rm -f "$TMP"
	exit 1
fi

{
	echo "# AI 服务分流规则 — 由 MetaCubeX/meta-rules-dat geosite category-ai-chat-!cn 生成"
	echo "# 更新于 $(date '+%Y-%m-%d %H:%M:%S')"
	echo "# 同键规则已去重（保留首次出现；顶部覆盖优先）"
	echo "# ===== G. 高带宽直连（省机场流量，2026-10-21）====="
	echo "# 模板把这些域名送进代理组，但它们在国内有可用 CDN，实测直连更快："
	echo "#   dl.google.com   → 🤖 干净出口（DOMAIN-SUFFIX,google.com）Chrome/Play/Android SDK 下载"
	echo "#   gvt1.com        → 🤖 干净出口（DOMAIN-SUFFIX,gvt1.com）  Chrome/Play 更新重定向"
	echo "#   gvt1-cn.com     → 🐟 漏网之鱼（不在 cn.mrs）             Google 中国 CDN 载荷"
	echo "#   jetbrains.com   → 🐟 漏网之鱼                            IDE/插件下载"
	echo "# 实测（路由器 WAN 直连 vs 127.0.0.1:7890，Range 3MB）："
	echo "#   dl.google.com 4.98 vs 1.76 MB/s；gvt1→gvt1-cn 4.45 MB/s；download.jetbrains.com 3.42 vs 0.48 MB/s"
	echo "# 反例（实测代理更快，保持代理）：nodejs.org 0.86 vs 3.25、cdn.jsdelivr.net 0.48 vs 1.74、"
	echo "#   shared.akamai.steamstatic.com 8.7 vs 83 KB/s、repo.anaconda.com 0.81 vs 2.32 MB/s"
	echo "- DOMAIN,dl.google.com,🎯 全球直连"
	echo "- DOMAIN-SUFFIX,gvt1.com,🎯 全球直连"
	echo "- DOMAIN-SUFFIX,gvt1-cn.com,🎯 全球直连"
	echo "- DOMAIN-SUFFIX,jetbrains.com,🎯 全球直连"
	echo "# 模型 API / 账号 Token（必须排在 geosite 规则之前）"
	echo "- DOMAIN-SUFFIX,opencode.ai,${API_GROUP}"
	echo "# ZCode 账号/项目 Token：直连，避免默认代理（香港出口）拖到 15s 超时"
	echo "- DOMAIN-SUFFIX,z.ai,🎯 全球直连"
	echo "- DOMAIN-SUFFIX,bigmodel.cn,🎯 全球直连"
	echo "# Google 服务统一出口（必须排在 geosite 规则和模板 googleapis 规则之前）"
	echo "- DOMAIN-SUFFIX,play.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,android.clients.google.com,$CL"
	echo "- DOMAIN-SUFFIX,android.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,update.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,safebrowsing.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,fcm.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,fcmregistrations.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,firebaseinstallations.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,www.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,gemini.google.com,$CL"
	echo "- DOMAIN-SUFFIX,gemini.gstatic.com,$CL"
	echo "- DOMAIN-SUFFIX,gemini.google,$CL"
	echo "- DOMAIN,geminiweb-pa.clients.google.com,$CL"
	echo "- DOMAIN,geminiweb-pa.clients6.google.com,$CL"
	echo "- DOMAIN-SUFFIX,generativelanguage.googleapis.com,$CL"
	awk -v g="$GROUP" '
	  /opencode\.ai/ { next }
	  /^[[:space:]]*-[[:space:]]*/ {
	    s=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",s);
	    if (s ~ /^\+\./)      { sub(/^\+\./,"",s); print "- DOMAIN-SUFFIX," s "," g }
	    else if (s ~ /^\*\./) { sub(/^\*\./,"",s); print "- DOMAIN-SUFFIX," s "," g }
	    else if (s ~ /^[A-Za-z0-9]/) { print "- DOMAIN," s "," g }
	  }' "$TMP"
	echo "# ===== 分类修正层（必须在所有模板规则之前，顺序敏感）====="
	echo "# A. 广告/追踪优先（必须早于宽泛 bing/googleapis/facebook）"
	echo "- DOMAIN-SUFFIX,bat.bing.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,analytics.google.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,2mdn.net,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,clickserve.dartsearch.net,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,connect.facebook.net,🛑 广告拦截"
	echo "#GEMINI_E_BLOCK_MARKER Gemini/Google 关键端点统一出口（必须早于 IP-CIDR 与模板 DOMAIN-KEYWORD,google）"
	echo "# 这些端点若落到 IP-CIDR 203.208.32.0/19 或 DOMAIN-KEYWORD,google，会以中国出口 IP 访问，Google 即判定为中国区"
	echo "- DOMAIN-SUFFIX,gstatic.com,$CL"
	echo "- DOMAIN-SUFFIX,gvt1.com,$CL"
	echo "- DOMAIN-SUFFIX,gvt2.com,$CL"
	echo "- DOMAIN-SUFFIX,gvt3.com,$CL"
	echo "- DOMAIN-SUFFIX,clients.google.com,$CL"
	echo "- DOMAIN-SUFFIX,clients2.google.com,$CL"
	echo "- DOMAIN-SUFFIX,clients3.google.com,$CL"
	echo "- DOMAIN-SUFFIX,clients4.google.com,$CL"
	echo "- DOMAIN-SUFFIX,clients5.google.com,$CL"
	echo "- DOMAIN-SUFFIX,clients6.google.com,$CL"
	echo "- DOMAIN-SUFFIX,clients.l.google.com,$CL"
	echo "- DOMAIN,accounts.google.com,$CL"
	echo "- DOMAIN,oauth2.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,tools.google.com,$CL"
	echo "- DOMAIN,mtalk.google.com,$CL"
	echo "- DOMAIN-SUFFIX,generativelanguage.googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,gemini.google.com,$CL"
	echo "- DOMAIN-SUFFIX,gemini.gstatic.com,$CL"
	echo "- DOMAIN-SUFFIX,googleusercontent.com,$CL"
	echo "- DOMAIN-SUFFIX,google.com,$CL"
	echo "- DOMAIN-KEYWORD,google,$CL"
	echo "- DOMAIN-SUFFIX,googleapis.com,$CL"
	echo "- DOMAIN-SUFFIX,googletagmanager.com,$CL"
	echo "#CLEAN_EXIT_BLOCK_MARKER 2026-10-20: Google 残留域族 / GFE 段 / YouTube 全族 → 干净出口（印度）"
	echo "# ===== E. 干净出口（Google 残留域族 / GFE 段 / YouTube 全族）====="
	echo "# 这些域在模板里会落到通用池（🚀 节点选择 / 🌍 国外媒体），而通用池的出口被 Google 判为 CN。"
	echo "# 统一改指干净出口（印度），保证一次 Google 会话只有一个出口 IP。"
	echo "- DOMAIN-KEYWORD,gmail,$CL"
	echo "- DOMAIN-KEYWORD,1e100,$CL"
	echo "- DOMAIN-KEYWORD,blogspot,$CL"
	echo "- DOMAIN-SUFFIX,googleapis.cn,$CL"
	echo "- DOMAIN-SUFFIX,gstatic.cn,$CL"
	echo "- DOMAIN-SUFFIX,gvt0.com,$CL"
	echo "- DOMAIN-SUFFIX,g.co,$CL"
	echo "- DOMAIN-SUFFIX,goo.gl,$CL"
	echo "- DOMAIN-SUFFIX,gcr.io,$CL"
	echo "- DOMAIN-SUFFIX,ggpht.com,$CL"
	echo "- DOMAIN-SUFFIX,c.gle,$CL"
	echo "- DOMAIN-SUFFIX,appspot.com,$CL"
	echo "- DOMAIN-SUFFIX,blogger.com,$CL"
	echo "- DOMAIN-SUFFIX,android.com,$CL"
	echo "- DOMAIN-SUFFIX,firebaseio.com,$CL"
	echo "- DOMAIN-SUFFIX,google.com.hk,$CL"
	echo "- DOMAIN-SUFFIX,1e100.net,$CL"
	echo "- IP-CIDR,74.125.0.0/16,$CL"
	echo "- IP-CIDR,173.194.0.0/16,$CL"
	echo "- DOMAIN-SUFFIX,youtube.com,$CL"
	echo "- DOMAIN-SUFFIX,googlevideo.com,$CL"
	echo "- DOMAIN-SUFFIX,ytimg.com,$CL"
	echo "- DOMAIN-SUFFIX,youtu.be,$CL"
	echo "- DOMAIN-SUFFIX,youtube-nocookie.com,$CL"
	echo "- DOMAIN,youtubei.googleapis.com,$CL"
	echo "- DOMAIN,yt3.ggpht.com,$CL"
	echo "# ===== F. GitHub 统一出口（2026-10-21）====="
	echo "# 日本入口对 github.com 有约 20% 的 TLS 握手尖刺（1.4–7s），印度入口 40 次 0 尖刺。"
	echo "# 模板里这些域走 DOMAIN-KEYWORD,github / DOMAIN-SUFFIX,github.com（🚀 节点选择 → 🛟 主备自动 → ♻️ 自动选择），"
	echo "# 会随机落到日本节点，必须在这里提前截走。"
	echo "# 例外：geosite AI 列里的 copilot-* 子域排在本段之前，仍走 🤖 人工智能。"
	echo "- DOMAIN,api.github.com,$CL"
	echo "- DOMAIN-SUFFIX,github.com,$CL"
	echo "- DOMAIN-SUFFIX,githubusercontent.com,$CL"
	echo "- DOMAIN-SUFFIX,githubassets.com,$CL"
	echo "- DOMAIN-SUFFIX,githubapp.com,$CL"
	echo "# AI 关键字兜底：模板里这三条被更早的规则遮蔽，放到自定义块最前才生效"
	echo "- DOMAIN-KEYWORD,claude,🤖 人工智能"
	echo "- DOMAIN-KEYWORD,anthropic,🤖 人工智能"
	echo "- DOMAIN-KEYWORD,openai,🤖 人工智能"
	echo "# B. AI 语义修正（共享 SaaS 不绑定 AI 组；具体规则必须早于宽泛 sentry.io）"
	echo "- DOMAIN,o33249.ingest.sentry.io,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,disney.my.sentry.io,🎥 DisneyP"
	echo "- DOMAIN-SUFFIX,sentry.io,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,sydney.bing.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,edgeservices.bing.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,replicate.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,together.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,intercom.io,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,featuregates.org,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,statsigapi.net,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,cdn.auth0.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,opendns.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,opera-api.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,googleapis.com,🚀 节点选择"
	echo "# C. 服务一致性"
	echo "- DOMAIN-SUFFIX,bing.com,Ⓜ️ 微软服务"
	echo "- DOMAIN-SUFFIX,xbox.com,Ⓜ️ 微软服务"
	echo "- DOMAIN-SUFFIX,onedrive.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,onedrive.live.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,storage.live.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,skydrive.wns.windows.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,sharepoint.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,sharepointonline.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,photos.live.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,ai.azure.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,openai.azure.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,cognitiveservices.azure.com,🤖 人工智能"
	echo "# D. CN 直连与宽泛代理冲突"
	echo "- DOMAIN-SUFFIX,tmall.hk,🎯 全球直连"
	echo "- DOMAIN-SUFFIX,jd.hk,🎯 全球直连"
	echo "- DOMAIN,cm.steampowered.com,🎯 全球直连"
	echo "- IP-CIDR,203.208.32.0/19,🎯 全球直连,no-resolve"
	echo "- IP-CIDR6,2401:3800::/32,🎯 全球直连,no-resolve"
} | awk '
	# 同一 (类型, 域名) 只保留第一次出现。顶部覆盖（opencode / Google 服务）
	# 在最前面，所以后面 geosite 与修正层里的同键规则会被丢掉。
	/^- / {
		line=$0
		sub(/^-[[:space:]]*/, "", line)
		split(line, a, ",")
		key=a[1] "," a[2]
		if (seen[key]++) next
	}
	{ print }
' > "$OUT.tmp" #ATOMIC_WRITE_MARKER 先写临时文件，校验通过再 mv 覆盖，避免更新被中断时截断 rules.yaml

n=$(grep -c "^- " "$OUT.tmp")
rm -f "$TMP"
if [ "$n" -lt 50 ]; then
	echo "警告: 规则条数异常($n)，请检查 $OUT.tmp"
	exit 1
fi
if ! grep -q "opencode.ai,${API_GROUP}" "$OUT.tmp"; then
	echo "警告: opencode.ai 覆盖规则丢失，请检查 $OUT.tmp"
	exit 1
fi
if ! grep -q "z.ai,🎯 全球直连" "$OUT.tmp"; then
	echo "警告: z.ai 直连覆盖规则丢失，请检查 $OUT.tmp"
	exit 1
fi
if ! grep -q "bigmodel.cn,🎯 全球直连" "$OUT.tmp"; then
	echo "警告: bigmodel.cn 直连覆盖规则丢失，请检查 $OUT.tmp"
	exit 1
fi
if ! grep -q "play.googleapis.com,$CL" "$OUT.tmp"; then
	echo "警告: Google 出口覆盖规则丢失，请检查 $OUT.tmp"
	exit 1
fi
if ! grep -q "googleapis.com,$CL" "$OUT.tmp" || ! grep -q "bing.com,Ⓜ️ 微软服务" "$OUT.tmp"; then
	echo "警告: 分类修正层丢失，请检查 $OUT.tmp"
	exit 1
fi
if ! grep -q "DOMAIN-SUFFIX,github.com,$CL" "$OUT.tmp" || ! grep -q "DOMAIN-SUFFIX,githubusercontent.com,$CL" "$OUT.tmp"; then
	echo "警告: GitHub 出口覆盖规则丢失（可能被 geosite 同名规则去重掉），请检查 $OUT.tmp"
	exit 1
fi
if ! grep -q "DOMAIN,dl.google.com,🎯 全球直连" "$OUT.tmp" ||
   ! grep -q "DOMAIN-SUFFIX,gvt1.com,🎯 全球直连" "$OUT.tmp" ||
   ! grep -q "DOMAIN-SUFFIX,gvt1-cn.com,🎯 全球直连" "$OUT.tmp" ||
   ! grep -q "DOMAIN-SUFFIX,jetbrains.com,🎯 全球直连" "$OUT.tmp"; then
	echo "警告: 高带宽直连段丢失（可能被上游规则去重），请检查 $OUT.tmp"
	exit 1
fi
mv -f "$OUT.tmp" "$OUT"
echo "已更新 $n 条 AI/Google/修正规则 -> $OUT"
echo "重启服务生效: /etc/ShellCrash/start.sh start"
