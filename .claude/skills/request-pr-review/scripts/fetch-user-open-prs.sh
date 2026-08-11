#!/usr/bin/env bash
# Purpose: 取得使用者名下所有的 open PR，含 base/head branch。
#
# Usage: ./fetch-user-open-prs.sh [--author <username>] [--org <org>]
# Output (stdout): PR 物件的 JSON array，每筆帶 org/repo/number/title/url/updated_at/labels/base/head
# Progress (stderr): 搜尋進度；問不到的東西逐筆指名
# Exit:  0 至少問到一個 org / 3 一個 org 都問不到（含沒有人宣告要看哪個 org）
#
# **org 不從環境變數來，也不寫死。** 要看哪個 org 的 PR 由別的 skill 在自己的 SKILL.md 用
# PR-CONTEXT 宣告，這裡問 resolve-pr-context.sh。理由是這支 skill 要能被單獨帶到別的環境：
# 在那裡一個寫死的占位字串不會報錯，只會安靜地查一個不存在的地方。`--org` 仍然收，那是給
# 「臨時看一個沒宣告的 org」用的，不是預設路徑。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_CONTEXT="${SCRIPT_DIR}/resolve-pr-context.sh"
AUTHOR=""
ORG_OVERRIDE=""

SKILLS_ARGS=()

# --skills 原樣轉交給宣告解析器；selftest 用它指向一棵假的宣告樹，才量得到「宣告驅動」
# 本身，而不是順便量到某一家公司真的那一份宣告。空陣列在 bash 3.2 + set -u 下展開會炸，
# 所以取值一律用 ${SKILLS_ARGS[@]+...} 這個安全形式。
while [[ $# -gt 0 ]]; do
  case "$1" in
    --author) AUTHOR="${2:-}"; shift 2 ;;
    --org) ORG_OVERRIDE="${2:-}"; shift 2 ;;
    --skills) SKILLS_ARGS=(--skills "${2:-}"); shift 2 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "不認得的參數：$1" >&2; exit 2 ;;
  esac
done

if [[ -z "$AUTHOR" ]]; then
  AUTHOR="$(gh api user --jq '.login' 2>/dev/null || true)"
  if [[ -z "$AUTHOR" ]]; then
    echo "❌ 問不到你是誰（gh api user 沒回答），請用 --author <username> 指定" >&2
    exit 2
  fi
  echo "👤 自動偵測 GitHub user: ${AUTHOR}" >&2
fi

# 要看哪些 org
if [[ -n "$ORG_OVERRIDE" ]]; then
  ORGS="$ORG_OVERRIDE"
else
  if [[ ! -f "$PR_CONTEXT" ]]; then
    echo "❌ 找不到 ${PR_CONTEXT}——不知道要看哪個 org 的 PR。" >&2
    exit 3
  fi
  ORGS="$("$PR_CONTEXT" orgs ${SKILLS_ARGS[@]+"${SKILLS_ARGS[@]}"})" || exit 3
fi

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT
total=0
unreachable=""

for org in $ORGS; do
  echo "🔍 搜尋 ${AUTHOR} 在 ${org} 的 open PR..." >&2

  if ! prs="$(gh search prs "draft:false" --author "$AUTHOR" --state open --owner "$org" \
      --limit 100 --json repository,number,title,url,updatedAt,labels 2>&1)"; then
    # 一個 org 問不到不吃掉其餘的：記下來，最後一起說。整批消失比少一批更難發現。
    echo "  ⚠️ ${org} 問不到：$(printf '%s' "$prs" | head -1)" >&2
    unreachable="${unreachable}${org} "
    continue
  fi

  org_total="$(printf '%s' "$prs" | jq 'length')"
  echo "  📦 ${org}：${org_total} 個" >&2
  [[ "$org_total" -eq 0 ]] && continue

  for row in $(printf '%s' "$prs" | jq -r '.[] | @base64'); do
    _jq() { printf '%s' "$row" | base64 --decode | jq -r "$1"; }

    repo="$(_jq '.repository.name')"
    number="$(_jq '.number')"

    # base/head 要另外問一次——search 不回這兩個。問不到的那一筆要說出來，不能留空字串
    # 混進結果裡：下游拿空的 base 去比對，會把它讀成「base 是預設分支」。
    if branch_info="$(gh api "repos/${org}/${repo}/pulls/${number}" \
        --jq '{base: .base.ref, head: .head.ref}' 2>/dev/null)"; then
      base="$(printf '%s' "$branch_info" | jq -r '.base')"
      head="$(printf '%s' "$branch_info" | jq -r '.head')"
      branch_status="ok"
    else
      base=""
      head=""
      branch_status="unreachable"
      echo "  ⚠️ ${repo} #${number} 的 base/head 問不到" >&2
    fi

    jq -n \
      --arg org "$org" --arg repo "$repo" --argjson number "$number" \
      --arg title "$(_jq '.title')" --arg url "$(_jq '.url')" \
      --arg updated_at "$(_jq '.updatedAt')" \
      --arg labels "$(_jq '[.labels[].name] | join(",")')" \
      --arg base "$base" --arg head "$head" --arg branch_status "$branch_status" \
      '{org: $org, repo: $repo, number: $number, title: $title, url: $url,
        updated_at: $updated_at, labels: $labels, base: $base, head: $head,
        branch_status: $branch_status}' >> "$tmpfile"

    total=$((total + 1))
  done
done

if [[ -n "$unreachable" ]]; then
  echo "⚠️ 這些 org 這一趟問不到，結果裡沒有它們的 PR：${unreachable}" >&2
fi

if [[ "$total" -eq 0 && -n "$unreachable" ]]; then
  echo "❌ 一個 org 都問不到——這不是「沒有 PR」。" >&2
  echo "[]"
  exit 3
fi

jq -s '.' "$tmpfile"
echo "✅ 取得完成，共 ${total} 個 PR" >&2
