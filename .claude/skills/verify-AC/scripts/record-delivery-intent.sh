#!/usr/bin/env bash
# Purpose: Record what judge decided to hand downstream, once its checks pass.
# Inputs:  --issue <dir>, --summary <text>,
#          optional --head <sha> (defaults to the head the evidence was measured at).
# Outputs: writes {issue}/.spine/delivery.json; exit 1 if the source is not in
#          a deliverable state.
#
# Why there is no version field here (DP-467 H-P3)
# ------------------------------------------------
# Semantic versioning is a release model, and release tails are project-private —
# `driving-work-to-done` and this skill's own prose both say so. Carrying the word
# here at all, even as an optional slot, teaches every adopter a vocabulary from a
# model they may not be on: a project whose delivery is a ticket and a deploy has
# nothing to put in that slot, and a slot it can only leave empty is a slot that
# says the portable layer expected something.
#
# The earlier round made the flag optional and wrote a long justification for
# keeping it. That was half a move. Asking "would a stranger who downloaded only
# this skill ever have written this field" answers itself — they would not, because
# the field only means anything to one release tail.
#
# So the version lives entirely in the release tail, and its declaration source is
# whatever that tail already reads. Here that is `.changeset/*.md`; the tail derives
# the bump from them and checks itself against them. Nothing crosses the seam.
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
    --summary)      SUMMARY="${2:-}"; shift 2 ;;
    --head)         HEAD_SHA="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: record-delivery-intent.sh --issue <dir> --summary <text> [--head <sha>]" >&2
      exit 2
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ISSUE_DIR" ]] || die "POLARIS_DELIVERY_INTENT_USAGE" "--issue is required"
[[ -n "$SUMMARY" ]] || die "POLARIS_DELIVERY_INTENT_USAGE" \
  "--summary is required; it is the one line describing what was delivered"

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

# Two repositories, two heads, and they are not interchangeable. What was judged
# is the source's own repository, which issues/ is: the documents belong to
# whoever uses the framework, so they are versioned separately. What ships is a
# different tree, and this script does not go looking for it — see below.
#
# `env -u`: git sets GIT_DIR in a hook environment, and an explicit GIT_DIR beats
# `-C` — `--show-toplevel` then answers for the cwd instead of the path asked about.
ISSUE_REPO="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$(dirname "$INDEX")" rev-parse --show-toplevel 2>/dev/null || echo "$ROOT_DIR")"

# Empty when the source has no history of its own — the fence verifier already
# refuses that case, so this records the absence rather than inventing a value.
ISSUE_HEAD_SHA="$(git -C "$ISSUE_REPO" rev-parse HEAD 2>/dev/null || true)"

# DP-482: the delivered head used to come from `git rev-parse HEAD` in whatever
# directory this was invoked from, and the record then carried a `delivering_repo`
# field derived the same way — a second answer to "where does this ticket land",
# produced by the one writer that stands furthest from the declaration. On the
# first ticket that really landed in another repository it disagreed with that
# ticket's own declaration, and the release gate believed the wrong one.
#
# The head now comes from the evidence, which is the only artifact that knows
# which tree was actually measured. That is not a substitute authority: a delivery
# record says "this tree was proven green", and the evidence is what proved it.
# Deriving the head from anywhere else lets the two disagree, which is exactly the
# failure the head check below exists to catch.
HEAD_FROM_EVIDENCE="$(mktemp)"
TREE_FROM_EVIDENCE="$(mktemp)"
trap 'rm -f "$HEAD_FROM_EVIDENCE" "$TREE_FROM_EVIDENCE"' EXIT

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
python3 - "$INDEX" "$ISSUE_DIR/.spine/evidence" "$HEAD_SHA" "$HEAD_FROM_EVIDENCE" \
  "$TREE_FROM_EVIDENCE" <<'PY' || exit 1
import json
import os
import re
import subprocess
import sys

index_path, evidence_dir, head, head_out, tree_out = sys.argv[1:6]

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
measured = {}
measured_in = {}
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
    elif not ev.get("head_sha"):
        problems.append(f"  {aid}: evidence names no head_sha")
    elif head and ev.get("head_sha") != head:
        problems.append(
            f"  {aid}: measured at {str(ev.get('head_sha'))[:12]}, delivering {head[:12]}")
    else:
        measured.setdefault(ev["head_sha"], []).append(aid)
        measured_in.setdefault(ev.get("measured_in") or "", []).append(aid)

# 沒有 --head 的時候，交付的 head 就是證據量到的那一棵樹。證據彼此不一致代表這幾條斷言
# 量的不是同一棵樹——那不是「取一個」就好，取哪一個都會讓另一批證據變成沒看過的東西。
if not problems and not head:
    if len(measured) > 1:
        problems.append("  證據指向不只一棵樹，說不出要交付哪一個 head：")
        for sha, aids in sorted(measured.items()):
            problems.append(f"    {sha[:12]}: {', '.join(aids)}")
    else:
        head = next(iter(measured))

# 證據說得出自己是在哪一棵樹上量的，所以「那棵樹現在還在不在那個 commit」問得到它本人。
# 這一條原本問的是呼叫者當下站的目錄——量完之後又推了幾個 commit 的時候它確實會紅，但
# 它紅的理由是「你站的地方變了」，而站的地方跟量的地方在 --cwd 之下根本是兩棵樹。
if not problems:
    trees = [d for d in measured_in if d]
    if len(trees) > 1:
        problems.append("  證據來自不只一棵樹，說不出要交付哪一個工作區：")
        for tree in sorted(trees):
            problems.append(f"    {tree}: {', '.join(measured_in[tree])}")
    elif not trees:
        # 揭露而不是放行：舊的證據沒有這個欄位，這一條就量不到。量不到跟量到沒問題是
        # 兩件事，安靜跳過會讓下一個讀的人以為它查過了。
        print("NOTE: 證據沒有記下它在哪一棵樹上量的（DP-482 之前產生的），"
              "「量完之後還有沒有新 commit」這一條沒有被檢查。")
    else:
        tip = subprocess.run(["git", "-C", trees[0], "rev-parse", "HEAD"],
                             capture_output=True, text=True).stdout.strip()
        if not tip:
            problems.append(f"  量測用的工作區問不出 HEAD：{trees[0]}")
        elif tip != head:
            problems.append(
                f"  證據量的是 {head[:12]}，但 {trees[0]} 現在在 {tip[:12]}——"
                "量完之後又有 commit 落下去了")

if problems:
    print("POLARIS_DELIVERY_INTENT_EVIDENCE_INCOMPLETE", file=sys.stderr)
    print(f"{len(ids)} assertions declared; refusing to record delivery intent:",
          file=sys.stderr)
    print("\n".join(problems), file=sys.stderr)
    print("Re-measure at the delivered head with run-hardened-oracle.sh "
          "--evidence-out, then record again.", file=sys.stderr)
    sys.exit(1)

open(head_out, "w", encoding="utf-8").write(head)
open(tree_out, "w", encoding="utf-8").write(next(iter(d for d in measured_in if d), ""))
print(f"EVIDENCE: {len(ids)} assertions measured at {head[:12]} ({', '.join(ids)})")
PY

HEAD_SHA="$(cat "$HEAD_FROM_EVIDENCE")"
DELIVERED_IN="$(cat "$TREE_FROM_EVIDENCE")"

# DP-482 之前產生的證據沒有記下它在哪一棵樹上量的。那時候退回去問「呼叫者站在哪」，
# 而那正是這張單要拆掉的形狀——所以退回去問那張單自己的宣告，它只有一個產生者。
if [[ -z "$DELIVERED_IN" ]]; then
  LANDING_RESOLVER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/driving-work-to-done/scripts/spine-loop-state.sh"
  if [[ -f "$LANDING_RESOLVER" && -f "$ISSUE_DIR/.spine/loop-state.json" ]]; then
    DELIVERED_IN="$(bash "$LANDING_RESOLVER" landing --state "$ISSUE_DIR/.spine/loop-state.json" 2>/dev/null | head -n 1 || true)"
    [[ -n "$DELIVERED_IN" ]] \
      && echo "NOTE: 證據沒記下量的是哪一棵樹，改動落在哪改讀這張單的宣告：$DELIVERED_IN"
  fi
fi

# 舊層還撐著的話，這張單交付不出去。這道檢查以前只寫在散文裡，於是它對每一張真單都紅了
# 幾個月而沒有人知道——一道沒有人呼叫的檢查跟沒有那道檢查，在出事的時候長得一樣。所以
# 它接在這裡：清單由枚舉器產生（手寫的清單由寫的人決定漏掉什麼），寫紀錄之前跑，非 0 就
# 不寫。枚舉器跑不起來也不放行，那是量不到，不是通過。
#
# 它排在證據之後而不是之前，因為「這次交付留下了什麼」要對著改動真的落下去的那棵樹問，
# 而說得出那是哪一棵的只有證據。排在前面的那一版是對著呼叫者站的地方問的（DP-482）。
INVENTORY="$ISSUE_DIR/.spine/inventory.json"
ENUMERATE=("$ROOT_DIR/scripts/enumerate-spine-inventory.sh" --issue "$ISSUE_DIR")
[[ -n "$DELIVERED_IN" ]] && ENUMERATE+=(--repo "$DELIVERED_IN")
if ! bash "${ENUMERATE[@]}" >/dev/null 2>&1; then
  die "POLARIS_DELIVERY_INTENT_INVENTORY_UNBUILDABLE" \
    "無法枚舉這張單逼出了哪些檔案，交付紀錄不寫。直接跑它看原因：" \
    "  bash ${ENUMERATE[*]}"
fi
if ! legacy_out="$(bash "$ROOT_DIR/scripts/check-spine-legacy-layers.sh" --inventory "$INVENTORY" 2>&1)"; then
  die "POLARIS_DELIVERY_INTENT_LEGACY_LAYER_FORCED" \
    "這張單的流程還撐在脊椎要取代的舊層上，交付紀錄不寫：" "$legacy_out"
fi
echo "$legacy_out"


# Whoever runs this is the one accountable for the summary, same as the fence
# signer. Recording it makes the handoff traceable to a person, not a process.
judged_by="$(git -C "$ISSUE_REPO" config user.name 2>/dev/null || echo unknown)"
judged_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# DP-482 removed a `delivering_repo` field from this payload. It existed so a
# reader could tell "this head belongs to another repository" apart from "this
# head is stale", and it answered that by asking git, here, for the remote url of
# wherever this script was invoked — a second producer of the fact the ticket
# already declares once, and the one standing furthest from the declaration.
#
# Nobody needs it. Whether a head lives in a given repository is answerable in
# that repository without a field (`git cat-file -e`), and where it *does* live is
# the ticket's declaration, which has one producer. A field that restates a fact
# two other places already own is a field that will eventually disagree with them.
OUT_DIR="$ISSUE_DIR/.spine"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/delivery.json"

python3 - "$OUT" "$ISSUE_DIR" "$destination" "$HEAD_SHA" \
  "$SUMMARY" "$judged_by" "$judged_at" "$ISSUE_HEAD_SHA" <<'PY'
import json
import sys

(out, source, destination, head, summary, by, at, source_head) = sys.argv[1:9]
payload = {
    "schema_version": 1,
    "producer": "record-delivery-intent.sh",
    "source": source,
    "destination": destination,
    "head_sha": head,
    "issue_head_sha": source_head,
    "summary": summary,
    "judged_by": by,
    "judged_at": at,
}
with open(out, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

echo "RECORDED: $OUT"
echo "  destination=$destination head=${HEAD_SHA:0:12} source_head=${ISSUE_HEAD_SHA:0:12}"

