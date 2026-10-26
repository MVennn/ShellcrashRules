#!/usr/bin/env python3
"""对比多个公开节点源（Clash YAML）的存活率与延迟。

做法：对每个源取同样的多样性样本（默认 45 条），复用 screen.py 的分批测试
流程推到路由器实测，测完立刻恢复原来的 proxies.yaml。

用法：
  python tools/public-nodes/evaluate.py
  python tools/public-nodes/evaluate.py --sample 45 --batch 45

注意：运行期间会重启 ShellCrash 几次；不要和每日筛选任务同时跑。
"""
from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
import time
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import screen  # noqa: E402
import uri_parse  # noqa: E402

ROOT = HERE.parents[1]
EVAL_DIR = ROOT / ".work" / "public-nodes" / "eval"

SOURCES = [
    (
        "ermaozi-reachable",
        "https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/reachable/clash.yml",
    ),
    (
        "ermaozi-all",
        "https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/clash.yml",
    ),
    (
        "epodonios",
        "https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_base64_Sub.txt",
    ),
    (
        "pawdroid",
        "https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub",
    ),
    (
        "ripaojiedian",
        "https://raw.githubusercontent.com/ripaojiedian/freenode/main/clash",
    ),
]


def fetch(url: str) -> str:
    proc = subprocess.run(
        ["curl", "-fsSL", "-m", "90", url],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
    )
    if proc.returncode != 0 or len(proc.stdout) < 1000:
        raise RuntimeError(f"fetch failed rc={proc.returncode} bytes={len(proc.stdout)}")
    return proc.stdout


def evaluate_source(
    name: str,
    url: str,
    sample_size: int,
    batch_size: int,
    settle: int,
    per_type: int,
    per_base: int,
) -> dict:
    screen.log(f"===== {name} =====")
    text = fetch(url)
    raw_nodes = None
    try:
        data = yaml.safe_load(text) or {}
        if isinstance(data, dict) and isinstance(data.get("proxies"), list):
            raw_nodes = data["proxies"]
    except yaml.YAMLError:
        pass
    if raw_nodes is None:
        raw_nodes = uri_parse.parse_subscription(text)
    if not isinstance(raw_nodes, list):
        screen.log(f"{name}: 格式不支持（既不是 Clash YAML 也不是 URI 列表），跳过")
        return {"name": name, "error": "unsupported format"}

    valid = [n for n in (screen.normalize_node(x) for x in raw_nodes) if n]
    pool = screen.select_pool(valid, per_type=per_type, per_base=per_base)
    sample = pool[:sample_size]
    screen.log(f"{name}: 原始 {len(raw_nodes)} → 合格 {len(valid)} → 池 {len(pool)} → 样本 {len(sample)}")
    if not sample:
        return {"name": name, "error": "empty sample"}

    original = screen.read_remote(screen.REMOTE_PROXIES)
    state = {"version": 1, "nodes": {}}
    try:
        results = screen.test_batches(
            sample,
            state,
            batch_size=batch_size,
            settle=settle,
            backup="",
            old_content=original,
        )
    finally:
        # 不管测试结果如何，都恢复现有的兜底节点
        screen.write_remote(screen.REMOTE_PROXIES, original)
        screen.restart_core(settle)

    alive = [n for n in sample if results.get(screen.fingerprint(n), {}).get("alive")]
    delays = sorted(results[screen.fingerprint(n)]["delay"] for n in alive)
    types = {}
    for n in alive:
        types[n.get("type")] = types.get(n.get("type"), 0) + 1
    alive_nodes = [
        {
            "type": n.get("type"),
            "server": n.get("server"),
            "port": n.get("port"),
            "delay": results[screen.fingerprint(n)]["delay"],
        }
        for n in alive
    ]
    for item in alive_nodes:
        screen.log(f"  {item['type']:8} {item['server']}:{item['port']} {item['delay']}ms")
    summary = {
        "name": name,
        "raw": len(raw_nodes),
        "valid": len(valid),
        "pool": len(pool),
        "sample": len(sample),
        "alive": len(alive),
        "survival": round(len(alive) / len(sample) * 100, 1) if sample else 0,
        "min_delay": delays[0] if delays else None,
        "median_delay": int(statistics.median(delays)) if delays else None,
        "max_delay": delays[-1] if delays else None,
        "types": types,
        "alive_nodes": alive_nodes,
    }
    screen.log(
        f"{name}: 存活 {summary['alive']}/{summary['sample']} "
        f"({summary['survival']}%) 延迟 "
        f"{summary['min_delay']}/{summary['median_delay']}/{summary['max_delay']} ms"
    )
    return summary


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="对比公开节点源")
    parser.add_argument("--sample", type=int, default=120, help="每个源测试多少条")
    parser.add_argument("--batch", type=int, default=45, help="每批加载多少条")
    parser.add_argument("--settle", type=int, default=25, help="重启后等待秒数")
    parser.add_argument("--per-type", type=int, default=60, help="每个协议最多取多少条进池")
    parser.add_argument("--per-base", type=int, default=2, help="每个 IP /24 或根域最多取多少条")
    parser.add_argument("--only", default="", help="逗号分隔，只跑指定源（名称见 SOURCES）")
    args = parser.parse_args()

    EVAL_DIR.mkdir(parents=True, exist_ok=True)
    # 隔离状态/日志，不污染每日筛选的数据
    screen.WORK = EVAL_DIR
    screen.LOG_FILE = EVAL_DIR / "evaluate.log"
    screen.STATE_FILE = EVAL_DIR / "state.json"

    only = {x.strip() for x in args.only.split(",") if x.strip()}
    summaries = []
    # 评测期间要反复 start.sh restart；看门狗并发会触发双实例/配置回退事故
    # （见 screen.pause_watchdogs 的注释）。与 screen.run 保持同一口径。
    paused = False
    try:
        screen.pause_watchdogs()
        paused = True
    except Exception as exc:  # noqa: BLE001 - 暂停失败不终止评测，但要留痕
        screen.log(f"WARN: 暂停看门狗失败，评测可能与看门狗抢重启: {exc}")

    try:
        for name, url in SOURCES:
            if only and name not in only:
                continue
            try:
                summaries.append(
                    evaluate_source(
                        name,
                        url,
                        args.sample,
                        args.batch,
                        args.settle,
                        args.per_type,
                        args.per_base,
                    )
                )
            except Exception as exc:  # noqa: BLE001 - 单个源失败不影响其它源
                screen.log(f"{name}: 失败 {exc}")
                summaries.append({"name": name, "error": str(exc)})
    finally:
        if paused:
            try:
                screen.resume_watchdogs()
            except Exception as exc:  # noqa: BLE001 - 恢复失败必须让人看到
                screen.log(f"ERROR: 恢复看门狗失败，请手动把备份拷回 crontab: {exc}")

    print("\n=== 对比结果 ===")
    print(json.dumps(summaries, ensure_ascii=False, indent=2))
    (EVAL_DIR / "summary.json").write_text(
        json.dumps(summaries, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
