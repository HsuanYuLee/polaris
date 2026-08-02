import hashlib
import json
import shlex
import sys

evidence_path = sys.argv[1]
command = sys.argv[2:]

try:
    data = json.load(open(evidence_path, "r", encoding="utf-8"))
except Exception as exc:
    print(
        f"[ci-local-run] BLOCKED_ENV evidence could not be read: {exc}", file=sys.stderr
    )
    sys.exit(0)

blocked = data.get("blocked_env") or {}
context = data.get("context") or {}
raw_context = "|".join(
    str(context.get(k) or "") for k in ("event", "base_branch", "source_branch", "ref")
)
context_hash = hashlib.sha1(raw_context.encode()).hexdigest()[:12]
reason = blocked.get("reason") or "unknown"
host = blocked.get("host") or ""
manual_remediation = "Connect the required VPN/private network or run the same command from an unsandboxed shell, then rerun the exact command."

payload = {
    "action": "RETRY_WITH_ESCALATION",
    "status": "BLOCKED_ENV",
    "reason": reason,
    "host": host,
    "stage": blocked.get("stage") or "",
    "package_manager": blocked.get("package_manager") or "",
    "context_hash": context_hash,
    "head_sha": data.get("head_sha") or "",
    "evidence": evidence_path,
    "command": " ".join(shlex.quote(part) for part in command),
    "manual_remediation": manual_remediation,
}

print(
    f"[ci-local-run] BLOCKED_ENV still present after same-context retry: reason={reason} host={host or 'unknown'}",
    file=sys.stderr,
)
print(json.dumps(payload, indent=2, sort_keys=True), file=sys.stderr)
