# 踩坑总汇

> **一句话**：本仓长期维护的坑清单 —— 每条给「现象 → 根因 → 解法」，
> 带日期与出处；**新踩一个坑就往这里加一条**，别只留在聊天记录里。

排查某个具体现象的命令级步骤见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)；
本篇只负责「为什么会这样、怎么根治」。

**目录**

1. [顶层 `rule-providers` 重复 = mihomo 直接拒载](#p1)
2. [`rules.yaml` 是生成物，手改必丢](#p2)
3. [`*.X` 只匹配单标签，`+.X` 才是任意深度](#p3)
4. [`start_old=ON` 时重启必须用 `start.sh start`](#p4)
5. [路由器自己的 curl 不走透明代理](#p5)
6. [hotupdate 必须写 `/etc/ShellCrash/config.yaml`](#p6)
7. [QUIC 只走 UDP，会直出绕过透明代理](#p7)
8. [Google 国内边缘段 `203.208.32.0/19`：要剔除、要 `no-resolve`](#p8)
9. [机场节点的地理标签不可信：27 个节点里只有 1 个印度](#p9)
10. [`.lan` 搜索域污染 fake-ip 匹配](#p10)
11. [ShellCrash 每次重启重写 `inet shellcrash` 整表](#p11)
12. [两个「主人」= 双 mihomo 实例，白占 50 MB 内存](#p12)
13. [`/tmp` 是 tmpfs，重启即清空](#p13)
14. [Chrome LNA 把 fake-IP 判成「本地地址」](#p14)
15. [规则存在 ≠ 规则生效：先匹配先赢](#p15)
16. [分类正确 ≠ 功能可达](#p16)
17. [代理的「通」要按真实出口耗时判定](#p17)
18. [判断 Google 302 要用 GET，不能用 HEAD](#p18)
19. [策略名为空会写出尾逗号规则，mihomo 起不来](#p19)
20. [改完 nft 规则不清 conntrack，等于没改](#p20)
21. [凭据不再写在源码里：不设环境变量就报错退出](#p21)

---

<a id="p1"></a>

## 1. 顶层 `rule-providers` 重复 = mihomo 直接拒载

**现象**：自定义策略组、AI 分流、CN 中间层**一起消失**，路由看起来「像没改过」。
日志里最多一句「自定义配置文件校验失败」，**没有**「哪一行重复」的提示。
实测报错形态：`mapping key "type" already defined`。

**根因**：YAML 同一层不允许同名 key。mihomo 解析到重复的**顶层** `rule-providers:` 就
**拒绝加载整个配置**；ShellCrash 遇到校验失败会**静默回退基础配置**继续跑 ——
这是「宁可少功能也不能断网」的设计，代价是所有自定义无声消失。
本仓的合并链路天然会制造重复：基础 config.yaml 是上一次合并结果的快照（已含上次的自定义组），
`merger_yaml` 又把本次的用户自定义组追加进去，同名组必然出现。

**解法**：

- **不要把 `rule-providers` 写进 `others.yaml` / 用户 yaml** —— 顶层 `rule-providers` 重复会直接拒载。
  规则集统一复用既有 provider（如 `rule-providers.cn`）。
- 由 `reorder-groups.sh` 做同名组去重（保留**第一次**出现 —— merger_yaml 把最新定义放在最前）
  与组内重复 key 清理。
- 合并后**必须**跑 `CrashCore -t` / `mihomo -t` 校验，通过才热加载。
- 巡检：`ai-api-check.sh` 第 5、8、12 段。

**判据**：面板里**自定义组还在不在**。在 → 配置加载了，问题在规则顺序；
不在 → 配置被拒载了。详见 [ARCHITECTURE.md](ARCHITECTURE.md) §5。

---

<a id="p2"></a>

## 2. `rules.yaml` 是生成物，手改必丢

**现象**：在 `/etc/ShellCrash/yamls/rules.yaml` 里加的规则，几天后不见了。

**根因**：这个文件是 `config/generators/ai-rules-update.sh` 的**输出**。
cron `30 4 * * 0` 每周重跑，生成器**整文件重写**。
文件头两行就是自证：`# AI 服务分流规则 — 由 MetaCubeX/meta-rules-dat ... 生成` +
`# 更新于 <时间戳>`。

**解法**：

- 要改规则 → 改**生成器**（`config/generators/ai-rules-update.sh`），
  规则写进「分类修正层」，重跑生成器，再跑 `ai-api-check.sh` 校验。
- 本仓的 `config/generated/rules.yaml` 是**生成物快照**（目录名即约定），
  作用是「离线也能看到当前生效的规则长什么样」，不是编辑入口。
- 唯一例外：上游 geosite 分类确实错了（某域名应该归 AI 结果归了媒体），
  这也要写进生成器的修正层 —— 否则下次更新照样被覆盖。

---

<a id="p3"></a>

## 3. `*.X` 只匹配单标签，`+.X` 才是任意深度

**现象**：fake-ip 排除清单里写了某域名，客户端访问**照样拿到假 IP**；
或者清理 `.lan` 搜索域后，`.lan` 变体变成 NXDOMAIN 而不是回落绝对名。

**根因**：mihomo 的 fake-ip 匹配语法有两种：

| 写法 | 匹配范围 |
|---|---|
| `*.X` | **只匹配单标签**（`a.X`，不匹配 `b.a.X`） |
| `+.X` | **任意深度后缀**（`a.X`、`b.a.X`、`b.c.a.X` 都匹配） |
| 裸 `*` | **完全失效**（什么都匹配不了） |

**解法**：

- fake-ip 排除清单一律用 `+.域名` 形式（`+.google.com`、`+.gstatic.com`、`+.googleapis.com`）。
- 清理失效条目：裸 `*` 直接删；`*.lan` 改成 `+.lan`。
- 与 mihomo 的 `rule-set:` 是同一层语义（`rule-set:` 才是任意深度）。

---

<a id="p4"></a>

## 4. `start_old=ON` 时重启必须用 `start.sh start`

**现象**：按常规方式重启代理（面板点重启 / procd 重启 / `start.sh restart`），
代理起不来或配置不生效；日志显示走的是另一条启动路径。

**根因**：ShellCrash 开了 `start_old=ON`（旧版启动模式），
此时**生效的启动路径是 `start.sh`**，别的重启方式走不到那条路径，
于是看起来「重启了但什么都没变」。

**解法**：一律用 `/etc/ShellCrash/start.sh start` 重启。
需要确认是否生效，读组状态：面板里看 `🤖 AI接口` 的 `now`，
或 `curl -s -H "Authorization: Bearer <secret>" http://127.0.0.1:9999/proxies/<组名>`。

> 配套：改完配置要**重启**才生效（不只是 hotupdate）；
> 而 hotupdate 本身有独立的路径坑，见 §6。

---

<a id="p5"></a>

## 5. 路由器自己的 curl 不走透明代理

**现象**：在路由器上 `curl https://opencode.ai/` 超时或拿到异常结果，
但客户端（PC / 手机）访问正常；于是误判成「代理挂了」。

**根因**：**路由器本机流量走 OUTPUT 链，不走 PREROUTING** → 透明代理只作用于 LAN 客户端流量，
路由器自己的 `curl` 是直出。同理，路由器本机 `nslookup` 走 dnsmasq → WAN DNS，
拿到的是**污染过的解析结果**（实测 `gemini.google.com` 被解析到 Meta 段 `69.63.184.142`），
**不能代表 LAN 客户端**。

**解法**：

- 测 API 一律显式走代理口：`-x http://127.0.0.1:7890`。
- 判断客户端 DNS 一律用 `nslookup x 10.0.0.1` 或 `127.0.0.1:1053`（mihomo 自己的 DNS 口），
  不要用路由器本机的 `nslookup`。
- 验证 LAN 行为**必须从客户端发起** —— 本仓三张 nft 表都是 prerouting 链，对路由器本机无效。

---

<a id="p6"></a>

## 6. hotupdate 必须写 `/etc/ShellCrash/config.yaml`

**现象**：`task/task.sh hotupdate` 执行后**没有任何报错**，但配置没更新；
或者热更新被 mihomo 拒绝，ShellCrash 照旧静默回退。

**根因**：两处叠加：

1. **mihomo `SAFE_PATHS`**：控制 API 只允许写入白名单路径。
   `/tmp/ShellCrash/config.yaml` 不在白名单里 → 写入被拒。
2. **`put_save` 丢弃 HTTP 状态码**：写失败（403/400）ShellCrash 不看状态码，
   当成成功 → **静默失败**，日志里什么都看不到。

**解法**：

- hotupdate 必须写 **`/etc/ShellCrash/config.yaml`**（持久路径），
  不是 `/tmp/ShellCrash/config.yaml`（tmpfs 运行副本）。
- **校验 HTTP 状态码**，别信 `put_save` 的返回值。
- 改完用「探针规则」验证：先插一条只在本配置里成立的探针规则，
  hotupdate 后确认它生效 —— 这是本仓当时用的验证手段。
- 巡检：`ai-api-check.sh` 第 6 段检查 `task/task.sh` 里是不是 `$CRASHDIR/config.$format`，
  被重置会自动 sed 修回。

---

<a id="p7"></a>

## 7. QUIC 只走 UDP，会直出绕过透明代理

> **覆盖范围正本**：[ARCHITECTURE.md](ARCHITECTURE.md) §2.2 ——
> Redir 只代理 TCP、UDP 一律直出 WAN，以及代理端口集与非白名单端口直出的规则。
> 本条只讲「它怎么坑人、怎么根治」。

**现象**：Chrome 打开 Gemini **页面外壳能开，但只剩输入框**（推荐区、侧栏不出现）；
无痕模式同样坏；而 Electron 内置浏览器（ZCode）**完全正常**。
或者「你坏、它好」—— 同一台机器两个浏览器行为相反。

**根因**：

1. Chrome 优先用 HTTP/3（QUIC），**Redir 模式代理不了 UDP** → UDP 一律直接出 WAN。
2. fake-ip-filter 里的 Google 域名拿的是**真实 IP**（不是假 IP），
   而原先的 QUIC 拦截只覆盖「假 IP 段」与「国内边缘段」→ 真实 IP 的 QUIC 直接带
   **国内出口 IP** 出 WAN，Google 看到的就是中国 IP。
3. Electron **默认不启用 QUIC** → 一直正常。**浏览器类问题要先看传输层，不要只看 HTTP 层。**

**解法**：

- 全局拒绝 UDP 443/8443（`firewall/tables/quicguard.nft`），浏览器立刻回落 TCP，
  全部流量走代理 → 同一会话单一出口 IP。
- 同时拒掉其它 QUIC/DoQ 端口：`4433 5226 5228 8081 8883 19302`。
- 代价：国内应用的 QUIC 也一并回落 TCP（流量略增），换来出口 IP 一致。
- 判别手法：把 UDP 443 全局拦掉再复测；或在 mihomo 连接里看 `destinationIP`
  与下载字节是否停在半截。
- 巡检：`ai-api-check.sh` 第 16 段（文件与 live 表都要查）。

---

<a id="p8"></a>

## 8. Google 国内边缘段 `203.208.32.0/19`：要剔除、要 `no-resolve`

**现象**：Gemini 主端点走了日本节点，但 gstatic / gvt1 / googletagmanager /
app-measurement / tools.google.com 等 **13 个 Google 端点全部以中国出口 IP 直连**
（`58.254.x` / `203.208.x`），与 API 的日本出口割裂；
实测 `connectivitycheck.gstatic.com → dst=203.208.41.2 → rule=IPCIDR 203.208.32.0/19 → chains=DIRECT`。

**根因**：**没有 `no-resolve` 的 `IP-CIDR` 规则会在规则匹配时触发真实 DNS 解析** ——
本来按域名来的流量被解析到国内边缘 IP，然后被这条 IP 规则命中并直连。
再加上 TLS 嗅探缺 `override-destination`：客户端解析到国内边缘 IP 时，
mihomo 只用 SNI 做规则匹配，**连接目标仍是原来的国内边缘 IP** →
即使走日本节点，Google 仍按「你在中国的边缘」返回限制页。

**解法**（三件事一起做，缺一件就复现）：

1. **加 `,no-resolve`**：相关 IP-CIDR 规则末尾加 `no-resolve`，避免按域名触发真实解析。
2. **剔除国内边缘段**：`203.208.32.0/19`（及 IPv6 段 `2401:3800::/32`）不放在
   「国内直连」侧 —— 改为由 `firewall/tables/googlecn.nft` 把 LAN 发往该段的
   TCP `{80,443}` **重定向进 mihomo**，让域名规则（AI 组 / 直连）有机会生效。
3. **TLS 嗅探开 `override-destination`**：`clash_modify.sh` 里
   `sniffer.tls` 加 `override-destination: true`（原来只有 http 有）。

**顺带**：非白名单端口的真实 IP 目标直接放行 —— FCM 5228 / DoQ 19302 必须加进代理端口集。

---

<a id="p9"></a>

## 9. 机场节点的地理标签不可信：27 个节点里只有 1 个印度

**现象**：Gemini 报「不支持此国家/地区」；`support.google.com` 页里 `var cc='CN'`；
`www.google.com` 302 到 `www.google.com.hk/url?...&hl=zh-CN`；
Play 自动给 USD 而不是 JPY。
但第三方 GeoIP（ipinfo / ip-api / Cloudflare）**全都说「东京 / 新加坡」**。

**根因**：**服务侧的地区判定看的是出口 IP 的注册地，不是机房位置。**
全量实测 27 个节点：除印度外**全部 `cc=CN`** —— 连 Linode 美国段 `<REDACTED-EXIT-IP>`、
Hetzner 德国段 `<REDACTED-EXIT-IP>`、Azure 英国段 `<REDACTED-EXIT-IP>` 都是 CN
（IP 是正经海外机房地址，但**注册主体在中国**）。
只有印度那条 `<CLEAN-EXIT-IP>`（DigitalOcean，注册地印度）判定为 **IN**（5/5 稳定）。
解码原始订阅确认：**全订阅只有 1 个印度节点**。
台湾那条判定会随连接在 CN↔TW 之间跳变（轮换 IP 池），也不可靠。

**解法**：

- **换国家没用**，换 IP 池也未必（判定看注册地）。
- `🤖 AI网页` / `🤖 干净出口` 组用 **`select` 不用 `url-test`** ——
  url-test 按延迟会漂到被判 CN 的节点（实测 28 节点里印度延迟排第 17，url-test 永远选不到它），
  而且漂一次出口 IP 就变一次，会话直接废。
- 出口钉到唯一干净的印度入口；守护进程每 5 分钟探测 `support.google.com` 的 `var cc=`，
  一旦被判 CN 自动切回（`guardian.sh`，在 `AX3000TOpenwrt` 仓）。
- **同地区多入口 = 免费冗余**：机场印度只给 p6 一个入口，
  但 m2 / ct2 显然是同端口同 Host 服务的 → 在 `config/yamls/proxies.yaml` 自建
  `🇮🇳 印度-备用m2` / `🇮🇳 印度-备用ct2`。三条入口**共用同一出口 IP**，
  切入口不换 IP（Google 会话不受影响），只换一条链路。
- **三个入口全劣化时只告警，绝不降级到非印度节点** —— 那会让 Google 直接报「不支持此国家」。

**配套教训**：健康探测要能抓到真实症状。小响应 API 端点正常不代表大页面下载正常
（订阅入口的 p6 对 `gemini.google.com`（784 KB）实测 22.3 s / 25 s 超时，
而同节点的小响应 API 端点始终 0.9 s）→ 探测要用**真实页面**并截断到 128 KB 测总耗时。

---

<a id="p10"></a>

## 10. `.lan` 搜索域污染 fake-ip 匹配

**现象**：客户端把查询拼成 `xxx.lan`（路由器 `dhcp.@dnsmasq[0].domain='lan'`），
fake-ip-filter 的精确 / 后缀匹配**全部失配** → 假 IP 没被排除 → 该走直连的域名走了代理。

**根因**：搜索域 + 匹配语法两件事叠加（见 §3：`.lan` 这种单标签域必须用 `+.lan`）。

**解法**：

- 两条修法都验证过：
  ① 用**空值** DHCP option 119/15 覆盖 → **Windows DHCP 客户端会丢弃整个 DHCPOFFER**，
     PC 拿不到租约（IP 变 APIPA `169.254.x`，SSH 全断）→ **不可用**；
  ② 服务端把 `*.lan` 改成 `+.lan` → `.lan` 变体返回 **NXDOMAIN**，客户端自动回落绝对名 ✓（采用）。
- 同时 `uci set dhcp.@dnsmasq[0].domain=''` 停止下发 option 119 搜索域。
- 删除失效的裸 `*` 条目。

---

<a id="p11"></a>

## 11. ShellCrash 每次重启重写 `inet shellcrash` 整表

**现象**：`nft add rule inet shellcrash ...` 加的规则，代理重启后全没了。

**根因**：ShellCrash 启动时用 `starts/fw_nftables.sh` **整表重建** `inet shellcrash`。

**解法**：

- 要持久 → 改 `fw_nftables.sh`（本仓拥有，会被 `post-sc-update.sh` 在官方更新后恢复）；
- 要独立 → **独立 nft 表**（本仓 `firewall/tables/` 三张表就是这么来的）
  + `rc.local` 开机加载 + 守护进程补载。
- 独立表还有额外好处：ShellCrash 重建 `inet shellcrash` 的那几秒里，
  LAN 的 53 端口查询会漏到 dnsmasq → 拿到污染结果 → 站点超时；
  `googleroute.nft` 独立存在就没有这个死窗口。

---

<a id="p12"></a>

## 12. 两个「主人」= 双 mihomo 实例，白占 50 MB 内存

**现象**：mihomo 有两个进程；后者抢不到端口但白占约 50 MB 内存
（MemAvailable 从 86 MB 掉到 12 MB）。重启验证时才发现。

**根因**：**两个主人**。看门狗调 `start.sh start` 时会先停掉 procd 的实例，
而 procd 配了 respawn 会立刻拉回来 → 变成「procd 实例 + legacy 实例」并存。

**解法**：只留一个主人 —— `etc/init.d/shellcrash disable`（停用 procd 的 `S99shellcrash`），
只留看门狗走 legacy 路径。实测：杀光实例后看门狗 5 秒拉起，**单实例**独占 4 个端口，
内存回到 56 MB。

---

<a id="p13"></a>

## 13. `/tmp` 是 tmpfs，重启即清空

**现象**：重启后 mihomo **6 分钟没起来**；开机自启失败后没有任何自愈。

**根因**：`/tmp` 是 tmpfs，`/tmp/ShellCrash` 重启后整个目录不存在 →
看门狗的 `mkdir` 锁目录永远失败 → 每分钟 exit 1 → 开机自启失败后无任何兜底。
另一个同源问题：`/tmp` 只有 116 MB，写满会 OOM 杀核心并触发 `mtk-wdt` **整机重启**
（实测 12:45 就是这么重启的，13:00 快照 tmp 99.4% 满）。

**解法**：

- 看门狗启动前先 `mkdir -p /tmp/ShellCrash`（`config/starts/start_legacy_wd.sh` 已带）。
- 陈旧锁自愈：锁目录存在且超过 300 秒就删掉重建。
- `pidof CrashCore` 存活短路：进程还在就直接退出（pid 文件在 tmpfs，重启后会丢，
  老逻辑会误判「没有进程」从而停掉一个健康运行的代理再重启它）。
- 守护进程加 `/tmp` 水位守卫（≥ 80% 清临时大文件）。

---

<a id="p14"></a>

## 14. Chrome LNA 把 fake-IP 判成「本地地址」

**现象**：Chrome（登录态）打开 `gemini.google.com` **只剩输入框**，页头/侧栏/推荐区全无；
**无痕模式同样坏**；Electron 内置浏览器完全正常。
控制台报：`Permission was denied for this request to access the 'local' address space`
（被拒的是 `www.gstatic.com/bg3/boq-bard-web/islands/assets/islands-*.js`）。

**根因**：Chrome 138+/155 的 **Local Network Access（LNA）** 把 mihomo 的
**fake-IP `198.18.0.0/15`** 判为「本地地址」→ 从公网页面加载的**子资源**被 CORS 拒。
Gemini 的页头/侧栏/推荐区由 `www.gstatic.com/.../islands/*.js` 懒加载渲染 →
bundle 被拒 → 只剩主 bundle 画出的输入框。
`gemini.google.com` 本身早就在 fake_ip_filter 里（`+.google.com`）→ 真实 IP → 页面壳正常。
（与 10-19 的「扩展安装报 Image decode failed」是**同一个 LNA 机制**。）

**解法**：`/etc/ShellCrash/configs/fake_ip_filter` 增加 `+.gstatic.com`、`+.googleapis.com`
（连同已有的 `+.google.com`，共 21 条）→ 静态资源域名给客户端真实 IP，LNA 不再拦。

**判别心得**：Chrome 与 Electron 的差别不在网络，在**浏览器策略**（Electron 不启用 LNA）。
判断页面是否渲染要看截图或 `document.body.innerText` ——
`--dump-dom` + grep 会命中 JS 源码里的字符串（假阴性）。

---

<a id="p15"></a>

## 15. 规则存在 ≠ 规则生效：先匹配先赢

**现象**：规则表里明明写着某域名走 A 组，实际流量走的是 B 组。

**根因**：mihomo 的规则是**先匹配先赢**。上游模板的顺序是
`自定义 → LAN → 广告 → FCM/GoogleCN → 流媒体 → AI → 微软/苹果/电报 → 媒体代理 → 通用代理 → CN 直连 → IP → MATCH`。
问题出在「媒体/通用代理」排在「CN 直连」**之前** → 宽泛 TLD / 关键词抢先。

**解法**：

- 具体服务规则必须在宽泛关键词/TLD 之前。
- 用 `OpenwrtOpsToolkit` 仓的 `mihomo/rule_audit.py` 离线算「每条域名规则的真实生效目标」——
  它按先匹配先赢的语义逐条算，能直接列出**声明目标 ≠ 实际目标**的规则。
- CN 直连中间层（`rules-mid.sh` 插入的 `RULE-SET,cn`）一次性解决宽泛代理与 CN 直连的顺序冲突。
- 结论与量化口径见 [RULE-AUDIT.md](RULE-AUDIT.md)。

---

<a id="p16"></a>

## 16. 分类正确 ≠ 功能可达

**现象**：`onedrive.live.com` 的规则目标是「微软服务」组（**分类正确**），
但该组当前是 DIRECT，而直连实测 10 秒超时 → OneDrive 不可用。

**根因**：规则审计只看「目标组」，没看「这个组的实际出口可达吗」。
组选 DIRECT 还是代理，是**运行时状态**，不是规则的一部分。

**解法**：

- 审计必须同时看**目标组**和**组的实际出口 / 可达性**，
  否则会把「分类正确但功能不通」误判成通过。
- 把关键服务的可达性探测并进自检脚本（`ai-api-check.sh`）。
- 分流与「哪个组现在选了什么」是两件事，改规则不会自动改组的当前选择 ——
  组的当前选择由 `profile.store-selected` 持久化，或由守护进程维护。

---

<a id="p17"></a>

## 17. 代理的「通」要按真实出口耗时判定

**现象**：PC 侧大部分站点 15 秒超时（Gemini / Google / Play / YouTube / GitHub），
但 Cloudflare 与百度正常；**路由器自身的显式代理探测全部正常**（Google cc=IN、OpenAI 401）。
mihomo `/connections` 显示连接**确实进了 mihomo**，链路正常，DNS 正常。

**根因**：**节点劣化**，不是规则问题。逐节点实测 GitHub 耗时：日本 0.82 s、
台湾 4.36 s、新加坡 4.79 s、**德国 5.01 s**（早前还是 5 s）、美国 LA 6.44 s。
`🚀 节点选择` 被钉在 `🇩🇪 德国节点`（不是 `♻️ 自动选择`）→ url-test 的自动择优被绕过。

**解法**：三种故障模式各有各的判据，别混：

| 故障模式 | 判据 |
|---|---|
| 规则错 | 看 mihomo `/rules` 的首匹配 |
| 旁路漏 | 看 nft 计数器 |
| **节点劣化** | **看真实出口耗时**（两次 `api.ipify.org` 取均值，> 3 s 即判劣化） |

守护进程加 `EXIT_HEALTH`（通用池）与 `CLEAN_EXIT_HEALTH`（干净出口）两条守卫：
劣化时复位 / 轮换入口。**只盯规则命中会把「节点劣化」误判成「规则没生效」。**

---

<a id="p18"></a>

## 18. 判断 Google 302 要用 GET，不能用 HEAD

**现象**：`curl -I`（HEAD）测不出 302，误以为「没有跳转 = 没被判定成境外」。

**根因**：Google 对 HEAD 请求的返回与 GET 不同。

**解法**：

- 用 `curl -o /dev/null -w '%{redirect_url}'`（GET）看跳转。
- 精确判定：抓 `https://support.google.com/gemini/answer/13575153` 页面里的 `var cc='XX'`。
  该页整页 1.6 MB，`cc` 变量在 1 MB 之后 —— 用 `--max-filesize` 截断抓不到。
- 切节点后**必须校验切换是否生效**（读组的 `now`）+ **连测两次出口 IP**，
  否则测的是上一个节点。

---

<a id="p19"></a>

## 19. 策略名为空会写出尾逗号规则，mihomo 起不来

**现象**：配置校验失败 → 「服务启动失败」→ `/tmp/ShellCrash/CrashCore: not found`。
报错形态：`rules[16] [DOMAIN-SUFFIX,i.google.dev,] error: format invalid`。

**根因**：生成规则的脚本（`ai-rules-update.sh` / `reorder-groups.sh` → `yamls/rules.yaml`）
在某条规则上写出了**空的策略名**，YAML 里就成了尾逗号。

**解法**：

- 生成器写规则时**不允许空策略名**（历史故障里已手工修成
  `- DOMAIN,ai.google.dev,🤖 人工智能`）。
- 巡检：`ai-api-check.sh` 第 12 段（规则文件完整性：空组名 / 原子写 / 组定义）。
- 校验必须过 `CrashCore -t` 才能热加载。

---

<a id="p20"></a>

## 20. 改完 nft 规则不清 conntrack，等于没改

**现象**：规则改了、配置也重启了，但老连接的行为完全没变。

**根因**：**硬件 offload 的存量连接不会重新走链** —— 已建立的连接按 conntrack 里的旧状态走，
不会重新经过 nft 链。

**解法**：改端口 / 改规则后**清理 conntrack** 再复测。

**边界**：本仓**只确认了存量连接这一层**。offload 的流量是否整体绕过 Redir 重定向，
**尚无直接实测** —— 详见 [ARCHITECTURE.md](ARCHITECTURE.md) §2.4 的「待补」两行。

---

<a id="p21"></a>

## 21. 凭据不再写在源码里：不设环境变量就报错退出

**现象**：`python mihomo/mihomo_api.py proxies`（脚本在 `OpenwrtOpsToolkit` 仓）立刻抛
`RuntimeError: 缺少环境变量 MIHOMO_SECRET（mihomo 控制台 secret）`，
**一条命令都跑不下去**。换台机器、换个终端跑同一个脚本，同样起不来。

**根因**：以前控制台 secret 是**硬编码在源码里**的 —— 规则扫描与 5 个链路诊断脚本各存一份。
代价有三个：凭据进版本库、
换 secret 要同时改 6 处、漏改一处就变成**静默 401**（看不出是凭据问题还是链路问题）。
现在 secret 改为**从环境变量 `MIHOMO_SECRET` 读**；
`HOST` / `PORT` 改为可用 `MIHOMO_API` / `MIHOMO_HOST` / `MIHOMO_PORT` 覆盖（默认 `http://127.0.0.1:9999`）；
**取不到就抛 `RuntimeError`，不继续往下跑**。

**解法**：

```sh
# 从设备上取 secret 并导出（值不落盘、不进仓库）
export MIHOMO_SECRET="$(ssh root@10.0.0.1 'grep -m1 "^secret=" /etc/ShellCrash/configs/ShellCrash.cfg | cut -d= -f2- | tr -d "\x27\x22"')"
```

- **报错退出是有意的，不是 bug** —— 宁可当场喊「你没给凭据」，
  也不要拿着空 secret 去请求、再把一个含义不明的 401 当成「链路故障」去排查。
- 换 secret 后**只需重新 `export` 一次**，不用再改 6 处源码。
- 设备侧真源是 `/etc/ShellCrash/configs/ShellCrash.cfg` 的 `secret=` 行；
  完整的取值说明见本仓 [SECRETS.md](SECRETS.md)。

**出处**：2026-10-20 凭据外置批次 —— 规则扫描与
`mihomo/{mihomo_api,mihomo_log,capture_live,qq_domain_classify,qq_rule_probe}.py` 一族，
共 **6 个脚本**（见仓库根 [CHANGELOG.md](../CHANGELOG.md)）。
**2026-10-20 迁仓后**：这些脚本在 `OpenwrtOpsToolkit` 仓（公开）的 `mihomo/` 与 `cdn/` 下，
报错文案里的「见 docs/SECRETS.md」也一并去掉了 —— 那是本仓的路径。

---

## 新增一条的格式

新踩一个坑，往这里加一条，**必须包含**：

1. **现象** —— 看到的症状（尽量给原文报错）
2. **根因** —— 为什么是这样（要有机制，不是「因为配置错了」）
3. **解法** —— 具体怎么做（命令 / 改哪个文件）
4. **出处** —— 哪天、哪次任务、哪个文件（指向仓库根 [CHANGELOG.md](../CHANGELOG.md) 的版本段）

写完在上面的目录里加一行锚点链接。

---

## 22. urldecode 的八进制往返会静默变成空串

**现象**：在路由器上（uhttpd 环境）用 shell 脚本做 URL 解码，**所有组名查找都失败** ——
组名带 emoji 或百分号编码时，解出来是空字符串。脚本不报错，只是"查不到组"。

**根因**：早期版本的解码实现把每个字节先转成**八进制序列**（`\ooo`），
再交给 `printf` 展开还原。在 uhttpd 环境下这条往返**静默失效** ——
`printf` 拿到的是已经被 shell 消费掉的一层转义，还原出来是空的。
本地终端跑却正常，所以极难复现。

**解法**：**不要做往返**。直接用 awk 的字节表把 `%XX` 解成原始字节输出：

```sh
printf '%s' "$1" | awk '
function hexval(c) { return index("0123456789abcdef", tolower(c)) - 1 }
BEGIN { for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i }
{ ... 直接 append 原始字节 ... }'
```

字节表覆盖 0..255，**UTF-8 的组名（emoji、国旗）能原样存活**。

**可复现的最小样例**：[`../tools/reference/dec_test.sh`](../tools/reference/dec_test.sh)
（三个用例：`/proxies/GLOBAL`、带 emoji 的日文组名、`♻️ 自动选择`）。

**下次怎么避**：凡是"编码 → 字符串 → 再解码"的两步流程，先问一句**中间那层格式是谁消费的** ——
多一次转义就多一次静默失败的机会。
