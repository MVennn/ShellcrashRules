# 更新日志

> **一句话**：本仓改了什么、为什么改、什么时候改 —— 按版本倒序；每条按对象单列一行，不打包成「代码整理」。

版本命名遵循三段式进位：**有功能更新进次版本（+0.1.0），没有就进补丁版本（+0.0.1）**。
规则正本见 [docs/VERSIONING.md](docs/VERSIONING.md)。
本仓是配置与脚本仓库，没有构建产物；版本号只在本文档头部维护，
发版 tag 与 Release 说明文件名都用它（格式见 [docs/release-notes/README.md](docs/release-notes/README.md)）。

---

## [未发布] — 2026-10-22

### 配置

- 新增 `🎬 B站解锁` 组 —— `select`：`香港WAP` / `台湾-优化3` / `日本-优化` / `新加坡-优化3`，默认 `🇭🇰 香港WAP-优化`；只由 `rules.yaml` J 段的 B站 API 域引用。实测 HY2 池到大陆方向不通（香港/韩国能连 gstatic，但百度/知乎/B站 TLS EOF/超时；日本/新加坡节点本身超时），vmess 的港/台/日/新节点在 B站 `x/web-interface/zone` 分别显示对应地区
- 新增 `📺 大流量` 组 —— `select`：`🆓 公共备用` → `♻️ 自动选择`，只由规则 H 段的大文件下载域引用；默认走公共池省机场流量，吞吐低于阈值时由 `bulk-guard.sh` 切回机场。`reorder-groups.sh` 的成员顺序与兜底插入同步（`🚀 节点选择` 末尾、`DIRECT` 之前）
- 调整 `config/yamls/proxies.example.yaml` —— 说明当前设备不再维护手工节点（节点全部来自订阅 + `sub-sync.sh` 自动补齐），模板只用于额外加备用入口；`cp` 重建时提醒保留 SUB-SYNC 块
- 调整 `config/yamls/proxies.example.yaml` —— 明确设备上的 `proxies.yaml` 有 `SUB-SYNC` / `PUBLIC-NODES` 两个自动块，**禁止整文件覆盖**（2026-10-22 曾因整文件部署冲掉 4 个公开节点）

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
