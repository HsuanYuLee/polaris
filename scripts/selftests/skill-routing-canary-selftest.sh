#!/usr/bin/env bash
# Exercise skill-routing-canary.sh against a synthetic skill directory.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SKILLS_DIR="$TMP_DIR/skills"
mkdir -p "$SKILLS_DIR"

create_skill() {
  local name="$1"
  local description="$2"
  mkdir -p "$SKILLS_DIR/$name"
  cat > "$SKILLS_DIR/$name/SKILL.md" <<EOF
---
name: $name
description: "$description"
---

# $name
EOF
}

create_skill review-pr "review PR, review 這個 PR"
create_skill check-pr-approvals "我的 PR, PR 狀態"
create_skill engineering "做 ticket, engineering"
create_skill refinement "討論需求, refinement, 修 bug, bug source"
create_skill breakdown "拆單, breakdown"
create_skill verify-AC "verify AC, 跑驗收"
create_skill learning "learning, 學習"
create_skill validate "validate, 檢查機制"

"$ROOT/scripts/skill-routing-canary.sh" --root "$ROOT" --skills-dir "$SKILLS_DIR"
echo "skill-routing-canary-selftest: PASS"
