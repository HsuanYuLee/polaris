#!/usr/bin/env bash
# Purpose: portable fail-closed push-time gate that enforces runtime-instruction
#          manifest freshness. The sole verdict source is
#          `compile-runtime-instructions.sh --check`; if the generated runtime
#          targets / `.generated` rules-manifest files are stale relative to
#          their `.claude/instructions/**` + `.claude/rules/*.md` sources (or a
#          manifest target is missing), the gate exits non-zero and prints a
#          repair hint. There is no env bypass — fail-closed by contract
#          (DP-320 AC1 / AC5 / AC-NEG1; DP-299 prose-vs-gate A-class invariant).
# Inputs:  --repo <path> (defaults to git toplevel / pwd)
# Outputs: stderr status; exit 0 in-sync, exit 1 stale/missing, exit 2 env error
# Side effects: none (read-only; compile --check never writes generated targets)
set -euo pipefail

PREFIX="[polaris gate-runtime-instruction-manifest]"
REPO_ROOT=""

usage() {
  cat >&2 <<EOF
Usage: bash scripts/gates/gate-runtime-instruction-manifest.sh [--repo <path>]

Runs scripts/compile-runtime-instructions.sh --check against the repo root.
Exits 0 when the runtime-instruction manifest is in sync; exits 1 when a source
drifted from the generated targets or a manifest target is missing (with a
repair hint); exits 2 on usage / environment error. Fail-closed: no env bypass.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) shift ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT" ]]; then
  echo "$PREFIX ERROR: cannot resolve repo root (--repo not given and not in git)." >&2
  exit 2
fi

COMPILE="$REPO_ROOT/scripts/compile-runtime-instructions.sh"

# Repos that do not carry the runtime-instruction compiler (e.g. product repos)
# have no manifest to keep fresh — there is nothing to enforce, so pass.
if [[ ! -f "$COMPILE" ]]; then
  exit 0
fi

# Single-source verdict: compile-runtime-instructions.sh --check. It already
# fails closed on a missing manifest target ("DRIFT: missing ...") and on any
# byte drift. We do not re-implement a second checksum path here (canonical
# writer / single source, per rules/canonical-contract-governance.md).
if bash "$COMPILE" --check >/dev/null 2>&1; then
  echo "$PREFIX ✅ runtime-instruction manifest is in sync." >&2
  exit 0
fi

echo "$PREFIX BLOCKED: runtime-instruction targets / manifest are stale relative to .claude/instructions/** + .claude/rules/*.md." >&2
echo "$PREFIX Repair: run 'bash scripts/compile-runtime-instructions.sh' then commit the regenerated targets, and re-push." >&2
exit 1
