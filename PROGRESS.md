# PROGRESS —— AI 接口「Beam 挂」修复（2026-10-27）

> **一句话**：`opencode.ai` 间歇 502 的根因是 `🤖 AI接口` 吃 mihomo 默认 300s 复测间隔；
> 已把该组压到 60s、给守护加数据面探活、把 zgate 握手超时收到 8s 并全部部署验证。

状态: 已完成

## 目标

机器人侧调用 `opencode.ai` 偶发 15s TLS 握手超时 → 502 → 回落 WorkBuddy 免费池
（429/503）→ 单次回复拖到 22–32s。根因在路由器 `🤖 AI接口`（url-test）的复测间隔：
没写 `interval`，吃 mihomo 默认 300s，坏节点最长在位 5 分钟。

## 步骤

- [x] 定位：客户端 / 路由器 / 节点三方对照，排除 fake-IP、DNS、conntrack、内存、Wi-Fi 丢包
- [x] ShellcrashRules：`config/yamls/proxy-groups.yaml` 给 `🤖 AI接口` 加
      `interval: 60` + `timeout: 5000`
- [x] 部署到路由器 `/etc/ShellCrash/yamls/proxy-groups.yaml`（备份在 `/root/backup/`），
      用 `task.sh hotupdate` 热重载（不重启服务）
- [x] 验证 live 配置里 `interval: 60`；之后客户端 35/35、路由器 35/35 全 200（TLS 0.31–0.41s）
- [x] AX3000TOpenwrt：`guardian/guardian.sh` 新增 2.4 段「AI API 数据面探活」，只告警不切组
- [x] 部署 guardian 并手工跑一轮：rc=0，无误报
- [x] ZcodeAIModels：`gateways/zgate/main.go` `TLSHandshakeTimeout` 15s → 8s，重建并重启
- [x] 验证 zgate `/health` 200、WB 子进程 200、经 zgate 打 OC `/v1/models` 200（0.9s）
- [x] 文档：三仓 CHANGELOG `[未发布]` 段 + `docs/PITFALLS.md` 条目

## 遗留 / 已知

- 坏窗口是**间歇性**的：同一批 LA 节点复测仍是 300–368ms，所以没有永久剔除，
  只把最长暴露从 5 分钟压到 1 分钟。
- zgate 没有整体 `Timeout`（会截断流式响应），只压了握手阶段；非流式长推理若真的
  「接受连接后不回包」，仍只能靠调用方超时。
- 路由器上保留的回退件：`/root/backup/proxy-groups.yaml.<时间戳>`、
  `/root/backup/guardian.sh.<时间戳>`；PC 上保留 `zgate.exe.prev`。
