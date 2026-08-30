#!/usr/bin/env bash
# Purpose: Record what judge decided to hand downstream, once its checks pass.
# Inputs:  --issue <dir>, --summary <text>,
#          optional --head <sha> (defaults to the head the evidence was measured at),
#          optional --delta-allows <path> (repeatable; see below).
# Outputs: writes {issue}/.spine/delivery.json; exit 1 if the source is not in
#          a deliverable state.
#
# --delta-allows: 驗證呼叫者的主張，不代它宣告
# ------------------------------------------
# 交付的 head 與證據量到的 head 不同時，預設拒絕——證據證的是一棵樹綠了。但有一種
# 差異是流程自己造出來的：下游先做了一件只動它自己那幾個檔案的事（壓版之類），然後
# 才回頭釘紀錄。那個 commit 在判定那一站根本還不存在，任何人都不可能量在它上面。
#
# 這種情況下呼叫者可以**指名**它動過哪些路徑，這支就去 git 驗這句話是不是真的：差集
# 裡出現任何一個沒被指名的路徑，照舊拒絕。指名什麼由呼叫者決定，因為那是它自己的
# 詞彙——這一層不認得「版號」「CHANGELOG」，也不該認得。沒有指名就是舊行為。
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
DELTA_ALLOWS=()

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
    --delta-allows) DELTA_ALLOWS+=("${2:-}"); shift 2 ;;
    -h|--help)
      echo "Usage: record-delivery-intent.sh --issue <dir> --summary <text> [--head <sha>] [--delta-allows <path>]..." >&2
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
  "$INDEX declares no destination; it is declared once by a human at the first gate," \
  "in the ticket's frontmatter. See this skill's SKILL.md for what the values mean." \
  "(The message here used to name check-source-destination.sh, deleted 2026-08-03 and" \
  "never relocated — pointing at it was telling people to run something that is gone.)"

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
DELTA_FROM_EVIDENCE="$(mktemp)"
# 每一棵有證據的樹與它各自的 head。單樹的單只有一筆，跟 head_sha 說的是同一件事；
# 多棵樹的單只有這一份說得完（DP-611）。
HEADS_FROM_EVIDENCE="$(mktemp)"
trap 'rm -f "$HEAD_FROM_EVIDENCE" "$TREE_FROM_EVIDENCE" "$DELTA_FROM_EVIDENCE" "$HEADS_FROM_EVIDENCE"' EXIT

if [[ ${#DELTA_ALLOWS[@]} -gt 0 && -z "$HEAD_SHA" ]]; then
  die "POLARIS_DELIVERY_INTENT_USAGE" \
    "--delta-allows 只有在同時指名 --head 的時候才有意義：它描述的是「證據量到的 head" \
    "與要交付的 head 之間」那段差異，沒有 --head 就沒有那段差異。"
fi

# 一個縮寫的 sha 進來的時候先解開它。證據裡記的是完整的 40 字元，直接拿縮寫去比會永遠
# 不相等——而下游那句話寫的是「量完之後又有 commit 落下去了」，於是使用者被指示去重跑
# 一次本來就正確的量測。2026-08-09 真的付過那個代價一次。
#
# 解不開就明說解不開，不要沉默地往下走：一個打錯的 sha 與一個縮寫的 sha 要長得不一樣。
if [[ -n "$HEAD_SHA" && ! "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  RESOLVED="$(git rev-parse --verify --quiet "${HEAD_SHA}^{commit}" 2>/dev/null || true)"
  if [[ -z "$RESOLVED" ]]; then
    die "POLARIS_DELIVERY_INTENT_HEAD_UNRESOLVED" \
      "--head 給的是 '$HEAD_SHA'，而 $(pwd) 解不出它是哪一個 commit。" \
      "給完整的 sha，或在看得到那個 commit 的工作區裡重跑。"
  fi
  echo "NOTE: --head '${HEAD_SHA}' 是縮寫，解開成 ${RESOLVED}。" >&2
  HEAD_SHA="$RESOLVED"
fi

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
python3 - "$ROOT_DIR" "$INDEX" "$ISSUE_DIR" "$HEAD_SHA" "$HEAD_FROM_EVIDENCE" \
  "$TREE_FROM_EVIDENCE" "$DELTA_FROM_EVIDENCE" "$HEADS_FROM_EVIDENCE" \
  "${DELTA_ALLOWS[@]+${DELTA_ALLOWS[@]}}" <<'PY' || exit 1
# 這兩個 import 放在最上面，不放在用得到它們的那個分支裡。條件運算式只求值被選中的那
# 一半，所以一個寫在 `if` 裡的 import 在另一條路上就不存在——而底下那條路只有「證據來
# 自不只一棵樹」的單走得到，框架自己的單全部是單樹，永遠走不到（DP-615）。
import json
import sys

sys.path.insert(0, sys.argv[1] + "/scripts/lib")
import assertion_verdicts as av

(root, index, issue, head, head_out, tree_out,
 delta_out, heads_out) = sys.argv[1:9]
delta_allows = sys.argv[9:]

report = av.judge(
    index, issue + "/.spine/evidence",
    head=head or None,
    delta_allows=delta_allows,
    # 第二層與第三層都開。這條路徑是唯一會寫下「這張單可以出貨」的地方，所以它讀的
    # 不能只是幾個 JSON 檔——那些檔案是誰寫的它自己說了算。報告那條路徑預設只做前
    # 兩層，因為它不宣稱任何東西。
    ledger_path=issue + "/.spine/measurement-ledger.json",
    rerun=True,
    oracle=root + "/scripts/run-hardened-oracle.sh",
)

if not report["ids"]:
    print("POLARIS_DELIVERY_INTENT_NO_ASSERTIONS", file=sys.stderr)
    print(f"{index} has a fence but no assertion ids in it; "
          "there is nothing to have proven", file=sys.stderr)
    sys.exit(1)

tally = av.counts(report)
if report["blockers"] or tally[av.FAIL] or tally[av.UNMEASURABLE]:
    print("POLARIS_DELIVERY_INTENT_EVIDENCE_INCOMPLETE", file=sys.stderr)
    print(f"{len(report['ids'])} assertions declared; "
          "refusing to record delivery intent:", file=sys.stderr)
    av.render(report, stream=sys.stderr)
    print("Re-measure at the delivered head with run-hardened-oracle.sh "
          "--evidence-out, then record again.", file=sys.stderr)
    sys.exit(1)

# 逐條都站得住了，才問「這一趟做成了幾層」。三層裡只有這一層會因為外面的狀態而做不成
# （另外兩層一個一定跑、一個上面寫死了 True）。**「這張單沒有量測登錄」不是豁免**：
# 少了它，一份手寫的證據可以自己指名一條一定會過的命令，而第三層會忠實地把它跑綠。
#
# 排在逐條之後，因為「哪一條沒過」是讀的人先要知道的事；一張連證據都還沒有的單，先被
# 告知「你的登錄不見了」只會讓人去修一個還沒輪到的東西。
if not report["layers"]["registered"]:
    print("POLARIS_DELIVERY_INTENT_EVIDENCE_INCOMPLETE", file=sys.stderr)
    print(av.layers_line(report), file=sys.stderr)
    print(f"交付這條路三層全要做。{issue}/.spine/measurement-ledger.json 讀不到，"
          "所以「證據記的命令是登錄過的那一條」沒有辦法問——先用 engineering 的 "
          "record-measurement-change.sh 把每條 assertion 的量測命令登錄起來。", file=sys.stderr)
    sys.exit(1)

print(av.layers_line(report))
for note in report["notes"]:
    print(f"NOTE: {note}")
open(head_out, "w", encoding="utf-8").write(report["head"])
open(tree_out, "w", encoding="utf-8").write(report["measured_in"])
# 一棵樹的時候不寫——那份紀錄已經有 head_sha 與這張單自己的落腳處宣告，多一個只說同一
# 件事的欄位遲早會跟它們不一致。
open(heads_out, "w", encoding="utf-8").write(
    json.dumps(report["heads"], ensure_ascii=False) if len(report["heads"]) > 1 else "")
if report["delta"]:
    open(delta_out, "w", encoding="utf-8").write(
        json.dumps(report["delta"], ensure_ascii=False))
    # 兩個被說成不同的 sha 要印得看得出不同——其中一個是另一個的前綴時，截成 12 個字元
    # 會印出兩個一模一樣的字串然後說它們不同（2026-08-09 真的印過那一行）。
    shown_from, shown_head = av.distinguish(report["delta"]["from"], report["head"])
    print(f"EVIDENCE: {len(report['ids'])} assertions measured at "
          f"{shown_from}, delivering {shown_head} "
          f"({', '.join(report['ids'])})")
    print(f"  中間那段差異只碰了呼叫者指名的路徑，共 {len(report['delta']['paths'])} 個："
          f"{'、'.join(report['delta']['paths'])}")
else:
    print(f"EVIDENCE: {len(report['ids'])} assertions measured at "
          f"{report['head'][:12]} ({', '.join(report['ids'])})")
PY

HEAD_SHA="$(cat "$HEAD_FROM_EVIDENCE")"
DELIVERED_IN="$(cat "$TREE_FROM_EVIDENCE")"
HEAD_DELTA="$(cat "$DELTA_FROM_EVIDENCE")"
EVIDENCE_HEADS="$(cat "$HEADS_FROM_EVIDENCE")"
# 證據自己說它量在哪。底下的 fallback 會在問不到的時候把 DELIVERED_IN 換成這張單的宣告，
# 換完之後那兩個值就一定相等——所以要比對的那一份得在換之前留下來。
EVIDENCE_TREE="$DELIVERED_IN"

# 兩種情況會讓「改動落在哪」問不到那份證據：DP-482 之前產生的證據根本沒記下這件事，
# 以及**記下了、但那棵樹已經不在**——釋出尾段的前一步就是移除量測用的 worktree。第二種
# 不是「不知道改動落在哪」，只是那個資料夾沒了，而底下的枚舉問的是 commit 之間的事。
#
# 兩種都退回去問那張單自己的宣告，它只有一個產生者。宣告也給不出一個還在的地方時**說
# 出來**，讓枚舉走它自己的預設——一個安靜地帶著死路徑往下跑的呼叫，會在枚舉那一層炸成
# 一句跟根因無關的話。
GONE_TREE=""
if [[ -n "$DELIVERED_IN" && ! -d "$DELIVERED_IN" ]]; then
  GONE_TREE="$DELIVERED_IN"
  DELIVERED_IN=""
fi
if [[ -z "$DELIVERED_IN" ]]; then
  LANDING_RESOLVER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/driving-work-to-done/scripts/spine-loop-state.sh"
  if [[ -f "$LANDING_RESOLVER" && -f "$ISSUE_DIR/.spine/loop-state.json" ]]; then
    DECLARED_IN="$(bash "$LANDING_RESOLVER" landing --state "$ISSUE_DIR/.spine/loop-state.json" 2>/dev/null | head -n 1 || true)"
    [[ -n "$DECLARED_IN" && -d "$DECLARED_IN" ]] && DELIVERED_IN="$DECLARED_IN"
  fi
  if [[ -n "$DELIVERED_IN" ]]; then
    if [[ -n "$GONE_TREE" ]]; then
      echo "NOTE: 證據記的量測工作區 ${GONE_TREE} 已經不在，改動落在哪改讀這張單的宣告：${DELIVERED_IN}"
    else
      echo "NOTE: 證據沒記下量的是哪一棵樹，改動落在哪改讀這張單的宣告：${DELIVERED_IN}"
    fi
  elif [[ -n "$GONE_TREE" ]]; then
    echo "NOTE: 證據記的量測工作區 ${GONE_TREE} 已經不在，而這張單的宣告也給不出一個還在的地方；" \
         "底下的枚舉走它自己的預設（單住的那個 repo），這一趟沒有問到改動真的落下去的那棵樹。"
  fi
fi

# 這張單記過幾輪。**只說不擋**——沒記過輪次不使一份三層都齊備的交付變成不合格，所以這裡
# 不會有第二個離場碼。它會被說出來，是因為位置重算拿「記過幾輪」判這張單走到哪：一張沒有
# 人記過輪次的單，重算會把它放進「開工了、還沒有人寫下來」那一格，而那一格不是終局。
#
# DP-627 是這件事最貴的一次：它 tag、release、併進預設分支都做完了，而輪次紀錄是空的，
# 於是它留在那一格，`next` 一直把一件已經出貨的事當成待辦提出來。補救是人手動做的。
if [[ -f "$ISSUE_DIR/.spine/loop-state.json" ]]; then
  ROUNDS_SEEN="$(python3 -c '
import json, sys
try:
    print(len(json.load(open(sys.argv[1], encoding="utf-8")).get("rounds") or []))
except Exception:
    print("?")
' "$ISSUE_DIR/.spine/loop-state.json" 2>/dev/null || echo '?')"
  if [[ "$ROUNDS_SEEN" == "0" ]]; then
    echo "NOTE: 這張單一輪都沒記過，所以位置重算讀不到它走到哪——交付紀錄寫得成，" \
         "但它不會因此走到終局那一格。要讓它走到，跑 spine-loop-state.sh record --outcome converged。"
  elif [[ "$ROUNDS_SEEN" == "?" ]]; then
    echo "NOTE: 這張單的輪次狀態讀不動，所以「記過幾輪」這一次沒有問到——那不是「零輪」。"
  fi
fi

# 證據量在哪棵樹，跟這張單宣告它落在哪，要對得上。
#
# 上面那段 fallback 只在「問不到」的時候拿宣告來補，兩邊**都答得出來**的時候它從來不比
# ——而那正是會出事的那一種：量測命令自己在命令字串裡 `cd` 進產品 repo，oracle 的 run_dir
# 仍然是呼叫者站的框架 repo，於是 head 取自一棵跟這張單無關的樹。那份紀錄看起來完全正常，
# 而它綁住的 commit 只要框架 repo 有人壓版就會變，跟這張單的產出無關（2026-08-28 兩張產品單）。
#
# 修法不是多一個欄位——旋鈕早就有了（run-hardened-oracle.sh 的 --cwd 設 run_dir，而 head_sha
# 與 measured_in 都從 run_dir 取，DP-482 做的）。缺的只是沒有人比對，於是沒有人轉它。
#
# **這一項現在由判定那一層做**（`assertion_verdicts.judge`）。它本來在這裡，而在這裡的
# 代價是看報告的人看不到它——`report-assertions.sh` 走的是同一個 judge，卻讀不到一條只
# 寫在交付腳本裡的規矩。搬過去之後：證據量在宣告外的樹是一條 blocker、宣告問不到是一句
# 說出來的話、而「一張單宣告不只一棵樹」是被支援的形狀而不是歧義（DP-611）。
#
# 這裡不留第二份。同一條規矩兩個實作會漂，而漂掉的那一刻通常沒有人在看。

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
    "這張單的流程還撐在主流程要取代的舊層上，交付紀錄不寫：" "$legacy_out"
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
  "$SUMMARY" "$judged_by" "$judged_at" "$ISSUE_HEAD_SHA" "$HEAD_DELTA" \
  "$EVIDENCE_HEADS" <<'PY'
import json
import os
import sys

(out, source, destination, head, summary, by, at,
 source_head, head_delta, heads) = sys.argv[1:11]
# 記名字，不記路徑（DP-496 L-P2）。一張單的格位由 `place-issues-by-state.sh` 依狀態重算，
# 所以寫下來的那一條路徑在下一次重算之後就是死指標——實測 19 條存過的單路徑全部指向已經
# 不存在的目錄。位置要用的時候問 `spine-loop-state.sh find`，而讀這份紀錄的東西（釋出尾段的
# 關卡）本來就是從紀錄自己的位置認出這是哪張單的，從來沒有讀過這個欄位。
# `abspath` 而不是 `normpath`：從單自己的目錄裡用 `--issue .` 跑的時候，`normpath(".")`
# 還是 `"."`，於是這一欄記下一個叫「.」的單。上面那句「記名字，不記路徑」因此兩邊都沒做
# 到——記的既不是名字也不是路徑。沒有人發現是因為讀這份紀錄的東西從來沒讀過這個欄位，
# 而一個沒有消費者的欄位錯了不會有人紅（DP-615）。
issue = os.path.basename(os.path.abspath(source))
payload = {
    "schema_version": 2,
    "producer": "record-delivery-intent.sh",
    "issue": issue,
    "destination": destination,
    "head_sha": head,
    "issue_head_sha": source_head,
    "summary": summary,
    "judged_by": by,
    "judged_at": at,
}
# 證據不是量在交付的那個 head 上時，這份紀錄自己要說得出差在哪——量的是哪一個、交付的是
# 哪一個、中間那段碰了哪些檔案、呼叫者當初指名的是哪幾條。一個沒被說出來的豁免，跟沒有
# 豁免在出事的時候長得一樣。
if head_delta:
    payload["head_delta"] = json.loads(head_delta)
# 一張單交付到不只一棵樹的時候，`head_sha` 這個純量只說得出其中一棵。它留著原樣是因為
# 釋出尾段只讀得懂一個值，而那條尾段只跑框架自己的單（單樹）；多出來的這一份才說得完
# 每一棵樹綁在哪一個 commit 上（DP-611）。單樹的紀錄不長這個欄位，所以既有的 123 份
# 一份都不用動。
if heads:
    payload["heads"] = json.loads(heads)
with open(out, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

echo "RECORDED: $OUT"
echo "  destination=$destination head=${HEAD_SHA:0:12} source_head=${ISSUE_HEAD_SHA:0:12}"

