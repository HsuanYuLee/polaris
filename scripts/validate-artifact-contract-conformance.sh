#!/usr/bin/env bash
# Purpose: DP-421 T1 — generic, registry-driven artifact-contract-conformance gate.
#   Reads scripts/lib/artifact-contract-registry.json (a class -> required_field / rule /
#   required_since / delegate_validator / migration_owner map), enumerates the existing artifacts
#   of each class, and classifies each as conformant / non-conformant:
#     - conformant  = required_field present AND the EXISTING delegate_validator (named in the
#                     registry) exits 0 on the artifact.
#     - non-conformant = required_field absent (contract requires it since required_since) OR the
#                     delegate_validator reports shape drift.
#   The gate itself only checks required_field PRESENCE (a class-agnostic registry contract) and
#   delegates all per-field SHAPE semantics to the registry-named validator — it does NOT
#   re-implement a second parallel classifier (canonical-contract-governance.md § No special
#   writer paths / Canonical shape first).
#
#   NEW-vs-EXISTING classification is DRAINING-LEDGER-ENROLLMENT based, NOT namespace based.
#   docs-manager/**/specs/** is gitignored, so git base-diff cannot distinguish a newly created
#   artifact from a pre-existing one. Instead, a one-time migration baseline seed enrolls every
#   currently-non-conformant artifact (regardless of active vs archive namespace) into a draining
#   migration ledger as known pre-existing debt. Thereafter:
#     - non-conformant AND enrolled in the ledger  => OK/draining (the gate does NOT fail on it).
#     - non-conformant AND NOT enrolled (i.e. NEW)  => fail-closed (exit 2 +
#                     POLARIS_ARTIFACT_CONTRACT_NON_CONFORMANT), enumerating every violation.
#   The ledger DRAINS: when an enrolled artifact later becomes conformant it is removed from the
#   ledger and `remaining` decreases toward target_remaining=0. It is a migration debt record with
#   an owner (migration_owner), NOT a permanent grandfather / waiver. A NEW (unenrolled) violation
#   is NEVER written into the ledger.
#
# Modes:
#   (default)           steady-state gate: fail-closed on NEW (unenrolled) non-conformant; enrolled
#                       debt passes; drains conformant entries out of an existing ledger.
#   --seed-baseline     migration baseline: enroll EVERY currently-non-conformant artifact into the
#                       draining ledger as pre-existing debt, then exit 0. Run once at migration time
#                       (and re-runnable to re-baseline). This is the only mode that ADDS enrollments.
# Inputs:
#   --registry <path>     (default: <repo>/scripts/lib/artifact-contract-registry.json)
#   --scan-root <dir>     (default: repo root; base for enumerate_glob + relative delegate paths)
#   --ledger-dir <dir>    (default: <scan-root>/.polaris/evidence/artifact-contract-migration)
#   --class <id>          (optional: restrict to one artifact class)
#   --seed-baseline       (enroll all current non-conformant as baseline debt; exit 0)
# Outputs: exit 0 PASS (incl. steady-state with only enrolled draining debt; and --seed-baseline);
#          exit 2 POLARIS_ARTIFACT_CONTRACT_NON_CONFORMANT (NEW/unenrolled violations) or
#          POLARIS_ARTIFACT_CONTRACT_USAGE (bad args / unreadable registry).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REGISTRY="$REPO_ROOT/scripts/lib/artifact-contract-registry.json"
SCAN_ROOT="$REPO_ROOT"
LEDGER_DIR=""
CLASS_FILTER=""
MODE="check"

die_usage() { echo "POLARIS_ARTIFACT_CONTRACT_USAGE: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="${2:-}"; shift 2 ;;
    --scan-root) SCAN_ROOT="${2:-}"; shift 2 ;;
    --ledger-dir) LEDGER_DIR="${2:-}"; shift 2 ;;
    --class) CLASS_FILTER="${2:-}"; shift 2 ;;
    --seed-baseline) MODE="seed"; shift ;;
    --help|-h) sed -n '2,55p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die_usage "unknown arg: $1" ;;
  esac
done

[[ -f "$REGISTRY" ]] || die_usage "registry not found: $REGISTRY"
[[ -d "$SCAN_ROOT" ]] || die_usage "scan-root not a directory: $SCAN_ROOT"
[[ -n "$LEDGER_DIR" ]] || LEDGER_DIR="$SCAN_ROOT/.polaris/evidence/artifact-contract-migration"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_artifact_contract_conformance_1.py" "$REGISTRY" "$SCAN_ROOT" "$LEDGER_DIR" "$CLASS_FILTER" "$MODE"
