#!/usr/bin/env python3
"""Classify ci-local dependency/install failures as BLOCKED_ENV.

Stdlib-only by design: this must run when repo dependencies are not installed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode


TOKEN_KEYS = {
    "_authtoken",
    "auth",
    "authorization",
    "token",
    "access_token",
    "id_token",
    "refresh_token",
    "password",
    "passwd",
    "secret",
    "apikey",
    "api_key",
}

URL_RE = re.compile(r"https?://[^\s'\"<>]+", re.IGNORECASE)
HOST_RE = re.compile(
    r"(?i)\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\b"
)


def read_output(args: argparse.Namespace) -> str:
    chunks: list[str] = []
    if args.output:
        chunks.append(args.output)
    if args.output_file:
        try:
            chunks.append(Path(args.output_file).read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            pass
    return "\n".join(chunks)


def scrub_url(raw: str) -> str:
    try:
        parts = urlsplit(raw)
    except Exception:
        return raw

    netloc = parts.netloc
    if "@" in netloc:
        _userinfo, hostpart = netloc.rsplit("@", 1)
        netloc = f"***:***@{hostpart}"

    if parts.query:
        safe_q = []
        for key, value in parse_qsl(parts.query, keep_blank_values=True):
            if key.lower() in TOKEN_KEYS or any(t in key.lower() for t in ("token", "secret", "password")):
                safe_q.append((key, "***"))
            else:
                safe_q.append((key, value))
        query = urlencode(safe_q)
    else:
        query = ""

    return urlunsplit((parts.scheme, netloc, parts.path, query, parts.fragment))


def scrub_text(text: str) -> str:
    text = URL_RE.sub(lambda m: scrub_url(m.group(0)), text)
    text = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+", r"\1***", text)
    text = re.sub(r"(?i)((?:_authToken|authToken|token|password|passwd|secret|api[_-]?key)\s*[=:]\s*)[^\s]+", r"\1***", text)
    text = re.sub(r"(?i)(authorization:\s*(?:basic|bearer)\s+)[A-Za-z0-9._~+/=-]+", r"\1***", text)
    return text


def output_tail(text: str, limit: int = 40) -> str:
    lines = scrub_text(text).strip().splitlines()
    return "\n".join(lines[-limit:])


def package_manager_from_command(command: str) -> str | None:
    first = command.strip().split()
    if not first:
        return None
    exe = Path(first[0]).name
    if exe in {"pnpm", "npm", "yarn"}:
        return exe
    if exe == "corepack" and len(first) > 1 and first[1] in {"pnpm", "npm", "yarn"}:
        return first[1]
    return None


def host_from_url(raw: str) -> str | None:
    try:
        host = urlsplit(raw).hostname
    except Exception:
        host = None
    return host


def discover_registry_hosts(repo: str | None) -> list[str]:
    if not repo:
        return []
    root = Path(repo)
    hosts: set[str] = set()

    npmrc = root / ".npmrc"
    if npmrc.is_file():
        for line in npmrc.read_text(encoding="utf-8", errors="ignore").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith(("#", ";")):
                continue
            if "registry=" in stripped:
                _key, value = stripped.split("=", 1)
                host = host_from_url(value.strip())
                if host:
                    hosts.add(host)

    yarnrc = root / ".yarnrc.yml"
    if yarnrc.is_file():
        for line in yarnrc.read_text(encoding="utf-8", errors="ignore").splitlines():
            if "npmRegistryServer:" in line or "npmPublishRegistry:" in line:
                _key, value = line.split(":", 1)
                host = host_from_url(value.strip().strip("'\""))
                if host:
                    hosts.add(host)

    return sorted(hosts)


def extract_host(text: str, registry_hosts: list[str]) -> str | None:
    patterns = [
        r"getaddrinfo\s+ENOTFOUND\s+([A-Za-z0-9.-]+)",
        r"Could not resolve host:\s*([A-Za-z0-9.-]+)",
        r"connect\s+ETIMEDOUT\s+([A-Za-z0-9.-]+)",
        r"ETIMEDOUT\s+([A-Za-z0-9.-]+)",
        r"ENOTFOUND\s+([A-Za-z0-9.-]+)",
        r"https?://([^/\s'\"<>]+)",
    ]
    for pattern in patterns:
        m = re.search(pattern, text, flags=re.IGNORECASE)
        if m:
            host = m.group(1).split(":")[0]
            if host:
                return host
    for host in registry_hosts:
        if host and host in text:
            return host
    m = HOST_RE.search(text)
    if m:
        return m.group(0)
    return registry_hosts[0] if registry_hosts else None


def classify_reason(text: str, host: str | None) -> tuple[str | None, str | None]:
    lower = text.lower()
    if re.search(r"getaddrinfo\s+enotfound|enotfound|could not resolve host|name or service not known|temporary failure in name resolution", lower):
        return "dns_resolution_failed", "DNS / hostname resolution failed"
    if re.search(r"etimedout|timed?\s*out|network timeout|connect timeout|connection timeout", lower):
        return "connection_timeout", "Connection to dependency infrastructure timed out"
    if re.search(r"self[_ -]?signed|unable_to_verify|cert_has_expired|certificate|tls|ssl|proxy|tunneling socket|econnreset", lower):
        return "tls_or_proxy_failure", "TLS / proxy / connection reset while reaching dependency infrastructure"
    if re.search(r"\b(e401|401|unauthorized|e403|403|forbidden|authentication required|auth required|unable to authenticate)\b", lower):
        return "auth_required_or_forbidden", "Dependency infrastructure requires credentials or denies access"
    if re.search(r"\b(vpn|private network|intranet|internal network)\b", lower):
        return "vpn_or_private_network_required", "Dependency infrastructure appears reachable only from private network or VPN"
    if host and is_privateish_host(host):
        return "vpn_or_private_network_required", "Dependency infrastructure host appears private or company-internal"
    return None, None


def is_privateish_host(host: str) -> bool:
    host_l = host.lower()
    return (
        host_l.endswith(".local")
        or host_l.endswith(".internal")
        or host_l.endswith(".corp")
        or ".sit." in host_l
        or host_l.startswith("nexus")
        or host_l.startswith("artifactory")
        or host_l.startswith("registry.")
    )


def category_is_dependency_stage(category: str, command: str) -> bool:
    category_l = (category or "").lower()
    if category_l == "install":
        return True
    command_l = command.lower()
    return any(
        token in command_l
        for token in (
            "pnpm install",
            "npm install",
            "npm ci",
            "yarn install",
            "corepack pnpm install",
            "corepack yarn install",
        )
    )


def build_payload(args: argparse.Namespace) -> dict:
    raw_output = read_output(args)
    registry_hosts = discover_registry_hosts(args.repo)
    package_manager = package_manager_from_command(args.command or "")
    host = extract_host(raw_output, registry_hosts)
    reason, detail = classify_reason(raw_output, host)
    dependency_stage = category_is_dependency_stage(args.category or "", args.command or "")

    if dependency_stage and reason:
        return {
            "status": "BLOCKED_ENV",
            "classification": "environment_blocker",
            "reason": reason,
            "detail": detail,
            "stage": args.category or "install",
            "host": host,
            "package_manager": package_manager,
            "registry_hosts": registry_hosts,
            "command": args.command,
            "output_tail": output_tail(raw_output),
        }

    return {
        "status": "FAIL",
        "classification": None,
        "reason": None,
        "stage": args.category,
        "host": host,
        "package_manager": package_manager,
        "registry_hosts": registry_hosts,
        "command": args.command,
        "output_tail": output_tail(raw_output),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify ci-local install failures")
    parser.add_argument("--category", default="", help="ci-local check category, e.g. install")
    parser.add_argument("--command", default="", help="failed command")
    parser.add_argument("--output", default="", help="stderr/stdout text")
    parser.add_argument("--output-file", default="", help="file containing stderr/stdout text")
    parser.add_argument("--repo", default="", help="optional repo root for registry host discovery")
    parser.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    args = parser.parse_args()

    payload = build_payload(args)
    print(json.dumps(payload, indent=2 if args.pretty else None, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
