#!/usr/bin/env python3
"""把 V2Ray/Clash 订阅里的 URI 转成 Clash 节点 dict。

只覆盖公开节点常见的 vless / vmess / trojan / ss / hysteria2；
解析不了的节点返回 None，由调用方跳过。SSL/WS/gRPC 的常见参数都处理。
"""
from __future__ import annotations

import base64
import json
from urllib.parse import parse_qs, unquote, urlparse


def _b64(text: str) -> str:
    compact = "".join(text.split()).replace("-", "+").replace("_", "/")
    compact += "=" * ((4 - len(compact) % 4) % 4)
    return base64.b64decode(compact, validate=False).decode("utf-8", errors="replace")


def _q(params: dict, *keys: str, default: str = "") -> str:
    for key in keys:
        values = params.get(key)
        if values:
            return unquote(str(values[0]))
    return default


def _alpn(value: str) -> list[str] | None:
    parts = [x.strip() for x in value.split(",") if x.strip()]
    return parts or None


def _ws_opts(path: str, host: str) -> dict:
    opts: dict = {"path": path or "/"}
    if host:
        opts["headers"] = {"Host": host}
    return opts


def parse_uri(line: str) -> dict | None:
    line = line.strip()
    if "://" not in line:
        return None
    scheme = line.split("://", 1)[0].lower()
    try:
        if scheme == "vmess":
            return _parse_vmess(line)
        if scheme in ("vless", "trojan", "ss", "hysteria2", "hy2"):
            return _parse_url(line, scheme)
    except Exception:  # noqa: BLE001 - 单条坏节点直接跳过
        return None
    return None


def _parse_vmess(line: str) -> dict | None:
    payload = line[8:].split("#", 1)[0]
    data = json.loads(_b64(payload))
    server = str(data.get("add") or "").strip()
    port = int(data.get("port") or 0)
    uuid = str(data.get("id") or "")
    if not server or not uuid or not 1 <= port <= 65535:
        return None
    node: dict = {
        "name": "",
        "type": "vmess",
        "server": server,
        "port": port,
        "uuid": uuid,
        "alterId": int(data.get("aid") or 0),
        "cipher": str(data.get("scy") or "auto"),
        "udp": True,
    }
    net = str(data.get("net") or "tcp")
    host = str(data.get("host") or "")
    path = str(data.get("path") or "/")
    tls = str(data.get("tls") or "").lower() in ("tls", "reality", "true", "1")
    sni = str(data.get("sni") or "")
    if tls:
        node["tls"] = True
        node["servername"] = sni or host or server
    if net == "ws":
        node["network"] = "ws"
        node["ws-opts"] = _ws_opts(path, host or sni)
    elif net == "grpc":
        node["network"] = "grpc"
        node["grpc-opts"] = {"grpc-service-name": path.strip("/")}
    fp = str(data.get("fp") or "")
    if fp:
        node["client-fingerprint"] = fp
    alpn = _alpn(str(data.get("alpn") or ""))
    if alpn:
        node["alpn"] = alpn
    return node


def _parse_url(line: str, scheme: str) -> dict | None:
    u = urlparse(line)
    server = (u.hostname or "").strip()
    port = int(u.port or 0)
    if not server or not 1 <= port <= 65535:
        return None
    params = parse_qs(u.query, keep_blank_values=True)
    name = ""

    if scheme == "ss":
        return _parse_ss(u, server, port, name)

    password = unquote(u.username or "")
    if scheme == "vless":
        if not password:
            return None
        node: dict = {
            "name": name,
            "type": "vless",
            "server": server,
            "port": port,
            "uuid": password,
            "udp": True,
        }
        security = _q(params, "security").lower()
        sni = _q(params, "sni", "peer", "host")
        fp = _q(params, "fp")
        flow = _q(params, "flow")
        if security in ("tls", "reality"):
            node["tls"] = True
            if sni:
                node["servername"] = sni
        if fp:
            node["client-fingerprint"] = fp
        if flow:
            node["flow"] = flow
        if security == "reality":
            pbk = _q(params, "pbk")
            sid = _q(params, "sid")
            if not pbk:
                return None
            node["reality-opts"] = {"public-key": pbk, "short-id": sid}
            spx = _q(params, "spx")
            if spx:
                node["reality-opts"]["spider-x"] = spx
        _apply_transport(node, params, sni or server)
    elif scheme == "trojan":
        if not password:
            return None
        node = {
            "name": name,
            "type": "trojan",
            "server": server,
            "port": port,
            "password": password,
            "sni": _q(params, "sni", "peer") or server,
            "udp": True,
        }
        if _q(params, "allowInsecure").lower() in ("1", "true"):
            node["skip-cert-verify"] = True
        _apply_transport(node, params, node["sni"])
    elif scheme in ("hysteria2", "hy2"):
        if not password:
            return None
        node = {
            "name": name,
            "type": "hysteria2",
            "server": server,
            "port": port,
            "password": password,
            "udp": True,
        }
        sni = _q(params, "sni", "peer")
        if sni:
            node["sni"] = sni
        if _q(params, "insecure").lower() in ("1", "true"):
            node["skip-cert-verify"] = True
        obfs = _q(params, "obfs")
        if obfs:
            node["obfs"] = obfs
            node["obfs-password"] = _q(params, "obfs-password")
        alpn = _alpn(_q(params, "alpn"))
        if alpn:
            node["alpn"] = alpn
    else:
        return None
    return node


def _apply_transport(node: dict, params: dict, default_host: str) -> None:
    net = _q(params, "type", default="tcp").lower()
    if net == "ws":
        node["network"] = "ws"
        node["ws-opts"] = _ws_opts(_q(params, "path") or "/", _q(params, "host") or default_host)
    elif net == "grpc":
        node["network"] = "grpc"
        node["grpc-opts"] = {"grpc-service-name": _q(params, "serviceName")}
    elif net in ("tcp", "", "http", "h2", "quic"):
        # http/h2/quic 在公开节点里少见；保留 tcp，其它由 mihomo 校验兜底
        if net in ("http", "h2"):
            node["network"] = "http"
            opts = {"path": _q(params, "path") or "/"}
            host = _q(params, "host")
            if host:
                opts["headers"] = {"Host": host}
            node["http-opts"] = opts
    else:
        raise ValueError(f"unsupported transport {net}")


def _parse_ss(u, server: str, port: int, name: str) -> dict | None:
    userinfo = unquote(u.username or "")
    password = unquote(u.password or "")
    if userinfo and ":" in userinfo and not password:
        method, _, pwd = userinfo.partition(":")
    elif userinfo and not password:
        try:
            method, _, pwd = _b64(userinfo).partition(":")
        except Exception:  # noqa: BLE001
            return None
    else:
        method, pwd = userinfo, password
    if not method or not pwd:
        return None
    params = parse_qs(u.query, keep_blank_values=True)
    if _q(params, "plugin"):
        return None  # 插件形态差异大，先跳过，避免把错误配置推到路由器
    return {
        "name": name,
        "type": "ss",
        "server": server,
        "port": port,
        "cipher": method,
        "password": pwd,
        "udp": True,
    }


def parse_subscription(text: str) -> list[dict]:
    """Clash YAML（proxies）或 Base64/明文 URI 列表。"""
    stripped = text.lstrip()
    if stripped.startswith("proxies:") or "\nproxies:" in text[:2000]:
        import yaml

        data = yaml.safe_load(text) or {}
        return list(data.get("proxies") or []) if isinstance(data, dict) else []

    # 明文 URI 列表
    lines = [line.strip() for line in text.splitlines() if "://" in line]
    if not lines:
        # Base64 订阅；Matin 这类带 #profile-* 头，先去掉注释行
        body = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
        try:
            lines = [line.strip() for line in _b64(body).splitlines() if "://" in line]
        except Exception:  # noqa: BLE001
            return []

    nodes: list[dict] = []
    for line in lines:
        node = parse_uri(line)
        if node:
            nodes.append(node)
    return nodes
