#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  scripts/verify-ac-feedback-signals.sh [--repo PATH]

Runs feedback signal checks as a verify-AC verifier.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

REPO="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -d "$REPO" ]]; then
  echo "BLOCKED: --repo must point to an existing repo" >&2
  exit 2
fi

(cd "$REPO" && bash scripts/check-feedback-signals.sh >/dev/null)
echo "PASS: feedback signals verifier wrapper ($REPO)"
