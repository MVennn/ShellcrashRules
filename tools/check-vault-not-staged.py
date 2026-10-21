#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""兜底检查：`vault/` 下的东西**绝不能**被提交。

`.gitignore` 已经排除了 `/vault/`，但忽略规则可能被改、可能被 `git add -f` 绕过、
也可能有人改了文件名。这个脚本在 CI 里跑：只要暂存区里出现 vault 的文件，直接红。

用法：
    python tools/check-vault-not-staged.py            # 检查暂存区
    python tools/check-vault-not-staged.py --all     # 顺便检查历史提交里有没有

退出码：0 通过 / 1 发现了不该进库的东西。
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

VAULT_DIRS = ("vault/",)
# 私钥类文件名 —— 即使不在 vault/ 下，也不该进库
SECRET_NAMES = re.compile(
    r"(^|/)(uhttpd\.key|.*\.key|.*\.key\.orig|.*\.crt|.*\.crt\.orig|wg-client\.conf)$"
)


def git(*args: str) -> str:
    try:
        r = subprocess.run(["git", *args], capture_output=True, text=True, errors="replace")
    except FileNotFoundError:
        print("✗ 找不到 git 命令 —— CI 镜像里要先装 git（apt-get install -y git）")
        raise SystemExit(2)
    return r.stdout


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="连历史提交一起查")
    args = ap.parse_args()

    staged = [x for x in git("diff", "--cached", "--name-only").split("\n") if x.strip()]
    tracked = [x for x in git("ls-files").split("\n") if x.strip()]

    bad = []
    for f in staged + tracked:
        norm = f.replace("\\", "/")
        if any(norm.startswith(v) for v in VAULT_DIRS) or SECRET_NAMES.search(norm):
            bad.append(norm)

    if args.all:
        log = git("log", "--all", "--name-only", "--pretty=format:")
        for f in {x for x in log.split("\n") if x.strip()}:
            norm = f.replace("\\", "/")
            if any(norm.startswith(v) for v in VAULT_DIRS) or SECRET_NAMES.search(norm):
                bad.append(norm + "  （出现在历史提交里）")

    if bad:
        print("✗ 发现了不该进版本库的东西：")
        for b in sorted(set(bad)):
            print("   ", b)
        print()
        print("  私钥 / 整机快照一旦提交进 git，删文件也删不掉历史 ——")
        print("  换掉凭据，并从历史里清除（git filter-repo / BFG）。")
        return 1

    print(f"✓ 没有不该进库的东西（暂存 {len(staged)} 个、已跟踪 {len(tracked)} 个文件）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
