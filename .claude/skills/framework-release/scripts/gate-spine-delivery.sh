#!/usr/bin/env bash
# 為什麼這一道還在（門檻 2026-08-13，見 .claude/instructions/core/bootstrap.md）：
#   對著一份沒人簽過的成功定義出貨。tag 與 release 推出去收不回來。
# gate-spine-delivery.sh — the delivery-evidence gate for spine sources.
#
# Usage:
#   bash .claude/skills/framework-release/scripts/gate-spine-delivery.sh [--repo <path>]
#   bash .claude/skills/framework-release/scripts/gate-spine-delivery.sh [--repo <path>] --is-spine-push
#
# Exit: 0 = pass (or not a spine push), 2 = block.
#
# What this gate does and does not own
# ------------------------------------
# It owns exactly one question: does the recorded delivery intent still describe
# the commit being pushed?
#
# `record-delivery-intent.sh` writes {issue}/.spine/delivery.json pinned to a
# head sha, after verifying the frozen assertion fence. That record is what the
# release tail reads. It goes stale the moment another commit lands, and nothing
# re-verifies it — the failure mode is recording intent, committing more, then
# pushing while believing the record still covers the work.
#
# It deliberately does NOT constrain branch or PR naming. Under the old model the
# branch name was the lookup key for a task.md, so a wrong name silently resolved
# to someone else's evidence and had to be gated. A spine source names itself
# inside delivery.json; identity lives in the artifact, not in the ref. Naming is
# a convention for humans reading a PR list, and belongs in repo knowledge next to
# every other naming convention — not in a gate.
#
# It also does not own records belonging to other repositories. `issues/` is one
# directory shared by every repository its owner works in, so a delivery recorded
# from a product repo sits next to the framework's own records with a head that
# correctly does not exist here. Those are skipped because the commit is not in
# this repository — a fact, not a field — and each skip is printed together with
# the landing that ticket declared: a gate that silently drops what it cannot
# judge reads like one that judged it.
#
# Callers that already know which ticket they are releasing say so with --issue.
# Scanning every record and then working out which ones are this repo's business
# was the only reason a second "where does this land" answer had to exist here.
#
# Known limit, stated rather than hidden: this checks staleness, not existence. A
# source pushed with no delivery.json at all passes here, because judge may simply
# not have run yet and a work-in-progress push is legitimate. Absence surfaces
# downstream instead — the release tail has nothing to read and cannot ship it.

set -euo pipefail

PREFIX="[polaris gate-spine-delivery]"
REPO_ROOT=""
ONLY_ISSUE=""
IS_SPINE_PUSH_QUERY=0
PRINT_RECORDS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)           REPO_ROOT="${2:-}"; shift 2 ;;
    --issue)          ONLY_ISSUE="${2:-}"; shift 2 ;;
    --is-spine-push)  IS_SPINE_PUSH_QUERY=1; shift ;;
    --print-records)  PRINT_RECORDS=1; shift ;;
    -h|--help)
      echo "Usage: gate-spine-delivery.sh [--repo <path>] [--issue <dir>] [--is-spine-push] [--print-records]" >&2
      exit 0
      ;;
    *) shift ;;
  esac
done

[[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$HEAD_SHA" ]] || exit 0

# 每一行紀錄的欄位用 US（\x1f）隔開，不用 tab。tab 是 IFS whitespace，`read` 會把連續
# 的 tab 併成一個分隔符——所以只要中間有一欄是空的（destination 常常是），後面每一欄都
# 往前挪一格，而挪過的那一行看起來仍然是一行合法的紀錄。
FS=$'\x1f'

# Records skipped because the commit they name does not live here, kept so the
# skip can be said out loud. A gate that silently drops what it cannot judge
# reads exactly like a gate that judged it and found nothing wrong.
#
# DP-482: this used to compare a `delivering_repo` field against this repo's
# remote url — a second answer to "where does this ticket land", derived here at
# read time from wherever the caller happened to be standing. It disagreed with
# the ticket's own declaration the first time a ticket really landed in another
# repository, and this gate then blocked every framework release on a product
# repository's record. Ownership is now a fact rather than a derivation: a commit is either in
# this repository or it is not. Where it *does* belong is read from the ticket's
# declaration, which has exactly one producer.
FOREIGN=()

# Description: say where a ticket declared its work would land.
# Args: $1 = repo-relative issue dir
# Output: the declared landing values joined by 、, or empty when none was declared.
declared_landing() {
  local state="$REPO_ROOT/$1/.spine/loop-state.json"
  local resolver
  resolver="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/driving-work-to-done/scripts/spine-loop-state.sh"
  [[ -f "$state" && -f "$resolver" ]] || return 0
  bash "$resolver" landing --state "$state" 2>/dev/null | paste -sd'、' - || true
}

record_field() {
  # Description: read one field out of a delivery record.
  # Args: $1 = record path, $2 = field name
  # Output: the field value, or empty when absent or unreadable.
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],"") or "")' \
    "$1" "$2" 2>/dev/null || true
}

# Description: echo the source dirs whose delivery record concerns this push.
# Args:   none (reads REPO_ROOT / HEAD_SHA)
# Output: repo-relative issue dirs, e.g. issues/framework/DP-462-spine-cutover
#
# Relevance is decided by the head the record itself names, not by which files
# the push happens to touch. An earlier version matched paths under issues/ and
# was wrong: a spine source's work usually lands in scripts/ or skills/, and only
# the record lives under issues/, so real deliveries were not recognised as
# deliveries at all. The record already states which commit it is about — reading
# that is both simpler and correct, and it is the authoritative field the path
# heuristic was standing in for.
#
# A record is about this push when its head is the commit being pushed, or sits
# in the range about to leave the machine. A record whose head is already in
# origin/main describes work that shipped, and is none of this push's business.
judge_record() {
  # Description: classify one delivery record against the commit being pushed.
  # Args: $1 = repo-relative issue dir
  # Output: one tab-separated line, or nothing when the record has shipped already.
  local issue="$1" record head destination
  record="$REPO_ROOT/$issue/.spine/delivery.json"
  [[ -f "$record" ]] || return 0
  head="$(record_field "$record" head_sha)"
  [[ -n "$head" ]] || return 0
  destination="$(record_field "$record" destination)"

  # Ownership first, and it is a fact: a commit is either in this repository or it
  # is not. `issues/` is one directory shared by every repository its owner works
  # in, so records sitting next to each other do not all describe commits that
  # live here — and a commit that lives elsewhere is not a stale commit. Where it
  # does belong is answered by the ticket's own declaration, not by anything
  # derived here.
  if ! git -C "$REPO_ROOT" cat-file -e "${head}^{commit}" 2>/dev/null; then
    local landing
    landing="$(declared_landing "$issue")"
    # 宣告說得出它落在哪，就是「不是這裡的事」，跳過並把跳過的那一份印出來。
    # 說不出來的話這道閘什麼都判不動——那不是通過，是拒絕。一個判不動又安靜的紀錄，
    # 之後看起來就跟一個判過而且沒問題的紀錄一模一樣。
    if [[ -n "$landing" ]]; then
      printf '%s%s%s%s%s%s%s\n' "$issue" "$FS" foreign "$FS" "$destination" "$FS" "$landing"
    else
      printf '%s%s%s%s%s\n' "$issue" "$FS" unjudgeable "$FS" "$destination"
    fi

    return 0
  fi

  if [[ "$head" == "$HEAD_SHA" ]]; then
    printf '%s%s%s%s%s\n' "$issue" "$FS" current "$FS" "$destination"

    return 0
  fi
  # Already contained in what the remote has: shipped, not stale.
  if git -C "$REPO_ROOT" merge-base --is-ancestor "$head" origin/main 2>/dev/null; then
    return 0
  fi
  # In the range being pushed but not at its tip: work continued after the
  # second gate signed off, and the record no longer describes what ships.
  if git -C "$REPO_ROOT" merge-base --is-ancestor "$head" "$HEAD_SHA" 2>/dev/null; then
    printf '%s%s%s%s%s\n' "$issue" "$FS" stale "$FS" "$destination"
  fi
}

relevant_records() {
  local record issue
  # 呼叫者知道自己在釋出哪一張單的時候就直接說——掃全部紀錄再自行判斷歸屬，是 DP-482 之前
  # 才需要的動作，而那套歸屬判斷正是第二個權威的來源。spine-release.sh 從一開始就收 --issue。
  if [[ -n "$ONLY_ISSUE" ]]; then
    judge_record "${ONLY_ISSUE%/}"

    return 0
  fi
  # 不預設交付紀錄埋在第幾層。以前這裡寫死兩種深度（活躍區那一層與 {命名空間}/archive/），
  # 只掃第一種的那一版對每一次真實交付都回「這不是脊椎推送」。多開一格資料夾就要回來再補
  # 一條，而漏掉的那一條不會爆炸——掃不到只是找不到紀錄，看起來跟「這次推送與脊椎無關」
  # 一模一樣。DP-481 把六格開出來之後，released/{日期}/ 又多了一層。
  while IFS= read -r record; do
    [[ -f "$record" ]] || continue
    issue="${record#"$REPO_ROOT/"}"
    judge_record "${issue%/.spine/delivery.json}"
  done < <(find "$REPO_ROOT/issues" -type d -name .git -prune -o \
             -type f -path '*/.spine/delivery.json' -print 2>/dev/null | sort)
}

# Collected with a read loop rather than mapfile: the stock macOS bash is 3.2 and
# has no mapfile, so a gate written with it would silently exit 127 on the very
# machine that runs the pre-push hook.
RECORDS=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  case "$line" in
    # 掃描的時候，落在別處的紀錄是「不是這裡的事」——印出來、不判。被指名的時候不是：
    # 呼叫者說「我要釋出這一張」，而它的產出不在這個 repo，那是叫錯了地方，要擋。
    *"${FS}foreign${FS}"*)
      if [[ -n "$ONLY_ISSUE" ]]; then RECORDS+=("$line"); else FOREIGN+=("$line"); fi
      ;;
    *) RECORDS+=("$line") ;;
  esac
done < <(relevant_records)

# Said before any verdict, and said whether or not anything else happens. The
# count is the point: a reader who sees "2 skipped" and expected 0 has found
# something, and a reader who sees nothing has been told nothing.
if [[ ${#FOREIGN[@]} -gt 0 ]]; then
  echo "$PREFIX ${#FOREIGN[@]} record(s) name a commit this repository does not contain, and are not judged here:" >&2
  for entry in "${FOREIGN[@]}"; do
    IFS="$FS" read -r f_issue _f_state _f_destination f_landing <<<"$entry"
    echo "$PREFIX   - ${f_issue} → ${f_landing:-（這張單沒有宣告落腳處；spine-loop-state.sh land 可以補記）}" >&2
  done
fi

# Introspection: which records concern this push, as issue \t state \t destination.
# Added for the leak gate, which no longer needs it; kept because "which record
# concerns this push" must have exactly one resolver, and a future second reader
# asking that question has to come here rather than grow its own.
if [[ "$PRINT_RECORDS" -eq 1 ]]; then
  for entry in "${RECORDS[@]:-}"; do
    [[ -n "$entry" ]] && printf '%s\n' "$entry"
  done
  exit 0
fi

# No record concerns this push, so this gate has no opinion and must not claim
# ownership — the task.md-shaped gates still own whatever this is.
if [[ ${#RECORDS[@]} -eq 0 ]]; then
  [[ "$IS_SPINE_PUSH_QUERY" -eq 1 ]] && exit 1
  exit 0
fi

# Ownership is claimed for any push a record concerns, current or stale. Claiming
# only the current ones would hand a stale delivery back to a gate that cannot
# see the problem, and it would pass there.
[[ "$IS_SPINE_PUSH_QUERY" -eq 1 ]] && exit 0

failures=0
for entry in "${RECORDS[@]}"; do
  # Fields are issue, state, destination; read them positionally rather than by
  # trimming from the ends, which silently picked up the wrong field the moment a
  # third column arrived.
  IFS="$FS" read -r issue state _destination <<<"$entry"

  if [[ "$state" == "current" ]]; then
    echo "$PREFIX ✅ ${issue}: delivery intent current @ ${HEAD_SHA:0:12}." >&2
    continue
  fi

  recorded="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("head_sha",""))' \
    "$REPO_ROOT/$issue/.spine/delivery.json" 2>/dev/null || true)"
  # 只有被指名的那一張單走得到這裡帶著 foreign：掃描模式已經把它歸進 FOREIGN 印掉了。
  # 指名了一張單、而它的產出不在這個 repo，那不是「別人的事」，是叫錯了地方——所以擋。
  if [[ "$state" == "foreign" || "$state" == "unjudgeable" ]]; then
    echo "$PREFIX BLOCKED: ${issue} recorded its delivery intent at ${recorded:0:12}, which this repository does not contain." >&2
    if [[ "$state" == "foreign" ]]; then
      echo "$PREFIX 這張單宣告的落腳處是：$(declared_landing "$issue")" >&2
      echo "$PREFIX 要嘛在那個地方釋出，要嘛那份紀錄記錯了 head——重錄一次：" >&2
    else
      echo "$PREFIX 而這張單沒有宣告過改動會落在哪，所以說不出它是不是別的地方的事。" >&2
      echo "$PREFIX 判不動就不放行。先補記落腳處，再重錄一次：" >&2
      echo "$PREFIX   bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh land --state ${issue}/.spine/loop-state.json --where <工作區路徑>" >&2
    fi
    echo "$PREFIX   bash scripts/record-delivery-intent.sh --issue ${issue} --summary '<line>'" >&2
    failures=$((failures + 1))
    continue
  fi
  echo "$PREFIX BLOCKED: ${issue} recorded its delivery intent at ${recorded:0:12}, but HEAD is ${HEAD_SHA:0:12}." >&2
  echo "$PREFIX The record the release tail reads describes a different commit than the one being pushed." >&2
  echo "$PREFIX Re-run judge's handoff step so the record and the commit agree:" >&2
  echo "$PREFIX   bash scripts/record-delivery-intent.sh --issue ${issue} --summary '<line>'" >&2
  failures=$((failures + 1))
done

[[ "$failures" -eq 0 ]] || exit 2
exit 0
