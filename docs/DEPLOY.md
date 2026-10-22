# 部署映射

> **一句话**：本仓每个文件「本地路径 → 路由器目标路径 → 谁调我 → 怎么退回去」的正本，外加目录职责与本仓待补清单。

## 目录结构

```
ShellcrashRules/
├── README.md               门面
├── CHANGELOG.md            变更记录（追加式，含版本号）
├── NOTICE                  第三方声明
├── LICENSE                 GPL-3.0 许可证全文（整仓，含 ShellCrash 的 GPL-3.0 派生件）
├── config/                 ← 设备侧配置与脚本（ShellCrash 扩展点）
│   ├── yamls/              自定义策略组 / 节点 / 顶层参数
│   ├── generated/          生成物（rules.yaml）—— 勿手改
│   ├── generators/         规则生成器 + 每周自动更新
│   ├── hooks/              生成后处理（CN 中间层 / 组去重重排）
│   ├── starts/             打补丁的上游 starts/ 脚本
│   └── archive/            一次性脚本（不部署）
├── firewall/tables/        三张独立 nft 表（quicguard / googlecn / googleroute）
├── tools/                  节点筛选 / 延迟探测 / 文档自检与密钥守卫
├── third-party/            ← 随仓分发的上游开源代码副本（每个项目带 UPSTREAM.md 来源凭证）
│   ├── ShellCrash/         上游原版 starts/ + 规则模板（GPL-3.0）
│   └── ACL4SSR/            上游原版规则列表 + 模板（CC BY-SA 4.0）
├── docs/                   文档（唯一索引：docs/README.md）
└── assets/                 logo 与社交预览
```

> `config/yamls/proxies.yaml` 是**真实节点凭据文件**，已被 `.gitignore` 排除；
> 仓库里只有模板 `proxies.example.yaml`。

## 部署映射表

> 「谁调我」写的是**设备上**的调用方；本仓文件除特别说明外都**先推到路由器再执行**。

| 本地路径 | 路由器目标路径 | 谁调我 | 回退方式 |
|---|---|---|---|
| `config/yamls/user.yaml` | `/etc/ShellCrash/yamls/user.yaml` | `starts/clash_modify.sh`（merger_yaml） | 删文件 → 回到 ShellCrash 内置 `set.yaml` |
| `config/yamls/proxy-groups.yaml` | `/etc/ShellCrash/yamls/proxy-groups.yaml` | 同上 | 删文件 → 自定义组消失，回到模板组 |
| `config/yamls/proxies.yaml` | `/etc/ShellCrash/yamls/proxies.yaml` | 同上 | 删文件 → 备用入口消失 |
| `config/yamls/proxies.example.yaml` | **模板，不部署** | 人工：照它重建 `proxies.yaml` | 无需回退；uuid 写 `<REPLACE-VMESS-UUID>`，真实 `proxies.yaml` 已被 `.gitignore` 排除 |
| `config/generated/rules.yaml` | `/etc/ShellCrash/yamls/rules.yaml` | `ai-rules-update.sh` **生成**（勿手改） | 重跑生成器；或用备份文件覆盖 |
| `config/generators/ai-rules-update.sh` | `/etc/ShellCrash/ai-rules-update.sh` | cron `30 4 * * 0`（经 auto-update.sh） | 停 cron 行 + 恢复旧 `rules.yaml` |
| `config/generators/auto-update.sh` | `/etc/ShellCrash/auto-update.sh` | cron `30 4 * * 0` | 删 `/etc/crontabs/root` 对应行 |
| `config/hooks/rules-mid.sh` | `/etc/ShellCrash/rules-mid.sh` | `starts/clash_modify.sh`（merger_yaml 之后） | 删文件 → 钩子失效 → 配置里没有 CN 中间层 |
| `config/hooks/reorder-groups.sh` | `/etc/ShellCrash/reorder-groups.sh` | 同上 | 删文件 → 去重/重排失效（**会退回重复 key 拒载的老坑**） |
| `config/archive/rules-dedup.sh` | **不部署（离线工具）** | 人工：在 PC 上对 scp 下来的 config.yaml 副本跑 | **禁止在路由器上跑** —— O(N²) 扫描会拖垮 CPU/内存（2026-10-22 实测断网） |
| `config/starts/fw_nftables.sh` | `/etc/ShellCrash/starts/fw_nftables.sh` | ShellCrash 启动；`post-sc-update.sh` 恢复 | 从 `/etc/ShellCrash/local-patches/` 恢复；上游副本存为 `starts/*.upstream.*` |
| `config/starts/start_legacy_wd.sh` | `/etc/ShellCrash/starts/start_legacy_wd.sh` | cron 每分钟 | 同上（local-patches 恢复） |
| `config/starts/clash_modify.sh` | `/etc/ShellCrash/starts/clash_modify.sh` | ShellCrash 启动 / 订阅更新 | **本仓待补**（见下方「待补」） |
| `config/post-sc-update.sh` | `/etc/ShellCrash/post-sc-update.sh` | 人工（ShellCrash 官方脚本更新后） | 删 `local-patches/` 即不再恢复 |
| `config/ai-api-check.sh` | `/etc/ShellCrash/ai-api-check.sh` | 人工（订阅更新后必跑） | 只读为主；少数段带自动修复，删掉即不修 |
| `config/archive/geo-test.sh` | **不部署** | 无（一次性诊断，已归档） | 归档件，保留备查 |
| `firewall/tables/quicguard.nft` | `/etc/quicguard.nft` | `rc.local`（`AX3000TOpenwrt` 仓）+ 守护进程补载；**设备上的文件由 `quicguard-sync.sh` 生成**（含 CN 镜像集合） | `nft delete table inet quicguard`，或 `nft -f` 任意 `/etc/quicguard.nft.bak.*` |
| `firewall/quicguard-sync.sh` | `/etc/quicguard-sync.sh` | 人工投放；按 ShellCrash 的 `cn_ip` / `cn_ip6` 重写 `/etc/quicguard.nft`（订阅更新 / ShellCrash 重启后要重跑） | 删文件 + 恢复旧 `/etc/quicguard.nft` |
| `firewall/tables/googlecn.nft` | `/etc/googlecn.nft` | 同上 | `nft delete table inet googlecn` |
| `firewall/tables/googleroute.nft` | `/etc/googleroute.nft` | 同上（**等 1053 端口就绪后**才加载） | `nft delete table inet googleroute` |
| `tools/latency/archive/**` | **不部署** | 无（早期探测残留，已归档） | 归档件，保留备查 |
| `tools/public-nodes/screen.py` + `run-daily.cmd` | **不部署（PC 侧）** | 手动或 Windows 计划任务（默认每天 05:10，仅登录时） | 删计划任务 + 删文件；节点回滚用路由器上的 `proxies.yaml.bak-public-screen-*` |
| `tools/public-nodes/evaluate.py` + `uri_parse.py` | **不部署（PC 侧）** | 手动：对比多个公开节点源（Clash YAML / V2Ray URI） | 删文件即可 |

> **通用工具不在本仓**：规则审计、mihomo 控制面诊断、站点可达性专项
> （`mihomo/` 与 `cdn/` 两个目录）都在 **`OpenwrtOpsToolkit` 仓**（公开）——
> 本仓只留**分流配置与文档**。

## 待补

本仓缺、但设备上在跑的东西 —— **补进来前不要删设备上的对应文件**：

| 缺什么 | 为什么重要 | 证据 |
|---|---|---|
| `config/starts/clash_modify.sh` | 整个合并链路的**入口**：读 `yamls/*`、拼 fake-ip 过滤、挂 `rules-mid.sh` / `reorder-groups.sh` 两个钩子 | `post-sc-update.sh` 按标记 `rules-mid.sh` 判定该文件是否被官方覆盖 |
| `config/fakeip/fake_ip_filter` 与 `fake_ip_filter.list` | 部署到 `/etc/ShellCrash/configs/`（**不是 `yamls/`**）。Chrome LNA 修复（`+.gstatic.com` / `+.googleapis.com` / `+.google.com`）就落在这里 | `ai-api-check.sh` 第 7 段校验 `fake_ip_filter` 里有 `+.googleusercontent.com`；`clash_modify.sh` 会 cat 这两个文件合成 fake-ip 排除清单 |
