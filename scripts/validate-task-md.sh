#!/usr/bin/env bash
# validate-task-md.sh — full enforcer for task.md schema (T{n}.md + V{n}.md, dual-path).
#
# Usage:
#   validate-task-md.sh <path/to/task.md>
#   validate-task-md.sh --scan <workspace_root>
#
# Exit:  0 = schema pass (single) / scan complete (scan mode, always 0)
#        1 = schema violations (single mode; details printed to stderr)
#        2 = hard fail — completion invariant violated (status: IMPLEMENTED in tasks/)
#            OR usage error / file not found
#
# Schema source:  skills/references/task-md-schema.md (DP-033 Phase A + Phase B, single source of truth)
# Called by:      skills/breakdown/SKILL.md Step 14.5 (after Write)
#                 .claude/hooks/pipeline-artifact-gate.sh (PreToolUse hook)
#
# Mode dispatch (DP-033 Phase B):
#   filename T*.md → T mode (Implementation Schema, § 3)
#   filename V*.md → V mode (Verification Schema, § 4)
#   filename 由 entry 偵測；mode 為 唯一 type 訊號（DP-033 D2，frontmatter 無 type 欄位）
#   T/V 共用：Title regex / Header / status invariant / Test Environment / jira_transition_log /
#             pr-release-skip / move-first / depends_on schema (cross-file, validate-task-md-deps.sh)
#   T-only:   ## 改動範圍 / ## Allowed Files / ## Test Command / ## Verify Command /
#             Operational Context Test sub-tasks/AC 驗收單/Task branch cells /
#             DP-028 Depends on ⇒ task/ Base branch cross-field /
#             deliverable / extension_deliverable lifecycle
#   V-only:   ## 驗收項目 / ## 驗收步驟 / Operational Context Implementation tasks cell /
#             ac_verification + ac_verification_log lifecycle (§ 4.7 對稱 D7)
#
# DP history:
#   DP-023 — runtime contract fields (Level / Runtime verify target / Env bootstrap)
#   DP-025 — non-runtime required sections (Operational Context JIRA keys, 改動範圍 / 估點理由 non-empty)
#   DP-028 — cross-field rule: Depends on (non-empty) ⇒ Base branch must be task/...
#   DP-032 — lifecycle write-back: deliverable / jira_transition_log
#   DP-033 — Phase A enforcer (D5/D6/D7 T mode); Phase B V mode dual-path + ac_verification
#   DP-048 — local_extension release metadata lifecycle

set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $0 <path/to/task.md>
       $0 --scan <workspace_root>
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

# ---------------------------------------------------------------------------
# Helper: extract all content lines under a markdown section heading.
# Stops at the next ## heading.
# ---------------------------------------------------------------------------
extract_markdown_section() {
  local file="$1"
  local heading="$2"
  awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract the first fenced code block from stdin.
# ---------------------------------------------------------------------------
extract_first_fenced_code_block() {
  awk '
    /^```/ {
      if (in_block == 0) { in_block=1; next }
      exit
    }
    in_block { print }
  '
}

verify_command_static_smoke() {
  local file="$1"
  local command="$2"

  python3 - "$file" "$command" <<'PY'
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse

task_path = Path(sys.argv[1])
command = sys.argv[2]
repo_root = Path.cwd()
errors = []

def script_supported_flags(script: Path):
    if not script.is_file():
        return None
    try:
        proc = subprocess.run(
            ["bash", str(script), "--help"],
            cwd=repo_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    except Exception:
        return None
    if proc.returncode not in (0, 2):
        return None
    help_text = f"{proc.stdout}\n{proc.stderr}"
    flags = set(re.findall(r"(?<!\w)--[A-Za-z][A-Za-z0-9_-]*", help_text))
    return flags or None

def smoke_script_flags(line: str, tokens: list[str]):
    script_idx = None
    for idx, token in enumerate(tokens):
        if token.startswith("scripts/") and token.endswith(".sh"):
            script_idx = idx
            break
    if script_idx is None:
        return
    script = repo_root / tokens[script_idx]
    if not script.is_file():
        errors.append(f"Verify Command references missing repo-local script: {tokens[script_idx]} (line: {line})")
        return
    supported = script_supported_flags(script)
    if supported is None:
        return
    used = []
    for token in tokens[script_idx + 1:]:
        if token == "--":
            break
        if token.startswith("--"):
            used.append(token.split("=", 1)[0])
    for flag in used:
        if flag not in supported:
            errors.append(
                f"Verify Command uses unsupported flag {flag} for {tokens[script_idx]} (line: {line})"
            )

def smoke_rg_pattern(line: str, tokens: list[str]):
    if not tokens or tokens[0] != "rg":
        return
    pattern = None
    skip_next = False
    option_args = {
        "-e", "--regexp", "-g", "--glob", "-t", "--type", "-T", "--type-not",
        "-A", "--after-context", "-B", "--before-context", "-C", "--context",
        "-m", "--max-count", "--max-depth", "--max-filesize",
    }
    for idx, token in enumerate(tokens[1:], start=1):
        if skip_next:
            skip_next = False
            continue
        if token == "--":
            if idx + 1 < len(tokens):
                pattern = tokens[idx + 1]
            break
        if token in option_args:
            if token in {"-e", "--regexp"} and idx + 1 < len(tokens):
                pattern = tokens[idx + 1]
                break
            skip_next = True
            continue
        if token.startswith("-"):
            continue
        pattern = token
        break
    if not pattern:
        return
    with tempfile.NamedTemporaryFile("w", delete=False) as handle:
        tmp = handle.name
    try:
        proc = subprocess.run(
            ["rg", "-q", "--regexp", pattern, tmp],
            cwd=repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
    except FileNotFoundError:
        return
    except Exception as exc:
        errors.append(f"Verify Command rg smoke failed unexpectedly (line: {line}): {exc}")
        return
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    if proc.returncode == 2:
        detail = proc.stderr.strip().splitlines()[0] if proc.stderr.strip() else "regex parse error"
        errors.append(f"Verify Command rg pattern parse failed: {pattern!r} (line: {line}) — {detail}")

def command_lines(script: str):
    for raw in script.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(("if ", "for ", "while ", "then", "fi", "do", "done", "else", "elif ")):
            continue
        yield line

for line in command_lines(command):
    try:
        tokens = shlex.split(line, comments=False, posix=True)
    except ValueError:
        continue
    if not tokens:
        continue
    if tokens[0] in {"env", "timeout", "command"} and len(tokens) > 1:
        tokens = tokens[1:]
    if tokens and tokens[0] == "bash" and len(tokens) > 1:
        smoke_script_flags(line, tokens)
    elif tokens and tokens[0].startswith("scripts/") and tokens[0].endswith(".sh"):
        smoke_script_flags(line, tokens)
    smoke_rg_pattern(line, tokens)

for error in errors:
    print(error)

raise SystemExit(1 if errors else 0)
PY
}

# ---------------------------------------------------------------------------
# Helper: extract the value cell of an Operational Context table row.
# task.md convention: `| {field} | {value} |`
# Returns the trimmed value; empty string if field is not present.
# ---------------------------------------------------------------------------
extract_op_ctx_field() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    /^\|/ {
      n = split($0, fields, "|")
      if (n < 4) next
      name = fields[2]; val = fields[3]
      sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+$/, "", name)
      sub(/^[[:space:]]+/, "", val);  sub(/[[:space:]]+$/, "", val)
      if (name == field) { print val; exit }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract a YAML scalar from the frontmatter block (first --- block).
# Returns the trimmed value for a top-level key: "key: value".
# Outputs nothing if key is absent or has a complex (block/list) value.
# ---------------------------------------------------------------------------
extract_frontmatter_scalar() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 {
      if (/^[[:space:]]/) next   # skip indented (nested) lines
      n = split($0, parts, ":")
      if (n >= 2) {
        k = parts[1]
        sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
        if (k == key) {
          val = $0
          sub(/^[^:]*:[[:space:]]*/, "", val)
          sub(/[[:space:]]+$/, "", val)
          print val
          exit
        }
      }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: check if a top-level YAML key exists in the frontmatter block.
# Returns 0 if found, 1 if not.
# ---------------------------------------------------------------------------
frontmatter_key_exists() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 {
      if (/^[[:space:]]/) next
      n = split($0, parts, ":")
      if (n >= 2) {
        k = parts[1]
        sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
        if (k == key) { found=1; exit }
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract raw frontmatter block (between first --- delimiters).
# ---------------------------------------------------------------------------
extract_frontmatter_block() {
  local file="$1"
  awk '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract frontmatter verification.visual_regression state as JSON.
# This mirrors the YAML subset supported by parse-task-md.sh without adding a
# PyYAML dependency to the validator.
# ---------------------------------------------------------------------------
extract_vr_frontmatter_state() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    lines = open(path, "r", encoding="utf-8").read().splitlines()
except OSError:
    print(json.dumps({"present": False}))
    raise SystemExit(0)

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
        return [parse_scalar(part.strip()) for part in body.split(",")]
    if value == "true":
        return True
    if value == "false":
        return False
    return value

def parse_frontmatter_lines(fm_lines):
    out = {}
    i = 0
    while i < len(fm_lines):
        raw = fm_lines[i]
        if not raw.strip() or raw.lstrip().startswith("#") or raw[0].isspace() or ":" not in raw:
            i += 1
            continue
        key, _, value = raw.partition(":")
        key = key.strip()
        value = value.strip()
        if value:
            out[key] = parse_scalar(value)
            i += 1
            continue

        mapping = {}
        i += 1
        while i < len(fm_lines):
            child_raw = fm_lines[i]
            if not child_raw.strip():
                i += 1
                continue
            child_indent = len(child_raw) - len(child_raw.lstrip(" "))
            if child_indent == 0:
                break
            child_stripped = child_raw.strip()
            if child_indent != 2 or ":" not in child_stripped:
                i += 1
                continue
            child_key, _, child_value = child_stripped.partition(":")
            child_key = child_key.strip()
            child_value = child_value.strip()
            if child_value:
                mapping[child_key] = parse_scalar(child_value)
                i += 1
                continue

            nested = {}
            i += 1
            while i < len(fm_lines):
                nested_raw = fm_lines[i]
                if not nested_raw.strip():
                    i += 1
                    continue
                nested_indent = len(nested_raw) - len(nested_raw.lstrip(" "))
                if nested_indent <= 2:
                    break
                nested_stripped = nested_raw.strip()
                if nested_indent == 4 and ":" in nested_stripped:
                    nested_key, _, nested_value = nested_stripped.partition(":")
                    nested[nested_key.strip()] = parse_scalar(nested_value.strip())
                i += 1
            mapping[child_key] = nested
        out[key] = mapping
    return out

frontmatter = {}
if lines and lines[0].strip() == "---":
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is not None:
        frontmatter = parse_frontmatter_lines(lines[1:end])

verification = frontmatter.get("verification")
vr = verification.get("visual_regression") if isinstance(verification, dict) else None
result = {
    "present": vr is not None,
    "is_map": isinstance(vr, dict),
    "expected": None,
    "expected_is_string": False,
    "pages_present": False,
    "pages_is_list": False,
}
if isinstance(vr, dict):
    expected = vr.get("expected")
    pages = vr.get("pages")
    result["expected"] = expected
    result["expected_is_string"] = isinstance(expected, str)
    result["pages_present"] = "pages" in vr
    result["pages_is_list"] = isinstance(pages, list)
print(json.dumps(result, ensure_ascii=False))
PY
}

# ---------------------------------------------------------------------------
# Helper: validate frontmatter verification.behavior_contract.
# The validator intentionally uses a small YAML subset parser to avoid adding a
# PyYAML dependency. Missing behavior_contract is allowed here; producer
# readiness / migration gates decide when the field is mandatory.
# ---------------------------------------------------------------------------
validate_behavior_contract_frontmatter() {
  local file="$1"
  python3 - "$file" <<'PY'
import csv
import sys

path = sys.argv[1]
try:
    lines = open(path, "r", encoding="utf-8").read().splitlines()
except OSError:
    raise SystemExit(0)

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

def extract_frontmatter(all_lines):
    if not all_lines or all_lines[0].strip() != "---":
        return []
    for idx in range(1, len(all_lines)):
        if all_lines[idx].strip() == "---":
            return all_lines[1:idx]
    return []

def extract_behavior_contract(fm_lines):
    in_verification = False
    in_behavior = False
    behavior = None
    current_list_key = None

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
                behavior = {} if parsed is None else parsed
                in_behavior = isinstance(behavior, dict)
            else:
                in_behavior = False
            continue

        if behavior is None or not isinstance(behavior, dict) or not in_behavior:
            continue

        if indent == 4 and ":" in stripped:
            key, _, value = stripped.partition(":")
            key = key.strip()
            value = value.strip()
            if value == "":
                behavior[key] = []
                current_list_key = key
            else:
                behavior[key] = parse_scalar(value)
                current_list_key = None
            continue

        if current_list_key and indent >= 6 and stripped.startswith("- "):
            behavior[current_list_key].append(parse_scalar(stripped[2:].strip()))

    return behavior

def is_nonempty_string(value):
    return isinstance(value, str) and value.strip() != ""

bc = extract_behavior_contract(extract_frontmatter(lines))
if bc is None:
    raise SystemExit(0)

errors = []
if not isinstance(bc, dict):
    errors.append("frontmatter verification.behavior_contract must be a map")
else:
    applies = bc.get("applies")
    if not isinstance(applies, bool):
        errors.append("frontmatter verification.behavior_contract.applies is required and must be true or false")
    elif not applies:
        if not is_nonempty_string(bc.get("reason")):
            errors.append("frontmatter verification.behavior_contract.reason is required when applies=false")
    else:
        mode = bc.get("mode")
        if mode not in {"parity", "visual_target", "pm_flow", "hybrid"}:
            errors.append("frontmatter verification.behavior_contract.mode must be parity, visual_target, pm_flow, or hybrid")

        source = bc.get("source_of_truth")
        if source not in {"existing_behavior", "figma", "pm_flow", "spec"}:
            errors.append("frontmatter verification.behavior_contract.source_of_truth must be existing_behavior, figma, pm_flow, or spec")

        fixture_policy = bc.get("fixture_policy")
        if fixture_policy not in {"mockoon_required", "live_allowed", "static_only"}:
            errors.append("frontmatter verification.behavior_contract.fixture_policy must be mockoon_required, live_allowed, or static_only")

        if "baseline_ref" in bc and not is_nonempty_string(bc.get("baseline_ref")):
            errors.append("frontmatter verification.behavior_contract.baseline_ref must be a non-empty string when present")

        if "target_url" in bc and not is_nonempty_string(bc.get("target_url")):
            errors.append("frontmatter verification.behavior_contract.target_url must be a non-empty string when present")

        viewport = bc.get("viewport")
        if viewport is not None and viewport not in {"mobile", "desktop", "responsive"}:
            errors.append("frontmatter verification.behavior_contract.viewport must be mobile, desktop, or responsive when present")

        if not is_nonempty_string(bc.get("flow")):
            errors.append("frontmatter verification.behavior_contract.flow is required when applies=true")

        assertions = bc.get("assertions")
        if not isinstance(assertions, list) or not assertions:
            errors.append("frontmatter verification.behavior_contract.assertions must be a non-empty YAML list when applies=true")
        elif any(not is_nonempty_string(item) for item in assertions):
            errors.append("frontmatter verification.behavior_contract.assertions entries must be non-empty strings")

        allowed_differences = bc.get("allowed_differences")
        if allowed_differences is not None and not isinstance(allowed_differences, list):
            errors.append("frontmatter verification.behavior_contract.allowed_differences must be a YAML list when present")
        elif mode == "hybrid" and not allowed_differences:
            errors.append("frontmatter verification.behavior_contract.allowed_differences must be non-empty when mode=hybrid")

for error in errors:
    print(error)
PY
}

# ---------------------------------------------------------------------------
# Helper: task identity grammar.
# Product tasks use JIRA keys (PROJ-123). Framework DP-backed work orders use
# pseudo IDs (DP-047-T1 / DP-047-V1) but otherwise follow the same task.md schema.
# ---------------------------------------------------------------------------
is_valid_task_identity() {
  local value="$1"
  [[ "$value" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ || "$value" =~ ^DP-[0-9]{3}-[TV][0-9]+[a-z]*$ ]]
}

is_valid_jira_key() {
  local value="$1"
  [[ "$value" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]
}

is_na_value() {
  local value
  value=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)
  [[ -z "$value" || "$value" == "n/a" || "$value" == "-" || "$value" == "none" || "$value" == "無" ]]
}

extract_header_token() {
  local file="$1"
  local label="$2"
  awk -v label="$label" '
    /^> / {
      line = $0
      n = split(line, parts, "|")
      for (i = 1; i <= n; i++) {
        part = parts[i]
        sub(/^>[[:space:]]*/, "", part)
        sub(/^[[:space:]]+/, "", part)
        sub(/[[:space:]]+$/, "", part)
        prefix = label ":[[:space:]]*"
        if (part ~ "^" prefix) {
          sub("^" prefix, "", part)
          sub(/[[:space:]]+$/, "", part)
          print part
          exit
        }
      }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Main single-file validator.
# Returns 0 (pass) / 1 (violations) / 2 (hard fail — completion invariant).
# Writes all output to stderr.
# ---------------------------------------------------------------------------
validate_file() {
  local FILE="$1"

  if [[ ! -f "$FILE" ]]; then
    echo "error: file not found: $FILE" >&2
    return 2
  fi

  # --- G: Skip rule — files under tasks/pr-release/ are never validated (DP-033 D6) ---
  case "$FILE" in
    */tasks/pr-release/*)
      return 0
      ;;
  esac

  # --- Mode detection (DP-033 Phase B): filename pattern → schema mode ---
  local _basename mode verify_section_name
  _basename=$(basename "$FILE")
  if [[ "$_basename" == "index.md" ]]; then
    _basename="$(basename "$(dirname "$FILE")").md"
  fi
  case "$_basename" in
    T[0-9]*.md)  mode="T" ;;
    V[0-9]*.md)  mode="V" ;;
    *)
      # Fallback: file is not a T*.md or V*.md → apply T mode (backward compat)
      # for legacy/unknown filenames; the dispatch hook should have routed
      # canonical V*.md / T*.md before this point.
      mode="T"
      ;;
  esac
  # Driver section that holds the executable / step block:
  #   T mode: ## Verify Command  (deterministic shell, fenced code block)
  #   V mode: ## 驗收步驟        (verify-AC LLM driver entry + per-AC step list)
  if [[ "$mode" == "V" ]]; then
    verify_section_name="## 驗收步驟"
  else
    verify_section_name="## Verify Command"
  fi

  local errors=()
  local warnings=()

  # ---------------------------------------------------------------------------
  # § 5.5 Hard invariant — completion location (exit 2, DP-033 D6)
  # If frontmatter status: IMPLEMENTED AND file is NOT in tasks/pr-release/ → HARD FAIL.
  # move-first contract: mark-spec-implemented.sh always mv before updating frontmatter,
  # so the only way to hit this is a manual edit that bypassed the helper.
  # ---------------------------------------------------------------------------
  local fm_status
  fm_status=$(extract_frontmatter_scalar "$FILE" "status" 2>/dev/null || true)
  if [[ "$fm_status" == "IMPLEMENTED" ]]; then
    echo "✗✗ HARD FAIL (exit 2) — task.md completion invariant violated in $FILE:" >&2
    echo "   frontmatter 'status: IMPLEMENTED' but file is NOT in tasks/pr-release/." >&2
    echo "   Fix: run 'scripts/mark-spec-implemented.sh' (move-first: mv tasks/T.md tasks/pr-release/T.md → update frontmatter)." >&2
    echo "   Reference: skills/references/task-md-schema.md § 5.5 + DP-033 D6" >&2
    return 2
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Title line regex (§ 2.2)
  # ^# (T|V)[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)
  # ---------------------------------------------------------------------------
  if ! grep -qE '^# (T|V)[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)' "$FILE"; then
    errors+=("missing or malformed title: expected '# T{n}[suffix]: {summary} ({SP} pt)' — regex: ^# (T|V)[0-9]+[a-z]*: .+\\([0-9.]+ ?pt\\)")
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Header metadata line — task identity + Repo (§ 2.3 / DP-050)
  # SOFT: Epic (warn only — Bug tasks may omit Epic)
  # ---------------------------------------------------------------------------
  local header_jira_token header_task_token
  header_jira_token="$(extract_header_token "$FILE" "JIRA")"
  header_task_token="$(extract_header_token "$FILE" "Task")"
  if [[ -n "$header_task_token" ]]; then
    if ! is_valid_task_identity "$header_task_token"; then
      errors+=("invalid Task identity in metadata line: got '$header_task_token' (expected JIRA key like PROJ-123 or DP pseudo identity like DP-047-T1 / DP-047-V1)")
    fi
    if [[ -n "$header_jira_token" ]] && ! is_na_value "$header_jira_token" && ! is_valid_jira_key "$header_jira_token"; then
      errors+=("invalid JIRA key in metadata line: got '$header_jira_token' (expected real JIRA key like PROJ-123 or N/A for DP-backed task)")
    fi
  else
    if [[ -z "$header_jira_token" ]]; then
      errors+=("missing task identity in metadata line: expected legacy 'JIRA: {KEY}' or canonical 'Task: {ID}'")
    elif ! is_valid_task_identity "$header_jira_token"; then
      errors+=("invalid task identity in metadata line: got '$header_jira_token' (expected JIRA key like PROJ-123 or legacy DP pseudo identity like DP-047-T1 / DP-047-V1)")
    fi
  fi
  if ! grep -qE '^> .*Repo: \S+' "$FILE"; then
    errors+=("missing Repo in metadata line: expected '> ... | Repo: {repo_name}'")
  fi
  # Soft: Epic: — warn only (Bug tasks are a real no-Epic case, per DP-033 D5)
  if ! grep -qE '^> .*Epic: \S+' "$FILE" && ! grep -qE '^> .*Source: \S+' "$FILE"; then
    warnings+=("metadata line missing 'Epic:' cell — Soft required (Bug tasks may omit; warn only)")
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Section existence (§ 3.1 / § 4.1, mode-aware)
  # ---------------------------------------------------------------------------
  local hard_sections=()
  local soft_sections=()
  if [[ "$mode" == "T" ]]; then
    hard_sections=(
      "## Operational Context"
      "## 改動範圍"
      "## Allowed Files"
      "## 估點理由"
      "## Test Command"
      "## Test Environment"
    )
    soft_sections=(
      "## 目標"
      "## 測試計畫（code-level）"
    )
  else
    # V mode (DP-033 Phase B § 4.1) — symmetric to T but driver section names differ:
    #   T 改動範圍       → V 驗收項目      (語意對稱：T 列檔案改動，V 列 AC 覆蓋)
    #   T 測試計畫 code-level → V 驗收計畫（AC level）
    # T-only sections (Allowed Files / Test Command) are omitted — V doesn't write code.
    # Verify Command analog `## 驗收步驟` is checked separately below (level-conditional).
    hard_sections=(
      "## Operational Context"
      "## 驗收項目"
      "## 估點理由"
      "## Test Environment"
    )
    soft_sections=(
      "## 目標"
      "## 驗收計畫（AC level）"
    )
  fi
  local section
  for section in "${hard_sections[@]}"; do
    if ! grep -qF "$section" "$FILE"; then
      errors+=("missing Hard required section: $section")
    fi
  done
  for section in "${soft_sections[@]}"; do
    if ! grep -qF "$section" "$FILE"; then
      warnings+=("missing Soft required section: $section (warn only — presence expected but not enforced)")
    fi
  done

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Non-empty body checks (§ 3.1)
  # 改動範圍, 估點理由 — must have at least 1 non-blank, non-comment line.
  # ---------------------------------------------------------------------------
  check_section_non_empty() {
    local heading="$1"
    local label="$2"
    if ! grep -qF "$heading" "$FILE"; then
      return  # missing section already reported above
    fi
    local body
    body=$(extract_markdown_section "$FILE" "$heading")
    local content_lines
    content_lines=$(printf '%s\n' "$body" | awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*>/ { next }
      { count++ }
      END { print count+0 }
    ')
    if [[ "$content_lines" -eq 0 ]]; then
      errors+=("section '$heading' body is empty ($label — must have at least 1 non-comment line)")
    fi
  }

  if [[ "$mode" == "T" ]]; then
    check_section_non_empty "## 改動範圍" "Hard required"
  else
    # V mode (§ 4.3): 驗收項目 must be non-empty (≥ 1 markdown row OR bullet)
    if grep -qF "## 驗收項目" "$FILE"; then
      local v_body
      v_body=$(extract_markdown_section "$FILE" "## 驗收項目")
      local v_lines
      v_lines=$(printf '%s\n' "$v_body" | awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*>/ { next }
        /^[[:space:]]*\|/ { count++ }
        /^[[:space:]]*-/ { count++ }
        END { print count+0 }
      ')
      if [[ "$v_lines" -eq 0 ]]; then
        errors+=("section '## 驗收項目' has no AC entries (Hard required — must have at least one markdown row '|' or bullet '- ')")
      fi
    fi
  fi
  check_section_non_empty "## 估點理由" "Hard required"

  # ---------------------------------------------------------------------------
  # HARD REQUIRED (T mode only): ## Allowed Files — non-empty bullet list (DP-033 D5, no grace)
  # V mode 不寫 code → 不需 Allowed Files。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && grep -qF "## Allowed Files" "$FILE"; then
    local allowed_files_body
    allowed_files_body=$(extract_markdown_section "$FILE" "## Allowed Files")
    local bullet_lines
    bullet_lines=$(printf '%s\n' "$allowed_files_body" | awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*>/ { next }
      /^[[:space:]]*-/ { count++ }
      END { print count+0 }
    ')
    if [[ "$bullet_lines" -eq 0 ]]; then
      errors+=("section '## Allowed Files' has no bullet list entries (Hard required — must have at least one '- ' bullet; A7 migration script can backfill)")
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Operational Context (§ 3.2)
  # Must contain ≥ 1 JIRA key pattern AND all required cells.
  # ---------------------------------------------------------------------------
  if grep -qF "## Operational Context" "$FILE"; then
    local op_ctx
    op_ctx=$(extract_markdown_section "$FILE" "## Operational Context")

    local task_identity
    task_identity="$(extract_op_ctx_field "$FILE" "Task ID")"
    if [[ -z "$task_identity" ]]; then
      task_identity="$(extract_op_ctx_field "$FILE" "Task JIRA key")"
    fi
    if [[ -z "$task_identity" ]]; then
      errors+=("Operational Context section missing task identity value (expected canonical 'Task ID' or legacy 'Task JIRA key')")
    elif ! is_valid_task_identity "$task_identity"; then
      errors+=("Operational Context task identity has invalid value '$task_identity' (expected JIRA key like PROJ-123 or DP pseudo identity like DP-047-T1 / DP-047-V1)")
    fi

    local canonical_identity=0
    if [[ -n "$(extract_op_ctx_field "$FILE" "Task ID")" \
          || -n "$(extract_op_ctx_field "$FILE" "Source type")" \
          || -n "$(extract_op_ctx_field "$FILE" "Source ID")" \
          || -n "$(extract_op_ctx_field "$FILE" "JIRA key")" ]]; then
      canonical_identity=1
    fi

    if [[ "$canonical_identity" -eq 1 ]]; then
      local source_type source_id jira_key_cell
      source_type="$(extract_op_ctx_field "$FILE" "Source type")"
      source_id="$(extract_op_ctx_field "$FILE" "Source ID")"
      jira_key_cell="$(extract_op_ctx_field "$FILE" "JIRA key")"
      case "$source_type" in
        dp|jira) ;;
        *) errors+=("Operational Context canonical identity requires Source type = dp|jira (got: '${source_type:-<empty>}')") ;;
      esac
      if [[ -z "$source_id" ]]; then
        errors+=("Operational Context canonical identity missing Source ID")
      fi
      if [[ -z "$(extract_op_ctx_field "$FILE" "Task ID")" ]]; then
        errors+=("Operational Context canonical identity missing Task ID")
      fi
      if [[ -z "$jira_key_cell" ]]; then
        errors+=("Operational Context canonical identity missing JIRA key cell (use N/A when absent)")
      elif ! is_na_value "$jira_key_cell" && ! is_valid_jira_key "$jira_key_cell"; then
        errors+=("Operational Context JIRA key must be a real JIRA key or N/A (got: '$jira_key_cell')")
      elif [[ "$source_type" == "jira" ]] && is_na_value "$jira_key_cell"; then
        errors+=("Operational Context source_type=jira requires a real JIRA key (got: '$jira_key_cell')")
      fi
    else
      if [[ -z "$(extract_op_ctx_field "$FILE" "Task JIRA key")" ]]; then
        errors+=("Operational Context legacy identity missing Task JIRA key")
      fi
      if [[ -z "$(extract_op_ctx_field "$FILE" "Parent Epic")" ]]; then
        errors+=("Operational Context legacy identity missing Parent Epic")
      fi
    fi

    # Hard required cells — mode-aware (§ 3.2 for T, § 4.2 for V)
    local required_cells=()
    if [[ "$mode" == "T" ]]; then
      required_cells=(
        "Test sub-tasks"
        "AC 驗收單"
        "Base branch"
        "Task branch"
        "References to load"
      )
    else
      # V mode (§ 4.2): drops T-only cells (Test sub-tasks / AC 驗收單 / Task branch)
      # and adds Implementation tasks (the T list this V verifies).
      required_cells=(
        "Implementation tasks"
        "Base branch"
        "References to load"
      )
    fi
    local cell
    for cell in "${required_cells[@]}"; do
      if ! grep -qF "$cell" "$FILE"; then
        errors+=("missing Hard required Operational Context cell: '$cell'")
      fi
    done

    # Soft: 'Depends on' — warn only (absent = no deps, which is valid; T/V common)
    if ! grep -qF "Depends on" "$FILE"; then
      warnings+=("Operational Context missing 'Depends on' cell (Soft — N/A is valid; warn only)")
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Test Environment — Level enum + Level-specific field rules
  # § 3.3 + § 5.1
  # ---------------------------------------------------------------------------
  local level=""
  if grep -qF "## Test Environment" "$FILE"; then

    # Extract Level value
    local level_line
    level_line=$(grep -E '^\*\*Level\*\*: |^- \*\*Level\*\*: ' "$FILE" | head -n1 || true)
    if [[ -z "$level_line" ]]; then
      errors+=("Test Environment section missing 'Level' field (expected '- **Level**: {static|build|runtime}')")
    else
      level=$(printf '%s' "$level_line" \
        | sed -E 's/.*\*\*Level\*\*:[[:space:]]*//' \
        | sed -E 's/[[:space:]].*//' \
        | tr '[:upper:]' '[:lower:]' \
        | tr -d '\r')
      case "$level" in
        static|build|runtime) ;;
        *) errors+=("Test Environment 'Level' must be one of {static, build, runtime} (got: '$level')") ; level="" ;;
      esac
    fi

    # Extract Runtime verify target + Env bootstrap command
    local target_line bootstrap_line target="" bootstrap=""
    target_line=$(grep -E '^\*\*Runtime verify target\*\*: |^- \*\*Runtime verify target\*\*: ' "$FILE" | head -n1 || true)
    bootstrap_line=$(grep -E '^\*\*Env bootstrap command\*\*: |^- \*\*Env bootstrap command\*\*: ' "$FILE" | head -n1 || true)

    if [[ -z "$target_line" ]]; then
      errors+=("Test Environment missing 'Runtime verify target' field (expected '- **Runtime verify target**: {url|N/A}')")
    else
      target=$(printf '%s' "$target_line" | sed -E 's/.*\*\*Runtime verify target\*\*:[[:space:]]*//' | tr -d '\r')
    fi

    if [[ -z "$bootstrap_line" ]]; then
      errors+=("Test Environment missing 'Env bootstrap command' field (expected '- **Env bootstrap command**: {command|N/A}')")
    else
      bootstrap=$(printf '%s' "$bootstrap_line" | sed -E 's/.*\*\*Env bootstrap command\*\*:[[:space:]]*//' | tr -d '\r')
    fi

    # Apply Level-specific cross-field rules (§ 5.1 + § 3.3)
    if [[ -n "$level" ]]; then
      if [[ "$level" == "runtime" ]]; then
        # --- Level=runtime rules ---
        local normalized_target
        normalized_target=$(printf '%s' "${target:-}" | sed -E 's/^`|`$//g' | xargs 2>/dev/null || true)

        if [[ -z "$normalized_target" || "$normalized_target" == "N/A" || "$normalized_target" == "n/a" ]]; then
          errors+=("Level=runtime requires non-N/A Runtime verify target (got: '${normalized_target:-<empty>}')")
        elif ! printf '%s' "$normalized_target" | grep -Eq '^https?://'; then
          errors+=("Level=runtime requires Runtime verify target to be an http/https URL (got: '$normalized_target')")
        fi

        local normalized_bootstrap
        normalized_bootstrap=$(printf '%s' "${bootstrap:-}" | xargs 2>/dev/null || true)
        if [[ -z "$normalized_bootstrap" || "$normalized_bootstrap" == "N/A" || "$normalized_bootstrap" == "n/a" ]]; then
          errors+=("Level=runtime requires non-N/A Env bootstrap command")
        fi

        # Verify Command / 驗收步驟 host must equal Runtime verify target host (§ 5.1 rule 4)
        if grep -qF "$verify_section_name" "$FILE"; then
          local verify_section verify_cmd verify_cmd_compact
          verify_section=$(extract_markdown_section "$FILE" "$verify_section_name")
          verify_cmd=$(printf '%s\n' "$verify_section" | extract_first_fenced_code_block)
          verify_cmd_compact=$(printf '%s' "$verify_cmd" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | xargs 2>/dev/null || true)

          if [[ -z "$verify_cmd_compact" ]]; then
            errors+=("$verify_section_name fenced code block is empty (Level=runtime requires a live endpoint URL inside)")
          else
            local verify_url target_host verify_host
            verify_url=$(python3 -c "
import re, sys
s = sys.stdin.read()
m = re.search(r'https?://[^\s\"\'\\)]+', s)
print(m.group(0) if m else '')
" <<< "$verify_cmd_compact" 2>/dev/null || true)

            if [[ -z "$verify_url" ]]; then
              errors+=("Level=runtime requires Verify Command fenced block to contain a live http/https endpoint URL")
            else
              target_host=$(python3 -c "
from urllib.parse import urlparse
import sys
u = sys.argv[1]
print((urlparse(u).hostname or '').lower())
" "$normalized_target" 2>/dev/null || true)
              verify_host=$(python3 -c "
from urllib.parse import urlparse
import sys
u = sys.argv[1]
print((urlparse(u).hostname or '').lower())
" "$verify_url" 2>/dev/null || true)

              if [[ -z "$target_host" || -z "$verify_host" ]]; then
                errors+=("unable to parse host from Runtime verify target ('$normalized_target') or Verify Command URL ('$verify_url')")
              elif [[ "$target_host" != "$verify_host" ]]; then
                errors+=("Level=runtime: Verify Command URL host ($verify_host) must match Runtime verify target host ($target_host) — DP-023 Target-first rule")
              fi

              if grep -qi 'docs-manager' "$FILE"; then
                local target_path verify_path
                target_path=$(python3 -c "
from urllib.parse import urlparse
import sys
print(urlparse(sys.argv[1]).path or '/')
" "$normalized_target" 2>/dev/null || true)
                verify_path=$(python3 -c "
from urllib.parse import urlparse
import sys
print(urlparse(sys.argv[1]).path or '/')
" "$verify_url" 2>/dev/null || true)
                if [[ "$target_path" != /docs-manager/* && "$target_path" != "/docs-manager/" ]]; then
                  errors+=("docs-manager runtime target must include /docs-manager/ path (got: '$normalized_target')")
                fi
                if [[ "$verify_path" != /docs-manager/* && "$verify_path" != "/docs-manager/" ]]; then
                  errors+=("docs-manager Verify Command URL must include /docs-manager/ path (got: '$verify_url')")
                fi
              fi
            fi
          fi
        fi

      elif [[ "$level" == "static" || "$level" == "build" ]]; then
        # --- Level=static|build: Runtime verify target + Env bootstrap must be N/A ---
        local t_val b_val
        t_val=$(printf '%s' "${target:-}" | sed -E 's/^`|`$//g' | xargs 2>/dev/null || true)
        b_val=$(printf '%s' "${bootstrap:-}" | xargs 2>/dev/null || true)
        if [[ -n "$t_val" && "$t_val" != "N/A" && "$t_val" != "n/a" ]]; then
          errors+=("Level=$level expects Runtime verify target = N/A (got: '$t_val') — avoid false declarations")
        fi
        if [[ -n "$b_val" && "$b_val" != "N/A" && "$b_val" != "n/a" ]]; then
          errors+=("Level=$level expects Env bootstrap command = N/A (got: '$b_val') — avoid false declarations")
        fi
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # Optional VR metadata: frontmatter verification.visual_regression.
  # When declared, it must be schema-valid and tied to runtime verification.
  # ---------------------------------------------------------------------------
  local vr_state vr_present vr_is_map vr_expected vr_expected_is_string vr_pages_present vr_pages_is_list
  vr_state="$(extract_vr_frontmatter_state "$FILE")"
  vr_present="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("present") else "0")' "$vr_state")"
  if [[ "$vr_present" == "1" ]]; then
    vr_is_map="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("is_map") else "0")' "$vr_state")"
    vr_expected="$(python3 -c 'import json,sys; v=json.loads(sys.argv[1]).get("expected"); print("" if v is None else v)' "$vr_state")"
    vr_expected_is_string="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("expected_is_string") else "0")' "$vr_state")"
    vr_pages_present="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("pages_present") else "0")' "$vr_state")"
    vr_pages_is_list="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("pages_is_list") else "0")' "$vr_state")"

    if [[ "$vr_is_map" != "1" ]]; then
      errors+=("frontmatter verification.visual_regression must be a map with expected and pages")
    fi
    if [[ "$vr_expected_is_string" != "1" || -z "$vr_expected" ]]; then
      errors+=("frontmatter verification.visual_regression.expected is required")
    else
      case "$vr_expected" in
        none_allowed|baseline_required|update_baseline) ;;
        *) errors+=("frontmatter verification.visual_regression.expected must be none_allowed, baseline_required, or update_baseline (got: '$vr_expected')") ;;
      esac
    fi
    if [[ "$vr_pages_present" != "1" ]]; then
      errors+=("frontmatter verification.visual_regression.pages is required; use [] to select workspace-config pages")
    elif [[ "$vr_pages_is_list" != "1" ]]; then
      errors+=("frontmatter verification.visual_regression.pages must be a YAML list")
    fi
    if [[ "$level" != "runtime" ]]; then
      errors+=("frontmatter verification.visual_regression requires Test Environment Level=runtime (got: '${level:-<empty>}')")
    fi
  fi

  # ---------------------------------------------------------------------------
  # Optional behavior contract metadata: frontmatter verification.behavior_contract.
  # When declared, it must explicitly say whether runtime/user-visible behavior
  # verification applies; applies=true has no unknown/default mode.
  # ---------------------------------------------------------------------------
  local behavior_contract_errors behavior_contract_error
  behavior_contract_errors="$(validate_behavior_contract_frontmatter "$FILE")"
  if [[ -n "$behavior_contract_errors" ]]; then
    while IFS= read -r behavior_contract_error; do
      [[ -n "$behavior_contract_error" ]] && errors+=("$behavior_contract_error")
    done <<< "$behavior_contract_errors"
  fi

  if [[ "$mode" == "T" ]] && grep -qF "## Verify Command" "$FILE"; then
    local smoke_section smoke_cmd smoke_output smoke_rc
    smoke_section=$(extract_markdown_section "$FILE" "## Verify Command")
    smoke_cmd=$(printf '%s\n' "$smoke_section" | extract_first_fenced_code_block)
    if [[ -n "$smoke_cmd" ]]; then
      set +e
      smoke_output=$(verify_command_static_smoke "$FILE" "$smoke_cmd" 2>/dev/null)
      smoke_rc=$?
      set -e
      if [[ "$smoke_rc" -ne 0 ]]; then
        while IFS= read -r line; do
          [[ -n "$line" ]] && errors+=("$line")
        done <<< "$smoke_output"
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: ## Verify Command (T) / ## 驗收步驟 (V) — only Hard when Level ≠ static
  # § 3.1 / § 4.1 / § 4.5
  # For Level=static: section is Optional (no check).
  # For Level=build|runtime: section must exist with fenced code block.
  # (runtime host-alignment check already done above inside Test Environment block.)
  # T/V 共用，使用 verify_section_name 動態指向。
  # ---------------------------------------------------------------------------
  if [[ -n "$level" && "$level" != "static" ]]; then
    if ! grep -qF "$verify_section_name" "$FILE"; then
      errors+=("missing Hard required section: $verify_section_name (required when Level=$level)")
    else
      local vc_code
      vc_code=$(extract_markdown_section "$FILE" "$verify_section_name" | extract_first_fenced_code_block | tr -d '[:space:]')
      if [[ -z "$vc_code" ]]; then
        errors+=("$verify_section_name section missing executable fenced code block (required when Level=$level)")
      fi
    fi
  elif [[ -z "$level" ]]; then
    # Level unknown (Test Environment missing or malformed) — check section integrity
    # if the section exists, it must have a code block (preserve prior behavior).
    if grep -qF "$verify_section_name" "$FILE"; then
      local vc_code2
      vc_code2=$(extract_markdown_section "$FILE" "$verify_section_name" | extract_first_fenced_code_block | tr -d '[:space:]')
      if [[ -z "$vc_code2" ]]; then
        errors+=("$verify_section_name section missing executable fenced code block")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED (T mode only): ## Test Command must contain a fenced code block (§ 3.5)
  # V mode 不跑 unit test → 不需 Test Command（§ 4.1 「合理省略」）。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && grep -qF "## Test Command" "$FILE"; then
    local tc_code
    tc_code=$(extract_markdown_section "$FILE" "## Test Command" | extract_first_fenced_code_block | tr -d '[:space:]')
    if [[ -z "$tc_code" ]]; then
      errors+=("## Test Command section missing executable fenced code block")
    fi
  fi

  # ---------------------------------------------------------------------------
  # DP-028 Cross-field (T mode only): Depends on (non-empty) ⇒ Base branch must start with task/
  # § 5.2 — V mode 通常從 feat/... 或 develop 跑驗收，不適用此 cross-field（§ 5.2 表格）。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]]; then
    local depends_on_val base_branch_val
    depends_on_val=$(extract_op_ctx_field "$FILE" "Depends on")
    base_branch_val=$(extract_op_ctx_field "$FILE" "Base branch")
    local deps_normalized
    deps_normalized=$(printf '%s' "$depends_on_val" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)
    if [[ -n "$deps_normalized" \
          && "$deps_normalized" != "n/a" \
          && "$deps_normalized" != "-" \
          && "$deps_normalized" != "無" \
          && "$deps_normalized" != "none" ]]; then
      if [[ -z "$base_branch_val" ]]; then
        errors+=("DP-028 cross-field: 'Depends on' is non-empty but 'Base branch' is not a task/ branch (got: <empty>)")
      elif [[ "$base_branch_val" != task/* ]]; then
        errors+=("DP-028 cross-field: 'Depends on' is non-empty but 'Base branch' is not a task/ branch (got: '$base_branch_val')")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (T mode only): deliverable schema (§ 2.1 + § 3.6 + DP-033 D7)
  # Not required to exist; validator only checks schema WHEN the block is present.
  # V mode 對稱 lifecycle 是 ac_verification（見下方 V-only block）。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && frontmatter_key_exists "$FILE" "deliverable" 2>/dev/null; then
    local fm_block
    fm_block=$(extract_frontmatter_block "$FILE")

    # Extract indented scalar fields under deliverable:
    # pr_url, pr_state, head_sha
    local pr_url pr_state head_sha
    pr_url=$(printf '%s\n' "$fm_block" | awk '
      /^[[:space:]]+pr_url:[[:space:]]/ {
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print val; exit
      }
    ')
    pr_state=$(printf '%s\n' "$fm_block" | awk '
      /^[[:space:]]+pr_state:[[:space:]]/ {
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print val; exit
      }
    ')
    head_sha=$(printf '%s\n' "$fm_block" | awk '
      /^[[:space:]]+head_sha:[[:space:]]/ {
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print val; exit
      }
    ')

    # Validate pr_url
    if [[ -z "$pr_url" ]]; then
      errors+=("deliverable.pr_url is missing or empty (required when deliverable block is present)")
    elif ! printf '%s' "$pr_url" | grep -qE '^https://github\.com/.+/pull/[0-9]+$'; then
      errors+=("deliverable.pr_url must match '^https://github\\.com/.+/pull/[0-9]+\$' (got: '$pr_url')")
    fi

    # Validate pr_state
    if [[ -z "$pr_state" ]]; then
      errors+=("deliverable.pr_state is missing or empty (required when deliverable block is present)")
    else
      case "$pr_state" in
        OPEN|MERGED|CLOSED) ;;
        *) errors+=("deliverable.pr_state must be OPEN, MERGED, or CLOSED (got: '$pr_state')") ;;
      esac
    fi

    # Validate head_sha (7+ hex chars)
    if [[ -z "$head_sha" ]]; then
      errors+=("deliverable.head_sha is missing or empty (required when deliverable block is present)")
    elif ! printf '%s' "$head_sha" | grep -qE '^[0-9a-fA-F]{7,}$'; then
      errors+=("deliverable.head_sha must be a hex string of ≥ 7 characters (got: '$head_sha')")
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (T mode only): extension_deliverable schema (DP-048)
  # Used by local_extension delivery endpoints. It may supplement a real
  # workspace PR deliverable for post-PR release tails, or stand alone for
  # explicitly PR-bypass endpoints; validator only checks structure WHEN the
  # block is present.
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && frontmatter_key_exists "$FILE" "extension_deliverable" 2>/dev/null; then
    local fm_block_ext
    fm_block_ext=$(extract_frontmatter_block "$FILE")

    extract_ext_field() {
      printf '%s\n' "$fm_block_ext" | awk -v key="$1" '
        /^extension_deliverable:/ { in_block=1; in_evidence=0; next }
        in_block && /^[^[:space:]#]/ { exit }
        in_block && /^[[:space:]]+evidence:/ { in_evidence=1; next }
        in_block && /^[[:space:]]+[A-Za-z0-9_.-]+:/ { in_evidence=0 }
        in_block && !in_evidence && match($0, "^[[:space:]]+" key ":[[:space:]]") {
          val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
          print val; exit
        }
      '
    }

    extract_ext_evidence_field() {
      printf '%s\n' "$fm_block_ext" | awk -v key="$1" '
        /^extension_deliverable:/ { in_block=1; next }
        in_block && /^[^[:space:]#]/ { exit }
        in_block && /^[[:space:]]+evidence:/ { in_evidence=1; next }
        in_evidence && /^[[:space:]]{4}/ && match($0, "^[[:space:]]+" key ":[[:space:]]") {
          val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
          print val; exit
        }
        in_evidence && /^[[:space:]]{2}[A-Za-z0-9_.-]+:/ { exit }
      '
    }

    local ext_endpoint ext_extension_id ext_task_head ext_workspace_commit ext_template_commit ext_version_tag ext_release_url ext_completed_at
    local ext_ci_evidence ext_verify_evidence ext_vr_evidence
    ext_endpoint=$(extract_ext_field "endpoint")
    ext_extension_id=$(extract_ext_field "extension_id")
    ext_task_head=$(extract_ext_field "task_head_sha")
    ext_workspace_commit=$(extract_ext_field "workspace_commit")
    ext_template_commit=$(extract_ext_field "template_commit")
    ext_version_tag=$(extract_ext_field "version_tag")
    ext_release_url=$(extract_ext_field "release_url")
    ext_completed_at=$(extract_ext_field "completed_at")
    ext_ci_evidence=$(extract_ext_evidence_field "ci_local")
    ext_verify_evidence=$(extract_ext_evidence_field "verify")
    ext_vr_evidence=$(extract_ext_evidence_field "vr")

    if [[ "$ext_endpoint" != "local_extension" ]]; then
      errors+=("extension_deliverable.endpoint must be local_extension (got: '${ext_endpoint:-<empty>}')")
    fi
    if [[ -z "$ext_extension_id" ]]; then
      errors+=("extension_deliverable.extension_id is missing or empty")
    elif ! printf '%s' "$ext_extension_id" | grep -qE '^[A-Za-z0-9._-]+$'; then
      errors+=("extension_deliverable.extension_id contains unsupported characters (got: '$ext_extension_id')")
    fi
    for field in task_head_sha workspace_commit template_commit; do
      local field_value
      case "$field" in
        task_head_sha) field_value="$ext_task_head" ;;
        workspace_commit) field_value="$ext_workspace_commit" ;;
        template_commit) field_value="$ext_template_commit" ;;
      esac
      if [[ -z "$field_value" ]]; then
        errors+=("extension_deliverable.$field is missing or empty")
      elif ! printf '%s' "$field_value" | grep -qE '^[0-9a-fA-F]{7,40}$'; then
        errors+=("extension_deliverable.$field must be a 7-40 char hex SHA (got: '$field_value')")
      fi
    done
    if [[ -z "$ext_version_tag" ]]; then
      errors+=("extension_deliverable.version_tag is missing or empty")
    elif [[ "$ext_version_tag" != "N/A" ]] && ! printf '%s' "$ext_version_tag" | grep -qE '^v[0-9][A-Za-z0-9._-]*$'; then
      errors+=("extension_deliverable.version_tag must look like v1.2.3 or be N/A (got: '$ext_version_tag')")
    fi
    if [[ -n "$ext_release_url" && "$ext_release_url" != "N/A" ]] && ! printf '%s' "$ext_release_url" | grep -qE '^https://github\.com/.+/releases/tag/.+$'; then
      errors+=("extension_deliverable.release_url must be a GitHub release URL or N/A (got: '$ext_release_url')")
    fi
    if [[ -z "$ext_completed_at" ]]; then
      errors+=("extension_deliverable.completed_at is missing or empty")
    elif ! printf '%s' "$ext_completed_at" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$'; then
      errors+=("extension_deliverable.completed_at must be ISO 8601 timestamp (got: '$ext_completed_at')")
    fi
    if [[ -z "$ext_ci_evidence" ]]; then
      errors+=("extension_deliverable.evidence.ci_local is missing (use N/A when no ci-local is declared)")
    fi
    if [[ -z "$ext_verify_evidence" || "$ext_verify_evidence" == "N/A" ]]; then
      errors+=("extension_deliverable.evidence.verify is missing or N/A")
    fi
    if [[ -z "$ext_vr_evidence" ]]; then
      errors+=("extension_deliverable.evidence.vr is missing (use N/A when VR did not run)")
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (V mode only): ac_verification schema (§ 4.6 + § 4.7,
  # symmetric to deliverable D7). verify-AC writes summary on every run.
  # Not required to exist (breakdown stage absent is legal); only check WHEN present.
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "V" ]] && frontmatter_key_exists "$FILE" "ac_verification" 2>/dev/null; then
    local fm_block_v
    fm_block_v=$(extract_frontmatter_block "$FILE")

    # Helper: extract scalar field under `ac_verification:` block (state machine).
    # Stops at the next top-level (unindented) YAML key.
    extract_av_field() {
      printf '%s\n' "$fm_block_v" | awk -v key="$1" '
        /^ac_verification:/ { in_block=1; next }
        in_block && /^[^[:space:]#]/ { exit }
        in_block && match($0, "^[[:space:]]+" key ":[[:space:]]") {
          val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
          print val; exit
        }
      '
    }

    local av_status av_last_run av_total av_pass av_fail av_manual av_uncertain av_disposition
    av_status=$(extract_av_field "status")
    av_last_run=$(extract_av_field "last_run_at")
    av_total=$(extract_av_field "ac_total")
    av_pass=$(extract_av_field "ac_pass")
    av_fail=$(extract_av_field "ac_fail")
    av_manual=$(extract_av_field "ac_manual_required")
    av_uncertain=$(extract_av_field "ac_uncertain")
    av_disposition=$(extract_av_field "human_disposition")

    # status enum
    if [[ -z "$av_status" ]]; then
      errors+=("ac_verification.status is missing or empty (required when ac_verification block is present)")
    else
      case "$av_status" in
        PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|IN_PROGRESS) ;;
        *) errors+=("ac_verification.status must be PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|IN_PROGRESS (got: '$av_status')") ;;
      esac
    fi

    # last_run_at ISO 8601 (loose: must look like YYYY-MM-DDThh:mm:ss with optional Z/±offset)
    if [[ -z "$av_last_run" ]]; then
      errors+=("ac_verification.last_run_at is missing or empty (required when ac_verification block is present)")
    elif ! printf '%s' "$av_last_run" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$'; then
      errors+=("ac_verification.last_run_at must be ISO 8601 timestamp (got: '$av_last_run')")
    fi

    # ac_total / ac_pass / ac_fail / ac_manual_required / ac_uncertain — int ≥ 0; sum == total
    local _is_int='^-?[0-9]+$'
    local sum=0 has_count_error=0
    local field val
    for field in ac_total ac_pass ac_fail ac_manual_required ac_uncertain; do
      val=$(extract_av_field "$field")
      if [[ -z "$val" ]]; then
        errors+=("ac_verification.$field is missing or empty (required when ac_verification block is present)")
        has_count_error=1
        continue
      fi
      if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        errors+=("ac_verification.$field must be a non-negative integer (got: '$val')")
        has_count_error=1
        continue
      fi
      if [[ "$field" != "ac_total" ]]; then
        sum=$((sum + val))
      fi
    done
    if [[ "$has_count_error" -eq 0 && -n "$av_total" ]]; then
      if [[ "$sum" -ne "$av_total" ]]; then
        errors+=("ac_verification: ac_pass + ac_fail + ac_manual_required + ac_uncertain ($sum) must equal ac_total ($av_total)")
      fi
    fi

    # human_disposition: required when status != PASS
    if [[ -n "$av_status" && "$av_status" != "PASS" && "$av_status" != "IN_PROGRESS" ]]; then
      if [[ -z "$av_disposition" ]]; then
        errors+=("ac_verification.human_disposition is required when status='$av_status' (FAIL/MANUAL_REQUIRED/UNCERTAIN need human triage)")
      else
        case "$av_disposition" in
          passed|rejected|deferred) ;;
          *) errors+=("ac_verification.human_disposition must be passed|rejected|deferred (got: '$av_disposition')") ;;
        esac
      fi
    elif [[ -n "$av_disposition" ]]; then
      # status=PASS or IN_PROGRESS but human_disposition is set — must still be valid enum
      case "$av_disposition" in
        passed|rejected|deferred) ;;
        *) errors+=("ac_verification.human_disposition must be passed|rejected|deferred (got: '$av_disposition')") ;;
      esac
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (V mode only): ac_verification_log schema (§ 4.6 + § 4.7, loose)
  # Same精神 as jira_transition_log — list-of-maps，time 建議不強制；其他欄位 freeform。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "V" ]] && frontmatter_key_exists "$FILE" "ac_verification_log" 2>/dev/null; then
    local fm_block_avl
    fm_block_avl=$(extract_frontmatter_block "$FILE")

    # Reject inline scalar (e.g., `ac_verification_log: some_string`).
    local avl_inline
    avl_inline=$(printf '%s\n' "$fm_block_avl" | awk '
      /^ac_verification_log:/ {
        val = $0
        sub(/^ac_verification_log:[[:space:]]*/, "", val)
        sub(/[[:space:]]+$/, "", val)
        if (val != "" && val != "[]" && val != "~" && val != "null") {
          print val
        }
        exit
      }
    ')
    if [[ -n "$avl_inline" ]]; then
      errors+=("ac_verification_log must be a YAML list (array), not a scalar (got inline value: '$avl_inline')")
    else
      # Each entry must be a map (key: value), not a bare scalar.
      local avl_bad
      avl_bad=$(printf '%s\n' "$fm_block_avl" | awk '
        /^ac_verification_log:/ { in_blk=1; next }
        in_blk && /^[^[:space:]]/ { exit }
        in_blk && /^[[:space:]]+-[[:space:]]+[^{]/ {
          sub(/^[[:space:]]+-[[:space:]]*/, "", $0)
          if ($0 !~ /:/) { print "bare scalar entry: " $0 }
        }
      ')
      if [[ -n "$avl_bad" ]]; then
        errors+=("ac_verification_log entries must be YAML maps (key: value), not bare scalars ($avl_bad)")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL: jira_transition_log schema (§ 2.1 + DP-033 D7, loose)
  # Not required to exist; WHEN present: must be a YAML list (not scalar).
  # Each entry should be a map; time is recommended but not enforced.
  # ---------------------------------------------------------------------------
  if frontmatter_key_exists "$FILE" "jira_transition_log" 2>/dev/null; then
    local fm_block2
    fm_block2=$(extract_frontmatter_block "$FILE")

    # Check that jira_transition_log is NOT a scalar (inline value on the key line).
    # Valid forms: empty value (list follows on next lines) or "[]"
    # Invalid: jira_transition_log: some_string
    local jtl_inline
    jtl_inline=$(printf '%s\n' "$fm_block2" | awk '
      /^jira_transition_log:/ {
        val = $0
        sub(/^jira_transition_log:[[:space:]]*/, "", val)
        sub(/[[:space:]]+$/, "", val)
        if (val != "" && val != "[]" && val != "~" && val != "null") {
          print val
        }
        exit
      }
    ')
    if [[ -n "$jtl_inline" ]]; then
      errors+=("jira_transition_log must be a YAML list (array), not a scalar (got inline value: '$jtl_inline')")
    else
      # Verify each list entry (lines starting with "  - ") is a map (has at least one sub-key: value pair).
      # Loose check: each "  - " line must be followed by at least one "    key: value" line.
      # We just verify that if there are entries, they don't look like raw scalars on the same line.
      local jtl_bad_entries
      jtl_bad_entries=$(printf '%s\n' "$fm_block2" | awk '
        /^jira_transition_log:/ { in_jtl=1; next }
        in_jtl && /^[^[:space:]]/ { exit }
        in_jtl && /^[[:space:]]+-[[:space:]]+[^{]/ {
          # "  - value" (bare scalar entry) — not a map
          sub(/^[[:space:]]+-[[:space:]]*/, "", $0)
          # If remainder looks like a plain scalar (no colon), it might be a scalar entry.
          # But since YAML allows "- key: val" on one line too, only flag obvious non-map.
          if ($0 !~ /:/) { print "bare scalar entry: " $0 }
        }
      ')
      if [[ -n "$jtl_bad_entries" ]]; then
        errors+=("jira_transition_log entries must be YAML maps (key: value), not bare scalars ($jtl_bad_entries)")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # Output: warnings (non-blocking) + errors (violations → exit 1)
  # ---------------------------------------------------------------------------
  if [[ ${#warnings[@]} -gt 0 ]]; then
    echo "⚠ task.md soft warnings in $FILE:" >&2
    local w
    for w in "${warnings[@]}"; do
      echo "  ~ $w" >&2
    done
    echo "" >&2
  fi

  if [[ ${#errors[@]} -eq 0 ]]; then
    return 0
  fi

  echo "✗ task.md schema violations in $FILE:" >&2
  local err
  for err in "${errors[@]}"; do
    echo "  - $err" >&2
  done
  echo "" >&2
  echo "Contract: skills/references/task-md-schema.md (DP-033 A2 full enforcer)" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Scan mode: recursively validate all T*.md and V*.md in specs/*/tasks/ (skip pr-release/)
# Always exits 0; produces PASS/FAIL/HARD summary lines.
# DP-033 Phase B: filename pattern擴展到 V*.md (filename dispatch 對 T/V 共用).
# ---------------------------------------------------------------------------
if [[ "$1" == "--scan" ]]; then
  if [[ $# -ne 2 ]]; then
    usage
  fi
  root="$2"
  if [[ ! -d "$root" ]]; then
    echo "error: scan root not found: $root" >&2
    exit 2
  fi

  pass=0
  fail=0
  hard=0
  while IFS= read -r f; do
    case "$f" in
      */.worktrees/*|*/node_modules/*) continue ;;
      */tasks/pr-release/*) continue ;;
    esac
    case "$f" in
      */specs/*/tasks/T*.md|*/specs/*/tasks/T*/index.md) ;;
      */specs/*/tasks/V*.md|*/specs/*/tasks/V*/index.md) ;;
      *) continue ;;
    esac

    rc=0
    validate_file "$f" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0)
        printf "PASS  %s\n" "$f"
        pass=$((pass+1))
        ;;
      2)
        printf "HARD  %s\n" "$f"
        validate_file "$f" 2>&1 | sed 's/^/      /' >&2 || true
        hard=$((hard+1))
        fail=$((fail+1))
        ;;
      *)
        printf "FAIL  %s\n" "$f"
        validate_file "$f" 2>&1 | sed 's/^/      /' >&2 || true
        fail=$((fail+1))
        ;;
    esac
  done < <(find "$root" -type f \( -name 'T*.md' -o -name 'V*.md' -o -name 'index.md' \) 2>/dev/null | sort)

  echo ""
  echo "task.md scan: $pass pass, $fail fail ($hard hard-fail) — total $((pass+fail))"
  exit 0
fi

# ---------------------------------------------------------------------------
# Single-file mode
# ---------------------------------------------------------------------------
validate_file "$1"
exit $?
