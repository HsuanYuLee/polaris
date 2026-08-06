#!/usr/bin/env bash
# Purpose: Record what judge decided to hand downstream, once its checks pass.
# Inputs:  --issue <dir>, --version-bump patch|minor|major, --summary <text>,
#          optional --head <sha> (defaults to HEAD).
# Outputs: writes {issue}/.spine/delivery.json; exit 1 if the source is not in
#          a deliverable state.
#
# This is the seam between the second gate and whatever ships the result. It
# exists because "judge said PASS" is a sentence, and the thing that promotes a
# branch and cuts a release needs a record it can read without asking anyone.
#
# The fence is verified first and the intent is refused if it does not hold.
# Delivering a source whose frozen assertions no longer match what was signed
# would be shipping against a definition of success nobody agreed to.
#
# Then every assertion the fence declares must have oracle evidence at the head
# being delivered. That is the difference between a definition of success that
# was agreed to and one that was met.

set -euo pipefail

ISSUE_DIR=""
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
    --issue)       ISSUE_DIR="${2:-}"; shift 2 ;;
    --version-bump) VERSION_BUMP="${2:-}"; shift 2 ;;
    --summary)      SUMMARY="${2:-}"; shift 2 ;;
    --head)         HEAD_SHA="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: record-delivery-intent.sh --issue <dir> --version-bump patch|minor|major --summary <text> [--head <sha>]" >&2
      exit 2
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ISSUE_DIR" ]] || die "POLARIS_DELIVERY_INTENT_USAGE" "--issue is required"
[[ -n "$SUMMARY" ]] || die "POLARIS_DELIVERY_INTENT_USAGE" \
  "--summary is required; it becomes the changelog entry a human will read"

case "$VERSION_BUMP" in
  patch|minor|major) ;;
  *) die "POLARIS_DELIVERY_INTENT_USAGE" \
       "--version-bump must be patch, minor or major (got '${VERSION_BUMP:-}')" ;;
esac

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INDEX="$ISSUE_DIR/index.md"
[[ -f "$INDEX" ]] || die "POLARIS_DELIVERY_INTENT_NO_INDEX" "no index.md under $ISSUE_DIR"

# A source that cannot prove its assertions are the ones that were signed has
# nothing to deliver against.
if ! bash "$ROOT_DIR/scripts/frozen-assertion-fence.sh" verify "$INDEX" >/dev/null 2>&1; then
  die "POLARIS_DELIVERY_INTENT_FENCE_UNVERIFIED" \
    "$INDEX did not pass fence verification; refusing to record delivery intent." \
    "Run it directly to see why:" \
    "  bash .claude/skills/verify-ac/scripts/frozen-assertion-fence.sh verify $INDEX"
fi

# 舊層還撐著的話，這張單交付不出去。這道檢查以前只寫在散文裡，於是它對每一張真單都紅了
# 幾個月而沒有人知道——一道沒有人呼叫的檢查跟沒有那道檢查，在出事的時候長得一樣。所以
# 它接在這裡：清單由枚舉器產生（手寫的清單由寫的人決定漏掉什麼），寫紀錄之前跑，非 0 就
# 不寫。枚舉器跑不起來也不放行，那是量不到，不是通過。
INVENTORY="$ISSUE_DIR/.spine/inventory.json"
if ! bash "$ROOT_DIR/scripts/enumerate-spine-inventory.sh" --issue "$ISSUE_DIR" >/dev/null 2>&1; then
  die "POLARIS_DELIVERY_INTENT_INVENTORY_UNBUILDABLE" \
    "無法枚舉這張單逼出了哪些檔案，交付紀錄不寫。直接跑它看原因：" \
    "  bash .claude/skills/verify-ac/scripts/enumerate-spine-inventory.sh --issue $ISSUE_DIR"
fi
if ! legacy_out="$(bash "$ROOT_DIR/scripts/check-spine-legacy-layers.sh" --inventory "$INVENTORY" 2>&1)"; then
  die "POLARIS_DELIVERY_INTENT_LEGACY_LAYER_FORCED" \
    "這張單的流程還撐在脊椎要取代的舊層上，交付紀錄不寫：" "$legacy_out"
fi
echo "$legacy_out"

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

# Two repositories, two heads, and they are not interchangeable. What ships is the
# checkout this is invoked from — not the one this script happens to sit in, which
# differs inside a worktree. What was judged is the source's own repository, which
# issues/ is: the documents belong to whoever uses the framework, so they are
# versioned separately. Recording only one of these would leave the release tail
# pinned to a commit from the wrong history.
DELIVERING_REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "$ROOT_DIR")"
ISSUE_REPO="$(git -C "$(dirname "$INDEX")" rev-parse --show-toplevel 2>/dev/null || echo "$DELIVERING_REPO")"
if [[ -z "$HEAD_SHA" ]]; then
  HEAD_SHA="$(git -C "$DELIVERING_REPO" rev-parse HEAD 2>/dev/null || true)"
fi
[[ -n "$HEAD_SHA" ]] || die "POLARIS_DELIVERY_INTENT_NO_HEAD" \
  "could not resolve a head sha; pass --head explicitly"

# Empty when the source has no history of its own — the fence verifier already
# refuses that case, so this records the absence rather than inventing a value.
ISSUE_HEAD_SHA="$(git -C "$ISSUE_REPO" rev-parse HEAD 2>/dev/null || true)"

# Every assertion the fence declares has to have been measured, at this head, by
# the oracle. Before this check nothing anywhere required evidence to exist
# before delivery: this script re-verified the fence, gate-spine-delivery says
# in its own words that it checks staleness rather than existence, and the
# release tail mentions neither evidence nor oracle. "Judge said PASS" was
# carried in prose the whole way.
#
# The head has to match because evidence proves a tree green, not a branch.
# Measurements taken three commits ago say nothing about what is being shipped,
# and a flow that runs to the end on one word is exactly the flow that would
# otherwise ship them.
#
# The producer has to be the oracle because a hand-written PASS is
# self-certification. The oracle pins tools before trusting them and keeps the
# exit code; a JSON file is whoever typed it.
python3 - "$INDEX" "$ISSUE_DIR/.spine/evidence" "$HEAD_SHA" <<'PY' || exit 1
import json
import os
import re
import sys

index_path, evidence_dir, head = sys.argv[1:4]

fences = re.findall(
    r"<!-- POLARIS-FROZEN-[A-Z]+-BEGIN -->(.*?)<!-- POLARIS-FROZEN-[A-Z]+-END -->",
    open(index_path, encoding="utf-8").read(),
    re.S,
)
# An id opening a list item, bold or not. Matching only the bold form would tie
# this to one house style and quietly find nothing when someone drops the
# asterisks — and finding nothing here reads as "nothing to prove".
# Ordered, de-duplicated: the report reads in the order a person signed them.
ids = list(dict.fromkeys(re.findall(
    r"^[ \t]*[-*][ \t]*\**([A-Z]+-[PN]\d+)\b", "\n".join(fences), re.M)))

if not ids:
    print("POLARIS_DELIVERY_INTENT_NO_ASSERTIONS", file=sys.stderr)
    print(f"{index_path} has a fence but no assertion ids in it; "
          "there is nothing to have proven", file=sys.stderr)
    sys.exit(1)

problems = []
for aid in ids:
    path = os.path.join(evidence_dir, f"{aid}.json")
    if not os.path.exists(path):
        problems.append(f"  {aid}: no evidence at {path}")
        continue
    try:
        ev = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError) as exc:
        problems.append(f"  {aid}: evidence unreadable ({exc})")
        continue
    if ev.get("producer") != "run-hardened-oracle.sh":
        problems.append(
            f"  {aid}: producer is {ev.get('producer')!r}, not run-hardened-oracle.sh")
    if ev.get("verdict") != "PASS":
        problems.append(f"  {aid}: verdict is {ev.get('verdict')!r}, not PASS")
    elif ev.get("head_sha") != head:
        problems.append(
            f"  {aid}: measured at {str(ev.get('head_sha'))[:12]}, delivering {head[:12]}")

if problems:
    print("POLARIS_DELIVERY_INTENT_EVIDENCE_INCOMPLETE", file=sys.stderr)
    print(f"{len(ids)} assertions declared; refusing to record delivery intent:",
          file=sys.stderr)
    print("\n".join(problems), file=sys.stderr)
    print("Re-measure at the delivered head with run-hardened-oracle.sh "
          "--evidence-out, then record again.", file=sys.stderr)
    sys.exit(1)

print(f"EVIDENCE: {len(ids)} assertions measured at {head[:12]} ({', '.join(ids)})")
PY

# Whoever runs this is the one accountable for the summary, same as the fence
# signer. Recording it makes the handoff traceable to a person, not a process.
judged_by="$(git -C "$DELIVERING_REPO" config user.name 2>/dev/null || echo unknown)"
judged_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Which repository the head belongs to. Without it a record is a bare sha, and a
# bare sha cannot be told apart from a stale one by anybody reading it later:
# issues/ is shared across every repository this person works in, so a delivery
# recorded from a product repo lands next to the framework's own records and its
# head is — correctly — absent from the framework. gate-spine-delivery.sh read
# that absence as "unusable, refuse", which blocked every framework push from the
# moment the first product-repo delivery was recorded.
#
# Recorded verbatim rather than normalised. The gate compares it against the same
# command run in its own repository, so two runs on the same clone agree exactly;
# a mismatch that is really the same repository under a different remote URL shows
# up in the gate's enumerated skip list with both strings printed, which is a
# reader's problem to judge and not a silent pass.
delivering_repo="$(git -C "$DELIVERING_REPO" config --get remote.origin.url 2>/dev/null || true)"
[[ -n "$delivering_repo" ]] || delivering_repo="$DELIVERING_REPO"

OUT_DIR="$ISSUE_DIR/.spine"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/delivery.json"

python3 - "$OUT" "$ISSUE_DIR" "$destination" "$HEAD_SHA" "$VERSION_BUMP" \
  "$SUMMARY" "$judged_by" "$judged_at" "$ISSUE_HEAD_SHA" "$delivering_repo" <<'PY'
import json
import sys

(out, source, destination, head, bump, summary, by, at, source_head,
 delivering_repo) = sys.argv[1:11]
payload = {
    "schema_version": 1,
    "producer": "record-delivery-intent.sh",
    "source": source,
    "destination": destination,
    "delivering_repo": delivering_repo,
    "head_sha": head,
    "issue_head_sha": source_head,
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
echo "  destination=$destination head=${HEAD_SHA:0:12} source_head=${ISSUE_HEAD_SHA:0:12} bump=$VERSION_BUMP"

