#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-verify-evidence-layout.sh <evidence-dir> [evidence-dir ...]

Validates DP-110 verify evidence layout:
  verify-report.md
  links.json
  publication-manifest.json
  assets/{raw,images,screenshots,videos,files}/
USAGE
  exit 2
}

[[ $# -gt 0 ]] || usage

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_verify_evidence_layout_1.py" "$@"
