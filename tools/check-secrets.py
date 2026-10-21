#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""公开仓密钥扫描：拦住订阅链接、节点 URI、私钥块与 shadow 哈希。

用法：
    python tools/check-secrets.py            # 扫描已跟踪文件
    python tools/check-secrets.py --all      # 扫描工作树（含未跟踪，排除 .git/.work/vault）

退出码：0 通过 / 1 发现疑似凭据。
这是 `docs/SECRETS.md` 的**可执行版本** —— 文档说「本仓不保存凭据」，
CI 里得有个脚本真的能拦住。
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", ".work", "vault", "third-party", "node_modules", "dist", "__pycache__"}
SKIP_EXT = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".gz", ".pyc", ".woff", ".woff2", ".zip"}

# 占位符与示例行不算命中
PLACEHOLDER = re.compile(r"REDACTED|YOUR-|REPLACE-|<[^>]+>|example\.(com|org|net)|placeholder", re.I)

PATTERNS = [
    ("私钥块", re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----")),
    ("订阅 token", re.compile(r"https?://[^\s'\"<>]+(?:token|subscribe|subscription)=[A-Za-z0-9._~-]{8,}", re.I)),
    # 真正的节点 URI 必须带一段 payload；源码里的 "vmess://" 字面量不算
    ("代理节点 URI", re.compile(r"\b(?:vmess|vless|trojan|ssr?|hysteria2?)://[A-Za-z0-9+/=_%.:@?&~-]{20,}", re.I)),
    ("shadow 哈希", re.compile(r"\$[1256][aby]?\$[./A-Za-z0-9]{8,}")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
    ("AWS access key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("通用 sk- token", re.compile(r"\bsk-[A-Za-z0-9]{20,}\b")),
    ("vmess uuid", re.compile(r"\buuid\s*[:=]\s*[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")),
]


def tracked_files() -> list[str]:
    try:
        out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True)
    except FileNotFoundError:
        print("✗ 找不到 git 命令")
        raise SystemExit(2)
    return [x for x in out.stdout.splitlines() if x.strip()]


def walk_files() -> list[str]:
    files = []
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            files.append(os.path.relpath(os.path.join(dp, f), ROOT))
    return files


def main() -> int:
    files = walk_files() if "--all" in sys.argv else tracked_files()
    bad = []
    for rel in files:
        if os.path.splitext(rel)[1].lower() in SKIP_EXT:
            continue
        parts = rel.replace("\\", "/").split("/")
        if any(p in SKIP_DIRS for p in parts[:-1]):
            continue
        try:
            with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
                for lineno, line in enumerate(fh, 1):
                    if PLACEHOLDER.search(line):
                        continue
                    for name, pat in PATTERNS:
                        if pat.search(line):
                            bad.append((rel, lineno, name, line.strip()[:120]))
        except OSError:
            continue

    if bad:
        print(f"✗ 发现 {len(bad)} 处疑似凭据：")
        for rel, lineno, name, text in bad:
            print(f"   {rel}:{lineno}  [{name}]  {text}")
        print()
        print("   处理方式：换成占位符，或从版本库移除并轮换真值。")
        print("   位置索引见 docs/SECRETS.md。")
        return 1

    print(f"✓ 已扫描 {len(files)} 个文件，未发现疑似凭据")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
