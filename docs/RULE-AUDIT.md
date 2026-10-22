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
两者都会被 `cn_ip`/`cn_ip6` 的直连豁免放行，根本到不了 mihomo。因此：

- `config/starts/fw_nftables.sh`：在 `cn_ip`/`cn_ip6` return **之前**把 B站 API 的
  IPv4/IPv6 段 TCP 443 重定向到 7892（`BILI_IP_MARKER` / `BILI_V6_MARKER`）；
- `firewall/quicguard-sync.sh` / `firewall/tables/quicguard.nft`：在 CN QUIC 豁免
  **之前** reject 这些网段的 UDP 443/8443，强制 App 回落 TCP。

| 类别 | 域名 | 目标 |
|---|---|---|
| API | `api.bilibili.com` / `app.bilibili.com` / `cm.bilibili.com` / `api.live.bilibili.com` / `api.vc.bilibili.com` / `biliapi.com` / `biliapi.net` | 🎬 B站解锁 |
| 页面/登录/静态 | `bilibili.com` / `bilibili.co` / `b23.tv` / `acg.tv` | 🎯 全球直连 |
| 视频 CDN | `bilivideo.com` / `bilivideo.cn` / `hdslb.com` / `biliimg.com` / `acgvideo.com` / `upos-hz-mirrorakam.akamaized.net` | 🎯 全球直连 |

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
