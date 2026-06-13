#!/usr/bin/env bash
# resolve-task-md-by-branch.sh
#
# Reverse-lookup: given a git branch name, find the corresponding task.md.
#
# DP-028 Gate layer
# -----------------
# DP-028 ("depends_on branch binding") introduces a three-layer model where
# engineering consumes task.md's `Base branch` / `Task branch` fields to
# validate the resolved Git state before allowing `gh pr create`. Hooks and
# revision-mode logic need to map a branch (what Git exposes) back to a
# task.md (what the gate policy lives in). This helper is that mapping.
#
# Consumed by
#   - scripts/pr-base-gate.sh (PreToolUse gate on `gh pr create`)
#   - skills/references/engineer-delivery-flow.md revision mode (R0 rebase
#     cascade + base-branch sanity check)
#
# Usage
#   resolve-task-md-by-branch.sh <branch-name>
#   resolve-task-md-by-branch.sh --current          # use HEAD's current branch
#   resolve-task-md-by-branch.sh --scan-root <path> <branch-name|--current>
#
# Exit codes
#   0  match found (stdout: absolute path(s), one per line)
#   1  no match    (stderr: scan diagnostics)
#   2  usage error (stderr: usage string)
#
# Matching rule
#   For each specs/**/tasks/T*.md or specs/**/tasks/T*/index.md found under
#   <scan-root>:
#     - extract `Task branch` value from the Operational Context table
#       (format: `| Task branch | <value> |`) and compare string-equal to
#       the input branch; AND
#     - extract `bundle_branch_alias` from the YAML frontmatter (format:
#       `bundle_branch_alias: <value>` inside the leading `---` block) and
#       compare string-equal to the input branch.
#     A task.md matches the query branch if EITHER field equals it.
#   This includes product specs roots (`docs-manager/src/content/docs/specs/companies/{company}/{EPIC}/tasks/`) and
#   framework DP specs roots (`docs-manager/src/content/docs/specs/design-plans/DP-NNN-*/tasks/`).
#
# DP-270 bundle layer
# -------------------
# DP-230's --aggregate-release lane writes a shared `bundle_branch_alias:
# bundle-DP-NNN-vX.Y.Z` into each bundled task.md frontmatter. A bundle-alias
# query (branch == that shared alias) therefore resolves to ALL bundle members
# (multi-match is legal and expected — the release lane consumes the full set).
# A per-task `Task branch` query keeps its original single-match semantics; the
# two matching fields are independent (a per-task Task branch query never
# accidentally widens into a bundle multi-match, and vice versa).
#
# Notes
#   * Excludes .worktrees/, node_modules/, .git/ to avoid duplicate hits
#     from worktree-side specs copies.
#   * If >1 task.md matches the same branch (shouldn't happen in practice;
#     Task branch values are expected to be globally unique), all matches
#     are printed (one per line) and a stderr warning notes that the
#     consumer should take the first line.
#   * Self-test: `RESOLVE_TASK_MD_SELFTEST=1 bash resolve-task-md-by-branch.sh`
#     builds a tmp fixture tree and verifies match / no-match / multi-match
#     by calling the internal scan function directly (no recursive shelling,
#     so it works in sandboxed / fork-limited environments).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"
# shellcheck source=lib/workspace-config-root.sh
. "$SCRIPT_DIR/lib/workspace-config-root.sh"

# resolve_scan_root_source_repo <scan_root>
#   DP-322: clean-worktree specs overlay lookup. When --scan-root points at a
#   worktree whose specs tree is absent (gitignored or rm -rf'd, e.g. a
#   framework-release bundle worktree), resolve the worktree's git common-dir
#   source repo so specs can be found there. Without this, resolve_specs_root's
#   overlay branch falls through to resolve_specs_workspace_root, which honors
#   POLARIS_WORKSPACE_ROOT and resolves the *caller's* workspace (the wrong
#   source tree). Fail-closed: emit nothing and return 1 when git is
#   unavailable, the path is not a git worktree, or the resolved source repo
#   has no specs — the caller then keeps the literal scan root and never falls
#   back to a PWD/env-driven workspace.
#   stdout: absolute source-repo path (only when it contains a specs tree)
#   exit:   0 resolved with specs, 1 otherwise
resolve_scan_root_source_repo() {
  local scan_root="$1"
  local common_dir source_repo
  command -v git >/dev/null 2>&1 || return 1
  common_dir="$(git -C "$scan_root" rev-parse --git-common-dir 2>/dev/null)" || return 1
  [[ -n "$common_dir" ]] || return 1
  # --git-common-dir is relative to scan_root for a linked worktree; the source
  # repo root is the parent of that resolved .git directory.
  if [[ "$common_dir" != /* ]]; then
    common_dir="$(cd "$scan_root" && cd "$common_dir" 2>/dev/null && pwd)" || return 1
  fi
  source_repo="$(cd "$(dirname "$common_dir")" 2>/dev/null && pwd)" || return 1
  [[ -n "$source_repo" ]] || return 1
  [[ -d "$source_repo/docs-manager/src/content/docs/specs" ]] || return 1
  printf '%s\n' "$source_repo"
}

usage() {
  cat >&2 <<'USAGE'
usage: resolve-task-md-by-branch.sh <branch-name>
       resolve-task-md-by-branch.sh --current
       resolve-task-md-by-branch.sh --scan-root <path> <branch-name|--current>
exit: 0 = found (stdout: absolute task.md path(s))
      1 = not found (stderr: scan diagnostics)
      2 = usage error
USAGE
}

# ---------- core: scan and emit -----------------------------------------
# resolve_task_md_scan <root> <branch>
#   stdout: absolute path(s) of matching task.md, one per line
#   stderr: diagnostics (scan count on miss, multi-match warning on dup)
#   exit:   0 found, 1 not found
resolve_task_md_scan() {
  local root="$1"
  local branch="$2"
  local specs_root=""
  local scanned=0
  local -a matches=()
  local f val alias
  specs_root="$(resolve_specs_root "$root")" || return 1

  while IFS= read -r -d '' f; do
    scanned=$((scanned + 1))
    # Extract the `Task branch` value from a markdown table row.
    # Format: `| Task branch | <value> |` (surrounding whitespace tolerated).
    val="$(awk -F'|' '
      /^[[:space:]]*\|[[:space:]]*Task branch[[:space:]]*\|/ {
        v = $3
        sub(/^[[:space:]]+/, "", v)
        sub(/[[:space:]]+$/, "", v)
        print v
        exit
      }
    ' "$f")"

    # DP-270: extract `bundle_branch_alias` from the leading YAML frontmatter
    # block (same parse shape as gate-work-source.sh). A bundle-alias query
    # matches every member sharing the alias.
    alias="$(awk '
      /^---$/ { fm++; next }
      fm == 1 && /^bundle_branch_alias:/ {
        sub(/^bundle_branch_alias:[[:space:]]*/, "")
        sub(/[[:space:]]+$/, "")
        print
        exit
      }
    ' "$f" 2>/dev/null || true)"

    if [[ -n "$val" && "$val" == "$branch" ]] \
      || [[ -n "$alias" && "$alias" == "$branch" ]]; then
      matches+=("$f")
    fi
  done < <(find "$specs_root" \
    \( -type d \( -name .git -o -name .worktrees -o -name node_modules -o -name archive \) -prune \) \
    -o \
    \( -type f \( -path '*/tasks/T*.md' -o -path '*/tasks/T*/index.md' -o -path '*/tasks/pr-release/T*.md' -o -path '*/tasks/pr-release/T*/index.md' \) -print0 \))

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "no task.md matched 'Task branch = $branch' or 'bundle_branch_alias = $branch' (scanned $scanned file(s) under $specs_root)" >&2
    return 1
  fi

  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "warn: multiple matches (${#matches[@]}) for branch '$branch'; consumer should use the first line" >&2
  fi

  local m
  for m in "${matches[@]}"; do
    if [[ "$m" = /* ]]; then
      printf '%s\n' "$m"
    else
      printf '%s\n' "$(cd "$(dirname "$m")" && pwd)/$(basename "$m")"
    fi
  done
  return 0
}

# ---------- self-test ----------------------------------------------------
# Runs the scan function against a tmp fixture tree; no recursive shelling.
if [[ "${RESOLVE_TASK_MD_SELFTEST:-0}" == "1" ]]; then
  set +e
  tmpdir="$(mktemp -d -t resolve-task-md-selftest.XXXXXX)"
  trap 'rm -rf "$tmpdir"' EXIT

  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/EPIC-1/tasks" \
           "$tmpdir/docs-manager/src/content/docs/specs/EPIC-2/tasks/T3" \
           "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-047-framework-work-order-bridge/tasks" \
           "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-048-folder-native-resolver/tasks/T1" \
           "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-099-bundle-fixture/tasks/T1" \
           "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-099-bundle-fixture/tasks/T2" \
           "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-099-bundle-fixture/tasks/T3" \
           "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-7/tasks/pr-release/T1" \
           "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/EPIC-9/tasks" \
           "$tmpdir/.worktrees/shadow/specs/EPIC-1/tasks" \
           "$tmpdir/node_modules/x/specs/EPIC-3/tasks"

  cat > "$tmpdir/docs-manager/src/content/docs/specs/EPIC-1/tasks/T1.md" <<'MD'
# T1
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/FOO-1-alpha |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/EPIC-1/tasks/T2.md" <<'MD'
# T2
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/FOO-2-beta |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/EPIC-2/tasks/T1.md" <<'MD'
# T1
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/BAR-99-gamma |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/EPIC-2/tasks/T3/index.md" <<'MD'
# T3
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/FOLDER-3-delta |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-047-framework-work-order-bridge/tasks/T1.md" <<'MD'
# T1
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/DP-047-T1-framework-bridge |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-048-folder-native-resolver/tasks/T1/index.md" <<'MD'
# T1
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/DP-048-T1-folder-native |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/EPIC-7/tasks/pr-release/T1/index.md" <<'MD'
# T1
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/PR-1-epsilon |
MD

  # DP-270 bundle fixture: three members sharing one bundle_branch_alias in
  # frontmatter, each with its own per-task Task branch in the table.
  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-099-bundle-fixture/tasks/T1/index.md" <<'MD'
---
bundle_branch_alias: bundle-DP-099-v1.0.0
---
# T1
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/DP-099-T1-one |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-099-bundle-fixture/tasks/T2/index.md" <<'MD'
---
bundle_branch_alias: bundle-DP-099-v1.0.0
---
# T2
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/DP-099-T2-two |
MD

  cat > "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-099-bundle-fixture/tasks/T3/index.md" <<'MD'
---
bundle_branch_alias: bundle-DP-099-v1.0.0
---
# T3
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/DP-099-T3-three |
MD

  # Worktree shadow copy — must be ignored by prune.
  cat > "$tmpdir/.worktrees/shadow/specs/EPIC-1/tasks/T1.md" <<'MD'
| Task branch | task/FOO-1-alpha |
MD

  # node_modules shadow copy — must be ignored by prune.
  cat > "$tmpdir/node_modules/x/specs/EPIC-3/tasks/T1.md" <<'MD'
| Task branch | task/FOO-2-beta |
MD

  # Archived copy — must be ignored by default active lookup.
  cat > "$tmpdir/docs-manager/src/content/docs/specs/companies/exampleco/archive/EPIC-9/tasks/T1.md" <<'MD'
| Task branch | task/ARCHIVED-1-only |
MD

  # Duplicate branch binding across legacy + folder-native task sources.
  mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/EPIC-2/tasks/T-dup"
  cat > "$tmpdir/docs-manager/src/content/docs/specs/EPIC-2/tasks/T-dup/index.md" <<'MD'
## Operational Context
| Task branch | task/FOO-1-alpha |
MD

  fail=0
  err_file="$(mktemp)"
  out_file="$(mktemp)"

  run_case() {
    # run_case <label> <branch> <want_rc>; stdout goes to $out_file, stderr to $err_file
    : > "$out_file"; : > "$err_file"
    resolve_task_md_scan "$tmpdir" "$2" >"$out_file" 2>"$err_file"
    local rc=$?
    if [[ $rc -ne $3 ]]; then
      echo "[selftest] $1 exit=$rc (want $3)"; fail=1
    fi
  }

  # Case 1: duplicate match across legacy EPIC-1/T1 and folder-native
  # EPIC-2/T-dup — expect exit 0,
  # both paths in stdout, no .worktrees / node_modules leakage, and a
  # 'multiple matches' stderr warning.
  run_case case1 task/FOO-1-alpha 0
  if ! grep -q 'EPIC-1/tasks/T1.md' "$out_file"; then echo "[selftest] case1 missing EPIC-1/T1"; fail=1; fi
  if ! grep -q 'EPIC-2/tasks/T-dup/index.md' "$out_file"; then echo "[selftest] case1 missing EPIC-2/T-dup"; fail=1; fi
  if grep -q '.worktrees' "$out_file"; then echo "[selftest] case1 leaked .worktrees path"; fail=1; fi
  if grep -q 'node_modules' "$out_file"; then echo "[selftest] case1 leaked node_modules path"; fail=1; fi
  if ! grep -q 'multiple matches' "$err_file"; then
    echo "[selftest] case1 expected 'multiple matches' warning"; fail=1
  fi

  # Case 2: no match → exit 1, empty stdout, 'scanned N' diagnostic on stderr
  run_case case2 task/NOPE-0-zzz 1
  if [[ -s "$out_file" ]]; then echo "[selftest] case2 stdout should be empty"; fail=1; fi
  if ! grep -q 'scanned' "$err_file"; then
    echo "[selftest] case2 expected 'scanned' diagnostic"; fail=1
  fi

  # Case 3: unique match for T2 (node_modules copy must be pruned)
  run_case case3 task/FOO-2-beta 0
  local_count="$(wc -l < "$out_file" | tr -d ' ')"
  if [[ "$local_count" != "1" ]]; then
    echo "[selftest] case3 expected 1 line, got $local_count"; fail=1
  fi
  if ! grep -q 'EPIC-1/tasks/T2.md' "$out_file"; then echo "[selftest] case3 wrong path"; fail=1; fi
  if grep -q 'node_modules' "$out_file"; then echo "[selftest] case3 leaked node_modules path"; fail=1; fi

  # Case 4: folder-native product task root.
  run_case case4 task/FOLDER-3-delta 0
  local_count="$(wc -l < "$out_file" | tr -d ' ')"
  if [[ "$local_count" != "1" ]]; then
    echo "[selftest] case4 expected 1 line, got $local_count"; fail=1
  fi
  if ! grep -q 'EPIC-2/tasks/T3/index.md' "$out_file"; then
    echo "[selftest] case4 missing folder-native product task path"; fail=1
  fi

  # Case 5: folder-native framework DP task root.
  run_case case5 task/DP-048-T1-folder-native 0
  local_count="$(wc -l < "$out_file" | tr -d ' ')"
  if [[ "$local_count" != "1" ]]; then
    echo "[selftest] case5 expected 1 line, got $local_count"; fail=1
  fi
  if ! grep -q 'design-plans/DP-048-folder-native-resolver/tasks/T1/index.md' "$out_file"; then
    echo "[selftest] case5 missing folder-native DP task path"; fail=1
  fi

  # Case 6: folder-native pr-release task root.
  run_case case6 task/PR-1-epsilon 0
  local_count="$(wc -l < "$out_file" | tr -d ' ')"
  if [[ "$local_count" != "1" ]]; then
    echo "[selftest] case6 expected 1 line, got $local_count"; fail=1
  fi
  if ! grep -q 'companies/exampleco/EPIC-7/tasks/pr-release/T1/index.md' "$out_file"; then
    echo "[selftest] case6 missing folder-native pr-release task path"; fail=1
  fi

  # Case 7: archive-only branch is intentionally invisible to active lookup.
  run_case case7 task/ARCHIVED-1-only 1
  if [[ -s "$out_file" ]]; then echo "[selftest] case7 stdout should be empty"; fail=1; fi

  # Case 8 (DP-270 AC2): a bundle_branch_alias query returns ALL members that
  # share that alias (multi-match is legal). Expect exit 0, three member paths,
  # and a 'multiple matches' stderr warning.
  run_case case8 bundle-DP-099-v1.0.0 0
  local_count="$(wc -l < "$out_file" | tr -d ' ')"
  if [[ "$local_count" != "3" ]]; then
    echo "[selftest] case8 expected 3 bundle member lines, got $local_count"; fail=1
  fi
  if ! grep -q 'DP-099-bundle-fixture/tasks/T1/index.md' "$out_file"; then echo "[selftest] case8 missing bundle member T1"; fail=1; fi
  if ! grep -q 'DP-099-bundle-fixture/tasks/T2/index.md' "$out_file"; then echo "[selftest] case8 missing bundle member T2"; fail=1; fi
  if ! grep -q 'DP-099-bundle-fixture/tasks/T3/index.md' "$out_file"; then echo "[selftest] case8 missing bundle member T3"; fail=1; fi
  if ! grep -q 'multiple matches' "$err_file"; then
    echo "[selftest] case8 expected 'multiple matches' warning for bundle"; fail=1
  fi

  # Case 9 (DP-270 AC2 independence): querying a bundle member's per-task Task
  # branch resolves to exactly that one member — the alias multi-match semantic
  # must NOT widen a per-task Task branch query into the whole bundle.
  run_case case9 task/DP-099-T2-two 0
  local_count="$(wc -l < "$out_file" | tr -d ' ')"
  if [[ "$local_count" != "1" ]]; then
    echo "[selftest] case9 expected 1 line for per-task Task branch, got $local_count"; fail=1
  fi
  if ! grep -q 'DP-099-bundle-fixture/tasks/T2/index.md' "$out_file"; then
    echo "[selftest] case9 wrong path for per-task Task branch query"; fail=1
  fi
  if grep -q 'multiple matches' "$err_file"; then
    echo "[selftest] case9 per-task Task branch query must not multi-match"; fail=1
  fi

  rm -f "$out_file" "$err_file"

  if [[ $fail -eq 0 ]]; then
    echo "[selftest] PASS (9 cases)"
    exit 0
  else
    echo "[selftest] FAIL"
    exit 1
  fi
fi

# ---------- arg parsing --------------------------------------------------
scan_root=""
branch=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-root)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      scan_root="$2"
      shift 2
      ;;
    --current)
      if ! command -v git >/dev/null 2>&1; then
        echo "error: --current requires git in PATH" >&2
        exit 2
      fi
      if ! branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
        echo "error: --current: not inside a git repo (or no HEAD)" >&2
        exit 2
      fi
      if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
        echo "error: --current: could not resolve current branch (detached HEAD?)" >&2
        exit 2
      fi
      shift
      ;;
    -h|--help)
      usage
      exit 2
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -n "$branch" ]]; then
        echo "error: unexpected extra argument: $1" >&2
        usage
        exit 2
      fi
      branch="$1"
      shift
      ;;
  esac
done

if [[ -z "$branch" ]]; then
  usage
  exit 2
fi

# ---------- resolve scan root -------------------------------------------
# Priority (DP-028):
#   1) --scan-root <path> (honored verbatim, must exist)
#   2) walk up from $PWD to the HIGHEST dir containing workspace-config.yaml
#      (specs/ can live under the Polaris workspace, above any product-repo .git)
#   3) inside a git worktree (/ product repo): resolve main checkout via
#      `git rev-parse --git-common-dir`, then check if its parent has
#      workspace-config.yaml
#   4) fallback to walk-up first .git-containing dir
if [[ -n "$scan_root" ]]; then
  if [[ ! -d "$scan_root" ]]; then
    echo "error: --scan-root not a directory: $scan_root" >&2
    exit 2
  fi
  root="$(cd "$scan_root" && pwd)"
  # DP-322: when the scan root has no specs of its own (clean worktree), resolve
  # its git common-dir source repo and prefer it so resolve_specs_root finds
  # specs directly instead of falling through to a POLARIS_WORKSPACE_ROOT-driven
  # (wrong) workspace. No-op when the scan root already has specs.
  if [[ ! -d "$root/docs-manager/src/content/docs/specs" ]]; then
    if source_repo="$(resolve_scan_root_source_repo "$root")" && [[ -n "$source_repo" ]]; then
      root="$source_repo"
    fi
  fi
else
  root=""
  if root="$(resolve_workspace_config_root "$(pwd)" 2>/dev/null || true)" && [[ -n "$root" ]]; then
    :
  fi

  if [[ -z "$root" ]]; then
    # Last-resort: walk up for first .git-containing dir (bare git repo case).
    probe="$(pwd)"
    while [[ "$probe" != "/" && -n "$probe" ]]; do
      if [[ -d "$probe/.git" || -f "$probe/.git" ]]; then
        root="$probe"
        break
      fi
      probe="$(dirname "$probe")"
    done
  fi

  if [[ -z "$root" ]]; then
    echo "error: could not locate workspace root (no workspace-config.yaml or .git above \$PWD)" >&2
    exit 1
  fi
fi

# ---------- scan ---------------------------------------------------------
resolve_task_md_scan "$root" "$branch"
