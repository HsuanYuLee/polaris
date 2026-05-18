#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TMP="$(mktemp -d -t framework-pr-gate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

make_stub() {
  local name="$1"
  local exit_code="$2"
  cat > "$TMP/$name" <<SH
#!/usr/bin/env bash
echo "$name"
exit $exit_code
SH
  chmod +x "$TMP/$name"
}

make_stub w1-pass 0
make_stub w2-pass 0
make_stub w3-pass 0
make_stub w4-pass 0
env \
  POLARIS_VALIDATE_RUNTIME_BIN="$TMP/w1-pass" \
  POLARIS_AUDIT_GRADUATION_BIN="$TMP/w2-pass" \
  POLARIS_LINT_REFERENCE_LINE_COUNT_BIN="$TMP/w3-pass" \
  POLARIS_CHECK_QUARANTINE_BIN="$TMP/w4-pass" \
  bash scripts/check-framework-pr-gate.sh >/dev/null

for fail in w1 w2 w3 w4; do
  make_stub w1 0
  make_stub w2 0
  make_stub w3 0
  make_stub w4 0
  make_stub "$fail" 1
  if env \
    POLARIS_VALIDATE_RUNTIME_BIN="$TMP/w1" \
    POLARIS_AUDIT_GRADUATION_BIN="$TMP/w2" \
    POLARIS_LINT_REFERENCE_LINE_COUNT_BIN="$TMP/w3" \
    POLARIS_CHECK_QUARANTINE_BIN="$TMP/w4" \
    bash scripts/check-framework-pr-gate.sh >"$TMP/out" 2>"$TMP/err"; then
    echo "self-test failed: $fail failure did not fail aggregator" >&2
    exit 1
  fi
  grep -q "framework-pr-gate failed" "$TMP/err"
done

env \
  POLARIS_VALIDATE_RUNTIME_BIN="$TMP/w1-pass" \
  POLARIS_AUDIT_GRADUATION_BIN="$TMP/w2-pass" \
  POLARIS_LINT_REFERENCE_LINE_COUNT_BIN="$TMP/w3-pass" \
  POLARIS_CHECK_QUARANTINE_BIN="$TMP/w4-pass" \
  POLARIS_SURFACE_CLASS="developer_pr" \
  bash scripts/check-framework-pr-gate.sh >/dev/null

framework_paths=(".claude/**" ".agents/**" "scripts/**" "docs-manager/src/content/docs/specs/design-plans/**" "CLAUDE.md" "AGENTS.md")

strip_yaml_value() {
  local value="$1"
  value="${value%%#*}"
  value="${value//[/ }"
  value="${value//]/ }"
  value="${value//,/ }"
  value="${value//\"/}"
  value="${value//\'/}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

contains_framework_path() {
  local raw="$1"
  local normalized
  normalized="$(strip_yaml_value "$raw")"
  local path
  for path in "${framework_paths[@]}"; do
    if [[ " $normalized " == *" $path "* ]]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

read_yaml_line() {
  local target="$1"
  local old_ifs="$IFS"
  local rc
  IFS=
  read -r "$target"
  rc="$?"
  IFS="$old_ifs"
  return "$rc"
}

check_pull_request_paths_ignore() {
  local workflow="$1"
  local line trimmed indent rest path
  local in_pull_request=0
  local pr_indent=-1
  local in_paths_ignore=0
  local paths_ignore_indent=-1

  while read_yaml_line line || [[ -n "$line" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    indent=$((${#line} - ${#trimmed}))

    if [[ "$in_pull_request" == "1" ]] && [[ "$indent" -le "$pr_indent" ]] && [[ "$trimmed" != pull_request:* ]]; then
      in_pull_request=0
      in_paths_ignore=0
    fi

    if [[ "$trimmed" == pull_request:* ]]; then
      in_pull_request=1
      pr_indent="$indent"
      in_paths_ignore=0
      continue
    fi

    if [[ "$in_pull_request" != "1" ]]; then
      continue
    fi

    if [[ "$in_paths_ignore" == "1" ]] && [[ "$indent" -le "$paths_ignore_indent" ]] && [[ "$trimmed" != -* ]]; then
      in_paths_ignore=0
    fi

    if [[ "$trimmed" == paths-ignore:* ]]; then
      rest="${trimmed#paths-ignore:}"
      path="$(contains_framework_path "$rest" || true)"
      if [[ -n "$path" ]]; then
        echo "workflow pull_request paths-ignore contains framework path: $path" >&2
        return 1
      fi
      in_paths_ignore=1
      paths_ignore_indent="$indent"
      continue
    fi

    if [[ "$in_paths_ignore" == "1" ]] && [[ "$trimmed" == -* ]]; then
      rest="${trimmed#-}"
      path="$(contains_framework_path "$rest" || true)"
      if [[ -n "$path" ]]; then
        echo "workflow pull_request paths-ignore contains framework path: $path" >&2
        return 1
      fi
    fi
  done < "$workflow"
}

workflow=".github/workflows/framework-pr.yml"
[[ -f "$workflow" ]] || { echo "missing $workflow" >&2; exit 1; }
for path in ".claude/**" ".agents/**" "scripts/**" "docs-manager/src/content/docs/specs/design-plans/**" "CLAUDE.md" "AGENTS.md"; do
  grep -Fq "$path" "$workflow" || { echo "workflow paths missing $path" >&2; exit 1; }
done
check_pull_request_paths_ignore "$workflow"

cat > "$TMP/no-pr-ignore.yml" <<'YAML'
on:
  pull_request:
    paths:
      - ".claude/**"
YAML
check_pull_request_paths_ignore "$TMP/no-pr-ignore.yml"

cat > "$TMP/non-framework-ignore.yml" <<'YAML'
on:
  pull_request:
    paths-ignore:
      - "docs/**/*.png"
      - "README.md"
YAML
check_pull_request_paths_ignore "$TMP/non-framework-ignore.yml"

cat > "$TMP/framework-inline-ignore.yml" <<'YAML'
on:
  pull_request:
    paths-ignore: ["README.md", ".claude/**"]
YAML
if check_pull_request_paths_ignore "$TMP/framework-inline-ignore.yml" 2>"$TMP/framework-inline-ignore.err"; then
  echo "self-test failed: framework pull_request paths-ignore fixture passed" >&2
  exit 1
fi
grep -Fq ".claude/**" "$TMP/framework-inline-ignore.err"

cat > "$TMP/push-ignore-only.yml" <<'YAML'
on:
  push:
    paths-ignore:
      - ".claude/**"
      - "scripts/**"
  pull_request:
    paths:
      - ".claude/**"
YAML
check_pull_request_paths_ignore "$TMP/push-ignore-only.yml"

echo "PASS: framework PR gate self-test"
