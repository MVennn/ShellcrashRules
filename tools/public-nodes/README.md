# 公开节点筛选器（PC 侧）

> **一句话**：定期拉取 AutoMergePublicNodes 的公开节点，在本地过滤后推到路由器
> 用 mihomo 实测，只把存活节点留在 `🆓 公共备用` 组里。

## 为什么在 PC 上跑

路由器是 OpenWrt + BusyBox，没有 Python/PyYAML；而筛选需要解析 400+ 条 YAML、
做协议/网段去重、分批调用 mihomo API。把这些放在 PC 上跑，路由器只负责
「加载候选 → 健康检查 → 回报结果」，不增加常驻依赖。

## 前置条件

- PC：Python 3.10+，已安装 `PyYAML`（`python -c "import yaml"` 通过）。
- PC 能免密 SSH 到路由器：`ssh -o BatchMode=yes root@10.0.0.1 echo ok`。
  （默认 `root@10.0.0.1`，可用环境变量 `ROUTER_SSH` 覆盖。）
- 路由器上已有 `🆓 公共备用` 组（`config/yamls/proxy-groups.yaml`）。

## 用法

```bash
# 只看会测哪些节点，不碰路由器
python tools/public-nodes/screen.py --dry-run

# 首次全量：把「未测过 + 现有存活」都扫一遍（约 3-5 分钟，会重启 3-4 次）
# 注意：已判 dead 且还在 3 天冷却期内的节点仍会跳过。
python tools/public-nodes/screen.py --full

# 日常增量：只测现有存活 + 新节点 + 冷却到期的死节点
python tools/public-nodes/screen.py

# 调参
python tools/public-nodes/screen.py --max-new 120 --max-keep 8 --batch-size 45 --settle 25
```

- `--batch-size`：每批加载多少条。路由器内存有限，默认 50，别轻易超过 60。
- `--settle`：重启后等健康检查的秒数，默认 25。
- `--max-keep`：最终最多保留多少条存活节点，默认 8。
- `--max-delay`：延迟超过多少毫秒不保留，默认 1500；用来剔掉“能连但很慢”的节点。

想强制重测所有 dead 节点（忽略冷却），删掉状态文件再跑：

```bash
rm -f .work/public-nodes/state.json
python tools/public-nodes/screen.py --full
```

## 对比多个源

`evaluate.py` 用同一批大小、同一台路由器实测多个源，测完自动恢复现有兜底节点：

```bash
python tools/public-nodes/evaluate.py --only ermaozi-reachable,epodonios --sample 120
python tools/public-nodes/evaluate.py --only pawdroid,ripaojiedian --sample 120
```

`uri_parse.py` 负责把 Base64/V2Ray URI 订阅（vless/vmess/trojan/ss/hysteria2）
转成 Clash 节点；`evaluate.py` 会自动识别 Clash YAML 或 URI 列表。

2026-10-21 的对比结果（当前网络）：

| 源 | 原始/合格 | 样本 | 存活 | 存活率 | 延迟（min/median/max） |
|---|---|---|---|---|---|
| NoMoreWalls（当前） | 442 / 319 | 110（全量） | 5 | **4.5%** | 298 / 452 / 528 ms |
| ermaozi reachable | 444 / 310 | 120 | 3 | 2.5% | 228 / 443 / 3476 ms |
| Epodonios | 6961 / 6952 | 120 | 3 | 2.5% | 423 / 447 / 491 ms |
| Pawdroid | 20 / 19 | 9 | 2 | 22%（样本太小） | 421 / 959 / 1498 ms |
| ripaojiedian | 14 / 14 | 4 | 0 | 0% | — |

结论：没有明显更优的源。NoMoreWalls 的存活率最高，当前 4 条兜底节点不变；
Epodonios 池子大但存活率同水平，适合以后需要更多数量时再做全量；
ripaojiedian 已过期（最后更新 2026-09-30）。

## 它做了什么

1. 从多个镜像拉取 `list.meta.yml`；
2. 过滤：只留 `vless/vmess/trojan/ss/hysteria2`，去掉诱饵、私网地址、
   占位 UUID、含 `#` 的字段（会被 `clash_modify.sh` 的 sed 截断）；
3. 去重 + 按协议/根域限流，按协议轮转排序；
4. 分批写入路由器 `/etc/ShellCrash/yamls/proxies.yaml` 的
   `# >>> PUBLIC-NODES` 标记块，`start.sh restart` 后用 mihomo API 读存活/延迟；
5. 把每轮结果写进 `.work/public-nodes/state.json`：
   - `alive` 下轮继续复测；
   - `dead` 冷却 3 天，期间不再测；
   - 45 天没在源里出现的条目自动清理；
6. 最终只保留存活节点；如果全部失效，保留旧配置不动。

日常增量如果只剩「复测现有节点」，会直接调 mihomo 的组延迟 API，
**不重载配置、不重启**；只有发现失效节点时才重写并重启。

## 状态与日志

- `.work/public-nodes/state.json`：节点指纹 → 存活/死亡、延迟、失败次数。
- `.work/public-nodes/screen.log`：每次运行的结构化日志。
- `.work/public-nodes/task.log`：计划任务的 stdout/stderr。

这两个目录都在 `.gitignore` 里（`/.work/`），不会入库。

## 定时任务（Windows）

创建每天 05:10（仅登录时）运行的增量任务：

```cmd
cd /d <仓库根>
schtasks /Create /TN "ShellcrashRules-PublicNodes" ^
  /TR "\"%CD%\tools\public-nodes\run-daily.cmd\"" ^
  /SC DAILY /ST 05:10 /IT /F
```

查看/手动触发：

```cmd
schtasks /Query /TN "ShellcrashRules-PublicNodes" /V /FO LIST
schtasks /Run /TN "ShellcrashRules-PublicNodes"
```

删除：

```cmd
schtasks /Delete /TN "ShellcrashRules-PublicNodes" /F
```

> 计划任务只在用户登录时跑；PC 关机/休眠错过的那次不会补跑。
> 需要补跑时手动执行 `run-daily.cmd` 或上面的 `python ...` 命令。
> 不要并发跑两个实例（会同时改路由器的 `proxies.yaml`）。

## 回滚

每次要写路由器前会备份，并在路由器上只保留最近 20 份（flash 有限）：

```
/etc/ShellCrash/yamls/proxies.yaml.bak-public-screen-<时间戳>
```

回滚：

```bash
ssh root@10.0.0.1 '
  cp /etc/ShellCrash/yamls/proxies.yaml.bak-public-screen-<时间戳> \
     /etc/ShellCrash/yamls/proxies.yaml
  sh /etc/ShellCrash/start.sh restart
'
```

## 安全边界

- 公开节点由陌生人运营，可能记录/篡改流量；**只用于机场全挂时的网页兜底**。
- `🆓 公共备用` 挂在 `🚀 节点选择` 末尾，**手动切换**；默认项仍是 `♻️ 自动选择`。
- `🤖 AI接口` / `🤖 AI网页` / `🤖 干净出口` 的 `exclude-filter` 已包含 `公共`，
  自动组不会把公开节点选走。改这些组时别把 `公共` 删掉。
