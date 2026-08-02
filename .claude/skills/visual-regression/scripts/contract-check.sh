#!/usr/bin/env bash
# contract-check.sh — Detect schema drift between Mockoon fixtures and live API responses.
# See: skills/references/api-contract-guard.md
#
# Usage:
#   contract-check.sh --env-dir <dir> --epic <name> [--format text|json] [--timeout <sec>]
#   contract-check.sh --file <environment.json> [--format text|json] [--timeout <sec>]
#
# Exit codes:
#   0 — No breaking drift
#   1 — Breaking drift detected
#   2 — Environment not reachable
#   3 — Invalid arguments

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
FORMAT="text"
TIMEOUT=10
ENV_DIR=""
EPIC=""
SINGLE_FILE=""

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-dir)   ENV_DIR="$2"; shift 2 ;;
    --epic)      EPIC="$2"; shift 2 ;;
    --file)      SINGLE_FILE="$2"; shift 2 ;;
    --format)    FORMAT="$2"; shift 2 ;;
    --timeout)   TIMEOUT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# //'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 3 ;;
  esac
done

# Validate
if [[ -z "$SINGLE_FILE" && ( -z "$ENV_DIR" || -z "$EPIC" ) ]]; then
  echo "Error: provide --file <path> or --env-dir <dir> --epic <name>" >&2
  exit 3
fi

# ── Resolve file list ────────────────────────────────────────────────────────
FILES=()
if [[ -n "$SINGLE_FILE" ]]; then
  [[ -f "$SINGLE_FILE" ]] || { echo "File not found: $SINGLE_FILE" >&2; exit 3; }
  FILES=("$SINGLE_FILE")
else
  TARGET_DIR="${ENV_DIR}/${EPIC}"
  [[ -d "$TARGET_DIR" ]] || { echo "Directory not found: $TARGET_DIR" >&2; exit 3; }
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$TARGET_DIR" -name '*.json' -not -name 'demo*' -not -name 'settings*' | sort)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No fixture files found." >&2
  exit 3
fi

# ── Python schema diff engine ────────────────────────────────────────────────
# Inline python for portability — no pip deps needed.
python3 - "${FORMAT}" "${TIMEOUT}" "${FILES[@]}" << 'PYEOF'
import json
import sys
import subprocess
import urllib.request
import urllib.error
import ssl
from datetime import datetime, timezone

format_mode = sys.argv[1]
timeout = int(sys.argv[2])
files = sys.argv[3:]

# SSL context that doesn't verify (dev/SIT certs may be self-signed)
ssl_ctx = ssl.create_default_context()
ssl_ctx.check_hostname = False
ssl_ctx.verify_mode = ssl.CERT_NONE

def get_type(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, int):
        return "integer"
    if isinstance(v, float):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "array"
    if isinstance(v, dict):
        return "object"
    return type(v).__name__

def schema_diff(fixture, live, path=""):
    """Compare two JSON values recursively. Returns list of diffs."""
    diffs = []
    ft = get_type(fixture)
    lt = get_type(live)

    if ft == "null" and lt != "null":
        diffs.append({"path": path or "$", "type": "breaking", "detail": f"null → {lt}"})
        return diffs
    if ft != "null" and lt == "null":
        diffs.append({"path": path or "$", "type": "breaking", "detail": f"{ft} → null"})
        return diffs
    if ft == "null" and lt == "null":
        return diffs

    # Type mismatch (excluding int/number interchangeability)
    if ft != lt and not ({ft, lt} <= {"integer", "number"}):
        diffs.append({"path": path or "$", "type": "breaking", "detail": f"{ft} → {lt}"})
        return diffs

    if ft == "object" and lt == "object":
        fixture_keys = set(fixture.keys())
        live_keys = set(live.keys())
        # Removed keys = breaking
        for k in fixture_keys - live_keys:
            diffs.append({"path": f"{path}.{k}", "type": "breaking", "detail": "field removed"})
        # Added keys = additive
        for k in live_keys - fixture_keys:
            diffs.append({"path": f"{path}.{k}", "type": "additive", "detail": f"field added ({get_type(live[k])})"})
        # Shared keys = recurse
        for k in fixture_keys & live_keys:
            diffs.extend(schema_diff(fixture[k], live[k], f"{path}.{k}"))

    elif ft == "array" and lt == "array":
        # Compare structure of first element only
        if len(fixture) > 0 and len(live) > 0:
            diffs.extend(schema_diff(fixture[0], live[0], f"{path}[0]"))
        elif len(fixture) > 0 and len(live) == 0:
            diffs.append({"path": path, "type": "breaking", "detail": "array became empty"})
        # fixture empty, live non-empty → additive (new data)

    else:
        # Same primitive type, different value → value-only (not reported as diff)
        pass

    return diffs

def fetch_live(url, method="GET"):
    """Fetch live API response."""
    try:
        req = urllib.request.Request(url, method=method.upper())
        req.add_header("Accept", "application/json")
        with urllib.request.urlopen(req, timeout=timeout, context=ssl_ctx) as resp:
            status = resp.getcode()
            body = resp.read().decode("utf-8", errors="replace")
            return status, body, None
    except urllib.error.HTTPError as e:
        return e.code, "", str(e)
    except Exception as e:
        return 0, "", str(e)

def process_file(filepath):
    """Process one Mockoon environment file."""
    with open(filepath) as f:
        env = json.load(f)

    proxy_host = env.get("proxyHost", "").rstrip("/")
    routes = env.get("routes", [])
    result = {
        "file": filepath.split("/")[-1],
        "proxy_host": proxy_host,
        "routes": []
    }

    if not proxy_host:
        return result

    for route in routes:
        method = route.get("method", "get").upper()
        endpoint = route.get("endpoint", "")
        responses = route.get("responses", [])

        if not responses:
            continue

        # Parse fixture body
        resp = responses[0]
        body_str = resp.get("body", "")
        body_type = resp.get("bodyType", "INLINE")

        if body_type != "INLINE" or not body_str.strip():
            continue

        try:
            fixture_body = json.loads(body_str)
        except json.JSONDecodeError:
            continue  # Non-JSON body, skip

        # Skip non-GET for now (POST/PUT may need request bodies)
        if method != "GET":
            result["routes"].append({
                "method": method,
                "endpoint": endpoint,
                "status": "skipped",
                "reason": f"non-GET method ({method})"
            })
            continue

        # Fetch live
        url = f"{proxy_host}{endpoint}"
        status_code, live_body_str, error = fetch_live(url, method)

        if error:
            if "timeout" in error.lower() or "timed out" in error.lower():
                result["routes"].append({
                    "method": method, "endpoint": endpoint,
                    "status": "timeout", "error": error
                })
            else:
                result["routes"].append({
                    "method": method, "endpoint": endpoint,
                    "status": "error", "error": error
                })
            continue

        if status_code in (401, 403):
            result["routes"].append({
                "method": method, "endpoint": endpoint,
                "status": "auth_required"
            })
            continue

        if status_code < 200 or status_code >= 300:
            result["routes"].append({
                "method": method, "endpoint": endpoint,
                "status": "error", "error": f"HTTP {status_code}"
            })
            continue

        try:
            live_body = json.loads(live_body_str)
        except json.JSONDecodeError:
            result["routes"].append({
                "method": method, "endpoint": endpoint,
                "status": "error", "error": "non-JSON response"
            })
            continue

        # Schema diff
        diffs = schema_diff(fixture_body, live_body)
        has_breaking = any(d["type"] == "breaking" for d in diffs)
        has_additive = any(d["type"] == "additive" for d in diffs)

        if has_breaking:
            classification = "breaking"
        elif has_additive:
            classification = "additive"
        elif diffs:
            classification = "value_only"
        else:
            classification = "unchanged"

        entry = {
            "method": method,
            "endpoint": endpoint,
            "status": classification,
        }
        if diffs:
            entry["diffs"] = diffs
        result["routes"].append(entry)

    return result

# ── Main ──────────────────────────────────────────────────────────────────────
all_results = []
has_breaking = False
total = checked = skipped = breaking = additive = value_only = unchanged = errors = 0

for fpath in files:
    file_result = process_file(fpath)
    all_results.append(file_result)
    for r in file_result["routes"]:
        total += 1
        s = r.get("status", "")
        if s == "breaking":
            checked += 1; breaking += 1; has_breaking = True
        elif s == "additive":
            checked += 1; additive += 1
        elif s == "value_only":
            checked += 1; value_only += 1
        elif s == "unchanged":
            checked += 1; unchanged += 1
        elif s == "skipped":
            skipped += 1
        else:
            errors += 1

summary = {
    "total_routes": total,
    "checked": checked,
    "skipped": skipped,
    "breaking": breaking,
    "additive": additive,
    "value_only": value_only,
    "unchanged": unchanged,
    "errors": errors,
}

report = {
    "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "files": all_results,
    "summary": summary,
}

if format_mode == "json":
    print(json.dumps(report, indent=2, ensure_ascii=False))
else:
    # Text output
    print("═" * 60)
    print("  API Contract Check Report")
    print("═" * 60)
    print()

    for fr in all_results:
        print(f"📁 {fr['file']}  ({fr['proxy_host']})")
        for r in fr["routes"]:
            s = r["status"]
            icon = {"breaking": "🔴", "additive": "🟡", "unchanged": "✅",
                    "value_only": "⚪", "skipped": "⏭️", "auth_required": "🔒",
                    "timeout": "⏱️", "error": "❌"}.get(s, "❓")
            print(f"  {icon} {r['method']:6} {r['endpoint']}")
            if s == "breaking" or s == "additive":
                for d in r.get("diffs", []):
                    marker = "‼️" if d["type"] == "breaking" else "➕"
                    print(f"       {marker} {d['path']}: {d['detail']}")
            elif "error" in r:
                print(f"       ↳ {r['error']}")
        print()

    print("─" * 60)
    print(f"  Total: {total}  Checked: {checked}  Skipped: {skipped}  Errors: {errors}")
    print(f"  🔴 Breaking: {breaking}  🟡 Additive: {additive}  ⚪ Value-only: {value_only}  ✅ Unchanged: {unchanged}")
    print("─" * 60)

    if has_breaking:
        print()
        print("⚠️  BREAKING DRIFT DETECTED — fixtures are stale.")
        print("   Update fixtures (--record mode) or fix the code before proceeding.")

sys.exit(1 if has_breaking else 0)
PYEOF
