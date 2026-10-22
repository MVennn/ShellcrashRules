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

---

# 推送前脱敏规则（通用）

> **一句话**：推送前跑一次 `python tools/check-secrets.py`；它拦的是三类东西 ——
> 可用凭据、本机用户目录、真实邮箱。规则对 8 个仓完全一致，一处改全局同步。

---

## 1. 为什么需要这一条

历史教训：本系列仓的脱敏一度靠人记，结果漏过两次 ——

1. **同步脚本把 `--config` 的绝对路径回显进报告**，报告又作为 evidence 提交，
   本机用户目录就这样进了版本库。脚本默认值是按主目录推导的，本身没问题，
   问题出在那两行 `log("已写入 %s" % args.config)`。
2. **没有守卫的仓全靠自觉**。8 个仓里原本只有 2 个有 `tools/check-secrets.py`，
   规则里还不含本机路径。

所以规则固化成本篇 + 一个脚本 + 一个 CI 步骤。脚本是规则的**可执行版本**。

---

## 2. 三类拦截面

| 类别 | 例子 | 为什么拦 |
|---|---|---|
| **P0 可用凭据** | `gh[pousr]_…`、`sk-…`、`oc_sk_…`、`AIza…`、`glpat-…`、`-----BEGIN … PRIVATE KEY`、`AKIA…`、shadow 哈希、订阅 URL 的 token 段、代理节点 URI | 任何人拿到就能直接用 |
| **P1 本机用户目录** | `C:\Users\<名字>\…`（正反斜杠都拦） | 暴露用户名与软件安装布局，是社工的素材 |
| **P1 真实邮箱** | `…@qq.com` / `@163.com` / `@gmail.com` 等 | 暴露个人身份；GitHub noreply 邮箱不含这些域名，不会误伤 |

> **域名清单**：qq / 163 / 126 / gmail / outlook / hotmail / foxmail / sina / sohu。
> 只列国内常用与 Google / Microsoft 系 —— 加更多域名只会增加误报。

---

## 3. 三条放行规则（避免误报）

守卫不是越严越好，误报多了人就学会跳过它。所以明确放行三种情形：

### 3.1 占位符与示例值不算命中

行内含 `REDACTED` / `YOUR-` / `REPLACE-` / `<…>` / `example.com` / `placeholder`
/ `<用户名>` 等字样时，整行跳过。所以写文档时**优先用占位符**，能省掉很多例外。

### 3.2 文档类文件允许「截断形式」的描述性引用

变更说明里需要引用泄漏原文，否则读者不知道该改什么。形如下面的写法放行：

- 用户名位置就是省略号：`C:\Users\...\provider_config.json`
- 用户名用尖括号占位：`C:\Users\<名字>\...`
- 用户名后紧跟 `\...` 截断：`C:\Users\SansK\...`

**完整路径一律不放行。** 这条只对文档类文件生效
（`CHANGELOG.md` / `PROGRESS.md` / `SECURITY.md` / `CONTRIBUTING.md` / `docs/` /
`evidence/` / `memories/`）。

### 3.3 占位用户名不算命中

示例文件里的 `C:/Users/You/...`、`C:/Users/User/...`、`C:/Users/你的用户名/...`
是给用户照着改的模板，不是本机路径。

---

## 4. 白名单：只放「有意为之」

逐行白名单（`LINE_ALLOWLIST`）只放两类情形，**每条必须写清理由**：

- **机制上就该出现** —— 如 `.mailmap` 里的邮箱映射，那是 git 官方的作者身份
  归属机制，邮箱本来就该在里面。
- **确定不是敏感信息** —— 如 Kotlin 协程符号 `$scaleDone$1` 被 shadow 哈希
  正则误判。

加白名单前先问：能不能改用占位符绕开？能的话优先改内容，不要加白名单。

---

## 5. 推送前怎么做

```sh
# 1) 扫已跟踪文件（CI 跑的就是这个，退出码 0 才能推）
python tools/check-secrets.py

# 2) 扫工作树，含未跟踪文件（提交前自查用）
python tools/check-secrets.py --all
```

`--all` 模式**遵循 `.gitignore`** —— 本机配置（如 `config.local.json`）设计上
就不入库，报出来只是噪音。但它仍会扫**未跟踪且未被忽略**的新文件，所以能抓住
「新建了个文件忘了加 .gitignore」这种情况。

**CI 里有「敏感信息扫描」步骤**，推上去会自动跑。本地先跑一遍，别等 CI 报错。

---

## 6. 踩过的坑（写规则/脚本时注意）

1. **Python 单元素元组**：`SKIP_PREFIXES = ("tools/preview/")` 少了尾逗号，
   它不是元组而是字符串，`any(base.startswith(p) for p in "…")` 会逐字符迭代，
   导致所有以首字符开头的路径都被跳过 —— 守卫静默失效，扫描显示"通过"但实际
   什么都没查。必须写 `("tools/preview/",)`。
2. **`printf` 吞转义**：Git Bash 里 `printf 'C:\Users\...'` 把 `\U` 当 unicode
   转义，写出的测试文件内容是坏的，注入测试假通过。写含反斜杠的测试内容要用
   Python 的 `chr(92)`。
3. **replace-text 只匹配字面量**：重写历史时，文档里引用泄漏原文的写法
   （如 `git grep Users.SansK`，没有 `C:\` 前缀）匹配不到，要单独列规则。
4. **模板多行块替换**：按单行字符串替换跨多行的配置块会留下孤儿行导致
   IndentationError；先在源里 `assert` 锚点存在再替换，失败即中止。
5. **守卫脚本自己的注释会被自己的规则拦到** —— 注释里别出现完整路径字面量。

---

## 7. 相关文档

| 要查什么 | 去哪 |
|---|---|
| 凭据从哪读、怎么轮换 | 本篇其余章节 |
| 上报安全问题 | [../SECURITY.md](../SECURITY.md) |
| 提交前自检 | [../CONTRIBUTING.md](../CONTRIBUTING.md) |
| 文档怎么写 | [DOC-RULES.md](DOC-RULES.md) |
