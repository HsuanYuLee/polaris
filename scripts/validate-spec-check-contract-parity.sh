#!/usr/bin/env bash
# Purpose: DP-417 T11 — bidirectional spec↔check contract parity gate. Asserts that
#          every deterministic refinement.json producer check's hard requirement /
#          prohibition on an AUTHOR-controllable field is faithfully reflected in the
#          LLM-facing producer schema spec (refinement-artifact.md / pipeline-handoff.md).
#          Its thesis: "write the artifact per the spec" ⇒ "the deterministic checks pass
#          BY CONSTRUCTION". It fails-closed on drift in either direction:
#            - validator-hard-requires field X but the spec does not document X as
#              required          → POLARIS_SPEC_CHECK_PARITY_UNDOCUMENTED
#            - spec declares field X required but a validator FORBIDS X (or the spec
#              marks X as forbidden for a source type the validator now requires it on)
#                                → POLARIS_SPEC_CHECK_PARITY_CONTRADICTION
#          Each manifest entry is tied to a live validator via an anchor literal
#          (anchor-liveness); if the anchor is gone the manifest is stale and the check
#          is no longer trustworthy → POLARIS_SPEC_CHECK_PARITY_ANCHOR_STALE. This keeps
#          the manifest from silently diverging from the checks it mirrors.
# Inputs:  --repo-root <path>  (default: git toplevel of cwd, else this script's repo).
# Outputs: PASS line on stdout (exit 0); POLARIS_SPEC_CHECK_PARITY_* markers on stderr
#          (exit 2) on drift; exit 2 on missing inputs (fail-closed).
set -euo pipefail

REPO_ROOT=""
DESCRIBE_AUTHORITY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
    --describe-authority) DESCRIBE_AUTHORITY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" >&2; exit 0 ;;
    *) echo "POLARIS_SPEC_CHECK_PARITY_USAGE: unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ "$DESCRIBE_AUTHORITY" -eq 1 ]]; then
  if [[ -n "$REPO_ROOT" ]]; then
    echo "POLARIS_SPEC_CHECK_PARITY_USAGE: --describe-authority does not accept --repo-root" >&2
    exit 2
  fi
  command printf '%s\n' '{"authority_id":"producer_consumer_validator_parity","registry":"scripts/lib/producer-consumer-bridges.json","validator":"scripts/validate-spec-check-contract-parity.sh"}'
  exit 0
fi

if [[ -z "$REPO_ROOT" ]]; then
  # git toplevel if inside a repo, else fall back to this script's parent dir.
  # NB: keep the git branch and the fallback as separate statements — a single
  # `git ... || cd ... && pwd` chain mis-parses (|| and && are left-associative
  # with equal precedence), appending pwd to a successful git result.
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || REPO_ROOT=""
  if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/lib/validate_spec_check_contract_parity.py" --repo-root "$REPO_ROOT"
