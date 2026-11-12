# AGENTS —— 机器协议

> **一句话**：三条硬规矩 —— **三张 nft 表必须独立**、**改配置三处同改并试跑生成**、**订阅与节点真值不进仓**。
> 链路与部署顺序见 `docs/ARCHITECTURE.md`、`docs/DEPLOY.md`。

## 1. 防火墙层：三张表独立存在

- 三张独立 nft 表：QUIC 全局阻断、Google 国内边缘段重定向、Google 推送端口 + DNS 劫持。
- **原因**：ShellCrash 每次重启会重写它自己的整表，所以这三张不能并进去，否则一重启就没了。
- 改表在 `firewall/tables/` 里改，部署路径见 `docs/DEPLOY.md`；改完必须实测生效（`nft list ruleset` + 站点实测）。

## 2. 配置层：改一处要三处同改

- 配置长在 `config/`：`yamls/`（扩展点）、`generators/`、`hooks/`、`starts/`、`fakeip/`、`generated/`（产物）。
- 记忆中的教训：**改配置要三处同改，并按部署顺序生效**；只改一处 = 静默不生效。
- 生成期钩子中止等于**静默断网**：改 `config/hooks/` 后必须本地试跑生成，diff `config/generated/` 产物再上线。
- 订阅转换链路、合并顺序见 `docs/ARCHITECTURE.md`，不要凭印象重排。

## 3. 真值不外泄

- 订阅原文、节点 UUID、策略组实名、IPv6 前缀、服务器域名：一律 `<REDACTED-…>` / `<REPLACE-…>`。
- 真值配置走 gitignored 文件；`.work/private-evidence/`、`.work/public-nodes*/` 与 `.work/private-history.bundle`（私有完整历史镜像）不进库、不恢复进公开分支。
- 本仓 **GPL-3.0**：引入外部代码前确认许可证兼容，`third-party/` 原样保留。

## 4. 目录

- `config/` — 分流配置正本（见上）；`config/archive/` 是退役配置
- `firewall/` — 三张 nft 表
- `tools/` — `check-docs.py`、`check-secrets.py`、`check-vault-not-staged.py`、`latency/`、`public-nodes/`、`reference/`
- `docs/` — 架构、部署、规则审计、排障、踩坑、发版；`docs/release-notes/` 文件名 = 版本号（不带 `v`）
- `.work/` — 审计与筛选的中间产物（gitignored）

## 5. 验证

- 改文档跑 `python tools/check-docs.py`；改配置/脚本跑 `check-secrets.py` 与 `check-vault-not-staged.py`。
- 规则改动看 `docs/RULE-AUDIT.md` 的审计口径；站点行为实测结论在记忆 `infra-site-quirks`。
- 节点/出口结论别写死：机场节点会变，存活率只有 1.5–5%。

## 6. 边界

- 路由器系统层在 `AX3000TOpenwrt`；通用工具与 mihomo 控制面诊断在 `OpenwrtOpsToolkit`；控制台在 `OpenwrtConsole`；网关侧在 `ModelBus`（原 ZcodeAIModels）。
- `third-party/` 是 vendored 上游，一个字节都不动。
