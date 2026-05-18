#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS=()

usage() {
  cat <<'USAGE'
Usage: bash scripts/check-runtime-asset.sh [--root <repo>] [--asset <tool>:<profile>:<path>:<remediation>]... [--self-test]

Fails when a required runtime asset is missing, using the Polaris tool token
contract. With no --asset arguments the gate passes.
USAGE
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/scripts" "$tmp/assets"
  cp "$0" "$tmp/scripts/check-runtime-asset.sh"
  bash "$tmp/scripts/check-runtime-asset.sh" --root "$tmp" --asset "playwright:runtime:assets:bootstrap" >/dev/null
  if bash "$tmp/scripts/check-runtime-asset.sh" --root "$tmp" --asset "playwright:runtime:missing:bootstrap" >/tmp/check-runtime-asset.out 2>&1; then
    echo "expected missing runtime asset to fail" >&2
    exit 1
  fi
  grep -q '\[POLARIS_TOOL_MISSING\] tool=playwright profile=runtime remediation="bootstrap"' /tmp/check-runtime-asset.out
  echo "PASS: check-runtime-asset selftest"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="$2"; shift 2 ;;
    --asset) ASSETS+=("$2"); shift 2 ;;
    --self-test) run_self_test; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "check-runtime-asset: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

failures=0
for asset in "${ASSETS[@]}"; do
  IFS=: read -r tool profile path remediation <<<"$asset"
  if [[ -z "${tool:-}" || -z "${profile:-}" || -z "${path:-}" || -z "${remediation:-}" ]]; then
    echo "check-runtime-asset: invalid asset spec: $asset" >&2
    exit 2
  fi
  if [[ ! -e "$ROOT_DIR/$path" ]]; then
    echo "[POLARIS_TOOL_MISSING] tool=$tool profile=$profile remediation=\"$remediation\"" >&2
    echo "missing runtime asset: $path" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -gt 0 ]]; then
  echo "FAIL: runtime asset gate ($failures issue(s))" >&2
  exit 1
fi

echo "PASS: runtime asset gate"
