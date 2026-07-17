#!/usr/bin/env bash
# Purpose: Resolve a head-bound verification artifact path by delegating the
# canonical location functions in scripts/lib/verification-evidence.sh.
# Inputs: --kind verify|vr --repo PATH --ticket KEY --head-sha SHA.
# Outputs: canonical durable path (default) or a JSON record; no filesystem write.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_LIB="$SCRIPT_DIR/lib/verification-evidence.sh"
KIND=""
REPO=""
TICKET=""
HEAD_SHA=""
FORMAT="path"

usage() {
  local fd=2
  [[ "${1:-2}" -eq 0 ]] && fd=1
  cat >&"$fd" <<'USAGE'
Usage: resolve-artifact-location.sh --kind verify|vr --repo PATH --ticket KEY --head-sha SHA [--format path|json]
USAGE
  exit "${1:-2}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind|--repo|--ticket|--head-sha|--format)
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
        --format) FORMAT="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage 0 ;;
    *) echo "POLARIS_ARTIFACT_LOCATION_INVALID_ARGUMENT:$1" >&2; usage ;;
  esac
done

[[ "$KIND" == "verify" || "$KIND" == "vr" ]] || {
  echo "POLARIS_ARTIFACT_LOCATION_KIND_INVALID:${KIND:-missing}" >&2
  exit 2
}
[[ -n "$REPO" && -d "$REPO" ]] || {
  echo "POLARIS_ARTIFACT_LOCATION_REPO_INVALID:${REPO:-missing}" >&2
  exit 2
}
[[ -n "$TICKET" ]] || { echo "POLARIS_ARTIFACT_LOCATION_TICKET_REQUIRED" >&2; exit 2; }
[[ -n "$HEAD_SHA" ]] || { echo "POLARIS_ARTIFACT_LOCATION_HEAD_REQUIRED" >&2; exit 2; }
[[ "$FORMAT" == "path" || "$FORMAT" == "json" ]] || {
  echo "POLARIS_ARTIFACT_LOCATION_FORMAT_INVALID:$FORMAT" >&2
  exit 2
}
[[ -f "$EVIDENCE_LIB" ]] || {
  echo "POLARIS_ARTIFACT_LOCATION_AUTHORITY_MISSING:$EVIDENCE_LIB" >&2
  exit 2
}
command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "修復：執行 'mise install'（或依序執行 'mise run bootstrap' 與 'mise run doctor -- --profile runtime'）。" >&2
  exit 2
}

current_head="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$current_head" && "$current_head" == "$HEAD_SHA" ]] || {
  echo "POLARIS_ARTIFACT_LOCATION_HEAD_MISMATCH:expected=$HEAD_SHA:actual=${current_head:-missing}" >&2
  exit 2
}

# shellcheck source=scripts/lib/verification-evidence.sh
source "$EVIDENCE_LIB"
case "$KIND" in
  verify) artifact_path="$(verification_evidence_durable_path "$REPO" "$TICKET" "$HEAD_SHA")" ;;
  vr) artifact_path="$(vr_evidence_durable_path "$REPO" "$TICKET" "$HEAD_SHA")" ;;
esac

if [[ "$FORMAT" == "json" ]]; then
  python3 - "$KIND" "$REPO" "$TICKET" "$HEAD_SHA" "$artifact_path" <<'PY'
import json
import sys

kind, repo, ticket, head_sha, path = sys.argv[1:6]
print(json.dumps({
    "kind": kind,
    "repo": repo,
    "ticket": ticket,
    "head_sha": head_sha,
    "path": path,
    "authority": "scripts/lib/verification-evidence.sh",
}, ensure_ascii=False, sort_keys=True))
PY
else
  printf '%s\n' "$artifact_path"
fi
