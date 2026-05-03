#!/usr/bin/env bash
# build-review-prompt.sh — Generate review sub-agent prompts from PR candidates JSON
#
# Input:  stdin = JSON array from check-my-review-status.sh
# Args:   --my-user <github_username>
#         --review-pr-skill <path to review-pr/SKILL.md>
#         --base-dir <local repo base directory>
#         --out-dir <output directory for prompt files> (default: /tmp/review-prompts)
#
# Output: One file per PR in out-dir: review-prompt-{repo}-{number}.txt
#         Also writes /tmp/review-prompt-manifest.json with [{file, pr_url, number, repo}]
#
# Usage:
#   cat /tmp/review-candidates.json \
#     | ./build-review-prompt.sh \
#         --my-user daniel-lee-kk \
#         --review-pr-skill /path/to/review-pr/SKILL.md \
#         --base-dir /path/to/repos
#
# The Strategist reads each prompt file and uses it as the Agent tool's prompt parameter.

set -euo pipefail

MY_USER=""
REVIEW_PR_SKILL=""
BASE_DIR=""
OUT_DIR="/tmp/review-prompts"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --my-user) MY_USER="$2"; shift 2 ;;
    --review-pr-skill) REVIEW_PR_SKILL="$2"; shift 2 ;;
    --base-dir) BASE_DIR="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MY_USER" || -z "$REVIEW_PR_SKILL" || -z "$BASE_DIR" ]]; then
  echo "Usage: ... | build-review-prompt.sh --my-user USER --review-pr-skill PATH --base-dir PATH [--out-dir PATH]" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

INPUT=$(cat)
COUNT=$(echo "$INPUT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

if [[ "$COUNT" -eq 0 ]]; then
  echo "No PR candidates to generate prompts for." >&2
  echo "[]" > /tmp/review-prompt-manifest.json
  exit 0
fi

MANIFEST="["

for i in $(seq 0 $((COUNT - 1))); do
  PR_JSON=$(echo "$INPUT" | python3 -c "import sys,json; pr=json.load(sys.stdin)[$i]; print(json.dumps(pr))")
  REPO=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['repo'])")
  NUMBER=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['number'])")
  TITLE=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['title'])")
  URL=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
  AUTHOR=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['author'])")
  STATUS=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['review_status'])")
  DETAIL=$(echo "$PR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('review_detail',''))")

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

  PROMPT_FILE="$OUT_DIR/review-prompt-${REPO}-${NUMBER}.txt"

  cat > "$PROMPT_FILE" <<PROMPT
Review PR: ${URL}
Repo: ${REPO} (local path: ${BASE_DIR}/${REPO})
PR #${NUMBER}: ${TITLE} by @${AUTHOR}
Review status: ${STATUS} (${DETAIL})
Review mode: ${MODE_INSTRUCTION}

你是一個 Code Reviewer sub-agent。請按照 review-pr SKILL.md 的流程執行 review。

**執行步驟**：
1. 讀取 ${REVIEW_PR_SKILL} 了解完整 review 流程
2. Step 1: 專案辨識 — repo = ${REPO}, local path = ${BASE_DIR}/${REPO}
3. Step 2: 用 ${BASE_DIR}/${REPO} 下的 fetch-pr-info.sh 或 gh api 取得 PR 資訊（若 skill 有 bundled script 則優先使用）
4. Step 3: 讀 ${BASE_DIR}/${REPO}/.claude/rules/ + handbook
5. Step 3.5: 讀既有 review comments（去重）
6. Step 4: 審查每個變更檔案
7. Step 5: 提交 GitHub review
8. Step 6: 查詢 approve 狀態

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
  MANIFEST+="{\"file\":\"${PROMPT_FILE}\",\"pr_url\":\"${URL}\",\"number\":${NUMBER},\"repo\":\"${REPO}\"}"
done

MANIFEST+="]"
echo "$MANIFEST" > /tmp/review-prompt-manifest.json

echo "Generated ${COUNT} prompt files in ${OUT_DIR}/" >&2
echo "Manifest: /tmp/review-prompt-manifest.json" >&2
