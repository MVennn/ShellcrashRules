# 配置生成链路与运行期架构

> **一句话**：这份配置是怎么长出来的、运行时谁在管、哪些文件归谁 ——
> 以及**最坏情况下会怎么悄悄坏掉**（§5 是本篇最重要的一节）。

<a id="arch-gen"></a>

## 1. 生成期：从订阅到 config.yaml

### 1.1 全链路

```
机场订阅
   │  ShellCrash 订阅转换（server_link=2 → api.v1.mk；rule_link=1 → ACL4SSR 全能优化版）
   │  ※ provider_temp_clash 是死设置，改它没用
   ▼
基础 config.yaml（13k 条模板规则）
   │  写入 /etc/ShellCrash/config.yaml（持久）→ 运行期副本在 /tmp/ShellCrash/config.yaml（tmpfs）
   ▼
starts/clash_modify.sh  ← 合并链路的入口（本仓待补，设备侧在跑）
   │  merger_yaml 合并四份来源：
   │    yamls/user.yaml          → 顶层内核参数（tcp-concurrent / find-process-mode / profile.*）
   │    yamls/proxy-groups.yaml  → 自定义策略组（🤖 AI接口 / 🤖 AI网页 / 🤖 干净出口 / 🎬 B站解锁 / 📺 大流量 + 地区组）
   │    yamls/proxies.yaml       → 自定义节点（HY2 池，由 sub-sync.sh 在生成配置前补齐）
   │    yamls/rules.yaml         → AI 分流规则（置顶，在所有模板规则之前）
   │  同时 cat 进 fake_ip_filter 与 fake_ip_filter.list 合成 fake-ip 排除清单
   ▼
钩子 ① rules-porn.sh      注入 porn provider（MetaCubeX category-porn，6,520 域名 / 日更）
   │                      RULE-SET,porn 规则本身由 rules.yaml 的 I 段提供
   ▼
钩子 ② rules-mid.sh        插 - RULE-SET,cn,🎯 全球直连
   │                      （最后一条「📲 电报消息」之后，第一条「🌍 国外媒体」之前）
   ▼
钩子 ③ rules-cnip.sh       把 8,980 条内联 CN IP-CIDR 折叠成一条 RULE-SET,cnip
   │                      （rule-providers.cnip：file / ipcidr / mrs；13k → 4.1k 条）
   ▼
钩子 ④ reorder-groups.sh   ① proxy-groups 同名去重（保留首次出现）
   │                      ② 组内重复 key 清理 / 机场伪节点剔除
   │                      ③ 组顺序重排（常用入口 → 专用出口 → 地区组 → 工具 → 内部子组）
   │                      ④ 成员/节点重排（主选择器；手动/自动组按地区）
   │                      ⑤ mixed-port 归一（去掉重复的 host 前缀）
   ▼
mihomo 校验（CrashCore -t）→ 加载
   ▼
运行期 config.yaml（/tmp/ShellCrash/config.yaml）
```

### 1.2 四个钩子的分工

| 钩子 | 解决什么 | 关键约束 |
|---|---|---|
| `rules-porn.sh` | 手写的成人站名单只覆盖大站，未列到的小站会静默回落默认出口。注入上游 `category-porn` provider（6,520 域名 / 日更）做系统性兜底 | **幂等**；provider 键不能变成顶层重复键（与 `cn:` 同缩进）；写前校验行数、原子替换；目标组不存在时跳过 |
| `rules-mid.sh` | 模板把「宽泛代理」（ProxyMedia / ProxyLite）排在「CN 直连」之前 → `.hk`、Steam 中国等 CN 站点被绕路。插一行 CN 直连中间层即可一次性解决 | **幂等**；写前先在同目录写临时文件并做完整性校验，全部通过才 `mv` 原子替换；任何失败都不动原文件；预检 `rule-providers.cn` 必须存在且 `behavior: domain` / `format: mrs` |
| `rules-cnip.sh` | 模板把约 9,631 条 IP-CIDR 内联在配置里，其中 8,980 条目标是 `🎯 全球直连` → 13k 行配置、内存和加载时间都高。折叠成 `cnip` provider 后 13,133 → 4,154 条 | **幂等**；provider 键不能变成顶层重复键；删除/插入前做行号、规则数、IP-CIDR 数、逐行重建四重校验；失败不 `mv` |
| `reorder-groups.sh` | ShellCrash 的 `merger_yaml` 把用户自定义组**追加**进基础配置，而基础配置本身是上一次合并结果的快照 → 同名组重复出现 → YAML 重复 key → mihomo 拒载 | 同名组保留**第一次出现**（merger_yaml 把最新定义放在最前），丢弃后续陈旧副本；同一组块内重复 key 一并丢弃 |

> **为什么这四个钩子必须放在 `merger_yaml` 之后、`test_yaml`（校验）之前** ——
> 早了拿不到合并结果，晚了校验已经过了。位置写死在 `starts/clash_modify.sh` 里，
> ShellCrash 官方更新会覆盖该文件，由 `post-sc-update.sh` 按标记串恢复。

### 1.3 规则生成器

`config/generators/ai-rules-update.sh` 是**唯一**能写 `yamls/rules.yaml` 的东西：

- 数据源：MetaCubeX/meta-rules-dat 的 `geosite/category-ai-chat-!cn`（meta 分支，日更）；
- 输出：`/etc/ShellCrash/yamls/rules.yaml`；
- 写前校验：下载内容必须含 `payload:`，否则**什么都不改**并退出 1；
- 写后校验：检查前若干行（历史上只查前 3 行 → 每周误报「覆盖规则丢失」，已修）；
- 末尾追加「分类修正层」（广告优先 → AI 语义修正 → Bing/Copilot → OneDrive/SharePoint →
  Sentry/Disney → CN 例外），必须保持在模板规则**之前**；
- 分类修正层顶部另有 **Google 广告/追踪 carve-out**（2026-10-22）：`doubleclick.net` /
  `googlesyndication.com` / `googleadservices.com` / `google-analytics.com` / `csi.gstatic.com` /
  `collector.githubapp.com` / `app-measurement.com` 等必须在 `DOMAIN-SUFFIX,google.com` /
  `DOMAIN-KEYWORD,google` 之前，否则模板 BanAD 的广告 REJECT 会被整段遮蔽；
- geosite 之前另有**共享 SaaS 覆盖**（`envato*` / `liveperson` / `datadoghq`），
  避免上游误收把素材市场、客服聊天、RUM 流量带进 AI 出口；
- 生成时按 `(类型, 域名)` 去重，**保留首次出现**：顶部 Google 服务覆盖优先，
  后续 geosite / 修正层里的同键规则会被丢弃（修复 `generativelanguage.googleapis.com`
  被 geosite AI 规则抢走的问题）；
- 顶部另有「高带宽直连」段（G 段，2026-10-21）：`dl.google.com` / `gvt1.com` /
  `gvt1-cn.com` / `jetbrains.com` 直连，避免被 `DOMAIN-SUFFIX,google.com` 的干净出口
  规则或 `MATCH` 带去代理；实测直连比代理快 3–7 倍且不耗机场流量。

`config/generators/auto-update.sh` 是每周维护入口（cron `30 4 * * 0`）：
先跑规则生成器，**成功才**跑 `task/task.sh hotupdate`；生成器失败就跳过 hotupdate，
避免把半成品规则推到线上；hotupdate 失败再降级用 `start.sh start` 本地重建。

<a id="arch-run"></a>

## 2. 运行期

### 2.1 进程与端口

| 组件 | 说明 |
|---|---|
| mihomo（`CrashCore`） | ShellCrash 拉起。监听 redir **7892**、mixed **7890**、控制 API **9999**、DNS **1053** |
| **单一主人** | procd 的 `S99shellcrash` 已 `disable`，只保留看门狗 legacy 路径。两个主人会同时拉起两个实例（抢不到端口但白占 ~50 MB 内存，实测 MemAvailable 从 86 MB 掉到 12 MB） |
| 看门狗 | cron 每分钟 `starts/start_legacy_wd.sh shellcrash`；必须先 `mkdir -p /tmp/ShellCrash`（`/tmp` 是 tmpfs，重启后目录不存在 → 锁目录永远建不出来 → 代理离线 6 分钟） |

### 2.2 Redir 透明代理的实际覆盖范围

**Redir 只代理 TCP。UDP 一律直出 WAN** —— 这是本仓一半坑的根源。

- 代理端口集：`{22, 80, 443, 8080, 8443}`，另加 **FCM 5228** 与 **DoQ 19302**
  （`fw_nftables.sh` 的 `FCM_DOQ_PORT_MARKER`；不加的话真实 IP 目标会直连、暴露国内出口 IP）。
- 非白名单端口的**真实 IP 目标直接放行**（实测小米平板与 Google 全球 DoQ 直连）。
- **路由器本机流量走 OUTPUT，不走 PREROUTING** → 本仓三张表的 prerouting 规则
  对路由器自己无效；验证 LAN 行为必须从客户端发起。
- **路由器自己的 `curl` 不走透明代理** → 测 API 必须显式 `-x http://127.0.0.1:7890`。

### 2.3 三张独立 nft 表

**为什么必须独立**：ShellCrash 每次重启都会**重写 `inet shellcrash` 整表** ——
直接 `nft add rule` 加的东西会被抹掉。要么改 `fw_nftables.sh`（可持久但受官方更新覆盖），
要么用独立表 + `rc.local`。

| 表 | family / hook / priority | 作用 | 加载时机 |
|---|---|---|---|
| `inet quicguard` | filter / prerouting / **-150** | 全局拒绝 QUIC/DoQ：UDP `{443, 8443, 4433, 5226, 5228, 8081, 8883, 19302}`；另单独覆盖假 IP 段 `198.18.0.0/15`、假 IPv6 `fc00::/16`、Google 国内边缘段 `203.208.32.0/19`、国内 IPv6 段 `2401:3800::/32`；B站 API 段 `157.148.134.0/24` / `27.37.206.0/24`（**仅 IPv4**；`api.bilibili.com` 无公开 AAAA，`2408:8756::/31` 是联通大段、含腾讯 CDN，2026-10-22 已撤回）在 CN 豁免**之前**单独 reject UDP 443/8443（强制回落 TCP，评论属地才能被域名规则接管） | `rc.local` 开机加载；守护进程每 5 分钟补载 |
| `inet googlecn` | nat / prerouting / **-105** | LAN 发往 Google 国内边缘段（`203.208.32.0/19`、`2401:3800::/32`）的 TCP `{80,443}` 重定向到 **7892**，让域名规则（AI 组 / 直连）有机会生效；IPv6 按 `iifname "br-lan"` 匹配（不写死运营商 PD 前缀） | 同上 |
| `inet googleroute` | nat / prerouting / **dstnat - 4** | ① LAN 的 53 端口一律重定向到 mihomo DNS **1053**（避免 ShellCrash 重建表那几秒 DNS 漏到 dnsmasq 拿到污染结果）；② Google 推送/Play 端口 `{5222,5223,5224,5226,5228,8081,8883}` → 7892；③ fake-IPv6 段 `fc00::/16` → 7892；IPv6 同理按 `iifname "br-lan"` 匹配 | **必须等 1053 端口就绪（最多 90s）再加载** —— 等不到就不加载，否则重启后出现「连上没网」死窗口 |

### 2.4 flow offload 与 Redir 的冲突面

| 项 | 结论 | 证据状态 |
|---|---|---|
| 硬件 offload 的**存量连接**不会重新走链 | **已确认**：改端口/规则后必须清 conntrack 才生效 | 实测结论（见仓库根 [CHANGELOG.md](../CHANGELOG.md) 与 [PITFALLS.md](PITFALLS.md)） |
| offload 的流量是否**整体绕过** Redir 重定向 | **待补**：本仓尚无直接实测，只在「存量连接不重走链」这个层面确认过 | ❌ 缺实测 |
| 三张独立表与 offload 的交互 | **待补**：表是 nat/filter hook，改动后同样受 conntrack 影响 | ❌ 缺实测 |

> **这条别当结论用** —— 前两行是实测，后两行是推断。补测之前，
> 判断 offload 相关故障请按「改完规则 → 清 conntrack → 重测」这条保守路径走。

<a id="arch-ownership"></a>

## 3. 文件所有权表

**这一节决定「改哪个仓」。** 改错地方 = 白改。

| 文件 / 批次 | 归属 | 谁写 | 谁加载 / 触发 |
|---|---|---|---|
| `config/yamls/*.yaml` | **本仓**（`ShellcrashRules`） | 人工维护；`rules.yaml` 由 `ai-rules-update.sh` 生成 | `starts/clash_modify.sh` 的 merger_yaml |
| `config/hooks/*.sh` | **本仓** | 人工维护 | `starts/clash_modify.sh`（merger_yaml 之后） |
| `config/generators/*.sh` | **本仓** | 人工维护 | cron `30 4 * * 0`（auto-update.sh → ai-rules-update.sh → hotupdate） |
| `config/starts/fw_nftables.sh` | **本仓** | 人工维护（打补丁的上游件） | ShellCrash 启动时生成 `inet shellcrash`；`post-sc-update.sh` 在官方更新后恢复 |
| `config/starts/start_legacy_wd.sh` | **本仓** | 人工维护（打补丁的上游件） | cron 每分钟 |
| `config/starts/clash_modify.sh` | **本仓（待补）** | — | ShellCrash 启动 / 订阅更新 |
| `config/ai-api-check.sh` | **本仓** | 人工维护 | 人工（订阅更新后必跑） |
| `config/post-sc-update.sh` | **本仓** | 人工维护 | 人工（ShellCrash 官方脚本更新后） |
| `firewall/tables/*.nft` | **本仓**（内容） | 人工维护 | **`rc.local`（`AX3000TOpenwrt` 仓）** 开机加载 + 守护进程补载 |
| `tools/latency/archive/**` | **本仓**（归档件） | 人工维护 | 不部署，仅留档 |
| `mihomo/` `cdn/` 诊断工具（规则审计 / 控制面诊断 / 站点可达性专项） | **`OpenwrtOpsToolkit` 仓**（公开） | 那边维护 | PC 侧人工执行，不上设备 |
| `docs/**` | **本仓** | 人工维护 | — |
| `rc.local` | **`AX3000TOpenwrt` 仓** | 那边 | 开机加载本仓三张 nft 表 |
| `guardian.sh`（守护进程） | **`AX3000TOpenwrt` 仓** | 那边 | cron 每 5 分钟：补载三表、节点劣化复位、干净出口守护 |
| `bulk-guard.sh`（大流量守卫） | **`OpenwrtOpsToolkit` 仓** | 那边 | cron 每 10 分钟：按真实吞吐切 `📺 大流量`（公共池 ↔ 机场） |
| `rule-providers.porn`（`category-porn.mrs`） | **上游 MetaCubeX** | 本仓 `rules-porn.sh` 只注入 provider 条目；mihomo 按 `interval: 86400` 自行更新 | `RULE-SET,porn,📺 大流量`（规则由 `ai-rules-update.sh` I 段输出） |
| `/etc/mixedport.nft`（7890 收口） | **`AX3000TOpenwrt` 仓** | 那边 | `rc.local` 引用 —— ⚠️ **该文件在本仓与设备上都需确认存在**（历史记录里被引用但缺失） |
| `recover-now.sh` 等恢复脚本 | **`AX3000TOpenwrt` 仓** | 那边 | 人工 |
| ShellCrash 本体（`/etc/ShellCrash` 其余部分） | **ShellCrash 官方** | 官方更新 | 官方脚本更新会覆盖 `starts/` → 由 `post-sc-update.sh` 恢复本仓的补丁 |

**控制台（`OpenwrtConsole` 仓）的写入边界**：
控制台**只能经 `modern-shellcrash` 受控写**本仓的 yaml 与 nft 表 ——
走接口、走校验、写前备份、写后能被 `ai-api-check.sh` 复验。
**禁止自由文本覆盖** `yamls/*.yaml` 与 `config.yaml`（理由见 §5）。

<a id="arch-params"></a>

## 4. 关键参数表

| 参数 | 值 | 位置 | 作用 / 注意 |
|---|---|---|---|
| mixed-port | `7890` | ShellCrash 内置 | 本地混合口。**测 API 必须 `-x http://127.0.0.1:7890`**；LAN 侧由 `inet mixedport` 表收口（input priority -200） |
| redir-port | `7892` | ShellCrash 内置 | 透明代理重定向端口；`googlecn.nft` / `googleroute.nft` 都 redirect 到它 |
| external-controller | `9999` | ShellCrash 内置 | 控制 API / zashboard 面板；**带 `secret`**，面板侧密码为空会 401 |
| DNS 监听 | `1053` | mihomo | `googleroute.nft` 把 LAN 53 重定向到它；`rc.local` 加载该表前必须等它就绪 |
| 代理端口集 | `{22,80,443,8080,8443}` + `5228`(FCM) + `19302`(DoQ) | `config/starts/fw_nftables.sh` | 只有这些端口进代理；其余真实 IP 目标直连 |
| QUIC 拒绝端口 | `{443,8443,4433,5226,5228,8081,8883,19302}` | `firewall/tables/quicguard.nft` | UDP 一律阻断，浏览器回落 TCP |
| Google 推送端口 | `{5222,5223,5224,5226,5228,8081,8883}` | `firewall/tables/googleroute.nft` | 送进 7892 |
| `tcp-concurrent` | `true` | `config/yamls/user.yaml` | 多 IP 域名并发建连，降低首包延迟 |
| `find-process-mode` | `"off"` | `config/yamls/user.yaml` | 路由器上 PROCESS-NAME 永不命中，关掉省 CPU |
| `profile.store-fake-ip` | `true` | `config/yamls/user.yaml` | fake-IP 与域名映射写 cache.db，重启后仍按域名分流 |
| `profile.store-selected` | `true` | `config/yamls/user.yaml` | **必须有**：干净出口组成员会随订阅变化，没它重启后被重置成第一个成员（实测恰是那条不稳定的订阅入口） |
| `tolerance` | `50` | `config/yamls/proxy-groups.yaml`（🤖 AI接口） | 延迟差 < 50ms 不换节点 → 出口 IP 稳定 |
| `exclude-filter` | 含 `香港\|HK\|Hong Kong\|公共` | `config/yamls/proxy-groups.yaml` | 排除香港出口（OpenAI 上游会返回 `unsupported_country_region_territory`）与公开节点（陌生人的出口不可用于 AI 流量） |
| 🤖 AI网页 类型 | `select` + `filter: (印度\|India\|IN\|台湾-优化3\|新加坡\|HY2)` | `config/yamls/proxy-groups.yaml` | **不能用 url-test** —— 按延迟会漂到被 Google 判为 CN 的节点；`exclude-filter` 排除香港与公共节点 |
| 🤖 干净出口 | `select` + 印度/台湾-优化3/新加坡/HY2 过滤 | `config/yamls/proxy-groups.yaml` | 唯一经 Google 侧 `cc` 实测判为非 CN 的稳定出口；`exclude-filter` 排除香港与公共节点 |
| 🎬 B站解锁 | `select` + `filter: (香港WAP\|台湾-优化3\|日本-优化\|新加坡-优化3)` | `config/yamls/proxy-groups.yaml` | B站 API 域（`api/app/cm.bilibili.com`、`biliapi.com/.net`）的出口，规则见 `rules.yaml` J 段。**HY2 池到大陆方向不通**（香港/韩国能连 gstatic，但百度/知乎/B站 TLS EOF/超时；日本/新加坡节点本身超时）；实测 vmess 的香港WAP/台湾-优化3/日本-优化/新加坡-优化3 在 B站 `x/web-interface/zone` 分别显示对应地区，默认 `🇭🇰 香港WAP-优化`。CDN（bilivideo/hdslb/biliimg/acgvideo）规则用字面 `DIRECT`（`respect-rules` 的 DNS 才走 `direct-nameserver`），由 `clash_modify.sh` 单独指定上游 DNS；设备侧 `ipv6_dns=OFF`（Akamai IPv6 实测 22 KB/s），视频不占机场流量。MCDN/PCDN 域（`*.mcdn.bilivideo.cn`、`*.edge.mountaintoys.cn`）在生成的 `hosts:` 里指到 `127.0.0.1`，避免播放器踩到 6–11 KB/s 的劣化 P2P 节点。属地按请求源 IP 判定，没有独立检测接口；评论接口是 `cm.bilibili.com`，只加 `api` 不够 |
| 🛟 主备自动 | `fallback`：`♻️ 自动选择` → `🆓 公共备用` | `config/yamls/proxy-groups.yaml` | `🚀 节点选择` 的默认项；机场节点正常时走 `♻️ 自动选择`，机场全挂时自动落到公共备用。**不放 DIRECT**，避免两边都挂时静默直连泄露真实 IP |
| 🆓 公共备用 | `url-test` + `filter: 🆓 公共` | `config/yamls/proxy-groups.yaml` | 机场全挂时的最后网页通道：作为 `🛟 主备自动` 的兜底成员，同时保留在 `🚀 节点选择` 末尾供手动选择。节点由 PC 侧 `tools/public-nodes/screen.py` 从 6 个源筛选后写入路由器本地 `yamls/proxies.yaml`（不入库）；2026-10-23 实测池 1271 条、实测 259 条、保留 10 条（8 条存活，211–584ms），公共-08 对 OVH 2MB 实测 889 KB/s。**不可用于 AI / 网银 / 邮箱** |
| 📺 大流量 | `select`：`🆓 公共备用` → `♻️ 自动选择` | `config/yamls/proxy-groups.yaml` | 承载 `rules.yaml` H/I/I2/K 段：Steam / Epic 内容 CDN、成人站及其自有 CDN（`RULE-SET,porn` 兜底）、Telegram 两个 DC 段、游戏补丁（暴雪/Riot/EA/育碧/Xbox/GOG）、媒体 CDN（Reddit/Imgur/Pixiv/Vimeo/Twitch/SourceForge/`replicate.delivery`）、HuggingFace LFS / GitHub release / NVIDIA+AMD 驱动 / Maven，以及探测域 `proof.ovh.net`。默认走公共池省机场流量；`bulk-guard.sh`（`OpenwrtOpsToolkit` 仓）用 `proof.ovh.net` 对钉点/候选做二次校验，吞吐低于 800 KB/s 时切回机场并冷却 1 小时。**订阅流媒体刻意不进**：YouTube 全族必须走干净出口（Google cc），Netflix/Disney 对公共节点几乎必然判代理；成人站与 Telegram 不绑账号/支付出口、全程加密，所以接进来 |
| 𝕏 媒体 | `fallback`：`𝕏 媒体-HY2` → `𝕏 媒体-备用` | `config/yamls/proxy-groups.yaml` | X/Twitter 图片与视频 CDN（`twimg.com`）专用出口，规则见 `rules.yaml` X 段。2026-10-23 白天实测：VMess+WS 并发建连会被串行化（10 并发真实图片 1.9–5.9s）；HY2（QUIC 多路复用）0.35s、单张 0.21–0.25s，所以 HY2 主组只收 HY2、不掺 VMess。当晚 HY2 对 `pbs.twimg.com` 4/4 超时、VMess 5/5 200，于是拆成 HY2 主 + VMess 备的 fallback：HY2 正常时仍享受并发，整池劣化时自动落到 VMess（实测 `pbs` 200/0.26–0.28s）。健康检查统一用 `pbs.twimg.com/robots.txt`（200、稳定；根路径 400 抖动大） |
| 规则更新 cron | `30 4 * * 0` | 路由器 crontab | 每周跑 `auto-update.sh`（规则生成 + hotupdate） |
| 看门狗 cron | `* * * * *` | 路由器 crontab | 每分钟拉起代理（`starts/start_legacy_wd.sh shellcrash`） |
| 守护 cron | `*/5 * * * *` | 路由器 crontab | 每 5 分钟自愈（补载三表、节点劣化复位、干净出口守护）—— 脚本在 `AX3000TOpenwrt` 仓 |
| 大流量守卫 cron | `*/10 * * * *` | 路由器 crontab | 每 10 分钟判定一次（空闲时每 2 小时实测一次吞吐）—— 脚本在 `OpenwrtOpsToolkit` 仓，组名来自 `/etc/openwrt-ops/device.conf` |
| 自检段数 | 18 段 | `config/ai-api-check.sh` | 订阅更新后必跑；退出码 0/1 |

### 4.1 组名与规则目标的约定

| 类别 | 命名 | 是否被规则引用 | 说明 |
|---|---|---|---|
| 地区组 | 国旗 emoji + 地区名（`🇭🇰 香港节点` / `🇸🇬 新加坡节点` …） | **否** | 只作为 `🚀 节点选择` / `🤖 人工智能` 的手动选项；没有任何规则指向它们 |
| 功能组 | 图标 emoji + 功能名（`🤖` AI 家族 / `🎥` 流媒体 / `🛑` 广告 / `🎯` 直连 / `🚀` `♻️` `🛟` 调度） | 是 | 规则只指向功能组 |
| 内置目标 | `GLOBAL` / `DIRECT` / `REJECT` | 是 | mihomo 内置：`DIRECT`/`REJECT` 是关键字，`GLOBAL` 是全局选择器；都不能加 emoji 或改名。控制台会隐藏 `GLOBAL`，面板（zashboard）仍会显示 |

- 代理组在面板里的顺序（由 `reorder-groups.sh` 维护）：
  `🚀 节点选择` → `🛟 主备自动` → `♻️ 自动选择` → `🚀 手动切换` →
  `🤖 AI接口` → `🤖 人工智能` → `🤖 AI网页` → `🤖 干净出口` →
  `🔗 GitHub 出口` → `🎬 B站解锁` → `𝕏 媒体` → `📺 大流量` → `🆓 公共备用` →
  地区组（港/日/台/新/美/印/加/德/英）→ 流媒体组 → 工具组 →
  `𝕏 媒体-HY2` / `𝕏 媒体-备用`（内部子组放最后，避免干扰常用组）。
- `🚀 节点选择` 的成员顺序（由 `reorder-groups.sh` 维护）：
  `🛟 主备自动`（默认）→ `♻️ 自动选择` → `🚀 手动切换` → `🤖 AI接口` →
  `🔗 GitHub 出口` → `🎬 B站解锁` → `𝕏 媒体` → `📺 大流量` → `🆓 公共备用` →
  地区组（港/日/台/新/美/印/加/德/英）→ `DIRECT`。
- `🚀 手动切换` / `♻️ 自动选择` 的节点顺序：香港 → 日本 → 台湾 → 新加坡 →
  美国 → 印度 → 加拿大 → 德国 → 英国；同地区内保持订阅原顺序（稳定排序）。
  注意：`store-selected` 会记住面板里的最后一次手动选择；设备上的守护进程
  在出口劣化时会把 `🚀 节点选择` 复位到 `♻️ 自动选择`，所以「默认项是主备自动」
  并不等于运行期一直在主备自动上（见 [PITFALLS.md](PITFALLS.md)「主备自动的兜底实际不生效」）。
- `🐟 漏网之鱼` 同样把 `DIRECT` 收尾。
- 规则行尾的 `#自定义规则` / `#自定义代理` 是 `clash_modify.sh` 的标记，不是组名的一部分。
- 地区组名来自机场模板（例如 `🇺🇲 美国节点` 的旗其实是美国本土外小岛屿），
  订阅更新会重新生成；本仓不改名，避免引用失配。
- 纯中转组（`📲 电报消息` / `📢 谷歌FCM` → `🚀 节点选择`，
  `Ⓜ️ 微软服务` / `🍎 苹果服务` → `DIRECT`）已删除，规则直接指向实际出口。
  只有真正需要独立出口的服务组才保留（如 `🎥 NETFLIX` / `🎥 DisneyP` 锁定新加坡）。
- 内部子组（`𝕏 媒体-HY2` / `𝕏 媒体-备用`）只作为父组 fallback 的成员；
  OpenwrtConsole 默认不单独展示它们的卡片（父组下拉仍可切换），避免列表末尾
  看起来像重复的 `𝕏 媒体`。

### 代理组排序规则（新增组必须遵守）

> **正本**。`config/hooks/reorder-groups.sh` 里的 `order[]` 是实际执行者；
> `config/yamls/proxy-groups.yaml` 的**文件顺序不决定面板顺序**，订阅顺序也不决定。
> 新增 / 改名 / 删除组时，按下表选段落，再同步 `order[]`；漏加不会报错，
> 但该组会按原顺序追加到面板最后。

**组顺序分段**（从常用到兜底）：

| 段 | 段内顺序 | 新组落点 |
|---|---|---|
| 入口/调度 | `🚀 节点选择` → `🛟 主备自动` → `♻️ 自动选择` → `🚀 手动切换` | 固定，不新增 |
| AI 专用 | `🤖 AI接口` → `🤖 人工智能` → `🤖 AI网页` → `🤖 干净出口` | 本段末尾，按「API → 父组 → 网页 → 干净出口」 |
| 服务专用 | `🔗 GitHub 出口` → `🎬 B站解锁` → `𝕏 媒体` | 本段末尾；通用服务在前、单站服务在后 |
| 流量/兜底 | `📺 大流量` → `🆓 公共备用` | 本段末尾 |
| 地区组 | 港 → 日/韩 → 台 → 新 → 美 → 印 → 加 → 德 → 英 | 按地理位置插入；新地区加在本段末尾 |
| 流媒体 | `🎥 NETFLIX` → `🎥 DisneyP` → `🌍 国外媒体` | 本段末尾 |
| 工具/规则 | `🛑 广告拦截` → `🎯 全球直连` → `🐟 漏网之鱼` | 固定，不新增 |
| 内部子组 | `𝕏 媒体-HY2` → `𝕏 媒体-备用` | **所有内部子组都放最后**，不干扰常用组 |

**`🚀 节点选择` 成员分段**：

`🛟 主备自动` → `♻️ 自动选择` → `🚀 手动切换` → 专用组（`🤖 AI接口` →
`🔗 GitHub 出口` → `🎬 B站解锁` → `𝕏 媒体` → `📺 大流量` → `🆓 公共备用`）→
地区组 → `DIRECT`。新成员按段插入；`DIRECT` 永远最后；
内部子组（`𝕏 媒体-HY2` / `𝕏 媒体-备用`）**不要**加进主选择器。

**节点顺序**（`🚀 手动切换` / `♻️ 自动选择`）：

香港 → 日本/韩国 → 台湾 → 新加坡 → 美国 → 印度 → 加拿大 → 德国 → 英国；
同地区内保持订阅原顺序（稳定排序），未知地区排最后。新增地区时在
`reorder-groups.sh` 的 `rank()` 里按地理位置插入，不要用字母序。

**新增 / 改名 / 删除一个组的最小步骤**：

1. 在 `config/yamls/proxy-groups.yaml` 定义组（需要挂进父组就写 `#父组`）。
2. 在 `config/hooks/reorder-groups.sh` 的**组顺序** `order[]` 中按上表插入。
3. 如果它要出现在 `🚀 节点选择` 里，再在**成员顺序** `order[]` 的对应段插入；
   内部子组不要加。
4. 如果它的节点需要手动排序，把组名加到节点排序 pass 的目标列表，
   并在 `rank()` 里补新地区。
5. 用配置副本验证：`sh config/hooks/reorder-groups.sh /tmp/test.yaml`，
   检查「组顺序 / 主选择器成员 / 节点顺序」三处，再部署；
   重启前暂停 `guardian.sh` / `start_legacy_wd.sh` / `bulk-guard.sh` 三条 cron。
   面板侧可用 OpenwrtConsole 的本地 mock 入口验证（见其 CONTRIBUTING「本地 UI 开发」），
   不需要路由器密码。

<a id="arch-failure"></a>

## 5. 降级与失败模式

> **本节是本篇最重要的一节。** 本仓所有配置都经同一条通道进入 mihomo，
> 而这条通道**失败时不报错**。

### 5.1 YAML 顶层 key 重复 = mihomo 直接拒载 → ShellCrash 静默回退基础配置

**现象**：自定义策略组、AI 分流、CN 中间层**全部消失**，
路由看起来「恢复成没改过的样子」；日志里没有明显报错（最多一句「自定义配置文件校验失败」）。
发生在 `config.yaml` 里出现**重复的顶层 key** 时 —— 典型是 `rule-providers:` 顶层重复，
以及 `proxy-groups:` 里同名组重复（表现为 `mapping key "type" already defined`）。

**根因**：

1. YAML 规范不允许同一层出现同名 key；mihomo 解析到就报错并**拒绝加载整个配置**。
2. ShellCrash 遇到「自定义配置校验失败」时，**静默回退到上一次的基础配置**继续跑 ——
   不弹窗、不退出、不写日志。这是为了「宁可少功能也不能断网」，但代价是**所有自定义消失且无提示**。
3. 本仓的链路把两件事叠在一起：基础 config.yaml 本身是**上一次合并结果的快照**
   （含上次的自定义组），而 `merger_yaml` 又把本次的用户自定义组追加进去 →
   同名组必然出现 → 官方去重标记失配时会漏掉残留组 → 重复 key。

**解法**：

| 层 | 做法 |
|---|---|
| 预防（首选） | **不要把 `rule-providers` 写进 `others.yaml` / 用户 yaml** —— 顶层 `rule-providers` 重复会直接拒载。规则集统一走 `rule-providers.cn` 这一个既有 provider |
| 预防 | `reorder-groups.sh` 负责同名组去重（保留首次出现）+ 组内重复 key 清理 + mixed-port 归一 |
| 预防 | 合并后**必须**跑 `CrashCore -t` / `mihomo -t` 校验，通过才热加载 |
| 检测 | `ai-api-check.sh` 第 12 段检查规则文件完整性（空组名 / 原子写 / 组定义）；第 5 段检查分组排序钩子 |
| 检测 | 面板里看不到 `🤖 AI接口` / `🤖 干净出口` 组 → 就是回退了 |
| 兜底 | 回退发生时守护进程会重跑 hotupdate 试图恢复；仍不行就按 §5.2 手工重建 |

### 5.2 其它降级路径

| 失败点 | 表现 | 处置 |
|---|---|---|
| `ai-rules-update.sh` 下载或校验失败 | 什么都不改，退出 1；`auto-update.sh` 跳过 hotupdate | 保留旧 `rules.yaml`（**这就是跳过 hotupdate 的理由**），网络恢复后重跑 |
| `hotupdate` 写 `/tmp/ShellCrash/config.yaml` | mihomo `SAFE_PATHS` 拒绝 + `put_save` 丢弃 HTTP 状态码 → **静默失败** | 必须写 `/etc/ShellCrash/config.yaml`，且**校验 HTTP 状态码**；`ai-api-check.sh` 第 6 段巡检并自动修复 |
| `rules-mid.sh` 预检失败（`rule-providers.cn` 不对） | 不改原文件、退出 1 → 配置里没有 CN 中间层 | 修 provider 后重跑 |
| `rules-mid.sh` / `rules-cnip.sh` / `reorder-groups.sh` 钩子丢失 | ShellCrash 官方更新覆盖了 `starts/clash_modify.sh` | `post-sc-update.sh` 按标记串恢复；`ai-api-check.sh` 第 8 段巡检 CN 中间层 |
| mihomo OOM 被杀 | 9999 监听整个消失、所有 URL 返回 000，约 3 分钟后才恢复 | 瘦身 `config.yaml`（13k 条规则 ≈ 739 KB）、清 `/tmp`（tmpfs 水位守卫 ≥ 80% 触发清理） |
| 配置里出现尾逗号规则 | `rules[16] [DOMAIN-SUFFIX,i.google.dev,] error: format invalid` → 校验失败 → 起不来 | 生成器写规则时不允许空策略名；`ai-api-check.sh` 第 12 段巡检 |
| 单实例与双实例 | 两个 mihomo 实例并存，抢不到端口但白占内存 | 只留一个主人：procd `S99shellcrash` 必须 `disable` |

### 5.3 一条通用判据

**「配置不见了」先怀疑拒载回退，别先怀疑规则写错。**
判据：面板里**自定义组还在不在**。
在 → 配置被加载了，问题在规则顺序或出口；
不在 → 配置被拒载了，走 §5.1。
