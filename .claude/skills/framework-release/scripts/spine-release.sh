#!/usr/bin/env bash
# Purpose: Ship what the second gate signed off, reading {issue}/.spine/delivery.json.
# Inputs:  --issue <dir>, optional --repo, --execute (default is a preview).
# Outputs: version compression, main promotion, and — for a template-bound
#          source — template sync, tag and GitHub release. Exit 1 on any refusal.
#
# Why this exists separately from framework-release-execute.sh
# ------------------------------------------------------------
# That executor takes --task-md and orders itself around task PRs landing into a
# feat branch. A spine source has no task.md and no aggregation branch, so it
# cannot be expressed in that shape. Rather than widen the old executor to accept
# a shape it was not designed for, this composes the same underlying helpers —
# release-version.sh, framework-release-main-promotion.sh, sync-to-polaris.sh —
# from the delivery record instead. The old path is untouched and still works.
#
# The destination decides how far this goes. A workspace-bound source is promoted
# and stops: it gets no version and no changeset, because CHANGELOG.md itself
# syncs to the template and a workspace-only entry there would announce work that
# never shipped. Only a template-bound source runs the full tail.
#
# One honest tension, named rather than hidden: compressing the version adds a
# commit, which leaves the delivery record behind its own HEAD. This re-pins it,
# but only after proving the delta is exactly that one mechanical commit and the
# fence still holds. A re-pin across anything else is refused — otherwise the
# release tool would be a way to launder unsigned work past the gate.

set -euo pipefail

ISSUE_DIR=""
REPO_PATH=""
EXECUTE=0
PROBE_TAG=""
PROBE_BRANCH=""
PROBE_ISSUE_PATH=""
STATUS=0
PROBE_TAIL_PLAN=""
PROBE_RECORD_STATE=0

die() {
  # Description: print a POLARIS marker plus context to stderr and exit 1.
  # Args: $1 = marker, $2.. = message lines
  local marker="$1"; shift
  echo "$marker" >&2
  printf '%s\n' "$@" >&2
  exit 1
}

step() { echo "" >&2; echo "── $* ──" >&2; }
note() { echo "   $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)  ISSUE_DIR="${2:-}"; shift 2 ;;
    --repo)    REPO_PATH="${2:-}"; shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    # Answers "has origin already released this version?" and exits. The tail asks
    # the same question through this path, so a test can reach it without a
    # release; two answers to one question is how the skip below went wrong.
    --origin-has-tag) PROBE_TAG="${2:-}"; shift 2 ;;
    # 促進那一步問的第二個問題：「這條分支是不是已經在目的地分支裡了」。走同一條路徑
    # 讓測試問得到它，不必真的釋出一次——理由與上面那一個 probe 相同，一個問題兩個答案
    # 正是這裡出過錯的形狀。
    --branch-in-base) PROBE_BRANCH="${2:-}"; shift 2 ;;
    # 交給下游的那條單路徑。同上：印的與交的是同一個值。
    --issue-path) PROBE_ISSUE_PATH=1; shift ;;
    # 只讀：逐項問每個系統這一趟走到哪，印完就結束。什麼都不寫、不推、不建立。
    --status) STATUS=1; shift ;;
    # 只讀 probe：tag 與 release 各自要不要做（同一個函式，測試問到的與真的做的是同一份）。
    --tail-plan) PROBE_TAIL_PLAN="${2:-}"; shift 2 ;;
    # 只讀 probe：交付紀錄與 HEAD 的關係——current / resumable-version-commit / stale。
    --record-state) PROBE_RECORD_STATE=1; shift ;;
    -h|--help)
      echo "Usage: spine-release.sh --issue <dir> [--repo <path>] [--execute | --status]" >&2
      echo "Without --execute this previews what it would do and changes nothing." >&2
      echo "--status asks each system how far this release got, and writes nothing." >&2
      exit 0
      ;;
    *) die "POLARIS_SPINE_RELEASE_USAGE" "unknown argument: $1" ;;
  esac
done

[[ -n "$ISSUE_DIR" || -n "$PROBE_TAG" || -n "$PROBE_BRANCH" || -n "$PROBE_TAIL_PLAN" ]] \
  || die "POLARIS_SPINE_RELEASE_USAGE" "--issue is required"
[[ -n "$REPO_PATH" ]] || REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

# `--issue` 是相對於 `--repo` 的，而下游那幾支腳本各自對著**呼叫者當下的 cwd** 解析路徑。
# 這一行是這條路徑唯一的產生者：底下每一處交出去的都是它，不是那條相對的。
#
# 少了它的那一版，尾段從 repo 根以外的地方跑會死在 `POLARIS_DELIVERY_INTENT_NO_INDEX:
# no index.md under issues/…`——那句話說的是「這張單不見了」，而實際狀態是「你站的地方
# 不對」。2026-08-10 釋出 v4.23.0 時真的死在那裡，位置是版號已經壓下去、還沒推出去的
# 中間態（DP-500）。
#
# `if` 不是風格：`[[ … ]] && X=…` 在 ISSUE_DIR 為空時整句回非 0，而 `set -e` 會讓那一行
# 直接結束整支腳本——只帶 probe 旗標進來的那幾條路徑會安靜地什麼都不印。
ISSUE_ABS=""
if [[ -n "$ISSUE_DIR" ]]; then
  ISSUE_ABS="$REPO_PATH/$ISSUE_DIR"
fi

# Description: print the sha origin has for a tag, empty when origin has none.
# Args: $1 = tag name. Side effects: one network read of origin's refs.
origin_tag_sha() {
  local tag="$1"
  git -C "$REPO_PATH" ls-remote --tags origin "refs/tags/$tag" 2>/dev/null \
    | awk -v ref="refs/tags/$tag" '$2 == ref { print $1 }'
}

# Description: 這條分支的內容是不是已經在目的地分支裡了。
# Args: $1 = 分支名，$2 = 目的地 ref（例如 origin/main）。
# Returns: 0 表示已經在裡面，非 0 表示不在（含兩者任一解不出來）。
# 為什麼問 git 不問 gh：這是一個關於 commit 祖先的問題，本機答得出來，而尾段被打斷後
# 重跑的那一刻最不需要的就是再一次網路往返。
branch_in_base() {
  git -C "$REPO_PATH" merge-base --is-ancestor "$1" "$2" 2>/dev/null
}

if [[ -n "$PROBE_TAG" ]]; then
  origin_tag_sha "$PROBE_TAG"
  exit 0
fi
if [[ -n "$PROBE_BRANCH" ]]; then
  branch_in_base "$PROBE_BRANCH" "origin/main" && echo yes || echo no
  exit 0
fi
# Description: 這個 repo 在 GitHub 上叫什麼。
# Returns: `owner/name` 印到 stdout，問不到就印空字串（不 die：只讀模式要能報告「問不到」）。
resolve_workspace_repo() {
  (cd "$REPO_PATH" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
}

# Description: 這個 tag 的 GitHub release 存不存在。
# Args: $1 = tag，$2 = owner/name。
# Returns: 0 存在，非 0 不存在或問不到。
# 為什麼要單獨問：tag 與 release 是兩件事，而它們之間有一個真實的中斷點（DP-501）。
release_exists() {
  [[ -n "${2:-}" ]] || return 1
  gh release view "$1" --repo "$2" --json tagName >/dev/null 2>&1
}

# Description: 這一趟 tag 與 release 各自要不要做。
# Args: $1 = tag，$2 = owner/name。
# Outputs: 兩行——`tag push|skip` 與 `release create|skip|unknown`。
# 為什麼是兩行：舊的那一版用一個判斷（tag 在不在 origin 上）決定兩件事，於是推 tag 與建
# release 之間被切斷時，重跑會印「already on origin」然後回報 shipped，而那個 release
# 從來沒有存在過（DP-501）。真的要做的那一步讀的就是這兩行，probe 印的也是這兩行。
plan_tag_and_release() {
  local tag="$1" repo="${2:-}"
  if [[ -n "$(origin_tag_sha "$tag")" ]]; then echo "tag skip"; else echo "tag push"; fi
  if [[ -z "$repo" ]]; then
    echo "release unknown"
  elif release_exists "$tag" "$repo"; then
    echo "release skip"
  else
    echo "release create"
  fi
}

if [[ -n "$PROBE_TAIL_PLAN" ]]; then
  plan_tag_and_release "$PROBE_TAIL_PLAN" "$(resolve_workspace_repo)"
  exit 0
fi

if [[ -n "$PROBE_ISSUE_PATH" ]]; then
  # 交給下游的就是這一條。印它出來，測試才問得到「交出去的路徑換一個工作目錄開不開得到」，
  # 而且問到的與真的交出去的是同一個值——不是第二份。
  echo "$ISSUE_ABS"
  exit 0
fi
# The spine finds its own parts next to itself, not inside the repo being
# released — a released repo need not carry a copy of the spine.
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 交付紀錄是 verify-ac 的產物，重釘也得由它來寫。這裡跨 skill 取用，不自己複製一份：
# 兩份會漂，而漂掉的那一刻正好是「判定過的東西」與「出貨的東西」對不上的時候。
VERIFY_AC="$(cd "$SCRIPTS/../../verify-ac/scripts" && pwd)"

RECORD="$REPO_PATH/$ISSUE_DIR/.spine/delivery.json"
[[ -f "$RECORD" ]] || die "POLARIS_SPINE_RELEASE_NO_RECORD" \
  "$ISSUE_DIR has no delivery record; the second gate has not handed anything over." \
  "Run verify-ac, then: bash .claude/skills/verify-ac/scripts/record-delivery-intent.sh --issue $ISSUE_DIR ..."

# Description: echo one field from the delivery record.
# Args: $1 = field name
record_field() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' \
    "$RECORD" "$1"
}

# Description: 待處理的 changeset 份數——版號要壓多少的唯一宣告源。
#   交付紀錄裡沒有這件事，而且刻意沒有：那份紀錄是可攜層寫的，而版號是這條釋出尾段
#   自己的模型（DP-467 H-P3）。這裡直接數 release-version.sh 等一下真的會讀的那些檔案，
#   中間不經過任何人轉述。
# Returns: 一個非負整數印到 stdout。
pending_changesets() {
  local dir="$REPO_PATH/.changeset"
  [[ -d "$dir" ]] || { echo 0; return; }
  find "$dir" -maxdepth 1 -name '*.md' ! -name 'README.md' -type f | wc -l | tr -d ' '
}

DESTINATION="$(record_field destination)"
SUMMARY="$(record_field summary)"
RECORDED_HEAD="$(record_field head_sha)"
JUDGED_BY="$(record_field judged_by)"

case "$DESTINATION" in
  workspace|template) ;;
  *) die "POLARIS_SPINE_RELEASE_BAD_DESTINATION" \
       "delivery record declares destination='${DESTINATION:-<empty>}'; expected workspace or template" ;;
esac

BRANCH="$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git -C "$REPO_PATH" rev-parse HEAD)"

# 壓版那一步碰得到的路徑，唯一的一份。重釘時要交出去的 `--delta-allows`、以及判斷「HEAD
# 是不是一個壓版 commit」時要比對的清單，都從這裡展開——抄成兩份的話，哪天 release-version.sh
# 開始寫別的檔案，其中一份會先鬆掉而沒有人看得見。
VERSION_STEP_PATHS=(VERSION CHANGELOG.md package.json .changeset)

RECORD_STALE_REASON=""

# Description: HEAD 是不是「剛好坐在被判定的 head 上、而且只碰了壓版那幾條路徑」的那一個 commit。
# Returns: 0 是，非 0 不是——不是的時候 RECORD_STALE_REASON 說出是哪一項不成立。
# Why: 交付紀錄釘的不是 HEAD 有兩種原因，而它們要的下一步相反——上一趟自己壓的版號
#   commit（這支腳本證明得了），或者有人塞了沒被判定看過的改動（照舊拒絕）。舊的那一版
#   把兩者收斂成同一種拒絕，於是「壓完版之後被切斷」對那張單永遠啟動不了（DP-501）。
version_commit_on_recorded_head() {
  RECORD_STALE_REASON=""
  local parent touched path allowed matched
  parent="$(git -C "$REPO_PATH" rev-parse --verify --quiet 'HEAD^' 2>/dev/null || true)"
  if [[ -z "$parent" ]]; then
    RECORD_STALE_REASON="HEAD 沒有 parent，說不出它是不是坐在被判定的那個 commit 上"
    return 1
  fi
  if [[ "$parent" != "$RECORDED_HEAD" ]]; then
    RECORD_STALE_REASON="HEAD 的 parent 是 ${parent:0:12}，不是紀錄釘的 ${RECORDED_HEAD:0:12}——中間不只一個 commit"
    return 1
  fi
  touched="$(git -C "$REPO_PATH" diff --name-only "$RECORDED_HEAD" HEAD 2>/dev/null || true)"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    matched=0
    for allowed in "${VERSION_STEP_PATHS[@]}"; do
      if [[ "$path" == "$allowed" || "$path" == "$allowed"/* ]]; then matched=1; break; fi
    done
    if [[ "$matched" -eq 0 ]]; then
      RECORD_STALE_REASON="那個 commit 碰到了壓版步驟碰不到的檔案：$path"
      return 1
    fi
  done <<< "$touched"
  return 0
}

# Description: 把交付紀錄重釘到壓版之後的那個 head，並讓紀錄那一支去 git 驗這段差異。
# Args: $1 = 要釘上去的 head。
# Side effects: 覆寫 {issue}/.spine/delivery.json；差異碰到指名以外的路徑時它自己會拒絕。
repin_across_version_commit() {
  local head="$1" flags=() path
  for path in "${VERSION_STEP_PATHS[@]}"; do flags+=(--delta-allows "$path"); done
  bash "$VERIFY_AC/record-delivery-intent.sh" --issue "$ISSUE_ABS" \
    --summary "$SUMMARY" --head "$head" "${flags[@]}" >&2
}

# Description: 逐項問每一個系統「這一趟做到哪裡了」，印成一張表。只讀。
# Side effects: 無。不 fetch（那會寫 refs）、不 commit、不 push、不建立任何檔案。
# Why: 被中斷的尾段留下一半送出去的狀態，而「走到第幾步」以前沒有任何指令回答得出來——
#   2026-08-10 那一次是人拿 git ls-remote、gh release list、template checkout 的 status
#   一項一項反推的，而反推的人漏看哪一項，沒有任何東西說得出來（DP-501）。
#
#   每一格問的都是**真的擁有那件事的那個系統**，不是任何一份本機的帳。一份進度檔會與
#   現實不一致，而不一致的那一刻正好是有人被中斷、最需要一句真話的時候。
# Description: 印一列「這一步做到哪」。
# Args: $1 = 步驟名，$2 = 狀態，$3 = 細節（可省）。
# 不排欄位：printf 的 %-Ns 數的是位元組，而中文標籤一個字三個位元組——用它對齊，這張表
# 在有中文的時候永遠是歪的，而歪掉的表比沒有表更難讀。
say() { printf '   %s：%s%s\n' "$1" "$2" "${3:+ — $3}" >&2; }
status_report() {
  step "走到哪了"

  # 1. 交付紀錄釘的是不是 HEAD
  if [[ "${RECORDED_HEAD}" == "${HEAD_SHA}" ]]; then
    say 交付紀錄 對得上 "釘在 ${HEAD_SHA:0:12}"
  elif version_commit_on_recorded_head; then
    say 交付紀錄 待重釘 "釘在 ${RECORDED_HEAD:0:12}，而 HEAD 是它上面的壓版 commit"
  else
    say 交付紀錄 對不上 "${RECORD_STALE_REASON}"
  fi

  # 2. 版號
  local pending version
  pending="$(pending_changesets)"
  version="$(cat "$REPO_PATH/VERSION" 2>/dev/null || echo unknown)"
  if [[ "${DESTINATION}" != "template" ]]; then
    # 這條路徑不壓版，所以它留下來的 changeset 沒有人會消化——它會躺在 .changeset/ 裡，
    # 等下一張 template-bound 的單釋出時被壓進 CHANGELOG.md。那份 CHANGELOG 會同步到
    # 公開的 template repo，於是它宣告了一件從來沒有出去的事，而紅的是別人的 commit。
    # 說出來就好，不擋：一份 changeset 到底該不該留，是人的判斷。
    if [[ "${pending}" == "0" ]]; then
      say 版號 不適用 "destination=${DESTINATION}，這條路徑不壓版；沒有待處理的 changeset"
    else
      say 版號 不適用 "destination=${DESTINATION}，這條路徑不壓版；但 .changeset/ 裡有 ${pending} 份待處理，它們會被下一次 template 的釋出壓進 CHANGELOG.md"
    fi
  elif [[ "${pending}" == "0" ]]; then
    say 版號 壓過了 "VERSION=${version}，沒有待處理的 changeset"
  else
    say 版號 還沒壓 "VERSION=${version}，$pending 份 changeset 待處理"
  fi

  # 3. 這條分支推出去了沒
  local remote_branch
  remote_branch="$(git -C "${REPO_PATH}" ls-remote origin "refs/heads/${BRANCH}" 2>/dev/null | awk '{print $1}')"
  if [[ -z "${remote_branch}" ]]; then
    say 推分支 沒有 "origin 上沒有 ${BRANCH}（可能是收尾時刪掉的）"
  elif [[ "${remote_branch}" == "${HEAD_SHA}" ]]; then
    say 推分支 推過了 "origin/$BRANCH = ${HEAD_SHA:0:12}"
  else
    say 推分支 落後 "origin/$BRANCH = ${remote_branch:0:12}，本機是 ${HEAD_SHA:0:12}"
  fi

  # 4. 促進 main——問 origin 現在的 main 是哪一個 commit，再問它含不含要交付的那個
  local main_sha
  main_sha="$(git -C "${REPO_PATH}" ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1}')"
  if [[ -z "${main_sha}" ]]; then
    say 促進main 問不到 "origin 說不出 refs/heads/main"
  elif ! git -C "${REPO_PATH}" cat-file -e "${main_sha}^{commit}" 2>/dev/null; then
    say 促進main 問不到 "origin/main 是 ${main_sha:0:12}，本機物件庫沒有它——沒有 fetch 就答不了"
  elif git -C "${REPO_PATH}" merge-base --is-ancestor "${RECORDED_HEAD}" "${main_sha}" 2>/dev/null; then
    say 促進main 併了 "${RECORDED_HEAD:0:12} 在 origin/main（${main_sha:0:12}）裡"
  else
    say 促進main 還沒 "${RECORDED_HEAD:0:12} 不在 origin/main（${main_sha:0:12}）裡"
  fi

  # 5. template——問那一支自己，template 在哪、什麼算同步完了是它的知識
  if [[ "${DESTINATION}" != "template" ]]; then
    say 同步template 不適用 "destination=${DESTINATION}"
  else
    say 同步template "$(bash "$SCRIPTS/sync-to-polaris.sh" --status 2>/dev/null || echo '問不到')"
  fi

  # 6/7. tag 與 GitHub release——兩件事，各問各的
  local tag repo
  tag="v${version}"
  repo="$(resolve_workspace_repo)"
  if [[ "${DESTINATION}" != "template" ]]; then
    say tag 不適用 "destination=${DESTINATION}"
    say release 不適用 "destination=${DESTINATION}"
  else
    if [[ -n "$(origin_tag_sha "${tag}")" ]]; then
      say tag 推過了 "$tag 在 origin 上"
    else
      say tag 還沒 "origin 上沒有 ${tag}"
    fi
    if [[ -z "${repo}" ]]; then
      say release 問不到 "gh 說不出這個 repo 在 GitHub 上叫什麼"
    elif release_exists "${tag}" "${repo}"; then
      say release 建過了 "$repo 有 $tag 的 release"
    else
      say release 還沒 "$repo 沒有 $tag 的 release"
    fi
  fi

  # 8. 這張單自己的釋出紀錄（本機檔案，問的就是本機檔案）
  if [[ -f "$REPO_PATH/$ISSUE_DIR/.spine/release.json" ]]; then
    say 釋出紀錄 寫了 "$ISSUE_DIR/.spine/release.json"
  else
    say 釋出紀錄 還沒 "$ISSUE_DIR/.spine/release.json 不在"
  fi

  # 9. 本機收尾
  local local_main
  local_main="$(git -C "${REPO_PATH}" rev-parse --verify --quiet main 2>/dev/null || true)"
  if [[ -z "${main_sha}" ]]; then
    say 本機收尾 問不到 "不知道 origin/main 是哪一個，比不了"
  elif [[ "${local_main}" == "${main_sha}" ]]; then
    say 本機收尾 做了 "本機 main = origin/main"
  else
    say 本機收尾 還沒 "本機 main = ${local_main:0:12}，origin/main = ${main_sha:0:12}"
  fi

  step "只讀"
  note "什麼都沒有被寫、被推、被建立。"
}

if [[ "$PROBE_RECORD_STATE" -eq 1 ]]; then
  # 只讀：交付紀錄釘的與 HEAD 的關係。真的那道判斷讀的是同一個函式。
  if [[ "$RECORDED_HEAD" == "$HEAD_SHA" ]]; then
    echo "current"
  elif version_commit_on_recorded_head; then
    echo "resumable-version-commit"
  else
    echo "stale: $RECORD_STALE_REASON"
  fi
  exit 0
fi

step "delivery record"
note "source        $ISSUE_DIR"
note "destination   $DESTINATION"
note "judged by     ${JUDGED_BY:-unknown}"
note "recorded head ${RECORDED_HEAD:0:12}"
note "current head  ${HEAD_SHA:0:12}"
note "branch        $BRANCH"

if [[ "$STATUS" -eq 1 ]]; then
  status_report
  exit 0
fi

# The fence and the record must both still hold, checked here rather than trusted
# from whenever verify-ac ran.
if ! bash "$VERIFY_AC/frozen-assertion-fence.sh" verify "$REPO_PATH/$ISSUE_DIR/index.md" >/dev/null 2>&1; then
  die "POLARIS_SPINE_RELEASE_FENCE_UNVERIFIED" \
    "$ISSUE_DIR/index.md no longer matches what was signed; refusing to ship." \
    "  bash .claude/skills/verify-ac/scripts/frozen-assertion-fence.sh verify $ISSUE_DIR/index.md"
fi
# 這裡知道自己在釋出哪一張單（--issue 是必填），所以直接說。讓閘自己去掃全部紀錄、
# 再判斷哪些是這個 repo 的事，是別張單的紀錄擋住這次釋出的唯一途徑（DP-482）。
RESUMED_VERSION_COMMIT=0
if ! bash "$SCRIPTS/gate-spine-delivery.sh" --repo "$REPO_PATH" --issue "$ISSUE_DIR" >/dev/null 2>&1; then
  # 兩種原因，下一步相反。見 version_commit_on_recorded_head 的檔頭。
  if version_commit_on_recorded_head; then
    RESUMED_VERSION_COMMIT=1
    note "紀錄釘的是上一趟壓版之前的 head，而 HEAD 就是那個壓版 commit——這一趟會重釘它"
  else
    die "POLARIS_SPINE_RELEASE_RECORD_STALE" \
      "交付紀錄釘的 commit 不是 HEAD，而 HEAD 不是一個壓版 commit：" \
      "  $RECORD_STALE_REASON" \
      "要嘛把那些 commit 也送審，要嘛回到被判定的那個狀態。不要重寫紀錄去遷就 HEAD。"
  fi
fi
# 宣告 workspace 就是「這批東西不會出去」。這一步在同步之前跑，因為同步是不可逆的那一刻，
# 而那個宣告在 2026-08-03 到 2026-08-09 之間沒有任何東西在驗。
destination_check="$(bash "$SCRIPTS/gate-source-destination.sh" \
  --repo "$REPO_PATH" --issue "$ISSUE_DIR" --head "$HEAD_SHA" 2>&1)" || {
  die "POLARIS_SPINE_RELEASE_DESTINATION_ESCAPE" "$destination_check"
}
note "destination honoured"

# 全套 selftest 只在這裡跑。commit 那一站只跑當次動到的 skill，pre-push 一支都不跑（87.7
# 秒掛在每次推送上會被關掉）——所以「沒動到的那幾支還是綠的嗎」這句話，全 repo 只有這裡
# 在問。v4.17.0 帶著一支紅的 selftest 出去，就是因為當時沒有任何地方問這句話：唯一會問的
# .github/workflows/ci.yml 從來沒有被觸發過一次。
selftest_report="$(bash "$SCRIPTS/run-selftests.sh" --repo "$REPO_PATH" --all 2>&1)" || {
  die "POLARIS_SPINE_RELEASE_SELFTESTS_RED" "$selftest_report"
}
note "selftests green (${selftest_report##*，})"

note "fence verified, record current"

if [[ "$EXECUTE" -ne 1 ]]; then
  step "preview only"
  note "would promote $BRANCH onto main"
  if [[ "$DESTINATION" == "template" ]]; then
    note "would compress version (from $(pending_changesets) pending changeset(s)), sync to template, tag and release"
  else
    note "workspace-bound: no version, no template sync, no tag"
  fi
  note "would then land locally: main fast-forwarded, hooks reinstalled, merged branch deleted"
  note "re-run with --execute to do it"
  exit 0
fi

# ── version ───────────────────────────────────────────────────────────────────
# Workspace-bound work deliberately skips this: CHANGELOG.md syncs outward, so an
# entry for work that never leaves would announce something nobody can see.
if [[ "$DESTINATION" == "template" ]]; then
  # 上一趟壓完版就被切斷的話，重釘是這一趟第一件要做的事——它排在壓版之後的那一版
  # 走不到這裡，因為前面那道拒絕先死了（DP-501）。
  if [[ "$RESUMED_VERSION_COMMIT" -eq 1 ]]; then
    step "re-pin"
    repin_across_version_commit "$HEAD_SHA"
    note "交付紀錄重釘到 ${HEAD_SHA:0:12}"
  fi

  step "version"
  before="$(cat "$REPO_PATH/VERSION" 2>/dev/null || echo unknown)"
  # 份數要在這裡數：changeset CLI 會把用掉的那些刪掉，壓完再數永遠是 0。
  pending="$(pending_changesets)"
  bash "$SCRIPTS/release-version.sh" --repo "$REPO_PATH" >&2
  after="$(cat "$REPO_PATH/VERSION" 2>/dev/null || echo unknown)"

  if [[ "$before" != "$after" ]]; then
    note "$before -> $after"
    git -C "$REPO_PATH" add -A
    git -C "$REPO_PATH" commit -q -m "chore(release): compress $after" \
      -m "${SUMMARY:-spine release}"

    # Re-pin, but only across the commit just made. Anything else means work
    # arrived that the second gate never saw, and shipping it would make the
    # record a formality.
    new_head="$(git -C "$REPO_PATH" rev-parse HEAD)"
    parent="$(git -C "$REPO_PATH" rev-parse HEAD^)"
    [[ "$parent" == "$HEAD_SHA" ]] || die "POLARIS_SPINE_RELEASE_UNEXPECTED_DELTA" \
      "the version commit is not sitting directly on the judged head; refusing to re-pin."
    # 壓版那個 commit 是這一步自己前一秒造出來的——判定那一站不可能量在它上面，所以
    # 這裡指名它動得到的那幾個路徑，讓紀錄那一支去 git 驗這句話。碰到指名以外的任何
    # 東西就照舊拒絕：那代表壓版那一步順手改了別的，而那些改動沒有被判定看過。
    #
    # 為什麼這份清單住在這裡：可攜層不認得「版號」也不該認得（見 record-delivery-intent.sh
    # 檔頭）。這是釋出尾段自己的詞彙，而 release-version.sh 就在隔壁——哪天它開始寫別的
    # 檔案，這裡會紅，這正是要的。清單本身在 VERSION_STEP_PATHS，只有一份。
    repin_across_version_commit "$new_head"
    HEAD_SHA="$new_head"
  fi

  # 宣告與實際對不對得起來，由一支獨立的判斷回答。內嵌在這裡的話它只會在 execute 模式
  # 被走到，而那條路要碰 remote 與 template checkout——一個只能在不可重播的路徑上被驗證
  # 的判斷，等於沒有被驗證。DP-464 出貨時它就是那樣錯的。
  bash "$SCRIPTS/assert-version-bump-applied.sh" \
    --pending "$pending" --before "$before" --after "$after" >&2
fi

step "push"
git -C "$REPO_PATH" push origin "$BRANCH" >&2

# ── promotion ─────────────────────────────────────────────────────────────────
step "promote main"
workspace_repo="$(resolve_workspace_repo)"
[[ -n "$workspace_repo" ]] || die "POLARIS_SPINE_RELEASE_NO_REPO" \
  "could not resolve the workspace repository from gh"
pr_number="$(gh pr list --repo "$workspace_repo" --head "$BRANCH" --state open \
  --json number -q '.[0].number' 2>/dev/null || true)"
if [[ -n "$pr_number" ]]; then
  note "PR #$pr_number"
  bash "$SCRIPTS/framework-release-main-promotion.sh" \
    --repo "$REPO_PATH" --workspace-repo "$workspace_repo" \
    --pr "$pr_number" --base main --head "$BRANCH" --execute >&2
else
  # 沒有 open PR 有兩種原因，而它們要的下一步完全相反：還沒開，或者已經併進去了。
  # 舊的那一版把兩者收斂成「先去開一個 PR」——照著做會開出一個空的 PR，而尾段被打斷後
  # 重跑一定走到這裡（DP-500，2026-08-10 實測）。
  git -C "$REPO_PATH" fetch --quiet origin main 2>/dev/null || true
  if branch_in_base "$BRANCH" "origin/main"; then
    note "$BRANCH 已經在 origin/main 裡了——促進上一趟就做完了，跳過這一步。"
  else
    die "POLARIS_SPINE_RELEASE_NO_PR" \
      "$BRANCH 既沒有 open PR，內容也不在 origin/main 裡；交付的意思是先開一個 PR。"
  fi
fi

# Description: leave the checkout running what was just released.
#   Promotion moves origin/main, but the local checkout stays on a branch that is
#   now merged and disposable, with local main still at the pre-release commit.
#   A later session starting from main would silently build on the old state.
#
#   The part that is easy to miss is the hooks. Their content is versioned now
#   (.claude/skills/framework-release/githooks/), so landing main is enough to
#   update what runs — but core.hooksPath is per-clone config, so a checkout that
#   has never been connected still runs nothing. install-git-hooks.sh is what
#   connects it, and it is idempotent.
#
#   Skipped entirely when the tree is dirty — landing is housekeeping and must
#   never be a reason to touch someone's uncommitted work.
land_locally() {
  step "land locally"

  if [[ -n "$(git -C "$REPO_PATH" status --porcelain)" ]]; then
    note "working tree is dirty — leaving the checkout alone."
    note "when ready: git checkout main && git merge --ff-only origin/main && bash .claude/skills/framework-release/scripts/install-git-hooks.sh"
    return 0
  fi

  git -C "$REPO_PATH" fetch --quiet origin main

  # Move the ref before checking it out, rather than checking out a possibly
  # far-behind main and fast-forwarding afterwards. Both end in the same place,
  # but this one never materialises the old tree, so nothing watching the
  # working directory sees a flicker back to the pre-release state.
  local previous_main
  previous_main="$(git -C "$REPO_PATH" rev-parse --short main 2>/dev/null || echo none)"
  git -C "$REPO_PATH" branch -f main origin/main
  git -C "$REPO_PATH" checkout --quiet main
  note "main $previous_main -> $(git -C "$REPO_PATH" rev-parse --short main)"

  # Idempotent, and the only step that actually arms a newly released gate.
  # --repo, not cwd: this ran from wherever the caller happened to stand, and a
  # shell that had wandered into issues/ is exactly how DP-500 was born.
  bash "$SCRIPTS/install-git-hooks.sh" --repo "$REPO_PATH" >/dev/null 2>&1 \
    && note "git hooks reinstalled — newly released gates are now armed" \
    || note "git hooks reinstall failed; run bash .claude/skills/framework-release/scripts/install-git-hooks.sh"

  # Only ever deletes a branch git itself proves is contained in main.
  if git -C "$REPO_PATH" merge-base --is-ancestor "$BRANCH" main 2>/dev/null; then
    git -C "$REPO_PATH" branch -q -D "$BRANCH" 2>/dev/null || true
    git -C "$REPO_PATH" push --quiet origin --delete "$BRANCH" 2>/dev/null \
      && note "deleted merged branch $BRANCH (local and remote)" \
      || note "deleted merged branch $BRANCH (local)"
  else
    note "$BRANCH is not contained in main — leaving it in place"
  fi
}

# Description: 把「這張單真的出去了」記在單自己身上。
# Args: $1 = 版本字串（workspace-bound 的沒有壓版，記的是當下的 VERSION）
#
# 為什麼不是交付紀錄：`delivery.json` 是第二個閘在釋出**之前**寫的交付意向，它的 `judged_at`
# 是判定日。在這一行執行之前，「這張單出去了沒有、哪一天出去的」在本機沒有任何地方回答得
# 出來——DP-481 要把收斂完的單按釋出日分開放，才發現這個訊號從來不存在，而拿判定日冒充
# 釋出日會把一張還沒上線的單放進 released/。
write_release_record() {
  local version="$1" record="$REPO_PATH/$ISSUE_DIR/.spine/release.json" today
  today="$(date -u +%Y-%m-%d)"
  mkdir -p "$(dirname "$record")"
  python3 - "$record" "$version" "$DESTINATION" "$HEAD_SHA" <<'RELEASE_RECORD'
import json
import sys
from datetime import datetime, timezone

record, version, destination, head = sys.argv[1:5]
now = datetime.now(timezone.utc)
with open(record, "w", encoding="utf-8") as handle:
    json.dump({
        "schema_version": 1,
        "producer": "spine-release.sh",
        "released_on": now.strftime("%Y-%m-%d"),
        "released_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "version": version,
        "destination": destination,
        "head_sha": head,
    }, handle, ensure_ascii=False, indent=1)
    handle.write("\n")
RELEASE_RECORD
  # 大括號不是風格：全形括號的位元組會被 bash 收進變數名，`set -u` 之下整個尾段就死在
  # 這一行——而它跑在 tag 與 release 都送出去之後，壞掉的樣子是「釋出成功但沒收尾」。
  note "釋出紀錄：$ISSUE_DIR/.spine/release.json（released_on=${today} version=${version}）"
  reproject_position
}

# Description: 剛寫下的釋出紀錄改變了這張單的狀態，位置要跟著重算。
#
# 為什麼這一行非有不可：位置是狀態的投影，而在這之前這一段從來沒有做過投影。398 張躺在
# `released/` 的單位置是對的，但它們是靠**後來某張不相干的單跑了 `record`**（那一支才會叫
# 重算）才被順手擺正的——所以永遠是最後釋出的那一張錯著，直到下一個人開下一張單。DP-507
# 就是那張。**一個靠不相干的未來工作才會正確的帳，在最後一筆上永遠是錯的。**
#
# 重算失敗不讓釋出失敗：釋出已經送出去了，這一步回頭把它判成失敗只會讓紀錄與事實更遠。
# 但它必須被看見——位置與狀態對不上正是要被看見的那件事。
reproject_position() {
  local placer="$REPO_PATH/.claude/skills/driving-work-to-done/scripts/place-issues-by-state.sh"
  local root="${ISSUE_DIR%%/*}"
  [[ -n "$root" && -d "$REPO_PATH/$root" ]] || {
    note "位置沒重算：從 $ISSUE_DIR 推不出單樹的根"; return 0; }
  [[ -f "$placer" ]] || { note "位置沒重算：找不到 $placer"; return 0; }
  # `--spine-only`：剛動過的是一張走脊椎的單，它的答案在本機。讓釋出去問別的命名空間宣告
  # 的解析器，等於每釋出一次就打幾十趟網路，而且那些系統掛掉的時候釋出會被拖著失敗。
  bash "$placer" --issues "$REPO_PATH/$root" --execute --spine-only >/dev/null \
    && note "位置重算完了" \
    || note "位置沒重算完，可能與狀態對不上：$placer --issues $REPO_PATH/$root"
}

if [[ "$DESTINATION" != "template" ]]; then
  write_release_record "$(cat "$REPO_PATH/VERSION" 2>/dev/null || echo unknown)"
  land_locally
  step "done"
  note "workspace-bound source promoted; nothing syncs outward."
  exit 0
fi

# ── template ──────────────────────────────────────────────────────────────────
step "sync to template"
bash "$SCRIPTS/sync-to-polaris.sh" --push >&2

step "tag and release"
version="$(cat "$REPO_PATH/VERSION")"
tag="v$version"
# The question is whether *this* repository has already released the version, so
# it is asked of origin. The local tag namespace cannot answer it: the template
# repository is a remote here and versions the same way, so its tags land locally
# with identical names pointing at entirely different commits. Reading local tags
# made the tail skip its own tag and still print "shipped at v3.85.1" — the
# release existed nowhere on origin (2026-08-02).
tail_plan="$(plan_tag_and_release "$tag" "$workspace_repo")"
tag_plan="$(printf '%s\n' "$tail_plan" | awk '$1 == "tag" { print $2 }')"
release_plan="$(printf '%s\n' "$tail_plan" | awk '$1 == "release" { print $2 }')"

if [[ "$tag_plan" == "skip" ]]; then
  note "$tag 已經在 origin 上——不動它"
else
  # -f because a same-named tag may already sit locally, pointing at the template
  # repository's commit; this repository's tag has to point at what shipped here.
  git -C "$REPO_PATH" tag -f -a "$tag" -m "${SUMMARY:-$tag}" >/dev/null
  git -C "$REPO_PATH" push origin "$tag" >&2
  note "pushed $tag"
fi

# release 是另一件事，所以另外問一次。上面那個判斷答的是「tag 在不在 origin 上」，而
# 推 tag 與建 release 之間有一個真實的中斷點：舊的那一版在那裡重跑會印「already on
# origin」然後一路報成 shipped，而那個 release 從來沒有存在過（DP-501）。
# 這正是這支腳本 2026-08-02 那次事故的鏡像——當時修的是「問哪一邊」，沒修「一個問題
# 答兩件事」。
if [[ "$release_plan" == "unknown" ]]; then
  die "POLARIS_SPINE_RELEASE_UNKNOWN_RELEASE_STATE" \
    "問不到 $tag 的 GitHub release 在不在，所以說不出該不該建它。" \
    "問不到不是「已經有了」——安靜跳過會讓一個從沒存在過的 release 被回報成出貨完成。"
elif [[ "$release_plan" == "skip" ]]; then
  note "$tag 的 GitHub release 已經在了——不動它"
else
  gh release create "$tag" --repo "$workspace_repo" \
    --title "$tag" --notes "${SUMMARY:-$tag}" >&2
  note "created release $tag"
fi

write_release_record "$version"
land_locally

step "done"
note "$ISSUE_DIR shipped at $tag"
