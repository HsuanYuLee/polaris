#!/usr/bin/env bash
# scripts/lib/verification-evidence.sh — shared Layer B verification evidence helpers.
#
# This file is sourced, not executed. It centralizes portable checks for
# head-bound verification evidence written by run-verify-command.sh so multiple
# gates do not each redefine ticket/head/writer/exit_code semantics.

VERIFICATION_EVIDENCE_ALLOWED_WRITERS_DEFAULT="run-verify-command.sh"
VR_EVIDENCE_ALLOWED_WRITERS_DEFAULT="run-visual-snapshot.sh"

_verification_evidence_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_verification_evidence_producer_map="${_verification_evidence_lib_dir}/evidence-producers.json"

verification_evidence_allowed_writers_for_kind() {
  local marker_kind="$1"
  local fallback="$2"

  if [[ ! -f "$_verification_evidence_producer_map" ]]; then
    printf '%s\n' "$fallback"
    return 0
  fi

  python3 - "$_verification_evidence_producer_map" "$marker_kind" "$fallback" <<'PY'
import json
import sys

path, marker_kind, fallback = sys.argv[1:4]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    writers = []
    for producer in data.get("producers", []):
        if marker_kind in producer.get("marker_kinds", []):
            writer = producer.get("writer")
            if writer and writer not in writers:
                writers.append(writer)
    print(",".join(writers) if writers else fallback)
except Exception:
    print(fallback)
PY
}

verification_evidence_root_for_repo() {
  local repo_root="$1"
  if [[ -z "$repo_root" ]]; then
    echo "verification_evidence_root_for_repo: missing repo_root argument" >&2
    return 1
  fi

  if [[ -n "${POLARIS_EVIDENCE_ROOT:-}" ]]; then
    printf '%s\n' "$POLARIS_EVIDENCE_ROOT"
    return 0
  fi

  local main_checkout=""
  if [[ -f "${_verification_evidence_lib_dir}/main-checkout.sh" ]]; then
    # shellcheck source=main-checkout.sh
    . "${_verification_evidence_lib_dir}/main-checkout.sh"
    if declare -F resolve_main_checkout >/dev/null 2>&1; then
      main_checkout="$(resolve_main_checkout "$repo_root" 2>/dev/null || true)"
    fi
  fi
  if [[ -z "$main_checkout" ]]; then
    main_checkout="$repo_root"
  fi
  printf '%s/.polaris/evidence\n' "$main_checkout"
}

verification_evidence_tmp_path() {
  local ticket="$1"
  local head_sha="$2"
  printf '/tmp/polaris-verified-%s-%s.json\n' "$ticket" "$head_sha"
}

verification_evidence_durable_path() {
  local repo_root="$1"
  local ticket="$2"
  local head_sha="$3"
  local evidence_root
  evidence_root="$(verification_evidence_root_for_repo "$repo_root")" || return 1
  printf '%s/verify/polaris-verified-%s-%s.json\n' "$evidence_root" "$ticket" "$head_sha"
}

verification_evidence_resolve_existing_path() {
  local repo_root="$1"
  local ticket="$2"
  local head_sha="$3"
  local tmp_path durable_path

  if [[ -z "$repo_root" || -z "$ticket" || -z "$head_sha" ]]; then
    return 1
  fi

  tmp_path="$(verification_evidence_tmp_path "$ticket" "$head_sha")"
  if [[ -f "$tmp_path" ]]; then
    printf '%s\n' "$tmp_path"
    return 0
  fi

  durable_path="$(verification_evidence_durable_path "$repo_root" "$ticket" "$head_sha")" || return 1
  if [[ -f "$durable_path" ]]; then
    printf '%s\n' "$durable_path"
    return 0
  fi

  return 1
}

verification_evidence_find_stale_path() {
  local repo_root="$1"
  local ticket="$2"
  local head_sha="$3"
  local evidence_root path

  [[ -n "$ticket" && -n "$head_sha" ]] || return 1
  evidence_root="$(verification_evidence_root_for_repo "$repo_root" 2>/dev/null || true)"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ "$path" != *-"$head_sha".json ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(
    {
      find /tmp -maxdepth 1 -type f -name "polaris-verified-${ticket}-*.json" 2>/dev/null
      find /private/tmp -maxdepth 1 -type f -name "polaris-verified-${ticket}-*.json" 2>/dev/null
      if [[ -n "$evidence_root" && -d "${evidence_root}/verify" ]]; then
        find "${evidence_root}/verify" -maxdepth 1 -type f -name "polaris-verified-${ticket}-*.json" 2>/dev/null
      fi
    } | sort -u
  )

  return 1
}

verification_evidence_validate_file() {
  local evidence_file="$1"
  local ticket="$2"
  local head_sha="$3"
  local allowed_writers="${4:-$VERIFICATION_EVIDENCE_ALLOWED_WRITERS_DEFAULT}"

  if [[ -z "$allowed_writers" || "$allowed_writers" == "$VERIFICATION_EVIDENCE_ALLOWED_WRITERS_DEFAULT" ]]; then
    allowed_writers="$(verification_evidence_allowed_writers_for_kind "verify" "$VERIFICATION_EVIDENCE_ALLOWED_WRITERS_DEFAULT")"
  fi

  python3 - "$evidence_file" "$ticket" "$head_sha" "$allowed_writers" <<'PY'
import json
import sys

path, expected_ticket, expected_head, allowed = sys.argv[1:5]
allowed_writers = {item for item in allowed.split(",") if item}

try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    assert data.get("ticket") == expected_ticket, "ticket mismatch"
    assert data.get("head_sha") == expected_head, "head_sha mismatch"
    writer = data.get("writer")
    assert writer in allowed_writers, f"writer not in whitelist: {writer!r}"
    assert "exit_code" in data, "missing exit_code"
    assert isinstance(data["exit_code"], int), "exit_code must be int"
    assert data.get("at"), "missing at"
except Exception as exc:
    print(f"invalid: {exc}")
    raise SystemExit(1)

print("valid")
PY
}

verification_evidence_validate_current_identity() {
  local evidence_file="$1"
  local task_md="$2"
  local repo_root="$3"
  local parse_task_md="${_verification_evidence_lib_dir}/../parse-task-md.sh"
  local verify_command="" level="" runtime_target="" execution_cwd=""

  [[ -f "$evidence_file" ]] || { echo "invalid identity: evidence file missing"; return 1; }
  [[ -f "$task_md" ]] || { echo "invalid identity: task.md missing"; return 1; }
  [[ -x "$parse_task_md" ]] || { echo "invalid identity: parse-task-md.sh missing"; return 1; }
  [[ -d "$repo_root" ]] || { echo "invalid identity: repo root missing"; return 1; }

  verify_command="$(bash "$parse_task_md" "$task_md" --no-resolve --field verify_command 2>/dev/null || true)"
  level="$(bash "$parse_task_md" "$task_md" --no-resolve --field level 2>/dev/null || true)"
  runtime_target="$(bash "$parse_task_md" "$task_md" --no-resolve --field runtime_verify_target 2>/dev/null || true)"
  execution_cwd="$(cd "$repo_root" && pwd)"
  [[ -n "$verify_command" && -n "$level" ]] \
    || { echo "invalid identity: task verification contract incomplete"; return 1; }

  python3 - "$evidence_file" "$verify_command" "$level" "$runtime_target" "$execution_cwd" <<'PY'
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

evidence_path, command, level, runtime_target, execution_cwd = sys.argv[1:]


def sha256_text(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def normalized_command(value):
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line.rstrip() for line in value.split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def command_version(argv):
    if shutil.which(argv[0]) is None:
        return "unavailable"
    try:
        result = subprocess.run(
            argv,
            cwd=execution_cwd,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
    except Exception as exc:
        return f"error:{type(exc).__name__}"
    output = (result.stdout or result.stderr).strip().splitlines()
    first = output[0] if output else ""
    return f"exit={result.returncode};{first}"


try:
    evidence = json.loads(Path(evidence_path).read_text(encoding="utf-8"))
    toolchain_context = {
        "bash": command_version(["bash", "--version"]),
        "git": command_version(["git", "--version"]),
        "mise": command_version(["mise", "current"]),
        "python3": command_version(["python3", "--version"]),
    }
    toolchain_hash = sha256_text(
        json.dumps(toolchain_context, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    )
    url_re = re.compile(r"https?://[^\s\"'<>)]+")
    if level == "runtime":
        target = runtime_target.strip()
        target_host = (urlparse(target).hostname or "").lower() if target.startswith("http") else ""
        match = url_re.search(command)
        verify_url = match.group(0).rstrip(",;)") if match else ""
        verify_host = (urlparse(verify_url).hostname or "").lower() if verify_url else ""
        runtime_contract = {
            "level": level,
            "runtime_verify_target": target,
            "verify_command_url": verify_url,
            "runtime_verify_target_host": target_host,
            "verify_command_url_host": verify_host,
        }
    else:
        runtime_contract = {"level": level}
    command_hash = sha256_text(normalized_command(command))
    context = {
        "level": level,
        "execution_cwd": execution_cwd,
        "runtime_contract": runtime_contract,
        "toolchain_context_hash": toolchain_hash,
    }
    context_hash = sha256_text(
        json.dumps(context, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    )
    identity = evidence.get("evidence_identity") or {}
    assert evidence.get("normalized_verify_command_hash") == command_hash, "verify command hash drift"
    assert evidence.get("toolchain_context") == toolchain_context, "toolchain context drift"
    assert evidence.get("toolchain_context_hash") == toolchain_hash, "toolchain hash drift"
    assert evidence.get("runtime_contract") == runtime_contract, "runtime contract drift"
    assert evidence.get("execution_cwd") == execution_cwd, "execution cwd drift"
    assert evidence.get("level") == level, "test level drift"
    assert evidence.get("verification_context_hash") == context_hash, "verification context drift"
    assert identity.get("head_sha") == evidence.get("head_sha"), "identity head mismatch"
    assert identity.get("normalized_verify_command_hash") == command_hash, "identity command mismatch"
    assert identity.get("verification_context_hash") == context_hash, "identity context mismatch"
except Exception as exc:
    print(f"invalid identity: {exc}")
    raise SystemExit(1)

print("current")
PY
}

verification_evidence_is_pass() {
  local evidence_file="$1"

  python3 - "$evidence_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    exit_code = int(data.get("exit_code", -1))
except Exception as exc:
    print(f"invalid exit_code: {exc}")
    raise SystemExit(1)

if exit_code != 0:
    print(f"exit_code != 0 ({exit_code})")
    raise SystemExit(1)

print("pass")
PY
}

vr_evidence_tmp_path() {
  local ticket="$1"
  local head_sha="$2"
  printf '/tmp/polaris-vr-%s-%s.json\n' "$ticket" "$head_sha"
}

vr_evidence_durable_path() {
  local repo_root="$1"
  local ticket="$2"
  local head_sha="$3"
  local evidence_root
  evidence_root="$(verification_evidence_root_for_repo "$repo_root")" || return 1
  printf '%s/vr/polaris-vr-%s-%s.json\n' "$evidence_root" "$ticket" "$head_sha"
}

vr_evidence_resolve_existing_path() {
  local repo_root="$1"
  local ticket="$2"
  local head_sha="$3"
  local tmp_path durable_path

  if [[ -z "$repo_root" || -z "$ticket" || -z "$head_sha" ]]; then
    return 1
  fi

  tmp_path="$(vr_evidence_tmp_path "$ticket" "$head_sha")"
  if [[ -f "$tmp_path" ]]; then
    printf '%s\n' "$tmp_path"
    return 0
  fi

  durable_path="$(vr_evidence_durable_path "$repo_root" "$ticket" "$head_sha")" || return 1
  if [[ -f "$durable_path" ]]; then
    printf '%s\n' "$durable_path"
    return 0
  fi

  return 1
}

vr_evidence_find_stale_path() {
  local repo_root="$1"
  local ticket="$2"
  local head_sha="$3"
  local evidence_root path

  [[ -n "$ticket" && -n "$head_sha" ]] || return 1
  evidence_root="$(verification_evidence_root_for_repo "$repo_root" 2>/dev/null || true)"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ "$path" != *-"$head_sha".json ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(
    {
      find /tmp -maxdepth 1 -type f -name "polaris-vr-${ticket}-*.json" 2>/dev/null
      find /private/tmp -maxdepth 1 -type f -name "polaris-vr-${ticket}-*.json" 2>/dev/null
      if [[ -n "$evidence_root" && -d "${evidence_root}/vr" ]]; then
        find "${evidence_root}/vr" -maxdepth 1 -type f -name "polaris-vr-${ticket}-*.json" 2>/dev/null
      fi
    } | sort -u
  )

  return 1
}

vr_evidence_validate_file() {
  local evidence_file="$1"
  local ticket="$2"
  local head_sha="$3"
  local required_mode="${4:-compare}"
  local allowed_writers="${5:-$VR_EVIDENCE_ALLOWED_WRITERS_DEFAULT}"

  python3 - "$evidence_file" "$ticket" "$head_sha" "$required_mode" "$allowed_writers" <<'PY'
import json
import sys

path, expected_ticket, expected_head, required_mode, allowed = sys.argv[1:6]
allowed_writers = {item for item in allowed.split(",") if item}

try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    assert data.get("ticket") == expected_ticket, "ticket mismatch"
    assert data.get("head_sha") == expected_head, "head_sha mismatch"
    writer = data.get("writer")
    assert writer in allowed_writers, f"writer not in whitelist: {writer!r}"
    assert data.get("mode") == required_mode, f"mode must be {required_mode}"
    assert data.get("status"), "missing status"
    assert data.get("at"), "missing at"
except Exception as exc:
    print(f"invalid: {exc}")
    raise SystemExit(1)

print("valid")
PY
}

vr_evidence_normalized_outcome() {
  local evidence_file="$1"

  python3 - "$evidence_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    status = str(data.get("status") or "")
except Exception as exc:
    print(f"invalid: {exc}")
    raise SystemExit(1)

mapping = {
    "PASS": "PASS",
    "BLOCK": "FAIL",
    "BLOCKED_ENV": "BLOCKED_ENV",
    "MANUAL_REQUIRED": "MANUAL_REQUIRED",
    "SKIP": "UNCERTAIN",
    "BASELINE_CAPTURED": "UNCERTAIN",
}

if status not in mapping:
    print(f"invalid: unsupported VR status {status!r}")
    raise SystemExit(1)

print(mapping[status])
PY
}
