#!/usr/bin/env bash
# Purpose: Validate that a verify/VR artifact occupies the canonical location
# and is bound to the requested ticket and current HEAD.
# Inputs: resolver coordinates plus optional --artifact PATH.
# Outputs: PASS or a POLARIS_ARTIFACT_LOCATION_* blocking marker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-artifact-location.sh"
EVIDENCE_LIB="$SCRIPT_DIR/lib/verification-evidence.sh"
KIND=""
REPO=""
TICKET=""
HEAD_SHA=""
ARTIFACT=""

usage() {
  local fd=2
  [[ "${1:-2}" -eq 0 ]] && fd=1
  cat >&"$fd" <<'USAGE'
Usage: validate-artifact-location.sh --kind verify|vr --repo PATH --ticket KEY --head-sha SHA [--artifact PATH]
USAGE
  exit "${1:-2}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind|--repo|--ticket|--head-sha|--artifact)
      option="$1"
      [[ $# -ge 2 && -n "${2:-}" && "${2:-}" != --* ]] || {
        echo "POLARIS_ARTIFACT_LOCATION_OPTION_VALUE_REQUIRED:$option" >&2
        exit 2
      }
      case "$option" in
        --kind) KIND="$2" ;;
        --repo) REPO="$2" ;;
        --ticket) TICKET="$2" ;;
        --head-sha) HEAD_SHA="$2" ;;
        --artifact) ARTIFACT="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage 0 ;;
    *) echo "POLARIS_ARTIFACT_LOCATION_INVALID_ARGUMENT:$1" >&2; usage ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "修復：執行 'mise install'（或依序執行 'mise run bootstrap' 與 'mise run doctor -- --profile runtime'）。" >&2
  exit 2
}

expected="$($RESOLVER --kind "$KIND" --repo "$REPO" --ticket "$TICKET" --head-sha "$HEAD_SHA")" || exit 2
[[ -n "$ARTIFACT" ]] || ARTIFACT="$expected"
[[ "$ARTIFACT" == "$expected" ]] || {
  echo "POLARIS_ARTIFACT_LOCATION_NONCANONICAL:expected=$expected:actual=$ARTIFACT" >&2
  exit 2
}
[[ -f "$ARTIFACT" ]] || {
  echo "POLARIS_ARTIFACT_LOCATION_MISSING:$ARTIFACT" >&2
  exit 2
}

# shellcheck source=scripts/lib/verification-evidence.sh
source "$EVIDENCE_LIB"
VERIFY_VALIDATE_FN="verification_evidence_validate_file"
VERIFY_PASS_FN="verification_evidence_is_pass"
VR_VALIDATE_FN="vr_evidence_validate_file"
case "$KIND" in
  verify)
    "$VERIFY_VALIDATE_FN" "$ARTIFACT" "$TICKET" "$HEAD_SHA" >/dev/null || {
      echo "POLARIS_ARTIFACT_LOCATION_MARKER_INVALID:$ARTIFACT" >&2
      exit 2
    }
    "$VERIFY_PASS_FN" "$ARTIFACT" >/dev/null || {
      echo "POLARIS_ARTIFACT_LOCATION_MARKER_NOT_PASS:$ARTIFACT" >&2
      exit 2
    }
    ;;
  vr)
    "$VR_VALIDATE_FN" "$ARTIFACT" "$TICKET" "$HEAD_SHA" compare >/dev/null || {
      echo "POLARIS_ARTIFACT_LOCATION_MARKER_INVALID:$ARTIFACT" >&2
      exit 2
    }
    [[ "$(vr_evidence_normalized_outcome "$ARTIFACT")" == "PASS" ]] || {
      echo "POLARIS_ARTIFACT_LOCATION_MARKER_NOT_PASS:$ARTIFACT" >&2
      exit 2
    }
    ;;
esac

echo "PASS: canonical $KIND artifact $ARTIFACT"
