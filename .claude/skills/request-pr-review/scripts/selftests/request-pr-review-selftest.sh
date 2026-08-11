#!/usr/bin/env bash
# request-pr-review-selftest.sh — 一條斷言一個 case，離線可重跑。
#
# Usage: request-pr-review-selftest.sh --assertion <ID>
#        request-pr-review-selftest.sh --list
#
# Exit: 0 這條成立 / 1 這條不成立 / 2 量不到（前置條件沒到，不得被讀成成立）
#
# 每個 case 至少印一行 `MEASURED …`，說出它**真的量到了什麼**——一個只回 exit 0 的 case
# 跟一個什麼都沒跑的 case 在輸出上長得一樣，而負向的量測天生會把「我沒看到」讀成
# 「它沒發生」。掃不到檔案、樣本數 0、正則對上 0 次，一律走 exit 2，不走 exit 0。
#
# 會打 GitHub 的 case 一律走同目錄的 fixtures/gh（假的），理由寫在那支腳本的檔頭：真的
# GitHub 不會在你需要的時候壞掉，而且它的回答會變——DP-511 量兩趟之間就有一個 PENDING
# 的 check 變綠了。

set -uo pipefail

SELFTEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELFTEST_DIR/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
FIXTURES="$SELFTEST_DIR/fixtures"

# case 標籤共用一個分支時長成 `B-P2|B-N1)`，只認 `ID)` 的正則會讓那兩條從清單裡靜靜
# 消失——而一條沒被列出來的斷言，跟沒有那條斷言在輸出上長得一樣。
list_assertions() {
  grep -oE '^  [A-C]-[PN][0-9][A-C|PN0-9-]*\)' "$1" | tr -d ' )' | tr '|' '\n' | grep -E '^[A-C]-[PN][0-9]$'
}

ASSERTION=""
case "${1:-}" in
  "")
    # 不帶參數＝跑全部。selftest harness 是這樣叫它的，而一支只認得 --assertion 的腳本
    # 在那裡會回 2，看起來就像整支壞掉。
    rc=0; failed=""; unmeasured=""
    for one in $(list_assertions "$0"); do
      out="$(bash "$0" --assertion "$one" 2>&1)"; case "$?" in
        0) printf '  ✅ %s\n' "$one" ;;
        2) printf '  ❔ %s — %s\n' "$one" "$(printf '%s' "$out" | tail -1)"; unmeasured="${unmeasured}${one} " ;;
        *) printf '  ❌ %s — %s\n' "$one" "$(printf '%s' "$out" | tail -1)"; failed="${failed}${one} "; rc=1 ;;
      esac
    done
    # 量不到要說出來而且不能靜悄悄：它不是「過」的溫和版本。但它也不是紅——這支 skill 是
    # 可攜的，某些條在沒有任何宣告的環境裡本來就沒有樣本。
    [[ -z "$unmeasured" ]] || echo "量不到（不是過）：${unmeasured}" >&2
    [[ -z "$failed" ]] || echo "沒過：${failed}" >&2
    exit "$rc" ;;
  --list) list_assertions "$0"; exit 0 ;;
  --assertion) ASSERTION="${2:-}" ;;
  *) echo "用法：$0 [--assertion <ID>] [--list]" >&2; exit 2 ;;
esac
[[ -n "$ASSERTION" ]] || { echo "要 --assertion" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -f -r "$WORK"' EXIT

measured() { echo "MEASURED $*"; }
fail() { echo "FAILED $*" >&2; exit 1; }
unmeasurable() { echo "UNMEASURABLE $*" >&2; exit 2; }

for tool in jq python3; do
  command -v "$tool" >/dev/null 2>&1 || unmeasurable "沒有 ${tool}，這一條量不到"
done

# ---------------------------------------------------------------- 共用的跑法

# 跑 fetch 那一段（假 gh、假宣告），stdout 進 $1、stderr 進 $2。
run_fetch() {
  PATH="${FIXTURES}:${PATH}" \
  POLARIS_SELFTEST_SCENARIO="${3:-happy}" \
    bash "$SCRIPTS_DIR/fetch-user-open-prs.sh" --author selftest-user \
      --skills "$WORK/skills" >"$1" 2>"$2"
}

# 建一棵只有一行宣告的假 skill 樹：C 段的斷言講的是「宣告驅動」，拿某一家公司真的那份
# 宣告來量，等於同時在量那一層，而那不是這裡要判的東西。
make_skills_tree() {
  local orgs="${*:-acme}"
  mkdir -p "$WORK/skills/fake-owner"
  cat > "$WORK/skills/fake-owner/answer.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
mode="${1:-}"; shift || true
repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in --repo) repo="${2:-}"; shift 2 ;; *) shift ;; esac
done
case "$mode" in
  notify)
    [[ "$repo" == "widget" ]] || { echo "[fake] 「${repo}」沒有人說要通知誰。" >&2; exit 3; }
    echo "somewhere_id	FAKE-DESTINATION" ;;
  ticket)
    while IFS=$'\t' read -r r n t b; do
      [[ -n "${r:-}" ]] || continue
      key="$(printf '%s' "${t}" | sed -n 's/.*\(ACME-[0-9][0-9]*\).*/\1/p')"
      [[ -n "$key" ]] || continue
      echo "${r}	${n}	${key}	https://tickets.invalid/${key}"
    done ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$WORK/skills/fake-owner/answer.sh"
  {
    printf '# fake\n\n'
    for one in $orgs; do
      printf '<!-- FAKE-PR-CONTEXT-%s: bash %s/skills/fake-owner/answer.sh -->\n' "$one" "$WORK"
    done
  } > "$WORK/skills/fake-owner/SKILL.md"
}

# 整條 pipeline（五段），輸出進 $1。
run_pipeline() {
  local scenario="${2:-happy}"
  PATH="${FIXTURES}:${PATH}" POLARIS_SELFTEST_SCENARIO="$scenario" bash -c '
    set -o pipefail
    "$1/fetch-user-open-prs.sh" --author selftest-user --skills "$2/skills" \
      | "$1/check-pr-approval-status.sh" --threshold 2 \
      | "$1/fetch-pr-review-comments.sh" --author selftest-user \
      | "$1/check-pr-ci-status.sh" \
      | "$1/attach-pr-ticket.sh" --skills "$2/skills"
  ' _ "$SCRIPTS_DIR" "$WORK" >"$1" 2>"$WORK/pipeline.err"
}

# 掃這支 skill 底下的散文與腳本；掃到 0 個檔就是量不到，不是乾淨。
skill_files() {
  find "$SKILL_DIR" -type f \( -name '*.sh' -o -name '*.md' -o -name '*.py' \) \
    -not -path "*/selftests/*"
}

# ---------------------------------------------------------------- 逐條

case "$ASSERTION" in

  A-P1)
    make_skills_tree
    run_fetch "$WORK/out.json" "$WORK/err.txt" || fail "fetch 非 0"
    n="$(jq 'length' "$WORK/out.json")"
    [[ "$n" -gt 0 ]] || unmeasurable "一個 PR 都沒有，這一條沒有樣本"
    missing="$(jq -r '[.[] | select((.repo|length)==0 or (.title|length)==0 or (.url|length)==0)] | length' "$WORK/out.json")"
    [[ "$missing" -eq 0 ]] || fail "有 ${missing} 筆缺 repo/title/url"
    # 環境變數一個都沒設也要成立：ORG 之類的東西不得是前置條件。
    grep -q 'ORG' "$WORK/err.txt" && fail "stderr 提到 ORG，可能還在要環境變數"
    measured "${n} 個 PR，每一筆都有 repo/title/url；沒有設任何環境變數"
    ;;

  A-P2)
    make_skills_tree
    run_pipeline "$WORK/out.json" || fail "pipeline 非 0"
    n="$(jq 'length' "$WORK/out.json")"
    [[ "$n" -gt 0 ]] || unmeasurable "沒有樣本"
    bad="$(jq -r '[.[] | select(
        (has("valid_approvals")|not) or (has("threshold")|not) or (has("has_stale")|not)
        or (has("requested_reviewers")|not) or (has("unaddressed_comments")|not)
        or (.ci.state == null))] | length' "$WORK/out.json")"
    [[ "$bad" -eq 0 ]] || fail "有 ${bad} 筆缺 review 狀態欄位"
    # 四類狀態都要真的走到，不是欄位存在就算。
    jq -e '[.[] | select(.has_stale)] | length > 0' "$WORK/out.json" >/dev/null || fail "沒有一筆 stale，這一條沒被走到"
    jq -e '[.[] | select((.requested_reviewers|length) > 0)] | length > 0' "$WORK/out.json" >/dev/null || fail "沒有被指名的 reviewer"
    jq -e '[.[] | select(.unaddressed_comments > 0)] | length > 0' "$WORK/out.json" >/dev/null || fail "沒有未回覆意見"
    states="$(jq -r '[.[].ci.state] | unique | join(",")' "$WORK/out.json")"
    measured "${n} 筆全帶 review 狀態；stale/被指名/未回覆各至少一筆；CI 狀態出現：${states}"
    ;;

  A-P3)
    make_skills_tree
    run_fetch "$WORK/out.json" "$WORK/err.txt" || fail "fetch 非 0"
    grep -qE '共 [0-9]+ 個 PR' "$WORK/err.txt" || fail "沒有說出總數"
    grep -qE '📦 [^：]+：[0-9]+ 個' "$WORK/err.txt" || fail "沒有說出分布"
    measured "總數與逐 org 分布都印出來了：$(grep -oE '共 [0-9]+ 個 PR' "$WORK/err.txt" | head -1)"
    ;;

  A-P4)
    # ghost 也要被宣告——沒宣告的 org 根本不會被查，那樣測到的是「沒查」不是「查不到」。
    make_skills_tree acme ghost
    # 一個整個問不到的 org + 一個 PR endpoint 壞掉的 repo。
    run_fetch "$WORK/out.json" "$WORK/err.txt" unreachable || fail "整批被一個問不到的東西吃掉了"
    grep -q 'ghost' "$WORK/err.txt" || fail "問不到的 org 沒有被指名"
    n="$(jq 'length' "$WORK/out.json")"
    [[ "$n" -gt 0 ]] || fail "其餘沒有照常回來"
    jq -e '[.[] | select(.branch_status == "unreachable")] | length > 0' "$WORK/out.json" >/dev/null \
      || fail "問不到的 base/head 沒有被標成 unreachable"
    # CI 那一段單獨餵紅：問不到不得變成 PASS 或 NONE。
    ci="$(printf '[{"org":"acme","repo":"nope","number":9}]' \
      | PATH="${FIXTURES}:${PATH}" bash "$SCRIPTS_DIR/check-pr-ci-status.sh" 2>/dev/null \
      | jq -r '.[0].ci.state')"
    [[ "$ci" == "UNREACHABLE" ]] || fail "CI 問不到時回的是 ${ci}，不是 UNREACHABLE"
    measured "ghost org 被指名、其餘 ${n} 筆照常回來、壞掉的 base/head 標成 unreachable、CI 問不到回 UNREACHABLE"
    ;;

  A-N1)
    files="$(skill_files | wc -l | tr -d ' ')"
    [[ "$files" -gt 0 ]] || unmeasurable "掃不到任何檔案"
    # **禁字從宣告推導，不寫死在這裡。** 上一版把兩個公司名寫進這一行——那條檢查「不得
    # 寫死座標」的檢查自己寫死了座標，而閘抓到了。現在問的是：這棵樹上被宣告出來的 org
    # 名，有沒有任何一個出現在這支可攜 skill 的檔案裡。
    tree_root="$(cd "$SKILL_DIR/.." && pwd)"
    declared="$(bash "$SCRIPTS_DIR/resolve-pr-context.sh" orgs --skills "$tree_root" 2>/dev/null || true)"
    [[ -n "$declared" ]] || unmeasurable "這棵樹上沒有任何宣告，推不出禁字，這一條沒有樣本"
    # 禁字全部推導出來，不摻啟發式：org 名、org 的公司前綴、呼叫端給的 repo 名，以及那些
    # repo 真正解出來的目的地字串。上一版多加了一條「一長串大寫英數就算 id」，它把
    # UNREACHABLE 與 POLARIS_APPROVAL_API_ERROR 都算成寫死的座標——一條猜出來的規則會
    # 製造 80 個假紅，而假紅比沒有檢查更快被關掉。
    tokens=""
    for org in $declared; do
      tokens="${tokens} ${org} ${org%%-*}"
      for repo in ${POLARIS_PR_CONTEXT_REPOS:-}; do
        tokens="${tokens} ${repo}"
        dest="$(bash "$SCRIPTS_DIR/resolve-pr-context.sh" notify --org "$org" --repo "$repo" --skills "$tree_root" 2>/dev/null | tr '\t' ' ')"
        tokens="${tokens} ${dest}"
      done
    done
    hits=0
    for token in $tokens; do
      [[ "${#token}" -ge 4 ]] || continue
      c="$(skill_files | xargs grep -liF "$token" 2>/dev/null | wc -l | tr -d ' ')"
      if [[ "${c:-0}" -gt 0 ]]; then
        skill_files | xargs grep -liF "$token" 2>/dev/null | sed "s/^/  寫死了 ${token}：/" >&2
        hits=$((hits + c))
      fi
    done
    [[ "$hits" -eq 0 ]] || fail "有 ${hits} 處寫死的座標"
    grep -q 'PR-CONTEXT' "$SKILL_DIR/scripts/resolve-pr-context.sh" || fail "宣告機制不在"
    measured "掃過 ${files} 個檔，比對推導出來的禁字，寫死的座標 0 處"
    ;;

  A-N2)
    files="$(skill_files | grep -c '\.sh$')"
    [[ "$files" -gt 0 ]] || unmeasurable "掃不到腳本"
    # 「我現在站在哪」長這樣：問 git remote、問當前 repo、拿 cwd 當 repo 名。
    hits="$(skill_files | grep '\.sh$' | xargs grep -nE 'git remote|gh repo view|basename "?\$\(pwd\)' 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$hits" -eq 0 ]] || { skill_files | grep '\.sh$' | xargs grep -nE 'git remote|gh repo view|basename "?\$\(pwd\)' 2>/dev/null >&2; fail "有 ${hits} 處從當下位置推座標"; }
    grep -q 'resolve-pr-context.sh' "$SKILL_DIR/scripts/fetch-user-open-prs.sh" || fail "org 不是從宣告來的"
    measured "掃過 ${files} 支腳本，從當下位置推座標 0 處；org 來自 resolve-pr-context.sh"
    ;;

  B-P1)
    make_skills_tree
    run_pipeline "$WORK/out.json" || fail "pipeline 非 0"
    n="$(jq 'length' "$WORK/out.json")"
    [[ "$n" -gt 0 ]] || unmeasurable "沒有樣本"
    # 「當場決定」需要的東西：它是什麼、屬於哪張單、誰看過、卡在哪。
    bad="$(jq -r '[.[] | select(
        (has("url")|not) or (has("ticket")|not) or (has("needs_review")|not)
        or (has("unaddressed_comments")|not) or (.ci.state == null))] | length' "$WORK/out.json")"
    [[ "$bad" -eq 0 ]] || fail "有 ${bad} 筆缺決策需要的欄位"
    jq -e '[.[] | select(.ticket != null)] | length > 0' "$WORK/out.json" >/dev/null || fail "沒有一筆帶得出單號"
    measured "${n} 筆都帶著 url/單/是否需要 review/未回覆數/CI；帶得出單號的：$(jq '[.[]|select(.ticket!=null)]|length' "$WORK/out.json")"
    ;;

  B-P2|B-N1)
    # 量的是**這條流程**，不是這個目錄裡存不存在有寫入能力的程式碼。B-P2 說的是「沒有人
    # 點頭之前不寫東西」——那是行為。這支 skill 目前還帶著幾支不屬於這三步的殘留腳本，
    # 其中有具備寫入能力的；它們是另一件事（見判斷報告），不由這一條判。
    flow_scripts="$(grep -oE 'scripts/[a-z0-9-]+\.sh' "$SKILL_DIR/SKILL.md" | sort -u \
      | sed "s|^|${SKILL_DIR}/|")"
    flow_scripts="${flow_scripts}
${SKILL_DIR}/scripts/lib/github-rest.sh
${SKILL_DIR}/scripts/lib/pr-approval-count.sh
${SKILL_DIR}/scripts/lib/approval-staleness.sh"
    n_flow=0
    for f in $flow_scripts; do [[ -f "$f" ]] && n_flow=$((n_flow + 1)); done
    [[ "$n_flow" -gt 0 ]] || unmeasurable "從 SKILL.md 解不出這條流程跑哪些腳本"
    if [[ "$ASSERTION" == "B-P2" ]]; then
      # 呼叫，不是提及：行首或管線/分號之後才算，註解裡的用法說明不算。
      pattern='(^|[;|&(]) *(gh pr (edit|comment|merge|close|review)|polaris_pr_create_rest)'
      what="會寫東西出去的呼叫"
    else
      pattern='(^|[;|&(]) *git +(push|rebase|checkout|switch|stash|reset|merge|commit|cherry-pick)'
      what="會動 git 狀態的命令"
    fi
    hits=0
    for f in $flow_scripts; do
      [[ -f "$f" ]] || continue
      c="$(grep -cE "$pattern" "$f" 2>/dev/null || true)"
      if [[ "${c:-0}" -gt 0 ]]; then grep -nE "$pattern" "$f" | sed "s|^|${f}:|" >&2; hits=$((hits + c)); fi
    done
    [[ "$hits" -eq 0 ]] || fail "這條流程有 ${hits} 處${what}"
    measured "這條流程的 ${n_flow} 支腳本（含 lib），${what} 0 處"
    ;;

  C-P1)
    make_skills_tree acme
    orgs="$(bash "$SCRIPTS_DIR/resolve-pr-context.sh" orgs --skills "$WORK/skills")" || fail "orgs 問不到"
    [[ "$orgs" == "acme" ]] || fail "org 不是從宣告來的（拿到「${orgs}」）"
    dest="$(bash "$SCRIPTS_DIR/resolve-pr-context.sh" notify --org acme --repo widget --skills "$WORK/skills")" \
      || fail "notify 問不到"
    printf '%s' "$dest" | grep -q 'FAKE-DESTINATION' || fail "目的地不是宣告那一層給的（拿到「${dest}」）"
    # 核心不得解讀那個答案的格式：宣告方印什麼都該原樣出來。
    measured "org 與目的地都由宣告決定，核心原樣轉交：${dest}"
    ;;

  C-P2)
    mkdir -p "$WORK/empty"
    bash "$SCRIPTS_DIR/resolve-pr-context.sh" orgs --skills "$WORK/empty" >/dev/null 2>"$WORK/e1"
    [[ "$?" -ne 0 ]] || fail "一個宣告都沒有時還是回了答案"
    grep -q 'PR-CONTEXT' "$WORK/e1" || fail "沒有說出缺什麼"
    make_skills_tree acme
    bash "$SCRIPTS_DIR/resolve-pr-context.sh" notify --org nobody --repo widget --skills "$WORK/skills" >"$WORK/o2" 2>"$WORK/e2"
    rc="$?"
    [[ "$rc" -ne 0 ]] || fail "沒有人認領的 org 還是回了目的地"
    [[ ! -s "$WORK/o2" ]] || fail "問不到卻印了東西出來：$(cat "$WORK/o2")"
    grep -q 'nobody' "$WORK/e2" || fail "沒有指名是哪個 org"
    # 認領了、但那個 repo 沒設 → 一樣不得猜。
    bash "$SCRIPTS_DIR/resolve-pr-context.sh" notify --org acme --repo gadget --skills "$WORK/skills" >"$WORK/o3" 2>/dev/null
    [[ "$?" -ne 0 && ! -s "$WORK/o3" ]] || fail "沒設定的 repo 被猜了一個目的地"
    measured "沒有宣告／沒人認領／認領了但沒設定，三種都非 0 且不印任何目的地"
    ;;

  C-N3)
    make_skills_tree acme
    run_pipeline "$WORK/out.json" || fail "pipeline 非 0"
    n="$(jq 'length' "$WORK/out.json")"
    [[ "$n" -gt 0 ]] || unmeasurable "沒有樣本"
    # gadget 沒有目的地：plan 該非 0，但前面兩步的結果必須完好。
    printf '[{"org":"acme","repo":"gadget","number":9}]' \
      | bash "$SCRIPTS_DIR/plan-pr-notify.sh" --skills "$WORK/skills" >"$WORK/plan" 2>"$WORK/planerr"
    rc="$?"
    [[ "$rc" -ne 0 ]] || fail "送不出去卻回了 0"
    grep -q 'unknown' "$WORK/plan" || fail "沒有把它標成 unknown"
    still="$(jq 'length' "$WORK/out.json")"
    [[ "$still" -eq "$n" ]] || fail "前兩步的結果被影響了"
    measured "目的地問不到時 plan 回 ${rc} 並標 unknown，query 與列表的 ${n} 筆結果完好"
    ;;

  C-N1)
    files="$(skill_files | wc -l | tr -d ' ')"
    [[ "$files" -gt 0 ]] || unmeasurable "掃不到任何檔案"
    hits="$(skill_files | xargs grep -niE 'slack|channel_id|chat\.postmessage' 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$hits" -eq 0 ]] || { skill_files | xargs grep -niE 'slack|channel_id|chat\.postmessage' 2>/dev/null >&2; fail "有 ${hits} 處提到某一種傳輸方式"; }
    measured "掃過 ${files} 個檔，Slack／channel／傳輸 API 0 處"
    ;;

  C-N2)
    tree_root="$(cd "$SKILL_DIR/.." && pwd)"
    dupes="$(python3 - "$tree_root" <<'PY'
import os, re, sys
root = sys.argv[1]
pattern = re.compile(r"<!--\s*[A-Za-z0-9_-]+-PR-CONTEXT-([A-Za-z0-9_.-]+):\s*(.+?)\s*-->")
seen, by_org = set(), {}
for dirpath, _, files in os.walk(root):
    if "SKILL.md" not in files:
        continue
    path = os.path.join(dirpath, "SKILL.md")
    real = os.path.realpath(path)
    if real in seen:
        continue
    seen.add(real)
    for org, command in pattern.findall(open(path, encoding="utf-8", errors="ignore").read()):
        by_org.setdefault(org, set()).add(command)
print(f"SCANNED {len(seen)}")
for org, commands in sorted(by_org.items()):
    print(f"ORG {org} {len(commands)}")
    if len(commands) > 1:
        print(f"DUPE {org} " + " | ".join(sorted(commands)))
PY
)"
    scanned="$(printf '%s' "$dupes" | sed -n 's/^SCANNED //p')"
    [[ "${scanned:-0}" -gt 0 ]] || unmeasurable "掃不到任何 SKILL.md"
    orgs="$(printf '%s' "$dupes" | grep -c '^ORG ')"
    [[ "$orgs" -gt 0 ]] || unmeasurable "一個宣告都沒有，這一條沒有樣本"
    if printf '%s' "$dupes" | grep -q '^DUPE '; then
      printf '%s\n' "$dupes" | grep '^DUPE ' >&2
      fail "有 org 有第二份等價的答案"
    fi
    measured "掃過 ${scanned} 份 SKILL.md、${orgs} 個 org，每個 org 只有一個來源"
    ;;

  B-P3)
    make_skills_tree acme
    run_pipeline "$WORK/all.json" || fail "pipeline 非 0"
    # 「選中」用 jq 模擬：只挑 widget #101。plan 只該出現這一個 repo，其餘一個都不動。
    jq '[.[] | select(.number == 101)]' "$WORK/all.json" > "$WORK/selected.json"
    [[ "$(jq 'length' "$WORK/selected.json")" -eq 1 ]] || unmeasurable "選出來的樣本不是 1 個"
    bash "$SCRIPTS_DIR/plan-pr-notify.sh" --skills "$WORK/skills" < "$WORK/selected.json" > "$WORK/plan" 2>/dev/null       || fail "選中的那個算不出目的地"
    rows="$(wc -l < "$WORK/plan" | tr -d ' ')"
    [[ "$rows" -eq 1 ]] || fail "選了 1 個，plan 卻出現 ${rows} 個 repo"
    cut -f1 "$WORK/plan" | grep -qx 'widget' || fail "plan 出現的不是被選中的那個"
    # 沒選中的那個完全沒被算進去。
    cut -f1 "$WORK/plan" | grep -qx 'gadget' && fail "沒選中的也被算進去了"
    measured "選 1 個 → plan 恰好 1 列且就是那一個；沒選中的沒有出現"
    ;;

  B-N2)
    doc="$SKILL_DIR/SKILL.md"
    [[ -s "$doc" ]] || unmeasurable "讀不到 SKILL.md"
    grep -q '停下來等使用者選' "$doc" || fail "沒有寫出「停下來等人選」"
    grep -q '不自動挑一批送出去' "$doc" || fail "沒有禁止自動挑一批送出去"
    grep -q '不代替使用者決定' "$doc" || fail "Hard Safety Rules 沒有這一條"
    measured "SKILL.md 三處都在：停下來等人選、不自動挑一批、不代替人決定"
    ;;

  C-P3)
    # 機械可量的那一半：這批會出現的每一個 repo 都解得到目的地。用真的宣告樹，因為這一條
    # 講的就是「那一份真的宣告」——換成假的等於量了別的東西。
    #
    # 要涵蓋哪些 repo 由呼叫端給（量測命令裡寫），不寫死在這支可攜 skill 裡：repo 名是
    # 某一家公司的座標，寫進來就是 A-N1 自己要擋的東西。沒給就是量不到，不是過。
    tree_root="$(cd "$SKILL_DIR/.." && pwd)"
    [[ -n "${POLARIS_PR_CONTEXT_REPOS:-}" ]] \
      || unmeasurable "沒有給 POLARIS_PR_CONTEXT_REPOS，不知道這批涵蓋哪些 repo"
    orgs="$(bash "$SCRIPTS_DIR/resolve-pr-context.sh" orgs --skills "$tree_root" 2>/dev/null)" \
      || unmeasurable "這棵樹上沒有任何宣告，這一條沒有樣本"
    covered=0; missing=""
    for org in $orgs; do
      for repo in ${POLARIS_PR_CONTEXT_REPOS}; do
        if bash "$SCRIPTS_DIR/resolve-pr-context.sh" notify --org "$org" --repo "$repo" --skills "$tree_root" >/dev/null 2>&1; then
          covered=$((covered + 1))
        else
          missing="${missing}${org}/${repo} "
        fi
      done
    done
    [[ "$covered" -gt 0 ]] || unmeasurable "一個 repo 都沒解到，這一條沒有樣本"
    [[ -z "$missing" ]] || fail "沒有目的地的：${missing}"
    # 另一半（真的送成功過一次）不在這支腳本的能力範圍——它要一個對外的送出動作。
    # 說出來而不是靜靜地算成過：一個宣稱自己量滿了的檢查，會讓下一個人不再看那一半。
    measured "宣告涵蓋 ${covered} 個 repo，全部解得到目的地"
    measured "DOGFOOD-ONLY「真的送成功過一次」不由這支腳本判——見判斷報告的 permalink（樣本 1）"
    ;;

  C-P4)
    doc="$SKILL_DIR/SKILL.md"
    ref="$SKILL_DIR/references/request-pr-review-reporting.md"
    [[ -s "$doc" && -s "$ref" ]] || unmeasurable "讀不到 SKILL.md 或 reporting reference"
    grep -q '送出去的是哪幾個、送到哪、成功與否' "$doc" || fail "沒有要求逐個回報"
    grep -q '送不出去要說出來' "$doc" || fail "沒有要求把送不出去的也說出來"
    grep -q '通知送到哪' "$ref" || fail "reporting 沒有要求說出送到哪"
    measured "SKILL.md 與 reporting 都要求逐個回報送了哪些、送到哪、成功與否，且送不出去也要說"
    ;;

  *)
    echo "不認得的斷言：${ASSERTION}" >&2
    exit 2
    ;;
esac
