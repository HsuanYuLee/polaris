#!/usr/bin/env bash
# scripts/lib/verification-evidence.sh — shared Layer B verification evidence helpers.
#
# This file is sourced, not executed. It centralizes portable checks for
# head-bound verification evidence written by run-verify-command.sh so multiple
# gates do not each redefine ticket/head/writer/exit_code semantics.

VERIFICATION_EVIDENCE_ALLOWED_WRITERS_DEFAULT="run-verify-command.sh"
VR_EVIDENCE_ALLOWED_WRITERS_DEFAULT="run-visual-snapshot.sh"

_verification_evidence_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
