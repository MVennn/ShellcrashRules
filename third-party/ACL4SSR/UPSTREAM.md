# ACL4SSR/ACL4SSR —— 来源凭证

> **一句话**：本目录是 ACL4SSR 规则模板的**最小子集**（17 个文件）——
> 它是本仓分流规则的**数据源与模板血统**。

---

## 1. 上游

| 项 | 值 |
| --- | --- |
| 仓库 | `ACL4SSR/ACL4SSR` |
| URL | <https://github.com/ACL4SSR/ACL4SSR> |
| 许可 | **CC BY-SA 4.0 International**（原文见本目录 `LICENCE`，注意上游文件名是 `LICENCE` 不是 `LICENSE`） |
| 钉住的 commit | `575637df38884575bfa523e95c17d0ee3be1676c`（`master`） |
| 上游路径 | `Clash/`（规则集与模板）+ `LICENCE` |
| commit 时间 | 2026-10-17 |

## 2. 包含哪些文件（17 个）

| 文件 | 是什么 |
| --- | --- |
| `Clash/config/ACL4SSR_Online_Full.ini` | **规则模板本体** —— 设备侧 `rules/ShellClash.ini` 是它的裁剪改编版 |
| `Clash/ChinaDomain.list` `Clash/ChinaIp.list` `Clash/ChinaIpV6.list` | CN 直连集合（模板的 `ruleset=` 指向它们） |
| `Clash/ProxyMedia.list` `Clash/ProxyLite.list` | 媒体 / 轻量代理集合 |
| `Clash/GoogleCN.list` `Clash/Microsoft.list` `Clash/LocalAreaNetwork.list` | Google / 微软 / 局域网 |
| `Clash/Apple.list` `Clash/BanAD.list` `Clash/BanProgramAD.list` | Apple / 广告拦截 / 程序广告拦截 |
| `Clash/Telegram.list` | Telegram |
| `Clash/Ruleset/Netflix.list` `Clash/Ruleset/DisneyPlus.list` `Clash/Ruleset/GoogleFCM.list` | Ruleset 子目录里的三个 |
| `LICENCE` | CC BY-SA 4.0 全文 |

**逐字节一致性：17 / 17 ✅**（md5 与上游 `raw.githubusercontent.com` 逐一比对通过）。

> 刻意**没有**取上游其余 560+ 个文件（整棵 `Clash/` 有 9.6 MB）——
> 本仓只取**自己实际引用**的 16 个 `ruleset=` 与那 1 个模板，取子集能让"引了什么"一目了然。

## 3. 与本仓的关系（为什么值得 vendor）

设备侧实际生效的 `rules/ShellClash.ini` 是 ACL4SSR `ACL4SSR_Online_Full.ini` 的
**裁剪改编版** —— 模板里 18 条 `ruleset=` 有 **15 条**指向本目录里的这批 `.list`。

存一份上游原件的价值：
- 随时能回答「这个 ruleset 原本长什么样、我们改了什么」；
- 离线复现规则审计的**输入**（`scripts/rule_audit.py` 依赖同一批 `.list` 的结构）；
- 证明「改编版」与「原件」的血缘关系。

## 4. 许可：CC BY-SA 4.0 与本仓 GPL-3.0 的关系

本仓整体是 **GPL-3.0**（因为含 ShellCrash 的 GPL-3.0 派生件，见
[../../docs/UPSTREAM.md](../../docs/UPSTREAM.md)）。

**CC BY-SA 4.0 → GPL-3.0 是单向兼容的**：允许把 CC BY-SA 4.0 的内容并入 GPL-3.0 的作品。
但反过来不成立，且 **CC BY-SA 4.0 自带的 share-alike 条款独立于 GPL-3.0 继续生效**。

本仓的处理方式 —— **隔离**：

| 范围 | 许可 |
| --- | --- |
| 本仓自研内容（配置、钩子、生成器、诊断工具、文档） | GPL-3.0 |
| **本目录的 ACL4SSR 原件** | **CC BY-SA 4.0**，不改一字，原样随附 `LICENCE` |

再分发本目录时必须做到（CC BY-SA 4.0 的三项义务）：
1. **署名** ACL4SSR；
2. 保持 **CC BY-SA 4.0** 许可；
3. **改编物亦按 CC BY-SA 4.0** 发布 —— 本仓的 `rules/ShellClash.ini` 是它的改编版，
   按此条款该文件亦应按 CC BY-SA 4.0 对外分发（仓库根 [NOTICE](../../NOTICE) 已标注这一例外）。

## 5. 怎么更新

```bash
SHA=$(git ls-remote https://github.com/ACL4SSR/ACL4SSR.git refs/heads/master | cut -f1)
BASE="https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/$SHA"
for f in Clash/Apple.list Clash/BanAD.list Clash/BanProgramAD.list Clash/ChinaDomain.list \
         Clash/ChinaIp.list Clash/ChinaIpV6.list Clash/config/ACL4SSR_Online_Full.ini \
         Clash/GoogleCN.list Clash/LocalAreaNetwork.list Clash/Microsoft.list \
         Clash/ProxyLite.list Clash/ProxyMedia.list Clash/Ruleset/DisneyPlus.list \
         Clash/Ruleset/GoogleFCM.list Clash/Ruleset/Netflix.list Clash/Telegram.list LICENCE; do
  mkdir -p "$(dirname "$f")"; curl -sSL "$BASE/$f" -o "$f"
done
```

**更新后**：本仓 `config/generated/rules.yaml` 的 `ruleset=` 指向不变，但**内容**会变 ——
需要重跑一次规则审计（`scripts/rule_audit.py`），确认没有新的遮蔽冲突。

## 6. 上游的另一个坑

`ACL4SSR` 的 `ruleset=` 指向的是 `.../ShellClash/master/rules/xxx.list` 这种
**仓库内路径**，不是本目录的本地路径 —— 两者**内容同源但不是同一份文件**。
本仓的 `config/hooks/rules-mid.sh` 插入 CN 中间层时参照的是**设备侧**那份。
