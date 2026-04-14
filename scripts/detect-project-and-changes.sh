#!/usr/bin/env bash
# detect-project-and-changes.sh — 偵測專案類型、變更檔案、對應測試檔
#
# Usage: ./detect-project-and-changes.sh [--project-dir <path>]
# Output (stdout): JSON object with project info, changed files, and test coverage
# Progress (stderr): 偵測進度
#
# 輸出欄位：
#   - project         — 專案名稱
#   - test_framework   — jest | vitest | none
#   - base_branch      — develop | main
#   - test_command      — 測試執行指令
#   - coverage_command  — 覆蓋率指令
#   - lint_command      — ESLint 指令
#   - changed_files     — 變更的 source files（排除測試/mock/型別）
#   - test_files        — 對應的測試檔（含存在狀態）
#   - missing_tests     — 缺少測試的檔案清單
#   - stats             — 統計
#
# Example:
#   ./detect-project-and-changes.sh --project-dir ~/work/your-repo
#   cd ~/work/your-api-repo && ./detect-project-and-changes.sh

set -euo pipefail

PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# 如果未指定，用當前目錄
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(pwd)"
fi

cd "$PROJECT_DIR"

echo "🔍 偵測專案：$PROJECT_DIR" >&2

# ── Step 1: Project Detection ──────────────────────────────────────

project="unknown"
test_framework="none"
base_branch="develop"
test_command=""
coverage_command=""
lint_command="npx eslint"

if [ -f "apps/main/vitest.config.ts" ] || [ -f "apps/main/vitest.config.mts" ]; then
  project="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
  test_framework="vitest"
  base_branch="develop"
  test_command="cd apps/main && npx vitest run"
  coverage_command="cd apps/main && npx vitest run --coverage"
  echo "  📦 ${project}（Vitest — monorepo apps/main）" >&2
elif [ -f "jest.config.js" ] && [ -d "resources" ]; then
  # Laravel-style project with resources/ directory
  project="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
  test_framework="jest"
  base_branch="develop"
  test_command="npx jest"
  coverage_command="npx jest --coverage"
  echo "  📦 ${project}（Jest）" >&2
elif [ -f "jest.config.js" ] && [ -d "src" ] && [ -f "pnpm-workspace.yaml" ]; then
  project="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
  test_framework="jest"
  base_branch="main"
  test_command="npx jest"
  coverage_command="npx jest --coverage"
  echo "  📦 ${project}（Jest — pnpm workspace）" >&2
elif [ -f "gulpfile.js" ]; then
  project="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
  test_framework="none"
  base_branch="main"
  echo "  📦 ${project}（無測試框架）" >&2
elif [ -f "vitest.config.ts" ] || [ -f "vitest.config.mts" ]; then
  project="$(basename "$PROJECT_DIR")"
  test_framework="vitest"
  test_command="npx vitest run"
  coverage_command="npx vitest run --coverage"
  echo "  📦 ${project}（Vitest — generic）" >&2
elif [ -f "jest.config.js" ] || [ -f "jest.config.ts" ]; then
  project="$(basename "$PROJECT_DIR")"
  test_framework="jest"
  test_command="npx jest"
  coverage_command="npx jest --coverage"
  echo "  📦 ${project}（Jest — generic）" >&2
else
  project="$(basename "$PROJECT_DIR")"
  echo "  ⚠️ 未知專案類型：$project" >&2
fi

# ── Step 2: Detect Changed Files ───────────────────────────────────

echo "  📝 偵測變更檔案..." >&2

# 收集所有來源的變更，合併去重（避免遺漏任何階段的改動）
sources_used=""

# Source 1: staged changes
staged=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || echo "")
if [ -n "$staged" ]; then
  sources_used="${sources_used}staged+"
  echo "  ✓ staged changes 偵測到" >&2
fi

# Source 2: unstaged changes（工作目錄的未暫存修改）
unstaged=$(git diff --name-only --diff-filter=ACMR 2>/dev/null || echo "")
if [ -n "$unstaged" ]; then
  sources_used="${sources_used}unstaged+"
  echo "  ✓ unstaged changes 偵測到" >&2
fi

# Source 3: branch diff（已 commit 但尚未 merge 的變更）
branch_diff=""
merge_base=$(git merge-base HEAD "origin/$base_branch" 2>/dev/null || git merge-base HEAD "$base_branch" 2>/dev/null || echo "")
if [ -n "$merge_base" ]; then
  branch_diff=$(git diff "$merge_base"...HEAD --name-only --diff-filter=ACMR 2>/dev/null || echo "")
  if [ -n "$branch_diff" ]; then
    sources_used="${sources_used}branch_diff+"
    echo "  ✓ branch diff（vs ${base_branch}）偵測到" >&2
  fi
fi

# 合併所有來源並去重
all_changed=$(printf "%s\n%s\n%s" "$staged" "$unstaged" "$branch_diff" | sort -u | grep -v '^$' || echo "")

# 決定 change_source 標籤
sources_used="${sources_used%+}"  # 移除尾部 +
if [ -z "$sources_used" ]; then
  change_source="none"
  echo "  ⚠️ 未偵測到任何變更" >&2
else
  change_source="$sources_used"
  echo "  使用 ${sources_used} 合併偵測" >&2
fi

# 過濾出 source files（排除測試、mock、型別定義、設定檔）
source_files=""
if [ -n "$all_changed" ]; then
  source_files=$(echo "$all_changed" \
    | grep -E '\.(ts|tsx|vue|js|jsx)$' \
    | grep -v -E '\.test\.|\.spec\.|__test__|__tests__|__mock__|__mocks__|\.d\.ts' \
    | grep -v -E '\.config\.(ts|js|mjs)$' \
    | grep -v -E 'index\.(ts|js)$' \
    || echo "")
fi

source_count=0
if [ -n "$source_files" ]; then
  source_count=$(echo "$source_files" | wc -l | tr -d ' ')
fi

echo "  📊 $source_count 個 source files 變更" >&2

# ── Step 3: Check Test File Existence ──────────────────────────────

echo "  🧪 檢查測試檔案..." >&2

changed_files_json="[]"
test_files_json="[]"
missing_tests="[]"
has_test_count=0
no_test_count=0

if [ -n "$source_files" ]; then
  while IFS= read -r src_file; do
    # 加入 changed_files
    changed_files_json=$(echo "$changed_files_json" | jq --arg f "$src_file" '. + [$f]')

    # 跳過不需要測試的檔案
    basename_file=$(basename "$src_file")
    skip=false

    case "$basename_file" in
      types.ts|types.tsx|constants.ts|constants.tsx) skip=true ;;
      *.d.ts) skip=true ;;
    esac

    if [ "$skip" = true ]; then
      continue
    fi

    # 找對應測試檔
    dir=$(dirname "$src_file")
    name_no_ext="${basename_file%.*}"
    ext="${basename_file##*.}"

    test_found=false
    test_path=""

    # 嘗試多種位置
    for test_suffix in ".test" ".spec"; do
      for test_dir in "$dir" "$dir/__tests__" "$dir/../__tests__"; do
        candidate="$test_dir/${name_no_ext}${test_suffix}.${ext}"
        if [ -f "$candidate" ]; then
          test_found=true
          test_path="$candidate"
          break 2
        fi
        # 也檢查 .ts 測試（即使 source 是 .vue）
        if [ "$ext" = "vue" ]; then
          candidate="$test_dir/${name_no_ext}${test_suffix}.ts"
          if [ -f "$candidate" ]; then
            test_found=true
            test_path="$candidate"
            break 2
          fi
        fi
      done
    done

    if [ "$test_found" = true ]; then
      has_test_count=$((has_test_count + 1))
      test_files_json=$(echo "$test_files_json" | jq \
        --arg src "$src_file" --arg test "$test_path" \
        '. + [{"source": $src, "test": $test, "exists": true}]')
    else
      no_test_count=$((no_test_count + 1))
      missing_tests=$(echo "$missing_tests" | jq --arg f "$src_file" '. + [$f]')
      test_files_json=$(echo "$test_files_json" | jq \
        --arg src "$src_file" --arg test "" \
        '. + [{"source": $src, "test": $test, "exists": false}]')
    fi
  done <<< "$source_files"
fi

echo "  ✅ $has_test_count 有測試，⚠️ $no_test_count 缺少測試" >&2

# ── Step 4: Collect all test files to run ──────────────────────────

existing_test_files=$(echo "$test_files_json" | jq -r '[.[] | select(.exists == true) | .test] | join("\n")')

# Also include changed test files themselves
changed_test_files=""
if [ -n "$all_changed" ]; then
  changed_test_files=$(echo "$all_changed" \
    | grep -E '\.(test|spec)\.(ts|tsx|js|jsx)$' \
    || echo "")
fi

# Merge and deduplicate
all_test_files=""
if [ -n "$existing_test_files" ] || [ -n "$changed_test_files" ]; then
  all_test_files=$(printf "%s\n%s" "$existing_test_files" "$changed_test_files" | sort -u | grep -v '^$' || echo "")
fi

test_file_count=0
if [ -n "$all_test_files" ]; then
  test_file_count=$(echo "$all_test_files" | wc -l | tr -d ' ')
fi

# Build test file list as JSON
test_files_to_run="[]"
if [ -n "$all_test_files" ]; then
  while IFS= read -r tf; do
    test_files_to_run=$(echo "$test_files_to_run" | jq --arg f "$tf" '. + [$f]')
  done <<< "$all_test_files"
fi

# ── Output ─────────────────────────────────────────────────────────

result=$(jq -n \
  --arg project "$project" \
  --arg test_framework "$test_framework" \
  --arg base_branch "$base_branch" \
  --arg test_command "$test_command" \
  --arg coverage_command "$coverage_command" \
  --arg lint_command "$lint_command" \
  --arg change_source "$change_source" \
  --argjson changed_files "$changed_files_json" \
  --argjson test_files "$test_files_json" \
  --argjson test_files_to_run "$test_files_to_run" \
  --argjson missing_tests "$missing_tests" \
  --argjson stats "$(jq -n \
    --argjson source_count "$source_count" \
    --argjson has_test "$has_test_count" \
    --argjson missing_test "$no_test_count" \
    --argjson test_files_to_run "$test_file_count" \
    '{source_files: $source_count, has_test: $has_test, missing_test: $missing_test, test_files_to_run: $test_files_to_run}')" \
  '{
    project: $project,
    test_framework: $test_framework,
    base_branch: $base_branch,
    test_command: $test_command,
    coverage_command: $coverage_command,
    lint_command: $lint_command,
    change_source: $change_source,
    changed_files: $changed_files,
    test_files: $test_files,
    test_files_to_run: $test_files_to_run,
    missing_tests: $missing_tests,
    stats: $stats
  }')

echo "$result"
echo "✅ 偵測完成：${project}（${test_framework}），${source_count} 個 source files，${test_file_count} 個測試待執行" >&2
