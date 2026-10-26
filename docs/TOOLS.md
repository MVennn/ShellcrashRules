# 工具用法

> **一句话**：本仓与配套工具箱仓里那几个脚本「干什么、在哪、怎么跑、要传什么参数」的正本 ——
> 订阅更新后的**校验顺序**不在这里，见 [MAINTENANCE.md](MAINTENANCE.md) §2。

---

## 1. 工具在哪

| 工具 | 在哪 | 跑在哪 | 会不会改设备状态 |
|---|---|---|---|
| AI 接口自检 `ai-api-check.sh` | 本仓 `config/`，设备侧 `/etc/ShellCrash/` | 路由器上 | ⚠️ 少数几段带自动修复（改 log-level、修 `task.sh` 路径、重载 nft 表） |
| 规则生成器 `ai-rules-update.sh` | 本仓 `config/generators/` | 路由器上 | ✅ 写 `yamls/rules.yaml`（写前校验不过就什么都不改） |
| 控制 API 客户端 `mihomo_api.py` | `OpenwrtOpsToolkit` 仓 `mihomo/` | PC 侧 | ❌ 只读 |
| 节点延迟探测 `latency_probe.py` | `OpenwrtOpsToolkit` 仓 `mihomo/` | PC 侧 | ❌ 只读 |
| 规则审计器 `rule_audit.py` | `OpenwrtOpsToolkit` 仓 `mihomo/` | PC 侧 | ❌ 只读 |
| 规则审计口径与结论 | [RULE-AUDIT.md](RULE-AUDIT.md) | — | — |

> 通用诊断工具**不在本仓**（本仓是参考实现，工具箱仓是公开仓）—— 边界见
> [UPSTREAM.md](UPSTREAM.md) §6。

---

## 2. 准备凭据（跑 PC 侧工具前必做）

mihomo 控制 API 带 `secret`，工具**从环境变量读，源码里没有明文**；
**没设就抛 `RuntimeError` 明确报错退出**，不会拿着空 secret 去请求、再收到一个含义不明的 401。

```bash
# 克隆工具箱仓（公开仓）并进入
git clone https://github.com/MVennn/OpenwrtOpsToolkit.git && cd OpenwrtOpsToolkit

# 从设备上取 secret 并导出（值不落盘、不进仓库）
export MIHOMO_SECRET="$(ssh root@10.0.0.1 'grep -m1 "^secret=" /etc/ShellCrash/configs/ShellCrash.cfg | cut -d= -f2- | tr -d "\x27\x22"')"
```

| 环境变量 | 作用 | 缺了会怎样 |
|---|---|---|
| `MIHOMO_SECRET` | 控制 API 鉴权 | **抛 `RuntimeError` 报错退出** |
| `MIHOMO_API` | 控制 API 基址，默认 `http://127.0.0.1:9999` | 用默认值 |
| `MIHOMO_HOST` / `MIHOMO_PORT` | 单独指定主机 / 端口（与 `MIHOMO_API` 二选一） | 用默认值 |

值的真源、轮换与脱敏规矩见 [SECRETS.md](SECRETS.md)。

---

## 3. 检查策略组

```bash
# 读 mihomo 控制 API：只读、不切组
python mihomo/mihomo_api.py proxies
# 输出每个策略组的 type / now / 历史延迟条数
```

- 组名不写死：默认查 `GROUP_A` / `GROUP_B` / `GROUP_C` 这类占位符，
  用 `MIHOMO_PROBE_GROUPS='🚀 节点选择,🎯 全球直连'` 换成你自己的组名。
- 其它子命令：`summary`（版本 / 内核参数 / 规则统计）、`rulestats`（规则类型分布）、
  `conns`（当前连接快照）、`dns`（经 mihomo 解析域名）、`delay <URL> [组名...]`、
  `raw <路径>`。`python mihomo/mihomo_api.py --help` 有完整说明。
- 路由器本机也能直接看（**路由器自己的 curl 不走透明代理**）：

  ```bash
  ssh root@10.0.0.1 'curl -s -H "Authorization: Bearer <secret>" http://127.0.0.1:9999/proxies' | head -c 800
  ```

---

## 4. 跑 AI 接口自检

```bash
# 路由器上：逐段自检（策略组 / 延迟 / 钩子 / nft 表 / 规则位置 / 出口组…）
ssh root@10.0.0.1 'sh /etc/ShellCrash/ai-api-check.sh'
# 退出码 0 = 全过 / 1 = 有失败项
```

- **订阅更新后必跑这一条** —— 它覆盖本仓最容易悄悄坏掉的十几个点
  （hotupdate 路径被 ShellCrash 更新重置、`rules-mid.sh` 钩子丢失、QUIC 阻断表没加载、
  Google 出口规则被冲掉……）。
- 段数与逐段覆盖范围见 [MAINTENANCE.md](MAINTENANCE.md) §2.2。
- 失败怎么查见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) §1。

---

## 5. 跑规则审计

```bash
# PC 侧，纯离线：config.yaml + proxies.json + 上游 lists/ → 报告
# 输入从路由器取：
scp root@10.0.0.1:/tmp/ShellCrash/config.yaml ./config.yaml
ssh root@10.0.0.1 'curl -s http://127.0.0.1:9999/proxies' > proxies.json
# 列表目录用本仓现成的：ShellcrashRules/third-party/ACL4SSR/Clash/
python mihomo/rule_audit.py config.yaml proxies.json third-party/ACL4SSR/Clash REPORT.md
```

- 审计器在工具箱仓 `mihomo/rule_audit.py`；**不写死策略组名**，用环境变量对上你自己的组：

  | 环境变量 | 对应组 | 默认占位符 |
  |---|---|---|
  | `AUDIT_DIRECT_GROUP` | 直连组 | `DIRECT_GROUP` |
  | `AUDIT_AD_GROUP` | 广告拦截组 | `AD_GROUP` |
  | `AUDIT_AI_GROUPS` | AI 组（逗号分隔） | `AI_GROUP` |
  | `AUDIT_FCM_GROUP` / `AUDIT_TELEGRAM_GROUP` | 推送组 / 电报组 | `FCM_GROUP` / `TELEGRAM_GROUP` |
  | `AUDIT_NETFLIX_GROUP` / `AUDIT_DISNEY_GROUP` | Netflix / Disney+ | `NETFLIX_GROUP` / `DISNEY_GROUP` |
  | `AUDIT_MS_GROUP` / `AUDIT_APPLE_GROUP` | 微软服务 / 苹果服务 | `MS_GROUP` / `APPLE_GROUP` |

- 依赖 PyYAML（`pip install pyyaml`）；审计口径与结论见 [RULE-AUDIT.md](RULE-AUDIT.md)。
- 报告里大量遮蔽冲突怎么判，见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) §7。

---

## 6. 测节点延迟

```bash
# PC 侧，只读：只调 /proxies 与 /proxies/{name}/delay，不切组
python mihomo/latency_probe.py
```

| 环境变量 | 含义 | 默认 |
|---|---|---|
| `MIHOMO_PROBE_GROUPS` | 要看的策略组（逗号分隔） | `GROUP_A,GROUP_B,GROUP_C` |
| `MIHOMO_PROBE_NODES` | 要测的节点（逗号分隔） | `NODE_A,NODE_B` |
| `MIHOMO_PROBE_URLS` | 探测目标 `名字=URL`（逗号分隔） | 三个公开 AI 站点 |

> 脚本**不写死任何组名 / 节点名** —— 默认值是通用占位符，照抄订阅里的名字会一个都对不上。

---

## 7. 相关文档

| 要查什么 | 去哪 |
|---|---|
| 订阅更新后的校验顺序与判据 | [MAINTENANCE.md](MAINTENANCE.md) §2 |
| 凭据位置、取值、轮换、脱敏 | [SECRETS.md](SECRETS.md) |
| 规则审计口径与结论 | [RULE-AUDIT.md](RULE-AUDIT.md) |
| 脚本所在的工具箱仓边界 | [UPSTREAM.md](UPSTREAM.md) §6 |
| 自检失败怎么排 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| 踩坑的根因与根治 | [PITFALLS.md](PITFALLS.md) |
