#!/usr/bin/env bash
# Selftest for check-docs-sync-complete.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="$script_dir/check-docs-sync-complete.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

setup_repo() {
  local repo="$1"
  mkdir -p "$repo/.claude/skills/demo" "$repo/docs" "$repo/scripts"
  cat > "$repo/.claude/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: >
  Demo skill.
metadata:
  version: 1.0.0
---

# Demo
EOF
  cat > "$repo/README.md" <<'EOF'
# Demo

1 workflow skills
EOF
  cat > "$repo/README.zh-TW.md" <<'EOF'
# Demo

1 個工作流技能
EOF
  cat > "$repo/docs/chinese-triggers.md" <<'EOF'
| 功能 | 中文觸發詞 | 英文觸發詞 | 說明 |
|---|---|---|---|
| **demo** | demo | demo | Demo |
EOF
  cat > "$repo/scripts/readme-lint.py" <<'EOF'
#!/usr/bin/env python3
import os, sys
if os.environ.get("FORCE_DOCS_LINT_FAIL") == "1":
    print("lint fail")
    sys.exit(1)
print("lint ok")
EOF
  chmod +x "$repo/scripts/readme-lint.py"

  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  git -C "$repo" add .
  git -C "$repo" commit -qm "initial"
}

assert_pass() {
  local label="$1"
  shift
  if ! "$@" >/tmp/check-docs-sync-complete.out 2>/tmp/check-docs-sync-complete.err; then
    echo "ASSERT FAIL [$label]: expected pass" >&2
    cat /tmp/check-docs-sync-complete.out >&2 || true
    cat /tmp/check-docs-sync-complete.err >&2 || true
    exit 1
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@" >/tmp/check-docs-sync-complete.out 2>/tmp/check-docs-sync-complete.err; then
    echo "ASSERT FAIL [$label]: expected fail" >&2
    cat /tmp/check-docs-sync-complete.out >&2 || true
    exit 1
  fi
}

# Case 1: frontmatter change without docs updates -> fail
repo1="$tmp/repo1"
setup_repo "$repo1"
python3 - <<'PY' "$repo1/.claude/skills/demo/SKILL.md"
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
path.write_text(text.replace("Demo skill.", "Demo skill updated."))
PY
assert_fail "frontmatter-needs-docs" "$gate" --repo "$repo1"
grep -q "missing docs targets" /tmp/check-docs-sync-complete.out

# Case 2: frontmatter change with trigger + README pair updates -> pass
repo2="$tmp/repo2"
setup_repo "$repo2"
python3 - <<'PY' "$repo2/.claude/skills/demo/SKILL.md" "$repo2/README.md" "$repo2/README.zh-TW.md" "$repo2/docs/chinese-triggers.md"
from pathlib import Path
skill, readme, zh, triggers = map(Path, __import__("sys").argv[1:])
skill.write_text(skill.read_text().replace("Demo skill.", "Demo skill updated."))
readme.write_text("# Demo\n\n1 workflow skills\n\nUpdated docs.\n")
zh.write_text("# Demo\n\n1 個工作流技能\n\n更新說明。\n")
triggers.write_text("| 功能 | 中文觸發詞 | 英文觸發詞 | 說明 |\n|---|---|---|---|\n| **demo** | demo | demo | Updated |\n")
PY
assert_pass "frontmatter-with-docs" "$gate" --repo "$repo2"

# Case 3: translation pair mismatch -> fail
repo3="$tmp/repo3"
setup_repo "$repo3"
echo -e "# Demo\n\n1 workflow skills\n\nChanged only english.\n" > "$repo3/README.md"
assert_fail "pair-mismatch" "$gate" --repo "$repo3"
grep -q "translation pair mismatch" /tmp/check-docs-sync-complete.out

# Case 4: metadata-only version bump should not require docs updates
repo4="$tmp/repo4"
setup_repo "$repo4"
python3 - <<'PY' "$repo4/.claude/skills/demo/SKILL.md"
from pathlib import Path
path = Path(__import__("sys").argv[1])
path.write_text(path.read_text().replace("version: 1.0.0", "version: 1.0.1"))
PY
assert_pass "metadata-only" "$gate" --repo "$repo4"

# Case 5: lint failure blocks closeout
repo5="$tmp/repo5"
setup_repo "$repo5"
assert_fail "lint-failure" env FORCE_DOCS_LINT_FAIL=1 "$gate" --repo "$repo5"
grep -q "readme-lint failed" /tmp/check-docs-sync-complete.out

echo "check-docs-sync-complete selftest: PASS"
