#!/usr/bin/env bash
set -euo pipefail

PREFIX="[polaris release-surface]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"

TASK_MD=""
FORMAT="text"
FIELD=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/resolve-release-surface.sh --task-md <path> [--format text|json|field] [--field <name>]

Output:
  text   SURFACE class=<none|developer_pr|package_release|local_extension|ambiguous> release_required=<true|false>
  json   { "class": "...", "release_required": true|false, "surface_signals": [...], "ambiguity_reasons": [...] }
  field  one of: class, release_required

Exit:
  0   success
  64  invalid usage / parse failure
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --field) FIELD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

[[ -n "$TASK_MD" ]] || { echo "$PREFIX --task-md is required" >&2; usage; exit 64; }
[[ -f "$TASK_MD" ]] || { echo "$PREFIX task.md not found: $TASK_MD" >&2; exit 64; }
[[ "$FORMAT" == "text" || "$FORMAT" == "json" || "$FORMAT" == "field" ]] || {
  echo "$PREFIX --format must be text, json, or field" >&2
  exit 64
}
if [[ "$FORMAT" == "field" ]]; then
  [[ "$FIELD" == "class" || "$FIELD" == "release_required" ]] || {
    echo "$PREFIX --field must be class or release_required" >&2
    exit 64
  }
fi

task_json="$(bash "$PARSE_TASK_MD" "$TASK_MD" --no-resolve 2>/dev/null)" || {
  echo "$PREFIX failed to parse task.md: $TASK_MD" >&2
  exit 64
}

python3 - "$FORMAT" "$FIELD" "$task_json" <<'PY'
import json
import sys

fmt = sys.argv[1]
field = sys.argv[2]
data = json.loads(sys.argv[3])
frontmatter = data.get("frontmatter") or {}

deliverable = frontmatter.get("deliverable")
if not isinstance(deliverable, dict):
    deliverable = None

deliverables = frontmatter.get("deliverables")
if not isinstance(deliverables, dict):
    deliverables = {}
changeset = deliverables.get("changeset")
if not isinstance(changeset, dict):
    changeset = None

extension = frontmatter.get("extension_deliverable")
if not isinstance(extension, dict):
    extension = None

surface_signals = []
ambiguity_reasons = []

if extension is not None:
    endpoint = extension.get("endpoint")
    if endpoint == "local_extension":
        surface_signals.append("local_extension")
    else:
        ambiguity_reasons.append("extension_deliverable_without_local_extension_endpoint")

if changeset is not None:
    if any(changeset.get(key) not in (None, "") for key in ("package_scope", "bump_level_default", "filename_slug")):
        surface_signals.append("package_release")

if deliverable is not None:
    pr_url = deliverable.get("pr_url")
    if pr_url:
        surface_signals.append("developer_pr")
    else:
        ambiguity_reasons.append("deliverable_without_pr_url")

if ambiguity_reasons:
    klass = "ambiguous"
elif "local_extension" in surface_signals:
    klass = "local_extension"
elif "package_release" in surface_signals:
    klass = "package_release"
elif "developer_pr" in surface_signals:
    klass = "developer_pr"
else:
    klass = "none"

release_required = klass != "none"

payload = {
    "class": klass,
    "release_required": release_required,
    "surface_signals": surface_signals,
    "ambiguity_reasons": ambiguity_reasons,
}

if fmt == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2))
elif fmt == "field":
    value = payload[field]
    if isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)
else:
    print(
        "SURFACE class={klass} release_required={required}".format(
            klass=klass,
            required="true" if release_required else "false",
        )
    )
PY
