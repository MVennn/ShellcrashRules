# 更新日志

> **一句话**：本仓改了什么、为什么改、什么时候改 —— 按版本倒序；每条按对象单列一行，不打包成「代码整理」。

版本命名遵循三段式进位：**有功能更新进次版本（+0.1.0），没有就进补丁版本（+0.0.1）**。
规则正本见 [docs/VERSIONING.md](docs/VERSIONING.md)。
本仓是配置与脚本仓库，没有构建产物；版本号只在本文档头部维护，
发版 tag 与 Release 说明文件名都用它（格式见 [docs/release-notes/README.md](docs/release-notes/README.md)）。

---

## [未发布] — 2026-10-22

### 配置

- 调整 `config/yamls/proxies.example.yaml` —— 说明当前设备不再维护手工节点（节点全部来自订阅 + `sub-sync.sh` 自动补齐），模板只用于额外加备用入口；`cp` 重建时提醒保留 SUB-SYNC 块
- 调整 `config/yamls/proxies.example.yaml` —— 明确设备上的 `proxies.yaml` 有 `SUB-SYNC` / `PUBLIC-NODES` 两个自动块，**禁止整文件覆盖**（2026-10-22 曾因整文件部署冲掉 4 个公开节点）

### 设备侧（不入库）

- 删除 `yamls/proxies.yaml` 里的 `印度-备用m2` / `印度-备用ct2` —— 机场已不再发布这两个入口，且它们硬编码了共享 UUID，机场换凭据时会静默失效；两者都不在 guardian 候选与自动选路路径上，删除后 `proxies` 34 → 32
- 恢复并重跑公开节点 —— 整文件部署冲掉的 `PUBLIC-NODES` 块已从 `.bak-hy2-20261022` 恢复，随后跑 `tools/public-nodes/screen.py` 换新：384 条原始 → 测 55 条 → 存活 12 → 保留 8 条

### 规则

- 新增 Google 广告/追踪 carve-out —— `doubleclick.net` / `googlesyndication.com` / `googleadservices.com` / `google-analytics.com` / `googleadsserving.cn` / `ads.google.com` / `adservice.google.com` / `pagead.google.com` / `pagead.l.google.com` / `pagead-tpc.l.google.com` / `mobileads.google.com` / `afd.l.google.com` / `badad.googleplex.com` / `csi.gstatic.com` / `collector.githubapp.com` / `app-measurement.com` 改回 `🛑 广告拦截`：此前被自定义 `DOMAIN-KEYWORD,google` / `DOMAIN-SUFFIX,google.com` 整段遮蔽，实测走 `🤖 干净出口` 并真实下载 59–63 KB；`doubleclick.net` 同时挡住 `googleads.*` 子域
- 调整 `googletagmanager.com` / `googletagservices.com` —— 从 `🤖 干净出口` 改到 `🚀 节点选择`，共享标签管理器不再与 Google 账号流量共用出口
- 调整 AI 列表共享 SaaS 域 —— `envato.com` / `envato-static.com` / `envatousercontent.com` / `themeforest.net` / `liveperson.net` / `lpsnmedia.net` / `browser-intake-datadoghq.com` 从 `🤖 人工智能` 改到 `🚀 节点选择`：上游 geosite 误收，素材市场/客服聊天/RUM 不应占用 AI 出口

### 脚本

- 调整 `config/generators/ai-rules-update.sh` —— 顶部加入共享 SaaS 覆盖；A 段加入 Google 广告 carve-out；生成后逐条校验 carve-out 与共享 SaaS 覆盖存在，防止每周更新被冲掉
- 调整 `config/ai-api-check.sh` —— 新增第 18 段：逐条校验广告 carve-out / 共享 SaaS 覆盖存在，并断言 `doubleclick.net` 排在 `DOMAIN-SUFFIX,google.com` / `DOMAIN-KEYWORD,google` 之前
- 调整 `config/ai-api-check.sh` —— 第 14/15 段干净出口期望从「印度」改为「HY2/印度/台湾-优化3」，与 guardian 的 HY2 候选对齐，消除重启后的两条误报 WARN
- 调整 `config/generated/rules.yaml` —— 由路由器重生成（323 条，+17）

### 文档

- 调整 `docs/RULE-AUDIT.md` —— 追加 2026-10-22 广告 carve-out 与 AI 共享 SaaS 清理的审计结论、实测证据与规则清单
- 调整 `docs/PITFALLS.md` —— 新增第 23 条：宽泛 Google 规则遮蔽模板广告 REJECT；补目录缺失的第 22 条与锚点
- 调整 `docs/TROUBLESHOOTING.md` —— 规则审计一节补「广告域走代理」的判据与 `ai-api-check.sh` 第 18 段入口

### 部署验证（2026-10-22）

- 备份：`/etc/ShellCrash/ai-rules-update.sh.bak-adcarve-20261022`、`/etc/ShellCrash/ai-api-check.sh.bak-adcarve-20261022`、`/etc/ShellCrash/yamls/rules.yaml.bak-adcarve-20261022`
- 重生成：323 条规则；运行配置 4,154 条；`RULE-SET,cn` 在 #3227，仍在 ProxyMedia 之前
- 实测：`pagead2.googlesyndication.com` / `www.google-analytics.com` / `googleads.g.doubleclick.net` / `collector.githubapp.com` / `csi.gstatic.com` / `app-measurement.com` 经 `127.0.0.1:7890` 全部 exit=35（REJECT），此前为 200 并下载 59–63 KB
- 实测：`www.google.com` / `github.com` / `dl.google.com` / `chatgpt.com` 仍 exit=0；`googletagmanager.com` / `googletagservices.com` / `liveperson.net` 的 chains 为 `香港WAP → ♻️ 自动选择 → 🚀 节点选择`
- `ai-api-check.sh` 全 18 段通过（exit 0）；CrashCore RSS 53 MB

---

## [0.2.1] — 2026-10-22

把节点同步从「只补 hysteria2」泛化为「转换后缺什么补什么」，并修掉几个会反噬的边界。

### 脚本

- 调整 `config/starts/sub-sync.sh` —— 由 `hy2-sync.sh` 重命名并泛化：拿原始订阅与转换后的配置逐节点比对，只补「转换后没有的」；转换器将来支持某类节点时块会自动变空，不会与订阅重名
- 修复 `config/starts/sub-sync.sh` —— 策略组也是 `- { name: X, type: select, proxies: [...] }` 形状且列表里含 HY2 名字，必须用 `server:` 过滤，否则整组会被当成节点写进 proxies
- 新增 `config/starts/sub-sync.sh` —— 基准少于 10 个节点或待补超过 20 个时保留旧块，避免解析异常把订阅节点整批重复写入
- 调整 `config/starts/clash_modify.sh` —— 调用点改为 `sub-sync.sh`
- 调整 `config/yamls/proxy-groups.yaml` —— filter 追加 `HY2`：`日本JP-HY2` / `韩国KR-HY2` 之前根本不在组里，guardian 的候选有一半是空的
- 调整 `config/yamls/proxies.example.yaml` —— 说明改为 SUB-SYNC 块

### 部署验证（2026-10-22）

- 备份：`/etc/ShellCrash/starts/clash_modify.sh.bak-subsync-20261022`、`/etc/ShellCrash/yamls/proxy-groups.yaml.bak-subsync-20261022`
- 真实基准 28 个、待补 4 个；模拟「转换器已支持 HY2」时块变 0 个，恢复后回到 4 个
- 组内成员：印度×3、日本JP-HY2、韩国KR-HY2、新加坡×4、台湾-优化3（香港HK-HY2 被 exclude-filter 挡掉）
- `cc='SG'`；`gemini.google.com/app` 200 / 0.29s；可用内存 57MB

---

## [0.2.0] — 2026-10-22

新增订阅刷新后的 Hysteria2 节点自动同步；Gemini 干净出口从 vmess 池改到 HY2 池。

### 规则

- 新增 `DOMAIN-SUFFIX,z.ai,🎯 全球直连` —— ZCode 账号/项目 Token API 不再落到默认代理的香港出口；路由器直连实测 0.34s，原路径 project token 15s 超时
- 新增 `DOMAIN-SUFFIX,bigmodel.cn,🎯 全球直连` —— 与 Z.ai 账号相关的国内端点保持直连

### 脚本

- 新增 `config/starts/hy2-sync.sh` —— 生成配置前用 UA `clash.meta` 拉机场**原始**订阅，把 hysteria2 节点重写进 `yamls/proxies.yaml` 的 `# >>> HY2-AUTO` 块；6 小时节流，拉取失败或抽到 0 个都保留旧块、不阻断构建
- 调整 `config/starts/clash_modify.sh` —— `modify_yaml()` 开头调用 `hy2-sync.sh`，start 与 hotupdate 两条路径都覆盖

### 配置

- 调整 `config/yamls/proxy-groups.yaml` —— `🤖 AI网页` / `🤖 干净出口` 的 filter 从 `(印度|India|IN|台湾-优化3)` 放宽为 `(印度|India|IN|台湾-优化3|新加坡)`
- 调整 `config/yamls/proxies.example.yaml` —— 说明 HY2 节点由 `hy2-sync.sh` 自动同步，不需要手填

### 生成器

- 调整 `config/generators/ai-rules-update.sh` —— 顶部覆盖段加入上述两条，并在生成后校验；`config/generated/rules.yaml` 已用路由器生成物同步（306 条）
- 调整 `docs/RULE-AUDIT.md` —— 记录本次 +2 条与原因；审计表 `00_custom` 201 为 2026-10-19 旧快照

### 根因：HY2 池被两层静默隐藏

- 机场按**精确 UA** 给节点集：`clash.meta` 返回 50 条含 4 个 hysteria2；`clash.meta/mihomo`（ShellCrash 转换器实际传的）只回 46 条且 0 个 HY2
- 订阅转换器 `url.v1.mk` 的 `target=clash` 不认 hysteria2，整类丢弃且不报错；`target=mihomo` 被该服务拒绝（`Invalid target!`）
- 机场把「剩余流量 / 套餐到期 / 过滤掉N条线路」三个占位节点也定义成 `type: hysteria2`，同步时必须按名字排除
- 后果：vmess 池 5 个候选（含手机同款「新加坡-优化3」）全部 `cc=CN`，HY2 池 4 个全部 `cc=SG` —— 唯一能用的那批恰好被藏掉了

### 部署验证（2026-10-22）

- 备份：`/root/backup/pre-zai-20261022-020452`、`/etc/ShellCrash/yamls/proxies.yaml.bak-auto-20261022`
- 生成器：306 条；`z.ai` / `bigmodel.cn` 在第 21–22 行
- `hotupdate`：成功；`/tmp/ShellCrash/config.yaml` 第 500–501 行命中 `🎯 全球直连`
- `ai-api-check.sh`：17 段全过；1 个既有 WARN（`🤖 AI网页` 出口 = 新加坡-优化3，与本次无关）
- HY2 同步：`hy2=4`、`proxies=34`；删掉节流戳后重跑 hotupdate，节点与选择均保住
- 出口判定：`var cc='SG'`；`gemini.google.com/app` 200 / 0.34s；可用内存 57MB

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
