#!/usr/bin/env bash
# rebase-pr-branch.sh — 批次 rebase PR branches 到最新 base branch
#
# Usage: echo '<pr_json>' | ./rebase-pr-branch.sh [--work-dir <path>] [--dry-run]
# Input (stdin): fetch-user-open-prs.sh 的 JSON 輸出
# Output (stdout): JSON array，每個 PR 附加 rebase_status
# Progress (stderr): rebase 進度
#
# rebase_status 值：
#   - "success"     — rebase + push 成功
#   - "conflict"    — rebase 有 conflict，已 abort
#   - "skipped"     — 本地無 repo 或 stash 失敗
#
# Example:
#   ./fetch-user-open-prs.sh --author your-username \
#     | ./rebase-pr-branch.sh --work-dir ~/work

set -euo pipefail

WORK_DIR="$HOME/work"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir) WORK_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ "$DRY_RUN" = true ]; then
  echo "🔍 Dry-run mode: will rebase but skip push" >&2
fi

# 讀取 stdin 的 PR JSON
prs=$(cat)
total=$(echo "$prs" | jq 'length')

if [ "$total" -eq 0 ]; then
  echo "[]"
  exit 0
fi

echo "🔄 開始 rebase $total 個 PR..." >&2

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
success_count=0
conflict_count=0
skip_count=0

# 記住起始目錄
ORIGINAL_DIR="$(pwd)"

# --- Cascade Rebase ---
# 若 task PR 的 base 是 feature branch（非 develop/main/master），先 rebase feature branch 到其 upstream
# 避免 task PR diff 膨脹（包含 feature branch 落後 develop 的所有差異）
ORG="${ORG:-}"
cascade_processed=""

if [ -n "$ORG" ]; then
  for row in $(echo "$prs" | jq -r '.[] | @base64'); do
    _jq_cascade() { echo "$row" | base64 --decode | jq -r "$1"; }
    repo=$(_jq_cascade '.repo')
    base=$(_jq_cascade '.base')

    # 只處理非 develop/main/master 的 base branch
    case "$base" in
      develop|main|master) continue ;;
    esac

    # 每個 (repo, base) 只處理一次
    cascade_key="${repo}:${base}"
    if echo "$cascade_processed" | grep -qF "$cascade_key"; then
      continue
    fi
    cascade_processed="$cascade_processed $cascade_key"

    repo_dir="$WORK_DIR/$repo"
    if [ ! -d "$repo_dir" ]; then
      continue
    fi

    # 查詢 feature branch 的 upstream（從 open PR 取 baseRefName）
    upstream=$(gh pr list --repo "$ORG/$repo" --head "$base" --state open \
      --json baseRefName --jq '.[0].baseRefName' 2>/dev/null || echo "")

    if [ -z "$upstream" ] || [ "$upstream" = "null" ]; then
      echo "  ℹ️ $repo: $base 無 open PR，跳過 cascade rebase" >&2
      continue
    fi

    echo "  🔗 Cascade: $repo $base → rebase onto origin/$upstream" >&2

    cd "$repo_dir"

    # Stash
    cascade_had_stash=false
    cascade_original_branch=$(git branch --show-current 2>/dev/null || echo "")
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      if git stash push -m "cascade-rebase-auto-stash" 2>/dev/null; then
        cascade_had_stash=true
      fi
    fi

    # Fetch + checkout feature branch + rebase onto upstream
    git fetch origin "$upstream" "$base" 2>/dev/null
    if git checkout "$base" 2>/dev/null; then
      if git rebase "origin/$upstream" 2>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
          echo "  ✅ Cascade: $repo $base rebased onto $upstream（dry-run: skipped push）" >&2
        elif git push --force-with-lease 2>/dev/null; then
          echo "  ✅ Cascade: $repo $base rebased + pushed onto $upstream" >&2
        else
          echo "  ✅ Cascade: $repo $base already up to date with $upstream" >&2
        fi
      else
        git rebase --abort 2>/dev/null || true
        echo "  ⚠️ Cascade: $repo $base rebase onto $upstream failed (conflict)" >&2
      fi
    fi

    # Restore
    if [ -n "$cascade_original_branch" ]; then
      git checkout "$cascade_original_branch" 2>/dev/null || true
    fi
    if [ "$cascade_had_stash" = true ]; then
      git stash pop 2>/dev/null || true
    fi
    cd "$ORIGINAL_DIR"

    # Re-fetch 更新後的 base branch（供後續 task rebase 使用）
    cd "$repo_dir"
    git fetch origin "$base" 2>/dev/null
    cd "$ORIGINAL_DIR"
  done
fi

# --- Per-PR Rebase ---
for row in $(echo "$prs" | jq -r '.[] | @base64'); do
  _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

  repo=$(_jq '.repo')
  number=$(_jq '.number')
  title=$(_jq '.title')
  url=$(_jq '.url')
  updated_at=$(_jq '.updated_at')
  labels=$(_jq '.labels')
  base=$(_jq '.base')
  head=$(_jq '.head')

  rebase_status="skipped"
  rebase_detail=""

  repo_dir="$WORK_DIR/$repo"

  if [ ! -d "$repo_dir" ]; then
    rebase_detail="本地無 $repo 目錄"
    skip_count=$((skip_count + 1))
    echo "  ⏭ $repo #$number — $rebase_detail" >&2
  else
    cd "$repo_dir"

    # 記住當前 branch
    original_branch=$(git branch --show-current 2>/dev/null || echo "")

    # Stash 未 commit 的改動
    had_stash=false
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      if git stash push -m "rebase-pr-branch-auto-stash" 2>/dev/null; then
        had_stash=true
      else
        rebase_detail="stash 失敗，跳過"
        skip_count=$((skip_count + 1))
        echo "  ⏭ $repo #$number — $rebase_detail" >&2
        cd "$ORIGINAL_DIR"

        pr_result=$(jq -n \
          --arg repo "$repo" --argjson number "$number" --arg title "$title" \
          --arg url "$url" --arg updated_at "$updated_at" --arg labels "$labels" \
          --arg base "$base" --arg head "$head" \
          --arg rebase_status "skipped" --arg rebase_detail "$rebase_detail" \
          '{repo: $repo, number: $number, title: $title, url: $url, updated_at: $updated_at, labels: $labels, base: $base, head: $head, rebase_status: $rebase_status, rebase_detail: $rebase_detail}')
        echo "$pr_result" >> "$tmpfile"
        continue
      fi
    fi

    # Fetch + checkout + rebase
    git fetch origin "$head" "$base" 2>/dev/null

    if git checkout "$head" 2>/dev/null; then
      if git rebase "origin/$base" 2>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
          rebase_status="success"
          rebase_detail="rebase 成功（dry-run: skipped push）"
          success_count=$((success_count + 1))
          echo "  ✅ $repo #$number — $rebase_detail" >&2
        elif git push --force-with-lease 2>/dev/null; then
          rebase_status="success"
          rebase_detail="rebase + push 成功"
          success_count=$((success_count + 1))
          echo "  ✅ $repo #$number — $rebase_detail" >&2
        else
          rebase_status="success"
          rebase_detail="rebase 成功（already up to date）"
          success_count=$((success_count + 1))
          echo "  ✅ $repo #$number — $rebase_detail" >&2
        fi
      else
        git rebase --abort 2>/dev/null || true
        rebase_status="conflict"
        rebase_detail="rebase origin/$base failed"
        conflict_count=$((conflict_count + 1))
        echo "  ⚠️ $repo #$number — conflict: $rebase_detail" >&2
      fi
    else
      rebase_status="skipped"
      rebase_detail="checkout $head 失敗"
      skip_count=$((skip_count + 1))
      echo "  ⏭ $repo #$number — $rebase_detail" >&2
    fi

    # 切回原本的 branch
    if [ -n "$original_branch" ]; then
      git checkout "$original_branch" 2>/dev/null || true
    fi

    # Restore stash
    if [ "$had_stash" = true ]; then
      git stash pop 2>/dev/null || echo "  ⚠️ stash pop 失敗，請手動檢查 $repo" >&2
    fi

    cd "$ORIGINAL_DIR"
  fi

  pr_result=$(jq -n \
    --arg repo "$repo" --argjson number "$number" --arg title "$title" \
    --arg url "$url" --arg updated_at "$updated_at" --arg labels "$labels" \
    --arg base "$base" --arg head "$head" \
    --arg rebase_status "$rebase_status" --arg rebase_detail "$rebase_detail" \
    '{repo: $repo, number: $number, title: $title, url: $url, updated_at: $updated_at, labels: $labels, base: $base, head: $head, rebase_status: $rebase_status, rebase_detail: $rebase_detail}')

  echo "$pr_result" >> "$tmpfile"
done

jq -s '.' "$tmpfile"
echo "✅ Rebase 完成：$success_count 成功、$conflict_count conflict、$skip_count 跳過" >&2
