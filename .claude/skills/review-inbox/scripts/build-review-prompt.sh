#!/usr/bin/env bash
# build-review-prompt.sh — Generate review sub-agent prompts from PR candidates JSON
#
# Input:  stdin = JSON array from check-my-review-status.sh
# Args:   --my-user <github_username>
#         --base-dir <local repo base directory>
#         --workspace <workspace root> (default: current directory)
#         --company <company key> (optional)
#         --project <project key> (optional)
#         --bundle <dispatch context bundle path> (default: skill bundle)
#         --out-dir <output directory for prompt files> (default: /tmp/review-prompts)
#         --manifest <manifest output path> (default: /tmp/review-prompt-manifest.json)
#         --show-all-checks (include PASS CI rollup in packet instructions; default failure/error only)
#         --authorized-by <人> / --authorization-quote <原話>
#                 送出授權。兩個都給，packet 才帶著「可以送出」與它的來源；缺一個就
#                 明講未授權，執行者產出 payload 但不送出。轉述不算授權——D-N1。
#
# Output: One file per PR in out-dir: review-prompt-{repo}-{number}.txt
#         （repo 裡的 `/` 在檔名上換成 `-`；repo 這個值本身不動）
#         Also writes manifest with [{file, pr_url, number, repo}]
#
# Usage:
#   cat /tmp/review-candidates.json \
#     | ./build-review-prompt.sh \
#         --my-user daniel-lee-kk \
#         --base-dir /path/to/repos \
#         --workspace /path/to/workspace \
#         --company exampleco \
#         --project exampleco-web
#
# The Strategist reads each prompt file and uses it as the Agent tool's prompt parameter.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

MY_USER=""
BASE_DIR=""
WORKSPACE="$PWD"
COMPANY=""
PROJECT=""
BUNDLE_PATH="$SCRIPT_DIR/../dispatch-context-bundle.md"
OUT_DIR="/tmp/review-prompts"
MANIFEST_PATH="/tmp/review-prompt-manifest.json"
SHOW_ALL_CHECKS=false
AUTHORIZED_BY=""
AUTHORIZATION_QUOTE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --my-user) MY_USER="$2"; shift 2 ;;
    --review-pr-skill) shift 2 ;; # Backward-compatible no-op.
    --base-dir) BASE_DIR="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --company) COMPANY="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --bundle) BUNDLE_PATH="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --manifest) MANIFEST_PATH="$2"; shift 2 ;;
    --show-all-checks) SHOW_ALL_CHECKS=true; shift ;;
    --authorized-by) AUTHORIZED_BY="$2"; shift 2 ;;
    --authorization-quote) AUTHORIZATION_QUOTE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MY_USER" || -z "$BASE_DIR" ]]; then
  echo "Usage: ... | build-review-prompt.sh --my-user USER --base-dir PATH [--workspace PATH] [--company KEY] [--project KEY] [--bundle PATH] [--out-dir PATH]" >&2
  exit 1
fi

if [[ ! -f "$BUNDLE_PATH" ]]; then
  echo "Dispatch context bundle not found: $BUNDLE_PATH" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

INPUT=$(cat)
COUNT=$(echo "$INPUT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

if [[ "$COUNT" -eq 0 ]]; then
  echo "No PR candidates to generate prompts for." >&2
  mkdir -p "$(dirname "$MANIFEST_PATH")"
  echo "[]" > "$MANIFEST_PATH"
  exit 0
fi

BUNDLE_TEXT=$(cat "$BUNDLE_PATH")
if [[ "$SHOW_ALL_CHECKS" == "true" ]]; then
  CI_ROLLUP_RULE="CI rollup: explicit --show-all-checks override is enabled. You may inspect all checks when needed, but keep main-session summary concise."
else
  CI_ROLLUP_RULE="CI rollup: only FAILURE / ERROR checks may enter main context. PASS checks must be omitted. Use gh pr view --json statusCheckRollup with a jq filter that selects failure/error only."
fi
# 一格綠的檢查只有在它真的跑過這條 branch 的時候才是證據。沒跑過的綠與跑過而通過的綠，
# 在 statusCheckRollup 裡長得一模一樣。
#
# **問的是這顆 sha 上的 commit status，不是那份 workflow 設定檔。** 以前教的是「把 base 拿
# 去對觸發條件」——那要人開一份 YAML、自己算條件成不成立，而同一件事 GitHub 上有一個直接
# 答得出來的地方。實測（2026-09-16／17，一個走 woodpecker 的 repo）：同一個 context 名
# `pr/woodpecker/lint-frontend`，在一顆真的跑完的 sha 上 pending→success 是 **689 秒**，
# 在四顆沒跑的上面是 9／22／11／20 秒；而第五顆連那個 context 都沒出現，rollup 上卻仍然
# 全綠（只有兩條真的跑完的 `b2c-ci/*`）。
#
# **兩種形狀要分開講**，因為它們要人做的事不同：太快的那一種要去看那個 build 到底做了什麼，
# 整個 context 缺席的那一種要問「這個 repo 的 PR 本來該有哪幾條」。
#
# **不寫死秒數。** 同一顆 sha 上 `check_changeset` 7 秒、`baseline-refresh` 12 秒，兩者都是
# 真的跑完——一個絕對門檻會把它們一起標紅。對照拿同名 context 的別顆 sha。
CI_ROLLUP_RULE="${CI_ROLLUP_RULE} 綠不等於跑過。判準問 commit status，不要去讀 workflow 的觸發條件：\`gh api repos/{owner}/{repo}/commits/{head_sha}/statuses --paginate --jq '.[] | \"\(.context)\t\(.state)\t\(.created_at)\"' | sort\`。逐個 context 看兩件事：(1) pending 到 success 的秒數差——同一個 context 名在別顆真的跑完的 sha 上要多久，拿那個當對照，不要用寫死的門檻（同一顆 sha 上本來就有 7 秒跑完的 job）；(2) 那個 context 在不在——整組缺席跟「跑很快」是兩種形狀，而它在 rollup 上一樣是全綠。兩種都不是綠，是**沒有量**：要在意見裡說出來，不要拿它當「CI 全綠」的依據。statuses 問不到的時候（權限、API 失敗）說出這一趟沒問到，並退回舊那招：把這顆 PR 的 base 拿去對那份 workflow 的觸發條件。**問不到不是全綠的溫和版本。**"
# 這一段以前指向 review-inbox 自己抄的一份 resolver，而它讀的是工作區底下沒有版控的
# polaris-config。那份補充現在住在提供它的那支 skill 自己的目錄裡（DP-484），所以這裡改成
# 掃宣告：核心不認得任何一家公司，也不去讀任何一支 skill 的目錄。
#
#   <!-- {前綴}-REPO-NOTES-{公司}: {命令} -->
#
# 找不到宣告就是「這家公司沒有補充」——那是一個答案，不是缺一個檔案。
HANDBOOK_JSON="[]"
if [[ -n "$COMPANY" && -n "$PROJECT" ]]; then
  DECLARED="$(grep -rhoE "<!--[[:space:]]*[A-Za-z0-9_-]*REPO-NOTES-${COMPANY}:[[:space:]]*[^>]+-->" \
    "$SCRIPT_DIR/../.." --include='SKILL.md' 2>/dev/null \
    | sed -E "s/.*REPO-NOTES-${COMPANY}:[[:space:]]*//; s/[[:space:]]*-->$//" | head -1 || true)"
  # 沒有宣告是一個答案（這家公司沒有補充），不是失敗——pipefail 之下 grep 的 1 會讓整支停掉。
  if [[ -n "$DECLARED" ]]; then
    # 宣告裡的路徑是相對 repo 根的（跟其他宣告一樣），所以在那裡跑。
    HANDBOOK_JSON="$( (cd "$ROOT_DIR" && eval "$DECLARED" "$PROJECT") 2>/dev/null \
      | python3 -c 'import json,sys
try:
    print(json.dumps(json.load(sys.stdin).get("narrative_paths", [])))
except Exception:
    print("[]")')"
  fi
fi

HANDBOOK_BLOCK=$(python3 - "$HANDBOOK_JSON" <<'PY'
import json
import sys

paths = json.loads(sys.argv[1])
if not paths:
    print("No project handbook: verified resolver returned an empty list. Do not scan repo guideline folders.")
else:
    print("Verified project handbook paths:")
    for idx, path in enumerate(paths, start=1):
        print(f"{idx}. {path}")
PY
)

# 送出授權：兩個都在才算授權，而且要帶著來源——一句沒有來源的「使用者已同意」在對外
# 寫入面前不成立，2026-08-26 有一個 sub-agent 因此拒絕送出，它是對的。
if [[ -n "$AUTHORIZED_BY" && -n "$AUTHORIZATION_QUOTE" ]]; then
  AUTHORIZATION_BLOCK="**送出授權：已授權。**
- 授權的人：${AUTHORIZED_BY}
- 原話：「${AUTHORIZATION_QUOTE}」
- 適用範圍：這一輪 review-inbox 的每一張 PR，包含本張。
依〈執行步驟〉第 6 步送出 GitHub review。"
else
  AUTHORIZATION_BLOCK="**送出授權：沒有授權。**
不要送出。做完 review 之後把 event、body、comments 各寫成一個檔案，路徑放進 Completion
Envelope 的 Detail，然後回報 \`AUTHORIZATION_MISSING\`。**宣告檔案寫好之前自己 \`ls\` 驗一次**
——2026-08-26 有一次宣告完成而檔案不存在，原因是命令在 parse 階段就死了而 exit code 被
讀成部分失敗。"
fi

# 延伸參考：只給路徑，讀不讀、讀多少由執行者判斷。以前 review-inbox 底下躺著這幾份
# 逐字相同的第二份（453 行），DP-575 刪掉了——相依早就寫在 frontmatter 的 requires 裡。
REVIEW_PR_REFS="$(cd "$SCRIPT_DIR/../../review-pr/references" 2>/dev/null && pwd || true)"
EXTRA_REFS=""
for f in review-pr-analysis-flow.md review-pr-entry-fetch-flow.md \
         review-pr-rereview-learning-flow.md review-pr-submit-flow.md \
         pr-input-resolver.md github-slack-user-mapping.md; do
  [[ -n "$REVIEW_PR_REFS" && -f "$REVIEW_PR_REFS/$f" ]] && EXTRA_REFS+="- ${REVIEW_PR_REFS}/${f}
"
done
if [[ -z "$EXTRA_REFS" ]]; then
  EXTRA_REFS_BLOCK="旁邊沒有 review-pr 這支 skill，所以沒有延伸參考可讀。上面的 inline dispatch
context 本來就自足，照它做完即可。"
else
  EXTRA_REFS_BLOCK="上面的 inline dispatch context 已經自足，下面這幾份是**延伸**——卡住的時候
可以讀，讀不讀、讀多少由你判斷，不需要全部讀完：
${EXTRA_REFS}"
fi

# 「一則 review 寫成什麼形狀」只有一份，住在 review-pr 底下。它必須 inline 進 packet：
# 執行者是 sub-agent，一份「讀不讀由你判斷」的形式規範對它不生效。這裡讀那一份、不抄它。
COMMENT_FORM_PATH="${REVIEW_PR_REFS:-}/review-comment-form.md"
if [[ -n "$REVIEW_PR_REFS" && -f "$COMMENT_FORM_PATH" ]]; then
  # 去掉 YAML frontmatter：那幾行是給讀 reference 的人看的，放進 packet 只是雜訊。
  COMMENT_FORM_BLOCK="$(awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {fm=0; next} !fm' "$COMMENT_FORM_PATH")"
else
  COMMENT_FORM_BLOCK="旁邊沒有 review-pr 這支 skill，拿不到那一份形式規範。照上面的 inline
dispatch context 做完，body 與 comment 的形狀自己判斷。"
fi

# 「什麼擋 merge」跟「一則 review 寫成什麼形狀」是同一類東西：它是判定規則，而下判斷的
# 是 sub-agent——一份列在「延伸參考、讀不讀由你判斷」裡的規則對它不生效。2026-09-06 真的
# 發生過：那張判定表當時沒有「上一輪的 should-fix 沒落地」那一列，派工的人自己補了一條
# 「沒落地就維持 REQUEST_CHANGES」，一顆已經有人 approve 的 PR 差點被一則既有註解擋住。
#
# 所以這裡把兩段 inline 進 packet，**讀 review-pr 那兩份、不抄它們**：門檻只有一個宣告源，
# 改一次兩邊就都對。抄一份進來的話，下一次改的人只會改到其中一份。
#
# 「送哪一個 event」是第三段，同一個理由：bundle 以前自己抄了一句 mapping，於是那句話與
# 〈Review Action〉那張表是兩個宣告源。DP-734 把 bundle 那一句改成指過來，表就只有一份。
SEVERITY_PATH="${REVIEW_PR_REFS:-}/../SKILL.md"
REREVIEW_PATH="${REVIEW_PR_REFS:-}/review-pr-rereview-learning-flow.md"
SUBMIT_FLOW_PATH="${REVIEW_PR_REFS:-}/review-pr-submit-flow.md"
VERDICT_RULES_BLOCK=""
if [[ -n "$REVIEW_PR_REFS" && -f "$SUBMIT_FLOW_PATH" ]]; then
  VERDICT_RULES_BLOCK+="$(awk '/^## Review Action/{f=1} f && /^## / && !/^## Review Action/{exit} f' "$SUBMIT_FLOW_PATH")
"
fi
if [[ -n "$REVIEW_PR_REFS" && -f "$SEVERITY_PATH" ]]; then
  VERDICT_RULES_BLOCK+="$(awk '/^## Severity Boundary/{f=1} f && /^## /  && !/^## Severity Boundary/{exit} f' "$SEVERITY_PATH")
"
fi
if [[ -n "$REVIEW_PR_REFS" && -f "$REREVIEW_PATH" ]]; then
  VERDICT_RULES_BLOCK+="
$(awk '/^## Re-approve Decision/{f=1} f && /^## / && !/^## Re-approve Decision/{exit} f' "$REREVIEW_PATH")"
fi
if [[ -z "${VERDICT_RULES_BLOCK//[[:space:]]/}" ]]; then
  VERDICT_RULES_BLOCK="旁邊沒有 review-pr 這支 skill，拿不到「什麼擋 merge」那份判定規則。
**這種時候不要自己補一條**——擋人的門檻是「這份 diff 讓系統變壞」，不是「我發現了一件真的
事」。**送出的 event 一律是 \`COMMENT\`**（沒問題或只有 nit 才 \`APPROVE\`）：\`REQUEST_CHANGES\`
會擋住對方接下來的每一次 push，而那要使用者明說過才送得出去，派工的人沒有那個授權。
must-fix 照樣逐條寫出來，只是那一票不擋人。"
fi

MANIFEST="["

for i in $(seq 0 $((COUNT - 1))); do
  PR_JSON=$(echo "$INPUT" | python3 -c "import sys,json; pr=json.load(sys.stdin)[$i]; print(json.dumps(pr))")
  REPO=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['repo'])")
  NUMBER=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['number'])")
  TITLE=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['title'])")
  URL=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
  # submit-pr-review.sh 要 owner/name，而這裡手上只有完整 URL。導不出來時故意吐一個
  # 帶著來源的值：它過不了 helper 的 --repository 檢查，於是失敗會指名是哪個 URL 解不開，
  # 而不是送出一個空字串讓下游猜。
  REPO_SLUG=$(printf '%s' "$URL" | python3 -c "
import re, sys
url = sys.stdin.read().strip()
m = re.search(r'github\.com/([^/]+/[^/]+)/pull/', url)
print(m.group(1) if m else f'UNRESOLVED-REPO-SLUG-FROM/{url}')
")
  AUTHOR=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['author'])")
  STATUS=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['review_status'])")
  DETAIL=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('review_detail',''))")
  MODEL_TIER=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('model_tier','standard_coding'))")
  MODEL_TIER_REASON=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('model_tier_reason','default review risk'))")
  CLUSTER_ROLE=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster_role','standalone'))")
  CLUSTER_KEY=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster_key',''))")
  CLUSTER_SIZE=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster_size',1))")
  CLUSTER_LEAD_URL=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster_lead_url',''))")
  CLUSTER_LEAD_SUMMARY=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster_lead_summary',''))")
  # 這一顆為什麼被判成 cluster（或為什麼沒有）。一個沒有人讀得到的理由等於沒有理由，
  # 所以它同時進 packet 與 manifest。
  CLUSTER_REASON=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster_reason',''))")
  # 這一顆站在誰身上。cluster 那幾格問的是「同不同一批改動」，這一格問的是一條不需要
  # 成組就成立的關係：base 是另一顆候選的 head。
  STACKED_ON_URL=$(echo "$PR_JSON" | python3 -c "import sys,json; print((json.load(sys.stdin).get('stacked_on') or {}).get('url',''))")
  STACKED_ON_NUMBER=$(echo "$PR_JSON" | python3 -c "import sys,json; print((json.load(sys.stdin).get('stacked_on') or {}).get('number') or '')")
  STACKED_BY=$(echo "$PR_JSON" | python3 -c "import sys,json; print(','.join(str(n) for n in (json.load(sys.stdin).get('stacked_by') or [])))")
  STACKED_IN_ROUND=$(echo "$PR_JSON" | python3 -c "import sys,json; print('1' if (json.load(sys.stdin).get('stacked_on') or {}).get('in_this_round') else '')")
  STACKED_REASON=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stacked_reason') or '')")
  TICKET_KEY=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ticket_key') or '')")
  ROOT_TICKET_KEY=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('root_ticket_key') or '')")
  ROOT_TOPIC_KEY=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('root_topic_key') or '')")
  SLACK_THREAD_TS=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('slack_thread_ts') or '')")

  # 那一句要讀得懂：兩個方向各一種說法，沒有邊的時候明講「站在預設分支上」。
  if [[ -n "$STACKED_ON_NUMBER" && -n "$STACKED_IN_ROUND" ]]; then
    STACKED_TEXT="這顆 PR 的 base 是 #${STACKED_ON_NUMBER}（${STACKED_ON_URL}），那一顆**同一輪也在被 review、還沒有人 approve**。你看到的 diff 有一部分是它的。先讀它的 review 結果（或它的 description）再判這一顆——兩顆在同一個檔案上的改動合起來之後的行為，沒有任何一份單獨的 review 在看。"
  elif [[ -n "$STACKED_ON_NUMBER" ]]; then
    STACKED_TEXT="這顆 PR 的 base 是 #${STACKED_ON_NUMBER}（${STACKED_ON_URL}），那一顆是 open PR，但**這一輪不在 review 範圍內**——多半是我方已經投過票、或它還是 draft。意思是你的 base 裡有一段沒有人在這一輪看的改動，而它可能還帶著沒解除的 CHANGES_REQUESTED。先去那一顆確認它現在的 review 狀態，再判這一顆。"
  elif [[ -n "$STACKED_BY" ]]; then
    STACKED_TEXT="這顆 PR 是別人的 base：#${STACKED_BY} 疊在它上面，同一輪也在被 review。**先做完這一顆**，你的結論是它們的前提。"
  else
    STACKED_TEXT="沒有別的候選疊在它上面。它自己站在哪裡：${STACKED_REASON:-問不到}。"
  fi

  # Map review_status to review mode instruction
  case "$STATUS" in
    needs_first_review)
      MODE_INSTRUCTION="正常 review 流程（首次 review）"
      ;;
    needs_re_approve)
      MODE_INSTRUCTION="Re-approve 流程：檢查自上次 approve 後的新 diff，若無實質變更直接 re-approve，有變更則 review 新的部分"
      ;;
    needs_re_review)
      MODE_INSTRUCTION="Re-review 流程：檢查上一輪 review comments 的修正狀況，確認作者是否已回應所有 issues"
      ;;
    *)
      MODE_INSTRUCTION="正常 review 流程"
      ;;
  esac

  # repo 可能是 `owner/name`。直接嵌進檔名的話，那條路徑指向一個不存在的子目錄，
  # `cat >` 失敗——而失敗的樣子是這顆 PR 的 packet 寫不出來，review 安靜地少一顆。
  # 今天沒壞是因為真實候選 JSON 的 repo 恰好是裸名字，那是巧合不是契約。
  #
  # 只換檔名，不換 repo 這個值本身：packet 正文與 manifest 的 `repo` 欄位仍然是候選
  # 給的那個字串，因為下游拿它去組本機路徑（`${BASE_DIR}/${REPO}`）。
  # 名字不能叫 REPO_SLUG——那個名字上面 :215 已經在用了，裝的是從 PR URL 解出來的
  # owner/name，packet 裡三處 `--repository` 都吃它。第一版就是這樣蓋掉它的，
  # review-packet-head-binding-selftest 當場判紅並指名那三處的值變成了裸名字。
  REPO_FILE_PART="${REPO//\//-}"
  PROMPT_FILE="$OUT_DIR/review-prompt-${REPO_FILE_PART}-${NUMBER}.txt"

  # 這幾個在 manifest 裡要保留原值（沒有就是空字串），所以另外取一個只給本文用的名字。
  # 就地覆寫的話，manifest 的欄位會從 "" 變成 "N/A"。
  CLUSTER_KEY_TEXT="${CLUSTER_KEY:-N/A}"
  CLUSTER_LEAD_URL_TEXT="${CLUSTER_LEAD_URL:-N/A}"
  CLUSTER_LEAD_SUMMARY_TEXT="${CLUSTER_LEAD_SUMMARY:-N/A}"
  CLUSTER_REASON_TEXT="${CLUSTER_REASON:-N/A}"
  TICKET_KEY_TEXT="${TICKET_KEY:-N/A}"
  ROOT_TICKET_KEY_TEXT="${ROOT_TICKET_KEY:-N/A}"
  ROOT_TOPIC_KEY_TEXT="${ROOT_TOPIC_KEY:-N/A}"
  SLACK_THREAD_TS_TEXT="${SLACK_THREAD_TS:-N/A}"

  # 本文寫在一個**帶引號**的 heredoc 裡，所以反引號、$(…)、裸 $VAR 全部是字面值，
  # 不需要任何逸出。要展開的東西一律寫成 ${NAME}，由下面這一段明確地填進去。
  # 只認得 ${NAME} 這一種形狀：帶預設值的 ${NAME:-…} 不支援是刻意的——支援它的話，
  # 一個打錯的名字會安靜地拿到預設值；不支援的話，它沒有值就是紅的。
  export AUTHOR AUTHORIZATION_BLOCK BASE_DIR BUNDLE_TEXT CI_ROLLUP_RULE CLUSTER_KEY_TEXT CLUSTER_LEAD_SUMMARY_TEXT CLUSTER_LEAD_URL_TEXT CLUSTER_REASON_TEXT CLUSTER_ROLE CLUSTER_SIZE STACKED_TEXT STACKED_REASON COMMENT_FORM_BLOCK DETAIL EXTRA_REFS_BLOCK HANDBOOK_BLOCK MODEL_TIER MODEL_TIER_REASON MODE_INSTRUCTION MY_USER NUMBER REPO REPO_SLUG ROOT_TICKET_KEY_TEXT ROOT_TOPIC_KEY_TEXT SCRIPT_DIR SLACK_THREAD_TS_TEXT STATUS TICKET_KEY_TEXT TITLE URL VERDICT_RULES_BLOCK
  fill_prompt_placeholders() {
    python3 -c '
import os, re, sys
text = sys.stdin.read()
missing = []


def fill(match):
    name = match.group(1)
    if name not in os.environ:
        missing.append(name)
        return ""
    return os.environ[name]


out = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", fill, text)
if missing:
    sys.stderr.write(
        "POLARIS_REVIEW_PROMPT_PLACEHOLDER_UNSET: " + ", ".join(sorted(set(missing))) + "\n")
    raise SystemExit(3)
sys.stdout.write(out)
'
  }

  fill_prompt_placeholders > "$PROMPT_FILE" <<'PROMPT'
Review PR: ${URL}
Repo: ${REPO} (local path: ${BASE_DIR}/${REPO})
PR #${NUMBER}: ${TITLE} by @${AUTHOR}
Review status: ${STATUS} (${DETAIL})
Review mode: ${MODE_INSTRUCTION}
Model class hint: ${MODEL_TIER} (${MODEL_TIER_REASON})
Cluster role: ${CLUSTER_ROLE}
Cluster key: ${CLUSTER_KEY_TEXT}
Cluster size: ${CLUSTER_SIZE}
Cluster lead PR: ${CLUSTER_LEAD_URL_TEXT}
Ticket key: ${TICKET_KEY_TEXT}
Root ticket key: ${ROOT_TICKET_KEY_TEXT}
Root topic key: ${ROOT_TOPIC_KEY_TEXT}
Slack thread_ts: ${SLACK_THREAD_TS_TEXT}

你正在執行 Code Reviewer review packet。請直接依照以下 inline dispatch context 執行 review。
這份 packet 自足——不需要讀任何 skill 就做得完；不要掃 repo guideline folders。

**Inline Dispatch Context**：
${BUNDLE_TEXT}

**一則 review 寫成什麼形狀（能用圖或表講的就不要寫成散文）**：
${COMMENT_FORM_BLOCK}

**什麼擋 merge（判定規則，不是參考）**：
${VERDICT_RULES_BLOCK}

**送出授權**：
${AUTHORIZATION_BLOCK}

**Project Handbook**：
${HANDBOOK_BLOCK}

**延伸參考**：
${EXTRA_REFS_BLOCK}

**Reviewed Head（先做，其餘每一步都綁在它上面）**：
- 這一次 review 依據哪一顆 sha，由這一行決定，之後不要再重算：
  `REVIEWED_HEAD=$(bash ${SCRIPT_DIR}/submit-pr-review.sh --repository ${REPO_SLUG} --pull-number ${NUMBER} --print-head)`
- 完整 diff 一律對那一顆取，存到 `/tmp/review-inbox-runs/{run_id}/pr-${NUMBER}.diff`：
  `bash ${SCRIPT_DIR}/submit-pr-review.sh --repository ${REPO_SLUG} --pull-number ${NUMBER} --reviewed-head "$REVIEWED_HEAD" --print-diff`
- **不要用 gh 的 pr diff 子命令讀內容。** 它與 REST 之間有過 34 分鐘的落差（2026-07-27 實測），
  讀到舊版會讓你對作者已經修好的東西再提一次。它只能用來取 changed-file 名單。

**Token Budget Rules**：
- Diff sampling: 先執行 `gh pr diff ${URL} --name-only` 取得完整 changed-file list。
- 主 session raw diff output 對單 PR 累積上限為 100 行。超過後本 PR 維持 hunk-only / sample-only 到 review 完成。
- 完整 diff（上面那條釘住 sha 的命令取回來的）優先存到 `/tmp/review-inbox-runs/{run_id}/pr-${NUMBER}.diff`，後續用 `inspect-pr-section.sh` 取 bounded section，不要用 Read 工具回讀完整 diff。

**落檔路徑（不要自己取名）**：一輪裡好幾個 reviewer 並行跑，而 `{run_id}` 那個目錄是整輪
共用的。**下面這幾個路徑各帶著這顆 PR 的編號，所以兩個 reviewer 在結構上寫不到同一個檔**：

| 這個東西 | 落在哪 |
|---|---|
| 完整 diff | `/tmp/review-inbox-runs/{run_id}/pr-${NUMBER}.diff` |
| review body | `/tmp/review-inbox-runs/{run_id}/pr-${NUMBER}-body.md` |
| inline comments | `/tmp/review-inbox-runs/{run_id}/pr-${NUMBER}-comments.json` |
| 中間檔（草稿、逐則 comment） | 同一個目錄，檔名一律以 `pr-${NUMBER}-` 開頭 |

2026-09-07 有一則以使用者名義送出的 review，body 講的是另一顆 PR 的 sitemap——兩個 reviewer
相隔 14 秒寫讀同一個 `body.md`。那個名字是當時的 agent 自己取的，因為這裡沒有說。

**review body 的第一行要寫下你正在看的那一顆**：

```
<!-- polaris-review-target: ${REPO_SLUG}#${NUMBER} -->
```

它是 HTML 註解，GitHub 算繪時看不見。**送出前那道閘會拿它跟要送去的 PR 對一次**，對不上就
擋下來——所以這一行不是裝飾，少了它送不出去。寫下它的必須是你（正在看這顆 PR 的人），
送出的那一步補不了：那一步只知道你叫它送去哪，不知道你讀到的檔是誰寫的。
- 在 sub-agent envelope 內，若那份 diff 不超過 2000 行，可讀完整 diff；超過時只讀每個 changed file 的 hunk headers、changed lines 與前後約 20 行 context。
- 單檔 diff 小於 200 行只適用於 sub-agent envelope；大檔只 sample changed hunks。
- **在 sub-agent envelope 內，讀 diff 以外的檔案不需要先落進某一類風險。** 以前這裡
  列著一張七類的白名單（import/export、routing、API contract、schema、test expectation、
  security/auth、payment/booking），而那張表擋掉的正好是最有價值的一類：把元件的 prop 或事件
  接線追到消費端、對照姊妹 repo 的同一段、讀**未改動**的區域確認註解與行為是否一致。判準改成
  一句話——**追到答案為止**：一個結論需要哪幾個檔案才站得住，就讀哪幾個。讀了什麼要在 Detail
  artifact 裡列出來。這一條只在 sub-agent 那一層成立，主 session 仍然受上面那條 100 行的限制。
- ${CI_ROLLUP_RULE}
- Existing comments: **主 session 只拿 dedup metadata**，完整 comment body 不進主 context：
  `gh api "repos/OWNER/REPO/pulls/${NUMBER}/comments" --paginate --jq '.[] | {user: .user.login, path, line: (.line // .original_line), side, head: ((.body // "")[:80])}'`
  **sub-agent envelope 內讀得到完整的 comment body**——接續別人的意見往下推（「上面
  那則講的其實也會一起解掉」）需要讀得懂別人在說什麼，而 80 個字讀不出來。
- Dedup 只比對 `(user, path, line, head)` 與語意相同的已指出問題；不要重複貼既有 comment 全文。
- **送出之前把 existing comments 再抓一次。** 你 review 的期間別人可能也留了意見——2026-08-26 的 #3009 就是這樣重複了兩則。

**你站在誰身上**：${STACKED_TEXT}

**Cluster / Model Tier Rules**：
- 這一顆的 cluster 判定憑什麼：${CLUSTER_REASON_TEXT}。`same_repo_overlap` 是量到的改動交集，`cross_repo_key_only` 是跨 repo 量不到交集而憑鍵放行的——後者代表「同一批改動」這件事沒有被驗證過，sibling-diff mode 下要自己確認。
- Model class hint 是一個事實，不是一道指令：它說的是這張 PR 的規模與風險等級。派工的人拿它判斷，adapter 認不認得這個類別由那一層決定。
- `cluster_lead`：完整 review 本 PR，Detail artifact 必須留下可被 sibling PR 使用的一句 lead review summary。
- `cluster_sibling`：Sibling-diff mode。Lead PR = ${CLUSTER_LEAD_URL_TEXT}。Lead summary = ${CLUSTER_LEAD_SUMMARY_TEXT}。
  **Lead summary 是起點不是全部——lead PR 自己的 description 要去讀一次。** 它講的是 lead 找到
  什麼，而 lead 對「哪些情況不歸我管」的宣稱只寫在它自己的 description 裡，不會出現在 summary
  上。那種宣稱正是 sibling 拿來對照的東西：lead 說「這一類我不做，因為上游沒有 X」，而 sibling
  正好只做那一類、而且它解 X 解得出來——兩張就不可能都對。
  2026-08-26 與 2026-08-27 對同一顆 sha 各跑一次同一張 sibling：讀了 lead description 的那一次
  抓到這個矛盾並判 must-fix，只看 lead summary 的那一次整條漏掉。
  先比較 sibling changed-file list / sampled diff 與 lead PR 的差異，再判斷 lead findings 是否仍適用。
  若行為、平台、API contract、測試範圍或風險不一致，或 lead summary 缺失且無法 confidence 判斷，將 result 設為 COMMENT 並在 summary 標記 needs_standard_review。
  **「兩邊不一致」本身就是一個發現，不是只是一個要標記的例外。** 姊妹 repo 的同一段是這一邊的
  對照組——兩端行為對不上的時候，先問哪一邊是對的，再把那個答案寫成意見；不要只回報「不一致所以
  需要標準 review」。
- `standalone`：正常 review。

**執行步驟**：
1. 專案辨識 — repo = ${REPO}, local path = ${BASE_DIR}/${REPO}
2. 取 $REVIEWED_HEAD（見 Reviewed Head 區塊），再用 ${BASE_DIR}/${REPO} 下可用的 fetch script 或 gh api 取得 PR metadata、changed-file names、reviews；diff 對 $REVIEWED_HEAD 取
3. 只讀 Project Handbook 區塊列出的 verified paths；若是 no project handbook，略過 handbook 讀取
4. 以 metadata-only 讀既有 review comments 並去重
5. 審查 changed files，依 inline dispatch context 的 severity / submit rules 產生 review
6. 送出 GitHub review，綁在同一顆上：
   `bash ${SCRIPT_DIR}/submit-pr-review.sh --repository ${REPO_SLUG} --pull-number ${NUMBER} --reviewed-head "$REVIEWED_HEAD" --event EVENT --body-file /tmp/review-inbox-runs/{run_id}/pr-${NUMBER}-body.md --comments-file /tmp/review-inbox-runs/{run_id}/pr-${NUMBER}-comments.json --submit`
   沒有 `--reviewed-head` 會被擋。stderr 出現 `POLARIS_PR_HEAD_ADVANCED` 表示作者在你 review
   期間又 push 了——review 已經送出且正確綁在你讀過的那一版，要不要再看一次由你判斷。
   **review 的送出與修正一律走這支腳本，不要自己打 `gh api`。** 要改一則已經送出的 review，
   把它的 id 交回同一支腳本：
   `bash ${SCRIPT_DIR}/submit-pr-review.sh --repository ${REPO_SLUG} --pull-number ${NUMBER} --update-review-id REVIEW_ID --body-file <改好的 body>`
   自己發 `gh api -X PUT` 已經毀掉過一則送出的 review：`-f body=@檔名` 傳的是字面值 `@檔名`，
   11 個字元蓋掉 4483 bytes 的意見，而我們這端沒有任何東西回報失敗。腳本每次寫入之後都會
   回讀一次，GitHub 回來的跟送出的對不上就非零離場
7. 查詢 approve 狀態

**參數**：
- GitHub username (--my-user): ${MY_USER}
- PR URL: ${URL}

**回傳格式（Completion Envelope）**：
Status: DONE | ERROR
Artifacts: {
  pr_url: "${URL}",
  number: ${NUMBER},
  title: "${TITLE}",
  author: "${AUTHOR}",
  repo: "${REPO}",
  result: "APPROVE" | "REQUEST_CHANGES" | "COMMENT",
  must_fix: N, should_fix: N, nit: N,
  approve_status: "M/2 approve(s), 已達標 / 還需 N 位",
  summary: "一句話描述"
}
Detail: /tmp/polaris-agent-{timestamp}.md
Summary: ≤ 3 sentences
PROMPT

  # Build manifest entry
  if [[ $i -gt 0 ]]; then MANIFEST+=","; fi
  MANIFEST+="{\"file\":\"${PROMPT_FILE}\",\"pr_url\":\"${URL}\",\"number\":${NUMBER},\"repo\":\"${REPO}\",\"model_tier\":\"${MODEL_TIER}\",\"cluster_role\":\"${CLUSTER_ROLE}\",\"cluster_key\":\"${CLUSTER_KEY}\",\"cluster_lead_url\":\"${CLUSTER_LEAD_URL}\",\"cluster_reason\":\"${CLUSTER_REASON}\",\"stacked_on\":\"${STACKED_ON_NUMBER}\",\"stacked_by\":\"${STACKED_BY}\",\"ticket_key\":\"${TICKET_KEY}\",\"root_ticket_key\":\"${ROOT_TICKET_KEY}\",\"root_topic_key\":\"${ROOT_TOPIC_KEY}\",\"slack_thread_ts\":\"${SLACK_THREAD_TS}\"}"
done

MANIFEST+="]"
mkdir -p "$(dirname "$MANIFEST_PATH")"
echo "$MANIFEST" > "$MANIFEST_PATH"

echo "Generated ${COUNT} prompt files in ${OUT_DIR}/" >&2
echo "Manifest: ${MANIFEST_PATH}" >&2
