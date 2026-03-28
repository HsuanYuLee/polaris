#!/usr/bin/env bash
# detect-repo-context.sh — Detect repo type, framework, base branch, and project metadata
# Usage: detect-repo-context.sh [--repo-dir <path>]
set -euo pipefail

REPO_DIR="."

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

cd "$REPO_DIR"

# Detect project name from directory
PROJECT=$(basename "$(pwd)")

# Detect framework
FRAMEWORK="unknown"
LANGUAGE="javascript"
TEST_FRAMEWORK="unknown"
BASE_BRANCH="develop"
HAS_ESLINT=false
HAS_TSCONFIG=false
SRC_DIRS='["src"]'

# Check TypeScript
if [[ -f "tsconfig.json" ]]; then
  LANGUAGE="typescript"
  HAS_TSCONFIG=true
fi

# Check ESLint
if [[ -f ".eslintrc.js" ]] || [[ -f ".eslintrc.json" ]] || [[ -f ".eslintrc.cjs" ]] || [[ -f "eslint.config.js" ]] || [[ -f "eslint.config.mjs" ]]; then
  HAS_ESLINT=true
fi

# Detect framework from config files
if [[ -f "nuxt.config.ts" ]] || [[ -f "nuxt.config.js" ]]; then
  FRAMEWORK="nuxt3"
  # Check for monorepo structure
  if [[ -d "apps/main/src" ]]; then
    SRC_DIRS='["apps/main/src","src"]'
  fi
elif [[ -f "next.config.js" ]] || [[ -f "next.config.ts" ]] || [[ -f "next.config.mjs" ]]; then
  FRAMEWORK="nextjs"
elif [[ -f "vue.config.js" ]] || [[ -f "vite.config.ts" ]] || [[ -f "vite.config.js" ]]; then
  FRAMEWORK="vue3"
fi

# Detect test framework
if [[ -f "vitest.config.ts" ]] || [[ -f "vitest.config.js" ]] || grep -q '"vitest"' package.json 2>/dev/null; then
  TEST_FRAMEWORK="vitest"
elif [[ -f "jest.config.ts" ]] || [[ -f "jest.config.js" ]] || grep -q '"jest"' package.json 2>/dev/null; then
  TEST_FRAMEWORK="jest"
fi

# Detect base branch
if git rev-parse --verify develop >/dev/null 2>&1; then
  BASE_BRANCH="develop"
elif git rev-parse --verify main >/dev/null 2>&1; then
  BASE_BRANCH="main"
elif git rev-parse --verify master >/dev/null 2>&1; then
  BASE_BRANCH="master"
fi

cat <<EOF
{
  "project": "$PROJECT",
  "framework": "$FRAMEWORK",
  "language": "$LANGUAGE",
  "test_framework": "$TEST_FRAMEWORK",
  "base_branch": "$BASE_BRANCH",
  "src_dirs": $SRC_DIRS,
  "has_eslint": $HAS_ESLINT,
  "has_tsconfig": $HAS_TSCONFIG
}
EOF
