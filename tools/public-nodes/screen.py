#!/usr/bin/env python3
"""公开节点筛选器（PC 侧执行）。

流程：
  1. 拉取 AutoMergePublicNodes 的 list.meta.yml（多个镜像兜底）；
  2. 本地过滤：协议白名单、去诱饵、去重、按协议/网段限流；
  3. 分批推到路由器 /etc/ShellCrash/yamls/proxies.yaml，重启 ShellCrash
     让 mihomo 的健康检查实测每条节点；
  4. 只保留本轮存活的节点，其余记为 dead，进入冷却期；
  5. 下次只测「存活 + 从未见过 + 冷却期已过」的节点，避免重复测死节点。

路由器上没有 Python，所以本脚本在 PC 上跑；只通过 ssh/scp 读写
/etc/ShellCrash/yamls/proxies.yaml，不改动仓库里的任何文件。

用法：
  python tools/public-nodes/screen.py --dry-run      # 只看会测哪些，不碰路由器
  python tools/public-nodes/screen.py --full         # 首次全量扫（约 3-5 分钟）
  python tools/public-nodes/screen.py                # 日常增量（默认最多 100 条）
  python tools/public-nodes/screen.py --max-keep 6 --batch-size 40

状态与日志在 .work/public-nodes/（已 gitignore）。
"""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import os
import shlex
import subprocess
import sys
import time
import urllib.parse
from datetime import datetime
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / ".work" / "public-nodes"
STATE_FILE = WORK / "state.json"
LOG_FILE = WORK / "screen.log"

ROUTER = os.environ.get("ROUTER_SSH", "root@10.0.0.1")
REMOTE_YAMLS = "/etc/ShellCrash/yamls"
REMOTE_PROXIES = f"{REMOTE_YAMLS}/proxies.yaml"
REMOTE_RUNTIME = "/tmp/ShellCrash/config.yaml"
REMOTE_SECRET_CFG = "/etc/ShellCrash/configs/ShellCrash.cfg"
API = "http://127.0.0.1:9999"

MARK_START = "# >>> PUBLIC-NODES"
MARK_END = "# <<< PUBLIC-NODES <<<"
NAME_PREFIX = "🆓 公共"

SOURCES = [
    "https://raw.githubusercontent.com/chengaopan/AutoMergePublicNodes/master/list.meta.yml",
    "https://cdn.jsdelivr.net/gh/chengaopan/AutoMergePublicNodes@master/list.meta.yml",
    "https://ghproxy.cn/https://raw.githubusercontent.com/chengaopan/AutoMergePublicNodes/master/list.meta.yml",
]

WHITELIST = {"vless", "vmess", "trojan", "ss", "hysteria2"}
PLACEHOLDER_UUID_PREFIX = "88888888-"

DEAD_COOLDOWN = 3 * 86400       # 死节点 3 天内不再测
STATE_TTL = 45 * 86400          # 45 天没在源里出现就清掉状态

_secret_cache: str | None = None


# --------------------------------------------------------------------------
# 基础 IO
# --------------------------------------------------------------------------
def log(msg: str) -> None:
    line = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    WORK.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def ssh(cmd: str, *, stdin: str | None = None, timeout: int = 120, check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", ROUTER, cmd],
        input=stdin,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    if check and proc.returncode != 0:
        raise RuntimeError(f"ssh failed ({proc.returncode}): {cmd}\n{proc.stderr[-800:]}")
    return proc


def read_remote(path: str) -> str:
    return ssh(f"cat {shlex.quote(path)}").stdout


def write_remote(path: str, content: str) -> None:
    tmp = f"/tmp/public-nodes-screen-{os.getpid()}.tmp"
    ssh(f"cat > {tmp} && mv {tmp} {shlex.quote(path)}", stdin=content, timeout=60)


def fetch_source() -> tuple[str, str]:
    WORK.mkdir(parents=True, exist_ok=True)
    last_err = ""
    for url in SOURCES:
        try:
            proc = subprocess.run(
                ["curl", "-fsSL", "-m", "60", url],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=90,
            )
            if proc.returncode == 0 and len(proc.stdout) > 10_000:
                return url, proc.stdout
            last_err = f"{url}: rc={proc.returncode} bytes={len(proc.stdout)}"
        except Exception as exc:  # noqa: BLE001 - 逐个镜像兜底
            last_err = f"{url}: {exc}"
        log(f"镜像失败：{last_err}")
    raise RuntimeError(f"所有源都拉取失败：{last_err}")


# --------------------------------------------------------------------------
# 节点过滤
# --------------------------------------------------------------------------
def _is_public_server(server: str) -> bool:
    try:
        ip = ipaddress.ip_address(server)
    except ValueError:
        return "." in server and " " not in server and len(server) <= 253
    return not (ip.is_private or ip.is_loopback or ip.is_reserved or ip.is_multicast or ip.is_unspecified)


def _has_hash(value) -> bool:
    if isinstance(value, str):
        return "#" in value
    if isinstance(value, list):
        return any(_has_hash(v) for v in value)
    if isinstance(value, dict):
        return any(_has_hash(k) or _has_hash(v) for k, v in value.items())
    return False


def normalize_node(raw) -> dict | None:
    """返回可安全写入 flow YAML 的节点；不合格返回 None。"""
    if not isinstance(raw, dict):
        return None
    node = dict(raw)
    typ = node.get("type")
    server = str(node.get("server") or "").strip()
    port = node.get("port")

    if typ not in WHITELIST:
        return None
    if not server or not _is_public_server(server):
        return None
    try:
        port = int(port)
    except (TypeError, ValueError):
        return None
    if not 1 <= port <= 65535:
        return None
    node["port"] = port
    node["server"] = server

    if typ in ("vless", "vmess"):
        uuid = str(node.get("uuid") or "")
        if not uuid or uuid.startswith(PLACEHOLDER_UUID_PREFIX):
            return None
    elif typ in ("trojan", "ss", "hysteria2"):
        if not (node.get("password") or node.get("auth") or node.get("auth-str")):
            return None
        if typ == "ss" and not node.get("cipher"):
            return None

    # name 稍后会统一改成 `🆓 公共-NN`，源里的 # 不影响写入；
    # 其余字段若含 #，会被 clash_modify.sh 的 sed 's/#.*/.../' 截断，直接丢弃。
    node.pop("name", None)
    if _has_hash(node):
        return None

    try:
        line = yaml.safe_dump(
            node,
            allow_unicode=True,
            sort_keys=True,
            default_flow_style=True,
            width=100000,
        ).strip()
    except yaml.YAMLError:
        return None
    if not line.startswith("{") or "\n" in line or "#" in line:
        return None
    if len(line) > 4000:
        return None
    return node


def fingerprint(node: dict) -> str:
    parts = [
        str(node.get("type")),
        str(node.get("server", "")).lower(),
        str(node.get("port")),
        str(node.get("uuid") or node.get("password") or node.get("auth") or node.get("auth-str") or ""),
        str(node.get("network") or ""),
    ]
    return hashlib.sha1("|".join(parts).encode("utf-8")).hexdigest()[:16]


def basekey(node: dict) -> str:
    """用于多样性：IP 取 /24，域名取最后两段；优先用 SNI。"""
    for value in (node.get("sni"), node.get("servername"), node.get("server")):
        if not value:
            continue
        value = str(value).lower()
        try:
            ip = ipaddress.ip_address(value)
            return ".".join(str(ip).split(".")[:3]) if ip.version == 4 else str(ip)
        except ValueError:
            parts = value.split(".")
            if len(parts) >= 2:
                return ".".join(parts[-2:])
            return value
    return ""


def select_pool(nodes: list[dict], per_type: int, per_base: int) -> list[dict]:
    seen: set[str] = set()
    type_count: dict[str, int] = {}
    base_count: dict[str, int] = {}
    out: list[dict] = []
    for node in nodes:
        fp = fingerprint(node)
        if fp in seen:
            continue
        typ = str(node.get("type"))
        bk = basekey(node)
        if type_count.get(typ, 0) >= per_type:
            continue
        if bk and base_count.get(bk, 0) >= per_base:
            continue
        seen.add(fp)
        type_count[typ] = type_count.get(typ, 0) + 1
        if bk:
            base_count[bk] = base_count.get(bk, 0) + 1
        out.append(node)

    # 按协议轮转排序：保证前几批覆盖所有协议，而不是先被 hysteria2 占满。
    groups: dict[str, list[dict]] = {}
    for node in out:
        groups.setdefault(str(node.get("type")), []).append(node)
    order = ["vless", "vmess", "trojan", "ss", "hysteria2"]
    ordered: list[dict] = []
    while any(groups.get(t) for t in order):
        for typ in order:
            bucket = groups.get(typ) or []
            if bucket:
                ordered.append(bucket.pop(0))
    return ordered


# --------------------------------------------------------------------------
# 状态
# --------------------------------------------------------------------------
def load_state() -> dict:
    if not STATE_FILE.exists():
        return {"version": 1, "nodes": {}}
    try:
        state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        if not isinstance(state, dict) or not isinstance(state.get("nodes"), dict):
            raise ValueError("bad state shape")
        return state
    except Exception as exc:  # noqa: BLE001 - 状态坏了就重建，不阻断筛选
        log(f"状态文件损坏，重建：{exc}")
        try:
            STATE_FILE.replace(STATE_FILE.with_suffix(".json.bad"))
        except OSError:
            pass
        return {"version": 1, "nodes": {}}


def save_state(state: dict) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(STATE_FILE)


def update_state(state: dict, node: dict, *, alive: bool, delay: int | None, now: int) -> None:
    fp = fingerprint(node)
    old = state["nodes"].get(fp, {})
    state["nodes"][fp] = {
        "status": "alive" if alive else "dead",
        "last_checked": now,
        "last_seen": now,
        "fail_count": 0 if alive else int(old.get("fail_count", 0)) + 1,
        "delay": delay,
        "type": node.get("type"),
        "server": node.get("server"),
        "port": node.get("port"),
        "name": node.get("name"),
    }


def prune_state(state: dict, now: int) -> None:
    for fp, info in list(state["nodes"].items()):
        if now - int(info.get("last_seen", 0)) > STATE_TTL:
            del state["nodes"][fp]


# --------------------------------------------------------------------------
# 路由器侧：写节点块 / 重启 / 读 API
# --------------------------------------------------------------------------
def make_block(nodes: list[dict], prefix: str) -> tuple[str, list[dict]]:
    """生成带标记的 flow YAML 块；prefix 为空时用 公共-01，否则 公共-T01。"""
    lines = [MARK_START + " (auto-generated by tools/public-nodes/screen.py, do not edit) >>>"]
    kept: list[dict] = []
    for idx, node in enumerate(nodes, 1):
        node = dict(node)
        node["name"] = f"{NAME_PREFIX}-{prefix}{idx:02d}" if prefix else f"{NAME_PREFIX}-{idx:02d}"
        line = yaml.safe_dump(
            node,
            allow_unicode=True,
            sort_keys=True,
            default_flow_style=True,
            width=100000,
        ).strip()
        if line.endswith("..."):
            line = line[:-3].strip()
        if not line.startswith("{") or "\n" in line or "#" in line:
            log(f"跳过无法序列化的节点：{node.get('type')} {node.get('server')}:{node.get('port')}")
            continue
        lines.append("- " + line)
        kept.append(node)
    lines.append(MARK_END)
    return "\n".join(lines) + "\n", kept


def parse_existing(content: str) -> list[dict]:
    """读出路由器上当前标记块里的节点，确保它们每轮都被复测，不会因源更新而丢。"""
    out: list[dict] = []
    skipping = False
    for line in content.splitlines():
        if line.startswith(MARK_START):
            skipping = True
            continue
        if line.startswith(MARK_END):
            skipping = False
            continue
        if skipping and line.startswith("- "):
            try:
                node = yaml.safe_load(line[2:])
            except yaml.YAMLError:
                continue
            name = str(node.get("name") or "") if isinstance(node, dict) else ""
            node = normalize_node(node)
            if node:
                if name:
                    node["name"] = name
                out.append(node)
    return out


def dedup_nodes(nodes: list[dict]) -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for node in nodes:
        fp = fingerprint(node)
        if fp in seen:
            continue
        seen.add(fp)
        out.append(node)
    return out


def replace_block(content: str, block: str) -> str:
    out: list[str] = []
    skipping = False
    for line in content.splitlines():
        if line.startswith(MARK_START):
            skipping = True
            continue
        if line.startswith(MARK_END):
            skipping = False
            continue
        if not skipping:
            out.append(line)
    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out) + "\n\n" + block


def backup_remote(keep: int = 20) -> str:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    dst = f"{REMOTE_PROXIES}.bak-public-screen-{stamp}"
    ssh(f"cp {shlex.quote(REMOTE_PROXIES)} {shlex.quote(dst)}")
    # 路由器 flash 有限：只留最近 20 份
    ssh(
        f"for f in $(ls -1t {REMOTE_PROXIES}.bak-public-screen-* 2>/dev/null | "
        f"tail -n +{keep + 1}); do rm -f \"$f\"; done",
        check=False,
    )
    return dst


def prevalidate(block: str) -> tuple[bool, str]:
    """把候选块插进当前运行配置的 proxies 段，用 CrashCore -t 预检。"""
    runtime = read_remote(REMOTE_RUNTIME)
    if "proxy-groups:" not in runtime:
        return False, "运行配置里没有 proxy-groups:"
    lines = [line for line in runtime.splitlines() if f"{NAME_PREFIX}-" not in line]
    indented = ["  " + line for line in block.rstrip("\n").splitlines()]
    out: list[str] = []
    inserted = False
    for line in lines:
        if not inserted and line.startswith("proxy-groups:"):
            out.extend(indented)
            inserted = True
        out.append(line)
    if not inserted:
        return False, "未找到插入点"
    test_path = "/tmp/public-nodes-screen-test.yaml"
    write_remote(test_path, "\n".join(out) + "\n")
    proc = ssh(
        f"/tmp/ShellCrash/CrashCore -t -d /etc/ShellCrash -f {test_path}",
        timeout=90,
        check=False,
    )
    ssh(f"rm -f {test_path}", check=False)
    detail = (proc.stdout + proc.stderr).strip().splitlines()
    return proc.returncode == 0, detail[-1] if detail else ""


def restart_core(settle: int) -> bool:
    proc = ssh(
        "sh /etc/ShellCrash/start.sh restart >/tmp/sc-public-screen.log 2>&1",
        timeout=120,
        check=False,
    )
    if proc.returncode != 0:
        log(f"重启返回 {proc.returncode}")
        return False
    time.sleep(settle)
    tail = ssh("tail -3 /tmp/sc-public-screen.log", check=False).stdout.strip()
    if "校验失败" in tail:
        log(f"配置校验失败：{tail}")
        return False
    return True


def get_secret() -> str:
    global _secret_cache
    if _secret_cache:
        return _secret_cache
    line = ssh(f"grep -m1 '^secret=' {REMOTE_SECRET_CFG}").stdout.strip()
    _secret_cache = line.split("=", 1)[1].strip().strip("'\"") if "=" in line else ""
    return _secret_cache


def api_proxies() -> dict:
    secret = get_secret()
    cmd = (
        f"curl -s -m 20 -H {shlex.quote('Authorization: Bearer ' + secret)} "
        f"{API}/proxies"
    )
    for attempt in (1, 2):
        proc = ssh(cmd, timeout=40, check=False)
        try:
            data = json.loads(proc.stdout)
            if isinstance(data, dict) and isinstance(data.get("proxies"), dict):
                return data["proxies"]
        except json.JSONDecodeError:
            pass
        log(f"读取 /proxies 失败（第 {attempt} 次）")
        time.sleep(5)
    raise RuntimeError("mihomo API /proxies 读取失败")


def test_existing_direct(nodes: list[dict], state: dict) -> dict[str, dict] | None:
    """不重载配置，直接用组的 delay API 复测现有节点；失败返回 None。"""
    group = f"{NAME_PREFIX}备用"
    encoded = urllib.parse.quote(group, safe="")
    url = (
        f"{API}/group/{encoded}/delay?"
        "url=http%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=6000"
    )
    cmd = (
        f"curl -s -m 40 -H {shlex.quote('Authorization: Bearer ' + get_secret())} "
        f"{shlex.quote(url)}"
    )
    proc = ssh(cmd, timeout=60, check=False)
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict) or "message" in data:
        return None

    now = int(time.time())
    results: dict[str, dict] = {}
    for node in nodes:
        name = node.get("name")
        delay = int(data.get(name) or 0) if name else 0
        alive = delay > 0
        results[fingerprint(node)] = {"alive": alive, "delay": delay if alive else None}
        update_state(state, node, alive=alive, delay=delay if alive else None, now=now)
    save_state(state)
    return results


def runtime_public_count() -> int:
    out = ssh(f"grep -c {shlex.quote(NAME_PREFIX + '-')} {REMOTE_RUNTIME}", check=False).stdout.strip()
    try:
        return int(out)
    except ValueError:
        return 0


# --------------------------------------------------------------------------
# 分批实测
# --------------------------------------------------------------------------
def test_batches(
    nodes: list[dict],
    state: dict,
    *,
    batch_size: int,
    settle: int,
    backup: str,
    old_content: str,
) -> dict[str, dict]:
    results: dict[str, dict] = {}
    batches = [nodes[i : i + batch_size] for i in range(0, len(nodes), batch_size)]
    for bi, batch in enumerate(batches, 1):
        log(f"批次 {bi}/{len(batches)}：{len(batch)} 条")
        block, kept = make_block(batch, "T")
        if not kept:
            continue
        ok, detail = prevalidate(block)
        if not ok:
            log(f"批次 {bi} 预检失败，跳过：{detail}")
            continue
        content = read_remote(REMOTE_PROXIES)
        write_remote(REMOTE_PROXIES, replace_block(content, block))
        if not restart_core(settle):
            log(f"批次 {bi} 重启/校验失败，跳过")
            continue
        loaded = runtime_public_count()
        if loaded < max(1, len(kept) // 2):
            log(f"批次 {bi} 运行配置只加载了 {loaded}/{len(kept)} 条，跳过")
            continue
        data = api_proxies()
        now = int(time.time())
        alive_n = 0
        for idx, node in enumerate(kept, 1):
            name = node["name"]
            info = data.get(name) or {}
            history = info.get("history") or []
            delay = history[-1].get("delay") if history else None
            alive = bool(info.get("alive")) and bool(delay)
            results[fingerprint(node)] = {"alive": alive, "delay": delay if alive else None}
            update_state(state, node, alive=alive, delay=delay if alive else None, now=now)
            if alive:
                alive_n += 1
        save_state(state)
        log(f"批次 {bi} 存活 {alive_n}/{len(kept)}")
    return results


def pick_survivors(
    nodes: list[dict],
    results: dict[str, dict],
    max_keep: int,
    max_delay: int = 1500,
) -> list[dict]:
    alive = [
        n
        for n in nodes
        if results.get(fingerprint(n), {}).get("alive")
        and (results[fingerprint(n)].get("delay") or 10**9) <= max_delay
    ]
    alive.sort(key=lambda n: results[fingerprint(n)]["delay"])
    seen_base: dict[str, int] = {}
    seen_endpoint: set[tuple[str, int]] = set()
    type_count: dict[str, int] = {}
    out: list[dict] = []
    for node in alive:
        typ = str(node.get("type"))
        bk = basekey(node)
        endpoint = (str(node.get("server", "")).lower(), int(node.get("port", 0)))
        if endpoint in seen_endpoint:
            continue
        if type_count.get(typ, 0) >= 3:
            continue
        if bk and seen_base.get(bk, 0) >= 2:
            continue
        seen_endpoint.add(endpoint)
        type_count[typ] = type_count.get(typ, 0) + 1
        if bk:
            seen_base[bk] = seen_base.get(bk, 0) + 1
        out.append(node)
        if len(out) >= max_keep:
            break
    return out


# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------
def main() -> int:
    # Windows 下 stdout 被重定向到日志时默认用 GBK，统一成 UTF-8。
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="公开节点本地筛选器（PC 侧）")
    parser.add_argument("--full", action="store_true", help="全量扫描（默认增量 100 条）")
    parser.add_argument("--max-new", type=int, default=100, help="单轮最多测试多少条新节点")
    parser.add_argument("--max-keep", type=int, default=8, help="最终保留多少条存活节点")
    parser.add_argument("--max-delay", type=int, default=1500, help="延迟超过多少毫秒不保留（默认 1500）")
    parser.add_argument("--batch-size", type=int, default=50, help="每批加载多少条（内存友好）")
    parser.add_argument("--settle", type=int, default=25, help="重启后等待健康检查的秒数")
    parser.add_argument("--dry-run", action="store_true", help="只拉取和筛选，不碰路由器")
    args = parser.parse_args()

    WORK.mkdir(parents=True, exist_ok=True)
    log("=" * 60)
    log(f"开始：full={args.full} max_new={args.max_new} max_keep={args.max_keep} batch={args.batch_size}")

    url, text = fetch_source()
    log(f"源：{url}（{len(text)} bytes）")
    try:
        raw = yaml.safe_load(text) or {}
    except yaml.YAMLError as exc:
        log(f"YAML 解析失败：{exc}")
        return 1
    raw_nodes = raw.get("proxies") if isinstance(raw, dict) else None
    if not isinstance(raw_nodes, list):
        log("源里没有 proxies 列表")
        return 1

    valid = [n for n in (normalize_node(x) for x in raw_nodes) if n]

    state = load_state()
    now = int(time.time())
    prune_state(state, now)

    # 固定按源顺序取池，保证每轮的 pool 稳定；未测过的新节点会自然进入
    # fresh 列表，不需要靠重排抢配额。per_type/per_base 只做上限，防止
    # 单一协议或单一服务商刷屏。
    pool = select_pool(valid, per_type=100, per_base=2)
    log(f"原始 {len(raw_nodes)} 条 → 合格 {len(valid)} 条 → 多样性池 {len(pool)} 条")

    old_content = "" if args.dry_run else read_remote(REMOTE_PROXIES)
    existing = parse_existing(old_content) if old_content else []

    known_alive = dedup_nodes(
        existing
        + [n for n in pool if state["nodes"].get(fingerprint(n), {}).get("status") == "alive"]
    )
    seen_known = {fingerprint(n) for n in known_alive}
    fresh = [n for n in pool if fingerprint(n) not in state["nodes"] and fingerprint(n) not in seen_known]
    retry = [
        n
        for n in pool
        if state["nodes"].get(fingerprint(n), {}).get("status") == "dead"
        and fingerprint(n) not in seen_known
        and now - int(state["nodes"][fingerprint(n)].get("last_checked", 0)) >= DEAD_COOLDOWN
    ]
    budget = 10000 if args.full else max(args.max_new, len(known_alive))
    test_list = (
        known_alive
        + fresh[: max(0, budget - len(known_alive))]
        + retry[: max(0, budget - len(known_alive) - len(fresh))]
    )
    log(
        f"状态：现有 {len(existing)}，存活 {len(known_alive)}，新节点 {len(fresh)}，"
        f"冷却到期 {len(retry)}；本轮测试 {len(test_list)} 条"
    )

    if args.dry_run:
        for n in test_list[:20]:
            log(f"  [dry] {n.get('type'):8} {n.get('server')}:{n.get('port')}")
        log("dry-run 结束")
        return 0
    if not test_list:
        log("没有需要测试的节点；结束")
        return 0

    # 先把状态里已知存活的节点保住，避免本轮全挂后丢掉现有兜底。
    existing_fps = {fingerprint(n) for n in existing}
    only_existing = bool(test_list) and all(fingerprint(n) in existing_fps for n in test_list)
    results: dict[str, dict]
    if only_existing:
        log("本轮只复测现有节点，走 API 直测（不重载配置）")
        direct = test_existing_direct(existing, state)
        if direct is not None:
            results = direct
            survivors = pick_survivors(existing, results, args.max_keep, args.max_delay)
            if len(survivors) == len(existing) and all(r.get("alive") for r in results.values()):
                log("现有节点全部存活，配置不变")
                return 0
            backup = backup_remote()
            log(f"有节点失效，准备重写；已备份 → {backup}")
        else:
            log("直测失败，回退到分批重载")
            backup = backup_remote()
            log(f"已备份路由器 proxies.yaml → {backup}")
            results = test_batches(
                test_list,
                state,
                batch_size=args.batch_size,
                settle=args.settle,
                backup=backup,
                old_content=old_content,
            )
            survivors = pick_survivors(test_list, results, args.max_keep, args.max_delay)
    else:
        backup = backup_remote()
        log(f"已备份路由器 proxies.yaml → {backup}")
        results = test_batches(
            test_list,
            state,
            batch_size=args.batch_size,
            settle=args.settle,
            backup=backup,
            old_content=old_content,
        )
        survivors = pick_survivors(test_list, results, args.max_keep, args.max_delay)
    log(f"本轮存活 {sum(1 for r in results.values() if r.get('alive'))} 条；最终保留 {len(survivors)} 条")
    for n in survivors:
        log(f"  保留 {n.get('type'):8} {n.get('server')}:{n.get('port')} {results[fingerprint(n)]['delay']}ms")

    if not survivors:
        log("没有存活节点；保留现有配置不动")
        # 恢复到本轮开始前的块，避免留下最后一批测试节点。
        if read_remote(REMOTE_PROXIES) != old_content:
            write_remote(REMOTE_PROXIES, old_content)
            restart_core(args.settle)
        return 0

    block, kept = make_block(survivors, "")
    ok, detail = prevalidate(block)
    if not ok:
        log(f"最终配置预检失败，回滚：{detail}")
        write_remote(REMOTE_PROXIES, old_content)
        restart_core(args.settle)
        return 1
    write_remote(REMOTE_PROXIES, replace_block(old_content, block))
    if not restart_core(args.settle):
        log("最终重启失败，回滚")
        write_remote(REMOTE_PROXIES, old_content)
        restart_core(args.settle)
        return 1

    loaded = runtime_public_count()
    if loaded != len(kept):
        log(f"最终运行配置节点数 {loaded} != {len(kept)}，回滚")
        write_remote(REMOTE_PROXIES, old_content)
        restart_core(args.settle)
        return 1

    data = api_proxies()
    group = data.get(f"{NAME_PREFIX}备用") or {}
    members = group.get("all") or []
    alive_now = sum(1 for name in members if (data.get(name) or {}).get("alive"))
    log(f"验证：组 {NAME_PREFIX}备用 成员 {len(members)}，当前存活 {alive_now}，now={group.get('now')}")
    log("完成")
    return 0


if __name__ == "__main__":
    sys.exit(main())
