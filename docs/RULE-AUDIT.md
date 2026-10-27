# ShellCrash 规则分类审计与重组方案（2026-10-19）

> **一句话**：13,010 条分流规则的分类正确性审计结论与分阶段整改方案（原始审计数据未随公开仓发布）。

## 0. 结论

**分类“大体正确，但不够严谨”。** 主服务（Google Play/更新/FCM、AI 主端点、广告拦截、CN 直连主体）没有大问题，
但模板的**顺序**和**宽泛规则**让一部分规则的实际生效目标与声明目标不一致：

- 13,010 条规则中，**9,627 条是 IP 规则（74%）**；在 fake-IP 模式下，域名流量几乎不经过 IP 规则，
  真正做决策的是 **3,378 条域名规则**。
- 域名规则中：2,918 条自身就是最早匹配；196 条被同目标规则冗余覆盖；**161 条实际生效目标与声明不同**
  （16 条严重：一边 DIRECT/REJECT、一边代理；145 条只是代理组不同）。
- 130 个代表域名测试：**6 个分类异常**；另有 1 个“分类正确但功能不通”（OneDrive 直连超时）
  和 1 个“直连疑似被地区封锁”（Epic 403）。
- 广告段 1,604 条，25 条关键词，测试集**无误伤**；但存在覆盖缺口（analytics.google.com、connect.facebook.net 等）。

**可以拆开重组，而且不需要重写 13k 模板。** 推荐三步：
1. **Phase 1（低风险，立即可做）**：在 `yamls/rules.yaml` 末尾加“分类修正层”，修正下面列出的 P0/P1 问题。
2. **Phase 2（中等）**：在服务组之后、ProxyMedia/ProxyLite 之前插入 `RULE-SET,cn,🎯 全球直连`，
   一次性解决 `.hk` 等宽泛代理 TLD 与 CN 直连的顺序冲突。
3. **Phase 3（长期）**：把 17 个内联列表换成 6 个 rule-provider，把 13k 行规则降到几百行。

本文只做审计与方案，**没有修改路由器规则**。原始量化报告与配置快照未随公开仓发布；
审计工具在 `OpenwrtOpsToolkit` 仓的 `mihomo/rule_audit.py`（迁出前在本仓 `tools/rule_audit.py`）。

---

## 1. 审计口径

- 数据：运行配置 `/tmp/ShellCrash/config.yaml`（13,010 条规则、25 个策略组）、
  17 个上游 ruleset（已下载到 `audit/rule-audit-20261019/lists/`）、mihomo `/proxies` 实时组状态。
- 方法：
  1. 按 `ShellClash.ini` 的 ruleset 顺序，把内联规则精确分段回 17 个上游列表；
  2. 按 mihomo 的“先匹配先赢”语义，对每条域名规则计算**最早匹配**（DOMAIN / SUFFIX / KEYWORD），
     得到实际生效目标；
  3. 用 130 个代表域名做端到端匹配，核对目标组；
  4. 核对策略组当前选择与实际出口。
- 口径说明：fake-IP 模式下客户端连接的是 fake-IP，`IP-CIDR` 规则通常不参与域名流量；
  它们主要服务真实 IP 直连/字面 IP 流量。因此重点审计域名层。

---

## 2. 结构画像

### 2.1 类型

| 类型 | 条数 | 占比 |
|---|---:|---:|
| IP-CIDR | 7,912 | 60.8% |
| DOMAIN-SUFFIX | 3,105 | 23.9% |
| IP-CIDR6 | 1,715 | 13.2% |
| DOMAIN | 170 | 1.3% |
| DOMAIN-KEYWORD | 103 | 0.8% |
| PROCESS-NAME | 4 | 0.03% |
| MATCH | 1 | 0.008% |

### 2.2 目标组

| 目标组 | 条数 | 语义 |
|---|---:|---|
| 🎯 全球直连 | 9,659 | DIRECT |
| 🛑 广告拦截 | 1,604 | REJECT |
| 🎥 NETFLIX | 538 | 流媒体（当前 SG） |
| 🚀 节点选择 | 439 | 通用代理（当前 HK WAP） |
| 🌍 国外媒体 | 371 | 媒体代理（当前 节点选择） |
| 🤖 人工智能 | 212 | AI（当前 AI网页 → JP） |
| Ⓜ️ 微软服务 | 79 | 当前 **DIRECT** |
| 📢 谷歌FCM | 44 | 当前 节点选择 |
| 🍎 苹果服务 | 29 | 当前 DIRECT |
| 🎥 DisneyP | 20 | 当前 SG |
| 📲 电报消息 | 13 | 当前 节点选择 |
| 🤖 AI接口 | 1 | opencode，url-test JP |
| 🐟 漏网之鱼 | 1 | MATCH → 节点选择 |

### 2.3 来源分段（模板顺序）

| 来源 | 索引 | 条数 | 目标 |
|---|---|---:|---|
| 00_custom（rules.yaml） | 0..200 | 201 | AI 191 / 节点选择 9 / AI接口 1 |
| LocalAreaNetwork | 201..237 | 37 | 全球直连 |
| BanAD | 238..825 | 588 | 广告拦截 |
| BanProgramAD | 826..1841 | 1,016 | 广告拦截 |
| GoogleFCM | 1842..1885 | 44 | 谷歌FCM |
| GoogleCN | 1886..1914 | 29 | 全球直连 |
| Netflix（ACL4SSR） | 1915..1954 | 40 | NETFLIX |
| Netflix（LM-Firefly） | 1955..2452 | 498 | NETFLIX |
| DisneyPlus | 2453..2472 | 20 | DisneyP |
| ai.list（ShellClash） | 2473..2493 | 21 | 人工智能 |
| Microsoft | 2494..2572 | 79 | 微软服务 |
| Apple | 2573..2601 | 29 | 苹果服务 |
| Telegram | 2602..2614 | 13 | 电报消息 |
| ProxyMedia | 2615..2985 | 371 | 国外媒体 |
| ProxyLite | 2986..3415 | 430 | 节点选择 |
| ChinaDomain | 3416..4050 | 635 | 全球直连 |
| ChinaIpV6 | 4051..5552 | 1,502 | 全球直连 |
| ChinaIp | 5553..13009 | 7,456 | 全球直连（含 MATCH） |

**关键结构结论**：模板的顺序是
`自定义 → LAN → 广告 → FCM/GoogleCN → 流媒体 → AI → 微软/苹果/电报 → 媒体代理 → 通用代理 → CN 直连 → IP → MATCH`。
问题就出在 **“媒体/通用代理”排在“CN 直连”之前**，以及 **ai.list 的少量宽泛规则排在微软/媒体之前**。

> **2026-10-22 追加**：`z.ai` / `bigmodel.cn` 显式直连（+2 条）。
> 原因：ZCode 账号/项目 Token API 的 `z.ai` 域名原先落到 `MATCH,🐟 漏网之鱼`
> （香港出口），project token 请求 15s 超时；路由器直连实测 0.34s。
> 审计表的 `00_custom` 201 是 2026-10-19 快照；当前生成物 323 条
> （含后续 geosite / 分类修正 / 2026-10-22 广告 carve-out），完整索引与计数待下次重跑审计。

---

## 3. 分类正确性

### 3.1 正确的部分

- **广告段**：1,604 条全部 REJECT；25 条关键词都是具体广告平台（admarvel、admaster、adwords、
  applovin、appsflyer 等），没有宽泛的 `ad` 关键词；130 个代表域名无一误伤。
- **Google Play/更新/FCM**：我们新增的 9 条覆盖位于 ai.list 之前，实测 Play/更新/FCM 全部走节点选择，
  不再被 `googleapis.com → 人工智能` 抢走。
- **AI 主端点**：192 条 geosite + AI接口；ChatGPT/Claude/Gemini/Copilot/opencode 等主域名分类正确。
- **CN 直连主体**：9,659 条 DIRECT，覆盖 LAN、ChinaDomain、ChinaIp、ChinaIpV6，方向正确。
- **服务专用段**：Netflix/Disney/Telegram/FCM 的列表本身没有明显错分（问题主要来自共享依赖和顺序）。

### 3.2 问题清单（按严重度）

#### P0：功能性或明显错分

| # | 现象 | 证据 | 影响 |
|---|---|---|---|
| P0-1 | **OneDrive 直连超时** | `onedrive.live.com` 直连 10s 超时（code 000）；规则命中 Microsoft → DIRECT | OneDrive/SharePoint 不可用 |
| P0-2 | **Epic 直连 403（复查：Cloudflare challenge，非路由问题）** | 直连和代理都返回 403 + `cf-mitigated: challenge`；带浏览器 UA 仍 403 | 与分流无关，保留 ChinaDomain DIRECT，不做代理覆盖 |
| P0-3 | **`.hk` 宽泛代理抢先** | ProxyLite `DOMAIN-SUFFIX,hk`（#3008）→ 节点选择；`tmall.hk`(#3500)、`jd.hk`(#3652) 的 CN 直连被遮蔽 | 港区 CN 站点被绕路 |
| P0-4 | **Steam 中国节点被代理** | ProxyLite `steampowered.com`（#3346）遮蔽 ChinaDomain 的 `cm.steampowered.com`(#3724) | Steam 中国下载变慢 |
| P0-5 | **Bing 搜索被拉进 AI 组** | ai.list `DOMAIN-SUFFIX,bing.com`（#2478）→ 人工智能；Microsoft `bing.com`(#2508)→DIRECT 被遮蔽；Bing 直连实测 302/0.31s | 所有 Bing 搜索绕 JP |
| P0-6 | **非 AI 的 googleapis 全走 AI** | ai.list `DOMAIN-SUFFIX,googleapis.com`（#2483）→ 人工智能；ProxyLite 的 `googleapis.com`(#3231)→节点选择被遮蔽 | 普通 Google API 绕 AI 组 |
| P0-7 | **`cn` 直连在代理之后** | ChinaDomain（#3416）排在 ProxyMedia/ProxyLite（#2615/#2986）之后 | 所有宽泛代理规则都能抢在 CN 直连之前 |

#### P1：语义错分 / 共享依赖

| # | 现象 | 证据 |
|---|---|---|
| P1-1 | ai.list 把共享 SaaS 拉进 AI 组 | `sentry.io`(#2484)、`intercom.io`(#2485)、`featuregates.org`(#2486)、`statsigapi.net`(#2487)、`cdn.auth0.com`(#2475)、`opendns.com`(#2477)、`opera-api.com`(#2490) |
| P1-2 | `adobedtm.com` 被钉到 DisneyP | Disney(#2454) 早于 ProxyLite(#3036)；Adobe DTM 是共享标签管理器 |
| P1-3 | `flashtalking.com` 被广告段 REJECT | 同时出现在 Disney(#2461) 与 ProxyMedia(#2740)，广告规则 #425 最终生效 |
| P1-4 | `akadns.net` 同时属于 Apple/Microsoft | Microsoft(#2500) 先匹配 → DIRECT；共享 Akamai DNS |
| P1-5 | `xbox.com` 没有规则 | 不在 Microsoft 列表，落 MATCH → 漏网之鱼 → 代理；直连实测 307 可用 |
| P1-6 | AI 覆盖缺口 | `replicate.com`、`together.ai` 落 MATCH → 漏网之鱼（可用，但不在 AI 组） |
| P1-7 | `ai.azure.com` 被 Microsoft 抢先 | ProxyMedia(#2632) 的规则被 Microsoft(#2503) 的 `azure.com` 遮蔽 → DIRECT |

#### P2：广告覆盖 / 策略选择

| # | 现象 |
|---|---|
| P2-1 | `analytics.google.com`、`connect.facebook.net` 未被 REJECT（前者走节点选择，后者走节点选择） |
| P2-2 | `2mdn.net`(#1887)、`clickserve.dartsearch.net`(#1898) 在 GoogleCN 里是 DIRECT，没有 REJECT |
| P2-3 | `Ⓜ️ 微软服务` 当前 = DIRECT；多数 MS 服务直连正常，但 OneDrive 不行（见 P0-1） |
| P2-4 | `🚀 手动切换` 当前停在德国；与规则无关，但容易误用 |
| P2-5 | ProxyLite 的 `telegram`(#3030) 关键词把未在 Telegram 列表里的 TG 域名送到节点选择，而不是电报消息；当前两个组出口相同，无功能差异 |

### 3.3 量化结果

- 域名规则 3,378 条（3,105 SUFFIX + 170 DOMAIN + 103 KEYWORD）。
- 自身最早匹配：2,918 条；同目标冗余：196 条；**实际改道：161 条**（严重 16 / 组级 145）。
- MATCH 之后规则：0 条。
- 130 个代表域名：**6 个异常**（analytics.google.com、connect.facebook.net、replicate.com、
  together.ai、xbox.com、epicgames.com）。
- 严重改道 16 条中：
  - 9 条是 FCM（`alt1-8-mtalk` + `mtalk`）：GoogleCN 的 DIRECT 被 FCM 规则覆盖，
    **这是有意且正确的**（FCM 必须代理）。
  - 2 条是 `d9.flashtalking.com`：广告段 REJECT 覆盖 Disney/ProxyMedia；
  - 2 条是 `app-measurement.com`、`2mdn.net`：GoogleCN DIRECT 覆盖 ProxyLite；
  - 2 条是 `tmall.hk`、`jd.hk`：ProxyLite `hk` 覆盖 ChinaDomain；
  - 1 条是 `cm.steampowered.com`：ProxyLite `steampowered.com` 覆盖 ChinaDomain。

### 3.4 一个重要区分：分类正确 ≠ 功能可达

`onedrive.live.com` 的规则目标是 `Ⓜ️ 微软服务`（分类正确），但该组当前选择 **DIRECT**，
而直连实测 10 秒超时。**规则审计必须同时看“目标组”和“组的实际出口/可达性”**，
否则会把“分类正确但功能不通”误判为通过。建议后续把关键服务的可达性探测加进自检脚本。

---

## 4. 重组方案

### 4.1 原则

1. **先具体、后宽泛**：具体服务规则必须在宽泛关键词/TLD 之前。
2. **先安全、后直连、后代理**：广告 REJECT 最前；CN 直连在宽泛代理之前。
3. **一个服务家族一个出口**：Google 功能、Google AI、FCM、Bing/Copilot、OneDrive 各自明确。
4. **共享 SaaS 不绑定单一服务组**：Sentry/Intercom/Auth0/Statsig 等不应因为某个 AI 服务用过就全量进 AI 组。
5. **不重写模板**：模板 13k 行继续由订阅生成，只在其前面/中间插入可控层。

### 4.2 目标顺序

```
1. LAN / local / 私有地址            → DIRECT
2. 广告 / 追踪                        → REJECT
3. 硬覆盖：AI API、Google Play/更新/FCM、Bing/Copilot、OneDrive、CN 例外
4. 服务专用：FCM / Netflix / Disney / Telegram / Microsoft / Apple
5. CN 直连中间层：RULE-SET,cn        → DIRECT
6. 宽泛代理：ProxyMedia / ProxyLite  → 代理
7. IP 规则（真实 IP 流量）
8. MATCH → 漏网之鱼 → 节点选择
```

### 4.3 Phase 1：分类修正层（低风险，建议先做）

在 `yamls/rules.yaml` **末尾**追加以下规则（仍在所有模板规则之前）。
顺序敏感，必须保持：广告 → AI 具体 → Bing/Google 宽泛 → 服务一致性 → CN 例外。

```yaml
# ===== 分类修正层（rules.yaml 末尾，模板规则之前）=====
# A. 广告优先（必须在宽泛 bing/googleapis 之前）
- DOMAIN-SUFFIX,bat.bing.com,🛑 广告拦截
- DOMAIN-SUFFIX,analytics.google.com,🛑 广告拦截
- DOMAIN-SUFFIX,2mdn.net,🛑 广告拦截
- DOMAIN-SUFFIX,clickserve.dartsearch.net,🛑 广告拦截
- DOMAIN-SUFFIX,connect.facebook.net,🛑 广告拦截   # 若影响 Facebook 登录 SDK 可删除

# B. AI 语义修正（具体必须先于宽泛 sentry.io）
- DOMAIN,o33249.ingest.sentry.io,🤖 人工智能
- DOMAIN-SUFFIX,disney.my.sentry.io,🎥 DisneyP
- DOMAIN-SUFFIX,sentry.io,🚀 节点选择
- DOMAIN-SUFFIX,sydney.bing.com,🤖 人工智能
- DOMAIN-SUFFIX,edgeservices.bing.com,🤖 人工智能
- DOMAIN-SUFFIX,replicate.com,🤖 人工智能
- DOMAIN-SUFFIX,together.ai,🤖 人工智能
- DOMAIN-SUFFIX,intercom.io,🚀 节点选择
- DOMAIN-SUFFIX,featuregates.org,🚀 节点选择
- DOMAIN-SUFFIX,statsigapi.net,🚀 节点选择
- DOMAIN-SUFFIX,cdn.auth0.com,🚀 节点选择
- DOMAIN-SUFFIX,opendns.com,🚀 节点选择
- DOMAIN-SUFFIX,opera-api.com,🚀 节点选择
- DOMAIN,youtubei.googleapis.com,🌍 国外媒体
- DOMAIN-SUFFIX,googleapis.com,🚀 节点选择   # 放在所有 AI 专用 googleapis 规则之后

# C. 服务一致性
- DOMAIN-SUFFIX,bing.com,Ⓜ️ 微软服务
- DOMAIN-SUFFIX,xbox.com,Ⓜ️ 微软服务
- DOMAIN-SUFFIX,onedrive.com,🚀 节点选择
- DOMAIN-SUFFIX,onedrive.live.com,🚀 节点选择
- DOMAIN-SUFFIX,storage.live.com,🚀 节点选择
- DOMAIN-SUFFIX,skydrive.wns.windows.com,🚀 节点选择
- DOMAIN-SUFFIX,sharepoint.com,🚀 节点选择
- DOMAIN-SUFFIX,sharepointonline.com,🚀 节点选择
- DOMAIN-SUFFIX,photos.live.com,🚀 节点选择
- DOMAIN-SUFFIX,ai.azure.com,🤖 人工智能
- DOMAIN-SUFFIX,openai.azure.com,🤖 人工智能
- DOMAIN-SUFFIX,cognitiveservices.azure.com,🤖 人工智能

# D. CN 直连与宽泛代理冲突
- DOMAIN-SUFFIX,tmall.hk,🎯 全球直连
- DOMAIN-SUFFIX,jd.hk,🎯 全球直连
- DOMAIN,cm.steampowered.com,🎯 全球直连   # 当前 NXDOMAIN，保留作未来兼容
```

**实施注意**：

- `ai-rules-update.sh` 目前会整文件重写 `rules.yaml`，必须把上面的修正块加进生成脚本
  （放在 Google 覆盖和 geosite 规则之后），并加一条校验，否则每周自动更新会冲掉。
- `googleapis.com` 的宽泛规则必须放在**所有 AI 专用 googleapis 规则之后**，
  否则会把 `generativelanguage.googleapis.com` 等抢走。
- `bing.com` 的宽泛规则必须放在 `sydney.bing.com`/`edgeservices.bing.com` 和 `bat.bing.com` 之后。
- 应用后跑 `rule_audit.py` 回归；预期 6 个异常降到 1–2 个（Epic 政策项）。

**Phase 1 实施结果（2026-10-19）**：

- 修正层已写入 `ai-rules-update.sh` 并 hotupdate；运行配置 13,047 条，`mihomo -t` 通过。
- `rule_audit.py` 回归：**139 个代表域名 0 异常**。
- 剩余 15 条 severe 均为有意覆盖：9 条 FCM（GoogleCN DIRECT 被 FCM 覆盖）、
  2 条 `d9.flashtalking.com`（广告 REJECT 覆盖 Disney）、`app-measurement.com`（直连）、
  `2mdn.net`（广告 REJECT）、2 条 Epic（代理覆盖 ChinaDomain）。
- 关键结果：Bing 直连、`sydney.bing.com` 走 AI、OneDrive/SharePoint 走代理、
  共享 Sentry/Intercom/Auth0 走节点选择、`disney.my.sentry.io` 保留 DisneyP、
  `tmall.hk`/`jd.hk` 直连；OneDrive 实测带浏览器 UA 返回 302（通）；
  Epic 保持直连（403 是 Cloudflare challenge，非路由问题）；`cm.steampowered.com` 当前 NXDOMAIN，规则保留作兼容。
### Phase 2 实施结果（2026-10-19）

- `rules-mid.sh` 已部署，`clash_modify.sh` 钩子生效；`RULE-SET,cn` 位于 #3158
  （电报 #3157 之后、ProxyMedia #3159 之前）；`CrashCore.raw -t` 通过。
- 最终 `rule_audit.py`：13,046 条规则，**139 个代表域名 0 异常**；
  剩余 13 条 severe 均为有意覆盖（9 FCM、2 flashtalking 广告、app-measurement 直连、2mdn 广告）。
- `cn` 模拟影响面 8 条（`joox.com`、`ip138.com`、`bloomberg.cn`、`gfx.ms`、`sfx.ms`、
  `googleapis.cn`、`gstatic.cn`、`oneclient.sfx.ms`），其中 `misrouted_cn` 5 条。
- 实况：`ip138.com` 命中 `DIRECT`；`joox.com` 仍走 `🌍 国外媒体`（运行中的
  `cn.mrs` 比文本列表滞后，属预期漂移）；`jd.hk` DIRECT；`www.google.com` 香港代理。
- `ai-api-check.sh` 第 8 节已加入并通过（脚本可执行、钩子在、位置正确）。
- 已知限制：`cm.steampowered.com` 已 NXDOMAIN；Epic 403 是 Cloudflare challenge，
  不是路由问题；`cn.mrs` 与文本 geosite 列表可能不同步。

### 4.4 Phase 2：CN 直连中间层（解决 P0-3/P0-4 和长尾）

**做法**：在服务组之后、ProxyMedia 之前插入一行：

```
 - RULE-SET,cn,🎯 全球直连
```

`cn` provider 已经存在（`rule-providers.cn`，`behavior: domain`，mrs），用于 DNS 的
`nameserver-policy: rule-set:cn`，不需要新增 provider。

**为什么放在这里**：广告段在它之前（中文广告域名仍会被 REJECT）；FCM/Netflix/Disney/
Microsoft/Apple/Telegram 在它之前（显式服务策略优先）；ProxyMedia/ProxyLite 在它之后
（宽泛代理不再抢 CN 域名）。

**实现方式**（不手改模板）：

1. 新增 `/etc/ShellCrash/rules-mid.sh`：读取生成的 config，在最后一条 `📲 电报消息`
   规则之后、第一条 `🌍 国外媒体` 规则之前插入 ` - RULE-SET,cn,🎯 全球直连`。
2. 在 `starts/clash_modify.sh` 的 `merger_yaml` 之后加钩子（和 `reorder-groups.sh` 同一位置）：
   `[ -x "$CRASHDIR"/rules-mid.sh ] && "$CRASHDIR"/rules-mid.sh "$TMPDIR"/config.yaml`
3. 用 `mihomo -t` 校验，再 `task.sh hotupdate`。
4. 在 `ai-api-check.sh` 加一条：钩子和 `RULE-SET,cn` 是否存在。
5. 用 `rule_audit.py` 回归，重点看 `.hk`/Steam/Epic 是否已修复，以及是否有新的 CN 域名被误直连。

**风险**：`geosite:cn` 的覆盖范围会随上游变化；如果某个本应代理的域名被 geosite:cn 收录，
会被直连。因此必须保留上面的显式代理覆盖（Epic、OneDrive 等），并在每次更新后跑回归。

### 4.5 Phase 3：provider 化（长期）

把 17 个内联列表替换为约 6 个 provider：

| provider | 内容 | 目标 |
|---|---|---|
| cn | geosite:cn（已有） | DIRECT |
| ads | geosite:category-ads-all | REJECT |
| ai | geosite:category-ai-chat-!cn（已有 192 条内联，可转 provider） | 人工智能 |
| google | geosite:google + 自定义 Google 服务覆盖 | 节点选择 |
| global | geosite:geolocation-!cn | 节点选择 |
| services | Netflix/Disney/Telegram/Microsoft/Apple 的本地 provider | 各自组 |

效果：规则从 13,010 行降到几百行；分类语义显式；订阅更新更快。
风险：`rule-providers` 与现有 `cn` provider 的合并可能冲突（历史上顶层重复键会让
mihomo 拒载），必须在一个独立配置上先做 `mihomo -t` 和回归，不建议一步到位。

---

## 5. 工具与验收

### 5.1 运行审计

```bash
# 1) 从路由器取运行配置和组状态
scp root@10.0.0.1:/tmp/ShellCrash/config.yaml ./config.yaml
curl -s 127.0.0.1:9999/proxies > proxies.json   # 需在路由器上执行后取回

# 2) 下载模板对应的 17 个上游列表（脚本已按 ShellClash.ini 自动下载）
# 3) 运行
python mihomo/rule_audit.py config.yaml proxies.json lists REPORT.md   # 工具在 OpenwrtOpsToolkit 仓
```

> 审计器的用法与 `AUDIT_*` 环境变量（对上你自己的策略组名）见 [TOOLS.md](TOOLS.md) §5。

### 5.2 验收指标

| 指标 | 当前 | 目标 |
|---|---|---|
| 130 域名分类异常 | 6 | ≤ 2（Epic 等政策项） |
| 严重改道 | 16（其中 9 条 FCM 为有意） | 0（FCM 白名单除外） |
| 广告误伤（测试集） | 0 | 0 |
| MATCH 后规则 | 0 | 0 |
| OneDrive 可达性 | 直连超时 | 代理 200 |
| Bing 搜索出口 | AI 组（JP） | 微软服务/DIRECT |
| `.hk` CN 站点 | 代理 | 直连（或显式例外） |

### 5.3 建议的落地顺序

1. **Phase 1**：写入修正层，跑审计；这是低风险、收益最大的部分。
2. 观察 1–2 天，确认 OneDrive/Epic/Bing/Steam 的行为。
3. **Phase 2**：加 `RULE-SET,cn` 中间层，回归；如出现误直连，用显式代理规则覆盖。
4. **Phase 3**：在独立配置上验证 provider 化，再替换。

---

## 6. 附：本次审计的原始报告

- 完整表格与机器可读结果：**未随公开仓发布**（含节点与订阅信息）
- 审计工具：`OpenwrtOpsToolkit` 仓的 `mihomo/rule_audit.py`
- 上游列表：`third-party/ACL4SSR/Clash/`

---

## 7. 2026-10-22 追加：Google 广告 carve-out 与 AI 列表共享 SaaS 清理

> 本节是 2026-10-19 审计后的增量结论。运行配置已从 13,010 条降到 4,154 条
> （`cnip` provider 接管 8,980 条 CN IP 规则），生成物 `00_custom` 323 条。

### 7.1 问题：宽泛 Google 规则把广告 REJECT 整段遮蔽

2026-10-19 的 Phase 1 把「Google 统一出口」放在自定义层最前，保证一次 Google 会话只有一个出口 IP。
代价是模板 BanAD 里的 Google 广告规则排在后面，永远轮不到：

| 域名 | 模板本意 | 实际命中（2026-10-22 实测） | 实际出口 |
|---|---|---|---|
| `pagead2.googlesyndication.com` | 🛑 广告拦截 | `DomainKeyword,google` | 🤖 干净出口，单次 63 KB |
| `www.google-analytics.com` | 🛑 广告拦截 | `DomainKeyword,google` | 🤖 干净出口，单次 59 KB |
| `adservice.google.com` | 🛑 广告拦截 | `DomainSuffix,google.com` | 🤖 干净出口 |
| `tpc.googlesyndication.com` | 🛑 广告拦截 | `DomainKeyword,google` | 🤖 干净出口 |
| `googletagmanager.com` | 🎯 全球直连 | `DomainKeyword,google` | 🤖 干净出口 |
| `csi.gstatic.com` | 🛑 广告拦截 | `DomainSuffix,gstatic.com` | 🤖 干净出口 |
| `collector.githubapp.com` | 🛑 广告拦截 | `DomainSuffix,githubapp.com` | 🤖 干净出口 |

`doubleclick.net` 是更隐蔽的一类：父域规则 `DOMAIN-SUFFIX,doubleclick.net,🛑 广告拦截` 本身不含
`google`，按规则值做遮蔽审计不会报；但真实广告主机 `googleads.g.doubleclick.net` 含 `google`，
仍被关键词抢走。所以 carve-out 必须按父域写 `doubleclick.net`，不能只列具体主机。

被遮蔽的 REJECT 规则共 15 条（14 条 Google 广告/追踪 + `collector.githubapp.com`），
另有 `googletagmanager.com` / `googletagservices.com` 两条 DIRECT 被改成代理。

### 7.2 修复

在 `config/generators/ai-rules-update.sh` 的 A 段、Google 块之前加入：

- `doubleclick.net`、`googlesyndication.com`、`googleadservices.com`、`google-analytics.com`、
  `googleadsserving.cn`、`ads.google.com`、`adservice.google.com`、`pagead.google.com`、
  `pagead.l.google.com`、`pagead-tpc.l.google.com`、`mobileads.google.com`、`afd.l.google.com`、
  `badad.googleplex.com`、`csi.gstatic.com`、`collector.githubapp.com`、`app-measurement.com` → `🛑 广告拦截`
- `googletagmanager.com` / `googletagservices.com` → `🚀 节点选择`
- `googlecommerce.com` 保留代理（Google Shopping/Merchant，不一定是广告）

### 7.3 共享 SaaS 从 AI 组移出

上游 `category-ai-chat-!cn` 里混入了非 AI 专用域，和 2026-10-19 处理过的
sentry/intercom/auth0/statsig 是同一类问题：

| 域 | 实际用途 | 新目标 |
|---|---|---|
| `envato.com` / `envato-static.com` / `envatousercontent.com` / `themeforest.net` | 素材市场 | 🚀 节点选择 |
| `liveperson.net` / `lpsnmedia.net` | 客服聊天组件 | 🚀 节点选择 |
| `browser-intake-datadoghq.com` | Datadog RUM | 🚀 节点选择 |

### 7.4 回归结果（2026-10-22）

- 运行配置 4,154 条；`RULE-SET,cn` 在 #3227，仍在 ProxyMedia 之前；`RULE-SET,cnip` 在 #877
- `pagead2.googlesyndication.com` / `www.google-analytics.com` / `googleads.g.doubleclick.net` /
  `collector.githubapp.com` / `csi.gstatic.com` / `app-measurement.com` 经 `127.0.0.1:7890` 全部
  `exit=35`（REJECT）；修复前是 200 且真实下载 59–63 KB
- `www.google.com` / `github.com` / `dl.google.com` / `chatgpt.com` 仍 `exit=0`
- `googletagmanager.com` / `googletagservices.com` / `liveperson.net` 的 chains 为
  `🇭🇰 香港WAP → ♻️ 自动选择 → 🚀 节点选择`
- `ai-api-check.sh` 全 18 段通过；第 18 段断言 carve-out 在
  `DOMAIN-SUFFIX,google.com` / `DOMAIN-KEYWORD,google` 之前

> 未改：`gstatic.cn` / `googleapis.cn` 仍走干净出口；`baidustatic.com` / `xdrig.com` 仍是
> BanAD REJECT（可能是误伤，未验证到实际使用场景，暂不动）。

### 7.5 可删减空间与「不部署」结论（2026-10-22）

对 4,154 条运行配置做同目标遮蔽扫描（`DOMAIN` / `DOMAIN-SUFFIX` / `DOMAIN-KEYWORD`，
先匹配先赢）：

| 类别 | 数量 | 处理 |
|---|---:|---|
| 同目标冗余（前面已有同目标规则命中） | 222 | 离线工具可删 207（15 条保护规则除外） |
| 完全重复（type + domain + target 相同） | 90 | 含在上面 222 条里（73 条）；另 17 条被不同目标先命中，保留作意图 |
| `find-process-mode: off` 下永不命中的 `PROCESS-NAME` | 4 | 离线工具可删 |
| 不同目标遮蔽（模板意图/审计痕迹） | 222 | **保留**；删了不改行为，但会丢审计依据 |
| CN 直连「文本列表看似冗余」 | 528（505 在 `RULE-SET,cn` 之后） | **保留**；运行态 `cn.mrs` 可能滞后，`joox.com` 先例 |
| `cnip` 之后的 DIRECT IP-CIDR | 10 | **保留**；Apple/Akamai 段，不是 CN IP |

**副本测试**：4,154 → 3,943 条（-211，-5.1%）；同目标冗余归零，不同目标遮蔽保持 222 条。
**但未部署到路由器** —— 2026-10-22 在路由器上跑 `rules-dedup.sh --check`（O(N²) 两两匹配）
把 CPU/内存拖垮，导致整网断流。脚本已归档到
[`config/archive/rules-dedup.sh`](../config/archive/rules-dedup.sh)，只允许在 PC 上
对 scp 下来的 `config.yaml` 副本跑。

**当前路由器状态（2026-10-22 维护窗口后）**：`rules-cnip` 已恢复，运行配置 4,154 条；
单 CrashCore、可用内存 63 MB；`RULE-SET,cnip` / `RULE-SET,cn` 各 1 条；自检 18 段通过，
广告域仍 REJECT。`rules-dedup` 仍未部署 —— 211 条规则的收益不值得在路由器上再冒一次断网风险。

> 为什么不全删 444 条死规则：其中 222 条是「模板声明目标 vs 自定义覆盖」的
> 审计证据（例如 `googlecommerce.com,REJECT` 被 `google` 关键词送去代理），
> 删掉行为不变，但下次审计会看不出模板原本想怎么分。

### 7.6 B站属地拆分（2026-10-22）

**目标**：评论 / 主页的 IP 属地显示国外，视频仍走国内直连。

**机制**：B站属地由「发请求那一刻的源 IP」判定，没有独立的「IP 检测」接口；
路由器层只能按域名拆，发评论和刷首页走同一批 API 域名。所以要让属地变国外，
必须把 API 域名整体指向国外组，CDN 保持直连。

**网络层（2026-10-22 追加）**：只加域名规则不够 —— 手机端 App 会用 HTTPDNS 拿到
真实 CN IP（`157.148.134.0/24`、`27.37.206.0/24`）或走 QUIC（UDP 443），
两者都会被 `cn_ip` 的直连豁免放行，根本到不了 mihomo。因此：

- `config/starts/fw_nftables.sh`：在 `cn_ip` return **之前**把 B站 API 的
  IPv4 段 TCP 443 重定向到 7892（`BILI_IP_MARKER`）；
- `firewall/quicguard-sync.sh` / `firewall/tables/quicguard.nft`：在 CN QUIC 豁免
  **之前** reject 这些网段的 UDP 443/8443，强制 App 回落 TCP。

**IPv6 不做**（2026-10-22 撤回 `BILI_V6_MARKER`）：`api.bilibili.com` 没有公开
AAAA；原先使用的 `2408:8756::/31` 是整个联通 IPv6 大段，腾讯（QQ/微信）的 CDN
大量落在里面，reject 其 QUIC、并把 443 重定向进 mihomo，会直接打断 QQ/微信视频播放。

**DNS / IPv6 层（2026-10-22 追加）**：直连不等于快，CDN 边缘会被 DNS 选错：

- `dns.ipv6: true` 时 Akamai 的 AAAA（`2600:140e:3:e::…`）实测只有 22 KB/s，
  IPv4 有 1.4–2.1 MB/s；设备侧把 `ipv6_dns=OFF`（备份 `ShellCrash.cfg.bak-bili-ipv6-*`），
  mihomo 只返回 A。
- `respect-rules` 只对**字面 `DIRECT`** 走 `direct-nameserver`；用 `🎯 全球直连` 组会落到默认
  `nameserver`（Cloudflare/Google DoH），解析到 `23.193.186.11`，实测 28 KB/s。
- `direct-nameserver`（AliDNS/DoH.pub）返回 `23.49.104.x`，10MB 实测仅 12 KB/s；
  上游光猫 DNS（`192.168.1.1`）返回 `2.16.62.x` / `23.57.75.x`，实测 1.4–2.1 MB/s。
- `config/starts/clash_modify.sh` 因此给 `+.bilivideo.com` / `+.bilivideo.cn` / `+.hdslb.com` /
  `+.biliimg.com` / `+.acgvideo.com` / `upos-hz-mirrorakam.akamaized.net` 单独设
  `nameserver-policy` → 上游 DNS（从 `/tmp/resolv.conf.d/resolv.conf.auto` 读取）。

**MCDN / PCDN 层（2026-10-22 追加）**：播放器还会用 `bvc.bilivideo.com`（直连、按 CN IP）
拿 MCDN 列表，媒体分段优先走 `xy<ip>xy.mcdn.bilivideo.cn:8082`（P2P 节点）和
`*.edge.mountaintoys.cn:4483`（MCDN 边缘），而不是 `playurl` 的 `upos-*`：

- 实测 9 个 PCDN 节点：7 个 2.5–5.4 MB/s，**2 个只有 6–11 KB/s**；踩中慢节点时分段卡住，
  等超时才切下一个，表现为「看一会儿转圈一下」。
- 8082/4483 **不在** 7892 重定向端口集合（`22/80/443/5228/8080/8443/19302`）里，
  流量不进 mihomo，`/connections` 看不到，域名规则也拦不到，只能在 DNS 层处理。
- 解法：`clash_modify.sh` 生成的 `hosts:` 把 `'*.mcdn.bilivideo.cn'` / `'*.edge.mountaintoys.cn'`
  指到 `127.0.0.1`；播放器回落 `upos-*`（实测 6.5–20 MB/s）。API 仍走香港，属地不变。
- **验证陷阱**：mihomo 的 `/dns/query` API 不读 `hosts`，仍返回真实 IP；要在 LAN 客户端用
  `nslookup <peerhost> 10.0.0.1` 验证，返回 `127.0.0.1` 才算生效。

| 类别 | 域名 | 目标 |
|---|---|---|
| 属地 API | `api.bilibili.com` / `biliapi.com` / `biliapi.net` | 🎬 B站解锁 |
| 非属地 API | `app.bilibili.com` / `cm.bilibili.com` / `api.vc.bilibili.com` / `api.live.bilibili.com` | DIRECT |
| 页面/登录/静态 | `bilibili.com` / `bilibili.co` / `b23.tv` / `acg.tv` | 🎯 全球直连 |
| 视频 CDN | `bilivideo.com` / `bilivideo.cn` / `hdslb.com` / `biliimg.com` / `acgvideo.com` / `upos-hz-mirrorakam.akamaized.net` | DIRECT |
| MCDN / PCDN | `*.mcdn.bilivideo.cn` / `*.edge.mountaintoys.cn` | `hosts:` → `127.0.0.1`（强制回落常规 CDN） |

**2026-10-22 二次拆分：只有三族真的需要出国**

原先把 `app.` / `cm.` / `api.live.` / `api.vc.` 也送进 🎬 B站解锁，但它们都不参与属地：
`app` 是 App 启动配置/版本/开屏，`cm` 是广告投放，`api.vc` 是动态/关注/私信（显示的是**他人**属地），
`api.live` 是直播房间 API（弹幕与开播信息不含自身属地）。改直连后实测：

- 经香港：`api.bilibili.com` TLS 0.42–1.29s、TTFB 0.57–1.57s；
- 直连：同类请求 TTFB 0.06–0.09s（冷启动 0.11s）—— 每个新连接省一次隧道往返；
- 验证：`/connections` 里四个域链路为 `["DIRECT"]`，`api.bilibili.com` 为
  `["🎬 B站解锁","🇭🇰 香港WAP-优化"]`，`x/web-interface/zone` 仍返回 `country=香港`。

**视频 CDN 拆不动（同一轮实测，别再试）**

`playurl` 与评论/zone 同在 `api.bilibili.com`，而 B站按**请求源 IP** 选 CDN：
经香港请求返回 `upos-sz-mirrorcosov.bilivideo.com` + `upos-hz-mirrorakam.akamaized.net`（海外边缘，
实测 0.69–1.23 MB/s）；路由器 WAN 出口请求同一接口返回 `upos-sz-mirrorbd.bilivideo.com`（国内 CDN）。
因此只要 API 出国，媒体就注定落在海外边缘；想拿国内 CDN 只能让 `api.bilibili.com` 直连 ——
那等于放弃属地。按域名/路径都拆不开：规则只能匹配 host，playurl 与评论同 host；
`dash` 的 `backupUrl` 也只有海外域，DNS 层屏蔽海外 CDN 只会把播放打断。

**节点选择（2026-10-22 实测）**：

- HY2 池到大陆方向不通：香港/韩国节点能连 `gstatic.com`，但 `baidu.com` / `zhihu.com` /
  `www/api.bilibili.com` 全部 TLS EOF 或超时；日本/新加坡节点本身超时。
- vmess 池可用：`香港WAP-优化` / `台湾-优化3` / `日本-优化` / `新加坡-优化3`。
  B站 `x/web-interface/zone` 实测分别返回 香港 / 台湾 / 日本 / 新加坡。
- 默认选 `香港WAP-优化`（延迟最低，且能解锁港澳台番剧）。

**验证**：

- `curl -x http://127.0.0.1:7890 https://api.bilibili.com/x/web-interface/zone`
  → `country=香港`，`addr=45.149.92.7`；
- `www.bilibili.com` 直连 200（0.24s）；
- playurl 返回的 CDN（`upos-hz-mirrorakam.akamaized.net` / `upos-sz-mirrorcosov.bilivideo.com`）
  Range 请求 206，`/connections` 链路 `["DIRECT","🎯 全球直连"]`，rule `DomainSuffix,bilivideo.com`。

**注意**：这是「API 出国、CDN 直连」，不是「所有流量走国内」；抖音对境外 IP
有内容与风控限制，小红书相对可用，但同一套拆法无法让「全部流量国内 + 属地国外」成立。

---

## 8. 2026-10-23 规则吸收与公共池利用

### 8.1 调研的上游项目

| 项目 | 星 | 重点 | 本轮结论 |
|---|---:|---|---|
| `Loyalsoldier/clash-rules` | 28.9k | direct / proxy / reject 分类清单 | 全量 11 万 direct、19.9 万 reject 与模板重叠且吃内存，**不整包引入**；只吸收 3 条直连与 5 条广告变体 |
| `VPSDance/ai-proxy-rules` | 644 | 按 provider 拆分的 AI 规则，日更 | 吸收 40 条 AI 自有域；共享 SaaS/CDN 明确不收 |
| `Aethersailor/Custom_OpenClash_Rules` | 6.6k | 直连 / 代理 / Steam / 游戏下载 CDN | 吸收 Epic / Steam / 暴雪 / Riot / Bethesda / Ubisoft / Xbox / GOG 下载域 |
| `MetaCubeX/meta-rules-dat` | 5.4k | geosite category 规则集 | 用 `category-game-platforms-download` 交叉核对；本仓现用的 `category-ai-chat-!cn` **不换** |
| `blackmatrix7/ios_rule_script` | 28.4k | 一服务一文件 | 只吸收 Disney 自有 CDN 与 Telegram/Twitch 辅助域；不引入 600+ 服务包 |
| `peasoft/NoMoreWalls` | 3.5k | 公开节点 | 新增为公共节点源 |
| `Au1rxx/free-vpn-subscriptions` | 1.0k | 公开节点 | 新增为公共节点源 |
| `zhuhaiuk/free-nodes` | 366 | 公开节点 | 新增为公共节点源 |

### 8.2 吸收的规则

统一写进 `config/generators/ai-rules-update.sh`，再由生成器输出
`config/generated/rules.yaml`（当前 491 条 / 626 行），**不直接手改生成物**。

| 类别 | 代表规则 | 目标 |
|---|---|---|
| AI 自有域 | `ai.com`、`modelcontextprotocol.io`、`together.xyz`、`deepinfra.com`、`fireworks.ai`、`novita.ai`、`bfl.ai`、`stability.ai`、`runway.com`、`suno.com`、`udio.com`、`character.ai`、`you.com` 及生成/编码类 | 🤖 人工智能 |
| 大流量 | Epic `download2/3/4`、`fastly-download`、`cloudflare.epicgamescdn`、`egdownload.fastly-edge` | 📺 大流量 |
| Steam | CM `steamserver.net`、目录 `api.steampowered.com`、国内 CDN `eccdnx.com` / `clngaa.com` / `pphimalayanrt.com`、`steamcontent.com` → **DIRECT**（2026-10-27，CM 直连才拿得到国内 CDN）；`steamstatic.com`、`steamcdn-a.akamaihd.net`、`steampipe*.akamaized.net` → 🚀 节点选择 | — |
| 游戏补丁 | `cdn.blizzard.com`、`blzddistkr1`、`prod.cloudflare.cdn.ea.com`、`dyn.riotcdn.net`、`gamedownloads-rockstargames-com.akamaized.net`、`cdp.bethesda.net`、`uplaypc-s-ubisoft*.cdn.ubi.com`、`assets1/2.xboxlive.com`、`gog-cdn.akamaized.net` | 📺 大流量 |
| 媒体 CDN | `i/v/preview.redd.it`、`i.imgur.com`、`i.pximg.net`、`vimeocdn.com`、`dmcdn.net`、`ttvnw.net`、`static-cdn.jtvnw.net`、`sourceforge.net`、`replicate.delivery`、`image.civitai.com` | 📺 大流量 |
| Civitai | 主站 `civitai.com` → 🚀 节点选择；图片 CDN → 📺 大流量（`image.*` 必须排在主站之前） | — |
| 高带宽直连 | `hf-mirror.com`（Range 4MB 实测 2.42 vs 代理 0.65 MB/s）、`kuaishouzt.com`、`images-cn.ssl-images-amazon.com` | 🎯 全球直连 |
| 广告变体 | `2mdn-cn.net`、`doubleclick-cn.net`、`dartsearch-cn.net`、`admob-cn.com`、`app-measurement-cn.com` | 🛑 广告拦截 |
| 一致性 | `ghcr.io` → 🔗 GitHub 出口；`graph.org` / `tg.dev` → 🚀 节点选择；`live-video.net` → 🌍 国外媒体；`hotstar-cdn.net` / `dlp-media.com` → 🎥 DisneyP | — |
| 性能 | Google 兜底 `IP-CIDR 74.125.0.0/16` / `173.194.0.0/16` 补 `no-resolve`，避免为匹配触发真实 DNS | — |

### 8.3 实测否掉的建议

- `cn.download.nvidia.com` **不要直连**：直连 403（跳到 `.cn` 后仍 403），代理 3.2 MB/s。
- `gstatic-cn.com` 两边都 000；`recaptcha-cn.net` 直连 1.6s vs 代理 0.27s —— 不加直连。
- 不整包引入 Loyalsoldier 的 `direct.txt` / `reject.txt`：与 `RULE-SET,cn`、
  本仓广告表高度重叠，且 11 万/19.9 万条会显著增加内存与加载时间。
- 不把 auth0 / sentry / statsig / aws / azure 共享域塞进 AI 组：同一登录会话出口会分裂。
- `i.pximg.net` 必须显式写；只写 `pximg.net` 时 `ip.pximg.net` 会被更早的
  `DOMAIN-SUFFIX,pximg.net,🚀 节点选择` 截走（实测首匹配已确认）。

### 8.4 伪节点与主备组事故（2026-10-23）

机场在订阅里塞了一个名字叫 **`过滤掉14条线路`** 的节点，它与 `🇯🇵 日本-优化`
**同 server / port / uuid**（`p6-olduser.linuxlh.xin:16617`），但名字带「过滤掉」。
`♻️ 自动选择` 是模板组，没有排除它，url-test 因它延迟低而选中；该节点到
`gstatic.com` 的健康检查在 07:03–07:23 之间多次返回 0，导致
`🛟 主备自动` 把整个 `♻️ 自动选择` 判为不健康，**所有通用流量回落到 `🆓 公共备用`**。
实测 15:11 时 `🛟 主备自动 now = 🆓 公共备用`。

修复：`config/hooks/reorder-groups.sh` 在生成阶段从 `proxies:` 定义和**所有**
`proxy-groups` 成员列表中剔除名字匹配 `剩余流量|套餐|到期|过滤掉|官网` 的伪节点。
配置副本验证：删除 3 行，YAML 可正常解析；重启后运行配置 0 处伪节点，
`♻️ 自动选择` 首位回到真实 `🇯🇵 日本-优化`，`🛟 主备自动 now = ♻️ 自动选择`。

### 8.5 公共节点筛选与 `bulk-guard` 二次校验

- 数据源从 3 个扩到 6 个：`NoMoreWalls`、`Au1rxx`、`zhuhaiuk` 新增；
  本轮 9804 原始 → 9479 合格 → 1271 多样性池；实测 259 条，13 存活，最终保留 10 条
  （延迟 211–584ms）。
- 逐节点 OVH 2MB 实测：`公共-08` 889 KB/s（最快）、`05` 582、`10` 580、`07` 488、
  `09` 418、`04` 386、`06` 180、`01` 85 KB/s；`02/03` TLS EOF / HTTP 503。
- 公共池钉到 `公共-08` 后，`proof.ovh.net` 4MB 实测 **1.9–2.2 MB/s**（修复前 17–34 KB/s）。
- `OpenwrtOpsToolkit/openwrt/bulk-guard.sh` 修复：新增 `node_bulk_alive()`，
  钉点、候选、当前节点都用 `PROBE_URL`（`proof.ovh.net`）做二次校验；
  原来的 `node_alive()` 只测 `gstatic.com/generate_204`，会把「能出网但不能跑大文件」
  的节点钉进 `📺 大流量`。
- 当前公共池 10 条中 8 条存活；`📺 大流量` 仍默认 `🆓 公共备用`，守卫按阈值
  切回机场。

### 8.6 𝕏 媒体 fallback

白天实测 HY2 并发优势仍在（10 并发 0.35s vs VMess 1.9–5.9s），但 2026-10-23 晚
HY2 池对 `pbs.twimg.com/robots.txt` **4/4 全部超时**，而 VMess 节点 **5/5 200**
（日本 79ms / 香港 152ms / 新加坡 107ms）。因此把 `𝕏 媒体` 拆成：

- `𝕏 媒体-HY2`：url-test，只收 HY2；
- `𝕏 媒体-备用`：url-test，收非 HY2、非公共节点；
- `𝕏 媒体`：fallback，HY2 优先，整池劣化时自动落到 VMess。

实测 `pbs.twimg.com` 恢复 200 / 0.26–0.28s；HY2 恢复后 fallback 会自动切回。
策略组总数 28 → 30。

### 8.7 验收

- 生成器输出 **486 条 / 610 行**；运行配置 **4317 条规则 / 30 个策略组**。
- `ai-api-check.sh` **18 段全部通过**（`CHECK_RC=0`）；新增伪节点、AI/大流量规则、
  Google `no-resolve` 检查。
- 关键站点：GitHub 200/0.78s、B站 200/0.11s、百度 200/0.10s、`pbs.twimg.com` 200/0.27s；
  `hf-mirror.com` 直连 1.06 MB/s；公共池 4MB 1.76 MB/s。
- Gemini / YouTube 本轮偏慢（12–18s / 13–20s），原因是 `🤖 干净出口` 当前在
  `🇹🇼 台湾-优化3`，`support.google.com` 的 `cc='TW'` 合法但吞吐差；
  这是出口节点劣化，不是规则回归，`guardian.sh` 会继续轮换。
- 内存：MemAvailable ≈ 28 MB，`/tmp` 69%；dmesg 里的 OOM 记录是更早的一次，
  本轮无新 OOM。

### 8.8 回退

| 改动 | 回退 |
|---|---|
| 生成器 / 规则 | 恢复路由器 `/etc/ShellCrash/ai-rules-update.sh.bak-20261023-153637` 与 `yamls/rules.yaml.bak-20261023-153637`，重启 |
| 伪节点过滤 | 恢复 `reorder-groups.sh.bak-20261023-153637` |
| X 媒体 fallback | 恢复 `proxy-groups.yaml.bak-20261023-*`，重启 |
| `bulk-guard` | 恢复 `bulk-guard.sh.bak-20261023-*` |
| 公共节点 | 恢复 `proxies.yaml.bak-public-screen-20261023-154500`，重启 |
