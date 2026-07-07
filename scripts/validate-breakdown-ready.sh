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
  local tasks valid invalid invalid_matrix missing_scope missing_allowed missing_surface folder_valid local_specs_only static_runner package_graph_no_lock app_unclean_debug app_clean_debug broad_migration_grep changeset_missing_allowed changeset_allowed
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
  changeset_missing_allowed="$tasks/T14.md"
  changeset_allowed="$tasks/T15.md"

  cat > "$valid" <<'MD'
---
title: "T1: 建立 breakdown readiness gate (2 pt)"
---

# T1: 建立 breakdown readiness gate (2 pt)

> Source: DP-082 | Task: DP-082-T1 | JIRA: N/A | Repo: work

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-082 |
| Task ID | DP-082-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Task branch | task/DP-082-T1-breakdown-readiness-gate |
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

  awk '
    /^title:/ {
      print
      print "status: PLANNED"
      print "deliverables:"
      print "  changeset:"
      print "    package_scope: \"@selftest/single-pkg\""
      print "    bump_level_default: patch"
      print "    filename_slug: selftest-123-change"
      next
    }
    { print }
  ' "$valid" \
    | sed \
      -e 's/# T1:/# T14:/' \
      -e 's/Task: DP-082-T1/Task: DP-082-T14/' \
      -e 's/Task ID | DP-082-T1/Task ID | DP-082-T14/' \
      -e 's/task\/DP-082-T1-breakdown-readiness-gate/task\/DP-082-T14-changeset-scope/' \
    > "$changeset_missing_allowed"
  sed '/^- `VERSION`$/i\
- `.changeset/selftest-123-change.md`' "$changeset_missing_allowed" > "$changeset_allowed"

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
  bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$tasks/T7" >/dev/null || {
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
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$changeset_missing_allowed" >/dev/null 2>&1; then
    echo "self-test failed: declared changeset deliverable outside Allowed Files passed" >&2
    return 1
  fi
  bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$changeset_allowed" >/dev/null || {
    echo "self-test failed: declared changeset deliverable covered by Allowed Files did not pass" >&2
    return 1
  }
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

python3 - "$SCRIPT_DIR" "$1" <<'PY'
from __future__ import annotations

import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path

script_dir = Path(sys.argv[1])
target = Path(sys.argv[2])
parse_task_md = script_dir / "parse-task-md.sh"
validate_task_md = script_dir / "validate-task-md.sh"
validate_task_md_deps = script_dir / "validate-task-md-deps.sh"
check_verify_command_executability = script_dir / "lib" / "check-verify-command-executability.sh"
validate_branch_name_ascii = script_dir / "validate-branch-name-ascii.sh"
resolve_task_branch = script_dir / "resolve-task-branch.sh"


def section(text: str, heading: str) -> str:
    lines = text.splitlines()
    out: list[str] = []
    in_section = False
    for line in lines:
        if line == heading:
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            out.append(line)
    return "\n".join(out)


def path_token(raw: str) -> bool:
    value = normalize_path_token(raw)
    if not value:
        return False
    if any(ch.isspace() for ch in value):
        return False
    if re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", value):
        return False
    if value.startswith("-"):
        return False
    if value in {".", ".."} or "/../" in f"/{value}/":
        return False
    if value.startswith(("http://", "https://")):
        return False
    return bool(re.match(r"^[^\s`'\"]+$", value))


def normalize_path_token(raw: str) -> str:
    value = raw.strip()
    if value.startswith("`") and value.endswith("`"):
        value = value[1:-1].strip()
    return value


def parse_allowed(file: Path) -> list[str]:
    proc = subprocess.run(
        [str(parse_task_md), "--field", "allowed_files", str(file)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return []
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


# task_shape ∈ {audit, confirmation} are confirmation-only delivery shapes whose
# work product is an evidence/spec artifact, not a tracked code change. For these
# shapes the specs-only / empty Allowed Files rejection is relaxed (DP-262 AC2).
# A missing field defaults to implementation, which keeps the original rejection
# (DP-262 AC-NEG1). The enum itself is validated by validate-task-md.sh; this
# consumer only reads the parsed value.
CARVE_OUT_TASK_SHAPES = {"audit", "confirmation"}


def parse_task_shape(file: Path) -> str:
    proc = subprocess.run(
        [str(parse_task_md), "--field", "task_shape", str(file)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return "implementation"
    value = proc.stdout.strip()
    return value or "implementation"


def task_files(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if path.is_dir():
        # Collect both T-tasks and V-tasks (DP-371 T2): the directory scan must
        # feed V{n}.md / V{n}/index.md to task_id_for_file symmetrically with the
        # T forms, otherwise V-tasks in a directory target are never seen.
        files = (
            sorted(path.glob("T*.md"))
            + sorted(path.glob("T*/index.md"))
            + sorted(path.glob("V*.md"))
            + sorted(path.glob("V*/index.md"))
        )
        return [
            file
            for file in files
            if "/tasks/pr-release/" not in str(file) and "/archive/" not in str(file)
        ]
    raise FileNotFoundError(path)


# --- DP-337 T2 (AC3 / AC-NEG3): delivery-boundary feat-base required gate -------
# DP-337 graduated source.base_branch to a universal field. At the refinement-json
# layer (T1) it is schema-OPTIONAL for a dp source: the ~230 historical dp
# refinement.json carry base_branch=None and must not be retroactively broken.
# The REQUIRED enforcement lives here, at the delivery boundary: when a dp-backed
# source actually walks breakdown, it MUST carry source.base_branch=feat/{id}
# (the feat-lane release model, DP-334). A dp source missing it (or carrying a
# non-feat value) fail-closes with POLARIS_DP_FEAT_BASE_REQUIRED.
#
# This is the SINGLE enforcement point. validate-refinement-lock-preflight.sh
# delegates to validate-breakdown-ready.sh and therefore inherits this gate at
# LOCK time — no second feat-base implementation lives in the preflight.
#
# The gate resolves the source's refinement.json from the target (the tasks/
# directory or a tasks/T{n}/index.md file both sit under a source container whose
# sibling is refinement.json). When no dp refinement.json is reachable (a non-DP
# tree, or the synthesized placeholders the lock-preflight runs in a tmpdir), the
# gate is a no-op: there is no source-level base_branch to certify there, and the
# real source's gate already ran (or will run) against its own refinement.json.
#
# AC-NEG3: the gate consults NO bypass env. There is intentionally no
# POLARIS_*_BYPASS read path; a missing feat base always fail-closes.

DP_FEAT_BASE_REQUIRED_MARKER = "POLARIS_DP_FEAT_BASE_REQUIRED"


def resolve_source_refinement_json(target: Path) -> Path | None:
    """Locate the refinement.json for the source container that owns the target.

    The breakdown / lock-preflight invocations pass either a source's tasks/
    directory or a tasks/T{n}/index.md file; both live under a source container
    whose direct child is refinement.json. Walk up from the target until a
    refinement.json sibling of a tasks/ ancestor is found.

    Args:
        target: the validate-breakdown-ready target path (file or directory).

    Returns:
        The resolved refinement.json Path when found, else None.
    """
    start = target if target.is_dir() else target.parent
    current = start.resolve()
    while True:
        candidate = current / "refinement.json"
        if candidate.is_file():
            return candidate
        # Only climb while we are still inside a source's tasks/ subtree; once we
        # pass the container boundary keep climbing one more level so the
        # container's own refinement.json (sibling of tasks/) is reached.
        parent = current.parent
        if parent == current:
            return None
        current = parent


def validate_dp_feat_base_required(target: Path) -> tuple[str, str] | None:
    """Require source.base_branch=feat/{id} for a dp source entering breakdown.

    Reads the resolved source refinement.json. Only dp sources are gated here:
    jira sources carry their own (jira-only) base contract enforced at the
    refinement-json layer, and a non-dp/non-jira tree has no source to certify.

    Args:
        target: the validate-breakdown-ready target path.

    Returns:
        (marker, message) on a contract violation (missing or non-feat
        base_branch on a dp source), or None when the source carries the
        required feat base, is not a dp source, or no refinement.json is
        reachable (e.g. the lock-preflight tmpdir placeholders).
    """
    refinement_json = resolve_source_refinement_json(target)
    if refinement_json is None:
        return None
    try:
        data = json.loads(refinement_json.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        # A malformed refinement.json is owned by validate-refinement-json.sh;
        # do not double-report it as a feat-base failure.
        return None
    source = data.get("source") if isinstance(data, dict) else None
    if not isinstance(source, dict):
        return None
    if source.get("type") != "dp":
        return None
    source_id = str(source.get("id") or "").strip()
    if not source_id:
        # No source.id to derive the expected feat base; this is a schema problem
        # owned by validate-refinement-json.sh, not a feat-base failure here.
        return None
    expected_base = f"feat/{source_id}"
    base_branch = source.get("base_branch")
    if isinstance(base_branch, str) and base_branch == expected_base:
        return None
    return (
        DP_FEAT_BASE_REQUIRED_MARKER,
        f"{refinement_json}: dp source {source_id} entering breakdown must declare "
        f"source.base_branch='{expected_base}' (DP-337 delivery-boundary required gate); "
        f"found {base_branch!r}. Backfill the feat-lane base before breakdown handoff.",
    )


# --- D4: delivery-unit shape gate (DP-274) ------------------------------------
# A refinement-owned source that walks breakdown -> engineering -> verify-AC must
# be a real delivery unit (delivery-unit-completion-standard.md D1): it needs at
# least one task that actually changes framework/product behavior
# (task_shape: implementation). Two shapes are NOT delivery units and must
# fail-stop at breakdown / LOCK time:
#
#   - 研究單 (research unit, D2): every task is task_shape: audit and there is no
#     implementation task. The deliverable is a research/audit conclusion with no
#     runtime-verifiable completion standard. -> POLARIS_RESEARCH_UNIT_NO_IMPLEMENTATION
#   - 轉發 / theme 單 (dispatch / theme unit, D3): the source has no implementation
#     task either, but its tasks are confirmation/dispatch shapes (e.g. all
#     confirmation, or an audit+confirmation mix). The deliverable merely dispatches
#     to other concrete delivery units. -> POLARIS_DISPATCH_THEME_UNIT_NO_IMPLEMENTATION
#
# The detection BANKS ON the existing task_shape classifier (parse_task_shape /
# CARVE_OUT_TASK_SHAPES) — it does NOT introduce a second classifier (DP-274 D4).
# The single, sufficient gate is "the source must contain >= 1 implementation
# task". A DP that mixes implementation + audit/confirmation tasks (DP-262
# carve-out) therefore PASSes, because it has at least one implementation task
# (DP-274 AC-NEG1).

RESEARCH_UNIT_MARKER = "POLARIS_RESEARCH_UNIT_NO_IMPLEMENTATION"
DISPATCH_THEME_UNIT_MARKER = "POLARIS_DISPATCH_THEME_UNIT_NO_IMPLEMENTATION"


def validate_delivery_unit_shape(target: Path, files: list[Path]) -> tuple[str, str] | None:
    """Detect research-unit / dispatch-theme-unit shapes at the source level.

    Returns (marker, message) on a contract violation, or None when the source
    is a legitimate delivery unit (>= 1 implementation task) or has no tasks to
    classify. Only runs for a directory target (a refinement-owned source's
    tasks/ surface); a single task.md cannot represent a whole source's shape.
    """
    task_shapes = [parse_task_shape(file) for file in files if task_id_for_file(file) is not None]
    if not task_shapes:
        return None

    if "implementation" in task_shapes:
        # >= 1 implementation task -> legitimate delivery unit (DP-262 carve-out,
        # DP-274 AC-NEG1). No second classifier is consulted.
        return None

    # No implementation task: classify as research vs dispatch/theme purely from
    # the existing task_shape values.
    if all(shape == "audit" for shape in task_shapes):
        return (
            RESEARCH_UNIT_MARKER,
            f"{target}: 研究單 (research unit) — all tasks are task_shape: audit with no "
            f"implementation task; research is a refinement-phase activity and cannot be an "
            f"independent delivery unit. Fold its scope into an implementation DP's refinement "
            f"seed (see .claude/skills/references/delivery-unit-completion-standard.md D2).",
        )

    return (
        DISPATCH_THEME_UNIT_MARKER,
        f"{target}: 轉發 / theme 單 (dispatch / theme unit) — no implementation task; the source "
        f"only dispatches to other concrete delivery units. Rewrite it as a north-star artifact "
        f"(not a delivery DP) with a defined supersede signal "
        f"(see .claude/skills/references/delivery-unit-completion-standard.md D3).",
    )


def table_rows(markdown: str) -> list[list[str]]:
    rows: list[list[str]] = []
    for line in markdown.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|") or "|" not in stripped[1:]:
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if cells and all(re.match(r"^:?-{3,}:?$", cell.replace(" ", "")) for cell in cells):
            continue
        rows.append(cells)
    return rows


def gate_rows(markdown: str) -> dict[str, list[str]]:
    rows = table_rows(markdown)
    if not rows:
        return {}
    header = [cell.lower() for cell in rows[0]]
    gate_idx = next((idx for idx, cell in enumerate(header) if "gate" in cell), 0)
    out: dict[str, list[str]] = {}
    for row in rows[1:]:
        if gate_idx >= len(row):
            continue
        gate = row[gate_idx].strip().lower()
        for required in ("scope", "test", "verify", "ci-local"):
            if gate == required or gate.startswith(f"{required} "):
                out[required] = row
    return out


def has_meaningful_cell(row: list[str], idx: int) -> bool:
    if idx >= len(row):
        return False
    value = row[idx].strip()
    return bool(value and value not in {"-", "--"})


def task_id_for_file(file: Path) -> str | None:
    # T-tasks and V-tasks are both first-class Polaris task ids (DP-371 T2),
    # recognized symmetrically in their flat (T{n}.md / V{n}.md) and folder-native
    # (T{n}/index.md / V{n}/index.md) forms.
    if re.match(r"^[TV][0-9]+[a-z]*\.md$", file.name):
        return file.stem
    if file.name == "index.md" and re.match(r"^[TV][0-9]+[a-z]*$", file.parent.name):
        return file.parent.name
    return None


def is_verification_task(file: Path) -> bool:
    task_id = task_id_for_file(file)
    return bool(task_id and task_id.startswith("V"))


def column_index(header: list[str], *needles: str) -> int | None:
    lowered = [cell.strip().lower() for cell in header]
    for needle in needles:
        for idx, cell in enumerate(lowered):
            if needle in cell:
                return idx
    return None


def split_path_cells(value: str) -> list[str]:
    parts = re.split(r"<br\s*/?>|,|，", value)
    paths: list[str] = []
    for part in parts:
        token = normalize_path_token(part)
        if token and token not in {"-", "--", "N/A", "n/a"}:
            paths.append(token)
    return paths


def path_covered(path: str, allowed: list[str]) -> bool:
    for entry in allowed:
        pattern = normalize_path_token(entry)
        if path == pattern or fnmatch.fnmatch(path, pattern):
            return True
    return False


UI_SURFACE_KEYWORDS = (
    "dashboard",
    "ui",
    "render",
    "visible",
    "page",
    "screen",
    "status",
    "sidebar",
    "畫面",
    "頁面",
    "儀表板",
    "導覽",
    "顯示",
)

RENDER_API_PATTERNS = (
    ".astro",
    ".tsx",
    ".jsx",
    ".vue",
    ".svelte",
    "/pages/",
    "/components/",
    "route",
    "api",
    "endpoint",
    "render",
    "page",
)

PACKAGE_GRAPH_HINTS = (
    "dependency",
    "dependencies",
    "devdependency",
    "devdependencies",
    "package graph",
    "catalog",
    "lockfile",
    "套件",
    "依賴",
)

TEST_RUNNER_RE = re.compile(
    r"("
    r"\b(?:pnpm|npm|yarn|bun)\b[^\n]*(?:\b(?:test|vitest|jest|build|nuxt|playwright|cypress)\b)"
    r"|"
    r"\b(?:vitest|jest|nuxt|playwright|cypress)\b"
    r")",
    re.IGNORECASE,
)


def needs_render_surface(*values: str) -> bool:
    combined = " ".join(values).lower()
    for keyword in UI_SURFACE_KEYWORDS:
        if re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", keyword):
            if keyword in combined:
                return True
        elif re.search(rf"\b{re.escape(keyword)}\b", combined):
            return True
    return False


def has_render_api_surface(owning_files: list[str], surface: str) -> bool:
    combined = " ".join([surface, *owning_files]).lower()
    return any(pattern in combined for pattern in RENDER_API_PATTERNS)


def first_fenced_code(markdown: str) -> str:
    match = re.search(r"```[^\n]*\n(.*?)\n```", markdown, re.DOTALL)
    return match.group(1).strip() if match else ""


def test_environment_field(text: str, label: str) -> str:
    env = section(text, "## Test Environment")
    pattern = re.compile(
        rf"^\s*(?:-\s*)?\*\*{re.escape(label)}\*\*:\s*(.*?)\s*$",
        re.IGNORECASE | re.MULTILINE,
    )
    match = pattern.search(env)
    return match.group(1).strip() if match else ""


def is_na(value: str) -> bool:
    return value.strip().lower() in {"", "n/a", "na", "-", "--", "none"}


def allowed_contains(allowed: list[str], token: str) -> bool:
    return any(normalize_path_token(entry) == token for entry in allowed)


def validate_package_graph_scope(file: Path, text: str, allowed: list[str]) -> list[str]:
    errors: list[str] = []
    normalized_allowed = [normalize_path_token(entry) for entry in allowed]
    touches_pnpm_catalog = "pnpm-workspace.yaml" in normalized_allowed
    touches_package_json = any(entry.endswith("package.json") for entry in normalized_allowed)
    mentions_package_graph = any(hint in text.lower() for hint in PACKAGE_GRAPH_HINTS)

    if (touches_pnpm_catalog or (touches_package_json and mentions_package_graph)) and not allowed_contains(allowed, "pnpm-lock.yaml"):
        errors.append(
            f"{file}: package graph/dependency scope changes require `pnpm-lock.yaml` in Allowed Files, or a documented non-pnpm/no-lockfile decision before READY"
        )

    return errors


def validate_test_environment_consistency(file: Path, text: str) -> list[str]:
    errors: list[str] = []
    test_command = first_fenced_code(section(text, "## Test Command"))
    if not test_command or not TEST_RUNNER_RE.search(test_command):
        return errors

    level = test_environment_field(text, "Level").lower()
    bootstrap = test_environment_field(text, "Env bootstrap command")
    if level == "static":
        errors.append(
            f"{file}: Test Command runs a test/build runner but Test Environment Level=static; declare build/runtime or route baseline/env decision before READY"
        )
    if is_na(bootstrap):
        errors.append(
            f"{file}: Test Command runs a test/build runner but Env bootstrap command is N/A; declare install/bootstrap or route baseline/env decision before READY"
        )

    return errors


def validate_test_command_debug_hygiene(file: Path, text: str) -> list[str]:
    errors: list[str] = []
    test_command = first_fenced_code(section(text, "## Test Command"))
    if not test_command:
        return errors

    command_space = " ".join(test_command.split())
    text_lower = text.lower()
    is_nuxt_vitest_app_command = bool(
        re.search(r"\bnuxt\b", command_space)
        or (re.search(r"\bvitest\b", command_space) and ("apps/main" in command_space or "nuxt" in text_lower))
    )
    clears_debug = bool(re.search(r"\benv\s+-u\s+DEBUG\b", command_space))
    if is_nuxt_vitest_app_command and not clears_debug:
        errors.append(
            f"{file}: Nuxt/Vitest app Test Command must clear inherited DEBUG via `env -u DEBUG ...`; inherited DEBUG can change Nuxt test startup behavior"
        )

    return errors


# --- DP-311 T6 (AC8 / AC-NEG7): Verify/Test Command executability gate ---------
# The ## Verify Command / ## Test Command fenced blocks must be executable bash,
# not prose (the DP-252-T1 plan defect: zh-TW prose copied verbatim into the
# fence, exploding only at the verify gate). The verdict comes from the SHARED
# helper scripts/lib/check-verify-command-executability.sh (bash -n parse +
# outside-quote CJK detection; quoted CJK patterns stay legal) — the same
# judgment derive-task-md-from-refinement-json.sh runs at write time (D9: no
# second copy). A violation is a contract violation: exit 2 with the helper's
# POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE marker, distinct from the generic
# exit-1 readiness FAIL. validate-refinement-lock-preflight.sh inherits this
# gate through its existing delegation to this validator.

VERIFY_COMMAND_NOT_EXECUTABLE_MARKER = "POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE"


def validate_command_executability(file: Path, text: str) -> list[str]:
    """Run the shared executability helper over the Verify/Test Command fences.

    Args:
        file: the task.md under validation (used as the marker label context).
        text: the full task.md text.

    Returns:
        One violation message per non-executable fenced block (empty when both
        fences are absent or executable). A missing helper is itself a
        violation (fail-closed), never a silent skip.
    """
    violations: list[str] = []
    if not check_verify_command_executability.is_file():
        return [
            f"{file}: missing shared executability helper: {check_verify_command_executability}"
        ]
    for heading in ("## Verify Command", "## Test Command"):
        command = first_fenced_code(section(text, heading))
        if not command:
            continue
        proc = subprocess.run(
            ["bash", str(check_verify_command_executability), "--label", f"{file}:{heading}"],
            input=command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if proc.returncode != 0:
            reasons = [
                line for line in (proc.stderr or "").splitlines() if line.strip()
            ]
            detail = "; ".join(reasons[:4]) or "executability helper failed"
            violations.append(
                f"{file}: {heading} fenced block is not executable bash ({detail})"
            )
    return violations


# --- DP-307 T2 (D3 / AC4): branch-name ASCII gate ------------------------------
# A task.md "Task branch" field with any non-ASCII byte ships a CJK/UTF-8 branch
# name into engineering-branch-setup, PR creation, and release tooling. The
# byte-level verdict comes from scripts/validate-branch-name-ascii.sh (the same
# validator usable standalone; no second judgment here). git check-ref-format is
# NOT a substitute — it accepts UTF-8/CJK ref names (AC-NEG5). A violation is a
# contract violation: exit 2 with the validator's POLARIS_BRANCH_NAME_NON_ASCII
# marker, distinct from the generic exit-1 readiness FAIL.

BRANCH_NAME_NON_ASCII_MARKER = "POLARIS_BRANCH_NAME_NON_ASCII"


def task_branch_field(text: str) -> str:
    """Extract the Operational Context "Task branch" value from task.md text.

    Args:
        text: the full task.md text.

    Returns:
        The branch name with surrounding backticks stripped, or "" when the
        row is absent or holds a placeholder (N/A, -, none).
    """
    match = re.search(r"^\|\s*Task branch\s*\|\s*(.*?)\s*\|\s*$", text, re.MULTILINE)
    if not match:
        return ""
    value = match.group(1).strip()
    if value.startswith("`") and value.endswith("`"):
        value = value[1:-1].strip()
    if value.lower() in {"", "n/a", "na", "-", "--", "none"}:
        return ""
    return value


def validate_branch_name_ascii_gate(file: Path, text: str) -> list[tuple[str, str]]:
    """Run the branch-name ASCII validator over the task.md "Task branch" field.

    Args:
        file: the task.md under validation (used in violation messages).
        text: the full task.md text.

    Returns:
        A list of (message, marker_line) violations; empty when the field is
        absent (nothing to certify here — schema gates own field presence) or
        the branch name is pure ASCII. A missing validator script is itself a
        violation (fail-closed), never a silent skip.
    """
    branch = task_branch_field(text)
    if not branch:
        return []
    if not validate_branch_name_ascii.is_file():
        return [
            (
                f"{file}: missing branch-name ASCII validator: {validate_branch_name_ascii}",
                f"{BRANCH_NAME_NON_ASCII_MARKER}:{branch}",
            )
        ]
    proc = subprocess.run(
        ["bash", str(validate_branch_name_ascii), branch],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode == 0:
        return []
    marker = next(
        (
            line.strip()
            for line in (proc.stderr or "").splitlines()
            if line.startswith(BRANCH_NAME_NON_ASCII_MARKER)
        ),
        f"{BRANCH_NAME_NON_ASCII_MARKER}:{branch}",
    )
    return [
        (
            f"{file}: Task branch `{branch}` contains non-ASCII bytes; branch names must be ASCII-only (DP-307 D3)",
            marker,
        )
    ]


# --- DP-328 T2 (AC4 / AC5): branch-identity gate -------------------------------
# A task.md "Task branch" must carry the delivery_ticket_key prefix
# (task/{delivery_ticket_key}-...), NOT the internal composite work_item_id
# marker. For a JIRA-Epic-backed source the work_item_id (e.g. EXCO-700-T2)
# differs from the delivery_ticket_key (the real per-task jira_key, e.g.
# EXCO-712); a branch prefixed with the composite marker (task/EXCO-700-T2-...)
# is an internal task marker identity leak. For a DP-backed source the two atoms
# collapse (delivery_ticket_key == work_item_id == DP-NNN-Tn), so a well-formed
# DP branch never trips this gate (AC-NEG1).
#
# The verdict REUSES scripts/resolve-task-branch.sh validate_branch — the single
# canonical branch-identity rule (AC5). No second prefix/leak implementation
# lives here: this gate only invokes resolve-task-branch.sh per task.md and maps
# its exit-1 (validate_branch rejection, incl. the AC-NEG5 leak) to a contract
# violation (exit 2 + structured marker), distinct from the generic exit-1
# readiness FAIL. Moving the invariant here makes the leak fail at breakdown-ready
# instead of leaking through to engineering-branch-setup (the previous sole
# enforcement point, too late). resolve exit 2 (no identity / parse failure) is
# left to the schema gates that own field presence; this gate does not
# double-report it.

TASK_BRANCH_IDENTITY_LEAK_MARKER = "POLARIS_TASK_BRANCH_IDENTITY_LEAK"


def validate_branch_identity_gate(file: Path, text: str) -> list[tuple[str, str]]:
    """Certify the task.md "Task branch" carries the delivery_ticket_key prefix.

    Reuses scripts/resolve-task-branch.sh validate_branch as the single
    canonical branch-identity rule (DP-328 AC5); no second prefix/leak
    implementation lives here.

    Args:
        file: the task.md under validation (used in violation messages).
        text: the full task.md text; used only to skip when there is no Task
            branch field to certify (schema gates own field presence).

    Returns:
        A list of (message, marker_line) violations; empty when there is no
        Task branch field, the branch passes validate_branch (exit 0), or the
        resolver cannot reach the branch check (exit 2 — a structural problem
        owned by the schema gates, not double-reported here). A missing
        resolver script is itself a violation (fail-closed), never a silent
        skip.
    """
    branch = task_branch_field(text)
    if not branch:
        return []
    if not resolve_task_branch.is_file():
        return [
            (
                f"{file}: missing branch-identity resolver: {resolve_task_branch}",
                f"{TASK_BRANCH_IDENTITY_LEAK_MARKER}:{file}",
            )
        ]
    proc = subprocess.run(
        ["bash", str(resolve_task_branch), str(file)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode == 0:
        return []
    if proc.returncode != 1:
        # exit 2 = task_md not found / parse failure / no identity. The schema
        # gates (validate-task-md) own field presence; do not double-report.
        return []
    detail = "; ".join(
        line.strip() for line in (proc.stderr or "").splitlines() if line.strip()
    )[:240] or "resolve-task-branch.sh validate_branch rejected the Task branch"
    return [
        (
            f"{file}: Task branch `{branch}` fails the canonical branch-identity invariant "
            f"(resolve-task-branch.sh validate_branch): {detail} (DP-328 AC4)",
            f"{TASK_BRANCH_IDENTITY_LEAK_MARKER}:{file}",
        )
    ]


def validate_verify_command_specificity(file: Path, text: str) -> list[str]:
    errors: list[str] = []
    verify_command = first_fenced_code(section(text, "## Verify Command"))
    if not verify_command:
        return errors

    has_broad_moment_grep = bool(
        re.search(
            r"rg\b[^\n]*(['\"])(?:moment-timezone\|moment|moment\|moment-timezone)\1",
            verify_command,
        )
    )
    scans_source = bool(re.search(r"\bapps/main/(?!package\.json)", verify_command))
    scans_dependency_or_bundle = bool(
        re.search(r"\b(package\.json|pnpm-lock\.yaml|pnpm-workspace\.yaml|\.output/|node_modules/moment|/moment@|moment/min|moment/locale)\b", verify_command)
    )
    if has_broad_moment_grep and scans_source and not scans_dependency_or_bundle:
        errors.append(
            f"{file}: Verify Command uses broad `moment-timezone|moment` source grep; use a direct library usage/import pattern so cross-scope prop names/comments do not force out-of-scope edits"
        )

    return errors


def parse_task_json(file: Path) -> dict:
    proc = subprocess.run(
        [str(parse_task_md), str(file), "--no-resolve"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        return {}
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}


def validate_changeset_scope_contract(file: Path, allowed: list[str]) -> list[str]:
    errors: list[str] = []
    data = parse_task_json(file)
    frontmatter = data.get("frontmatter") if isinstance(data, dict) else {}
    deliverables = frontmatter.get("deliverables") if isinstance(frontmatter, dict) else {}
    changeset = deliverables.get("changeset") if isinstance(deliverables, dict) else {}
    if not isinstance(changeset, dict) or not changeset:
        return errors

    slug = str(changeset.get("filename_slug") or "").strip()
    if not slug:
        errors.append(f"{file}: deliverables.changeset declares a changeset but filename_slug is missing")
        return errors

    expected = slug if slug.startswith(".changeset/") else f".changeset/{slug}"
    if not expected.endswith(".md"):
        expected = f"{expected}.md"
    if not path_covered(expected, allowed):
        errors.append(
            f"{file}: deliverables.changeset declares `{expected}` but Allowed Files does not cover it; add `{expected}` or `.changeset/**`"
        )

    return errors


def validate_scope_trace(
    file: Path, text: str, allowed: list[str], allow_uncovered: bool = False
) -> list[str]:
    errors: list[str] = []
    matrix = section(text, "## Scope Trace Matrix")
    if not matrix.strip():
        return [f"{file}: missing non-empty ## Scope Trace Matrix"]

    rows = table_rows(matrix)
    if len(rows) < 2:
        return [f"{file}: Scope Trace Matrix must include at least one trace row"]

    header = rows[0]
    goal_idx = column_index(header, "goal", "ac", "目標")
    owning_idx = column_index(header, "owning", "file", "檔案")
    surface_idx = column_index(header, "surface", "boundary", "介面", "邊界")
    tests_idx = column_index(header, "test", "驗證", "測試")
    missing_columns = [
        name
        for name, idx in (
            ("Goal / AC", goal_idx),
            ("Owning files", owning_idx),
            ("Surface / boundary", surface_idx),
            ("Tests", tests_idx),
        )
        if idx is None
    ]
    if missing_columns:
        errors.append(f"{file}: Scope Trace Matrix missing columns: {', '.join(missing_columns)}")
        return errors

    assert goal_idx is not None
    assert owning_idx is not None
    assert surface_idx is not None
    assert tests_idx is not None
    for row_number, row in enumerate(rows[1:], start=2):
        goal = row[goal_idx].strip() if goal_idx < len(row) else ""
        owning_raw = row[owning_idx].strip() if owning_idx < len(row) else ""
        surface = row[surface_idx].strip() if surface_idx < len(row) else ""
        tests = row[tests_idx].strip() if tests_idx < len(row) else ""
        if not goal or goal in {"-", "--"}:
            errors.append(f"{file}: Scope Trace Matrix row {row_number} must include Goal / AC")
        owning_files = split_path_cells(owning_raw)
        if not owning_files:
            errors.append(f"{file}: Scope Trace Matrix row {row_number} must include owning files")
        if not surface or surface in {"-", "--", "N/A", "n/a"}:
            errors.append(f"{file}: Scope Trace Matrix row {row_number} must include surface/boundary")
        if not tests or tests in {"-", "--", "N/A", "n/a"}:
            errors.append(f"{file}: Scope Trace Matrix row {row_number} must include tests")
        for owning_file in owning_files:
            if not path_token(owning_file):
                errors.append(f"{file}: Scope Trace Matrix row {row_number} owning file is not a path/glob token: {owning_file}")
                continue
            # audit/confirmation carve-out tasks may declare empty/specs-only
            # Allowed Files, so the owning-file coverage check is relaxed for
            # them (DP-262 AC2). implementation tasks keep the strict check.
            if not allow_uncovered and not path_covered(owning_file, allowed):
                errors.append(f"{file}: Scope Trace Matrix row {row_number} owning file is not covered by Allowed Files: {owning_file}")
        if needs_render_surface(goal, surface) and not has_render_api_surface(owning_files, surface):
            errors.append(
                f"{file}: Scope Trace Matrix row {row_number} appears UI/dashboard/API-visible but lacks a render/API surface"
            )

    return errors


def validate_one(file: Path) -> list[str]:
    errors: list[str] = []
    normalized = str(file)
    if "/tasks/pr-release/" in normalized or "/archive/" in normalized:
        return errors
    if task_id_for_file(file) is None:
        return errors

    schema = subprocess.run(
        [str(validate_task_md), str(file)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if schema.returncode != 0:
        errors.append(f"{file}: validate-task-md.sh failed; fix schema before readiness handoff")

    # DP-364 D2 / AC5: V tasks have their own task.md schema. They are validated
    # by validate-task-md.sh above and by validate-task-md-deps.sh in directory
    # mode below; do not run T-task constructability checks such as Allowed Files,
    # Scope Trace Matrix, or Gate Closure Matrix against V task envelopes.
    if is_verification_task(file):
        return errors

    text = file.read_text(encoding="utf-8")

    task_shape = parse_task_shape(file)
    is_carve_out_shape = task_shape in CARVE_OUT_TASK_SHAPES

    allowed = parse_allowed(file)
    # audit/confirmation tasks may legitimately declare empty Allowed Files
    # (their deliverable is evidence/spec, not a tracked code change).
    if not allowed and not is_carve_out_shape:
        errors.append(f"{file}: Allowed Files has no entries")
    for entry in allowed:
        if not path_token(entry):
            errors.append(f"{file}: Allowed Files entry is not a machine-matchable path/glob token: {entry}")

    is_dp_task = "/design-plans/DP-" in normalized or "| source type | dp |" in text.lower()
    if is_dp_task and not is_carve_out_shape:
        non_spec_allowed = [
            entry
            for entry in allowed
            if not normalize_path_token(entry).startswith("docs-manager/src/content/docs/specs/")
        ]
        if allowed and not non_spec_allowed:
            errors.append(
                f"{file}: DP-backed engineering task cannot target only local spec/sample artifacts under docs-manager/src/content/docs/specs; split a tracked releaseable task"
            )

    errors.extend(validate_scope_trace(file, text, allowed, allow_uncovered=is_carve_out_shape))
    errors.extend(validate_package_graph_scope(file, text, allowed))
    errors.extend(validate_test_environment_consistency(file, text))
    errors.extend(validate_test_command_debug_hygiene(file, text))
    errors.extend(validate_verify_command_specificity(file, text))
    errors.extend(validate_changeset_scope_contract(file, allowed))

    matrix = section(text, "## Gate Closure Matrix")
    if not matrix.strip():
        errors.append(f"{file}: missing non-empty ## Gate Closure Matrix")
    else:
        lower = matrix.lower()
        rows = table_rows(matrix)
        header = [cell.lower() for cell in rows[0]] if rows else []
        pass_idx = next((idx for idx, cell in enumerate(header) if "pass condition" in cell or "通過條件" in cell), 2)
        owner_idx = next((idx for idx, cell in enumerate(header) if "owner" in cell or "decision" in cell or "歸屬" in cell or "決策" in cell), 3)
        gates = gate_rows(matrix)
        for gate in ("scope", "test", "verify", "ci-local"):
            row = gates.get(gate)
            if row is None:
                errors.append(f"{file}: Gate Closure Matrix must mention '{gate}' gate")
                continue
            if not has_meaningful_cell(row, pass_idx):
                errors.append(f"{file}: Gate Closure Matrix '{gate}' row must include a pass condition")
            if not has_meaningful_cell(row, owner_idx):
                errors.append(f"{file}: Gate Closure Matrix '{gate}' row must include owner/decision")
        if "n/a" in lower and not re.search(r"n/a.{3,}", lower):
            errors.append(f"{file}: Gate Closure Matrix N/A entries must include a reason")

    return errors


if not target.exists():
    print(f"validate-breakdown-ready: path not found: {target}", file=sys.stderr)
    raise SystemExit(2)

files = task_files(target)


# --- DP-324 T1 (AC1 / AC2 / AC-NEG1): vacuous-pass guard ----------------------
# Without this guard the validator silently printed PASS for two empty inputs:
#   (a) a single-file target whose path does not resolve to a recognized task id
#       (task_id_for_file is None) and is not under tasks/pr-release/ or
#       /archive/ — every per-file check is skipped, so nothing fails.
#   (b) a directory target whose task-file glob yields 0 recognized task files —
#       the per-file loop never runs.
# Both are vacuous passes: the gate certified nothing yet returned exit 0. They
# now fail-closed (exit 2 + POLARIS_VACUOUS_PASS), distinct from the generic
# exit-1 readiness FAIL.
#
# Marker layering: this guard fires ONLY when there is no recognized task to
# certify. It is disjoint from the D4 delivery-unit shape gate below, which fires
# when a directory DOES contain recognized tasks but none is task_shape:
# implementation (research-unit / dispatch-theme-unit). A single-file target
# never reaches the D4 gate (it is dir-only), and the pr-release/archive per-file
# skip is preserved: a recognized task.md under tasks/pr-release/ or /archive/
# resolves to a task id, so it is not "unrecognized" and does not trip the guard
# (it still skips its per-file checks downstream, keeping its prior exit 0).

VACUOUS_PASS_MARKER = "POLARIS_VACUOUS_PASS"


def fail_vacuous_pass(message: str) -> None:
    """Emit the vacuous-pass contract violation and exit 2.

    Args:
        message: the human-readable reason describing the empty input.
    """
    print("validate-breakdown-ready.sh FAIL", file=sys.stderr)
    print(f"  - {message}", file=sys.stderr)
    print(f"{VACUOUS_PASS_MARKER}:{target}", file=sys.stderr)
    raise SystemExit(2)


if target.is_file():
    if "/tasks/pr-release/" not in str(target) and "/archive/" not in str(target):
        if task_id_for_file(target) is None:
            fail_vacuous_pass(
                f"{target}: single-file target does not resolve to a recognized task id "
                f"(expected T{{n}}.md or T{{n}}/index.md) and is not under tasks/pr-release/ "
                f"or /archive/; refusing to certify nothing (DP-324 T1 vacuous-pass guard)."
            )
elif target.is_dir():
    if not any(task_id_for_file(file) is not None for file in files):
        fail_vacuous_pass(
            f"{target}: directory target yielded 0 recognized task files "
            f"(no T{{n}}.md or T{{n}}/index.md after the pr-release/archive exclusion); "
            f"refusing to certify an empty breakdown (DP-324 T1 vacuous-pass guard)."
        )

# D4 (DP-274): source-level delivery-unit shape gate. Runs before the per-task
# readiness checks so a 研究單 / 轉發單 fail-stops with a POLARIS_* marker and
# exit 2 (contract violation), distinct from the generic exit-1 readiness FAIL.
if target.is_dir():
    shape_violation = validate_delivery_unit_shape(target, files)
    if shape_violation is not None:
        marker, message = shape_violation
        print("validate-breakdown-ready.sh FAIL", file=sys.stderr)
        print(f"  - {message}", file=sys.stderr)
        print(f"{marker}:{target}", file=sys.stderr)
        raise SystemExit(2)

# DP-337 T2 (AC3 / AC-NEG3): delivery-boundary feat-base required gate. Runs for
# both directory and single-file targets (the resolver finds the owning source's
# refinement.json either way), so the dp source's feat-lane base is certified at
# the breakdown boundary, not after derive has already produced a main-targeting
# task.md. Like the D4 gate it is a contract violation: exit 2 + POLARIS_* marker.
feat_base_violation = validate_dp_feat_base_required(target)
if feat_base_violation is not None:
    marker, message = feat_base_violation
    print("validate-breakdown-ready.sh FAIL", file=sys.stderr)
    print(f"  - {message}", file=sys.stderr)
    print(f"{marker}:{target}", file=sys.stderr)
    raise SystemExit(2)

all_errors: list[str] = []
# DP-311 T6: executability violations are tracked separately because they are
# contract violations (exit 2 + structured marker), not generic readiness
# failures (exit 1). The skip guards mirror validate_one's own.
executability_violations: list[tuple[Path, str]] = []
# DP-307 T2: branch-name ASCII violations share the contract-violation lane
# (exit 2 + structured marker); each entry carries its own marker line.
branch_name_violations: list[tuple[str, str]] = []
# DP-328 T2: branch-identity violations (composite work_item_id leak) share the
# same contract-violation lane; verdict reuses resolve-task-branch.sh.
branch_identity_violations: list[tuple[str, str]] = []
for file in files:
    all_errors.extend(validate_one(file))
    normalized = str(file)
    if "/tasks/pr-release/" in normalized or "/archive/" in normalized:
        continue
    if task_id_for_file(file) is None:
        continue
    file_text = file.read_text(encoding="utf-8")
    for violation in validate_command_executability(file, file_text):
        executability_violations.append((file, violation))
    branch_name_violations.extend(validate_branch_name_ascii_gate(file, file_text))
    branch_identity_violations.extend(validate_branch_identity_gate(file, file_text))

if target.is_dir() and validate_task_md_deps.exists():
    deps = subprocess.run(
        [str(validate_task_md_deps), str(target)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if deps.returncode != 0:
        all_errors.append(f"{target}: validate-task-md-deps.sh failed; fix dependency closure before readiness handoff")

if all_errors or executability_violations or branch_name_violations or branch_identity_violations:
    print("validate-breakdown-ready.sh FAIL", file=sys.stderr)
    for error in all_errors:
        print(f"  - {error}", file=sys.stderr)
    for _, violation in executability_violations:
        print(f"  - {violation}", file=sys.stderr)
    for message, _ in branch_name_violations:
        print(f"  - {message}", file=sys.stderr)
    for message, _ in branch_identity_violations:
        print(f"  - {message}", file=sys.stderr)
    if executability_violations or branch_name_violations or branch_identity_violations:
        # Contract violation: structured marker + exit 2 (AC8 / DP-307 AC4 /
        # DP-328 AC4); readiness-only failures keep the legacy exit 1.
        for offending_file in dict.fromkeys(file for file, _ in executability_violations):
            print(f"{VERIFY_COMMAND_NOT_EXECUTABLE_MARKER}:{offending_file}", file=sys.stderr)
        for marker in dict.fromkeys(marker for _, marker in branch_name_violations):
            print(marker, file=sys.stderr)
        for marker in dict.fromkeys(marker for _, marker in branch_identity_violations):
            print(marker, file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(1)

print(f"validate-breakdown-ready.sh PASS - {target}")
PY
