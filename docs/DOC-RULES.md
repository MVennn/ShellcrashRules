# 文档规则

> **一句话**：docs/ 下的文档怎么分类、怎么互相引用、改动时连带改哪些 ——
> 本篇只管「怎么写、怎么保持一致」，不承载任何具体技术规则。

---

## 1. 分类与定位

docs/ 分四类（索引见 [README.md](README.md)）：

| 类别 | 收什么 | 现有成员 |
|---|---|---|
| 架构与配置 | 配置怎么长出来、运行时怎么跑、部署到哪 | ARCHITECTURE、DEPLOY |
| 规则与工具 | 规则审计结论、脚本与工具的用法 | RULE-AUDIT、TOOLS |
| 流程与规范 | 文档怎么写、配置怎么维护、坑与排障、版本怎么晋升、凭据放在哪 | DOC-RULES、MAINTENANCE、PITFALLS、TROUBLESHOOTING、SECRETS、VERSIONING、release-notes/README |
| 参考资料 | 审计结论、Release 说明、上游与许可证 | release-notes/、UPSTREAM、根 LICENSE、NOTICE、CHANGELOG、third-party/ |

每篇文档开头必须有一个 **「一句话」引言块**（`> **一句话**：…`），
让读者不用往下翻就知道这篇管什么。新文档没有它不算写完
（`tools/check-docs.py` 会拦；`docs/release-notes/` 下的单版本说明与根
[README.md](../README.md) 例外 —— 前者正文首行就是加粗总结，后者是门面）。

### 1.1 文件命名：全大写 + 连字符

docs/ 下的文档**一律 `ALL-CAPS-WITH-HYPHENS.md`**（如 `RULE-AUDIT.md`、
`DOC-RULES.md`、`UPSTREAM.md`）。不接受小写文档名（小写留给 `README.md` 这类
约定俗成的入口）、不接受中文文件名、不接受下划线或空格。

改名纪律：**改名用 `git mv`**（保住历史），然后**全仓 grep 旧文件名**，
把所有指向它的链接改成新位置 —— **禁止只改名不同步引用方**。
改完跑 `python tools/check-docs.py`（链接 / 锚点 / 引言块 / 孤儿四项）。

唯一的例外是 `docs/release-notes/` 下的单版本说明：文件名 = `versionName`
（如 `0.2.1.md`），**不带 `v`** —— `v` 前缀只属于发版 tag。

仓库根的文件各管一件事，**不在 docs/ 里重复**：

| 文件 | 管什么 |
|---|---|
| 根 [README.md](../README.md) | 门面：这是什么 / 环境要求 / 使用 / 反馈 / 免责声明 / 开源鸣谢 / 许可证（**不放文件清单与链路图**） |
| 根 [CHANGELOG.md](../CHANGELOG.md) | 变更记录（**版本号本身**在它的版本标题里；**进位规则不在这里**，见 [VERSIONING.md](VERSIONING.md)） |
| 根 [LICENSE](../LICENSE) | 许可证全文（GPL-3.0） |
| 根 [NOTICE](../NOTICE) | 第三方声明 |

## 2. 单一正本原则

**每条规则只在一篇文档里定义；其余位置只允许一句话概述 + 指向正本的链接。**
两处都写全文，迟早各改各的。

权威正本映射表：

| 规则 | 正本 |
|---|---|
| 配置生成链路（订阅 → 合并 → 钩子 → 加载） | [ARCHITECTURE.md](ARCHITECTURE.md) §1 |
| 运行期架构（mihomo / Redir / nft 三表 / flow offload） | [ARCHITECTURE.md](ARCHITECTURE.md) §2 |
| **文件所有权**（哪个仓拥有哪些文件、谁写谁加载） | [ARCHITECTURE.md](ARCHITECTURE.md) §3 |
| 关键参数（端口 / 组 / cron / 内核开关） | [ARCHITECTURE.md](ARCHITECTURE.md) §4 |
| 降级与失败模式（顶层 key 重复 → 静默回退） | [ARCHITECTURE.md](ARCHITECTURE.md) §5 |
| 踩坑的**根因与根治**（现象 → 根因 → 解法） | [PITFALLS.md](PITFALLS.md) |
| 排错**步骤与判据** | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| 配置维护与清理流程（含「改完即删」） | [MAINTENANCE.md](MAINTENANCE.md) |
| 文档规则（本篇） | [DOC-RULES.md](DOC-RULES.md) |
| Release 说明格式 | [release-notes/README.md](release-notes/README.md) |
| **版本晋升规则**（三段式进位 / 有没有功能更新怎么判） | [VERSIONING.md](VERSIONING.md) §1–§2 |
| **交付 / 发版规则**（版本号在哪维护 / 什么时候不动版本号 / 打 tag） | [VERSIONING.md](VERSIONING.md) §3、§5 + [release-notes/README.md](release-notes/README.md) |
| 凭据存放位置与取值方法 | [SECRETS.md](SECRETS.md) |
| **工具用法与参数**（自检 / 审计 / 控制面查询 / 延迟探测怎么跑） | [TOOLS.md](TOOLS.md) |
| 订阅更新后的**校验顺序与判据** | [MAINTENANCE.md](MAINTENANCE.md) §2 |
| Redir 透明代理的**实际覆盖范围**（只代理 TCP，UDP 直出） | [ARCHITECTURE.md](ARCHITECTURE.md) §2.2 |
| 许可证 | 仓库根 [LICENSE](../LICENSE)（GPL-3.0 全文） |
| 许可证**选型理由**与随仓副本的例外（CC BY-SA） | [UPSTREAM.md](UPSTREAM.md) §4 |
| 规则分类审计结论 | [RULE-AUDIT.md](RULE-AUDIT.md) |

### 禁止重复清单（本次建仓发现的反例，勿重蹈）

1. **坑在 PITFALLS 与 TROUBLESHOOTING 各写一遍全文** —— 同一现象两处展开，
   根因演进时必然只改一处。已收敛：**根因只在 PITFALLS**，
   TROUBLESHOOTING 只给「看什么 → 敲什么 → 看到什么算对」，
   末尾一句话链回 PITFALLS 的对应条目。
2. **配置链路在 README 与 ARCHITECTURE 各画一张流程图** —— 两张图会分叉。
   已收敛：**完整流程图只在 ARCHITECTURE**；门面 README 不画图、不列文件清单，
   只保留一段文字摘要 + 链接（部署映射在 [DEPLOY.md](DEPLOY.md)）。
3. **文件所有权在 README / ARCHITECTURE 各写一遍** —— 两处必然口径不一。
   已收敛：**所有权表只在 ARCHITECTURE**；README 只留「哪些不归本仓」一句话。
4. **版本规则在 CHANGELOG 头部与 release-notes/README 各写一遍** ——
   已收敛：**规则只在 [VERSIONING.md](VERSIONING.md)**；`CHANGELOG.md` 头部只留
   **当前版本号**，`release-notes/README.md` 只引用。
5. **凭据明文散落在脚本与模板里** —— 已收敛：**只写位置**的清单在
   [SECRETS.md](SECRETS.md)；脚本改为从环境变量读，模板里换成占位符。

## 3. 红线内容保护：规则细节逐字保留

[PITFALLS.md](PITFALLS.md) 与 [ARCHITECTURE.md](ARCHITECTURE.md) 里的
**域名、域名后缀、策略组名、规则动作名、端口号、IP 段与 CIDR、文件路径、脚本标记串**
（如 `CLEAN_EXIT_MARKER`、`QUIC_BLOCK_MARKER`、`FCM_DOQ_PORT_MARKER`、
`RULE-SET,cn,🎯 全球直连`、`203.208.32.0/19`、`2401:3800::/32`），
在文档合并或修订时**必须逐字保留，一个不删** —— 哪怕当前配置里暂时没用到
（那是下次上游更新后的排查依据）。重复叙述可以压缩，**事实、名字、数字不行**。

同理，[RULE-AUDIT.md](RULE-AUDIT.md) 里的规则条数、代表域名数、索引位置
（如 `RULE-SET,cn` 位于 #3158）属于**实测快照**，删改前先想清楚它是不是还在被引用。

## 4. 链接纪律

- 统一用**相对链接 + 锚点**（形如 `[标题](文档名.md#锚点)`，写时用半角括号），
  不用绝对路径、不用仓库外的绝对路径。
- **锚点必须真实存在**：标题里带中文、标点、序号时，锚点在不同渲染器上可能不一致 ——
  需要精确跳转的段落，正文里显式写 `<a id="xxx"></a>` 再接标题，链接指向该 id。
- **改动 / 删除 / 合并文档后必须双向点验**：
  - 出链：新文档里指向别处的链接目标还存在、锚点没变；
  - 入链：全仓搜旧文件名（grep），把指向它的链接改成新位置 ——
    **禁止只删文档不改引用方**。
- 判断某段「重复」是否该收敛时，先看它被谁引用；收敛后引用方必须同步改。
- 历史记录里的旧文件名（如 CHANGELOG 历史条目）可保留原样 ——
  那是当时的事实；但**正文中指向现役文档的链接**必须始终指向现役文档。

## 5. 变更触发矩阵

改了什么，就必须连带改什么：

| 变更 | 必须同步 |
|---|---|
| 新增 / 删除 / 改名策略组 | [config/yamls/proxy-groups.yaml](../config/yamls/proxy-groups.yaml)、[ARCHITECTURE.md](ARCHITECTURE.md) §4 关键参数表；若影响出口判定，[PITFALLS.md](PITFALLS.md) 对应条目 |
| 新增 / 修改规则 | [config/generators/ai-rules-update.sh](../config/generators/ai-rules-update.sh) → 重跑生成器更新 [config/generated/rules.yaml](../config/generated/rules.yaml)、[RULE-AUDIT.md](RULE-AUDIT.md) |
| 新增 / 修改 nft 表 | [firewall/tables/](../firewall/tables/)、[ARCHITECTURE.md](ARCHITECTURE.md) §2 运行期、[PITFALLS.md](PITFALLS.md) |
| 改合并链路或后处理钩子 | [config/hooks/](../config/hooks/)、[config/starts/](../config/starts/)、[ARCHITECTURE.md](ARCHITECTURE.md) §1 生成期 |
| 踩到新坑 | [PITFALLS.md](PITFALLS.md) 加一条（现象 / 根因 / 解法 + 日期）；若该现象需要命令级排查，同时在 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 补一条检索入口 |
| 排查流程变化 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| 配置维护 / 清理流程变化 | [MAINTENANCE.md](MAINTENANCE.md) |
| 工具用法 / 参数 / 脚本位置变化 | [TOOLS.md](TOOLS.md)（用法正本）、[MAINTENANCE.md](MAINTENANCE.md) §2（校验顺序） |
| 改 yaml 所有权或写入纪律 | [ARCHITECTURE.md](ARCHITECTURE.md) §3 |
| 改了凭据的存放位置或新增了凭据 | [SECRETS.md](SECRETS.md)（位置清单）、`.gitignore` 的排除项 |
| 改了版本晋升 / 发版规则 | [VERSIONING.md](VERSIONING.md)；仓库根 [CHANGELOG.md](../CHANGELOG.md)（版本号本身） |
| 改了许可证 | 仓库根 [LICENSE](../LICENSE)、[NOTICE](../NOTICE)、[UPSTREAM.md](UPSTREAM.md) §1.1 / §4、根 [README.md](../README.md) 的许可证段 |
| 改名文档 | `git mv` + 全仓 grep 旧文件名同步引用方（见 §1.1）；跑 `python tools/check-docs.py` |
| 发版 | 仓库根 [CHANGELOG.md](../CHANGELOG.md)、`docs/release-notes/<版本>.md`（不带 `v`，格式正本 [release-notes/README.md](release-notes/README.md)；版本号进位规则：[VERSIONING.md](VERSIONING.md)） |
| 内部重构 / 死代码 / 归档 | 说明里**必须按对象单列一行**（算「调整」，不许打包成「代码整理」） |
| 新增 / 删除文档 | [docs/README.md](README.md) 索引（见 §7） |
| 改文档规则 | 本篇 + [docs/README.md](README.md) 的「正本」标注 |

## 6. 体量预算与样例时效

- **单篇 ≤ 800 行。** 超了就按「正文档 + 踩坑史」拆：正文档留结论与约束，
  历史 / 根因分析移到 HISTORY 篇。
- **样例时效**：带日期与版本的实测结论（如「2026-10-20 实测 `RULE-SET,cn` 位于 #3158」）
  可容忍过时 —— 它们是历史记录；但**结构性计数类内容**
  （「共 N 个策略组」「规则共 N 条」「自检共 N 段」）必须随变更同步，
  不允许停留在旧版本状态。

## 7. 索引维护与孤儿零容忍

- [README.md](README.md) 是 docs/ 的唯一索引，**新增 / 删除 / 改名文档必须同步更新**。
- **孤儿文档零容忍**：任何新文档必须至少被一处既有文档引用（或进索引并有明确入口），
  否则等于没写。
- 索引里的「**正本**」标注是单一正本原则的可见面 —— 改标题、改归属时，
  索引与正文必须同时改。
