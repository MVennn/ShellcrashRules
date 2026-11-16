#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""规则静态门禁：把生成器/运行时脚本里的关键不变量前移到 CI。

为什么需要：ci.yml 只有 sh -n 语法检查；而项目反复踩过的坑（空组名致 mihomo
拒载、支付/广告 carve-out 顺序被破坏、关键覆盖规则被 geosite 同名去重吃掉、
provider 退回 type:file 导致 62 天不更新）都只靠生成时自检与 ai-api-check.sh
在设备上兜底。提交阶段没有任何一道关拦住「规则被手改坏后再提交」。本脚本把
这些已知不变量固化成零依赖静态检查，让 CI 在提交时就拦住。

边界：只校验规则文件自身的结构/顺序/关键条目，**不做**按先匹配先赢的真实目标
计算（那是 OpenwrtOpsToolkit/mihomo/rule_audit.py 的职责，需完整 config.yaml）。
本脚本零第三方依赖、通用于 CI（UTF-8）与设备 GBK 控制台（结论不用 ✓/✗，
见 PITFALLS 43）。

用法：
    python3 tools/check-rules.py                       # 检查默认路径
    python3 tools/check-rules.py config/generated/rules.yaml ...
退出码：0 全部通过 / 1 有问题。
"""
from __future__ import annotations

import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 规则文件路径（相对仓根）。缺少则报错——CI 里缺文件即视为门禁失效。
RULE_FILES = [
    "config/generated/rules.yaml",
]
# 生成器：策略组变量定义（空组名根因，见 ai-api-check.sh 第 12 段）
GENERATOR = "config/generators/ai-rules-update.sh"
# provider 钩子：必须是 type:http + interval（PITFALLS 47：type:file 冻结 62 天）
PROVIDER_FILES = [
    "config/hooks/rules-cnip.sh",
    "config/hooks/rules-porn.sh",
]

fail = 0


def bad(msg: str) -> None:
    global fail
    fail = 1
    print("FAIL: " + msg)


def ok(msg: str) -> None:
    print("OK: " + msg)


def lines_of(rel: str) -> list[str] | None:
    p = os.path.join(ROOT, rel)
    if not os.path.isfile(p):
        bad("缺文件: " + rel)
        return None
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read().splitlines()


# 只认真正的规则行；注释（含行内 # 说明）里的逗号不算规则字段。
RULE_RE = re.compile(r"^[\-]\s+([A-Z0-9-]+),(.*)$")


def parse_rules(lines: list[str]) -> list[tuple[int, str, list[str]]]:
    out = []
    for n, s in enumerate(lines, 1):
        if s.lstrip().startswith("#"):
            continue
        m = RULE_RE.match(s.strip())
        if not m:
            continue
        # 去掉行内注释后再按逗号切分（规则的目标组名里不含 #）
        body = m.group(2).split(" #", 1)[0]
        out.append((n, m.group(1), [x.strip() for x in body.split(",")]))
    return out


def check_rules():
    for rel in RULE_FILES:
        lines = lines_of(rel)
        if lines is None:
            continue
        rules = parse_rules(lines)
        tag = os.path.basename(rel)

        # 1. 条数下限：低于 50 说明生成被截断（生成器同款阈值）
        if len(rules) < 50:
            bad("%s 规则条数异常(%d)，疑似生成被截断" % (tag, len(rules)))
        else:
            ok("%s 规则条数 %d (>=50)" % (tag, len(rules)))

        # 2. 空策略名：mihomo 对尾逗号规则直接拒载（ARCHITECTURE 357 / ai-api-check 12）
        empties = [n for n, _t, f in rules if len(f) >= 2 and f[-1] == ""]
        if empties:
            bad("%s 有 %d 条空组名规则（mihomo 会拒载）: 行 %s"
                % (tag, len(empties), ",".join(map(str, empties[:10]))))
        else:
            ok("%s 无空组名规则" % tag)

        # 3. 规则类型白名单：拼错的类型 mihomo 不认，提交阶段就拦
        known = {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD",
                 "DOMAIN-REGEX", "IP-CIDR", "IP-CIDR6", "IP-ASN", "GEOIP",
                 "GEOSITE", "RULE-SET", "MATCH", "PROCESS-NAME", "DST-PORT"}
        unknown = sorted({t for _n, t, _f in rules if t not in known})
        if unknown:
            bad("%s 出现未知规则类型: %s" % (tag, ", ".join(unknown)))
        else:
            ok("%s 规则类型均在白名单" % tag)

        # 4. 生成物必须含的稳定关键规则（防止手改/误去重删掉）
        #    注意：stripe/gh-proxy/cloudflare-dns 是 2026-11-12 生成器的 P0 新增，
        #    设备上还没重跑生成器时生成物里没有，故放在生成器段校验（见 check_generator）。
        must_exist = [
            "DOMAIN-SUFFIX,workbuddy.ai,",                # 直连覆盖
            "DOMAIN-SUFFIX,z.ai,",
            "DOMAIN-SUFFIX,bigmodel.cn,",
            "RULE-SET,porn,",                            # 大流量 provider 引用
        ]
        # 从原始行里做字面前缀匹配（组名用 emoji，避免写死）
        raw = chr(10).join(s for s in lines if not s.lstrip().startswith("#"))
        missing = [r for r in must_exist if r not in raw]
        if missing:
            bad("%s 缺关键覆盖规则: %s" % (tag, "; ".join(missing)))
        else:
            ok("%s 关键覆盖规则齐全 (%d 条)" % (tag, len(must_exist)))

        # 6. 顺序：广告 carve-out 必须早于宽泛 google 规则（先匹配先赢）
        ad = next((n for n, t, f in rules
                   if t == "DOMAIN-SUFFIX" and len(f) > 1 and f[1] == "doubleclick.net"), None)
        gkw = next((n for n, t, f in rules
                    if t == "DOMAIN-KEYWORD" and len(f) > 1 and f[1] == "google"), None)
        if ad is not None and gkw is not None and ad >= gkw:
            bad("%s 广告 carve-out(#%d) 必须早于 DOMAIN-KEYWORD,google(#%d)"
                % (tag, ad, gkw))
        else:
            ok("%s 广告 carve-out 顺序正常" % tag)


def check_generator():
    lines = lines_of(GENERATOR)
    if lines is None:
        return
    text = chr(10).join(lines)
    # 生成器必须定义策略组变量，否则规则生成空组名（ai-api-check 12）
    for var in ('AI_GROUP="🤖 人工智能"', 'CL="🤖 干净出口"'):
        if var not in text:
            bad("生成器缺变量定义: " + var)
        else:
            ok("生成器已定义 " + var.split("=")[0])

    # PITFALLS 48 的 P0 新增规则：真实来源是生成器（生成物可能尚未重跑），
    # 校验生成器里必须有这些 echo 行，且 stripe 的定义早于第一条 IP-CIDR echo。
    p0 = [
        "DOMAIN-SUFFIX,stripe.com,",
        "DOMAIN-SUFFIX,gh-proxy.com,",
        "DOMAIN-SUFFIX,cloudflare-dns.com,",
        "DOMAIN-SUFFIX,cdn.ldstatic.com,",
        "DOMAIN-SUFFIX,s.immersivetranslate.com,",
        "DOMAIN-SUFFIX,c.tenor.com,",
        "DOMAIN-SUFFIX,api.gemai.cc,",
    ]
    missing = [r for r in p0 if r not in text]
    if missing:
        bad("生成器缺 P0 覆盖规则: " + "; ".join(missing))
    else:
        ok("生成器 P0 覆盖规则齐全 (%d 条)" % len(p0))

    # stripe 的 echo 必须早于第一条 IP-CIDR 规则 echo（模板 IP-CIDR,34.208/12 会抢支付域）。
    # 只认规则行（echo "- ..."），注释行里的 "IP-CIDR,34.208..." 不算（生成器 awk 同口径）。
    s_line = next((i for i, l in enumerate(lines)
                   if l.lstrip().startswith("echo \"- DOMAIN-SUFFIX,stripe.com,")), None)
    ip_line = next((i for i, l in enumerate(lines)
                    if l.lstrip().startswith("echo \"- IP-CIDR")), None)
    if s_line is None or ip_line is None:
        bad("生成器缺 stripe 或 IP-CIDR 规则 echo，无法校验支付域顺序")
    elif s_line >= ip_line:
        bad("生成器 stripe 规则必须早于首个 IP-CIDR 规则，否则支付域被劫持")
    else:
        ok("生成器 stripe 早于 IP-CIDR（支付域不会被 IP 段抢走）")


def check_providers():
    for rel in PROVIDER_FILES:
        lines = lines_of(rel)
        if lines is None:
            continue
        tag = os.path.basename(rel)
        # provider 选项必须 type:http + interval；type:file 会冻结不更新（PITFALLS 47）
        prov = next((s for s in lines if "PROV_OPTS=" in s and not s.strip().startswith("#")), None)
        if prov is None:
            bad("%s 未找到 PROV_OPTS 定义" % tag)
            continue
        if "type: http" not in prov:
            bad("%s provider 不是 type:http（type:file 会冻结不更新）" % tag)
        elif "interval:" not in prov:
            bad("%s provider 缺 interval（不会定时更新）" % tag)
        else:
            ok("%s provider 为 type:http + interval" % tag)


check_rules()
check_generator()
check_providers()

if fail:
    print("结果: 有失败项")
else:
    print("结果: 全部通过")
sys.exit(fail)
