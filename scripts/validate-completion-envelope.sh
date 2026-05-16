#!/usr/bin/env bash
# Validate Polaris sub-agent Completion Envelope output.

set -euo pipefail

MODE="advisory"
SELF_TEST=0
FILES=()

usage() {
  cat <<'EOF'
Usage:
  scripts/validate-completion-envelope.sh [--blocking] <file>...
  scripts/validate-completion-envelope.sh --self-test

Default mode is advisory: invalid envelopes print warnings and exit 0.
Use --blocking at explicit enforcement callsites.
EOF
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
}

has_line() {
  local file="$1"
  local pattern="$2"
  grep -qF "$pattern" "$file"
}

status_value() {
  local file="$1"
  local value=""
  value="$(grep -m 1 '^## Status:' "$file" | sed 's/^## Status:[[:space:]]*//')"
  printf '%s\n' "$value"
}

validate_file() {
  local file="$1"
  local invalid=0
  local status=""

  if [[ ! -f "$file" ]]; then
    fail "file not found: $file"
    return 2
  fi

  status="$(status_value "$file")"
  case "$status" in
    DONE|BLOCKED|PARTIAL) ;;
    *)
      warn "$file: missing or invalid '## Status: DONE|BLOCKED|PARTIAL'"
      invalid=1
      ;;
  esac

  local line
  for line in "**Artifacts**:" "**Detail**:" "**Model Class**:" "**Runtime Agent**:" "**Selected Model**:" "**Model Fallback**:" "**Summary**:"; do
    if ! has_line "$file" "$line"; then
      warn "$file: missing required line '$line'"
      invalid=1
    fi
  done

  if [[ "$status" == "BLOCKED" ]] && ! has_line "$file" "**Blocker**:"; then
    warn "$file: BLOCKED status requires '**Blocker**:'"
    invalid=1
  fi

  if [[ "$status" == "PARTIAL" ]] && ! has_line "$file" "**Remaining**:"; then
    warn "$file: PARTIAL status requires '**Remaining**:'"
    invalid=1
  fi

  if [[ "$invalid" -eq 0 ]]; then
    printf 'PASS: completion envelope valid: %s\n' "$file"
    return 0
  fi

  if [[ "$MODE" == "blocking" ]]; then
    return 1
  fi

  warn "$file: advisory mode only; continuing"
  return 0
}

self_test() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  local valid="$tmp_dir/valid.md"
  local invalid="$tmp_dir/invalid.md"
  local partial="$tmp_dir/partial.md"

  cat >"$valid" <<'EOF'
## Status: DONE
**Artifacts**: none
**Detail**: inline
**Model Class**: standard_coding
**Runtime Agent**: polaris-standard-coding
**Selected Model**: inherit
**Model Fallback**: none
**Summary**: Complete.
EOF

  cat >"$invalid" <<'EOF'
## Status: DONE
**Artifacts**: none
**Summary**: Missing fields.
EOF

  cat >"$partial" <<'EOF'
## Status: PARTIAL
**Artifacts**: none
**Detail**: inline
**Model Class**: standard_coding
**Runtime Agent**: polaris-standard-coding
**Selected Model**: inherit
**Model Fallback**: none
**Summary**: Some work remains.
**Remaining**: one follow-up
EOF

  bash "$0" "$valid" >/dev/null
  bash "$0" "$invalid" >/dev/null
  if bash "$0" --blocking "$invalid" >/dev/null 2>&1; then
    fail "blocking invalid envelope should fail"
    return 1
  fi
  bash "$0" --blocking "$partial" >/dev/null

  printf 'validate-completion-envelope self-test PASS\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --blocking)
      MODE="blocking"
      shift
      ;;
    --self-test)
      SELF_TEST=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      fail "unknown option: $1"
      usage >&2
      exit 2
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

if [[ "$SELF_TEST" -eq 1 ]]; then
  self_test
  exit $?
fi

if [[ "${#FILES[@]}" -eq 0 ]]; then
  usage >&2
  exit 2
fi

rc=0
file=""
for file in "${FILES[@]}"; do
  if ! validate_file "$file"; then
    rc=1
  fi
done

exit "$rc"
