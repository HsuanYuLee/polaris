#!/usr/bin/env bash
# validate-language-policy.sh — workspace artifact language policy gate.
#
# Purpose: validate skill-produced artifacts against workspace-config.yaml language.
# Exit codes:
#   0 — PASS, or advisory findings only
#   1 — blocking language policy violations
#   2 — usage error / file not found / unsupported mode
#
# Usage:
#   validate-language-policy.sh [--blocking|--advisory] [--mode artifact|bilingual|bilingual-source|bilingual-translation] [--language LANG] [--workspace-root DIR] <file>...
#   validate-language-policy.sh --selftest
#   LANGUAGE_POLICY_SELFTEST=1 validate-language-policy.sh

set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $0 [--blocking|--advisory] [--mode artifact|json-fields|bilingual|bilingual-source|bilingual-translation] [--language LANG] [--workspace-root DIR] <file>...

Options:
  --blocking            Exit 1 when violations are found.
  --advisory            Print findings but exit 0. Default.
  --mode artifact       Enforce normal artifact policy. Default.
  --mode json-fields    Enforce per-field policy on refinement.json human-facing
                        prose fields (tasks[].title, tasks[].scope,
                        acceptance_criteria[].text). Violations name the field path.
  --mode bilingual      Allow bilingual/source documents without zh-TW-only enforcement.
  --mode bilingual-source|bilingual-translation
                        Aliases for bilingual documentation pairs.
  --language LANG       Override workspace-config.yaml language.
  --workspace-root DIR  Root used to find workspace-config.yaml.
  --selftest            Run embedded selftest.
EOF
  exit 2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/workspace-config-root.sh
. "$script_dir/lib/workspace-config-root.sh"

read_language_from_config() {
  local config="$1"
  if [[ ! -f "$config" ]]; then
    return 0
  fi
  awk -F ':' '
    /^[[:space:]]*language[[:space:]]*:/ {
      v=$2
      sub(/#.*/, "", v)
      gsub(/^[[:space:]"'\''"]+|[[:space:]"'\''"]+$/, "", v)
      if (v != "") {
        print v
      }
      exit
    }
  ' "$config"
}

read_workspace_language() {
  local start="${1:-$PWD}"
  local config_path=""
  config_path="$(resolve_workspace_config_path "$start" 2>/dev/null || true)"
  if [[ -n "$config_path" && -f "$config_path" ]]; then
    read_language_from_config "$config_path" || true
    return 0
  fi
  return 0
}

run_validator() {
  local enforcement="$1"
  local mode="$2"
  local language="$3"
  shift 3

  python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_language_policy_1.py" "$enforcement" "$mode" "$language" "$@"
}

selftest() {
  local tmpdir pass fail total
  tmpdir="$(mktemp -d)"
  pass=0
  fail=0
  total=0

  assert_rc() {
    local expected="$1"
    shift
    total=$((total + 1))
    set +e
    "$@" >/tmp/language-policy-selftest.out 2>/tmp/language-policy-selftest.err
    local actual=$?
    set -e
    if [[ "$actual" == "$expected" ]]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAIL [$total]: expected rc=$expected got rc=$actual — $*" >&2
      sed 's/^/  stderr: /' /tmp/language-policy-selftest.err >&2 || true
    fi
  }

  cat > "$tmpdir/zh.md" <<'MD'
# 目標

這是一段繁體中文 artifact，包含 `scripts/validate-language-policy.sh`、https://example.com/path 與 `JSON` key，應該通過。
MD

  cat > "$tmpdir/en.md" <<'MD'
This is a full English paragraph that should fail zh-TW artifact policy because it is natural language output.
MD

  cat > "$tmpdir/code-heavy.md" <<'MD'
```bash
LANGUAGE_POLICY_SELFTEST=1 bash scripts/validate-language-policy.sh
```

- `source_type`: `dp`
- `task/DP-050-T3-workspace-language-policy-gate-script`
- https://example.com/docs/path
- `scripts/validate-language-policy.sh --blocking --mode artifact`
MD

  mkdir -p "$tmpdir/root/company"
  cat > "$tmpdir/root/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML
  cat > "$tmpdir/root/company/workspace-config.yaml" <<'YAML'
# Company config intentionally does not override language.
projects: []
YAML
  cp "$tmpdir/en.md" "$tmpdir/root/company/en.md"

  mkdir -p "$tmpdir/no-language"
  cat > "$tmpdir/no-language/workspace-config.yaml" <<'YAML'
projects: []
YAML
  cp "$tmpdir/zh.md" "$tmpdir/no-language/zh.md"

  mkdir -p "$tmpdir/root/repo"
  git -C "$tmpdir/root/repo" init -q
  git -C "$tmpdir/root/repo" config user.name "Polaris Selftest"
  git -C "$tmpdir/root/repo" config user.email "polaris-selftest@example.com"
  cat > "$tmpdir/root/repo/README.md" <<'MD'
# repo
MD
  git -C "$tmpdir/root/repo" add README.md
  git -C "$tmpdir/root/repo" commit -qm "init"
  mkdir -p "$tmpdir/linked-worktree"
  git -C "$tmpdir/root/repo" worktree add --detach "$tmpdir/linked-worktree/repo-wt" >/dev/null
  cp "$tmpdir/root/company/en.md" "$tmpdir/linked-worktree/repo-wt/en.md"

  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode artifact "$tmpdir/zh.md"
  assert_rc 1 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode artifact "$tmpdir/en.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --advisory --language zh-TW --mode artifact "$tmpdir/en.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode artifact "$tmpdir/code-heavy.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode bilingual "$tmpdir/en.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language zh-TW --mode bilingual-source "$tmpdir/en.md"
  assert_rc 0 env -u LANGUAGE_POLICY_SELFTEST bash "$script_dir/validate-language-policy.sh" --blocking --language en --mode artifact "$tmpdir/en.md"
  assert_rc 1 bash -c "cd '$tmpdir/root/company' && env -u LANGUAGE_POLICY_SELFTEST bash '$script_dir/validate-language-policy.sh' --blocking --mode artifact '$tmpdir/root/company/en.md'"
  assert_rc 1 bash -c "cd '$tmpdir/root/company' && env -u LANGUAGE_POLICY_SELFTEST bash '$script_dir/validate-language-policy.sh' --blocking --workspace-root . --mode artifact '$tmpdir/root/company/en.md'"
  assert_rc 1 bash -c "cd '$tmpdir/no-language' && env -u LANGUAGE_POLICY_SELFTEST bash '$script_dir/validate-language-policy.sh' --blocking --mode artifact '$tmpdir/no-language/zh.md'"
  assert_rc 0 bash -c "cd '$tmpdir/no-language' && env -u LANGUAGE_POLICY_SELFTEST bash '$script_dir/validate-language-policy.sh' --advisory --mode artifact '$tmpdir/no-language/zh.md'"
  assert_rc 1 bash -c "cd '$tmpdir/linked-worktree/repo-wt' && env -u LANGUAGE_POLICY_SELFTEST bash '$script_dir/validate-language-policy.sh' --blocking --mode artifact '$tmpdir/linked-worktree/repo-wt/en.md'"

  echo "validate-language-policy.sh selftest: $pass/$total passed, $fail failed"
  rm -rf "$tmpdir"
  [[ "$fail" -eq 0 ]]
}

if [[ "${LANGUAGE_POLICY_SELFTEST:-}" == "1" ]]; then
  selftest
  exit $?
fi

enforcement="advisory"
mode="artifact"
language=""
workspace_root=""
files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --blocking)
      enforcement="blocking"
      shift
      ;;
    --advisory)
      enforcement="advisory"
      shift
      ;;
    --mode)
      [[ $# -ge 2 ]] || usage
      mode="$2"
      shift 2
      ;;
    --language)
      [[ $# -ge 2 ]] || usage
      language="$2"
      shift 2
      ;;
    --workspace-root)
      [[ $# -ge 2 ]] || usage
      workspace_root="$2"
      shift 2
      ;;
    --selftest)
      selftest
      exit $?
      ;;
    --help|-h)
      usage
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage
      ;;
    *)
      files+=("$1")
      shift
      ;;
  esac
done

if [[ ${#files[@]} -eq 0 ]]; then
  usage
fi

if [[ -z "$language" ]]; then
  if [[ -n "$workspace_root" ]]; then
    language="$(read_workspace_language "$workspace_root" || true)"
  else
    language="$(read_workspace_language "$PWD" || true)"
  fi
fi

run_validator "$enforcement" "$mode" "$language" "${files[@]}"
