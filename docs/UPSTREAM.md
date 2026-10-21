# UPSTREAM —— 本仓与上游开源项目的边界

> **一句话**：本仓站在四个上游项目（ShellCrash / ACL4SSR / mihomo / meta-rules-dat）
> 的肩膀上，但**边界画得很清楚**：哪些文件是上游原样、哪些是打补丁派生件、
> 哪些是本仓自研；随仓分发的上游代码副本一律放在 `third-party/`，
> 本仓自己的改动一律放在 `config/`。

---

## 1. 边界总表

| 本仓文件 | 性质 | 上游 | 许可证 |
|---|---|---|---|
| `third-party/ShellCrash/**` | **上游原样**（vendor 副本） | https://github.com/juewuy/ShellCrash @ `de1d9e2` | GPL-3.0 |
| `third-party/ACL4SSR/**` | **上游原样**（vendor 副本） | https://github.com/ACL4SSR/ACL4SSR @ `5756376` | CC BY-SA 4.0 |
| `config/starts/fw_nftables.sh` | **打补丁派生件** | ShellCrash `starts/fw_nftables.sh` | GPL-3.0 |
| `config/starts/start_legacy_wd.sh` | **打补丁派生件** | ShellCrash `starts/start_legacy_wd.sh` | GPL-3.0 |
| `config/hooks/rules-mid.sh` | **本仓自研**（作用在 ACL4SSR 血统的规则序列上） | 无 | GPL-3.0（本仓） |
| `config/hooks/reorder-groups.sh` | **本仓自研** | 无 | GPL-3.0（本仓） |
| `config/yamls/*.yaml` | **本仓自研**（ShellCrash 的官方扩展点，内容自写） | 无 | GPL-3.0（本仓） |
| `config/generated/rules.yaml` | **生成物**（由 meta-rules-dat 的 geosite 分类生成） | MetaCubeX/meta-rules-dat | GPL-3.0 |
| `config/generators/*.sh` | **本仓自研** | 无 | GPL-3.0（本仓） |
| `config/ai-api-check.sh`、`config/post-sc-update.sh` | **本仓自研** | 无 | GPL-3.0（本仓） |
| `config/archive/geo-test.sh` | **本仓自研**（一次性诊断，已归档） | 无 | GPL-3.0（本仓） |
| `firewall/tables/*.nft` | **本仓自研**（按 OpenWrt / nftables 语义写） | OpenWrt | GPL-3.0（本仓） |
| `tools/latency/archive/**` | **本仓自研**（早期探测残留，已归档） | 无 | GPL-3.0（本仓） |
| ~~`tools/**`（诊断脚本）~~ | **已迁出** → `OpenwrtOpsToolkit` 仓（公开，MIT） | 无 | 见 §6 |


> **`config/starts/` 里只有那 2 个文件是上游的**，其余全是本仓自研。
> 上游原版一律在 `third-party/ShellCrash/starts/` 里，一一对应。

### 1.1 上游项目一览（许可证 / 是否随仓分发）

> 这是门面「开源鸣谢」表里**「许可证」与「随仓分发」两列的正本** ——
> 门面只留「项目 + 用途」两列，细节以本表为准。

| 上游 | 用途 | 许可证 | 随仓分发 |
|---|---|---|---|
| [ShellCrash](https://github.com/juewuy/ShellCrash) | 透明代理框架；本仓用的 `yamls/` 扩展点、`starts/` 补丁机制都来自它 | GPL-3.0 | **是** —— `third-party/ShellCrash/`（上游原版 `starts/` 与规则模板） |
| [ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) | 分流规则的**数据源与模板血统**：设备侧规则模板是它的裁剪改编版，模板里 15 条 `ruleset=` 直接指向它的 `.list` | CC BY-SA 4.0 | **是** —— `third-party/ACL4SSR/`（15 个规则列表 + 模板原版） |
| [mihomo / Clash.Meta](https://github.com/MetaCubeX/mihomo) | 代理内核；`config.yaml` 的字段语义、`SAFE_PATHS` 行为都由它定义 | MIT | 否（仅引用语义） |
| [MetaCubeX meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) | geosite 分类与 ruleset（`cnip.mrs` 等）；`ai-rules-update.sh` 的数据源 | GPL-3.0 | 否（数据源，体积巨大） |
| [OpenWrt](https://openwrt.org) | 路由器固件与 nftables 子系统；本仓三张表用的 `inet` family、`reject with icmpx` 语法 | GPL-2.0 | 否 |

随仓分发的两份副本都在 `third-party/` 下，各带一份 `UPSTREAM.md` 来源凭证
（上游 URL、vendored commit SHA、license 全文位置、怎么更新），上游代码**一个字节未改**。
本仓自己的改动一律落在 `config/` 下；`config/starts/` 里那 2 个文件是
ShellCrash 上游脚本的**打补丁派生件**。许可传染性见 §4。

---

## 2. 补丁点清单（派生件改了上游什么）

两个派生件的补丁点共 **4 处标记**，逐处如下。
完整 diff 可现场复现：

```bash
diff -u third-party/ShellCrash/starts/fw_nftables.sh   config/starts/fw_nftables.sh
diff -u third-party/ShellCrash/starts/start_legacy_wd.sh config/starts/start_legacy_wd.sh
```

### 2.1 `config/starts/fw_nftables.sh`（上游 `starts/fw_nftables.sh`）

| # | 标记 | 位置 | 改动 | 原因 |
|---|---|---|---|---|
| 1 | `FCM_DOQ_PORT_MARKER` | `start_nft_route()` 首行 | 代理端口集 `$multiport` → `"$multiport,5228,19302"` | Google FCM(5228)/DoQ(19302) 不进代理端口集时，真实 IP 目标会直连、暴露国内出口 |
| 2 | `CN_IP_EXCLUDE_203208` | `#绕过CN-IP` 段 | `awk` 过滤掉 `203.208.32.0/19` | Google 国内边缘段留在 `cn_ip` 里会被 nft 提前放行直连，Google 判定为中国区 |
| 3 | `QUIC_BLOCK_MARKER` | IPv6 分支后、`#屏蔽quic` 前 | 新增 `udp dport {443, 8443} counter reject with icmpx type port-unreachable` | 只 `return` 挡不住 QUIC，HTTP/3 仍带国内出口 IP 直连逃逸 |

### 2.2 `config/starts/start_legacy_wd.sh`（上游 `starts/start_legacy_wd.sh`）

| # | 标记 | 改动 | 原因 |
|---|---|---|---|
| 4 | 无标记（注释说明） | ① `mkdir "$LOCKDIR" \|\| exit 1` 前加 `mkdir -p /tmp/ShellCrash`；② 锁目录存在且超过 300 秒则先删再建；③ 新增「`pidof CrashCore` 有进程就直接退出」早退分支 | `/tmp` 是 tmpfs，重启即清空 → 锁目录永远建不出来，看门狗每分钟 exit 1，代理拉不起来（2026-10-20 09:36 实测离线 6 分钟）；残留锁会让看门狗永久失效；pid 文件同样随 tmpfs 丢失 |

> 两个派生件都**保留了上游的 GPL-3.0 版权头**
> （`# Copyright (C) Juewuy`），这是「派生件」而非「重写」的事实凭据。

---

## 3. vendored 代码怎么更新

```bash
# ShellCrash（派生源；starts/ 在 ShellCrash.tar.gz 归档里，不在 git 树中）
git clone --depth 1 --branch dev https://github.com/juewuy/ShellCrash.git /tmp/sc-upstream
cd /tmp/sc-upstream && git rev-parse HEAD
mkdir -p /tmp/sc-extract && tar -xzf ShellCrash.tar.gz -C /tmp/sc-extract
diff -u /tmp/sc-extract/starts/fw_nftables.sh  third-party/ShellCrash/starts/fw_nftables.sh
diff -u /tmp/sc-upstream/rules/ShellClash.ini   third-party/ShellCrash/rules/ShellClash.ini

# ACL4SSR（数据源 + 模板血统）
git clone --depth 1 --branch master https://github.com/ACL4SSR/ACL4SSR.git /tmp/acl4ssr-upstream
cd /tmp/acl4ssr-upstream && git rev-parse HEAD
diff -u /tmp/acl4ssr-upstream/Clash/ChinaIp.list third-party/ACL4SSR/Clash/ChinaIp.list
```

**更新纪律**

1. **先 diff 再复制**：上游 `dev` 分支每次发版都换 `bin/` 下的二进制，
   `starts/` 里的脚本也可能跟着改。不 diff 直接覆盖 = 把本仓的 4 处补丁点基线冲掉。
2. **只改 `third-party/`**：上游原版落在 `third-party/`；本仓的改动落到 `config/starts/`。
   两边都要动时，先更新 `third-party/`，再把上游新增内容**手工合进** `config/starts/` 的派生件。
3. **每次更新都要同步 5 处**：对应项目的 `third-party/<name>/UPSTREAM.md`、
   `third-party/README.md`、仓库根 `NOTICE`、本文件 §1 边界总表、仓库根 `README.md`
   「开源鸣谢」表（门面只留项目与用途两列，许可证与是否随仓分发以本文件 §1 / §4 为准）。
   **不允许出现「文档说已 vendor 但目录里没有」或反过来的错位。**
4. 不拉 submodule（`--depth 1` 即可，**不要** `--recursive`）。

---

## 4. GPL-3.0 的传染性：本仓整体许可意味着什么

### 4.1 为什么整仓是 GPL-3.0

本仓随仓库分发了三类 GPL-3.0 衍生/派生内容：

| 内容 | 来源 | 与 GPL-3.0 的关系 |
|---|---|---|
| `config/starts/fw_nftables.sh`、`config/starts/start_legacy_wd.sh` | ShellCrash（GPL-3.0）的**打补丁派生件** | 派生作品，**必须**按 GPL-3.0 分发 |
| `third-party/ShellCrash/**` | ShellCrash（GPL-3.0）的**原样副本** | 逐字复制，保留许可证与版权头 |
| `config/generated/rules.yaml` 的模板规则部分 | meta-rules-dat（GPL-3.0）的数据 | 派生数据，按 GPL-3.0 处理 |

GPL-3.0 第 5 条：作品包含 GPL-3.0 覆盖的程序时，整体分发必须整体按 GPL-3.0 分发。
所以**不能**拆成「自研部分 MIT + 派生件 GPL」——那会让使用者无法确定整个仓库的许可，
而且组合作品本身就是 GPL-3.0 作品。仓库根 [LICENSE](../LICENSE) 是 GPL-3.0 全文，
覆盖**本仓自研部分 + 上述 GPL-3.0 派生/复制内容**。

### 4.2 一个例外：`third-party/ACL4SSR/` 不在 GPL-3.0 覆盖范围内

| 项 | 结论 |
|---|---|
| 上游许可证 | CC BY-SA 4.0（见 [`third-party/ACL4SSR/LICENCE`](../third-party/ACL4SSR/LICENCE)） |
| CC BY-SA 4.0 与 GPL-3.0 兼容性 | **不兼容**：CC BY-SA 4.0 要求衍生作品整体按 CC BY-SA 4.0 发布；GPL-3.0 要求整体按 GPL-3.0 发布。两个「整体必须同协议」的要求互斥 |
| 本仓怎么规避 | 把 ACL4SSR 的文件**原样隔离**在 `third-party/ACL4SSR/` 独立目录里，**不改一个字节**，并在该目录附上上游许可证全文 |
| 对使用者的义务 | 使用/再分发 `third-party/ACL4SSR/` 下的文件时：署名 ACL4SSR、保持 CC BY-SA 4.0；若做改编，改编物也要按 CC BY-SA 4.0 发布 |
| 实际影响 | 这些 `.list` 是**规则数据**，本仓**不修改**它们；把它们并入本仓自研代码或改写后再发布，会触发 CC BY-SA 的 ShareAlike —— **所以不要这么做** |

> **实践结论**：想改 ACL4SSR 的规则列表内容时，**不要改 `third-party/` 里的副本** ——
> 那是上游原样留档。要改就改本仓自己的 `config/`（例如 `config/hooks/` 里的后处理钩子），
> 让改动落在 GPL-3.0  territory 里，且不与上游文件混成同一个文件。

### 4.3 没有 vendor 的上游不影响本仓许可

mihomo、meta-rules-dat、OpenWrt **都没有随仓分发源码**，只是在运行期以
「设备侧安装包 / 按 URL 下载数据 / 语义参考」的形式被使用：

- 设备侧安装的 mihomo 内核本身按 **MIT** 分发（上游 `LICENSE`，Copyright 2023 KT）—— 那是**它**的义务，与本仓无关；
- meta-rules-dat 的数据按 URL 取用，本仓只保留**生成物** `config/generated/rules.yaml`，
  它是 GPL-3.0 派生数据，随本仓按 GPL-3.0 分发；
- OpenWrt 只是 nftables 语义参考。

## 5. 相关文档

| 位置 | 说什么 |
|---|---|
| [third-party/README.md](../third-party/README.md) | vendor 索引：项目 / URL / 用途 / license / commit SHA / 为什么 vendor |
| [third-party/ShellCrash/UPSTREAM.md](../third-party/ShellCrash/UPSTREAM.md) | ShellCrash 来源凭证 + 4 处补丁点的完整说明 + 更新命令 |
| [third-party/ACL4SSR/UPSTREAM.md](../third-party/ACL4SSR/UPSTREAM.md) | ACL4SSR 来源凭证 + 消费的 15 个 `.list` 清单 + 更新命令 |
| [NOTICE](../NOTICE) | 第三方声明：每个上游的来源、license、为何使用、**是否随仓分发** |
| 仓库根 [README.md](../README.md) 「开源鸣谢」 | 面向使用者的鸣谢表（**只留项目与用途两列**；许可证、是否随仓分发以本文件 §1 / §4 为准） |
| [docs/ARCHITECTURE.md](ARCHITECTURE.md) | 配置生成链路与运行期架构 |
| `OpenwrtOpsToolkit` 仓（公开） | 通用工具的所在地 —— 边界见本文件 §6 |

---

<a id="upstream-toolkit"></a>

## 6. 与 `OpenwrtOpsToolkit` 仓的边界（通用工具已迁出）

> **一句话**：本仓是**参考实现**（分流配置与文档），通用工具在公开仓
> `OpenwrtOpsToolkit` —— 谁拥有哪个文件，看这一节。

### 6.1 为什么迁

本仓的公开树只保留**配置、规则与文档**；分流规则的数据源自机场，模板里不出现
真实服务器域名。实测发现，**这批诊断脚本几乎全是设备无关的** ——
规则审计、控制面查询、节点延迟、CDN 专项，谁装 mihomo 都能用。
把它们留在本仓 = 好用的工具没人用得到。

### 6.2 文件归属

| 工具 | 原位置（本仓） | 现位置（`OpenwrtOpsToolkit`，公开） |
|---|---|---|
| 规则审计器 | `tools/rule_audit.py` | `mihomo/rule_audit.py` |
| 流式扫 `/rules` | `tools/scan_rules.py` | `mihomo/scan_rules.py` |
| 控制 API 客户端库 | `tools/diagnose/mihomo_api.py` | `mihomo/mihomo_api.py` |
| 实时日志 | `tools/diagnose/mihomo_log.py` | `mihomo/mihomo_log.py` |
| 增量抓日志到文件 | `tools/diagnose/capture_live.py` | `mihomo/capture_live.py` |
| 策略组 / 节点延迟 | `tools/latency/latency_probe.py` | `mihomo/latency_probe.py` |
| QQ 图片 CDN 连通性 | `tools/diagnose/qq_cdn_probe.py` | `cdn/qq_cdn_probe.py` |
| DNS 通道判定 | `tools/diagnose/qq_dns_path.py` | `cdn/qq_dns_path.py` |
| 域名归类（cn 集内外） | `tools/diagnose/qq_domain_classify.py` | `cdn/qq_domain_classify.py` |
| 规则命中观测 | `tools/diagnose/qq_rule_probe.py` | `cdn/qq_rule_probe.py` |
| QUIC 能力探测 | `tools/diagnose/quic_probe.py` | `cdn/quic_probe.py` |
| 早期探测残留（死代码） | `tools/latency/archive/**` | **不迁** —— 留在本仓归档位 |

### 6.3 迁出时做了什么（通用化）

**脚本逻辑未改**，只改「值从哪来」：

| 类别 | 处理 |
|---|---|
| 策略组名 / 节点名（`🤖 AI接口`、`🇮🇳 印度-优化` 之类 —— 机场的） | 改为**环境变量**，默认值用通用占位符（`AI_GROUP` / `NODE_A` / `DIRECT_GROUP`） |
| 控制 API 地址 | 保留 `MIHOMO_API` / `MIHOMO_HOST` / `MIHOMO_PORT` 环境变量；默认值从设备专属地址改为 `http://127.0.0.1:9999` |
| 控制台 secret | 保留 `MIHOMO_SECRET` 环境变量，**缺失即报错**，源码里仍无明文 |
| 套接字地址族 | 原来写死 `AF_INET6`；改为按主机字面量自动选 IPv4 / IPv6（否则默认的 `127.0.0.1` 连不上） |
| 报错文案里的本仓路径 | 「见 docs/SECRETS.md」等本仓专属引用改为通用措辞 |

### 6.4 许可与传播

- 迁出的脚本是**本仓自研**，迁到工具箱仓后按工具箱仓的许可（MIT）分发 ——
  本仓的 GPL-3.0 **不覆盖**它们，也**不因此**传染到工具箱仓。
- 反向也成立：工具箱仓是**公开**仓，**不得**引入本仓的敏感数据
  （订阅原文、节点 UUID、路由器口令）。
- 本仓 `config/`、`firewall/` 里的内容**一律不进**工具箱仓。
- 工具箱仓的脚本里**不得**出现本仓的策略组名、节点名与设备地址 ——
  那些是订阅相关的示例值。

---
