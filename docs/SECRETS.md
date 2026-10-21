# 凭据与安全须知

> **一句话**：本仓涉及哪些凭据、分别从哪里读、换设备或公开 Fork 前怎么处理 ——
> 本篇**只写位置与读取方式，不写任何值**。

---

## 1. 原则

本仓库是**脱敏后的参考实现**，不保存任何可直接使用的凭据：

- 文档与模板里出现的是 `<REDACTED-...>` / `<YOUR-...>` / `<REPLACE-...>` 占位符；
- 脚本从**环境变量**或**设备侧真源**读取；
- `.gitignore` 排除 `proxies.yaml`、订阅原文、私钥与本机工作区。

**占位符不是真实值** —— 拿 `<REPLACE-VMESS-UUID>` 去连接一定失败，那不是 bug，是设计。

---

## 2. 凭据清单与读取方式

| 凭据 | 真源（值在这儿） | 本仓里**不出现值**的对应物 | 处置 |
|---|---|---|---|
| **mihomo 控制台 / 控制 API secret** | 路由器 `/etc/ShellCrash/configs/ShellCrash.cfg` 的 `secret=` 行 | PC 侧诊断脚本从环境变量 `MIHOMO_SECRET` 读；文档与模板里写 `<REDACTED-mihomo-secret>` | 轮换后重新导出环境变量，否则表现为静默 `Unauthorized` |
| **节点 UUID**（vmess uuid） | 机场订阅面板 / 订阅链接；本机副本是 `config/yamls/proxies.yaml` | 模板 `config/yamls/proxies.example.yaml` 里写作 `<REPLACE-VMESS-UUID>`；真实文件被 `.gitignore` 排除 | 不入库；克隆后按 §3.2 重建 |
| **mihomo /proxies 快照**（含节点 UUID 与密码） | 路由器控制 API 的 `/proxies` 响应 | 不随公开仓发布 | 现取现用，不落库 |
| **机场订阅原始内容** | 订阅链接本身 | 不随公开仓发布 | **绝不入库**：含节点 UUID 与入口凭据 |
| **SSH / HTTPS / WireGuard 私钥** | 设备 `/etc/dropbear/`、`/etc/uhttpd.key`、`/etc/wg/` | 不入库 | 需要时从离线归档取 |

---

## 3. 凭据怎么取

> **本文档只写位置，不写值；值在真源取，或在真源轮换之后再取。**

### 3.1 mihomo 控制台 secret

- **设备侧真源**：`/etc/ShellCrash/configs/ShellCrash.cfg` 的 `secret=` 行。
- **PC 侧脚本**：从环境变量 `MIHOMO_SECRET` 读；未设置就明确报错，不会拿着空 secret
  去请求、再收到一个含义不明的 401。
- **连接地址**：`MIHOMO_HOST` / `MIHOMO_PORT` / `MIHOMO_API` 可覆盖。

```sh
export MIHOMO_SECRET="$(ssh root@"$ROUTER_IP" \
  'grep -m1 "^secret=" /etc/ShellCrash/configs/ShellCrash.cfg | cut -d= -f2- | tr -d "\x27\x22"')"
```

### 3.2 节点 UUID（`config/yamls/proxies.yaml`）

**仓库里没有节点凭据，只有模板。** 克隆本仓后要自己重建：

```sh
cp config/yamls/proxies.example.yaml config/yamls/proxies.yaml
# 然后把 <YOUR-NODE-SERVER> / <YOUR-WS-HOST> / <REPLACE-VMESS-UUID>
# 换成你自己的订阅入口与 UUID
```

| 项 | 值 |
|---|---|
| 模板（入库） | `config/yamls/proxies.example.yaml` |
| 真实文件（**不入库**） | `config/yamls/proxies.yaml` —— `.gitignore` 已排除 |
| 作用 | 备用入口，由 `starts/clash_modify.sh` 合并进生成的 `config.yaml`（链路见 [ARCHITECTURE.md](ARCHITECTURE.md) §3） |

### 3.3 环境变量 → 谁在读

| 环境变量 | 谁在读 | 默认值 | 缺失时 |
|---|---|---|---|
| **`MIHOMO_SECRET`** | `OpenwrtOpsToolkit` 仓的 mihomo / cdn 诊断脚本 | 无 | 抛 `RuntimeError`，不静默 |
| **`MIHOMO_API`** | 同上（控制 API 基址，**最常用**） | `http://127.0.0.1:9999` | 用默认值 |
| **`MIHOMO_HOST`** | 同上 | 由 `MIHOMO_API` 解析得出 | 用默认值 |
| **`MIHOMO_PORT`** | 同上 | 由 `MIHOMO_API` 解析得出（9999） | 用默认值 |

---

## 4. 公开 Fork 前的检查清单

```sh
# 1) 确认没有把凭据文件带进去
git ls-files | grep -Ei 'proxies\.yaml$|proxies\.json$|subscription'

# 2) 确认忽略规则生效
git status --ignored --short | grep -E '^!!' | head -20

# 3) 扫一遍将要提交的内容
python tools/check-secrets.py
```

逐条确认：

- [ ] `config/yamls/proxies.yaml` **不在** `git ls-files` 里；
- [ ] 订阅原文、`proxies.json`、连接快照不在库里；
- [ ] 诊断脚本源码里没有明文 secret（只从环境变量读）；
- [ ] 模板里是 `<REPLACE-...>` / `<YOUR-...>` 占位符；
- [ ] mihomo 控制 API secret 已轮换，且重新导出 `MIHOMO_SECRET`；
- [ ] 原始规则审计证据与抓包不在公开树里。

---

## 5. 硬规矩

1. **新脚本不许把 secret 写死在文件里** —— 读环境变量，未设置就明确报错退出。
2. **文档里出现值只允许是占位符** —— 新的说明一律指向真源。
3. **凭据变更必须连带改依赖方** —— 换了 secret，PC 侧要重新导出 `MIHOMO_SECRET`。
4. **日志里不要打印凭据** —— `Authorization` 头、订阅 URL 的 token 段，打印前先打码。
5. **订阅链接本身就是凭据** —— 不贴进 issue、截图或日志。

---

## 6. 相关文档

| 要查什么 | 去哪 |
|---|---|
| 配置生成链路（订阅 → 合并 → 钩子 → 加载）、文件所有权 | [ARCHITECTURE.md](ARCHITECTURE.md) §1、§3 |
| 节点凭据的备份与回退 | [MAINTENANCE.md](MAINTENANCE.md) |
| 各诊断脚本怎么跑、要传哪些参数 | [TOOLS.md](TOOLS.md) |
| 鉴权异常怎么查 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| 忽略规则 | 仓库根 `.gitignore` |
| 许可证（本仓含 ShellCrash 的 GPL-3.0 派生件） | 仓库根 [LICENSE](../LICENSE) |
