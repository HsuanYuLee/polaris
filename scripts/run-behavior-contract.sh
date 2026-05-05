#!/usr/bin/env bash
set -euo pipefail

# run-behavior-contract.sh — deterministic behavior contract evidence runner.
#
# Usage:
#   bash scripts/run-behavior-contract.sh --task-md <task.md> --mode baseline|compare [--repo <path>] [--ticket <KEY>]

PREFIX="[polaris behavior-contract]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"
TASK_MD=""
MODE=""
REPO_OVERRIDE=""
TICKET_OVERRIDE=""
WORKTREE_DIR=""
TMP_STDOUT=""
TMP_STDERR=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  run-behavior-contract.sh --task-md <task.md> --mode baseline|compare [--repo <path>] [--ticket <KEY>]
USAGE
}

cleanup() {
  rm -f "${TMP_STDOUT:-}" "${TMP_STDERR:-}" 2>/dev/null || true
  if [[ -n "${WORKTREE_DIR:-}" && -d "$WORKTREE_DIR" ]]; then
    git -C "$REPO_PATH" worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || rm -rf "$WORKTREE_DIR"
  fi
}
trap cleanup EXIT

safe_slug() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

parse_field() {
  local field="$1"
  "$PARSE_TASK_MD" --field "$field" "$TASK_MD" 2>/dev/null || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --repo) REPO_OVERRIDE="${2:-}"; shift 2 ;;
    --ticket) TICKET_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

case "$MODE" in
  baseline|compare) ;;
  *) echo "$PREFIX --mode must be baseline or compare" >&2; usage; exit 64 ;;
esac
if [[ -z "$TASK_MD" || ! -f "$TASK_MD" ]]; then
  echo "$PREFIX --task-md is required and must exist" >&2
  exit 64
fi

contract_json="$(python3 - "$TASK_MD" <<'PY'
import csv
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()

def parse_scalar(value):
    value = value.strip()
    if value == "":
        return None
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [parse_scalar(part.strip()) for part in next(csv.reader([body], skipinitialspace=True))]
    if value == "true":
        return True
    if value == "false":
        return False
    return value

def frontmatter(all_lines):
    if not all_lines or all_lines[0].strip() != "---":
        return []
    for idx in range(1, len(all_lines)):
        if all_lines[idx].strip() == "---":
            return all_lines[1:idx]
    return []

def behavior_contract(fm_lines):
    in_verification = False
    in_behavior = False
    current_list_key = None
    data = None
    for raw in fm_lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw.strip()
        if indent == 0:
            in_behavior = False
            current_list_key = None
            if ":" not in stripped:
                in_verification = False
                continue
            key, _, value = stripped.partition(":")
            in_verification = key.strip() == "verification" and value.strip() == ""
            continue
        if not in_verification:
            continue
        if indent == 2 and ":" in stripped:
            current_list_key = None
            key, _, value = stripped.partition(":")
            if key.strip() == "behavior_contract":
                parsed = parse_scalar(value.strip())
                data = {} if parsed is None else parsed
                in_behavior = isinstance(data, dict)
            else:
                in_behavior = False
            continue
        if data is None or not isinstance(data, dict) or not in_behavior:
            continue
        if indent == 4 and ":" in stripped:
            key, _, value = stripped.partition(":")
            key = key.strip()
            value = value.strip()
            if value == "":
                data[key] = []
                current_list_key = key
            else:
                data[key] = parse_scalar(value)
                current_list_key = None
            continue
        if current_list_key and indent >= 6 and stripped.startswith("- "):
            data[current_list_key].append(parse_scalar(stripped[2:].strip()))
    return data

print(json.dumps(behavior_contract(frontmatter(lines)) or {}, ensure_ascii=False, sort_keys=True))
PY
)"

applies="$(python3 -c 'import json,sys; print("true" if json.loads(sys.argv[1]).get("applies") is True else "false")' "$contract_json")"
if [[ "$applies" != "true" ]]; then
  echo "$PREFIX behavior_contract.applies is not true; no behavior evidence required." >&2
  exit 0
fi

behavior_mode="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("mode",""))' "$contract_json")"
fixture_policy="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("fixture_policy",""))' "$contract_json")"
baseline_ref="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("baseline_ref",""))' "$contract_json")"
target_url="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("target_url",""))' "$contract_json")"
viewport="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("viewport",""))' "$contract_json")"
flow="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("flow",""))' "$contract_json")"
flow_script="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d.get("flow_script") or d.get("script_path") or d.get("playwright_script") or "")' "$contract_json")"

if [[ -z "$flow_script" && "$flow" == */* ]]; then
  flow_script="$flow"
fi

repo_name="$(parse_field repo)"
task_ticket="$(parse_field task_id)"
if [[ -z "$task_ticket" ]]; then
  task_ticket="$(parse_field task_jira_key)"
fi
TICKET="${TICKET_OVERRIDE:-$task_ticket}"
if [[ -z "$TICKET" ]]; then
  echo "$PREFIX could not resolve task identity" >&2
  exit 1
fi
SAFE_TICKET="$(safe_slug "$TICKET")"

if [[ -n "$REPO_OVERRIDE" ]]; then
  REPO_PATH="$(cd "$REPO_OVERRIDE" && pwd)"
else
  if [[ -z "$repo_name" ]]; then
    echo "$PREFIX could not parse repo from task.md; pass --repo" >&2
    exit 1
  fi
  td="$(cd "$(dirname "$TASK_MD")" && pwd)"
  REPO_PATH=""
  while [[ "$td" != "/" ]]; do
    probe="$td/$repo_name"
    if [[ -d "$probe/.git" || -f "$probe/.git" ]]; then
      REPO_PATH="$(cd "$probe" && pwd)"
      break
    fi
    td="$(dirname "$td")"
  done
fi
if [[ -z "$REPO_PATH" || ! -d "$REPO_PATH" ]]; then
  echo "$PREFIX could not resolve repo path; pass --repo" >&2
  exit 1
fi

RUN_REPO="$REPO_PATH"
if [[ "$MODE" == "baseline" && -n "$baseline_ref" && "$baseline_ref" != "none" && "$baseline_ref" != "N/A" ]]; then
  if git -C "$REPO_PATH" rev-parse --verify "${baseline_ref}^{commit}" >/dev/null 2>&1; then
    WORKTREE_DIR="$(mktemp -d -t polaris-behavior-base.XXXXXX)"
    rm -rf "$WORKTREE_DIR"
    git -C "$REPO_PATH" worktree add --detach "$WORKTREE_DIR" "$baseline_ref" >/dev/null
    RUN_REPO="$WORKTREE_DIR"
  fi
fi

HEAD_SHA="$(git -C "$RUN_REPO" rev-parse HEAD)"
CURRENT_HEAD_SHA="$(git -C "$REPO_PATH" rev-parse HEAD)"
context_hash="$(python3 - "$contract_json" "$TASK_MD" <<'PY'
import hashlib
import json
import sys
payload = {"contract": json.loads(sys.argv[1]), "task_md": sys.argv[2]}
print(hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()[:12])
PY
)"

evidence_root="$REPO_PATH/.polaris/evidence"
behavior_dir="$evidence_root/behavior/$SAFE_TICKET"
artifact_dir="$behavior_dir/${MODE}-${context_hash}-${HEAD_SHA:0:12}"
mkdir -p "$artifact_dir"

script_abs=""
if [[ -n "$flow_script" ]]; then
  if [[ "$flow_script" = /* ]]; then
    script_abs="$flow_script"
  else
    script_abs="$RUN_REPO/$flow_script"
  fi
fi

TMP_STDOUT="$(mktemp -t polaris-behavior-stdout.XXXXXX)"
TMP_STDERR="$(mktemp -t polaris-behavior-stderr.XXXXXX)"
command_rc=0
if [[ -n "$script_abs" && -f "$script_abs" ]]; then
  set +e
  (
    cd "$RUN_REPO"
    POLARIS_BEHAVIOR_MODE="$MODE" \
    POLARIS_BEHAVIOR_OUTPUT_DIR="$artifact_dir" \
    POLARIS_BEHAVIOR_TICKET="$TICKET" \
    POLARIS_BEHAVIOR_HEAD_SHA="$HEAD_SHA" \
    POLARIS_BEHAVIOR_TARGET_URL="$target_url" \
    POLARIS_BEHAVIOR_VIEWPORT="$viewport" \
    bash "$script_abs"
  ) >"$TMP_STDOUT" 2>"$TMP_STDERR"
  command_rc=$?
  set -e
elif [[ "$fixture_policy" == "static_only" ]]; then
  printf '{"flow":"%s","assertions_only":true}\n' "$flow" >"$artifact_dir/behavior-state.json"
  : >"$TMP_STDOUT"
  : >"$TMP_STDERR"
else
  echo "$PREFIX behavior flow script not found: ${flow_script:-<empty>}" >"$TMP_STDERR"
  command_rc=1
fi

baseline_file=""
baseline_state_hash=""
if [[ "$MODE" == "compare" && ( "$behavior_mode" == "parity" || "$behavior_mode" == "hybrid" ) ]]; then
  baseline_file="$(python3 - "$behavior_dir" "$context_hash" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
context_hash = sys.argv[2]
matches = []
if root.is_dir():
    for path in root.glob(f"polaris-behavior-*-{context_hash}.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if data.get("mode") == "baseline" and data.get("status") == "PASS":
            matches.append((path.stat().st_mtime, path, data.get("state_hash", "")))
if matches:
    matches.sort(reverse=True)
    print(str(matches[0][1]) + "\t" + str(matches[0][2]))
PY
)"
  baseline_state_hash="${baseline_file#*$'\t'}"
  baseline_file="${baseline_file%%$'\t'*}"
  if [[ -z "$baseline_file" ]]; then
    echo "$PREFIX missing baseline behavior evidence for $TICKET context=$context_hash" >&2
    exit 1
  fi
fi

tmp_evidence="/tmp/polaris-behavior-${SAFE_TICKET}-${HEAD_SHA}-${context_hash}.json"
durable_evidence="$behavior_dir/polaris-behavior-${SAFE_TICKET}-${HEAD_SHA}-${context_hash}.json"

python3 - "$contract_json" "$MODE" "$behavior_mode" "$TICKET" "$SAFE_TICKET" "$HEAD_SHA" "$CURRENT_HEAD_SHA" "$context_hash" "$REPO_PATH" "$RUN_REPO" "$artifact_dir" "$script_abs" "$TMP_STDOUT" "$TMP_STDERR" "$command_rc" "$baseline_file" "$baseline_state_hash" "$tmp_evidence" "$durable_evidence" <<'PY'
import datetime as dt
import hashlib
import json
from pathlib import Path
import shutil
import sys

(
    contract_json,
    mode,
    behavior_mode,
    ticket,
    safe_ticket,
    head_sha,
    current_head_sha,
    context_hash,
    repo_path,
    run_repo,
    artifact_dir,
    script_abs,
    stdout_path,
    stderr_path,
    command_rc,
    baseline_file,
    baseline_state_hash,
    tmp_evidence,
    durable_evidence,
) = sys.argv[1:20]

contract = json.loads(contract_json)
artifact_root = Path(artifact_dir)
stdout_text = Path(stdout_path).read_text(encoding="utf-8", errors="replace")
stderr_text = Path(stderr_path).read_text(encoding="utf-8", errors="replace")

def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

screenshots = sorted(str(path) for ext in ("*.png", "*.jpg", "*.jpeg") for path in artifact_root.rglob(ext))
videos = sorted(str(path) for ext in ("*.webm", "*.mp4") for path in artifact_root.rglob(ext))
state_path = None
for candidate in (artifact_root / "behavior-state.json", artifact_root / "state.json"):
    if candidate.is_file():
        state_path = candidate
        break
state_hash = sha256_file(state_path) if state_path else sha256_bytes(stdout_text.encode("utf-8"))

command_pass = int(command_rc) == 0
status = "PASS" if command_pass else "FAIL"
comparison = {"kind": "none", "status": status}
if command_pass and mode == "compare" and behavior_mode in {"parity", "hybrid"}:
    drift = state_hash != baseline_state_hash
    if not drift:
        comparison = {"kind": "state_hash", "status": "PASS", "drift": False}
        status = "PASS"
    elif behavior_mode == "hybrid" and contract.get("allowed_differences"):
        comparison = {
            "kind": "state_hash",
            "status": "PASS",
            "drift": True,
            "accepted_by_allowed_differences": contract.get("allowed_differences", []),
        }
        status = "PASS"
    else:
        comparison = {"kind": "state_hash", "status": "FAIL", "drift": True}
        status = "FAIL"
elif command_pass and mode == "compare":
    comparison = {"kind": "flow_assertions", "status": "PASS"}

data = {
    "schema_version": 1,
    "ticket": ticket,
    "safe_ticket": safe_ticket,
    "head_sha": head_sha,
    "current_head_sha": current_head_sha,
    "mode": mode,
    "behavior_mode": behavior_mode,
    "status": status,
    "writer": "run-behavior-contract.sh",
    "at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "context_hash": context_hash,
    "contract": contract,
    "flow_script": script_abs or "N/A",
    "execution_cwd": str(run_repo),
    "artifact_dir": str(artifact_root),
    "screenshots": screenshots,
    "videos": videos,
    "state_file": str(state_path) if state_path else "N/A",
    "state_hash": state_hash,
    "stdout_hash": sha256_bytes(stdout_text.encode("utf-8")),
    "stderr_hash": sha256_bytes(stderr_text.encode("utf-8")),
    "exit_code": int(command_rc),
    "baseline_evidence": baseline_file or "N/A",
    "baseline_state_hash": baseline_state_hash or "N/A",
    "comparison": comparison,
}

for output in (Path(tmp_evidence), Path(durable_evidence)):
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

print(json.dumps({"status": status, "tmp": tmp_evidence, "durable": durable_evidence}, ensure_ascii=False))
PY

status="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["status"])' "$(cat "$tmp_evidence")")"
if [[ "$status" != "PASS" ]]; then
  echo "$PREFIX FAIL — evidence at $tmp_evidence" >&2
  exit 1
fi

echo "$PREFIX PASS — mode=$MODE evidence at $tmp_evidence" >&2
echo "$PREFIX durable evidence mirror at $durable_evidence" >&2
