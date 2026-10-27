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
# 干净出口组：只服务 Google 家族（cc≠CN + Gemini 吞吐都合格）
CL="🤖 干净出口"
# GitHub 组：只服务 GitHub 家族，url-test 拿 github.com/robots.txt 做健康检查，
# 节点握手开始抖就自动换（见 config/yamls/proxy-groups.yaml）。
# 2026-10-22 拆开的原因：干净出口按 Gemini 吞吐选到了到 GitHub 0/5 的 HY2 节点，
# GitHub 全族跟着时通时断 —— 两者需要的能力不同，不能共用一个组。
GH="🔗 GitHub 出口"
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
	echo "# ===== X. 𝕏 媒体（twimg.com 走 HY2，2026-10-23）====="
	echo "# X/Twitter 图片 CDN 的并发建连在 VMess+WS 上会被串行化："
	echo "#   2026-10-23 实测 10 并发真实图片，VMess 墙钟 1.9–5.9s、偶发单张 5–6s；"
	echo "#   HY2（QUIC 多路复用）墙钟 0.35s、单张 0.21–0.25s。"
	echo "# 单请求延迟看不出差异（HY2 89ms vs VMess 65ms），不能用延迟选路；"
	echo "#   策略组 𝕏 媒体 只收 HY2 节点，健康检查用同域 robots.txt（200）。"
	echo "- DOMAIN-SUFFIX,twimg.com,𝕏 媒体"
	echo "# ===== X2. Civitai（主站代理 / 图片 CDN 公共池，2026-10-23）====="
	echo "# 主站有账号/上传，不能过公共节点；图片 CDN 无登录态，放公共池省机场流量。"
	echo "# 顺序不能反：image.civitai.com 必须先于 civitai.com 命中。"
	echo "- DOMAIN-SUFFIX,image.civitai.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,civitai.com,🚀 节点选择"
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
	echo "# 2026-10-23 补充（只收实测直连更快/国内 CDN 的域）："
	echo "#   hf-mirror.com   HuggingFace 国内镜像，Range 4MB 实测 2.42 vs 代理 0.65 MB/s"
	echo "#   kuaishouzt.com / images-cn.ssl-images-amazon.com  国内静态/图片 CDN"
	echo "# 反例（实测直连更差，不要加）：cn.download.nvidia.com 直连 403（跳到 .cn 后仍 403），"
	echo "#   代理 3.2 MB/s；gstatic-cn.com 两边都 000；recaptcha-cn.net 直连 1.6s vs 代理 0.27s。"
	echo "- DOMAIN-SUFFIX,hf-mirror.com,🎯 全球直连"
	echo "- DOMAIN-SUFFIX,kuaishouzt.com,🎯 全球直连"
	echo "- DOMAIN-SUFFIX,images-cn.ssl-images-amazon.com,🎯 全球直连"
	echo "# ===== G2. Steam 下载（2026-10-27 走国内 CDN）====="
	echo "# 2026-10-27 实测：Steam 的内容服务器目录按「客户端公网 IP」分配 CDN。"
	echo "#   CM（*.steamserver.net）走代理时，Valve 认为客户端在境外，只给 cache*-hkg1 /"
	echo "#   tyo3（实测 43–183 Mbps）；CM 改直连后 Valve 看到真实国内 IP，分配国内 CDN"
	echo "#   （st.dl.eccdnx.com / dl.steam.clngaa.com / xz.pphimalayanrt.com），"
	echo "#   实测 375–390 Mbps —— 这些 IP 是 CN 段，在防火墙层就绕过 mihomo 走硬件转发。"
	echo "# 关键：steamserver.net 必须直连，它决定 Valve 看到的客户端 IP。"
	echo "# api.steampowered.com 是内容服务器目录接口，直连可达（偶发超时，客户端会自动重试），"
	echo "#   它的 DNS 必须走国内解析（见 starts/clash_modify.sh 的 nameserver-policy）。"
	echo "# steamcontent.com 保留 DIRECT 作为 SteamCache 兜底；steamstatic / steamcdn-a /"
	echo "#   steampipe 是商店静态资源与客户端安装包，直连实测更差（见 G 段反例），留在机场组。"
	echo "- DOMAIN-SUFFIX,steamserver.net,DIRECT"
	echo "- DOMAIN,api.steampowered.com,DIRECT"
	echo "- DOMAIN-SUFFIX,eccdnx.com,DIRECT"
	echo "- DOMAIN-SUFFIX,clngaa.com,DIRECT"
	echo "- DOMAIN-SUFFIX,pphimalayanrt.com,DIRECT"
	echo "- DOMAIN-SUFFIX,steamcontent.com,DIRECT"
	echo "- DOMAIN-SUFFIX,steamstatic.com,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,steamcdn-a.akamaihd.net,🚀 节点选择"
	echo "- DOMAIN,steampipe.akamaized.net,🚀 节点选择"
	echo "- DOMAIN,steampipe-kr.akamaized.net,🚀 节点选择"
	echo "# ===== H. 大流量（公共池承载，2026-10-22）====="
	echo "# 已知的大文件下载域走 📺 大流量：该组默认 🆓 公共备用，"
	echo "# bulk-guard.sh 实测吞吐低于阈值时切回 ♻️ 自动选择（见 OpenwrtOpsToolkit）。"
	echo "# 视频域刻意不进来：YouTube 全族必须走干净出口（Google cc 判定），"
	echo "#   Netflix/Disney 对公共节点几乎必然判代理。"
	echo "# proof.ovh.net 同时是 bulk-guard.sh 的探测域（Range 取前 4MB），必须固定在本组。"
	echo "- DOMAIN-SUFFIX,epicgames-download1.akamaized.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,download.epicgames.com,📺 大流量"
	echo "# 2026-10-23 补充 Epic/Steam 下载 CDN（Aethersailor / MetaCubeX）："
	echo "#   这些域在模板里分别落到 ChinaDomain 直连（Epic 403）或 MATCH，补进来才能走公共池。"
	echo "- DOMAIN,download2.epicgames.com,📺 大流量"
	echo "- DOMAIN,download3.epicgames.com,📺 大流量"
	echo "- DOMAIN,download4.epicgames.com,📺 大流量"
	echo "- DOMAIN,fastly-download.epicgames.com,📺 大流量"
	echo "- DOMAIN,cloudflare.epicgamescdn.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,egdownload.fastly-edge.com,📺 大流量"
	echo "- DOMAIN,proof.ovh.net,📺 大流量"
	echo "# ===== I. 视频站点 + Telegram（大流量，2026-10-22）====="
	echo "# 纯下载型视频流量（成人站 + Telegram 媒体）走公共池："
	echo "#   这些站不绑定账号/支付出口，HTTPS/MTProto 加密，公共节点看不到内容。"
	echo "#   注意：只进大站与其自有 CDN，不碰通用 CDN（cdn77 等）—— 那会把无关流量拖进来。"
	echo "#   未列到的小站由上游 category-porn 规则集兜底（provider 由 rules-porn.sh 注入）。"
	echo "# Telegram 的媒体与消息走同一条 MTProto 连接，无法只挑视频；"
	echo "#   要接就整段接（两个 DC 段）。若公共节点被 Telegram 限制，面板里切回即可。"
	echo "- RULE-SET,porn,📺 大流量"
	echo "- DOMAIN-KEYWORD,porn,📺 大流量"
	echo "- DOMAIN-SUFFIX,pornhub.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,pornhubpremium.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,phncdn.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,xvideos.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,xvideos2.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,xvideos-cdn.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,xnxx.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,xnxx-cdn.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,xhamster.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,xhcdn.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,redtube.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,rdcdn.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,youporn.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,ypcdn.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,spankbang.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,spankbang.party,📺 大流量"
	echo "- DOMAIN-SUFFIX,eporner.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,hqporner.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,txxx.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,thumbzilla.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,tube8.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,beeg.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,porntrex.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,cdn-telegram.org,📺 大流量"
	echo "- IP-CIDR,91.108.0.0/16,📺 大流量,no-resolve"
	echo "- IP-CIDR,149.154.160.0/20,📺 大流量,no-resolve"
	echo "# ===== I2. 媒体 CDN（公共池承载，2026-10-23）====="
	echo "# 只收无登录态的图片/视频 CDN；账号域（reddit.com / pixiv.net / twitch.tv）不进来。"
	echo "# 这些 CDN 可以走陌生人出口：传输的是公开媒体，不带 Cookie/Token。"
	echo "- DOMAIN-SUFFIX,i.redd.it,📺 大流量"
	echo "- DOMAIN-SUFFIX,v.redd.it,📺 大流量"
	echo "- DOMAIN-SUFFIX,preview.redd.it,📺 大流量"
	echo "- DOMAIN-SUFFIX,i.imgur.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,i.pximg.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,vimeocdn.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,dmcdn.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,ttvnw.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,static-cdn.jtvnw.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,sourceforge.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,replicate.delivery,📺 大流量"
	echo "# ===== J. B站（属地上国外、其余直连，2026-10-22）====="
	echo "# 目的：评论 / 主页的 IP 属地显示节点所在国家，视频仍走国内直连。"
	echo "# 属地由「发请求那一刻的源 IP」决定，没有独立检测接口 —— 只有让 API 真出国才改得了；"
	echo "#   页面 / 登录 / 静态 / 视频 CDN 必须直连，否则视频流量会绕到机场。"
	echo "# CDN 规则用字面 DIRECT，不用 🎯 全球直连 组：respect-rules 的 DNS 只有"
	echo "#   对字面 DIRECT 才走 direct-nameserver（AliDNS/DoH.pub）；用组会落到默认"
	echo "#   nameserver（Cloudflare/Google DoH），解析到海外 Akamai 边缘，实测 28 KB/s。"
	echo "# 只有这三族与属地有关，走 🎬 B站解锁："
	echo "#   api.bilibili.com   web 评论 / 空间 / zone"
	echo "#   biliapi.com/.net   App（grpc 上评论与 playurl 同域，拆不开）"
	echo "# HY2 池到大陆方向不通（香港/韩国能连 gstatic，但百度/知乎/B站全部 TLS EOF/超时）；"
	echo "#   vmess 池的 香港WAP/台湾-优化3/日本-优化/新加坡-优化3 可正常访问，"
	echo "#   B站 zone 分别显示对应地区。"
	echo "# 下面四个不参与属地，直连：每个新连接少一次隧道往返。"
	echo "#   实测（2026-10-22，api.bilibili.com）：经香港 TLS 0.42–1.29s / TTFB 0.57–1.57s，"
	echo "#   直连 TTFB 0.11s —— 动态 / 直播 / App 启动每开一个连接都要付这笔钱。"
	echo "#   app.bilibili.com      App 启动配置 / 版本 / 开屏"
	echo "#   cm.bilibili.com       广告投放"
	echo "#   api.vc.bilibili.com   动态 / 关注 / 私信（显示的是他人属地）"
	echo "#   api.live.bilibili.com 直播房间 API（弹幕与开播信息不含自身属地）"
	echo "# 模板本来就把 bilibili 全族直连，这里显式写一遍，避免模板更新后落到 MATCH。"
	echo "- DOMAIN-SUFFIX,api.bilibili.com,🎬 B站解锁"
	echo "- DOMAIN-SUFFIX,biliapi.com,🎬 B站解锁"
	echo "- DOMAIN-SUFFIX,biliapi.net,🎬 B站解锁"
	echo "- DOMAIN-SUFFIX,app.bilibili.com,DIRECT"
	echo "- DOMAIN-SUFFIX,cm.bilibili.com,DIRECT"
	echo "- DOMAIN-SUFFIX,api.vc.bilibili.com,DIRECT"
	echo "- DOMAIN-SUFFIX,api.live.bilibili.com,DIRECT"
	echo "- DOMAIN-SUFFIX,bilibili.com,DIRECT"
	echo "- DOMAIN-SUFFIX,bilibili.co,DIRECT"
	echo "- DOMAIN-SUFFIX,bilivideo.com,DIRECT"
	echo "- DOMAIN-SUFFIX,bilivideo.cn,DIRECT"
	echo "- DOMAIN-SUFFIX,hdslb.com,DIRECT"
	echo "- DOMAIN-SUFFIX,biliimg.com,DIRECT"
	echo "- DOMAIN-SUFFIX,acgvideo.com,DIRECT"
	echo "- DOMAIN-SUFFIX,acg.tv,DIRECT"
	echo "- DOMAIN-SUFFIX,b23.tv,DIRECT"
	echo "- DOMAIN,upos-hz-mirrorakam.akamaized.net,DIRECT"
	echo "# ===== K. 大流量补充：模型 / 发布包 / 驱动 / 游戏补丁（2026-10-22）====="
	echo "# 实测（路由器 → proof.ovh.net Range 4MB）：公共池 1.56 / 1.45 MB/s，"
	echo "#   机场 0.83 / 1.27 MB/s —— 公共池不慢于机场，适合大文件。"
	echo "# 入选标准：无登录态、内容有签名或哈希、可断点续传。"
	echo "# 刻意不收："
	echo "#   npm / PyPI / crates —— 大量小文件，公共节点 200-600ms 延迟反而更慢；"
	echo "#   Docker Hub —— 按 IP 限流，公共节点共享 IP 大概率 429；"
	echo "#   Apple / Microsoft 更新 —— 这两家的 CDN 已解析到国内节点，走代理只会更慢；"
	echo "#   Netflix / Disney —— DRM + 代理检测；"
	echo "#   任何登录、上传、P2P 流量。"
	echo "# 模型权重：huggingface.co 整族在 AI 组，GB 级 LFS 下载会占满 AI 出口；只摘 CDN。"
	echo "#   实测 resolve 后落到 us.aws.cdn.hf.co（不是 cdn-lfs.*），所以 cdn.hf.co 必须整段收。"
	echo "- DOMAIN-SUFFIX,cdn-lfs.huggingface.co,📺 大流量"
	echo "- DOMAIN-SUFFIX,cdn-lfs.hf.co,📺 大流量"
	echo "- DOMAIN-SUFFIX,cdn.hf.co,📺 大流量"
	echo "- DOMAIN-SUFFIX,cdn-lfs-us-1.hf.co,📺 大流量"
	echo "- DOMAIN-SUFFIX,cdn-lfs-eu-1.hf.co,📺 大流量"
	echo "- DOMAIN-SUFFIX,cas-bridge.xethub.hf.co,📺 大流量"
	echo "# GitHub 发布包：整族原本走干净出口（单条节点），几百 MB 的 release 会把它占死。"
	echo "#   只摘下载域；api.github.com / github.com 必须留在 $GH（见 F 段）。"
	echo "- DOMAIN-SUFFIX,objects.githubusercontent.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,release-assets.githubusercontent.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,codeload.github.com,📺 大流量"
	echo "# 驱动：NVIDIA / AMD 都是 Akamai 海外节点；AMD 直链国内被 EdgeOne 拦 567。"
	echo "- DOMAIN-SUFFIX,us.download.nvidia.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,international.download.nvidia.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,drivers.amd.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,download.amd.com,📺 大流量"
	echo "# 游戏平台补丁（Steam / Epic 见 H 段）：补丁几十 GB，全部签名。"
	echo "#   已剔除 NXDOMAIN 的 blizzard.vo.llnwd.net / ubisoft-a.akamaihd.net / riotcdn.net。"
	echo "- DOMAIN-SUFFIX,blzddist1-a.akamaihd.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,blzddist2-a.akamaihd.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,blzddist3-a.akamaihd.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,cdn.gog.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,gog-cdn-fastly.gog.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,origin-a.akamaihd.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,eaassets-a.akamaihd.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,ubistatic-a.akamaihd.net,📺 大流量"
	echo "# 2026-10-23 补充游戏平台补丁 CDN（MetaCubeX category-game-platforms-download）："
	echo "#   只收补丁/资源域，登录与商店域保持在通用代理；全部有签名/可续传。"
	echo "- DOMAIN-SUFFIX,cdn.blizzard.com,📺 大流量"
	echo "- DOMAIN,blzddistkr1-a.akamaihd.net,📺 大流量"
	echo "- DOMAIN,prod.cloudflare.cdn.ea.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,dyn.riotcdn.net,📺 大流量"
	echo "- DOMAIN,gamedownloads-rockstargames-com.akamaized.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,cdp.bethesda.net,📺 大流量"
	echo "- DOMAIN-SUFFIX,uplaypc-s-ubisoft.cdn.ubi.com,📺 大流量"
	echo "- DOMAIN,assets1.xboxlive.com,📺 大流量"
	echo "- DOMAIN,assets2.xboxlive.com,📺 大流量"
	echo "- DOMAIN-SUFFIX,gog-cdn.akamaized.net,📺 大流量"
	echo "# Maven 中央仓库：单个 jar 几十 MB，无 IP 限流。"
	echo "- DOMAIN-SUFFIX,repo1.maven.org,📺 大流量"
	echo "- DOMAIN-SUFFIX,repo.maven.apache.org,📺 大流量"
	echo "# 模型 API / 账号 Token（必须排在 geosite 规则之前）"
	echo "- DOMAIN-SUFFIX,opencode.ai,${API_GROUP}"
	echo "# ZCode 账号/项目 Token：直连，避免默认代理（香港出口）拖到 15s 超时"
	echo "- DOMAIN-SUFFIX,z.ai,🎯 全球直连"
	echo "- DOMAIN-SUFFIX,bigmodel.cn,🎯 全球直连"
	echo "# ===== M. AI 补充（VPSDance/ai-proxy-rules + MetaCubeX，2026-10-23）====="
	echo "# 只收 provider 自有域；共享 SaaS/CDN（auth0/sentry/statsig/aws/azure 共享域）不进来，"
	echo "# 否则同一个登录会话的出口会分裂。geosite 里已有的同键规则会被顶部去重丢掉。"
	echo "- DOMAIN-SUFFIX,ai.com,🤖 人工智能"
	echo "- DOMAIN-KEYWORD,chatgpt-async-webps-prod,🤖 人工智能"
	echo "- DOMAIN,openai-api.arkoselabs.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,modelcontextprotocol.io,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,together.xyz,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,deepinfra.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,fireworks.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,novita.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,bfl.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,stability.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,runway.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,runwayml.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,suno.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,suno.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,udio.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,character.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,you.com,🤖 人工智能"
	echo "# 生成/编码类（按 provider 自有域；共享 CDN 不收）"
	echo "- DOMAIN-SUFFIX,ideogram.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,leonardo.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,lumalabs.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,pika.art,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,recraft.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,heygen.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,synthesia.io,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,descript.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,gamma.app,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,genspark.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,lmarena.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,phind.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,otter.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,cline.bot,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,continue.dev,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,sourcegraph.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,cody.dev,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,ampcode.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,zed.dev,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,kilo.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,commandcode.ai,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,tabnine.com,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,v0.app,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,bolt.new,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,lovable.dev,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,replit.com,🤖 人工智能"
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
	echo "# 共享 SaaS / 非 AI 域（上游 geosite 误收；必须早于 geosite 同名规则）"
	echo "# Envato/ThemeForest 是素材市场，LivePerson 是客服聊天，Datadog 是 RUM —— 都不绑定 AI 出口"
	echo "- DOMAIN-SUFFIX,envato.com,$GOOGLE_GROUP"
	echo "- DOMAIN-SUFFIX,envato-static.com,$GOOGLE_GROUP"
	echo "- DOMAIN-SUFFIX,envatousercontent.com,$GOOGLE_GROUP"
	echo "- DOMAIN-SUFFIX,themeforest.net,$GOOGLE_GROUP"
	echo "- DOMAIN-SUFFIX,liveperson.net,$GOOGLE_GROUP"
	echo "- DOMAIN-SUFFIX,lpsnmedia.net,$GOOGLE_GROUP"
	echo "- DOMAIN,browser-intake-datadoghq.com,$GOOGLE_GROUP"
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
	echo "# A2. Google 广告/追踪 carve-out（必须在 google.com / DOMAIN-KEYWORD,google 之前）"
	echo "# 宽泛 google 规则会把这些模板 REJECT 整段抢走；实测 pagead2/google-analytics"
	echo "# 曾走 🤖 干净出口并真实下载 59–63 KB。doubleclick.net 同时挡住 googleads.* 子域。"
	echo "- DOMAIN-SUFFIX,doubleclick.net,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,googlesyndication.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,googleadservices.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,google-analytics.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,googleadsserving.cn,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,ads.google.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,adservice.google.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,pagead.google.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,pagead.l.google.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,pagead-tpc.l.google.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,mobileads.google.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,afd.l.google.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,badad.googleplex.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,csi.gstatic.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,collector.githubapp.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,app-measurement.com,🛑 广告拦截"
	echo "# 2026-10-23 补充国内变体（模板 BanAD 只覆盖非 -cn 变体）"
	echo "- DOMAIN-SUFFIX,2mdn-cn.net,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,doubleclick-cn.net,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,dartsearch-cn.net,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,admob-cn.com,🛑 广告拦截"
	echo "- DOMAIN-SUFFIX,app-measurement-cn.com,🛑 广告拦截"
	echo "# GTM/GTS 是共享标签管理器：不绑 Google 账号出口，走通用代理"
	echo "- DOMAIN-SUFFIX,googletagmanager.com,$GOOGLE_GROUP"
	echo "- DOMAIN-SUFFIX,googletagservices.com,$GOOGLE_GROUP"
	echo "# googlecommerce.com 保留代理（Google Shopping/Merchant，不一定是广告）"
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
	echo "# no-resolve：这两条是兜底，不应为了匹配而触发真实 DNS 解析（fake-ip 下无意义且拖慢）"
	echo "- IP-CIDR,74.125.0.0/16,$CL,no-resolve"
	echo "- IP-CIDR,173.194.0.0/16,$CL,no-resolve"
	echo "- DOMAIN-SUFFIX,youtube.com,$CL"
	echo "- DOMAIN-SUFFIX,googlevideo.com,$CL"
	echo "- DOMAIN-SUFFIX,ytimg.com,$CL"
	echo "- DOMAIN-SUFFIX,youtu.be,$CL"
	echo "- DOMAIN-SUFFIX,youtube-nocookie.com,$CL"
	echo "- DOMAIN,youtubei.googleapis.com,$CL"
	echo "- DOMAIN,yt3.ggpht.com,$CL"
	echo "# ===== F. GitHub 统一出口（2026-10-21，2026-10-22 拆组）====="
	echo "# 模板里这些域走 DOMAIN-KEYWORD,github / DOMAIN-SUFFIX,github.com（🚀 节点选择 → 🛟 主备自动 → ♻️ 自动选择），"
	echo "# 会随机落到日本节点（日本入口约 20% TLS 握手尖刺 1.4–7s），必须在这里提前截走。"
	echo "# 2026-10-22：从 🤖 干净出口 拆到 $GH —— 干净出口按 Gemini 吞吐选节点，"
	echo "#   曾选到到 GitHub 0/5 的 HY2 节点，GitHub 全族跟着断。"
	echo "#   $GH 是 url-test，健康检查就是 github.com/robots.txt，节点抖了自动换。"
	echo "# 例外：geosite AI 列里的 copilot-* 子域排在本段之前，仍走 🤖 人工智能。"
	echo "- DOMAIN,api.github.com,$GH"
	echo "- DOMAIN-SUFFIX,github.com,$GH"
	echo "- DOMAIN-SUFFIX,githubusercontent.com,$GH"
	echo "- DOMAIN-SUFFIX,githubassets.com,$GH"
	echo "- DOMAIN-SUFFIX,githubapp.com,$GH"
	echo "# 2026-10-23：容器镜像域名不在 DOMAIN-KEYWORD,github 内，显式走 GitHub 出口"
	echo "- DOMAIN-SUFFIX,ghcr.io,$GH"
	echo "# AI 关键字兜底：模板里这三条被更早的规则遮蔽，放到自定义块最前才生效"
	echo "- DOMAIN-KEYWORD,claude,🤖 人工智能"
	echo "- DOMAIN-KEYWORD,anthropic,🤖 人工智能"
	echo "- DOMAIN-KEYWORD,openai,🤖 人工智能"
	echo "# B. AI 语义修正（共享 SaaS 不绑定 AI 组；具体规则必须早于宽泛 sentry.io）"
	echo "- DOMAIN,o33249.ingest.sentry.io,🤖 人工智能"
	echo "- DOMAIN-SUFFIX,disney.my.sentry.io,🎥 DisneyP"
	echo "# 2026-10-23：Disney 自有 CDN 补齐（blackmatrix7）"
	echo "- DOMAIN-SUFFIX,hotstar-cdn.net,🎥 DisneyP"
	echo "- DOMAIN-SUFFIX,dlp-media.com,🎥 DisneyP"
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
	echo "# 2026-10-23：Telegram 网页/媒体辅助域 + Twitch 视频辅助域"
	echo "- DOMAIN-SUFFIX,graph.org,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,tg.dev,🚀 节点选择"
	echo "- DOMAIN-SUFFIX,live-video.net,🌍 国外媒体"
	# googleapis.com 已在上方 Google 段指向干净出口；同键去重保留首次出现，
	# 这里不再输出（旧行是死规则，会误导阅读者以为它走节点选择）。
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
if ! grep -q "DOMAIN-SUFFIX,github.com,$GH" "$OUT.tmp" || ! grep -q "DOMAIN-SUFFIX,githubusercontent.com,$GH" "$OUT.tmp"; then
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
for r in "DOMAIN-SUFFIX,steamserver.net,DIRECT" \
         "DOMAIN,api.steampowered.com,DIRECT" \
         "DOMAIN-SUFFIX,eccdnx.com,DIRECT" \
         "DOMAIN-SUFFIX,clngaa.com,DIRECT" \
         "DOMAIN-SUFFIX,pphimalayanrt.com,DIRECT" \
         "DOMAIN-SUFFIX,steamcontent.com,DIRECT" \
         "DOMAIN-SUFFIX,steamstatic.com,🚀 节点选择" \
         "DOMAIN-SUFFIX,steamcdn-a.akamaihd.net,🚀 节点选择" \
         "DOMAIN-SUFFIX,epicgames-download1.akamaized.net,📺 大流量" \
         "DOMAIN-SUFFIX,download.epicgames.com,📺 大流量" \
         "DOMAIN,proof.ovh.net,📺 大流量" \
         "DOMAIN-SUFFIX,pornhub.com,📺 大流量" \
         "RULE-SET,porn,📺 大流量" \
         "DOMAIN-KEYWORD,porn,📺 大流量" \
         "DOMAIN-SUFFIX,xvideos-cdn.com,📺 大流量" \
         "DOMAIN-SUFFIX,cdn-telegram.org,📺 大流量" \
         "IP-CIDR,91.108.0.0/16,📺 大流量,no-resolve" \
         "IP-CIDR,149.154.160.0/20,📺 大流量,no-resolve"; do
	if ! grep -qF -- "- $r" "$OUT.tmp"; then
		echo "警告: 大流量段丢失: $r"
		exit 1
	fi
done
for r in "DOMAIN-SUFFIX,cdn-lfs.huggingface.co,📺 大流量" \
         "DOMAIN-SUFFIX,cdn.hf.co,📺 大流量" \
         "DOMAIN-SUFFIX,objects.githubusercontent.com,📺 大流量" \
         "DOMAIN-SUFFIX,codeload.github.com,📺 大流量" \
         "DOMAIN-SUFFIX,us.download.nvidia.com,📺 大流量" \
         "DOMAIN-SUFFIX,blzddist1-a.akamaihd.net,📺 大流量" \
         "DOMAIN-SUFFIX,repo1.maven.org,📺 大流量"; do
	if ! grep -qF -- "- $r" "$OUT.tmp"; then
		echo "警告: 大流量补充段丢失: $r"
		exit 1
	fi
done
for r in "DOMAIN,api.github.com,$GH" \
         "DOMAIN-SUFFIX,github.com,$GH" \
         "DOMAIN-SUFFIX,githubusercontent.com,$GH" \
         "DOMAIN-SUFFIX,githubassets.com,$GH" \
         "DOMAIN-SUFFIX,githubapp.com,$GH"; do
	if ! grep -qF -- "- $r" "$OUT.tmp"; then
		echo "警告: GitHub 段丢失: $r"
		exit 1
	fi
done
for r in "DOMAIN-SUFFIX,api.bilibili.com,🎬 B站解锁" \
         "DOMAIN-SUFFIX,biliapi.net,🎬 B站解锁" \
         "DOMAIN-SUFFIX,app.bilibili.com,DIRECT" \
         "DOMAIN-SUFFIX,cm.bilibili.com,DIRECT" \
         "DOMAIN-SUFFIX,api.vc.bilibili.com,DIRECT" \
         "DOMAIN-SUFFIX,api.live.bilibili.com,DIRECT" \
         "DOMAIN-SUFFIX,bilibili.com,DIRECT" \
         "DOMAIN-SUFFIX,bilivideo.com,DIRECT" \
         "DOMAIN-SUFFIX,hdslb.com,DIRECT"; do
	if ! grep -qF -- "- $r" "$OUT.tmp"; then
		echo "警告: B站段丢失: $r"
		exit 1
	fi
done
if ! grep -qF -- "- DOMAIN-SUFFIX,twimg.com,𝕏 媒体" "$OUT.tmp"; then
	echo "警告: 𝕏 媒体段丢失，请检查 $OUT.tmp"
	exit 1
fi
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
	if ! grep -qF -- "- $r" "$OUT.tmp"; then
		echo "警告: Google 广告 carve-out 丢失: $r"
		exit 1
	fi
done
for r in "DOMAIN-SUFFIX,envato.com,$GOOGLE_GROUP" \
         "DOMAIN-SUFFIX,envato-static.com,$GOOGLE_GROUP" \
         "DOMAIN-SUFFIX,envatousercontent.com,$GOOGLE_GROUP" \
         "DOMAIN-SUFFIX,themeforest.net,$GOOGLE_GROUP" \
         "DOMAIN-SUFFIX,liveperson.net,$GOOGLE_GROUP" \
         "DOMAIN-SUFFIX,lpsnmedia.net,$GOOGLE_GROUP" \
         "DOMAIN,browser-intake-datadoghq.com,$GOOGLE_GROUP" \
         "DOMAIN-SUFFIX,googletagmanager.com,$GOOGLE_GROUP" \
         "DOMAIN-SUFFIX,googletagservices.com,$GOOGLE_GROUP"; do
	if ! grep -qF -- "- $r" "$OUT.tmp"; then
		echo "警告: 共享 SaaS / GTM 覆盖丢失: $r"
		exit 1
	fi
done
# 2026-10-23 吸收段：任一关键规则丢失就失败，防止上游同键去重静默吃掉。
for r in "DOMAIN-SUFFIX,image.civitai.com,📺 大流量" \
         "DOMAIN-SUFFIX,civitai.com,🚀 节点选择" \
         "DOMAIN-SUFFIX,hf-mirror.com,🎯 全球直连" \
         "DOMAIN,download2.epicgames.com,📺 大流量" \
         "DOMAIN,fastly-download.epicgames.com,📺 大流量" \
         "DOMAIN-SUFFIX,cdn.blizzard.com,📺 大流量" \
         "DOMAIN-SUFFIX,dyn.riotcdn.net,📺 大流量" \
         "DOMAIN-SUFFIX,i.pximg.net,📺 大流量" \
         "DOMAIN-SUFFIX,replicate.delivery,📺 大流量" \
         "DOMAIN-SUFFIX,runway.com,🤖 人工智能" \
         "DOMAIN-SUFFIX,suno.com,🤖 人工智能" \
         "DOMAIN-SUFFIX,ai.com,🤖 人工智能" \
         "DOMAIN-SUFFIX,ghcr.io,🔗 GitHub 出口"; do
	if ! grep -qF -- "- $r" "$OUT.tmp"; then
		echo "警告: 2026-10-23 吸收段丢失: $r"
		exit 1
	fi
done
if ! awk '/^- DOMAIN-SUFFIX,image\.civitai\.com,/{i=NR} /^- DOMAIN-SUFFIX,civitai\.com,/{c=NR} END{exit !(i && c && i<c)}' "$OUT.tmp"; then
	echo "警告: civitai 规则顺序错误（image.* 必须在主站之前）"
	exit 1
fi
if ! grep -qF -- "- IP-CIDR,74.125.0.0/16,$CL,no-resolve" "$OUT.tmp" || \
   ! grep -qF -- "- IP-CIDR,173.194.0.0/16,$CL,no-resolve" "$OUT.tmp"; then
	echo "警告: Google IP-CIDR 缺少 no-resolve"
	exit 1
fi
mv -f "$OUT.tmp" "$OUT"
echo "已更新 $n 条 AI/Google/修正规则 -> $OUT"
echo "重启服务生效: /etc/ShellCrash/start.sh start"
