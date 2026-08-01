#!/usr/bin/env bash
# Purpose: Record what judge decided to hand downstream, once its checks pass.
# Inputs:  --source <dir>, --version-bump patch|minor|major, --summary <text>,
#          optional --head <sha> (defaults to HEAD).
# Outputs: writes {source}/.spine/delivery.json; exit 1 if the source is not in
#          a deliverable state.
#
# This is the seam between the second gate and whatever ships the result. It
# exists because "judge said PASS" is a sentence, and the thing that promotes a
# branch and cuts a release needs a record it can read without asking anyone.
#
# The fence is verified first and the intent is refused if it does not hold.
# Delivering a source whose frozen assertions no longer match what was signed
# would be shipping against a definition of success nobody agreed to.

set -euo pipefail

SOURCE_DIR=""
VERSION_BUMP=""
SUMMARY=""
HEAD_SHA=""

die() {
  # Description: print a POLARIS marker plus context to stderr and exit 1.
  # Args: $1 = marker, $2.. = message lines
  local marker="$1"
  shift
  echo "$marker" >&2
  printf '%s\n' "$@" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)       SOURCE_DIR="${2:-}"; shift 2 ;;
    --version-bump) VERSION_BUMP="${2:-}"; shift 2 ;;
    --summary)      SUMMARY="${2:-}"; shift 2 ;;
    --head)         HEAD_SHA="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: record-delivery-intent.sh --source <dir> --version-bump patch|minor|major --summary <text> [--head <sha>]" >&2
      exit 2
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$SOURCE_DIR" ]] || die "POLARIS_DELIVERY_INTENT_USAGE" "--source is required"
[[ -n "$SUMMARY" ]] || die "POLARIS_DELIVERY_INTENT_USAGE" \
  "--summary is required; it becomes the changelog entry a human will read"

case "$VERSION_BUMP" in
  patch|minor|major) ;;
  *) die "POLARIS_DELIVERY_INTENT_USAGE" \
       "--version-bump must be patch, minor or major (got '${VERSION_BUMP:-}')" ;;
esac

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INDEX="$SOURCE_DIR/index.md"
[[ -f "$INDEX" ]] || die "POLARIS_DELIVERY_INTENT_NO_INDEX" "no index.md under $SOURCE_DIR"

# A source that cannot prove its assertions are the ones that were signed has
# nothing to deliver against.
if ! bash "$ROOT_DIR/scripts/frozen-assertion-fence.sh" verify "$INDEX" >/dev/null 2>&1; then
  die "POLARIS_DELIVERY_INTENT_FENCE_UNVERIFIED" \
    "$INDEX did not pass fence verification; refusing to record delivery intent." \
    "Run it directly to see why:" \
    "  bash scripts/frozen-assertion-fence.sh verify $INDEX"
fi

destination="$(awk '
  NR == 1 && $0 == "---" { inside = 1; next }
  inside && $0 == "---"   { exit }
  inside && /^destination:[[:space:]]*/ {
    sub(/^destination:[[:space:]]*/, "")
    gsub(/[[:space:]]*(#.*)?$/, "")
    print
    exit
  }
' "$INDEX")"

[[ -n "$destination" ]] || die "POLARIS_DELIVERY_INTENT_NO_DESTINATION" \
  "$INDEX declares no destination; run check-source-destination.sh for the contract"

if [[ -z "$HEAD_SHA" ]]; then
  HEAD_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
fi
[[ -n "$HEAD_SHA" ]] || die "POLARIS_DELIVERY_INTENT_NO_HEAD" \
  "could not resolve a head sha; pass --head explicitly"

# Whoever runs this is the one accountable for the summary, same as the fence
# signer. Recording it makes the handoff traceable to a person, not a process.
judged_by="$(git -C "$ROOT_DIR" config user.name 2>/dev/null || echo unknown)"
judged_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

OUT_DIR="$SOURCE_DIR/.spine"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/delivery.json"

python3 - "$OUT" "$SOURCE_DIR" "$destination" "$HEAD_SHA" "$VERSION_BUMP" \
  "$SUMMARY" "$judged_by" "$judged_at" <<'PY'
import json
import sys

out, source, destination, head, bump, summary, by, at = sys.argv[1:9]
payload = {
    "schema_version": 1,
    "producer": "record-delivery-intent.sh",
    "source": source,
    "destination": destination,
    "head_sha": head,
    "version_bump": bump,
    "changelog_summary": summary,
    "judged_by": by,
    "judged_at": at,
}
with open(out, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

echo "RECORDED: $OUT"
echo "  destination=$destination head=${HEAD_SHA:0:12} bump=$VERSION_BUMP"
