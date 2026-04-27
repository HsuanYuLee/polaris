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
#   For each specs/**/tasks/T*.md found under <scan-root>:
#     extract `Task branch` value from the Operational Context table
#     (format: `| Task branch | <value> |`) and compare string-equal to
#     the input branch.
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
  local scanned=0
  local -a matches=()
  local f val

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

    if [[ -n "$val" && "$val" == "$branch" ]]; then
      matches+=("$f")
    fi
  done < <(find "$root" \
    \( -type d \( -name .git -o -name .worktrees -o -name node_modules \) -prune \) \
    -o \
    \( -type f -name 'T*.md' \( -path '*/specs/*/tasks/*.md' -o -path '*/specs/*/tasks/complete/*.md' \) -print0 \))

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "no task.md matched 'Task branch = $branch' (scanned $scanned file(s) under $root)" >&2
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

  mkdir -p "$tmpdir/specs/EPIC-1/tasks" "$tmpdir/specs/EPIC-2/tasks" \
           "$tmpdir/.worktrees/shadow/specs/EPIC-1/tasks" \
           "$tmpdir/node_modules/x/specs/EPIC-3/tasks"

  cat > "$tmpdir/specs/EPIC-1/tasks/T1.md" <<'MD'
# T1
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/FOO-1-alpha |
MD

  cat > "$tmpdir/specs/EPIC-1/tasks/T2.md" <<'MD'
# T2
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/FOO-2-beta |
MD

  cat > "$tmpdir/specs/EPIC-2/tasks/T1.md" <<'MD'
# T1
## Operational Context
| 欄位 | 值 |
|------|-----|
| Task branch | task/BAR-99-gamma |
MD

  # Worktree shadow copy — must be ignored by prune.
  cat > "$tmpdir/.worktrees/shadow/specs/EPIC-1/tasks/T1.md" <<'MD'
| Task branch | task/FOO-1-alpha |
MD

  # node_modules shadow copy — must be ignored by prune.
  cat > "$tmpdir/node_modules/x/specs/EPIC-3/tasks/T1.md" <<'MD'
| Task branch | task/FOO-2-beta |
MD

  # Duplicate branch binding across Epics (multi-match case).
  cat > "$tmpdir/specs/EPIC-2/tasks/T-dup.md" <<'MD'
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

  # Case 1: duplicate match across EPIC-1/T1 and EPIC-2/T-dup — expect exit 0,
  # both paths in stdout, no .worktrees / node_modules leakage, and a
  # 'multiple matches' stderr warning.
  run_case case1 task/FOO-1-alpha 0
  if ! grep -q 'EPIC-1/tasks/T1.md' "$out_file"; then echo "[selftest] case1 missing EPIC-1/T1"; fail=1; fi
  if ! grep -q 'EPIC-2/tasks/T-dup.md' "$out_file"; then echo "[selftest] case1 missing EPIC-2/T-dup"; fail=1; fi
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

  rm -f "$out_file" "$err_file"

  if [[ $fail -eq 0 ]]; then
    echo "[selftest] PASS (3 cases)"
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
else
  root=""
  probe="$(pwd)"
  while [[ "$probe" != "/" && -n "$probe" ]]; do
    if [[ -f "$probe/workspace-config.yaml" ]]; then
      root="$probe"  # keep walking: outermost workspace-config.yaml wins
    fi
    probe="$(dirname "$probe")"
  done

  if [[ -z "$root" ]] && command -v git >/dev/null 2>&1; then
    # Worktree / product-repo case: locate main checkout via git-common-dir,
    # then check its parent for workspace-config.yaml.
    if gc="$(git rev-parse --git-common-dir 2>/dev/null)" && [[ -n "$gc" ]]; then
      [[ "$gc" = /* ]] || gc="$(pwd)/$gc"
      gc_abs="$(cd "$gc" 2>/dev/null && pwd || true)"
      if [[ -n "$gc_abs" ]]; then
        main_checkout="$(dirname "$gc_abs")"
        # Walk up from main checkout looking for workspace-config.yaml
        p2="$main_checkout"
        while [[ "$p2" != "/" && -n "$p2" ]]; do
          if [[ -f "$p2/workspace-config.yaml" ]]; then
            root="$p2"
            break
          fi
          p2="$(dirname "$p2")"
        done
      fi
    fi
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
