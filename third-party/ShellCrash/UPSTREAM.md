# ShellCrash —— 来源凭证

> **一句话**：ShellCrash 是本仓透明代理框架的**派生源** —— 本仓
> `config/starts/fw_nftables.sh` 与 `config/starts/start_legacy_wd.sh` 是上游
> `starts/` 同名脚本的**打补丁派生件**，本目录保存这两个脚本的**上游原版**
> （一个字节未改），供随时比对补丁点、判定派生关系。

---

## 1. 上游坐标

| 项 | 值 |
|---|---|
| 项目名 | ShellCrash |
| 上游仓库 | https://github.com/juewuy/ShellCrash |
| 注意 | `https://github.com/jucase/ShellCrash` **不存在**（GitHub API 返回 404）；`juewuy/ShellCrash` 才是真实地址。`juewuy/ShellClash` 是同一仓库的旧名/别名，GitHub 会 301 重定向到 `ShellCrash` |
| 默认分支 | `dev`（另有 `master` / `stable` / `rm` / `update` 分支） |
| vendored commit | `de1d9e20f71a77e794519d1c42d713253714f2e5` |
| commit 提交时间 | 2026-08-27T12:12:45+08:00（`git log -1 --format=%cI`；提交信息 `Merge pull request #1336 from Maozai-Teng/dev`） |
| 仓库最近一次 push | 2026-10-19T18:18:24Z（GitHub API `pushed_at`；指任意分支的最近 push，**不等于** `dev` 分支头的提交时间） |
| 上游版本号 | `1.9.5beta3`（见本目录 `version`，取自该 commit 的 `version` 文件） |
| Star 数 | 13604（GitHub API，2026-10-20 21:12 UTC+8 实测） |
| 仓库体积（GitHub API `size` 字段） | **5346820 KB**（约 5.1 GB） |
| License | **GPL-3.0**（GitHub API `license.spdx_id = "GPL-3.0"`） |
| License 全文 | 本目录 [`LICENSE.txt`](LICENSE.txt)（上游原文件，未改一字） |
| clone 时间 | 2026-10-20 20:40 UTC+8 |

> **仓库体积为什么是 5.1 GB**：上游把 `bin/` 下每个架构的 crashcore / sing-box 预编译包
> （`bin/meta/*.tar.gz`、`bin/singboxp/*.tar.gz` 等 20 余个归档）**连同历史提交**
> 一起放在同一个 git 仓库里，`size` 字段统计的是**全部历史对象**的体积。
> 因此本仓**不 vendor 上游整仓**，只 vendor 与本仓有代码级关系的那一小部分
> （见 §4），vendor 进来的实际体积见下表。

---

## 2. 与本仓的关系：**派生源（derivative）**

本仓对上游做了两类改动，两类都在 `config/starts/` 下，**不在** `third-party/`：

### 2.1 打补丁派生件（本仓的产物，留在 `config/starts/`）

| 本仓文件 | 上游原版（本目录） | 关系 |
|---|---|---|
| `config/starts/fw_nftables.sh` | [`starts/fw_nftables.sh`](starts/fw_nftables.sh) | 打补丁派生件，保留上游 GPL-3.0 版权头 `Copyright (C) Juewuy` |
| `config/starts/start_legacy_wd.sh` | [`starts/start_legacy_wd.sh`](starts/start_legacy_wd.sh) | 打补丁派生件，保留上游版权头与原有结构 |

补丁点清单（`diff -u third-party/ShellCrash/starts/X.sh config/starts/X.sh` 可复现）：

**`fw_nftables.sh` —— 3 处**

| 标记 | 位置 | 改了什么 | 为什么 |
|---|---|---|---|
| `FCM_DOQ_PORT_MARKER` | `start_nft_route()` 开头 | 代理端口集由 `$multiport` 改为 `"$multiport,5228,19302"` | 把 Google FCM(5228)/DoQ(19302) 纳入代理端口，否则真实 IP 目标会直连、暴露国内出口 |
| `CN_IP_EXCLUDE_203208` | `#绕过CN-IP` 段 | `awk '{printf "%s, ",$1}'` → `awk '$1 != "203.208.32.0/19" {printf "%s, ",$1}'` | 剔除 Google 国内边缘段，否则 gstatic/gvt1 等以中国出口访问、Google 判定为中国区 |
| `QUIC_BLOCK_MARKER` | IPv6 分支之后、`#屏蔽quic` 之前 | 新增一行 `udp dport {443, 8443} counter reject with icmpx type port-unreachable` | 境外 QUIC 真正 reject，而不是仅 `return` —— 否则 HTTP/3 仍带国内出口 IP 直连逃逸 |

**`start_legacy_wd.sh` —— 1 处（3 个 hunk）**

| 标记 | 改了什么 | 为什么 |
|---|---|---|
| `mkdir -p /tmp/ShellCrash` | 上游 `mkdir "$LOCKDIR" \|\| exit 1` → 先 `mkdir -p /tmp/ShellCrash` 再建锁目录 | `/tmp` 在 tmpfs 上，重启后整个目录不存在，锁目录永远建不出来，看门狗每分钟 exit 1，代理再也拉不起来（2026-10-20 09:36 实测离线 6 分钟） |
| 陈旧锁自愈 | 锁目录存在时先比对 `stat -c %Y`，超过 300 秒则 `rm -fr` 后重建 | 上次运行被中断会残留锁，导致看门狗永久失效 |
| 进程存活早退 | 新增 `[ "$1" = "shellcrash" ] && [ -n "$(pidof CrashCore)" ]` → 删锁退出 | pid 文件在 tmpfs，重启即丢，上游逻辑会误判「没有进程」从而 stop 掉一个健康运行的代理 |

### 2.2 本仓依赖、但未修改的上游文件（本目录 vendor）

| 本目录文件 | 上游路径 | 本仓怎么用它 |
|---|---|---|
| [`rules/ShellClash.ini`](rules/ShellClash.ini) | `rules/ShellClash.ini`（commit `de1d9e2`） | **设备侧正在用的规则模板**。ShellCrash 的 `servers.list` 第 501 行 `Acl4SSR全能优化版` 即此文件，本仓 `rule_link=1` 选中的就是它。`config/hooks/rules-mid.sh` 正是在它生成的规则序列上插入 CN 中间层 |
| [`rules/ai.list`](rules/ai.list) | `rules/ai.list` | `🤖 人工智能` 策略组的规则集来源（模板里 `ruleset=🤖 人工智能,.../ShellClash/master/rules/ai.list`） |
| [`starts/`](starts/) 全目录 | 归档 `ShellCrash.tar.gz` 内的 `starts/` | 上游启动脚本全集。本仓只改其中 2 个（见 §2.1）；`starts/clash_modify.sh` 是本仓全部 `yamls/` 扩展点与两个钩子的挂载入口 |

> **上游布局的一个坑**：上游 git 树里**没有** `starts/` 目录 —— 运行时目录被打包成
> 仓库根的 `ShellCrash.tar.gz`（本 commit 为 177958 字节，
> sha256 `771027462e5386a78071595ae396653a9beb4ede2428474a2cbff95c3f5805c5`）提交。
> 所以 `starts/` 的上游定位符是
> `https://github.com/juewuy/ShellCrash/raw/de1d9e20f71a77e794519d1c42d713253714f2e5/ShellCrash.tar.gz`
> 解包后的 `starts/`。

---

## 3. 本目录 vendored 了什么

| 路径 | 上游来源 | 字节 |
|---|---|---|
| `LICENSE.txt` | `LICENSE.txt` | 35149 |
| `version` | `version` | 11 |
| `rules/ShellClash.ini` | `rules/ShellClash.ini` | 5699 |
| `rules/ai.list` | `rules/ai.list` | 580 |
| `starts/`（28 个文件） | `ShellCrash.tar.gz` 内的 `starts/` | 107474 字节 |

- **vendor 进来的实际体积：上游内容 148 913 字节 / 32 个文件**；连同本 `UPSTREAM.md` 后
  `du -sk third-party/ShellCrash` = 217 KB（含 4 KB 块对齐）
- **上游代码一个字节未改**：所有文件逐字节 `diff` 与上游克隆结果一致
- 上游原有的 LICENSE 与版权头（`# Copyright (C) Juewuy`）原样保留

**关键校验值（sha256）**

```
156109641001b7392e98699958523cde449da24152d8b3badba955959d6d83c9  starts/fw_nftables.sh
01ae0cae4f1ea33b66795bdcc880c93bb8a3ea09fae8ce9481e85c1cbb7fc93e  starts/start_legacy_wd.sh
```

---

## 4. 为什么 vendor 这一部分

| 判定条件 | 结论 |
|---|---|
| 与本仓有**代码级**关系 | ✅ 本仓改的正是它的 `starts/fw_nftables.sh` 与 `starts/start_legacy_wd.sh`；本仓的 `rules-mid.sh` 又是按它 `rules/ShellClash.ini` 的规则顺序插入 |
| 体积 < 5 MB | ✅ vendor 进来的上游内容 **148 913 字节（约 145 KiB，32 个文件）**（上游整仓 5.1 GB，故只取相关子集，不取整仓） |
| license 允许再分发 | ✅ GPL-3.0，允许再分发；本仓整体亦按 GPL-3.0 发布 |

---

## 5. 怎么更新

```bash
# 1) 浅克隆（不要 --recursive：上游本仓不拉 submodule）
git clone --depth 1 --branch dev https://github.com/juewuy/ShellCrash.git /tmp/sc-upstream
cd /tmp/sc-upstream && git rev-parse HEAD        # 记下新的 commit SHA

# 2) 解出运行时目录（starts/ 在归档里）
mkdir -p /tmp/sc-extract && tar -xzf ShellCrash.tar.gz -C /tmp/sc-extract

# 3) 逐项比对，只在上游**没有**改动本仓补丁点的前提下才更新
diff -u /tmp/sc-extract/starts/fw_nftables.sh  third-party/ShellCrash/starts/fw_nftables.sh
diff -u /tmp/sc-extract/starts/start_legacy_wd.sh third-party/ShellCrash/starts/start_legacy_wd.sh
diff -u /tmp/sc-upstream/rules/ShellClash.ini   third-party/ShellCrash/rules/ShellClash.ini
diff -u /tmp/sc-upstream/rules/ai.list          third-party/ShellCrash/rules/ai.list

# 4) 复制（覆盖前先备份；不要跳过 diff —— 直接覆盖会把本仓补丁点的基线冲掉）
cp -p /tmp/sc-extract/starts/*.sh /tmp/sc-extract/starts/README.md third-party/ShellCrash/starts/
cp -p /tmp/sc-upstream/rules/ShellClash.ini /tmp/sc-upstream/rules/ai.list third-party/ShellCrash/rules/
cp -p /tmp/sc-upstream/LICENSE.txt /tmp/sc-upstream/version third-party/ShellCrash/

# 5) 同步本仓的派生件：把上游新增内容合进 config/starts/ 的两个补丁版
diff -u third-party/ShellCrash/starts/fw_nftables.sh config/starts/fw_nftables.sh
diff -u third-party/ShellCrash/starts/start_legacy_wd.sh config/starts/start_legacy_wd.sh

# 6) 更新本文件里的 commit SHA / 日期 / 体积，然后同步 third-party/README.md、
#    仓库根 NOTICE、README.md「开源鸣谢」、docs/UPSTREAM.md
```

> 上游 `dev` 分支随时在动（`bin/` 下每次发版都会换二进制），**升级前必须先跑第 3 步的
> diff**：只看 SHA 变了就覆盖，会把本仓三个 nft 补丁点与看门狗自愈逻辑一起冲掉。
