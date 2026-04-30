#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-model-tier-policy.sh"

PASS=0
FAIL=0
TOTAL=0

assert_rc() {
  local actual="$1"
  local expected="$2"
  local label="$3"

  TOTAL=$((TOTAL + 1))
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [$TOTAL]: $label expected rc=$expected got rc=$actual" >&2
  fi
}

make_root() {
  local root="$1"
  mkdir -p "$root/.claude/skills/references" "$root/.claude/rules" "$root/.agents"
  ln -s ../.claude/skills "$root/.agents/skills"
  cat > "$root/.claude/skills/references/model-tier-policy.md" <<'EOF'
# Model Tier Policy

| Class | Mapping |
|-------|---------|
| `small_fast` | `haiku` alias / `gpt-5.4-mini` |
| `standard_coding` | `sonnet` alias |

Migration: `model: "haiku"` becomes `model class: small_fast`.
EOF
}

run_validator() {
  local root="$1"
  bash "$VALIDATOR" "$root" >/tmp/polaris-model-tier-selftest.out 2>/tmp/polaris-model-tier-selftest.err
}

TMPDIR_ST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ST" /tmp/polaris-model-tier-selftest.out /tmp/polaris-model-tier-selftest.err' EXIT

# T1: legal central mapping passes.
ROOT1="$TMPDIR_ST/legal"
make_root "$ROOT1"
mkdir -p "$ROOT1/.claude/skills/demo"
cat > "$ROOT1/.claude/skills/demo/SKILL.md" <<'EOF'
# Demo

Dispatch with `model class: small_fast`.
EOF
run_validator "$ROOT1"
assert_rc "$?" "0" "legal central mapping"

# T2: illegal raw provider model policy in skill prose fails.
ROOT2="$TMPDIR_ST/illegal-skill"
make_root "$ROOT2"
mkdir -p "$ROOT2/.claude/skills/demo"
cat > "$ROOT2/.claude/skills/demo/SKILL.md" <<'EOF'
# Demo

Dispatch with model: "haiku" for batch JIRA writes.
EOF
set +e
run_validator "$ROOT2"
rc=$?
set -e
assert_rc "$rc" "1" "illegal skill raw model"

# T3: illegal gpt policy outside central mapping fails.
ROOT3="$TMPDIR_ST/illegal-gpt"
make_root "$ROOT3"
mkdir -p "$ROOT3/.claude/skills/demo"
cat > "$ROOT3/.claude/skills/demo/SKILL.md" <<'EOF'
# Demo

Use gpt-5.4-mini directly for this workflow.
EOF
set +e
run_validator "$ROOT3"
rc=$?
set -e
assert_rc "$rc" "1" "illegal gpt raw model"

# T4: copied .agents/skills mirror fails.
ROOT4="$TMPDIR_ST/bad-mirror"
make_root "$ROOT4"
rm "$ROOT4/.agents/skills"
mkdir -p "$ROOT4/.agents/skills"
mkdir -p "$ROOT4/.claude/skills/demo"
cat > "$ROOT4/.claude/skills/demo/SKILL.md" <<'EOF'
# Demo

Dispatch with `model class: small_fast`.
EOF
set +e
run_validator "$ROOT4"
rc=$?
set -e
assert_rc "$rc" "1" "bad mirror mode"

echo "validate-model-tier-policy selftest: $PASS/$TOTAL passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
