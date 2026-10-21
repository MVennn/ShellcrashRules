<div align="center">

<img src="assets/logo.png" width="128" alt="ShellcrashRules">

# ShellcrashRules

**ShellCrash / mihomo 的分流规则与链路诊断参考实现**

订阅解决「有哪些节点」，本仓解决「每个域名走哪条路」。

![CI](https://github.com/MVennn/ShellcrashRules/actions/workflows/ci.yml/badge.svg) ![源码仓库](https://img.shields.io/badge/源码仓库-GitHub-181717?logo=github&logoColor=white) ![问题反馈](https://img.shields.io/badge/问题反馈-Issues-181717?logo=github&logoColor=white) ![OpenWrt](https://img.shields.io/badge/OpenWrt-25.12-00B5E2?logo=openwrt&logoColor=white) ![mihomo](https://img.shields.io/badge/mihomo-Clash.Meta-9B59B6) ![License](https://img.shields.io/badge/License-GPL--3.0-red)

</div>

---

## 这是什么

小米 AX3000T 上跑 ShellCrash + mihomo 透明代理的**分流配置**。订阅负责「有哪些节点」，
这一层负责「每个域名走哪条路」。

本仓补两件事：

- **配置层** —— 自定义策略组、AI 分流规则，以及订阅合并后的两个处理钩子（CN 直连中间层、策略组去重重排）
- **防火墙层** —— 三张独立 nft 表：QUIC 全局阻断、Google 国内边缘段重定向、Google 推送端口与 DNS 劫持。ShellCrash 每次重启都会重写它自己的整表，所以这三张必须独立存在

**这是一份脱敏后的参考实现**：策略组名、节点名、服务器域名、IPv6 前缀等设备 / 订阅相关的值
已替换为占位符或示例值；订阅原文、节点 UUID 与原始证据**不随公开仓发布**。
通用工具（规则审计、mihomo 控制面诊断、站点可达性专项）在 `OpenwrtOpsToolkit` 仓；
路由器系统运维在 `AX3000TOpenwrt` 仓；控制台在 `OpenwrtConsole` 仓。

配置怎么长出来、每个文件部署到路由器的哪个路径，见
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 与 [docs/DEPLOY.md](docs/DEPLOY.md)。

## 环境要求

| 项 | 要求 |
|---|---|
| 路由器 | 小米 AX3000T（MT7981），OpenWrt 25.12 |
| 代理框架 | ShellCrash + mihomo，Redir 模式 |
| 端口 | 混合口 7890 / 重定向口 7892 / 控制 API 9999（带 secret） |
| 依赖 | 路由器侧 curl、uclient-fetch、jsonfilter、nft；PC 侧 Python 3 |

Redir 模式只代理 TCP，UDP 一律直出 —— 这是本仓一半坑的来源，见 [docs/PITFALLS.md](docs/PITFALLS.md)。

## 使用

1. 把本仓的配置部署到路由器 —— 路径映射与回退方式见 [docs/DEPLOY.md](docs/DEPLOY.md)。
2. 准备控制 API 的 secret（从环境变量读，不落盘）—— 见 [docs/SECRETS.md](docs/SECRETS.md)。
3. 自定义节点入口：复制模板并按你的订阅填写：

   ```sh
   cp config/yamls/proxies.example.yaml config/yamls/proxies.yaml
   # 把 <YOUR-NODE-SERVER> / <YOUR-WS-HOST> / <REPLACE-VMESS-UUID> 换成真实值
   ```

4. **订阅更新后必跑自检**：

   ```sh
   ssh root@<路由器> 'sh /etc/ShellCrash/ai-api-check.sh'
   ```

   退出码 0 = 全过。它覆盖最容易悄悄坏掉的十几个点（钩子丢失、QUIC 阻断表没加载、Google 出口规则被冲掉……）。
5. 查策略组、测节点延迟、跑规则审计 —— 脚本在 `OpenwrtOpsToolkit` 仓，用法见 [docs/TOOLS.md](docs/TOOLS.md)。
6. 出问题先查 [docs/PITFALLS.md](docs/PITFALLS.md) 与 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

## 目录

```
config/         ShellCrash 扩展配置：策略组、规则生成器、合并钩子、节点模板
firewall/       三张独立 nft 表与配套脚本
docs/           文档（唯一索引：docs/README.md）
tools/          节点筛选、延迟探测、文档自检与密钥守卫
third-party/    随仓分发的上游规则列表与 starts 补丁（各自保留许可证）
assets/         logo 与社交预览
```

## 安全与隐私

- 本仓库**不保存凭据**：节点 UUID、订阅 token、控制 API secret 均不入库；`config/yamls/proxies.yaml` 被 `.gitignore` 排除。
- 模板里的 `<YOUR-...>` / `<REPLACE-...>` 是占位符，不是真实值。
- 公开节点由陌生人运营，可能记录或篡改流量；不要把公开节点用于 AI、网银、邮箱或账号登录。
- 原始规则审计证据与内部台账仅保留在维护者的本地工作区，不进入公开仓库。

## 反馈

某个域名走错了路、规则没命中、自检报红，都可以到 [Issues](https://github.com/MVennn/ShellcrashRules/issues) 反馈。

请尽量带上：

- mihomo 内核与 ShellCrash 版本
- `ai-api-check.sh` 的输出
- 出问题的域名、实际走向与期望走向
- 相关配置片段（先脱敏：节点 UUID 与 secret 一律换成 `<REDACTED-...>`）

## 免责声明

本项目仅供学习与个人使用。

- 不收集、不上传、不存储任何个人信息；规则与脚本只作用于你自己的路由器
- 不修改 ShellCrash / mihomo 上游行为，只经官方扩展点与独立 nft 表接入
- 本仓不含机场订阅凭据与节点 UUID；控制台 secret 从环境变量读，证据里用占位符
- 本仓只做代理配置与分流，不涉及任何账号凭据的托管与转发
- 使用本项目产生的任何后果由使用者自行承担；请勿用于商业用途或违反第三方服务条款的场景

「ShellCrash」「mihomo / Clash.Meta」「OpenWrt」及其标志的知识产权归各自权利人所有；
本项目与之不存在隶属、合作或授权关系。

## 开源鸣谢

本仓库建立在这些开源项目之上：

| 项目 | 用途 |
|---|---|
| [ShellCrash](https://github.com/juewuy/ShellCrash) | 透明代理框架；本仓用的 `yamls/` 扩展点与 `starts/` 补丁机制都来自它 |
| [ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) | 分流规则的数据源与模板血统；设备侧规则模板是它的裁剪改编版 |
| [mihomo / Clash.Meta](https://github.com/MetaCubeX/mihomo) | 代理内核；`config.yaml` 的字段语义由它定义 |
| [MetaCubeX meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) | geosite 分类与 ruleset 数据源；AI 规则生成器的输入 |
| [OpenWrt](https://openwrt.org) | 路由器固件与 nftables 子系统；三张 nft 表的 `inet` family 与 reject 语法 |

各上游的许可证、随仓分发的副本与边界，见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

## 许可证

本仓库按 [GNU General Public License v3.0](LICENSE) 发布，第三方声明见 [NOTICE](NOTICE)。
整仓为什么用 GPL-3.0、随仓分发副本的许可与例外，见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。
