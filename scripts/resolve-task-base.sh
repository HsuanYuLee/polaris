#!/usr/bin/env bash
# resolve-task-base.sh — DP-028 Resolve 層 helper
#
# 用途：讀 task.md 的 Operational Context table 抓 Base branch（必要）與 Depends on（可選），
#       依 DP-028 D2 三層消費模型（snapshot → resolve → gate）之 Resolve 層語意回傳「實際要用的
#       base branch」。engineering 在 § 4.5 / § R0 / § Step 7 用其結果做 rebase / `gh pr create --base`，
#       pr-base-gate.sh 用同樣邏輯在 PreToolUse 驗證 `gh pr create --base` 值是否一致。
#
# 核心語意：
#   - Base branch 非 task/ 開頭（feat/*, develop, main 等）→ 直接回 Base branch 原值。
#   - Base branch 是 task/ 開頭（stacked 情境）→ 沿 Depends on 遞迴找「最終 feat branch」，
#     再用 `git merge-base --is-ancestor <task-branch> <feat-branch>` 判斷：
#       * 已 merged（exit 0）→ stack 已解除，回最終 feat branch（engineering 會改 rebase onto feat）
#       * 未 merged（exit 1）→ 維持 stacked，回原 Base branch
#       * branch 不存在 / 其他 git error → 視為未 merged，回原 Base branch，stderr warn
#
# Usage:
#   resolve-task-base.sh <path/to/task.md>
#
# Exit codes:
#   0 — 成功；stdout 印 resolved base branch（單一字串，無換行額外字元）
#   1 — task.md 格式錯誤 / Base branch 欄位缺失 / 循環依賴
#   2 — usage error / file not found
#
# Self-test:
#   RESOLVE_TASK_BASE_SELFTEST=1 bash resolve-task-base.sh
#
# Consumed by:
#   - engineer-delivery-flow.md § 4.5 (pre-work rebase)
#   - engineer-delivery-flow.md § R0 (revision pre-work rebase)
#   - engineer-delivery-flow.md § Step 7 (PR open — `gh pr create --base`)
#   - scripts/pr-base-gate.sh (PreToolUse hook on `gh pr create`)

set -u

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log_err() {
    printf '[resolve-task-base] %s\n' "$*" >&2
}

# Parse a markdown "| 欄位 | 值 |" table row. Returns the value column.
# Arg 1: field name (exact match, leading/trailing spaces trimmed)
# Arg 2: task.md path
# Output: trimmed value (may be empty if column not found)
parse_table_field() {
    local field="$1"
    local file="$2"
    # Match rows like "| Base branch | feat/... |" — pick first match.
    awk -F '|' -v key="$field" '
        {
            # Skip table header and separator
            if ($0 ~ /^[[:space:]]*\|[[:space:]]*-+/) next
            if (NF < 3) next
            # Trim field column ($2)
            f = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
            if (f == key) {
                v = $3
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                print v
                exit
            }
        }
    ' "$file"
}

# Extract task identity from "Depends on" value.
# Prefer DP pseudo-task IDs before generic JIRA-style keys; otherwise
# DP-049-T1 would be truncated to DP-049 by the generic regex.
extract_task_key() {
    local val="$1"
    local key
    key=$(printf '%s' "$val" | grep -oE 'DP-[0-9]{3}-T[0-9]+[a-z]*' | head -n 1)
    if [ -n "$key" ]; then
        printf '%s' "$key"
        return 0
    fi
    printf '%s' "$val" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1
}

# Parse "Repo: <name>" from task.md header (H1 nearby line like
# "> Epic: GT-478 | JIRA: KB2CW-3711 | Repo: kkday-b2c-web").
parse_repo_name() {
    local file="$1"
    # Look in the first 20 lines.
    head -n 20 "$file" | grep -oE 'Repo:[[:space:]]*[A-Za-z0-9._/-]+' \
        | head -n 1 | sed -E 's/^Repo:[[:space:]]*//'
}

# Given a task.md path, try to derive the git repo path it belongs to.
# Canonical convention: task.md lives under
# {workspace_root}/docs-manager/src/content/docs/specs/.../tasks/T*.md.
# With "Repo: <name>" in header, repo path is {workspace_root}/<name>.
derive_repo_path() {
    local task_md="$1"
    local repo_name
    repo_name=$(parse_repo_name "$task_md")
    if [ -z "$repo_name" ]; then
        return 1
    fi
    # Product tasks live under the canonical docs-manager specs root.
    # DP-backed tasks live under the same specs root at design-plans/<DP>/tasks/.
    # Walk upward to the nearest specs/ ancestor so both shapes resolve without
    # assuming a fixed task path depth.
    local dir specs_dir base_dir
    dir=$(cd "$(dirname "$task_md")" && pwd)
    specs_dir=""
    while [ "$dir" != "/" ]; do
        if [ "$(basename "$dir")" = "specs" ]; then
            specs_dir="$dir"
            break
        fi
        dir=$(dirname "$dir")
    done
    if [ -z "$specs_dir" ]; then
        return 1
    fi
    case "$specs_dir" in
        */docs-manager/src/content/docs/specs)
            base_dir="${specs_dir%/docs-manager/src/content/docs/specs}"
            ;;
        *)
            # Legacy selftests and historical workspaces used {workspace}/specs.
            base_dir=$(dirname "$specs_dir")
            ;;
    esac
    local candidate="$base_dir/$repo_name"
    if [ -d "$candidate/.git" ] || [ -d "$candidate" ]; then
        printf '%s' "$candidate"
        return 0
    fi
    return 1
}

# Find sibling task.md in the same tasks/ dir whose canonical "Task ID" or
# legacy "Task JIRA key" matches the given task identity.
# Arg 1: task key (e.g. KB2CW-3711 or DP-049-T1)
# Arg 2: tasks/ dir
# Output: path to matching T*.md (first match) or empty.
find_task_md_by_key() {
    local key="$1"
    local tasks_dir="$2"
    local candidate value
    # Glob T*.md in active tasks/ first, then tasks/pr-release/ (DP-033 D8 fallback —
    # downstream tasks must still resolve when an upstream has been moved to pr-release/
    # by mark-spec-implemented.sh's move-first sequence).
    shopt -s nullglob
    for candidate in "$tasks_dir"/T*.md "$tasks_dir"/pr-release/T*.md; do
        value=$(parse_table_field "Task ID" "$candidate")
        if [ "$value" = "$key" ]; then
            printf '%s' "$candidate"
            shopt -u nullglob
            return 0
        fi
        value=$(parse_table_field "Task JIRA key" "$candidate")
        if [ "$value" = "$key" ]; then
            printf '%s' "$candidate"
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob
    return 1
}

parse_frontmatter_scalar() {
    local field="$1"
    local file="$2"
    awk -v key="$field" '
        BEGIN { in_fm = 0 }
        NR == 1 && $0 == "---" { in_fm = 1; next }
        in_fm && $0 == "---" { exit }
        in_fm && $0 ~ "^[[:space:]]*" key ":" {
            sub("^[[:space:]]*" key ":[[:space:]]*", "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
            exit
        }
    ' "$file"
}

parse_frontmatter_nested_scalar() {
    local parent="$1"
    local field="$2"
    local file="$3"
    awk -v parent="$parent" -v key="$field" '
        BEGIN { in_fm = 0; in_parent = 0 }
        NR == 1 && $0 == "---" { in_fm = 1; next }
        in_fm && $0 == "---" { exit }
        in_fm && $0 ~ "^[^[:space:]].*:" { in_parent = 0 }
        in_fm && $0 ~ "^" parent ":[[:space:]]*$" { in_parent = 1; next }
        in_fm && in_parent && $0 ~ "^[[:space:]]+" key ":" {
            sub("^[[:space:]]+" key ":[[:space:]]*", "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
            exit
        }
    ' "$file"
}

is_sha_ancestor_of_ref() {
    local repo_dir="$1"
    local sha="$2"
    local ref="$3"

    if [ -z "$sha" ] || [ -z "$ref" ]; then
        return 1
    fi

    if [ -n "$repo_dir" ] && [ -d "$repo_dir" ]; then
        git -C "$repo_dir" rev-parse --verify --quiet "$sha^{commit}" >/dev/null 2>&1 || return 1
        git -C "$repo_dir" rev-parse --verify --quiet "$ref" >/dev/null 2>&1 || return 1
        git -C "$repo_dir" merge-base --is-ancestor "$sha" "$ref" >/dev/null 2>&1
    else
        git rev-parse --verify --quiet "$sha^{commit}" >/dev/null 2>&1 || return 1
        git rev-parse --verify --quiet "$ref" >/dev/null 2>&1 || return 1
        git merge-base --is-ancestor "$sha" "$ref" >/dev/null 2>&1
    fi
}

find_upstream_task() {
    local cur_task="$1"
    local depends_on depends_key tasks_dir upstream
    depends_on=$(parse_table_field "Depends on" "$cur_task")
    if [ -z "$depends_on" ]; then
        return 1
    fi
    depends_key=$(extract_task_key "$depends_on")
    if [ -z "$depends_key" ]; then
        return 1
    fi
    tasks_dir=$(dirname "$cur_task")
    upstream=$(find_task_md_by_key "$depends_key" "$tasks_dir")
    if [ -z "$upstream" ]; then
        return 1
    fi
    printf '%s' "$upstream"
}

# Recursively resolve "final feat branch" by walking depends_on chain.
# Arg 1: starting task.md path
# Arg 2: depth counter (initial 0)
# Output: feat/* branch name
# Returns: 0 on success, 1 on cycle / missing / format error
resolve_final_feat_branch() {
    local cur_task="$1"
    local depth="$2"
    local max_depth=10

    if [ "$depth" -gt "$max_depth" ]; then
        log_err "resolve chain exceeded max depth ($max_depth) at $cur_task — possible cycle"
        return 1
    fi

    local base
    base=$(parse_table_field "Base branch" "$cur_task")
    if [ -z "$base" ]; then
        log_err "no Base branch in $cur_task"
        return 1
    fi

    case "$base" in
        task/*)
            # Need to walk upstream.
            local depends_on depends_key tasks_dir upstream
            depends_on=$(parse_table_field "Depends on" "$cur_task")
            if [ -z "$depends_on" ]; then
                log_err "Base branch is '$base' but no 'Depends on' field in $cur_task (stacked task missing upstream)"
                return 1
            fi
            depends_key=$(extract_task_key "$depends_on")
            if [ -z "$depends_key" ]; then
                log_err "cannot extract task key from Depends on='$depends_on' in $cur_task"
                return 1
            fi
            tasks_dir=$(dirname "$cur_task")
            upstream=$(find_task_md_by_key "$depends_key" "$tasks_dir")
            if [ -z "$upstream" ]; then
                log_err "cannot find upstream task.md for task key $depends_key in $tasks_dir"
                return 1
            fi
            resolve_final_feat_branch "$upstream" $((depth + 1))
            ;;
        *)
            printf '%s' "$base"
            ;;
    esac
}

# Check if branch A is ancestor of B inside repo dir.
# Arg 1: repo dir (may be empty → fallback to $PWD)
# Arg 2: task branch
# Arg 3: feat branch
# Returns:
#   0 — A is ancestor of B (A merged into B)
#   1 — A is not ancestor
#   2 — branches missing / git error
is_merged_into() {
    local repo_dir="$1"
    local task_branch="$2"
    local feat_branch="$3"

    # Avoid bash 3.2 "unbound variable" on empty array expansion with set -u:
    # dispatch to two call variants depending on whether -C is needed.
    if [ -n "$repo_dir" ] && [ -d "$repo_dir" ]; then
        if ! git -C "$repo_dir" rev-parse --verify --quiet "$task_branch" >/dev/null 2>&1; then
            return 2
        fi
        if ! git -C "$repo_dir" rev-parse --verify --quiet "$feat_branch" >/dev/null 2>&1; then
            return 2
        fi
        if git -C "$repo_dir" merge-base --is-ancestor "$task_branch" "$feat_branch" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    else
        if ! git rev-parse --verify --quiet "$task_branch" >/dev/null 2>&1; then
            return 2
        fi
        if ! git rev-parse --verify --quiet "$feat_branch" >/dev/null 2>&1; then
            return 2
        fi
        if git merge-base --is-ancestor "$task_branch" "$feat_branch" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
}

# ---------------------------------------------------------------------------
# Main resolve routine
# ---------------------------------------------------------------------------

resolve_task_base() {
    local task_md="$1"

    if [ ! -f "$task_md" ]; then
        log_err "file not found: $task_md"
        return 2
    fi

    local base
    base=$(parse_table_field "Base branch" "$task_md")
    if [ -z "$base" ]; then
        log_err "Base branch field not found in $task_md"
        return 1
    fi

    # Non-stacked case: return base as-is.
    case "$base" in
        task/*) ;;
        *)
            printf '%s' "$base"
            return 0
            ;;
    esac

    # Stacked case: walk depends_on to final feat branch.
    local task_branch
    task_branch=$(parse_table_field "Task branch" "$task_md")
    if [ -z "$task_branch" ]; then
        log_err "Task branch field missing in $task_md (required to check merge state)"
        return 1
    fi

    local feat_branch
    if ! feat_branch=$(resolve_final_feat_branch "$task_md" 0); then
        # resolve_final_feat_branch already logged.
        return 1
    fi

    # Derive repo dir for merge-base check.
    local repo_dir=""
    if repo_dir=$(derive_repo_path "$task_md"); then
        :
    else
        log_err "cannot derive repo path from $task_md (no 'Repo:' header or dir missing); falling back to \$PWD git"
        repo_dir=""
    fi

    # The upstream task's Base branch (task/...) — we need the upstream task_branch
    # to check merge state, not our own task_branch. Our Base branch IS the upstream task_branch.
    local upstream_task_branch="$base"
    local upstream_task=""
    upstream_task=$(find_upstream_task "$task_md" || true)

    is_merged_into "$repo_dir" "$upstream_task_branch" "$feat_branch"
    local rc=$?
    case "$rc" in
        0)
            # Upstream task is merged into feat → stack resolved; rebase onto feat.
            printf '%s' "$feat_branch"
            return 0
            ;;
        1)
            # Still stacked.
            printf '%s' "$base"
            return 0
            ;;
        2)
            # Local-extension framework tasks may move their upstream task.md to
            # tasks/pr-release/ without leaving a pushed task branch. In that
            # case, trust the recorded completion SHA only if it is already
            # contained by the final base branch.
            if [ -n "$upstream_task" ]; then
                local upstream_status upstream_head
                upstream_status=$(parse_frontmatter_scalar "status" "$upstream_task")
                upstream_head=$(parse_frontmatter_nested_scalar "extension_deliverable" "task_head_sha" "$upstream_task")
                if [ "$upstream_status" = "IMPLEMENTED" ] && is_sha_ancestor_of_ref "$repo_dir" "$upstream_head" "$feat_branch"; then
                    printf '%s' "$feat_branch"
                    return 0
                fi
            fi
            log_err "warn: cannot verify merge state (branch missing or git error) for $upstream_task_branch vs $feat_branch in repo='${repo_dir:-$PWD}'; assuming not merged"
            printf '%s' "$base"
            return 0
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

run_selftest() {
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    local fails=0
    local pass=0

    # Case 1: Base branch is feat/* — return as-is.
    mkdir -p "$tmpdir/case1/tasks"
    cat >"$tmpdir/case1/tasks/T1.md" <<'EOF'
# T1: case 1

> Epic: DEMO-1 | JIRA: DEMO-100 | Repo: nonexistent-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-100 |
| Base branch | feat/DEMO-1-demo |
| Task branch | task/DEMO-100-demo |
EOF
    local out rc
    out=$(resolve_task_base "$tmpdir/case1/tasks/T1.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "0" ] && [ "$out" = "feat/DEMO-1-demo" ]; then
        echo "PASS case1: non-stacked feat/* returns as-is"
        pass=$((pass + 1))
    else
        echo "FAIL case1: expected 'feat/DEMO-1-demo' exit 0, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 2: Base branch is develop — return as-is.
    cat >"$tmpdir/case1/tasks/T2.md" <<'EOF'
# T2: case 2

> Repo: nonexistent-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-200 |
| Base branch | develop |
| Task branch | task/DEMO-200-demo |
EOF
    out=$(resolve_task_base "$tmpdir/case1/tasks/T2.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "0" ] && [ "$out" = "develop" ]; then
        echo "PASS case2: non-stacked develop returns as-is"
        pass=$((pass + 1))
    else
        echo "FAIL case2: expected 'develop' exit 0, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 3: Missing Base branch field → exit 1.
    cat >"$tmpdir/case1/tasks/T3.md" <<'EOF'
# T3: case 3

> Repo: nonexistent-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-300 |
| Task branch | task/DEMO-300-demo |
EOF
    out=$(resolve_task_base "$tmpdir/case1/tasks/T3.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "1" ]; then
        echo "PASS case3: missing Base branch → exit 1"
        pass=$((pass + 1))
    else
        echo "FAIL case3: expected exit 1, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 4: File not found → exit 2.
    out=$(resolve_task_base "$tmpdir/case1/tasks/nonexistent.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "2" ]; then
        echo "PASS case4: missing file → exit 2"
        pass=$((pass + 1))
    else
        echo "FAIL case4: expected exit 2, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 5: Stacked task/* with upstream feat/* but branches don't exist —
    # should fallback (rc=2 from is_merged_into), warn, and echo original base.
    cat >"$tmpdir/case1/tasks/T4.md" <<'EOF'
# T4: case 5 upstream

> Repo: nonexistent-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-400 |
| Base branch | feat/DEMO-1-demo |
| Task branch | task/DEMO-400-upstream |
EOF
    cat >"$tmpdir/case1/tasks/T5.md" <<'EOF'
# T5: case 5 downstream (stacked on T4)

> Repo: nonexistent-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-500 |
| Base branch | task/DEMO-400-upstream |
| Task branch | task/DEMO-500-downstream |
| Depends on | DEMO-400 (T4 — ...) |
EOF
    out=$(resolve_task_base "$tmpdir/case1/tasks/T5.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "0" ] && [ "$out" = "task/DEMO-400-upstream" ]; then
        echo "PASS case5: stacked + missing git branches → fallback to original base"
        pass=$((pass + 1))
    else
        echo "FAIL case5: expected 'task/DEMO-400-upstream' exit 0, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 6: Stacked task/* with no Depends on → exit 1.
    cat >"$tmpdir/case1/tasks/T6.md" <<'EOF'
# T6: case 6 stacked without depends_on

> Repo: nonexistent-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-600 |
| Base branch | task/DEMO-000-missing |
| Task branch | task/DEMO-600-demo |
EOF
    out=$(resolve_task_base "$tmpdir/case1/tasks/T6.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "1" ]; then
        echo "PASS case6: stacked without Depends on → exit 1"
        pass=$((pass + 1))
    else
        echo "FAIL case6: expected exit 1, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 7: Stacked + merged upstream (simulated via real git repo).
    local repo="$tmpdir/case7-repo"
    mkdir -p "$repo"
    git -C "$repo" init -q -b develop
    git -C "$repo" config user.email "self-test@example.com"
    git -C "$repo" config user.name "self-test"
    echo "initial" >"$repo/file.txt"
    git -C "$repo" add file.txt
    git -C "$repo" commit -q -m "initial"
    # feat branch
    git -C "$repo" checkout -q -b feat/DEMO-1-demo
    echo "feat-work" >>"$repo/file.txt"
    git -C "$repo" commit -q -am "feat work"
    # upstream task branch (will be merged into feat)
    git -C "$repo" checkout -q -b task/DEMO-400-upstream
    echo "upstream-task" >>"$repo/file.txt"
    git -C "$repo" commit -q -am "upstream task"
    # merge back into feat
    git -C "$repo" checkout -q feat/DEMO-1-demo
    git -C "$repo" merge -q --no-ff task/DEMO-400-upstream -m "merge upstream"

    # Create T7 pointing at this repo.
    local case7_specs="$tmpdir/case7-specs"
    mkdir -p "$case7_specs/DEMO-1/tasks"
    local repo_name="case7-repo"
    # derive_repo_path expects {base_dir}/<repo_name>; make symlink in sibling of specs.
    mkdir -p "$tmpdir/case7-base"
    ln -s "$repo" "$tmpdir/case7-base/$repo_name"
    # Also move specs tree under case7-base.
    mv "$case7_specs" "$tmpdir/case7-base/specs"
    case7_specs="$tmpdir/case7-base/specs"

    cat >"$case7_specs/DEMO-1/tasks/T4.md" <<EOF
# T4 upstream

> Repo: $repo_name

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-400 |
| Base branch | feat/DEMO-1-demo |
| Task branch | task/DEMO-400-upstream |
EOF
    cat >"$case7_specs/DEMO-1/tasks/T5.md" <<EOF
# T5 downstream

> Repo: $repo_name

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-500 |
| Base branch | task/DEMO-400-upstream |
| Task branch | task/DEMO-500-downstream |
| Depends on | DEMO-400 (T4 — ...) |
EOF
    out=$(resolve_task_base "$case7_specs/DEMO-1/tasks/T5.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "0" ] && [ "$out" = "feat/DEMO-1-demo" ]; then
        echo "PASS case7: stacked + upstream merged → return final feat branch"
        pass=$((pass + 1))
    else
        echo "FAIL case7: expected 'feat/DEMO-1-demo' exit 0, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 8: Stacked + upstream NOT merged into feat → keep original base.
    local repo8="$tmpdir/case8-repo"
    mkdir -p "$repo8"
    git -C "$repo8" init -q -b develop
    git -C "$repo8" config user.email "self-test@example.com"
    git -C "$repo8" config user.name "self-test"
    echo "init" >"$repo8/f.txt"
    git -C "$repo8" add f.txt && git -C "$repo8" commit -q -m init
    git -C "$repo8" checkout -q -b feat/DEMO-2-demo
    echo "feat" >>"$repo8/f.txt" && git -C "$repo8" commit -q -am feat
    git -C "$repo8" checkout -q -b task/DEMO-800-upstream
    echo "task" >>"$repo8/f.txt" && git -C "$repo8" commit -q -am task
    # Do NOT merge back into feat.

    local case8_base="$tmpdir/case8-base"
    mkdir -p "$case8_base"
    ln -s "$repo8" "$case8_base/case8-repo"
    mkdir -p "$case8_base/specs/DEMO-2/tasks"
    cat >"$case8_base/specs/DEMO-2/tasks/T1.md" <<'EOF'
# T1 upstream

> Repo: case8-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-800 |
| Base branch | feat/DEMO-2-demo |
| Task branch | task/DEMO-800-upstream |
EOF
    cat >"$case8_base/specs/DEMO-2/tasks/T2.md" <<'EOF'
# T2 downstream

> Repo: case8-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-900 |
| Base branch | task/DEMO-800-upstream |
| Task branch | task/DEMO-900-downstream |
| Depends on | DEMO-800 (T1 — ...) |
EOF
    out=$(resolve_task_base "$case8_base/specs/DEMO-2/tasks/T2.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "0" ] && [ "$out" = "task/DEMO-800-upstream" ]; then
        echo "PASS case8: stacked + upstream not merged → keep original base"
        pass=$((pass + 1))
    else
        echo "FAIL case8: expected 'task/DEMO-800-upstream' exit 0, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 9: Stacked + upstream task.md moved to tasks/pr-release/ (DP-033 D8 fallback).
    # find_task_md_by_jira must locate the upstream via pr-release/ glob; with no real
    # git repo, is_merged_into returns rc=2 → fallback to original base.
    mkdir -p "$tmpdir/case1/tasks/pr-release"
    cat >"$tmpdir/case1/tasks/pr-release/T7.md" <<'EOF'
# T7 upstream — moved to pr-release/

> Repo: nonexistent-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-700 |
| Base branch | feat/DEMO-7-demo |
| Task branch | task/DEMO-700-upstream |
EOF
    cat >"$tmpdir/case1/tasks/T8.md" <<'EOF'
# T8 downstream stacked on T7 (which is in pr-release/)

> Repo: nonexistent-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DEMO-800 |
| Base branch | task/DEMO-700-upstream |
| Task branch | task/DEMO-800-downstream |
| Depends on | DEMO-700 (T7 — ...) |
EOF
    out=$(resolve_task_base "$tmpdir/case1/tasks/T8.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "0" ] && [ "$out" = "task/DEMO-700-upstream" ]; then
        echo "PASS case9: upstream in tasks/pr-release/ → resolved + fallback to original base"
        pass=$((pass + 1))
    else
        echo "FAIL case9: expected 'task/DEMO-700-upstream' exit 0, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 10: DP pseudo-task dependency + upstream completed by local extension.
    # The upstream branch is absent, but its recorded task_head_sha is already
    # contained by main, so the stack resolves to main.
    local repo10="$tmpdir/case10-base/polaris-framework"
    mkdir -p "$repo10"
    git -C "$repo10" init -q -b main
    git -C "$repo10" config user.email "self-test@example.com"
    git -C "$repo10" config user.name "self-test"
    echo "init" >"$repo10/f.txt"
    git -C "$repo10" add f.txt && git -C "$repo10" commit -q -m init
    echo "t1" >>"$repo10/f.txt" && git -C "$repo10" commit -q -am "DP-049-T1"
    local t1_sha
    t1_sha=$(git -C "$repo10" rev-parse HEAD)

    mkdir -p "$tmpdir/case10-base/specs/design-plans/DP-049-demo/tasks/pr-release"
    cat >"$tmpdir/case10-base/specs/design-plans/DP-049-demo/tasks/pr-release/T1.md" <<EOF
---
extension_deliverable:
  endpoint: local_extension
  extension_id: framework-release
  task_head_sha: $t1_sha
status: IMPLEMENTED
---
# T1 upstream

> Epic: DP-049 | JIRA: DP-049-T1 | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-049-T1 |
| Base branch | main |
| Task branch | task/DP-049-T1-release-clean-source-gate |
EOF
    cat >"$tmpdir/case10-base/specs/design-plans/DP-049-demo/tasks/T2.md" <<'EOF'
# T2 downstream

> Epic: DP-049 | JIRA: DP-049-T2 | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-049-T2 |
| Base branch | task/DP-049-T1-release-clean-source-gate |
| Task branch | task/DP-049-T2-mechanism-registry-priority-audit |
| Depends on | DP-049-T1 (T1 — release clean-source gate) |
EOF
    out=$(resolve_task_base "$tmpdir/case10-base/specs/design-plans/DP-049-demo/tasks/T2.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "0" ] && [ "$out" = "main" ]; then
        echo "PASS case10: DP completed upstream local extension → return final base"
        pass=$((pass + 1))
    else
        echo "FAIL case10: expected 'main' exit 0, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Case 11: Same DP shape under the canonical docs-manager specs root.
    local case11_base="$tmpdir/case11-base"
    local repo11="$case11_base/polaris-framework"
    mkdir -p "$repo11"
    git -C "$repo11" init -q -b main
    git -C "$repo11" config user.email "self-test@example.com"
    git -C "$repo11" config user.name "self-test"
    echo "init" >"$repo11/f.txt"
    git -C "$repo11" add f.txt && git -C "$repo11" commit -q -m init
    echo "t1" >>"$repo11/f.txt" && git -C "$repo11" commit -q -am "DP-066-T1"
    local t11_sha
    t11_sha=$(git -C "$repo11" rev-parse HEAD)

    mkdir -p "$case11_base/docs-manager/src/content/docs/specs/design-plans/DP-066-demo/tasks/pr-release"
    cat >"$case11_base/docs-manager/src/content/docs/specs/design-plans/DP-066-demo/tasks/pr-release/T1.md" <<EOF
---
title: "T1: canonical root upstream"
extension_deliverable:
  endpoint: local_extension
  extension_id: framework-release
  task_head_sha: $t11_sha
status: IMPLEMENTED
---
# T1 upstream

> Epic: DP-066 | JIRA: DP-066-T1 | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-066-T1 |
| Base branch | main |
| Task branch | task/DP-066-T1-canonical-root |
EOF
    cat >"$case11_base/docs-manager/src/content/docs/specs/design-plans/DP-066-demo/tasks/T2.md" <<'EOF'
---
title: "T2: canonical root downstream"
---
# T2 downstream

> Epic: DP-066 | JIRA: DP-066-T2 | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | DP-066-T2 |
| Base branch | task/DP-066-T1-canonical-root |
| Task branch | task/DP-066-T2-downstream |
| Depends on | DP-066-T1 (T1 — canonical root upstream) |
EOF
    out=$(resolve_task_base "$case11_base/docs-manager/src/content/docs/specs/design-plans/DP-066-demo/tasks/T2.md" 2>/dev/null)
    rc=$?
    if [ "$rc" = "0" ] && [ "$out" = "main" ]; then
        echo "PASS case11: canonical docs-manager specs root resolves workspace repo"
        pass=$((pass + 1))
    else
        echo "FAIL case11: expected 'main' exit 0, got '$out' exit $rc"
        fails=$((fails + 1))
    fi

    # Summary
    echo ""
    echo "self-test: $pass passed, $fails failed"
    if [ "$fails" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if [ "${RESOLVE_TASK_BASE_SELFTEST:-0}" = "1" ]; then
    run_selftest
    exit $?
fi

if [ "$#" -ne 1 ]; then
    echo "usage: resolve-task-base.sh <path/to/task.md>" >&2
    exit 2
fi

resolve_task_base "$1"
exit $?
