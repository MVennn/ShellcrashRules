# 更新日志

> **一句话**：本仓改了什么、为什么改、什么时候改 —— 按版本倒序；每条按对象单列一行，不打包成「代码整理」。

版本命名遵循三段式进位：**有功能更新进次版本（+0.1.0），没有就进补丁版本（+0.0.1）**。
规则正本见 [docs/VERSIONING.md](docs/VERSIONING.md)。
本仓是配置与脚本仓库，没有构建产物；版本号只在本文档头部维护，
发版 tag 与 Release 说明文件名都用它（格式见 [docs/release-notes/README.md](docs/release-notes/README.md)）。

---

## [未发布]

### 游戏补丁/下载 CDN 移出 大流量，改直连（2026-10-30）

- H 段与「游戏平台补丁」段共 21 条（Epic / 暴雪 / GOG / EA / 育碧 / Xbox / Riot /
  Rockstar / Bethesda）由 `📺 大流量` 改成 `🎯 全球直连`
- 依据：`nslookup`（AliDNS）实测这些域全部解析到境外 Akamai/Fastly/暴雪边缘
  （23.x / 146.75.x / 137.221.x），TCP connect 0.07–0.9s 可达 —— 「各有国内 CDN」
  不成立，所以不能靠直连 CN 节点省事；但它们也不该占公共池，改为直连、
  由各家自己的下载体系跑。某条直连明显慢就单独改回 `📺 大流量`
- 三处写后校验（大流量段 / 大流量补充段 / 2026-10-23 吸收段）同步改成断言直连，
  第一次只改了规则没改校验，被生成器拦下（退出 1、rules.yaml 未被覆盖）——
  这正是原子写 + 写后校验的作用

### 📺 大流量 补容器镜像/网盘/模型权重的正文域（2026-10-30）

- `config/generators/ai-rules-update.sh` 的 K 段后新增 L 段 9 条：
  `production.cloudflare.docker.com`、`pkg-containers.githubusercontent.com`、
  `cdn01/02/03.quay.io`、`cloudflarestorage.com`、`userstorage.mega.co.nz`、
  `dl.dropboxusercontent.com`、`cas-bridge.xethub.hf.co`
- 只摘 **blob/CDN 正文域**（无凭证、可续传）；登录与 API 留在各自机型组 ——
  `🆓 公共备用` 是陌生人出口，不能过凭证（同 `🤖 AI接口` 排除公共节点的理由）
- 游戏下载域刻意不进公共池：Steam depot 仍 `DIRECT`，Steam 静态/CDN 仍 `🚀 节点选择`
- 写后校验加一条 `production.cloudflare.docker.com,📺 大流量`
- 文档：`docs/ARCHITECTURE.md` §3 补一行归属 —— 路由器侧守护脚本
  （`bulk-guard.sh` / `guardian.sh` / `recover-now.sh`）的正本在 **`OpenwrtOpsToolkit` 仓**，
  不在本仓；此前只在路由器上找，容易误判成「仓库里没有」

### opencode.ai / workbuddy.ai 改直连，机场只留给地区受限型号（2026-10-30）

- `config/generators/ai-rules-update.sh` + `config/generated/rules.yaml`：
  `DOMAIN-SUFFIX,opencode.ai` 由 `🤖 AI接口` 改为 `🎯 全球直连`，新增
  `DOMAIN-SUFFIX,workbuddy.ai,🎯 全球直连`；去掉因此不再使用的 `API_GROUP` 变量
  （写后校验同步改成断言这两条直连规则）
- 依据：带真实 key 从中国 IP 实测 26 个 opencode 型号直连 200（只有 `gpt-*` /
  `beam-free` / `muse-spark-*` 拿 403 地区限制）；`workbuddy.ai` 直连 0.25s。
  DeepSeek 之前每次 429 都会回落到这两跳，机场流量就是这么烧掉的
- `config/yamls/user.yaml` 新增 `listeners`：`ai-airport`（`type: http`，`port 7896`，
  `proxy: 🤖 AI接口`）—— **入站固定出口，不看规则匹配**，只给 zgate 的
  `chain[].proxy` 用（地区受限型号的兜底跳）
- 实测：经 7896 的出口是日本节点、路由器直连是广东联通；`start.sh restart` 后
  `ai-api-check.sh` 18 段全部通过
- 文档：`docs/ARCHITECTURE.md` §2.1 / §2.2 / §4（端口与出口分离机制）

### 🤖 AI接口 复测间隔压到 60s、健康检查换 robots.txt（2026-10-27）

- 调整 `config/yamls/proxy-groups.yaml` —— `🤖 AI接口` 显式写 `interval: 60` +
  `timeout: 5000`。此前没写 `interval`，吃 mihomo 默认 300s：节点一进坏态，
  url-test 最长 5 分钟才会换掉它，这段时间所有 `opencode.ai` 请求都压在死路上
  （实测 `🇺🇸 美国LA-优化-GPT` 根路径与 `/zen/go/v1/models` 同时超时，面板却仍显示 alive）
- 健康检查 URL 由首页改成 `https://opencode.ai/robots.txt` —— 首页 70 KB，mihomo
  复测会把响应体读完，24 个成员按 60s 复测约 2.4 GB/天（300s 时 0.5 GB/天）；
  robots.txt 只有 220 B，复测流量降到约 8 MB/天，口径同 `🔗 GitHub 出口`
- 不改组成员、不动 `tolerance` —— 坏窗口是**间歇性**的（同一批 LA 节点复测仍是
  300–368ms），永久剔除会白白丢掉最快的节点；缩短复测间隔才是对的杠杆
- 现象 / 根因 / 验证见 `docs/PITFALLS.md` 第 42 条

## [0.4.0] — 2026-10-27

### Steam 下载改走国内 CDN（2026-10-27）

- 调整 `config/generators/ai-rules-update.sh` + `config/generated/rules.yaml` —— 新增 G2 段：
  `steamserver.net`（CM）、`api.steampowered.com`（内容服务器目录）、`eccdnx.com` /
  `clngaa.com` / `pphimalayanrt.com`（国内 CDN）、`steamcontent.com` 全部 `DIRECT`；
  `steamstatic.com`、`steamcdn-a.akamaihd.net`、`steampipe*.akamaized.net` 从 `📺 大流量`
  挪到 `🚀 节点选择`（商店静态资源与客户端安装包，直连实测更差）
- 调整 `config/fakeip/fake_ip_filter.list` —— `api.steampowered.com` 不再走 fake-ip
- 调整 `config/starts/clash_modify.sh` —— `nameserver-policy` 给 `api.steampowered.com`
  指定 `$dns_nameserver`（AliDNS/DoH.pub）。默认 `nameserver` 是 Cloudflare/Google DoH，
  会把它解析到海外 Akamai 边缘（`23.35.148.x` / `95.101.182.x`），直连连不上
- 根因（两步）——
  1. `steamcontent.com` 被送进 `📺 大流量`，默认 `🆓 公共备用`（当时钉 `🆓 公共-05`，
     SS、348 ms），下载走 PC → 免费公共节点 → 香港 CDN；
  2. 更关键的是 **CM（`*.steamserver.net`）走代理**，Valve 从 CM 连接看到的客户端
     公网 IP 是香港，内容服务器目录因此只分配 `cache*-hkg1` / `cache*-tyo3`。
     只把 CDN 改直连、CM 仍走代理时，客户端依旧拿香港节点（实测 173–184 Mbps）；
     CM 改直连后 Valve 看到真实国内 IP，立刻分配国内 CDN
- 实测（客户端正在下 144 GB）—— 速率 43–60 Mbps（公共池）→ 173–184 Mbps（香港直连）
  → **375–390 Mbps**（国内 CDN：`st.dl.eccdnx.com` / `dl.steam.clngaa.com` /
  `xz.pphimalayanrt.com`）。国内 CDN 是 CN 段，在防火墙层就绕过 mihomo 走硬件转发，
  所以能突破 mihomo DIRECT 中继约 186 Mbps 的上限（实测 32 并发：裸 WAN 462 Mbps、
  经 mihomo 186 Mbps）
- 历史对照 —— 客户端 `content_log.txt` 里 2026-07-21 用同一 CellID 148 走的就是这批
  国内 CDN，峰值 568 Mbps；最后一次使用是 2026-09-23，与代理上线时间吻合
- 已知限制 —— `api.steampowered.com` 直连会偶发超时（客户端自动重试，成功一次即可
  拿到国内列表）；CM 直连到香港/新加坡比走机场慢（TLS 0.97s vs 0.35s），
  换来的是下载带宽从 ~180 Mbps 提到 ~390 Mbps
- 验证 —— 生成器 / `clash_modify.sh` `sh -n` ✓；`/rules` 实测五条 `DIRECT` 生效；
  客户端日志 13:22:58 出现 `Created download interface of type 'CDN' to host
  st.dl.eccdnx.com`，速率 13:23:47 起稳定在 375–390 Mbps

## [0.3.1] — 2026-10-26

### 全仓审查修复（2026-10-26）

- 修复 `firewall/quicguard-sync.sh` —— `cn_ip6_mirror` 集合只在 `CN6` 非空时才定义，
  但生成模板无条件引用它；未开 IPv6 / fake-ip 的设备上 `nft -c -f` 校验失败，
  整份 CN QUIC 豁免装不上。改为集合始终定义、元素可为空（PITFALLS 39）
- 修复 `config/starts/fw_nftables.sh` —— `[ -n "$$vm_ipv4" ]` 里的 `$$` 是当前 shell
  的 PID，条件恒真；`vm_redir=ON` 且 `vm_ipv4` 为空时会建出带空集合的链并导致
  全部 LAN TCP 被双重劫持。改回 `$vm_ipv4`（PITFALLS 40）
- 修复 `tools/public-nodes/evaluate.py` —— 评测反复 `start.sh restart` 却不暂停看门狗，
  与 `screen.py` 注释里记载的「双实例 → 重复键 → 静默回退基础配置」事故同路径；
  主循环前后复用 `pause_watchdogs()` / `resume_watchdogs()`（try/finally）
- 修复 `config/starts/sub-sync.sh` —— 已有节点名解析多一行 `sed "s/^[^ ]* //"`，
  含空格的节点名（`HK 01`）被截断后与订阅侧比对判定「缺失」而重复追加，
  mihomo 拒载整份配置；同时收窄伪节点过滤（去掉单独的「流量」，避免误杀
  「大流量专线」类真实节点）（PITFALLS 41）
- 修复 `config/ai-api-check.sh` —— 第 5 节与 9.1 节的自修复只验语法、不复核结果，
  上游改了锚点后会假报「已修复」；补重新 grep。第 14/15 节读 secret 未剥引号，
  `secret='abc'` 时全部 API 查询 401
- 修复 `config/generators/ai-rules-update.sh` —— `googleapis.com → 节点选择` 是死规则
  （同键去重保留前面的干净出口版本），删除并注释说明
- 修复 `tools/public-nodes/screen.py` —— crontab 备份放 `/tmp`（tmpfs），PC 异常退出后
  路由器重启会把「已暂停」状态当成正常态重新备份，看门狗永久停摆；移到
  `/etc/ShellCrash/`（overlay）
- 修复 `tools/check-secrets.py` —— 本机路径豁免是整行的；改为只豁免命中片段
- 修复 `config/archive/rules-dedup.sh` —— 用 `ls -l` 截出的符号权限喂 GNU chmod 必失败；
  改用 `cp -p` 保留原权限
- 部署 —— `starts/sub-sync.sh` 补进 `local-patches/` 与设备 `PATCH_SPEC`（标记 `HAVE_N`），
  ShellCrash 官方更新后能一起恢复；`quicguard-sync.sh` 重跑生成文件未变、live 表
  `cn_ip6_mirror` 1487 行；`ai-api-check.sh` 实跑全 OK


### 自检（2026-10-26）

- 调整 `config/ai-api-check.sh` —— 移除原第 4 段「三种协议最小 token 测试」：
  路由器不再每天向 `opencode.ai/zen/go` 发模型请求；其余 17 段与编号保留
  （第 4 段留一行「已移除」说明）。原因：该段走路由器本机显式代理 `127.0.0.1:7890`，
  与 PC 侧实际使用的 LAN 透明代理不是同一条路径，红了不代表客户端故障；
  模型可用性在 PC 侧实际调用时即可暴露，无需路由器定时探测。
- 文档 —— `MAINTENANCE.md` / `ARCHITECTURE.md` / `TOOLS.md` / `TROUBLESHOOTING.md`
  的自检段数与第 4 段引用同步；`TROUBLESHOOTING.md` §5 改为手动最小请求复测命令。
- 新增 `config/daily-ai-check.sh` —— 把只存在于路由器上的每日自检包装脚本纳入仓库；
  修正日志轮转：原写法从 `.1` 起逐个 `mv`，移动后又命中下一个序号，结果把单个文件一路推到
  `.21`、实际只保留 2 份。改为从 `.14` 倒序后移并清理 `.15+`，真正保留最近 14 份。
- 文档 —— `DEPLOY.md` 部署映射补 `daily-ai-check.sh`；`ARCHITECTURE.md` 的 cron 表补自检行。

### 文档正本（2026-10-24）

- 新增 `docs/DOC-RULES.md` 变更触发矩阵一条 —— **修一个缺陷必须给对应正本补一条**
  （只改代码不改正本，下次还会踩同一个坑）
- 新增 `docs/PITFALLS.md` 31–33 三条 —— 占位符整行放行会把同一行的真 `sk-` token 一起放过、
  `chmod` 符号模式、`pause_watchdogs()` 的备份顺序（先恢复残留备份那步失败会让坏备份被反复复用）

### 代理组与节点排序（2026-10-23）

- 调整 `config/hooks/reorder-groups.sh` —— 代理组展示顺序改为
  「常用入口 → 专用出口 → 地区组 → 工具 → 内部子组」：
  `🚀 节点选择` → `🛟 主备自动` → `♻️ 自动选择` → `🚀 手动切换` → AI 家族 →
  GitHub/B站/𝕏 媒体/大流量/公共备用 → 地区组 → 流媒体/工具 →
  `𝕏 媒体-HY2`/`𝕏 媒体-备用` 放最后；未知组按原顺序补在末尾
- 调整 `config/hooks/reorder-groups.sh` —— `🚀 节点选择` 成员顺序改为
  `🛟 主备自动` → `♻️ 自动选择` → `🚀 手动切换` → `🤖 AI接口` →
  `🔗 GitHub 出口` → `🎬 B站解锁` → `𝕏 媒体` → `📺 大流量` → `🆓 公共备用` →
  地区组（港/日/台/新/美/印/加/德/英）→ `DIRECT`；`🚀 手动切换` 从第 13 位提到第 3 位
- 新增 `config/hooks/reorder-groups.sh` —— `🚀 手动切换` / `♻️ 自动选择` 的节点按
  香港 → 日本 → 台湾 → 新加坡 → 美国 → 印度 → 加拿大 → 德国 → 英国稳定排序，
  同地区保留订阅原顺序，未知地区排最后
- 验证 —— 运行配置 30 个组顺序、`🚀 节点选择` 19 个成员、两个 27 节点组顺序
  全部符合预期；`ai-api-check.sh` 18 段全绿；伪节点仍为 0
- 文档 —— `ARCHITECTURE.md` 新增「代理组排序规则（新增组必须遵守）」正本；
  `MAINTENANCE.md` §2.5、`CONTRIBUTING.md`、`DOC-RULES.md` 变更触发矩阵、
  `PITFALLS.md` §38、`proxy-groups.yaml` / `reorder-groups.sh` 顶部注释同步。
  **新增 / 改名 / 删除组必须同步 `order[]`**，漏加会掉到面板最后；
  验证步骤补 OpenwrtConsole 本地 mock 入口（无需路由器密码）
- 调整 `docs/ARCHITECTURE.md` —— 说明 `𝕏 媒体-HY2` / `𝕏 媒体-备用` 是
  `𝕏 媒体` fallback 的内部子组；OpenwrtConsole 默认不单独展示它们的卡片
  （父组下拉仍可切换），避免列表末尾看起来像重复的 `𝕏 媒体`
- 文档 —— 固化「内部子组默认隐藏」约定：只作为父组 fallback 成员、默认不出卡片；
  新增 / 改名时同步 OpenwrtConsole 的 `HIDDEN_GROUPS`，父组下拉保留。
  `MAINTENANCE.md` §2.5、`CONTRIBUTING.md`、`DOC-RULES.md` 变更触发矩阵同步

### 规则吸收与公共池（2026-10-23）

- 调整 `config/generators/ai-rules-update.sh` + `config/generated/rules.yaml` —— 从
  `VPSDance/ai-proxy-rules` 吸收 40 条 AI 自有域（`ai.com`、`modelcontextprotocol.io`、
  `together.xyz`、`deepinfra.com`、`fireworks.ai`、`novita.ai`、`bfl.ai`、`stability.ai`、
  `runway.com`、`suno.com`、`udio.com`、`character.ai`、`you.com` 及生成/编码类），
  共享 SaaS/CDN 不收；生成物 486 条 / 610 行
- 调整 `config/generators/ai-rules-update.sh` —— 从 `Aethersailor/Custom_OpenClash_Rules`
  与 `MetaCubeX` 吸收 Epic / Steam / 暴雪 / Riot / Bethesda / Ubisoft / Xbox / GOG 下载 CDN；
  Civitai 主站走 `🚀 节点选择`、`image.civitai.com` 走 `📺 大流量`（图片 CDN 必须排在主站前）
- 调整 `config/generators/ai-rules-update.sh` —— 媒体 CDN 进 `📺 大流量`：Reddit 图片/视频、
  Imgur、Pixiv 图片、Vimeo、Dailymotion、Twitch CDN、SourceForge、`replicate.delivery`
- 调整 `config/generators/ai-rules-update.sh` —— 只吸收实测更快的直连：`hf-mirror.com`
  （Range 4MB 2.42 vs 代理 0.65 MB/s）、`kuaishouzt.com`、`images-cn.ssl-images-amazon.com`；
  实测否掉 `cn.download.nvidia.com`（直连 403、代理 3.2 MB/s）、`gstatic-cn.com`、`recaptcha-cn.net`
- 调整 `config/generators/ai-rules-update.sh` —— 补 5 条国内广告变体
  （`2mdn-cn.net` / `doubleclick-cn.net` / `dartsearch-cn.net` / `admob-cn.com` /
  `app-measurement-cn.com`）；`ghcr.io` → `🔗 GitHub 出口`，`graph.org` / `tg.dev` →
  `🚀 节点选择`，`live-video.net` → `🌍 国外媒体`
- 调整 `config/generators/ai-rules-update.sh` —— Google 兜底 `IP-CIDR 74.125.0.0/16` /
  `173.194.0.0/16` 补 `no-resolve`，避免 fake-ip 下为匹配触发真实 DNS
- 新增 `config/yamls/proxy-groups.yaml` —— `𝕏 媒体` 拆成 `𝕏 媒体-HY2`（主）+
  `𝕏 媒体-备用`（VMess）+ fallback；2026-10-23 晚 HY2 对 `pbs.twimg.com` 4/4 超时，
  VMess 5/5 200，`pbs` 恢复 200/0.26–0.28s；策略组 28 → 30
- 新增 `config/hooks/reorder-groups.sh` —— 生成阶段剔除机场伪节点
  （`过滤掉N条线路` / `剩余流量` / `套餐` / `到期` / `官网`）：`过滤掉14条线路` 与
  `日本-优化` 同 server/port/uuid，被 url-test 选中后健康抖动会让 `🛟 主备自动`
  整组回落到公共池；配置副本验证删除 3 行、YAML 可解析、运行配置 0 处伪节点
- 调整 `config/ai-api-check.sh` —— 第 5 段新增伪节点过滤/运行配置检查；第 17 段新增
  `hf-mirror.com` 等直连、AI/大流量吸收规则与 Google `no-resolve` 回归项；18 段全绿
- 调整 `tools/public-nodes/screen.py` —— 数据源 3 → 6（新增 `NoMoreWalls`、`Au1rxx`、
  `zhuhaiuk`）；筛选期间同时暂停 `bulk-guard`；重启后清空 `.bulk_guard_speed` /
  `.bulk_guard_tried`，避免节点编号重排后测速缓存张冠李戴
- 调整 `tools/public-nodes/README.md` —— 补六源说明与 2026-10-23 实跑结果
  （9804 → 9479 → 1271；实测 259/存活 13/保留 10）
- 调整 `OpenwrtOpsToolkit/openwrt/bulk-guard.sh` —— 新增 `node_bulk_alive()`，钉点/
  候选/当前节点都用 `PROBE_URL`（`proof.ovh.net`）二次校验；修复「gstatic 200 但大流量
  不通」的节点被钉进 `📺 大流量`（实测 `公共-02` TLS EOF/502）。公共池钉 `公共-08`
  后 4MB 实测 1.9–2.2 MB/s（修复前 17–34 KB/s）
- 验证 —— 生成器 `sh -n` ✓；`CrashCore -t` / 重启校验 ✓；`ai-api-check.sh` 18 段
  `CHECK_RC=0`；`/connections` 实测 `civitai.com` → 🚀 节点选择、`image.civitai.com` →
  📺 大流量、`runway/suno` → 🤖 人工智能；GitHub 0.78s、B站 0.11s、百度 0.10s、
  `pbs.twimg.com` 0.27s、`hf-mirror` 1.06 MB/s、公共池 1.76 MB/s

### 看门狗备份顺序（2026-10-24）

- 修复 `tools/public-nodes/screen.py` 的 `pause_watchdogs()` —— 先恢复上次残留备份这一步
  是 `check=False`，传输抖动时悄悄失败、后面又照常备份，备份里存的就是「已暂停」的
  crontab；此后恢复和下一次暂停都从坏备份读，guardian / legacy 看门狗永久停摆，而日志
  写着「已恢复」。现在恢复改 `check=True`，并校验备份里确实有看门狗行；备份前若当前
  crontab 本来就没有看门狗行，记 WARN 但不拒绝（那是真实状态）
- 修复 `resume_watchdogs()` —— 恢复失败不再静默，记 ERROR 并抛出让脚本非零退出
- 验证 —— `ast.parse` ✓；恢复/备份用到的 ssh 命令在路由器上手动核对过

## [0.3.0] — 2026-10-23

### 守卫与权限（2026-10-23）

- 修复 `tools/check-secrets.py` —— `PLACEHOLDER` 命中后整行 `continue`：行内只要
  出现 `example.com` / `<...>` / `YOUR-` 就把同一行的真值一起放过。改为只豁免
  匹配片段本身（实测带 `<!-- see docs -->` 的真 `sk-` token 现在会报，
  示例 URL 仍按预期放行）
- 修复 `config/hooks/rules-mid.sh` —— 权限保持用 `ls -l` 取 `rw-r--r--` 再
  `chmod`，GNU chmod 直接拒绝该模式（busybox 碰巧接受），PC 侧复现会静默退回
  umask。改为 `cp -p` 先建临时文件、再截断写入，权限与属主沿用原文件
- 验证 —— 7 个仓的同一份扫描脚本同步改完并各自跑通；`sh -n` ✓、
  `check-vault-not-staged --all` ✓、`check-secrets.py` ✓（123 个文件）、
  `check-docs.py` ✓（22 篇）


### 𝕏 媒体（2026-10-23）

- 新增 `𝕏 媒体` 组 —— `url-test` + `filter: HY2`，只承载 `twimg.com`（X/Twitter 图片与视频 CDN）。修复 VMess+WS 并发建连被串行化：10 并发真实图片从 1.9–5.9s（偶发单张 5–6s）降到 0.35s、单张 0.21–0.25s；单请求延迟看不出差异（HY2 89ms vs VMess 65ms），所以组内只放 HY2，健康检查用 `pbs.twimg.com/robots.txt`（200、稳定）
- 调整 `config/generators/ai-rules-update.sh` —— 规则置顶新增 X 段，并在写后校验里要求 `DOMAIN-SUFFIX,twimg.com,𝕏 媒体` 存在
- 调整 `config/generated/rules.yaml` —— 同步 X 段（自定义规则在机场模板规则之前，覆盖 `twimg.com` 的默认出口）

### 文档骨架对齐系列仓（2026-10-23）

- 调整 `docs/release-notes/` —— 文件名去掉 `v` 前缀（`v0.2.1.md` → `0.2.1.md`，共 4 份）；
  `v` 前缀只属于发版 tag，tag 未动。
- 调整 `docs/README.md` —— 引言块与结尾提醒对齐基准仓，一句话定位压到一行读完；
  参考资料补 `release-notes/` 目录入口，四份单版本说明链接跟随改名。
- 调整 `docs/VERSIONING.md` —— §5 改为「不发版的时候：不要动版本号」，按手工发布号改写；
  §2 判断口诀与边界表对齐基准仓。
- 调整 `docs/DOC-RULES.md` —— 新增 §1.1「文件命名：全大写 + 连字符」；
  `release-notes/README.md` 的「别写这些」补引言块与标题行两行禁令。

### 仓库门面

- 新增 `.github/ISSUE_TEMPLATE/` —— 问题反馈（Bug）与功能建议两套表单，外加 `config.yml`：
  Bug 表单要求填设备与固件、ShellCrash / mihomo 版本、实际与期望走向、`ai-api-check.sh` 输出；
  功能建议要求先写场景并确认范围
- 新增 `CONTRIBUTING.md` —— 提 Issue / PR 的入口、提交前自检命令与硬规矩索引
- 新增 `SECURITY.md` —— 私密报告渠道、支持版本、规则与 nft 表会改的设备状态与安全边界

### 配置

- 新增 `🎬 B站解锁` 组 —— `select`：`香港WAP` / `台湾-优化3` / `日本-优化` / `新加坡-优化3`，默认 `🇭🇰 香港WAP-优化`；只由 `rules.yaml` J 段的 B站 API 域引用。实测 HY2 池到大陆方向不通（香港/韩国能连 gstatic，但百度/知乎/B站 TLS EOF/超时；日本/新加坡节点本身超时），vmess 的港/台/日/新节点在 B站 `x/web-interface/zone` 分别显示对应地区
- 新增 `📺 大流量` 组 —— `select`：`🆓 公共备用` → `♻️ 自动选择`，只由规则 H 段的大文件下载域引用；默认走公共池省机场流量，吞吐低于阈值时由 `bulk-guard.sh` 切回机场。`reorder-groups.sh` 的成员顺序与兜底插入同步（`🚀 节点选择` 末尾、`DIRECT` 之前）
- 调整 `config/yamls/proxies.example.yaml` —— 说明当前设备不再维护手工节点（节点全部来自订阅 + `sub-sync.sh` 自动补齐），模板只用于额外加备用入口；`cp` 重建时提醒保留 SUB-SYNC 块
- 调整 `config/yamls/proxies.example.yaml` —— 明确设备上的 `proxies.yaml` 有 `SUB-SYNC` / `PUBLIC-NODES` 两个自动块，**禁止整文件覆盖**（2026-10-22 曾因整文件部署冲掉 4 个公开节点）
- 调整 `config/generators/ai-rules-update.sh` + `config/generated/rules.yaml` —— B站二次拆分：`app.bilibili.com` / `cm.bilibili.com` / `api.vc.bilibili.com` / `api.live.bilibili.com` 改 `DIRECT`（四者都不参与 IP 属地），只留 `api.bilibili.com` / `biliapi.com` / `biliapi.net` 走 `🎬 B站解锁`。实测直连 TTFB 0.06–0.09s vs 经香港 0.57–1.57s，动态/直播/App 启动每个新连接都省一次隧道往返
- 调整 `config/generators/ai-rules-update.sh` —— B站段自检同步新拆分：原来强制要求 `cm.bilibili.com` 指向 `🎬 B站解锁`，新规则会被自己的校验拒掉（`警告: B站段丢失`、`rc=1`），并补上四个 `DIRECT` 项
- 记录 `docs/RULE-AUDIT.md` 7.6 —— 视频 CDN 拆不动的实测：`playurl` 与评论同在 `api.bilibili.com`，经香港返回海外 CDN（0.69–1.23 MB/s），路由器官网出口返回国内 CDN（`upos-sz-mirrorbd`）；要国内 CDN 只能放弃属地

### 工具

- 调整 `tools/public-nodes/screen.py` —— 数据源从单一 AutoMergePublicNodes 扩到三个（新增 Epodonios、ermaozi），按源轮转合并后再进多样性池；候选池 200 → 1192 条
- 调整 `tools/public-nodes/screen.py` —— `--max-keep` 默认 8 → 16、`--max-new` 100 → 200、`--max-delay` 1500 → 800；`pick_survivors` 里「每协议最多 3 条 / 每网段最多 2 条」的硬编码上限改为参数 `--max-per-type` / `--max-per-base`（默认 8 / 5），此前 `--max-keep` 调大也不会生效
- 调整 `tools/public-nodes/screen.py` —— 运行期间自动暂停路由器 `guardian.sh` / `start_legacy_wd.sh` 的 cron 并在结束时恢复：两者与 `start.sh restart` 并发会生成带重复 `proxies:` / `proxy-groups:` 键的坏配置，整轮作废
- 调整 `tools/public-nodes/README.md` —— 补多源说明、新默认值，以及计划任务的「全自动」设置（错过补跑 / 电池也跑 / 失败重试）
- 修复 `tools/public-nodes/screen.py` —— 批次测试异常时不回滚：`api_proxies` 抛错会把最后一批 50 条测试节点留在设备上，正式的兜底节点被顶掉（2026-10-22 实测发生一次）。现在 `test_batches` 用 try/except 包住，异常时写回 `old_content` 并重启再抛出
- 修复 `tools/public-nodes/screen.py` —— 重启后先 `wait_api` 轮询 `/version`（最多 60s）再读 `/proxies`，`api_proxies` 重试 2 次 → 4 次、间隔 5s → 10s；这一轮就是「配置已加载但 API 未就绪」导致整轮崩掉的
- 修复 `tools/public-nodes/screen.py` —— 「没有存活节点」时保留旧配置的重启失败没人管，现在失败会等 30 秒重试一次，仍失败则显式返回 1：网络抖动会让配置生成被截断，ShellCrash 静默回退基础配置
- 修复 `tools/public-nodes/run-daily.cmd` —— **批处理文件里不能写中文注释**：本仓 `.gitattributes` 强制 `eol=lf`，计划任务用 OEM 代码页（936）解析 UTF-8 中文会直接退出整个脚本，表现为「任务返回 0 但 python 根本没启动」（2026-10-22 排查）。同时去掉多行 `if (...)` 块，改成单行 `if ... for ... do if ...`
- 修复 `tools/public-nodes/screen.py` —— `ssh()` 对**传输层**失败（超时 / rc=255）自动重试一次，并加 `ServerAliveInterval=5 / ServerAliveCountMax=2`：路由器重启那几十秒里连 `rm -f` 都能卡满 120 秒，足以让整轮作废（2026-10-22 16:37 实测）；命令本身的错误仍然立即抛出
- 修复 `tools/public-nodes/screen.py` —— 预检失败时二分定位坏节点：整块预检是「一条坏节点否决整批」，而候选池顺序稳定，不把坏节点挑出来记 dead，同样的 50 条每轮都会排在最前反复失败，**队头永久堵死**。现在用二分（约 2×log2(n) 次预检）找出 mihomo 无法加载的节点，写进 state 记 dead（3 天冷却），其余继续测。单测：20 条里精确找出 3 条坏节点

- 新增 `tools/public-nodes/run-daily-hidden.pyw` —— 计划任务的当前入口：用 `pythonw.exe` 无窗口转调 `run-daily.cmd`，任务动作已经是它；**任务本体仍是 `run-daily.cmd`**（日志轮转 / UTF-8 / python 调用只在它里面维护）
- 调整 `tools/public-nodes/README.md` —— 定时任务一节写明实际动作与无窗口原理，重建命令改用 `pythonw.exe` + `run-daily-hidden.pyw`

### 设备侧（不入库）

- 删除 `yamls/proxies.yaml` 里的 `印度-备用m2` / `印度-备用ct2` —— 机场已不再发布这两个入口，且它们硬编码了共享 UUID，机场换凭据时会静默失效；两者都不在 guardian 候选与自动选路路径上，删除后 `proxies` 34 → 32
- 恢复并重跑公开节点 —— 整文件部署冲掉的 `PUBLIC-NODES` 块已从 `.bak-hy2-20261022` 恢复，随后跑 `tools/public-nodes/screen.py` 换新：384 条原始 → 测 55 条 → 存活 12 → 保留 8 条
- 调整 `starts/clash_modify.sh` / `local-patches/clash_modify.sh` —— **不挂** `rules-dedup.sh`；去重只保留为 PC 离线工具（`config/archive/`）。`post-sc-update.sh` 恢复时只带 `rules-mid` / `rules-cnip` / `reorder-groups`
- 调整 `configs/ShellCrash.cfg` —— `ipv6_dns=OFF`（备份 `ShellCrash.cfg.bak-bili-ipv6-20261022*`）：B站 Akamai CDN 的 IPv6 边缘实测只有 22 KB/s，IPv4 有 1.4–2.1 MB/s；关掉 mihomo 的 AAAA 解析后视频不再缓冲。其他 IPv6 直连（路由器自身）不受影响

### 规则

- 新增 `🔗 GitHub 出口` 组 —— `url-test`，健康检查直接用 `https://github.com/robots.txt`（200、几 KB、不重定向、无需鉴权），`interval: 60`，成员为全部机场节点（`include-all-proxies` + 排除「公共」）。`F. GitHub` 段的 5 条规则从 `🤖 干净出口` 改指本组。**根因**：2026-10-22 干净出口按 Gemini 吞吐选到了 `🇰🇷 韩国KR-HY2`，而该节点到 GitHub 实测 **0/5**（台湾-优化3 是 4/5），GitHub 全族跟着时通时断，PC 侧 `git`/`gh` 报 `schannel: failed to receive handshake`。Google 要求 cc≠CN、GitHub 只要求能稳定握手，两者不能共用一个出口组
- 调整 `config/hooks/reorder-groups.sh` —— 组顺序与 `🚀 节点选择` 成员顺序加入 `🔗 GitHub 出口`（`🚀 手动切换` 之后、`🆓 公共备用` 之前），并纳入兜底插入清单
- 调整 `config/ai-api-check.sh` —— Google 段不再要求 `api.github.com`；GitHub 全族改为校验指向 `🔗 GitHub 出口`
- 调整 `guardian/guardian.sh`（`AX3000TOpenwrt`）的 `CL_ALIVE_URL` —— `https://github.com/` → `https://www.google.com/generate_204`：干净出口不再承载 GitHub，探针要和它实际服务的 Google 家族一致，否则守卫会按 GitHub 可达性把 Gemini 出口踢掉

- 新增 `K. 大流量补充` 段 —— HuggingFace LFS（`cdn-lfs.huggingface.co`、`cdn.hf.co`、`cdn-lfs*.hf.co`、`cas-bridge.xethub.hf.co`）、GitHub 发布包（`objects.githubusercontent.com`、`release-assets.githubusercontent.com`、`codeload.github.com`）、NVIDIA/AMD 驱动（`us/international.download.nvidia.com`、`drivers/download.amd.com`）、游戏补丁（暴雪 `blzddist1-3-a.akamaihd.net`、`cdn.gog.com`、`gog-cdn-fastly.gog.com`、`origin-a.akamaihd.net`、`eaassets-a.akamaihd.net`、`ubistatic-a.akamaihd.net`）、Maven（`repo1.maven.org`、`repo.maven.apache.org`）全部指向 `📺 大流量`。实测公共池 1.56/1.45 MB/s、机场 0.83/1.27 MB/s；真实下载验证：HF 3.37 MB/s、GitHub release 3.06 MB/s，链路均为 `📺 大流量 → 🆓 公共备用 → 🆓 公共-03`。**刻意不收**：npm/PyPI/crates（小文件，公共节点延迟反而更慢）、Docker Hub（按 IP 限流，共享 IP 大概率 429）、Apple/Microsoft 更新（CDN 已解析到国内节点）、Netflix/Disney（DRM + 代理检测）、任何登录/上传/P2P。DNS 预检剔除了 NXDOMAIN 的 `delivery.mp.microsoft.com`、`blizzard.vo.llnwd.net`、`ubisoft-a.akamaihd.net`、`riotcdn.net`
- 修复 `config/starts/fw_nftables.sh` / `firewall/quicguard-sync.sh` / `firewall/tables/quicguard.nft` —— 撤回 B站 API 的 IPv6 特殊段 `2408:8756::/31`（`BILI_V6_MARKER`）：该段是整个联通 IPv6 大段，腾讯 QQ/微信 CDN 大量落在里面，reject 其 QUIC、并把 TCP 443 重定向进 mihomo，会把 QQ/微信视频打断（2026-10-22 实测：手机发视频一直转圈、点播放无反应）。`api.bilibili.com` 本身没有公开 AAAA，IPv4 的 `157.148.134.0/24` / `27.37.206.0/24` 保留
- 调整 `firewall/tables/googlecn.nft` / `firewall/tables/googleroute.nft` —— IPv6 规则从「源地址匹配 ULA/link-local」改为按入接口 `iifname "br-lan"`：运营商 PD 前缀变化（重拨 / 换局向）后规则不会失效，也不要求客户端一定使用 ULA/link-local 源地址；新增 guest / VPN 网桥时把接口名加进集合
- 新增 `J. B站` 段 —— `api/app/cm.bilibili.com`、`api.live/api.vc.bilibili.com`、`biliapi.com/.net` 指向 `🎬 B站解锁`；`bilibili.com/.co`、`b23.tv`、`acg.tv`、`bilivideo.com/.cn`、`hdslb.com`、`biliimg.com`、`acgvideo.com`、`upos-hz-mirrorakam.akamaized.net` 显式直连（字面 `DIRECT`，不用 `🎯 全球直连` 组：`respect-rules` 的 DNS 只对字面 DIRECT 走 `direct-nameserver`）。目的：评论/主页 IP 属地显示节点所在国家，视频 CDN 不占机场流量；B站属地按请求源 IP 判定，没有独立检测接口。评论接口是 `cm.bilibili.com`，只加 `api.bilibili.com` 不够（2026-10-22 实测：手机端评论仍显示广东）
- 新增 `I. 视频站点 + Telegram` 段 —— 成人站（pornhub / xvideos / xnxx / xhamster / redtube / youporn / spankbang / eporner / hqporner / txxx / thumbzilla / tube8 / beeg / porntrex）与其自有 CDN（phncdn / xvideos-cdn / xnxx-cdn / xhcdn / rdcdn / ypcdn / spankbang.party），加 `RULE-SET,porn`（上游 MetaCubeX category-porn，6,520 个域名，日更）与 `DOMAIN-KEYWORD,porn` 兜底未列到的小站；Telegram 加 `cdn-telegram.org` 与两个 DC 段（`91.108.0.0/16` / `149.154.160.0/20`），全部指向 `📺 大流量`。不碰通用 CDN；Telegram 媒体与消息同连接，只能整段接
- 新增 `H. 大流量` 段 —— `steamcontent.com` / `steamstatic.com` / `steamcdn-a.akamaihd.net` / `epicgames-download1.akamaized.net` / `download.epicgames.com` / `proof.ovh.net` 指向 `📺 大流量`。订阅流媒体刻意不进：YouTube 全族必须走 `🤖 干净出口`（Google cc 判定），Netflix/Disney 对公共节点几乎必然判代理。探测域用 `proof.ovh.net` 而不是 Cloudflare 的 `__down`：后者在公共节点上会被限流成 403，403 的「速度」会被误判成节点慢
- 新增 Google 广告/追踪 carve-out —— `doubleclick.net` / `googlesyndication.com` / `googleadservices.com` / `google-analytics.com` / `googleadsserving.cn` / `ads.google.com` / `adservice.google.com` / `pagead.google.com` / `pagead.l.google.com` / `pagead-tpc.l.google.com` / `mobileads.google.com` / `afd.l.google.com` / `badad.googleplex.com` / `csi.gstatic.com` / `collector.githubapp.com` / `app-measurement.com` 改回 `🛑 广告拦截`：此前被自定义 `DOMAIN-KEYWORD,google` / `DOMAIN-SUFFIX,google.com` 整段遮蔽，实测走 `🤖 干净出口` 并真实下载 59–63 KB；`doubleclick.net` 同时挡住 `googleads.*` 子域
- 调整 `googletagmanager.com` / `googletagservices.com` —— 从 `🤖 干净出口` 改到 `🚀 节点选择`，共享标签管理器不再与 Google 账号流量共用出口
- 调整 AI 列表共享 SaaS 域 —— `envato.com` / `envato-static.com` / `envatousercontent.com` / `themeforest.net` / `liveperson.net` / `lpsnmedia.net` / `browser-intake-datadoghq.com` 从 `🤖 人工智能` 改到 `🚀 节点选择`：上游 geosite 误收，素材市场/客服聊天/RUM 不应占用 AI 出口

### 脚本

- 调整 `config/starts/clash_modify.sh` —— B站 CDN 域（`+.bilivideo.com` / `+.bilivideo.cn` / `+.hdslb.com` / `+.biliimg.com` / `+.acgvideo.com` / `upos-hz-mirrorakam.akamaized.net`）单独设 `nameserver-policy` → 上游光猫 DNS（从 `/tmp/resolv.conf.d/resolv.conf.auto` 读取）：AliDNS/默认 DoH 解析到 `23.49.104.x`/`23.193.186.11`（实测 12–689 KB/s），上游 DNS 返回 `2.16.62.x`/`23.57.75.x`（实测 1.4–2.1 MB/s）
- 调整 `config/generators/ai-rules-update.sh` —— J 段 CDN 规则从 `🎯 全球直连` 改为字面 `DIRECT`，并同步校验
- 调整 `config/generated/rules.yaml` —— 由路由器重生成（397 条）
- 调整 `config/starts/fw_nftables.sh` —— 在 `cn_ip`/`cn_ip6` return 之前把 B站 API 的 IPv4/IPv6 段（`157.148.134.0/24`、`27.37.206.0/24`、`2408:8756::/31`）TCP 443 重定向到 7892；手机端用 HTTPDNS 拿真实 CN IP 时域名规则才能生效（`BILI_IP_MARKER` / `BILI_V6_MARKER`）
- 调整 `firewall/quicguard-sync.sh` / `firewall/tables/quicguard.nft` —— 在 CN QUIC 豁免之前 reject B站 API 段的 UDP 443/8443，强制 App 回落 TCP；否则 QUIC 会带着国内 IP 直连
- 调整 `config/generators/ai-rules-update.sh` —— 新增 J 段（B站 API 出国 / CDN 直连）并逐条校验，防止每周更新被上游规则去重掉
- 调整 `config/hooks/reorder-groups.sh` —— 组定义顺序与 `🚀 节点选择` 成员顺序加入 `🎬 B站解锁`（`🆓 公共备用` 之后、`📺 大流量` 之前）
- 调整 `config/generated/rules.yaml` —— 由路由器重生成（396 条；J 段 +17，K 段由并行批次加入）
- 新增 `config/hooks/rules-porn.sh` —— 幂等注入 `porn` rule-provider（MetaCubeX category-porn，`type: http` / `format: mrs` / 日更）；目标组不存在时跳过，写前校验行数、原子替换
- 调整 `config/starts/clash_modify.sh` —— `merger_yaml` 之后调用 `rules-porn.sh`（在 rules-mid / rules-cnip 之前）
- 调整 `config/starts/clash_modify.sh` —— 生成的 `hosts:` 新增 `'*.mcdn.bilivideo.cn'` / `'*.edge.mountaintoys.cn'` → `127.0.0.1`：B站播放器优先从 MCDN/PCDN（`xy*.mcdn.bilivideo.cn:8082`、`*.edge.mountaintoys.cn:4483`）取流，实测 9 个节点里 2 个只有 6–11 KB/s，卡住要等超时才换分段（现象是「看一会儿转圈一下」）。这两个端口不在 7892 重定向集合里，mihomo 规则拦不到，只能在 DNS 层指到本地；播放器随后回落 `upos-*` 常规 CDN（实测 6.5–20 MB/s）。API 走香港、CDN 直连的 J 段设计不变
- 调整 `config/generators/ai-rules-update.sh` —— 新增 H 段（大流量下载域）与 I 段（视频站点 + Telegram）；生成后逐条校验 H/I 段与 `RULE-SET,porn` 存在，防止每周更新被上游规则去重掉
- 调整 `config/hooks/reorder-groups.sh` —— `🚀 节点选择` 成员顺序加入 `📺 大流量`（`🆓 公共备用` 之后、`DIRECT` 之前），并纳入兜底插入清单
- 调整 `config/generated/rules.yaml` —— 由路由器重生成（357 条）
- 调整 `config/generators/ai-rules-update.sh` —— 顶部加入共享 SaaS 覆盖；A 段加入 Google 广告 carve-out；生成后逐条校验 carve-out 与共享 SaaS 覆盖存在，防止每周更新被冲掉
- 调整 `config/ai-api-check.sh` —— 新增第 18 段：逐条校验广告 carve-out / 共享 SaaS 覆盖存在，并断言 `doubleclick.net` 排在 `DOMAIN-SUFFIX,google.com` / `DOMAIN-KEYWORD,google` 之前
- 调整 `config/ai-api-check.sh` —— 第 14/15 段干净出口期望从「印度」改为「HY2/印度/台湾-优化3」，与 guardian 的 HY2 候选对齐，消除重启后的两条误报 WARN
- 调整 `config/generated/rules.yaml` —— 由路由器重生成（323 条，+17）
- 新增 `config/archive/rules-dedup.sh` —— 离线去重审计：4,154 条副本上找出 211 条可安全删除的同目标冗余 / PROCESS-NAME；**不部署到路由器**（O(N²) 扫描会拖垮 CPU/内存，2026-10-22 实测断网）
- 调整 `config/post-sc-update.sh` —— 自动 disable `init.d/shellcrash`（避免 `start_old=ON` 下 procd + legacy 双实例）；不再检查 `rules-dedup.sh`
- 新增 `config/hooks/rules-cnip.sh` —— 从路由器同步回仓库：把 8,980 条内联 CN IP-CIDR 折叠成 `RULE-SET,cnip`，13,133 → 4,154
- 调整 `config/fakeip/fake_ip_filter` —— 补 `+.gstatic.com` / `+.googleapis.com`，与路由器 live 文件一致（Chrome LNA 修复）

### 文档

- 调整 `docs/ARCHITECTURE.md` —— §1.1 组清单、§4 参数表、§4.1 成员顺序加入 `🎬 B站解锁`
- 调整 `docs/RULE-AUDIT.md` —— 新增 §7.6：B站属地拆分的机制、API/CDN 域清单、HY2 与 vmess 节点实测、验证命令
- 调整 `docs/PITFALLS.md` —— 新增第 29 条：「IP 属地」不是独立检测接口，改不了显示只能改出口
- 调整 `docs/ARCHITECTURE.md` —— §4 新增 `📺 大流量` 组与大流量守卫 cron；§4.1 成员顺序同步；配置链路图更新自定义组与 `proxies.yaml` 说明；§1.2 钩子从三个变四个（新增 `rules-porn.sh`）；文件归属表加 `bulk-guard.sh` 与 `porn` provider
- 调整 `docs/PITFALLS.md` —— 新增第 26 条（url-test/fallback 只测首包，不测带宽，含 2/4/8/20MB 校准数据）、第 27 条（「主备自动」的兜底被守护进程复位绕过，实际不生效）、第 28 条（手写域名名单不可能穷举，改用上游类别规则集）
- 调整 `docs/DEPLOY.md` —— 部署映射表加入 `config/hooks/rules-porn.sh`
- 调整 `docs/RULE-AUDIT.md` —— 追加 2026-10-22 广告 carve-out 与 AI 共享 SaaS 清理的审计结论、实测证据与规则清单
- 调整 `docs/PITFALLS.md` —— 新增第 23 条：宽泛 Google 规则遮蔽模板广告 REJECT；补目录缺失的第 22 条与锚点
- 调整 `docs/TROUBLESHOOTING.md` —— 规则审计一节补「广告域走代理」的判据与 `ai-api-check.sh` 第 18 段入口
- 调整 `docs/ARCHITECTURE.md` —— 生成链路保持两个钩子；补充「去重只做离线审计」的说明；自检段数 18
- 调整 `docs/DEPLOY.md` —— `rules-dedup.sh` 标为归档、不部署；`clash_modify.sh` 仍为两个钩子
- 调整 `docs/MAINTENANCE.md` —— 自检 18 段；新增 §2.4 变更纪律（O(N²) 只在 PC、单实例启动、`init.d` disabled）
- 调整 `docs/RULE-AUDIT.md` —— §7.5 记录 211 条可删空间与「不部署」结论；补当前 13,133 条恢复状态
- 调整 `docs/PITFALLS.md` —— 新增 §24/§25（O(N²) 断网、双实例/并发启动）；§12 补 2026-10-22 复发
- 调整 `docs/TROUBLESHOOTING.md` —— 新增 §9 整网断/部分 DNS 的排查与恢复顺序
- 调整 `docs/ARCHITECTURE.md` —— 生成链路补 `rules-cnip.sh`（实际为三个钩子：rules-mid → rules-cnip → reorder-groups）
- 调整 `docs/DEPLOY.md` —— 映射表补 `rules-cnip.sh` 与 `fake_ip_filter`；移除已不成立的「待补」
- 调整 `docs/MAINTENANCE.md` —— 回退表补 `rules-cnip.sh`
- 新增 `docs/DOC-RULES.md` §1.1 —— 文件命名纪律：docs/ 下一律 `ALL-CAPS-WITH-HYPHENS.md`；改名用 `git mv` + 全仓 grep 同步引用方，改完跑 `tools/check-docs.py`；`release-notes/` 单版本说明例外（文件名 = `versionName`，不带 `v`）
- 调整 `docs/DOC-RULES.md` §5 —— 变更触发矩阵新增「改名文档」一行；「发版」行的说明文件名去掉 `v` 前缀
- 调整 `docs/VERSIONING.md` —— §5 改写为「不发版就不要动版本号」，补手工号提前进位会吃掉下一个版本号（CHANGELOG 标题 / 说明文件名 / tag 三处一起偏离）的理由；§2 边界情况表新增「规则段 / 策略组增删改名」一行；§3 / §4 的 Release 说明文件名与当前版本对齐（0.2.1，不带 `v`）
- 重命名 `docs/release-notes/v0.1.0.md` / `v0.1.1.md` / `v0.2.0.md` / `v0.2.1.md` —— 改为 `0.1.0.md` / `0.1.1.md` / `0.2.0.md` / `0.2.1.md`（对齐系列仓：文件名 = `versionName` 不带 `v`，`v` 前缀只属于发版 tag）；**git tag 不动**
- 调整 `docs/release-notes/README.md` —— 文件名口径改为 `versionName`（不带 `v`）并说明 `v` 只属于 tag；「别写这些」补引言块与版本标题行；发版流程与写完对照清单同步新文件名
- 调整 `docs/README.md` —— 索引引言块与结尾提醒对齐系列仓措辞；四张表的一句话定位压到一行能读完；「参考资料」补 `release-notes/` 目录入口行，四份单版本说明链接改新文件名
- 调整 `docs/MAINTENANCE.md` —— 收尾清单的 Release 说明路径去掉 `v` 前缀

### 事故与结论（2026-10-22）

- 现象：双 CrashCore；`start.sh start` 报 `rules-cnip: line count mismatch`；PC WiFi 已连接但无网，部分域名 DNS 失败
- 根因 1：`init.d/shellcrash` 被启用，`start_old=ON` 下 procd 与 legacy 各拉一个实例；手动 `start.sh start` 与 `guardian.sh` / `start_legacy_wd.sh` 并发，两个启动同时写 `/tmp/ShellCrash/config.yaml`，`rules-cnip.sh` 行数校验失败中止（未 `mv`，原配置未损坏，但本次生成作废）
- 根因 2：在路由器上跑 `rules-dedup.sh --check`（4,154 条规则，O(N²) 约 800 万次匹配），CPU/内存被拖垮，触发 OOM/看门狗重启
- 处置：disable `init.d/shellcrash`；kill 掉不占端口的 CrashCore；暂停 cron 后只跑一次 `start.sh start`；把 `rules-dedup.sh` 归档到 `config/archive/` 并禁止部署；`rules-cnip.sh` 在恢复时临时 `.disabled`，当前 13,133 条配置稳定运行（可用内存 67 MB）
- 已完成（2026-10-22 维护窗口）：暂停 cron、恢复 `rules-cnip`、单次 `start.sh start`，13,133 → 4,154；单 CrashCore，可用内存 63 MB；`RULE-SET,cnip` / `RULE-SET,cn` 各 1 条；18 段自检通过，广告域仍 REJECT

### 部署验证（2026-10-22）

- 备份：`/etc/ShellCrash/ai-rules-update.sh.bak-adcarve-20261022`、`/etc/ShellCrash/ai-api-check.sh.bak-adcarve-20261022`、`/etc/ShellCrash/yamls/rules.yaml.bak-adcarve-20261022`
- 广告 carve-out 部署时：323 条生成物；运行配置 4,154 条；`RULE-SET,cn` 在 #3227，仍在 ProxyMedia 之前
- 实测：`pagead2.googlesyndication.com` / `www.google-analytics.com` / `googleads.g.doubleclick.net` / `collector.githubapp.com` / `csi.gstatic.com` / `app-measurement.com` 经 `127.0.0.1:7890` 全部 exit=35（REJECT），此前为 200 并下载 59–63 KB
- 实测：`www.google.com` / `github.com` / `dl.google.com` / `chatgpt.com` 仍 exit=0；`googletagmanager.com` / `googletagservices.com` / `liveperson.net` 的 chains 为 `香港WAP → ♻️ 自动选择 → 🚀 节点选择`
- `ai-api-check.sh` 全 18 段通过（exit 0）；CrashCore RSS 53 MB
- 事故恢复后：单 CrashCore、端口 7890/7892/9999、可用内存 67 MB；运行配置 13,133 条（`rules-cnip.sh` 临时 disabled）
- 维护窗口完成后：4,154 条；单 CrashCore；可用内存 63 MB；`RULE-SET,cnip` / `RULE-SET,cn` 各 1 条；18 段自检通过；广告域 exit=35（REJECT），`google.com` / `github.com` / `baidu.com` exit=0
- 副本验证：`rules-cnip` 副本验证后已在维护窗口部署（13,133 → 4,154）；`rules-dedup` 4,154 → 3,943（保护 15 条后 -211），**未部署**
- 仓库/设备哈希对照：`clash_modify.sh` / `fw_nftables.sh` / `start_legacy_wd.sh` / `rules-mid.sh` / `reorder-groups.sh` / `post-sc-update.sh` / `ai-api-check.sh` / `ai-rules-update.sh` / `rules.yaml` / `fake_ip_filter.list` 全部一致；`fake_ip_filter` 的两行差异已补齐（注释保留）
- `rules-cnip.sh` 已入库；设备侧 `/etc/ShellCrash/rules-cnip.sh` 的 sha256 为 `d301054d…`

### 清理（2026-10-23）

- 删除 `.work/` 下 14 个一次性审计抓取（`live-*` / `current-*` / `test-*` 的 `config.yaml`
  与 `proxies.json`，以及 `c2` / `p3` / `conns-new` 三个 json）与两级 `tools/__pycache__`
  —— 都是 `docs/MAINTENANCE.md` §5.3 明说的可再生产物；仓体 21M → 19M
- 保留 `.work/` —— `private-evidence/`（11M 私有证据）、`private-history.bundle`（1.1M 旧历史）、
  `audit-20261022/`（1.2M 审计原文）、`public-nodes/`（1.8M 计划任务状态）、`PROGRESS.md`，
  与 `config/yamls/proxies.yaml`（含节点 uuid 的模板实例），按 §5.3 与上一轮口径均不删
- 补记 —— `docs/DOC-RULES.md` 与 `docs/PITFALLS.md` 两笔纯文档提交此前没有 CHANGELOG 条目

### 清理（2026-10-22）

- 删除 `__pycache__/`（`tools/`、`tools/public-nodes/`、`tools/latency/archive/` 三处，共 156 KB）—— `.gitignore` 已覆盖、[docs/MAINTENANCE.md](docs/MAINTENANCE.md) §5.3 明说可再生；仓体 18M → 17,734 KB（-156 KB）
- 调整 `docs/release-notes/README.md` —— 「形状」补第二行反馈入口，链接固定用绝对地址 `https://github.com/MVennn/ShellcrashRules/issues/new/choose`；明确它不是清单条目，已发布历史正文不回填
- 调整 `docs/README.md` —— RULE-AUDIT 定位补当前口径「13,010 → 4,154」；TOOLS 定位改为自检 / 控制面查询 / 规则审计 / 延迟探测，与 [docs/TOOLS.md](docs/TOOLS.md) 实际章节一致
- 保留 `.work/` —— `private-evidence/`、`private-history.bundle`、`audit-20261022/` 是隐私材料与审计证据原文；`public-nodes/{state.json,screen.log,task.log}` 是计划任务运行状态，均不删

---

## [0.2.1] — 2026-10-22

把节点同步从「只补 hysteria2」泛化为「转换后缺什么补什么」，并修掉几个会反噬的边界。

### 脚本

- 调整 `config/starts/sub-sync.sh` —— 由 `hy2-sync.sh` 重命名并泛化：拿原始订阅与转换后的配置逐节点比对，只补「转换后没有的」；转换器将来支持某类节点时块会自动变空，不会与订阅重名
- 修复 `config/starts/sub-sync.sh` —— 策略组也是 `- { name: X, type: select, proxies: [...] }` 形状且列表里含 HY2 名字，必须用 `server:` 过滤，否则整组会被当成节点写进 proxies
- 新增 `config/starts/sub-sync.sh` —— 基准少于 10 个节点或待补超过 20 个时保留旧块，避免解析异常把订阅节点整批重复写入
- 调整 `config/starts/clash_modify.sh` —— 调用点改为 `sub-sync.sh`
- 调整 `config/yamls/proxy-groups.yaml` —— filter 追加 `HY2`：`日本JP-HY2` / `韩国KR-HY2` 之前根本不在组里，guardian 的候选有一半是空的
- 调整 `config/yamls/proxies.example.yaml` —— 说明改为 SUB-SYNC 块

### 部署验证（2026-10-22）

- 备份：`/etc/ShellCrash/starts/clash_modify.sh.bak-subsync-20261022`、`/etc/ShellCrash/yamls/proxy-groups.yaml.bak-subsync-20261022`
- 真实基准 28 个、待补 4 个；模拟「转换器已支持 HY2」时块变 0 个，恢复后回到 4 个
- 组内成员：印度×3、日本JP-HY2、韩国KR-HY2、新加坡×4、台湾-优化3（香港HK-HY2 被 exclude-filter 挡掉）
- `cc='SG'`；`gemini.google.com/app` 200 / 0.29s；可用内存 57MB

---

## [0.2.0] — 2026-10-22

新增订阅刷新后的 Hysteria2 节点自动同步；Gemini 干净出口从 vmess 池改到 HY2 池。

### 规则

- 新增 `DOMAIN-SUFFIX,z.ai,🎯 全球直连` —— ZCode 账号/项目 Token API 不再落到默认代理的香港出口；路由器直连实测 0.34s，原路径 project token 15s 超时
- 新增 `DOMAIN-SUFFIX,bigmodel.cn,🎯 全球直连` —— 与 Z.ai 账号相关的国内端点保持直连

### 脚本

- 新增 `config/starts/hy2-sync.sh` —— 生成配置前用 UA `clash.meta` 拉机场**原始**订阅，把 hysteria2 节点重写进 `yamls/proxies.yaml` 的 `# >>> HY2-AUTO` 块；6 小时节流，拉取失败或抽到 0 个都保留旧块、不阻断构建
- 调整 `config/starts/clash_modify.sh` —— `modify_yaml()` 开头调用 `hy2-sync.sh`，start 与 hotupdate 两条路径都覆盖

### 配置

- 调整 `config/yamls/proxy-groups.yaml` —— `🤖 AI网页` / `🤖 干净出口` 的 filter 从 `(印度|India|IN|台湾-优化3)` 放宽为 `(印度|India|IN|台湾-优化3|新加坡)`
- 调整 `config/yamls/proxies.example.yaml` —— 说明 HY2 节点由 `hy2-sync.sh` 自动同步，不需要手填

### 生成器

- 调整 `config/generators/ai-rules-update.sh` —— 顶部覆盖段加入上述两条，并在生成后校验；`config/generated/rules.yaml` 已用路由器生成物同步（306 条）
- 调整 `docs/RULE-AUDIT.md` —— 记录本次 +2 条与原因；审计表 `00_custom` 201 为 2026-10-19 旧快照

### 根因：HY2 池被两层静默隐藏

- 机场按**精确 UA** 给节点集：`clash.meta` 返回 50 条含 4 个 hysteria2；`clash.meta/mihomo`（ShellCrash 转换器实际传的）只回 46 条且 0 个 HY2
- 订阅转换器 `url.v1.mk` 的 `target=clash` 不认 hysteria2，整类丢弃且不报错；`target=mihomo` 被该服务拒绝（`Invalid target!`）
- 机场把「剩余流量 / 套餐到期 / 过滤掉N条线路」三个占位节点也定义成 `type: hysteria2`，同步时必须按名字排除
- 后果：vmess 池 5 个候选（含手机同款「新加坡-优化3」）全部 `cc=CN`，HY2 池 4 个全部 `cc=SG` —— 唯一能用的那批恰好被藏掉了

### 部署验证（2026-10-22）

- 备份：`/root/backup/pre-zai-20261022-020452`、`/etc/ShellCrash/yamls/proxies.yaml.bak-auto-20261022`
- 生成器：306 条；`z.ai` / `bigmodel.cn` 在第 21–22 行
- `hotupdate`：成功；`/tmp/ShellCrash/config.yaml` 第 500–501 行命中 `🎯 全球直连`
- `ai-api-check.sh`：17 段全过；1 个既有 WARN（`🤖 AI网页` 出口 = 新加坡-优化3，与本次无关）
- HY2 同步：`hy2=4`、`proxies=34`；删掉节流戳后重跑 hotupdate，节点与选择均保住
- 出口判定：`var cc='SG'`；`gemini.google.com/app` 200 / 0.34s；可用内存 57MB

---

## [0.1.1] — 2026-10-22

与设备上实际运行的看门狗对齐。设备侧在公开化之后补了内存闸门，
仓库仍停留在旧快照；本次收回仓库。

### 脚本

- 修复 `config/starts/start_legacy_wd.sh` —— 补上 `memgate` 内存闸门（内存不足时跳过本轮拉起，打断 OOM → 拉起 → 再 OOM 的循环）
- 修复 `config/starts/start_legacy_wd.sh` —— 陈旧锁判断从 `stat -c %Y` 改为 `date -r`，不再依赖设备上不支持的 `stat -c`

### 文档

- 修复 `docs/PITFALLS.md` —— 出口策略从「绝不降级到非印度节点」改为「台湾优先、印度兜底」，与 2026-10-21 的实测一致

---

## [0.1.0] — 2026-10-21

首次公开版。仓库从私有运维仓整理为可独立阅读、可复用的参考实现。

### 公开化

- 调整 仓库范围 —— 移除订阅原文、节点凭据、原始审计证据与内部进度台账；公开树只保留配置、规则、脚本、文档与门面资源
- 修复 隐私 —— 服务器域名、WS Host、IPv6 PD 前缀、出口 IP、本机路径全部改为占位符或示例值
- 修复 凭据 —— 仓库不保存节点 UUID、订阅 token 或控制 API secret；真实 `proxies.yaml` 由 `.gitignore` 排除
- 新增 密钥守卫 —— `tools/check-secrets.py` 扫描订阅链接、节点 URI、私钥块与 shadow 哈希，CI 强制执行
- 调整 忽略规则 —— `.gitignore` 排除 `proxies.yaml`、订阅原文、私钥与 `.work/`

### 配置

- 调整 `config/yamls/proxies.example.yaml` —— 真实服务器域名与 WS Host 改为 `<YOUR-NODE-SERVER>` / `<YOUR-WS-HOST>`，UUID 保持占位符
- 调整 `firewall/tables/*.nft` —— IPv6 来源集合改用 ULA / link-local；使用运营商 PD 时由部署者自行加入前缀
- 调整 `config/yamls/proxy-groups.yaml` —— 策略组名与节点名保留为示例，换订阅后按自己的名字改

### 文档

- 调整 根 README —— 面向使用者的门面：这是什么 / 环境要求 / 使用 / 目录 / 安全与隐私 / 反馈 / 免责声明 / 鸣谢 / 许可证
- 调整 `docs/SECRETS.md` —— 重写为公开版：只写读取方式、位置与轮换顺序
- 调整 `docs/UPSTREAM.md` —— 重写与 `OpenwrtOpsToolkit` 的边界，移除私有仓与证据库表述
- 调整 `docs/DEPLOY.md` / `docs/MAINTENANCE.md` / `docs/TOOLS.md` / `docs/TROUBLESHOOTING.md` —— 规则审计列表改用 `third-party/ACL4SSR/Clash`，移除证据路径
- 调整 `docs/DOC-RULES.md` / `docs/README.md` —— 索引与规则按公开树重建
- 调整 `docs/RULE-AUDIT.md` —— 保留审计结论，移除原始证据链接与内部路径
- 调整 `NOTICE` / `third-party/README.md` —— 移除证据库与私有仓表述

### CI

- 调整 CI —— 保留凭据守卫、Shell 语法与文档自检，新增密钥扫描
