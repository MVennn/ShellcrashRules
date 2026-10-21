# 更新日志

> **一句话**：本仓改了什么、为什么改、什么时候改 —— 按版本倒序；每条按对象单列一行，不打包成「代码整理」。

版本命名遵循三段式进位：**有功能更新进次版本（+0.1.0），没有就进补丁版本（+0.0.1）**。
规则正本见 [docs/VERSIONING.md](docs/VERSIONING.md)。
本仓是配置与脚本仓库，没有构建产物；版本号只在本文档头部维护，
发版 tag 与 Release 说明文件名都用它（格式见 [docs/release-notes/README.md](docs/release-notes/README.md)）。

---

## [未发布] — 2026-10-22

### 规则

- 新增 `DOMAIN-SUFFIX,z.ai,🎯 全球直连` —— ZCode 账号/项目 Token API 不再落到默认代理的香港出口；路由器直连实测 0.34s，原路径 project token 15s 超时
- 新增 `DOMAIN-SUFFIX,bigmodel.cn,🎯 全球直连` —— 与 Z.ai 账号相关的国内端点保持直连

### 生成器

- 调整 `config/generators/ai-rules-update.sh` —— 顶部覆盖段加入上述两条，并在生成后校验；`config/generated/rules.yaml` 已用路由器生成物同步（306 条）
- 调整 `docs/RULE-AUDIT.md` —— 记录本次 +2 条与原因；审计表 `00_custom` 201 为 2026-10-19 旧快照

### 部署验证（2026-10-22）

- 备份：`/root/backup/pre-zai-20261022-020452`
- 生成器：306 条；`z.ai` / `bigmodel.cn` 在第 21–22 行
- `hotupdate`：成功；`/tmp/ShellCrash/config.yaml` 第 500–501 行命中 `🎯 全球直连`
- `ai-api-check.sh`：17 段全过；1 个既有 WARN（`🤖 AI网页` 出口 = 新加坡-优化3，与本次无关）

> 发版时按功能更新进位到 `0.2.0`（新增使用者可感知的分流能力）。

---

## [0.1.1] — 2026-10-22

与设备上实际运行的看门狗对齐。设备侧在公开化之后补了内存闸门，
仓库仍停留在旧快照；本次收回仓库。

### 脚本

- 修复 `config/starts/start_legacy_wd.sh` —— 补上 `memgate` 内存闸门（内存不足时跳过本轮拉起，打断 OOM → 拉起 → 再 OOM 的循环）
- 修复 `config/starts/start_legacy_wd.sh` —— 陈旧锁判断从 `stat -c %Y` 改为 `date -r`，不再依赖设备上不支持的 `stat -c`

### 文档

- 修复 `docs/PITFALLS.md` —— 出口策略从「绝不降级到非印度节点」改为「台湾优先、印度兜底」，与 2026-10-21 的实测一致

---

## [0.1.0] — 2026-10-21

首次公开版。仓库从私有运维仓整理为可独立阅读、可复用的参考实现。

### 公开化

- 调整 仓库范围 —— 移除订阅原文、节点凭据、原始审计证据与内部进度台账；公开树只保留配置、规则、脚本、文档与门面资源
- 修复 隐私 —— 服务器域名、WS Host、IPv6 PD 前缀、出口 IP、本机路径全部改为占位符或示例值
- 修复 凭据 —— 仓库不保存节点 UUID、订阅 token 或控制 API secret；真实 `proxies.yaml` 由 `.gitignore` 排除
- 新增 密钥守卫 —— `tools/check-secrets.py` 扫描订阅链接、节点 URI、私钥块与 shadow 哈希，CI 强制执行
- 调整 忽略规则 —— `.gitignore` 排除 `proxies.yaml`、订阅原文、私钥与 `.work/`

### 配置

- 调整 `config/yamls/proxies.example.yaml` —— 真实服务器域名与 WS Host 改为 `<YOUR-NODE-SERVER>` / `<YOUR-WS-HOST>`，UUID 保持占位符
- 调整 `firewall/tables/*.nft` —— IPv6 来源集合改用 ULA / link-local；使用运营商 PD 时由部署者自行加入前缀
- 调整 `config/yamls/proxy-groups.yaml` —— 策略组名与节点名保留为示例，换订阅后按自己的名字改

### 文档

- 调整 根 README —— 面向使用者的门面：这是什么 / 环境要求 / 使用 / 目录 / 安全与隐私 / 反馈 / 免责声明 / 鸣谢 / 许可证
- 调整 `docs/SECRETS.md` —— 重写为公开版：只写读取方式、位置与轮换顺序
- 调整 `docs/UPSTREAM.md` —— 重写与 `OpenwrtOpsToolkit` 的边界，移除私有仓与证据库表述
- 调整 `docs/DEPLOY.md` / `docs/MAINTENANCE.md` / `docs/TOOLS.md` / `docs/TROUBLESHOOTING.md` —— 规则审计列表改用 `third-party/ACL4SSR/Clash`，移除证据路径
- 调整 `docs/DOC-RULES.md` / `docs/README.md` —— 索引与规则按公开树重建
- 调整 `docs/RULE-AUDIT.md` —— 保留审计结论，移除原始证据链接与内部路径
- 调整 `NOTICE` / `third-party/README.md` —— 移除证据库与私有仓表述

### CI

- 调整 CI —— 保留凭据守卫、Shell 语法与文档自检，新增密钥扫描
