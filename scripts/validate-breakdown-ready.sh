#!/usr/bin/env bash
# validate-breakdown-ready.sh
#
# Breakdown-to-engineering readiness gate. It runs after task.md schema
# validation and before breakdown hands work to engineering.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
usage: validate-breakdown-ready.sh <task.md|tasks_dir>
       validate-breakdown-ready.sh --self-test

Validates task.md readiness before breakdown hands work to engineering:
- task.md schema passes
- task folder dependency gate passes
- Allowed Files are machine-matchable path/glob tokens
- Scope Trace Matrix maps goals/AC to owning files, surface/boundary, and tests
- Scope Trace Matrix owning files are covered by Allowed Files
- UI/dashboard/API visible work declares a render/API surface, not only helper files
- folder-native task directories are scanned (T*/index.md)
- Gate Closure Matrix is present and names scope/test/verify/ci-local gates
- Gate rows expose pass conditions and ownership/decisions
- package graph changes include lockfile scope, or explicitly avoid package graph
- executable test runners are not declared as static/N/A bootstrap gates
- Nuxt/Vitest app Test Commands clear inherited DEBUG
- source migration Verify Command does not use broad substring grep that catches
  cross-scope API names/comments instead of direct library usage
EOF
}

run_self_test() {
  local tasks valid invalid invalid_matrix missing_scope missing_allowed missing_surface folder_valid local_specs_only static_runner package_graph_no_lock app_unclean_debug app_clean_debug broad_migration_grep
  SELFTEST_TMP="$(mktemp -d -t validate-breakdown-ready.XXXXXX)"
  trap 'rm -rf "${SELFTEST_TMP:-}"' EXIT
  tasks="$SELFTEST_TMP/tasks"
  mkdir -p "$tasks"
  valid="$tasks/T1.md"
  invalid="$tasks/T2.md"
  invalid_matrix="$tasks/T3.md"
  missing_scope="$tasks/T4.md"
  missing_allowed="$tasks/T5.md"
  missing_surface="$tasks/T6.md"
  mkdir -p "$tasks/T7"
  folder_valid="$tasks/T7/index.md"
  local_specs_only="$tasks/T8.md"
  static_runner="$tasks/T9.md"
  package_graph_no_lock="$tasks/T10.md"
  app_unclean_debug="$tasks/T11.md"
  app_clean_debug="$tasks/T12.md"
  broad_migration_grep="$tasks/T13.md"

  cat > "$valid" <<'MD'
---
title: "T1: 建立 breakdown readiness gate (2 pt)"
status: PLANNED
task_kind: T
task_shape: implementation
verification:
  behavior_contract:
    applies: false
    reason: "framework validator selftest；無產品 runtime 行為。"
depends_on: []
---

# T1: 建立 breakdown readiness gate (2 pt)

> Source: DP-082 | Task: DP-082-T1 | JIRA: N/A | Repo: work

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-082 |
| Work item ID | DP-082-T1 |
| Task ID | DP-082-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-082-T1-breakdown-readiness-gate |
| Task branch | task/DP-082-T1-breakdown-readiness-gate |
| Depends on | N/A |
| References to load | - `.claude/skills/references/task-md-schema.md` |

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

新增 breakdown readiness gate。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `scripts/validate-breakdown-ready.sh` | create | readiness gate |

## Allowed Files

- `scripts/validate-breakdown-ready.sh`
- `scripts/validate-breakdown-ready-selftest.sh`
- `VERSION`

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| readiness gate validates valid and invalid task.md files | `scripts/validate-breakdown-ready.sh`, `scripts/validate-breakdown-ready-selftest.sh` | CLI validator output | `bash scripts/validate-breakdown-ready.sh --self-test` |
| version bump is part of release metadata | `VERSION` | release metadata | `bash scripts/gates/gate-version-lint.sh --repo /tmp/repo` |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | breakdown |
| test | yes | selftest pass | breakdown |
| verify | yes | smoke pass | breakdown |
| ci-local | no | N/A | no repo CI required |

## 估點理由

2 pt，單一 validator 與 selftest。

## 測試計畫（code-level）

- selftest covers valid and invalid task.md。

## Test Command

```bash
echo test
```

## Test Environment

- **Level**: static
- **Dev env config**: `workspace-config.yaml` → `projects[work].dev_environment`
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo verify
```
MD

  sed 's/`scripts\/validate-breakdown-ready.sh`/上述檔案的 test 檔/' "$valid" > "$invalid"
  sed 's/| verify | yes | smoke pass | breakdown |/| verify | yes |  |  |/' "$valid" > "$invalid_matrix"
  awk 'BEGIN{skip=0} /^## Scope Trace Matrix/{skip=1; next} skip && /^## Gate Closure Matrix/{skip=0} !skip{print}' "$valid" > "$missing_scope"
  sed '/^- `scripts\/validate-breakdown-ready-selftest.sh`$/d' "$valid" > "$missing_allowed"
  sed 's/| readiness gate validates valid and invalid task.md files | `scripts\/validate-breakdown-ready.sh`, `scripts\/validate-breakdown-ready-selftest.sh` | CLI validator output | `bash scripts\/validate-breakdown-ready.sh --self-test` |/| dashboard status renders task readiness | `scripts\/validate-breakdown-ready.sh` | N\/A | `bash scripts\/validate-breakdown-ready.sh --self-test` |/' "$valid" > "$missing_surface"
  cp "$valid" "$folder_valid"
  cat > "$local_specs_only" <<'MD'
---
title: "T8: local sample recut only (2 pt)"
---

# T8: local sample recut only (2 pt)

> Source: DP-082 | Task: DP-082-T8 | JIRA: N/A | Repo: work

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-082 |
| Task ID | DP-082-T8 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Task branch | task/DP-082-T8-local-sample-only |
| References to load | - `docs-manager/src/content/docs/specs/design-plans/DP-082-example/index.md` |

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

只改 local sample spec。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `docs-manager/src/content/docs/specs/design-plans/DP-082-example/index.md` | modify | local sample recut |

## Allowed Files

- `docs-manager/src/content/docs/specs/design-plans/DP-082-example/index.md`

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
| sample recut proof | `docs-manager/src/content/docs/specs/design-plans/DP-082-example/index.md` | local sample spec surface | `bash scripts/validate-breakdown-ready.sh docs-manager/src/content/docs/specs/design-plans/DP-082-example` |

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | breakdown |
| test | yes | sample lint pass | breakdown |
| verify | yes | sample grep pass | breakdown |
| ci-local | no | N/A - no repo CI required | breakdown |

## 估點理由

2 pt，只有 local sample。

## 測試計畫（code-level）

- sample smoke

## Test Command

```bash
echo test
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo verify
```
MD

  sed \
    -e 's/echo test/pnpm --dir apps\/main exec vitest run helpers\/date.test.ts/' \
    -e 's/| test | yes | selftest pass | breakdown |/| test | yes | vitest exits 0 | breakdown |/' \
    -e 's/`bash scripts\/validate-breakdown-ready.sh --self-test`/`pnpm --dir apps\/main exec vitest run helpers\/date.test.ts`/' \
    "$valid" > "$static_runner"

  sed \
    -e '/^- `VERSION`$/d' \
    -e '/^- `scripts\/validate-breakdown-ready-selftest.sh`$/a\
- `apps/main/package.json`\
- `pnpm-workspace.yaml`' \
    -e 's/version bump is part of release metadata/dayjs dependency graph is declared for apps\/main/' \
    -e 's/`VERSION`/`apps\/main\/package.json`, `pnpm-workspace.yaml`/' \
    -e 's/release metadata/repo package graph/' \
    -e 's/`bash scripts\/gates\/gate-version-lint.sh --repo \/tmp\/repo`/source grep + package graph check/' \
    "$valid" > "$package_graph_no_lock"

  sed \
    -e 's/echo test/pnpm --dir apps\/main exec vitest run helpers\/date.test.ts/' \
    -e 's/| test | yes | selftest pass | breakdown |/| test | yes | vitest exits 0 | breakdown |/' \
    -e 's/`bash scripts\/validate-breakdown-ready.sh --self-test`/`pnpm --dir apps\/main exec vitest run helpers\/date.test.ts`/' \
    -e 's#- \*\*Level\*\*: static#- **Level**: build#' \
    -e 's#- \*\*Env bootstrap command\*\*: N/A#- **Env bootstrap command**: pnpm install --frozen-lockfile#' \
    "$valid" > "$app_unclean_debug"

  sed 's/pnpm --dir apps\/main exec vitest run/env -u DEBUG pnpm --dir apps\/main exec vitest run/g' "$app_unclean_debug" > "$app_clean_debug"

  sed \
    -e '/## Verify Command/,$d' \
    "$valid" > "$broad_migration_grep"
  cat >> "$broad_migration_grep" <<'MD'
## Verify Command

```bash
! rg -n 'moment-timezone|moment' apps/main/pages/product
```
MD

  bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$valid" >/dev/null || {
    echo "self-test failed: valid task did not pass" >&2
    return 1
  }
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$invalid" >/dev/null 2>&1; then
    echo "self-test failed: natural-language Allowed Files entry passed" >&2
    return 1
  fi
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$invalid_matrix" >/dev/null 2>&1; then
    echo "self-test failed: incomplete Gate Closure Matrix row passed" >&2
    return 1
  fi
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$missing_scope" >/dev/null 2>&1; then
    echo "self-test failed: missing Scope Trace Matrix passed" >&2
    return 1
  fi
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$missing_allowed" >/dev/null 2>&1; then
    echo "self-test failed: Scope Trace Matrix owning file outside Allowed Files passed" >&2
    return 1
  fi
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$missing_surface" >/dev/null 2>&1; then
    echo "self-test failed: dashboard/UI row without render/API surface passed" >&2
    return 1
  fi
  bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$folder_valid" >/dev/null || {
    echo "self-test failed: folder-native T*/index.md task did not pass" >&2
    return 1
  }
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$local_specs_only" >/dev/null 2>&1; then
    echo "self-test failed: DP task targeting only local spec/sample artifacts passed" >&2
    return 1
  fi
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$static_runner" >/dev/null 2>&1; then
    echo "self-test failed: executable test runner with Level=static/bootstrap=N/A passed" >&2
    return 1
  fi
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$package_graph_no_lock" >/dev/null 2>&1; then
    echo "self-test failed: package graph change without lockfile scope passed" >&2
    return 1
  fi
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$app_unclean_debug" >/dev/null 2>&1; then
    echo "self-test failed: Nuxt/Vitest app command without DEBUG hygiene passed" >&2
    return 1
  fi
  bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$app_clean_debug" >/dev/null || {
    echo "self-test failed: clean DEBUG Nuxt/Vitest app command did not pass" >&2
    return 1
  }
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$broad_migration_grep" >/dev/null 2>&1; then
    echo "self-test failed: broad source migration moment grep passed" >&2
    return 1
  fi
  echo "validate-breakdown-ready self-test PASS"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit $?
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_breakdown_ready_1.py" "$SCRIPT_DIR" "$1"
