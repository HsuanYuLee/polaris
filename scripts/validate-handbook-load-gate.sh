#!/usr/bin/env bash
# Purpose: Enforce lazy first-touch loading for a repo-scoped Polaris handbook.
# Inputs: Repo, tracked mutation path, project identity, session identity, resolver.
# Outputs: Surfaced handbook index plus a session/repo marker, or fail-closed marker.

set -euo pipefail

REPO=""
TARGET_PATH=""
PROJECT="${POLARIS_PROJECT:-}"
SESSION_ID="${POLARIS_SESSION_ID:-${CLAUDE_SESSION_ID:-${CODEX_THREAD_ID:-shell-${PPID}}}}"
RESOLVER="${POLARIS_HANDBOOK_RESOLVER:-}"

usage() {
  echo "usage: validate-handbook-load-gate.sh --repo PATH --path FILE [--project ID] [--session-id ID] [--resolver PATH]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --path) TARGET_PATH="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --session-id) SESSION_ID="${2:-}"; shift 2 ;;
    --resolver) RESOLVER="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REPO" && -n "$TARGET_PATH" ]] || usage
REPO="$(cd "$REPO" && pwd)"
[[ -n "$RESOLVER" ]] || RESOLVER="$REPO/scripts/resolve-handbook.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

relative_path="$(python3 - "$REPO" "$TARGET_PATH" <<'PY'
import os, sys
repo = os.path.realpath(sys.argv[1])
target = os.path.realpath(sys.argv[2] if os.path.isabs(sys.argv[2]) else os.path.join(repo, sys.argv[2]))
try:
    relative = os.path.relpath(target, repo)
except ValueError:
    raise SystemExit(0)
if relative == ".." or relative.startswith("../"):
    raise SystemExit(0)
print(relative)
PY
)"
[[ -n "$relative_path" ]] || exit 0
git -C "$REPO" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1 || exit 0

if [[ -z "$PROJECT" ]]; then
  PROJECT="$(python3 - "$REPO" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1]) / "polaris-config"
configs = sorted(root.glob("*/handbook/config.yaml")) if root.is_dir() else []
if len(configs) == 1:
    print(configs[0].parents[1].name)
elif len(configs) > 1:
    print("POLARIS_AMBIGUOUS", file=sys.stderr)
    raise SystemExit(2)
PY
)" || {
    echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:ambiguous_project" >&2
    exit 1
  }
fi
[[ -n "$PROJECT" ]] || exit 0

config_path="$REPO/polaris-config/$PROJECT/handbook/config.yaml"
index_path="$REPO/polaris-config/$PROJECT/handbook/index.md"
if [[ ! -e "$config_path" && ! -e "$index_path" ]]; then
  if find "$REPO/polaris-config" -mindepth 3 -maxdepth 3 \
      \( -path '*/handbook/config.yaml' -o -path '*/handbook/index.md' \) \
      -type f -print -quit 2>/dev/null | grep -q .; then
    echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:project_mapping_not_found:$PROJECT" >&2
    exit 1
  fi
  exit 0
fi

runtime_dir="${POLARIS_RUNTIME_DIR:-$REPO/.polaris/runtime}"
marker_dir="$runtime_dir/handbook-load"
marker_path="$(python3 - "$marker_dir" "$REPO" "$SESSION_ID" <<'PY'
import hashlib, os, sys
directory, repo, session = sys.argv[1:]
digest = hashlib.sha256((os.path.realpath(repo) + "\0" + session).encode()).hexdigest()[:24]
print(os.path.join(directory, digest + ".json"))
PY
)"

if [[ -f "$marker_path" ]] && python3 - "$marker_path" "$REPO" "$SESSION_ID" <<'PY'
import json, os, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if data.get("repo") == os.path.realpath(sys.argv[2]) and data.get("session_id") == sys.argv[3] else 1)
PY
then
  exit 0
fi

if [[ ! -x "$RESOLVER" ]]; then
  echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:resolver_unavailable:$RESOLVER" >&2
  exit 1
fi

if ! payload="$("$RESOLVER" --scope-root "$REPO" --scope-id "$PROJECT" 2>&1)"; then
  echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:resolver_failed:$payload" >&2
  exit 1
fi

if ! index="$(python3 - "$payload" "$REPO" "$PROJECT" "$config_path" "$index_path" <<'PY'
import json, os, sys
try:
    data = json.loads(sys.argv[1])
except Exception as exc:
    print(f"invalid resolver JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)
required = ("config_path", "index_path", "scope_root", "scope_id")
if any(not isinstance(data.get(key), str) or not data[key] for key in required):
    print("resolver payload missing required path identity", file=sys.stderr)
    raise SystemExit(1)
if os.path.realpath(data["scope_root"]) != os.path.realpath(sys.argv[2]) or data["scope_id"] != sys.argv[3]:
    print("resolver payload identity mismatch", file=sys.stderr)
    raise SystemExit(1)
if os.path.realpath(data["config_path"]) != os.path.realpath(sys.argv[4]):
    print("resolver config path is outside canonical project mapping", file=sys.stderr)
    raise SystemExit(1)
if os.path.realpath(data["index_path"]) != os.path.realpath(sys.argv[5]):
    print("resolver index path is outside canonical project mapping", file=sys.stderr)
    raise SystemExit(1)
if not os.path.isfile(data["config_path"]) or not os.path.isfile(data["index_path"]):
    print("resolver payload paths do not exist", file=sys.stderr)
    raise SystemExit(1)
print(data["index_path"])
PY
)"; then
  echo "POLARIS_HANDBOOK_LOAD_GATE_BLOCKED:broken_payload" >&2
  exit 1
fi

mkdir -p "$marker_dir"
python3 - "$marker_path" "$REPO" "$SESSION_ID" "$PROJECT" "$index" <<'PY'
import json, os, sys, tempfile
path, repo, session, project, index = sys.argv[1:]
data = {
    "schema_version": 1,
    "marker_kind": "handbook_load",
    "repo": os.path.realpath(repo),
    "session_id": session,
    "project": project,
    "index_path": os.path.realpath(index),
}
directory = os.path.dirname(path)
fd, tmp = tempfile.mkstemp(prefix=".handbook-load.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY

printf 'HANDBOOK_INDEX=%s\n' "$index"
