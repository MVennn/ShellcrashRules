# docs/ 索引

> **一句话**：这里只有索引与定位，不放正文 —— 每篇文档一句话说明「它管什么」，
> 规则本身按 [DOC-RULES.md](DOC-RULES.md) 的**单一正本原则**只在对应文档里定义全文。

文档分四类。每篇开头都有一个「一句话」引言块，先看它再决定要不要往下读。

> 本仓是脱敏后的公开参考实现：订阅原文、节点凭据与原始审计证据不随公开仓发布。

---

## 一、架构与配置

| 文档 | 一句话定位 |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | **配置生成链路正本**：订阅 → ShellCrash 合并 → 自定义钩子 → mihomo 加载；文件所有权与关键参数 |
| [DEPLOY.md](DEPLOY.md) | 部署映射：本地路径 → 路由器目标路径 → 被谁调用 → 回退方式；目录职责与上游边界 |

## 二、规则与工具

| 文档 | 一句话定位 |
|---|---|
| [RULE-AUDIT.md](RULE-AUDIT.md) | 规则分类审计的结论与整改方案（13,010 条规则的分类正确性） |
| [TOOLS.md](TOOLS.md) | 节点筛选、延迟探测、规则审计脚本的用法与参数 |

## 三、流程与规范

| 文档 | 一句话定位 |
|---|---|
| [DOC-RULES.md](DOC-RULES.md) | **文档规则正本**：分类与定位、单一正本映射表、禁止重复清单、链接纪律、变更触发矩阵、索引维护 |
| [MAINTENANCE.md](MAINTENANCE.md) | 维护与回退：校验链、备份约定、改动后必须同步的文件 |
| [PITFALLS.md](PITFALLS.md) | 踩坑总汇（**正本**）：Redir/UDP、QUIC、策略组重排、静默回退等机制级坑 |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | 排障手册：按「现象 → 排查步骤 → 原因 / 解法」组织，每节给可执行命令 |
| [SECRETS.md](SECRETS.md) | 凭据的**存放位置**、读取方式与轮换建议（不写明文值） |
| [VERSIONING.md](VERSIONING.md) | **版本晋升规则正本**：三段式进位、版本号在哪维护、什么时候不动版本号 |
| [release-notes/README.md](release-notes/README.md) | **Release 说明格式正本**：四动词、一行一条、按对象拆行、覆盖率红线、固定尾巴 |

## 四、参考资料

| 位置 | 一句话定位 |
|---|---|
| [release-notes/v0.2.0.md](release-notes/v0.2.0.md) | 本版 Release 说明（面向使用者：HY2 节点自动同步、z.ai 直连） |
| [release-notes/v0.1.1.md](release-notes/v0.1.1.md) | 上一版 Release 说明（面向使用者：看门狗内存闸门、出口策略口径） |
| [release-notes/v0.1.0.md](release-notes/v0.1.0.md) | 首版 Release 说明（面向使用者：你现在能拿到什么） |
| 仓库根 [CHANGELOG.md](../CHANGELOG.md) | 开发者记录：按对象拆行的变更清单（**版本号本身**在这里维护） |
| 仓库根 [NOTICE](../NOTICE) | 第三方声明：ShellCrash、mihomo / Clash.Meta、meta-rules-dat、OpenWrt 的来源与许可证 |
| 仓库根 [LICENSE](../LICENSE) | 许可证全文（**GPL-3.0** —— 本仓含 ShellCrash 的 GPL-3.0 派生件） |
| [UPSTREAM.md](UPSTREAM.md) | **上游来源与调研正本**：引用了哪些上游、为什么引用/不引用、随仓分发了哪些文件 |
| 仓库根 [third-party/](../third-party/README.md) | **随仓分发的上游文件**：每个子目录一份 `UPSTREAM.md`（来源 URL / 钉住的 commit / 许可 / 怎么用 / 怎么更新） |

---

> 新增 / 删除文档后**必须同步更新本索引**（规则见 [DOC-RULES.md](DOC-RULES.md)）；
> 新文档至少要被一处既有文档引用，不允许孤儿。
