# 排错手册

> **一句话**：按「现象 → 排查步骤 → 原因 / 解法」组织的排查流程 ——
> 标题即检索词，搜到症状直接点进来；**根因与根治在 [PITFALLS.md](PITFALLS.md)，本篇只给步骤与判据。**

**通用前提**（先记住这三条，能省一半时间）：

1. **路由器自己的 `curl` 不走透明代理** —— 测 API 必须加 `-x http://127.0.0.1:7890`。
2. **路由器本机流量走 OUTPUT，不走 PREROUTING** —— 验证 LAN 行为必须**从客户端发起**。
3. **配置若被 mihomo 拒载，ShellCrash 会静默回退基础配置** —— 先看自定义组还在不在，
   再谈规则。

**拿 secret**（后面每条都要用）：

```bash
ssh root@10.0.0.1 'grep -m1 "^secret=" /etc/ShellCrash/configs/ShellCrash.cfg | cut -d= -f2- | tr -d "\x27\x22"'
```

**诊断脚本在哪**（下面命令里的 `mihomo/` `cdn/` 路径都相对于 **`OpenwrtOpsToolkit` 仓**根目录 ——
通用工具已从本仓迁出，本仓只留配置、规则与文档）：

```bash
git clone <OpenwrtOpsToolkit 的地址> && cd OpenwrtOpsToolkit
export MIHOMO_SECRET="$(ssh root@10.0.0.1 'grep -m1 "^secret=" /etc/ShellCrash/configs/ShellCrash.cfg | cut -d= -f2- | tr -d "\x27\x22"')"
export MIHOMO_API='http://10.0.0.1:9999'
```

---

<a id="ts-reject"></a>

## 1. mihomo 拒载配置

**现象**：自定义策略组、AI 分流、CN 中间层**一起消失**；
或 `/tmp/ShellCrash/CrashCore: not found`；
或日志里一句「自定义配置文件校验失败」就没了下文。

**排查步骤**：

```bash
# ① 配置还在不在（拒载回退的判据）
ssh root@10.0.0.1 'curl -s -H "Authorization: Bearer <secret>" http://127.0.0.1:9999/proxies' \
  | grep -o '"🤖 AI接口"\|"🤖 干净出口"\|"🚀 节点选择"'

# ② 直接校验当前配置，看 mihomo 到底报什么
ssh root@10.0.0.1 '/tmp/ShellCrash/CrashCore -t -f /tmp/ShellCrash/config.yaml'

# ③ 找顶层重复 key（最常见的原因）
ssh root@10.0.0.1 "grep -nE '^(rule-providers|proxy-groups|proxies|rules|dns|sniffer):' /tmp/ShellCrash/config.yaml"

# ④ 看是不是生成物写坏了（尾逗号 = 策略名为空）
ssh root@10.0.0.1 "grep -nE ',\]' /tmp/ShellCrash/config.yaml | head"

# ⑤ 巡检脚本（17 段，含自动修复）
ssh root@10.0.0.1 'sh /etc/ShellCrash/ai-api-check.sh'
```

**原因 / 解法**：

| 校验输出 | 原因 | 解法 |
|---|---|---|
| `mapping key "type" already defined` | 同名 `proxy-groups` 重复 | 确认 `reorder-groups.sh` 钩子在（`ai-api-check.sh` 第 5 段）；**不要把 `rule-providers` 写进用户 yaml** |
| `rules[N] [...] format invalid`（尾逗号） | 规则策略名为空 | 生成器（`ai-rules-update.sh`）修；巡检见第 12 段 |
| 校验通过但组仍然没有 | 不是拒载，是**组的当前选择**问题 | 看 `profile.store-selected` 是否为 true；见 [PITFALLS.md](PITFALLS.md) §16 |

**根治**：见 [PITFALLS.md](PITFALLS.md) §1（顶层 key 重复）与
[ARCHITECTURE.md](ARCHITECTURE.md) §5（降级与失败模式）。

---

<a id="ts-rule-noeffect"></a>

## 2. 分流规则不生效

**现象**：规则表里写着某域名走 A 组，实际流量走 B 组；
或者改完规则完全没变化。

**排查步骤**：

```bash
# ① 先确认配置真的重新加载了（改规则后要重启，见 PITFALLS §4）
ssh root@10.0.0.1 '/etc/ShellCrash/start.sh start'

# ② 看运行配置里规则的实际位置（不是模板位置）
ssh root@10.0.0.1 "grep -n 'RULE-SET,cn\|电报消息\|国外媒体' /tmp/ShellCrash/config.yaml | head -20"

# ③ 离线算「每条规则真实生效目标」—— 直接列出声明 ≠ 实际的规则
python mihomo/rule_audit.py config.yaml proxies.json third-party/ACL4SSR/Clash REPORT.md
```

**原因 / 解法**：

- **先匹配先赢**：宽泛规则（`.hk`、`DOMAIN-KEYWORD`）排在具体规则前面 → 具体规则永远轮不到。
  修法：具体服务规则必须在宽泛关键词/TLD 之前；
  CN 直连中间层（`rules-mid.sh` 插的 `RULE-SET,cn`）解决宽泛代理与 CN 直连的顺序冲突。
- **规则没进运行配置**：规则写在了 `yamls/rules.yaml` 但没重跑生成器 / 没重启。
- **配置没被加载**：先按 §1 排除拒载回退。

**根治**：见 [PITFALLS.md](PITFALLS.md) §15、[RULE-AUDIT.md](RULE-AUDIT.md)。

---

<a id="ts-domain-not-proxied"></a>

## 3. 某个域名没走代理

**现象**：某个域名（常见：Gemini、Play、某个 API）直连、或超时、或走的是另一个出口。

**排查步骤**：

```bash
# ① 抓实时日志看它命中了哪条规则（脚本会临时把 log-level 调 debug，结束会恢复）
python mihomo/mihomo_log.py 20 gemini.google.com

# ② 看这个域名当前有没有连接、走的哪条链
python mihomo/mihomo_api.py conns

# ③ 解析在哪个通道（是不是被污染 / 不是 fake-ip）
python mihomo/mihomo_api.py dns gemini.google.com
```

**判据与解法**：

| 观察到 | 原因 | 解法 |
|---|---|---|
| 日志里没有这个域名的连接 | 流量**根本没进 mihomo** | 多半是 QUIC（UDP）直出 → 全局拒 UDP 443/8443（`firewall/tables/quicguard.nft`）；见 [PITFALLS.md](PITFALLS.md) §7 |
| 命中 `IPCIDR 203.208.32.0/19` | 缺 `no-resolve`，按域名触发了真实解析 | 相关 IP-CIDR 加 `,no-resolve`；见 §8 |
| 命中 `🎯 全球直连` 但本该代理 | 规则顺序 / CN 中间层位置 | 见 §2 |
| 链路正常但出口 IP 是国内的 | 节点被 Google 判为 CN | 见 [PITFALLS.md](PITFALLS.md) §9 |
| 客户端拿到的是假 IP 但没被排除 | fake-ip 过滤清单语法错（`*.X` vs `+.X`） | 见 [PITFALLS.md](PITFALLS.md) §3 |
| 页面壳能开但推荐区不出现 | Chrome LNA 拦了 fake-IP 子资源 | fake_ip_filter 补 `+.gstatic.com` / `+.googleapis.com`；见 §14 |

---

<a id="ts-all-red"></a>

## 4. 策略组里节点全变红

**现象**：面板里某个组所有节点延迟测试失败（全是红的），
但别的组正常；或者切换到该组后全站超时。

**排查步骤**：

```bash
# ① 组类型与当前选择
python mihomo/mihomo_api.py proxies

# ② 该组候选是否还在（订阅更新后节点可能被删/改名）
ssh root@10.0.0.1 'curl -s -H "Authorization: Bearer <secret>" "http://127.0.0.1:9999/proxies/<组名>"'

# ③ 单节点延迟（换几个 URL 试，看是不是探测 URL 的问题）
python mihomo/mihomo_api.py delay https://opencode.ai/ "🤖 AI接口" "🚀 节点选择"
```

**原因 / 解法**：

| 原因 | 判据 | 解法 |
|---|---|---|
| 组的探测 URL 在当前网络不可达 | 换 URL 后节点就正常 | url-test 的 url 要选**确实能通**的（如 `http://www.gstatic.com/generate_204`）；🤖 AI接口 用 `https://opencode.ai/` |
| 节点本身失效 / 机场停用 | 逐节点测，多个组同时红 | 换节点；长期靠 `EXIT_HEALTH` 守卫（`AX3000TOpenwrt` 仓的守护进程） |
| 组的当前选择被钉死在坏节点 | `now` 指向一个红节点 | 复位到 `♻️ 自动选择`；见 [PITFALLS.md](PITFALLS.md) §17 |
| 干净出口组（🤖 干净出口 / 🤖 AI网页）全红 | 印度入口塌陷 | 三条入口轮换；**全劣化时只告警，不降级到非印度节点** |
| 组是空的（成员为空） | `all` 数组为空 | 订阅更新后节点改名 → 靠 `filter` 正则跟随，或检查 `exclude-filter` 是不是把节点全排除了 |

> **url-test 会漂出口**：`🤖 AI网页` 与 `🤖 干净出口` 必须是 `select`，
> url-test 会按延迟漂到被 Google 判为 CN 的节点（[PITFALLS.md](PITFALLS.md) §9）。

---

<a id="ts-ai-400"></a>

## 5. AI 接口返回 400

**现象**：`opencode.ai` 返回 400（而不是 200）；或者「curl 能通但客户端 400」。

**排查步骤**：

```bash
# ① 手动发最小请求（模型测试已从 ai-api-check.sh 移除，2026-10-26）
ssh root@10.0.0.1 'KEY=$(cat /etc/ShellCrash/opencode.key); \
  curl -s -x http://127.0.0.1:7890 -o /tmp/ai400.json -w "%{http_code}\n" \
  https://opencode.ai/zen/go/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"deepseek-v4.1-flash\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":8}"'
# 失败时看响应体前 200 字节
ssh root@10.0.0.1 'head -c 200 /tmp/ai400.json'

# ② 确认走的是代理口，且出口正常
ssh root@10.0.0.1 'curl -s -x http://127.0.0.1:7890 -o /dev/null -w "%{http_code}\n" https://opencode.ai/'
```

**原因 / 解法**：

| 判据 | 原因 | 解法 |
|---|---|---|
| 最小 token 请求也 400 | **请求体字段不被该模型接受**（如某些模型不接受思考类字段） | 用「模型真实请求体」复现再对比；手动复测用的是最小体 —— 最小体都 400 就是协议/模型侧问题，不是分流问题 |
| 最小 token 200、真实请求 400 | 同上，但只有真实体触发 | 对比真实体的字段；网关原样转发多余字段就会 400 |
| 三种协议里只有一种 400 | **请求头格式不对** | `chat/completions` 与 `responses` 用 `Authorization: Bearer`；`anthropic/messages` 用 `x-api-key` + `anthropic-version` |
| 401 / 403 | key 无效或**出口被拒**（香港出口会被 OpenAI 上游拒：`unsupported_country_region_territory`） | 排除香港出口（`exclude-filter` 里已有 `香港\|HK\|Hong Kong`）；换干净出口 |
| 400 且伴随节点劣化 | 出口节点本身异常 | 按 §4 处理 |

> **测 API 一定要加 `-x http://127.0.0.1:7890`** —— 路由器自己的 curl 不走透明代理，
> 不加代理口测的是**直连**，结论全错（[PITFALLS.md](PITFALLS.md) §5）。

---

<a id="ts-latency-fail"></a>

## 6. 测延迟脚本报连不上

**现象**：`python mihomo/latency_probe.py` 抛异常退出，
或打印一屏 `HTTPError` / `URLError` / `MISSING`。

**排查步骤**：

```bash
# ① 控制 API 通不通、要不要鉴权
curl -s -o /dev/null -w '%{http_code}\n' http://10.0.0.1:9999/proxies
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer <secret>" http://10.0.0.1:9999/proxies

# ② 换个工具试（它缺 secret 直接报错、带 IPv4/IPv6 自动选路、带重试）
python mihomo/mihomo_api.py proxies
```

> 两个脚本的用法与参数见 [TOOLS.md](TOOLS.md) §3、§6。

**原因 / 解法**：

| 现象 | 原因 | 解法 |
|---|---|---|
| **401 Unauthorized**，脚本在第一行 `get("/proxies")` 就崩 | 控制器启用了 `secret:`（2026-10-20 04:18 ShellCrash 每周自动更新加的），而 **`MIHOMO_SECRET` 没设** —— 脚本只在有 secret 时才带 `Authorization` 头 | `export MIHOMO_SECRET=...`；或用 `mihomo/mihomo_api.py`（缺 secret 直接抛错、带 IPv4/IPv6 自动选路与多重试）。**不要**为了迁就脚本去改面板密码 |
| 超时 / `URLError` | 路由器 IPv6 链路不稳、API 忙、或 9999 被 OOM 打掉 | 用 `mihomo_api.py`（自带重试与 chunked 解码）；确认 `/tmp` 水位、确认没有双实例（[PITFALLS.md](PITFALLS.md) §12） |
| 组名打印成 `MISSING` | 你给的组名 / 节点名清单跟订阅里的对不上（脚本本身**不写死**任何组名） | 改环境变量 `MIHOMO_PROBE_GROUPS` / `MIHOMO_PROBE_NODES`；或用 `mihomo_api.py proxies` 看真实名字 |
| 节点那几列全是 `HTTP404` | 组名里的 emoji / 中文没编码 | 脚本已 `quote`；若手工拼 URL 一定要 URL 编码 |

---

<a id="ts-audit-conflict"></a>

## 7. 规则审计报告里大量遮蔽冲突

**现象**：`rule_audit.py` 的报告里「实际改道」「严重冲突」条目很多，
或者某天突然比上次多出一大截。

**排查步骤**：

```bash
# ① 确认审计输入是「当前运行配置」，不是旧快照
ls -l config.yaml proxies.json
# config.yaml 必须来自当前路由器：
#   scp root@10.0.0.1:/tmp/ShellCrash/config.yaml ./config.yaml

# ② 跑审计
python mihomo/rule_audit.py config.yaml proxies.json third-party/ACL4SSR/Clash REPORT.md

# ③ 看机器可读结果，定位具体条目
python -c "import json;d=json.load(open('findings.json',encoding='utf-8'));print(list(d.keys()))"
```

> 审计器的用法与 `AUDIT_*` 环境变量见 [TOOLS.md](TOOLS.md) §5。

**原因 / 解法**：

| 原因 | 判据 | 解法 |
|---|---|---|
| **审计输入是旧快照** | `config.yaml` 的时间戳早于最近一次订阅更新 | 重新 `scp` 运行配置 |
| 上游 lists 与运行配置不是同一版 | `lists/` 里的上游列表和配置里的分段对不上 | 重新下载上游列表；或改用 `third-party/ACL4SSR/Clash/` 里与该配置配套的那份 |
| 模板顺序本身冲突（ProxyLite 宽泛 TLD 早于 ChinaDomain） | 冲突条目集中在 `.hk` / Steam / Bing / googleapis | 「分类修正层」+ CN 中间层；见 [RULE-AUDIT.md](RULE-AUDIT.md) §4 |
| **Google 广告域被宽泛 `google` 规则遮蔽** | `pagead2.googlesyndication.com` / `www.google-analytics.com` 的命中规则是 `DomainKeyword,google`，出口是 `🤖 干净出口`；模板 BanAD 的 REJECT 在更后面 | 在 Google 块之前加广告 carve-out；`ai-api-check.sh` 第 18 段逐条断言 |
| 有意覆盖被当成冲突 | 剩余 severe 集中在 9 条 FCM、2 条 flashtalking 广告、2mdn 广告；`app-measurement.com` 已于 2026-10-22 改 REJECT | **这些是有意的**，登记在白名单里，不要「修」掉 |

**预期基线**：Phase 1/2 实施后是「139 个代表域名 **0 异常**」，
剩余 13 条 severe **全部是有意覆盖**。突然变多 = 输入或配置出了问题，不是规则退化。

---

<a id="ts-mrs-order"></a>

## 8. mrs 规则集与内联规则顺序

**现象**：`RULE-SET,cn` 明明插进去了，某些 CN 域名运行时仍走国外媒体；
或者内联规则与 mrs 规则集对同一域名给出不同结论。

**排查步骤**：

```bash
# ① 确认 cn provider 与 RULE-SET 行都在
ssh root@10.0.0.1 "grep -n 'rule-providers:' -A 12 /tmp/ShellCrash/config.yaml | head -20"
ssh root@10.0.0.1 "grep -n 'RULE-SET,cn' /tmp/ShellCrash/config.yaml"

# ② 确认位置：最后一条「📲 电报消息」之后、第一条「🌍 国外媒体」之前
ssh root@10.0.0.1 "grep -n '📲 电报消息\|🌍 国外媒体\|RULE-SET,cn' /tmp/ShellCrash/config.yaml | head"

# ③ mrs 与文本列表会不会不一致：看运行时实际命中
python mihomo/mihomo_log.py 20 joox.com
```

**原因 / 解法**：

| 原因 | 解法 |
|---|---|
| 运行中的 `cn.mrs` **比文本列表滞后**（mrs 是预编译产物，上游更新与部署不同步） | 已知漂移，例：`joox.com` 运行时仍走 `🌍 国外媒体`。要么等 mrs 跟上，要么**保留显式代理覆盖** |
| `geosite:cn` 的覆盖范围会随上游变化 —— 某个本该代理的域名被收录 → 被直连 | 显式代理覆盖必须保留（OneDrive、Epic 等）；每次更新后跑 `rule_audit.py` 回归 |
| 顺序不对：`RULE-SET,cn` 插早了会被服务专用规则盖掉，插晚了会被宽泛代理盖掉 | 固定插在「电报消息之后、国外媒体之前」；`ai-api-check.sh` 第 8 段会巡检这个位置 |
| provider 配置不对（`behavior` / `format` 不是 `domain` / `mrs`） | `rules-mid.sh` 的预检会拦；修 provider 后重跑 |

**根治**：[RULE-AUDIT.md](RULE-AUDIT.md) §4.4（CN 直连中间层）与
[PITFALLS.md](PITFALLS.md) §15（先匹配先赢）。

---

<a id="ts-whole-net-down"></a>

## 9. 改完规则后整网断 / 只有部分域名解析失败

**现象**：PC 显示 WiFi 已连接但无法上网；`nslookup` 对部分域名（如 `search.bilibili.com`）
失败，但 `ping 223.5.5.5` 通；或浏览器报「找不到 DNS 地址」。

**排查步骤**（只读，不要跑全量规则扫描）：

```bash
# ① 代理进程与端口
ssh root@10.0.0.1 "ps | grep CrashCore; netstat -lntp | grep -E ':7890|:7892'"

# ② 内存与启动错误
ssh root@10.0.0.1 "free -m; tail -30 /tmp/ShellCrash/ShellCrash.log"

# ③ 配置生成失败的痕迹
ssh root@10.0.0.1 "grep -n 'rules-cnip\|rules-dedup' /etc/ShellCrash/starts/clash_modify.sh; ls -la /etc/ShellCrash/rules-*.sh*"
```

**判据 / 解法**：

| 看到什么 | 说明 | 怎么做 |
|---|---|---|
| `ps` 里没有 CrashCore，`rules-cnip: line count mismatch` | 并发 `start.sh start` 写坏了本次配置生成 | 按 [PITFALLS.md](PITFALLS.md) §25：disable init.d、killall、暂停 cron、只跑一次 `start.sh start` |
| `ps` 里有两个 CrashCore | procd + legacy 双实例 | 按 [PITFALLS.md](PITFALLS.md) §12/§25：disable init.d、kill 掉不占端口的那个 |
| 有 CrashCore 但可用内存 < 20 MB | 双实例 / 13k 配置 / 去重扫描挤爆内存 | 先杀多余实例；不要在路由器上跑 `rules-dedup.sh --check`（§24） |
| `nslookup` 部分域名失败，`ping 223.5.5.5` 通 | dnsmasq 把部分域名转给 mihomo DNS，而 CrashCore 没起来 | 先恢复 CrashCore；不要改 dnsmasq 上游做临时绕过 |
| `rules-dedup` 出现在 `clash_modify.sh` 里 | 去重钩子被挂到运行时 | 删掉该调用；去重只在 PC 对副本跑（§24） |

**恢复顺序**（维护窗口，网络可能中断）：

1. `pidof CrashCore` 确认没有实例；
2. 暂停 `guardian.sh` / `start_legacy_wd.sh` 的 cron；
3. `/etc/init.d/shellcrash disable`；
4. 只跑一次 `/etc/ShellCrash/start.sh start`；
5. 验证单实例 + 端口 + `free -m`；
6. 恢复 cron，再跑 `ai-api-check.sh` 17 段。

**根治**：[PITFALLS.md](PITFALLS.md) §24（O(N²) 不在路由器跑）、§25（并发启动）、
[MAINTENANCE.md](MAINTENANCE.md) §2.4（变更纪律）。

---

## 还没找到？

1. 先跑 `ai-api-check.sh` —— 17 段覆盖了本仓最容易悄悄坏掉的十几个点。
2. 再看仓库根 [CHANGELOG.md](../CHANGELOG.md) —— 过去的每一次故障都记了现象与根因。
3. 还不行 → 往 [PITFALLS.md](PITFALLS.md) 加一条（格式见该篇末尾），
   并在 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 补一个检索入口。
