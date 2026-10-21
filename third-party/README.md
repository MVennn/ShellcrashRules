# third-party/ —— 随仓分发的上游开源代码

> **一句话**：本目录是本仓**随仓库一起分发**的上游开源代码副本，
> 每一份都带 `UPSTREAM.md` 来源凭证（上游 URL / commit SHA / license /
> 本仓怎么用它 / 怎么更新）；上游代码**一个字节都没有改**。

---

## 1. 索引

| 项目 | 上游 URL | 用途 | License | vendored commit SHA | 为什么 vendor |
|---|---|---|---|---|---|
| [ShellCrash](ShellCrash/UPSTREAM.md) | https://github.com/juewuy/ShellCrash | 透明代理框架。本仓 `config/starts/fw_nftables.sh` 与 `config/starts/start_legacy_wd.sh` 是它 `starts/` 同名脚本的**打补丁派生件**；本目录存的是**上游原版** | GPL-3.0（[LICENSE.txt](ShellCrash/LICENSE.txt)） | `de1d9e20f71a77e794519d1c42d713253714f2e5` | 派生源：本仓改的正是它的文件，存原版才能随时比对补丁点、证明派生关系 |
| [ACL4SSR](ACL4SSR/UPSTREAM.md) | https://github.com/ACL4SSR/ACL4SSR | 分流规则的**数据源与模板血统**：设备侧生效的 `rules/ShellClash.ini` 是它 `Clash/config/ACL4SSR_Online_Full.ini` 的裁剪改编版，模板里 18 条 `ruleset=` 有 15 条指向它 | CC BY-SA 4.0（[LICENCE](ACL4SSR/LICENCE)） | `575637df38884575bfa523e95c17d0ee3be1676c` | 数据源：本仓的分流规则数据本体就是它的 `.list`；存快照才能复现离线规则审计的输入 |

**vendored 总体积：上游内容合计 594 260 字节（约 580 KiB，49 个文件）**；
连同 3 份本仓自写的来源凭证，`du -sk third-party` = 726 KB

> **只 vendor 相关子集，不 vendor 整仓**：两个上游的完整仓库都远超 5 MB
> （ShellCrash 的 git 仓库含 20 余个各架构预编译二进制包，git 历史累计 **5 346 820 KB**；
> ACL4SSR 整仓 **35412 KB**，`Clash/` 一个目录就约 9.8 MB）。
> 本仓只取**与本仓有代码级关系、且本仓真的消费**的那部分，
> 逐文件 `diff` 校验与上游一致，**未做任何修改**。

---

## 2. 没有 vendor 的上游（以及为什么）

| 项目 | 上游 URL | 关系 | 不 vendor 的理由 |
|---|---|---|---|
| mihomo / Clash.Meta | https://github.com/MetaCubeX/mihomo | **仅参考** —— 代理内核，本仓的 `config.yaml` 字段语义、`SAFE_PATHS` 行为、`rule-providers` / `sniffer` / `profile` 等均由它定义 | 仓库体积 **13792 KB**，是 Go 实现的完整内核；本仓只是**引用它的语义**，一行代码也没有复制进本仓 |
| MetaCubeX meta-rules-dat | https://github.com/MetaCubeX/meta-rules-dat | **数据源** —— `config/generators/ai-rules-update.sh` 按 geosite 分类 `category-ai-chat-!cn` 生成 `config/generated/rules.yaml`；运行期还要下载 `cnip.mrs` 等 ruleset | 仓库体积 **80815 KB**，装的是全球 geosite/geoip **数据文件**；本仓只**按 URL 取数据**，不需要也不适合把数据塞进版本库 |
| OpenWrt | https://openwrt.org | **仅参考** —— 路由器固件与 nftables 子系统，本仓 `firewall/tables/` 三张表按其 nftables 实现编写 | 固件项目本身，不是可 vendor 的代码库 |
| LM-Firefly/Rules | https://github.com/LM-Firefly/Rules | **仅取用** —— 规则模板 `rules/ShellClash.ini` 的 18 条 `ruleset=` 里有 1 条（Netflix 列表）指向它 | GitHub API `license` 字段为 **null**（无明确许可证声明）⇒ 按「NOASSERTION / 不明确的不要 vendor」不 vendor；本仓也未修改它的任何文件 |

> 上表四者**都不随本仓库分发**，在设备侧由各自的安装包 / 更新通道 / 按 URL 取数提供。
> 它们的来源、许可证与使用理由见仓库根 [NOTICE](../NOTICE)。

---

## 3. 本目录的纪律

1. **上游代码不改**：本目录里的任何文件都必须与上游逐字节一致。
   本仓自己的改动一律落在 `config/`（派生件），不落在这里。
2. **每次更新都要写来源凭证**：commit SHA、日期、体积、license 写进对应 `UPSTREAM.md`，
   并同步本文件、仓库根 `NOTICE` 与 `README.md` 的「开源鸣谢」表 —— 三处不允许错位。
3. **许可证不合并**：`third-party/ACL4SSR/` 下的文件仍按 CC BY-SA 4.0，
   `third-party/ShellCrash/` 下的文件按 GPL-3.0；
   仓库根的 GPL-3.0 只覆盖本仓自研部分与 ShellCrash 的 GPL-3.0 派生件。
   详见 [docs/UPSTREAM.md](../docs/UPSTREAM.md)。
4. **边界说明**见 [docs/UPSTREAM.md](../docs/UPSTREAM.md)。

---

## 4. 目录

```
third-party/
├── README.md                 本文件（索引）
├── ShellCrash/
│   ├── UPSTREAM.md            来源凭证：URL / SHA / license / 补丁点 / 更新命令
│   ├── LICENSE.txt            上游 GPL-3.0 全文（未改）
│   ├── version                上游版本号（1.9.5beta3）
│   ├── rules/
│   │   ├── ShellClash.ini     设备侧正在用的规则模板
│   │   └── ai.list            🤖 人工智能 策略组的规则集
│   └── starts/                上游启动脚本全集（28 个文件；本仓只改其中 2 个）
└── ACL4SSR/
    ├── UPSTREAM.md            来源凭证：URL / SHA / license / 更新命令
    ├── LICENCE                上游 CC BY-SA 4.0 全文（未改）
    └── Clash/
        ├── config/ACL4SSR_Online_Full.ini   规则模板的 ACL4SSR 原版（血统起点）
        ├── *.list              本仓实际消费的 12 个规则列表
        └── Ruleset/*.list      本仓实际消费的 3 个规则列表
```
