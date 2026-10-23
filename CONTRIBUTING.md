# 参与贡献

> **一句话**：本仓是 ShellCrash / mihomo 的分流规则与链路诊断参考实现；本文件只讲
> 怎么提 Issue / PR、改配置前要守哪些规矩。

先说边界：订阅负责「有哪些节点」，本仓负责「每个域名走哪条路」。节点订阅内容、
ShellCrash / mihomo 本体、路由器系统运维、控制台与 AI 接入各有归属，
分工见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。

## 提 Issue

- **域名走错路 / 规则没命中 / 自检报红** → 用「问题反馈（Bug）」模板。
  请务必带上 **`ai-api-check.sh` 的完整输出**、实际与期望走向、ShellCrash / mihomo 版本：

  ```sh
  ssh root@<路由器> 'sh /etc/ShellCrash/ai-api-check.sh; echo "exit=$?"'
  ```

- **想要新的规则段、策略组或诊断项** → 用「功能建议」模板。
  先说场景（哪个域名、现在走哪、为什么不对），再说期望的效果。

反馈前先查 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)；已知坑见
[docs/PITFALLS.md](docs/PITFALLS.md)，规则审计口径见 [docs/RULE-AUDIT.md](docs/RULE-AUDIT.md)。

## 提 Pull Request

1. 从 `main` 开分支，一条改动一个分支。
2. 配置里的**真实节点信息一律不入库**：节点 UUID、订阅 token、控制 API secret
   用 `<REDACTED-...>` 或示例值，规则见 [docs/SECRETS.md](docs/SECRETS.md)。
3. 提交前至少跑过：

   ```sh
   python3 tools/check-docs.py
   python3 tools/check-secrets.py
   python3 tools/check-vault-not-staged.py --all
   find . -name '*.sh' -not -path './third-party/*' -not -path './.work/*' \
     -print0 | xargs -0 -n1 sh -n
   ```

4. 改配置或 nft 表时，写清部署路径与回退方式（见 [docs/DEPLOY.md](docs/DEPLOY.md)）。
   PR 描述里写「怎么验的、实际走向是什么」；**真机没验就明说没验**。
5. 新增 / 改名 / 删除策略组时，按 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 的
   「代理组排序规则」同步 `config/hooks/reorder-groups.sh` 的 `order[]`
   （组顺序；需要时再改成员顺序 / 节点排序目标），PR 里贴出三处顺序的验证结果。

## 几条硬规矩

| 规矩 | 在哪定义 |
|---|---|
| 三张 nft 表必须独立存在，不能并进 ShellCrash 的整表 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| 订阅更新后必跑 `ai-api-check.sh`，退出码 0 才算过 | [docs/TOOLS.md](docs/TOOLS.md) |
| 凭据与节点信息不入库，配置片段先脱敏 | [docs/SECRETS.md](docs/SECRETS.md) |
| 规则顺序与策略组兜底不能随手改 | [docs/PITFALLS.md](docs/PITFALLS.md) |
| 新增策略组必须同步 `reorder-groups.sh` 的 `order[]`，否则会掉到面板最后 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)「代理组排序规则」 |
| 每条规则只在一篇文档里定义，别处只留链接 | [docs/DOC-RULES.md](docs/DOC-RULES.md) |
| 版本号只在发版时进位，规则按对象拆行 | [docs/VERSIONING.md](docs/VERSIONING.md) |
| 用户可感知的改动要进 [CHANGELOG.md](CHANGELOG.md) | [docs/MAINTENANCE.md](docs/MAINTENANCE.md) |

## 免责声明

提交 Issue / PR 即表示你已知悉：规则与 nft 表会改变路由器上的实际流量路径，
修改前应自行备份并能回退；公开节点由陌生人运营，可能记录或篡改流量；
使用本仓造成的任何后果由使用者自行承担。全文见 [README](README.md#免责声明)。
