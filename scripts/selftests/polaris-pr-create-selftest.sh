#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/polaris-pr-create.sh"

TMPROOT="$(mktemp -d -t polaris-pr-create-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_count=0
fail_count=0

ok() {
  printf 'ok %s\n' "$1"
  pass_count=$((pass_count + 1))
}

fail() {
  printf 'not ok %s\n' "$1" >&2
  fail_count=$((fail_count + 1))
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    ok "$label"
  else
    fail "$label"
    printf 'expected to contain: %s\nactual:\n%s\n' "$needle" "$haystack" >&2
  fi
}

run_auto_assign_case() {
  local label="auto-assign-config-user"
  local parent="$TMPROOT/$label"
  local repo="$parent/repo"
  local mockbin="$parent/bin"
  local edit_args_file="$parent/edit-args.txt"
  local out=""
  local rc=0

  mkdir -p "$repo" "$mockbin"
  cat > "$parent/workspace-config.yaml" <<'EOF'
language: zh-TW
user:
  github_username: "cfg-user"
EOF

  git init -q -b main "$repo"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" config user.email "polaris-selftest@example.com"
  printf 'fixture\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "base"
  git -C "$repo" checkout -q -b task/selftest

  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "pr" && "\$2" == "create" ]]; then
  printf 'https://github.com/demo/example/pull/123\n'
  exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "edit" ]]; then
  printf '%s\n' "\$*" > "$edit_args_file"
  exit 0
fi
if [[ "\$1" == "api" && "\${2:-}" == "user" ]]; then
  printf 'fallback-user\n'
  exit 0
fi
printf 'unexpected gh call: %s\n' "\$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"

  set +e
  out="$(PATH="$mockbin:$PATH" bash "$WRAPPER" --repo "$repo" --skip-gates --base main --title "fixture" --body "fixture" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    ok "$label rc"
  else
    fail "$label rc"
    printf '%s\n' "$out" >&2
  fi
  assert_contains "$label output" "$out" "PR assigned to cfg-user"
  assert_contains "$label edit-args" "$(cat "$edit_args_file")" "https://github.com/demo/example/pull/123 --add-assignee cfg-user"
}

run_auto_assign_case

if [[ "$fail_count" -ne 0 ]]; then
  printf '\n=== polaris-pr-create selftest: %s PASS / %s FAIL ===\n' "$pass_count" "$fail_count" >&2
  exit 1
fi

printf '\n=== polaris-pr-create selftest: %s/%s PASS ===\n' "$pass_count" "$pass_count"
