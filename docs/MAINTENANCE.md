# 配置维护与清理

> **一句话**：订阅更新后怎么校验、改坏了怎么退、生成物怎么标、备份怎么留 ——
> 以及一条纪律：**改完即删**（光清理不改变斜率）。

适用范围：本仓库（`ShellcrashRules`）及其在路由器上的**对应部署物**
（`/etc/ShellCrash/yamls/`、`/etc/ShellCrash/*.sh`、`/etc/*.nft`）。
不涉及路由器系统运维本身（`rc.local`、守护进程、恢复脚本 —— 那些在 `AX3000TOpenwrt` 仓）。

---

## 1. 触发语与术语

| 说法 | 含义 | 对应本文 |
|---|---|---|
| 做一次维护 | 跑完 §2 的校验链 + §6 的纪律检查 | §2 / §6 |
| 订阅更新了 | 跑完 §2，把结果写进仓库根 [CHANGELOG.md](../CHANGELOG.md) | §2 |
| 改回退 | 按 §3 回退某一批改动 | §3 |
| 清一下 | 只做 §4 标注 + §5 备份整理，**不改行为** | §4 / §5 |

---

## 2. 订阅更新后的校验（必跑）

订阅一变，配置就变；**不变的是「哪些地方会被悄悄冲掉」**。
下面这份清单按「冲掉了会怎样」排序，**从上往下跑**，前一条不过就别往下走。

### 2.1 顺序

```bash
# ① 生成器自己跑一遍（cron 每周也会跑，但手动跑能马上看到错误）
ssh root@10.0.0.1 'sh /etc/ShellCrash/ai-rules-update.sh'
#    失败 = 什么都不该改（脚本设计上不会写半成品）→ 停在这里，不要 hotupdate

# ② 自检 18 段（最重要的一条命令）
ssh root@10.0.0.1 'sh /etc/ShellCrash/ai-api-check.sh'
#    退出码 0 = 全过；1 = 有失败项
#    注意：部分段带**自动修复**（改 log-level、sed 修 task.sh 路径、重载 nft 表）

# ③ 重启使配置生效（start_old=ON 时只能用这个）
ssh root@10.0.0.1 '/etc/ShellCrash/start.sh start'

# ④ 再跑一次自检（重启可能暴露新的问题，比如钩子没挂上）
ssh root@10.0.0.1 'sh /etc/ShellCrash/ai-api-check.sh'

# ⑤ 离线规则回归（PC 侧；审计工具在 OpenwrtOpsToolkit 仓）
scp root@10.0.0.1:/tmp/ShellCrash/config.yaml ./config.yaml
ssh root@10.0.0.1 'curl -s http://127.0.0.1:9999/proxies' > proxies.json
python mihomo/rule_audit.py config.yaml proxies.json third-party/ACL4SSR/Clash REPORT.md
#    基线：139 个代表域名 0 异常；剩余 13 条 severe 全是有意覆盖
#    工具在 OpenwrtOpsToolkit 仓；策略组名用 AUDIT_* 环境变量对上本设备的组名
```

> 每条命令**单独怎么跑、要传哪些参数**见 [TOOLS.md](TOOLS.md)；
> 本节只管**顺序与判据**（前一条不过就别往下走）。

### 2.2 自检覆盖了什么（为什么它是唯一必跑的一条）

`ai-api-check.sh` 的 18 段，按顺序：

1. 策略组状态 · 2. 组到 opencode.ai 的延迟 · 3. opencode.ai 可达性 ·
4. 三种协议最小 token 测试 · 5. 分组/成员/节点排序钩子 + 伪节点过滤 · 6. hotupdate 重载路径 ·
7. Chrome/Google 下载修复（fake-ip 过滤 + quicguard 表）· 8. CN 直连中间层（rules-mid）·
9. 境外 QUIC 拦截 + TLS 重新解析 · 10. Google 家族统一出口 ·
11. 夜间加固项（cn_ip 剔除 / sniffer 跳过 CDN / 组出口）· 12. 规则文件完整性（空组名 / 原子写）·
13. IPv6 fake-IP 旁路防护 · 14. 干净出口组 · 15. 出口组与守护进程 · 16. 全局 QUIC 阻断 ·
17. 高带宽直连（Google 下载 / Chrome 更新 / JetBrains / hf-mirror / 国内 CDN 直连，省机场流量）·
18. 广告/追踪 carve-out（广告 REJECT 必须在 google.com / google 关键词之前）

**任何一段 FAIL 都必须处理完再往下走** —— 这些段覆盖的正是「更新后悄悄坏掉」的部位。

### 2.3 校验结果往哪写

写进仓库根 [CHANGELOG.md](../CHANGELOG.md) 的对应版本段：

- 日期与主题
- 订阅更新前后的关键差异（规则条数、策略组成员、出口 IP）
- 18 段自检的结果（过 / 不过 + 失败项）
- 做了什么修复
- 状态

### 2.4 变更纪律（2026-10-22 事故后）

三条硬规矩，违反任何一条都可能整网断流：

1. **规则级审计/去重只在 PC 上跑** —— 先把 `config.yaml` scp 下来，对副本跑
   `config/archive/rules-dedup.sh`、`rule_audit.py` 等；**禁止在路由器上跑 O(N²) 两两匹配**。
   2026-10-22 实测：4,154 条规则上跑 `rules-dedup.sh --check`，CPU/内存被拖垮，整网断流。
2. **同一时间只允许一个 `start.sh start`** —— 手动重启前先 `pidof CrashCore`；
   重启期间暂停 `guardian.sh`、`start_legacy_wd.sh`、`bulk-guard.sh` 三条 cron。
   两个启动并发会同时写 `/tmp/ShellCrash/config.yaml`，`rules-cnip.sh` 会因行数校验失败中止，
   配置不生效、CrashCore 起不来；`bulk-guard` 还会按测试批次的临时节点编号钉点。
3. **`init.d/shellcrash` 必须保持 disabled** —— `start_old=ON` 下 procd 与 legacy 各拉一个实例；
   双实例白占 ~50 MB，并放大 OOM。`post-sc-update.sh` 已改为自动 disable。

> 事故经过与恢复命令见 [PITFALLS.md](PITFALLS.md) §24/§25 与 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) §9。

### 2.5 新增代理组 / 节点的排序

**排序正本**是 [ARCHITECTURE.md](ARCHITECTURE.md) 的「代理组排序规则（新增组必须遵守）」。
这里只列操作顺序，避免在维护时漏掉 `order[]`：

1. 先在 `config/yamls/proxy-groups.yaml` 定义组；需要挂进父组就写 `#父组`。
2. 在 `config/hooks/reorder-groups.sh` 的**组顺序** `order[]` 按分段插入。
   漏加不会报错，但组会掉到面板最后。
3. 需要出现在 `🚀 节点选择` 的组，再在**成员顺序** `order[]` 对应段插入；
   内部子组（如 `𝕏 媒体-HY2`）不要加。
4. 节点需要排序的组，加到节点排序 pass 的目标列表；新地区补 `rank()`。
5. 用配置副本验证三处顺序（组 / 主选择器成员 / 节点），再部署；
   重启前暂停 `guardian.sh`、`start_legacy_wd.sh`、`bulk-guard.sh` 三条 cron。

**不要**依赖 `proxy-groups.yaml` 的文件顺序或订阅原始顺序；这两者都不决定面板顺序。

---

## 3. yamls 改动的回退方式

### 3.1 先备份，再改

**任何一次改 `config/yamls/*.yaml` 之前**，先在路由器上备份：

```bash
TS=$(date '+%Y%m%d-%H%M%S')
ssh root@10.0.0.1 "mkdir -p /root/backup/pre-yamls-$TS && \
  cp -a /etc/ShellCrash/yamls /root/backup/pre-yamls-$TS/"
```

### 3.2 回退方式（按改动对象选）

| 改了什么 | 怎么退 |
|---|---|
| `config/yamls/user.yaml` | 从备份目录拷回；或直接删掉文件 → 回到 ShellCrash 内置 `set.yaml` |
| `config/yamls/proxy-groups.yaml` | 拷回；或删文件 → 自定义组消失、回到模板组（**会连带丢掉 AI 分组，记得一起回退规则**） |
| `config/yamls/proxies.yaml` | 拷回；或删文件 → 备用入口消失（干净出口少两条冗余）。**该文件含节点凭据、不入库**，模板见 `proxies.example.yaml`（见 [SECRETS.md](SECRETS.md)） |
| `config/generated/rules.yaml` | **不要手改回退** —— 重跑生成器（`ai-rules-update.sh`）即可回到上游内容；但如果你改的是生成器，回退生成器文件后重跑 |
| `config/hooks/*.sh` | 删文件 → 钩子失效（`clash_modify.sh` 里有 `[ -x ]` 判断，不存在就跳过）。**注意**：删 `reorder-groups.sh` 会退回「同名组重复 → 拒载回退」的老坑；删 `rules-cnip.sh` 会保留 13k 内联 IP 规则（功能可用、内存略高）。`rules-dedup.sh` 已归档到 `config/archive/`，**不部署** |
| `config/starts/*.sh` | 从 `/etc/ShellCrash/local-patches/` 恢复；上游原版存为 `starts/*.upstream.*` |
| `firewall/tables/*.nft` | `nft delete table inet <表名>` 立即生效；文件层回退 = 删文件 + 重载 `rc.local` 那几行（`AX3000TOpenwrt` 仓） |
| `config/ai-api-check.sh` | 拷回（只读脚本，删掉即不巡检） |

### 3.3 回退后必做

```bash
ssh root@10.0.0.1 '/etc/ShellCrash/start.sh start'
ssh root@10.0.0.1 'sh /etc/ShellCrash/ai-api-check.sh'
```

**回退不是「撤销一次改动」，是「恢复到一个已知能跑的状态」** ——
所以回退完必须重新验一遍，否则你只是换了个坏法。

---

## 4. `config/generated/` 的标注约定

`config/generated/` 放的是**生成物**，不是编辑入口。

| 约定 | 说明 |
|---|---|
| **目录名即语义** | 放在 `generated/` 下的文件，**一律由某个 `generators/` 脚本产生**，不手工维护 |
| **文件头必须自证** | 生成物第一行写「由谁生成」，第二行写「更新时间」。本仓的 `config/generated/rules.yaml` 就是这个格式：<br>`# AI 服务分流规则 — 由 MetaCubeX/meta-rules-dat geosite category-ai-chat-!cn 生成`<br>`# 更新于 2026-10-20 11:30:21` |
| **改它 = 改生成器** | 要加规则 → 改 `config/generators/ai-rules-update.sh` → 重跑生成器 → 跑 `ai-api-check.sh` |
| **生成物入库，缓存不入库** | 生成物**进**版本库（离线也要能看到「当前生效的规则长什么样」）；中间产物（`/tmp/ai-rules-$$.yaml`）**不进** |
| **生成器必须幂等 + 失败不写半成品** | 下载内容必须校验通过才落盘；写文件用原子写（临时文件 → 校验 → `mv`） |

**新增生成物时的动作**：
① 放进 `config/generated/`；② 在生成器里加「写前校验 + 原子写」；
③ 在 `config/ai-api-check.sh` 里加一段巡检（文件在、内容含关键标记）；
④ 在 [docs/ARCHITECTURE.md](ARCHITECTURE.md) §1.3 补一行说明。

---

## 5. 备份命名约定与保留策略

### 5.1 命名

路由器侧统一：

```
/root/backup/pre-<主题>-<YYYYMMDD-HHMMSS>/
```

- `<主题>` 用短横线小写短语：`yamls` / `quic-sniff` / `fcm-doq` / `gemini-v2` / `rule-reorg`。
- 时间戳取**动手那一刻**，不是任务开始时间。
- 目录里放**改动前的原文件**（不是改动后的），必要时放一份 `NOTES.md` 写「为什么备份、改了什么」。

历史实例：`pre-rule-reorg/`、`pre-quic-sniff-20261020-004439/`、
`pre-fcm-doq-20261020-011522/`、`pre-gemini-v2-20261020-011921/`。

### 5.2 保留

| 类别 | 保留 |
|---|---|
| 最近一次改动 | 必留 |
| 最近 5 次 | 留 |
| 里程碑（每次大重构 / 每次换内核 / 每次换订阅源） | 单独留一份，**不受 5 次限制** |
| 其它 | 可删 |

> 路由器闪存有限（overlay 实测 58 MB / 已用 65%），备份别无限堆。
> 删之前先确认：那份备份对应的改动**已经稳定运行并写进了本仓**。

### 5.3 本仓内的清理

| 对象 | 能不能删 | 说明 |
|---|---|---|
| `config/archive/**` | **不能** | 归档件，保留备查（`geo-test.sh` 自述「临时诊断」，但它记录了当时的判断） |
| `tools/latency/archive/**` | **不能** | 同上 |
| `__pycache__/`、`*.pyc` | 能 | 已进 [.gitignore](../.gitignore) |
| 本地临时产物（`config.yaml` / `proxies.json` / `REPORT.md` 的临时拷贝） | 能 | 审计的输入，不是交付物 |
| `.codegraph/` | 能 | 本地索引，各人自建 |

---

## 6. 改完即删（光清理不改变斜率）

**这条是本篇的纪律部分。**

### 6.1 规则

**修掉一个根因的同时，立刻删掉当初为它加的绕过物、临时物、兼容分支。**

- 绕过物留着 → 下一个人会以为「本来就需要它」，于是不敢删真正的根因；
- 绕过物和根因修复同时在 → 出问题时**不知道是哪一套在起作用**；
- 绕过物越积越多 → 配置越来越难读、越来越不敢动。

**同一批次里必须列出三样东西**：

1. 这次修的根因是什么；
2. 因此**可以删**的东西（文件 / 规则行 / 兼容分支 / 巡检段 / 文档段落）；
3. 这次**不动**的东西（以及为什么不动 —— 例如「降级到非印度节点会让 Google 直接报不支持此国家」）。

### 6.2 「光清理不改变斜率」

**只做清理（删死文件、删失效规则、删过期文档），系统不会变好** ——
它只是让斜率**不再变坏**。真正的改进来自「改完即删」：
每修一次根因，旧机制随之消失，复杂度曲线才变陡。

所以：

- **清理**是卫生，不是成绩 —— 不要把「删了多少文件」当成进展汇报；
- **改完即删**才是改进 —— 汇报进展时报「修好什么 + 因此删掉了什么」。

### 6.3 执行

每次改动在 [CHANGELOG.md](../CHANGELOG.md) 的对应版本段里加一段：

```
### 本次作废
- <文件/规则/巡检段> —— 因为 <根因> 已修，保留会造成 <具体后果>
```

写不出来就说明**这次修复不彻底**，或者**还有旧机制没找到** —— 两种都得回头查。

---

## 7. 一次完整维护的收尾清单

- [ ] §2 的五步全跑过，`ai-api-check.sh` 退出码 0
- [ ] `rule_audit.py`（`OpenwrtOpsToolkit` 仓）回归：代表域名 0 异常，severe 只剩有意覆盖
- [ ] 备份已按 §5 命名并放到 `/root/backup/`
- [ ] 「本次作废」清单已写进 [CHANGELOG.md](../CHANGELOG.md)
- [ ] 改动了 `config/` 就同步了本仓对应文件（**设备上改了、仓里没改 = 下次更新就丢**）
- [ ] 改了规则/分组/端口就同步了 [docs/ARCHITECTURE.md](ARCHITECTURE.md) §4 关键参数表
- [ ] 踩到新坑就往 [docs/PITFALLS.md](PITFALLS.md) 加一条
- [ ] 发版就按 [VERSIONING.md](VERSIONING.md) §1 定版本号，再写 [CHANGELOG.md](../CHANGELOG.md) + `docs/release-notes/<版本>.md`（不带 `v`；`v` 只属于发版 tag）

---

## 8. 相关文档

| 要查什么 | 去哪 |
|---|---|
| 发版时版本号动哪一位（版本晋升规则正本） | [VERSIONING.md](VERSIONING.md) §1–§2 |
| Release 说明怎么写 | [release-notes/README.md](release-notes/README.md) |
| 凭据（mihomo secret / 节点 uuid）分别躺在哪 | [SECRETS.md](SECRETS.md) |
| 订阅 / 合并链路与文件所有权 | [ARCHITECTURE.md](ARCHITECTURE.md) §1、§3 |
| 踩坑的根因与根治 | [PITFALLS.md](PITFALLS.md) |
