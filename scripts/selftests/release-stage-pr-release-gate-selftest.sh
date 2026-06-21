#!/usr/bin/env bash
# Purpose: DP-319 T1 / AC1-AC5 + AC-NEG1-3 — selftest for the pr-release
#          release-stage exemption shared by gate-changeset.sh and
#          gate-pr-title.sh. Reproduces the DP-315 incident: an impl-bearing
#          framework-release bundle whose member task.md files are all finalized
#          into tasks/pr-release/ must NOT be torn apart by the per-task
#          changeset / PR-title contracts, because the bundle delta is
#          legitimately behavioral. The exemption keys off the pr-release task
#          lifecycle POSITION (resolved task path under */tasks/pr-release/*),
#          NOT container archive timing or branch naming.
# Inputs:  none (hermetic tmp git repos + fixture specs trees).
# Outputs: PASS/FAIL lines per scenario; exit 0 (all pass) / 1 (any fail).
# Covers:
#   AC1     fixture A — all members in tasks/pr-release/, behavioral bundle
#           delta -> gate-changeset exit 0 (release-stage exempt, BEFORE the
#           evidence-classifier).
#   AC2     fixture A — chore(release) bundle title -> gate-pr-title exit 0
#           (no [KEY-Tn] required).
#   AC3     fixture B — resolved task in tasks/Tn/ (active), behavioral + no
#           changeset -> gate-changeset exit 2; gate-pr-title still requires
#           [KEY-Tn] (per-task contract intact).
#   AC5     fixture mixed — multi-match bundle where one member is still in
#           tasks/Tn/ -> all-members rule rejects release-stage; gate-changeset
#           falls through and BLOCKS (exit 2).
#   AC-NEG1 the whole suite runs with NO POLARIS_SKIP_* env set; grep the gate
#           sources to confirm no new bypass env branch was introduced.
#   AC-NEG2 the existing gate-changeset-release-bump-selftest.sh stays green
#           (version-only release_bump carve-out untouched) — asserted by
#           re-running it.
#   AC-NEG3 fixture A keeps the container active and uses an arbitrary branch
#           name; grep the gate sources to confirm no archive-state /
#           branch-name heuristic drives release-stage.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE_CHANGESET="$ROOT/scripts/gates/gate-changeset.sh"
GATE_PR_TITLE="$ROOT/scripts/gates/gate-pr-title.sh"
RELEASE_BUMP_SELFTEST="$ROOT/scripts/selftests/gate-changeset-release-bump-selftest.sh"

[[ -f "$GATE_CHANGESET" ]] || { echo "FAIL: missing: $GATE_CHANGESET" >&2; exit 1; }
[[ -f "$GATE_PR_TITLE" ]] || { echo "FAIL: missing: $GATE_PR_TITLE" >&2; exit 1; }

# AC-NEG1 guard: the suite must run without any bypass env set.
if [[ -n "${POLARIS_SKIP_CHANGESET_GATE:-}" || -n "${POLARIS_SKIP_PR_TITLE_GATE:-}" ]]; then
  echo "FAIL: POLARIS_SKIP_* env is set; the exemption must come from pr-release lifecycle, not a bypass." >&2
  exit 1
fi

TMP="$(mktemp -d -t release-stage-pr-release-gate-XXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1" >&2; }

# write_task_md <dest> <task-id> <branch>
# Minimal canonical task.md with an Operational Context table that carries the
# fields gate-pr-title's parse-task-md.sh reads (delivery_ticket_key + summary).
write_task_md() {
  local dest="$1" task_id="$2" branch="$3"
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<MD
---
status: IN_PROGRESS
task_kind: T
---

# ${task_id}: release stage exemption fixture task (3 pt)

> Source: DP-319 | Task: ${task_id} | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task ID | ${task_id} |
| Base branch | main |
| Task branch | ${branch} |

## Allowed Files

- \`scripts/gates/gate-changeset.sh\`
MD
}

# Build a hermetic repo with changeset scaffolding + a behavioral bundle delta on
# HEAD relative to origin/main. The member task.md files live under the given
# tasks subdir layout. Emits the repo path on stdout.
#   $1 = repo name
#   $2 = "pr-release" | "active" | "mixed"
make_bundle_repo() {
  local name="$1" layout="$2"
  local r="$TMP/$name"
  mkdir -p "$r/.changeset" "$r/scripts"
  git -C "$r" init -q -b main
  git -C "$r" config user.email selftest@example.com
  git -C "$r" config user.name Selftest
  echo seed >"$r/README.md"
  printf '3.76.0\n' >"$r/VERSION"
  printf '# changelog\n' >"$r/CHANGELOG.md"
  cat >"$r/package.json" <<'JSON'
{ "name": "polaris-framework-workspace", "version": "3.76.0", "private": true }
JSON
  cat >"$r/.changeset/config.json" <<'JSON'
{ "$schema": "x", "changelog": "@changesets/cli/changelog", "commit": false, "fixed": [], "linked": [], "access": "restricted", "baseBranch": "main", "updateInternalDependencies": "patch", "ignore": [], "privatePackages": {"tag": true} }
JSON
  printf '# Changesets\n' >"$r/.changeset/README.md"
  printf '#!/usr/bin/env bash\necho seed\n' >"$r/scripts/x.sh"

  # Member task.md layout. Branch field uses an arbitrary name (AC-NEG3): the
  # exemption must NOT depend on the branch being called "bundle-*".
  local arb_branch="release/finalize-batch-42"
  case "$layout" in
    pr-release)
      write_task_md "$r/docs-manager/src/content/docs/specs/design-plans/DP-319-x/tasks/pr-release/T1/index.md" "DP-319-T1" "$arb_branch"
      write_task_md "$r/docs-manager/src/content/docs/specs/design-plans/DP-319-x/tasks/pr-release/T2/index.md" "DP-319-T2" "$arb_branch"
      ;;
    active)
      write_task_md "$r/docs-manager/src/content/docs/specs/design-plans/DP-319-x/tasks/T1/index.md" "DP-319-T1" "task/DP-319-T1-active"
      ;;
    mixed)
      write_task_md "$r/docs-manager/src/content/docs/specs/design-plans/DP-319-x/tasks/pr-release/T1/index.md" "DP-319-T1" "$arb_branch"
      write_task_md "$r/docs-manager/src/content/docs/specs/design-plans/DP-319-x/tasks/T2/index.md" "DP-319-T2" "$arb_branch"
      ;;
  esac

  git -C "$r" add -A
  git -C "$r" commit -q -m seed
  git -C "$r" update-ref refs/remotes/origin/main HEAD

  # Behavioral bundle delta on HEAD (a .sh logic change) — the evidence
  # classifier would call this "behavioral", so only the pr-release exemption
  # (which must run BEFORE the classifier) can let it pass.
  printf '#!/usr/bin/env bash\necho behavioral bundle change\n' >"$r/scripts/x.sh"
  git -C "$r" add -A
  git -C "$r" commit -q -m "behavioral bundle delta"
  printf '%s\n' "$r"
}

PRR_BASE="docs-manager/src/content/docs/specs/design-plans/DP-319-x/tasks/pr-release"
ACTIVE_BASE="docs-manager/src/content/docs/specs/design-plans/DP-319-x/tasks"

# ── AC1: all members in pr-release/, behavioral delta -> gate-changeset exit 0 ──
RA="$(make_bundle_repo repoA pr-release)"
set +e
out1="$(bash "$GATE_CHANGESET" --repo "$RA" --task-md "$RA/$PRR_BASE/T1/index.md" 2>&1)"
rc1=$?
set -e
if [[ "$rc1" -eq 0 ]]; then
  ok "AC1 all-pr-release behavioral bundle -> gate-changeset exit 0"
else
  bad "AC1 expected exit 0; got $rc1 | $out1"
fi

# ── AC2: chore(release) bundle title -> gate-pr-title exit 0 (no [KEY-Tn]) ──────
set +e
out2="$(bash "$GATE_PR_TITLE" --repo "$RA" --task-md "$RA/$PRR_BASE/T1/index.md" --title "chore(release): bundle DP-319 -> v3.76.18" 2>&1)"
rc2=$?
set -e
if [[ "$rc2" -eq 0 ]]; then
  ok "AC2 all-pr-release -> gate-pr-title exit 0 (chore release title)"
else
  bad "AC2 expected exit 0; got $rc2 | $out2"
fi

# ── AC3a: active task, behavioral, no changeset -> gate-changeset exit 2 ────────
RB="$(make_bundle_repo repoB active)"
set +e
out3="$(bash "$GATE_CHANGESET" --repo "$RB" --task-md "$RB/$ACTIVE_BASE/T1/index.md" 2>&1)"
rc3=$?
set -e
if [[ "$rc3" -eq 2 ]]; then
  ok "AC3 active task behavioral+no-changeset -> gate-changeset exit 2 (per-task intact)"
else
  bad "AC3 expected exit 2; got $rc3 | $out3"
fi

# ── AC3b: active task -> gate-pr-title still requires [KEY-Tn] ──────────────────
set +e
out3b="$(bash "$GATE_PR_TITLE" --repo "$RB" --task-md "$RB/$ACTIVE_BASE/T1/index.md" --title "chore(release): bundle DP-319 -> v3.76.18" 2>&1)"
rc3b=$?
set -e
if [[ "$rc3b" -eq 2 ]]; then
  ok "AC3 active task -> gate-pr-title rejects chore-release title (per-task [KEY-Tn] required)"
else
  bad "AC3 gate-pr-title expected exit 2 on active task; got $rc3b | $out3b"
fi

# ── AC5: mixed multi-match — one member still in tasks/Tn/ -> NOT release-stage ─
# Resolve by branch (shared arbitrary branch) so both members surface; the
# all-members rule must reject release-stage because T2 is still active.
RC="$(make_bundle_repo repoC mixed)"
# Sanity: confirm the multi-match actually surfaces both members by branch.
set +e
multi="$(bash "$ROOT/scripts/resolve-task-md-by-branch.sh" --scan-root "$RC" "release/finalize-batch-42" 2>/dev/null)"
set -e
multi_count="$(printf '%s\n' "$multi" | grep -c 'index.md' || true)"
if [[ "$multi_count" -ge 2 ]]; then
  ok "AC5 mixed bundle resolves >=2 members by branch (multi-match)"
else
  bad "AC5 multi-match precondition: expected >=2 members; got $multi_count | $multi"
fi
# With no --task-md, the gate resolves by branch (HEAD == release/finalize-batch-42)
# against --repo, surfacing BOTH members so the all-members rule can reject.
git -C "$RC" checkout -q -B "release/finalize-batch-42"
set +e
out5="$(bash "$GATE_CHANGESET" --repo "$RC" 2>&1)"
rc5=$?
set -e
if [[ "$rc5" -eq 2 ]]; then
  ok "AC5 mixed bundle (one member active) -> all-members rule rejects release-stage, gate-changeset exit 2"
else
  bad "AC5 expected exit 2 (fall through); got $rc5 | $out5"
fi

# ── AC-NEG1: no new bypass env branch introduced ───────────────────────────────
neg1_violation=0
for g in "$GATE_CHANGESET" "$GATE_PR_TITLE"; do
  # Allowed pre-existing bypass envs: gate-changeset uses
  # POLARIS_SKIP_CHANGESET_GATE; gate-pr-title uses POLARIS_SKIP_PR_TITLE_GATE.
  # Any OTHER POLARIS_SKIP_* env reference is a new bypass — reject.
  while IFS= read -r tok; do
    case "$tok" in
      POLARIS_SKIP_CHANGESET_GATE|POLARIS_SKIP_PR_TITLE_GATE) ;;
      *) neg1_violation=1; echo "  [FAIL] AC-NEG1 unexpected bypass env: $tok in $(basename "$g")" >&2 ;;
    esac
  done < <(grep -oE 'POLARIS_SKIP_[A-Z_]+' "$g" | sort -u)
done
if [[ "$neg1_violation" -eq 0 ]]; then
  ok "AC-NEG1 no new POLARIS_SKIP_* bypass env added to either gate"
else
  bad "AC-NEG1 a new bypass env was added"
fi

# ── AC-NEG3: no archive-state / branch-name heuristic drives release-stage ──────
# The release-stage code path must not key off archived containers or branch
# names. Reject literal "bundle-" branch-prefix tests or archive-status reads.
neg3_violation=0
for g in "$GATE_CHANGESET" "$GATE_PR_TITLE"; do
  if grep -nE 'bundle-DP|branch == "bundle|=~ \^bundle|/archive/|is_archived|archived_at' "$g" \
     | grep -v 'bundle_branch_alias' >/dev/null 2>&1; then
    neg3_violation=1
    echo "  [FAIL] AC-NEG3 archive/branch-name heuristic detected in $(basename "$g")" >&2
  fi
done
if [[ "$neg3_violation" -eq 0 ]]; then
  ok "AC-NEG3 release-stage keys off pr-release path only (no archive/branch-name heuristic)"
else
  bad "AC-NEG3 archive/branch-name heuristic found"
fi

# ── AC-NEG2: existing release_bump carve-out regression stays green ─────────────
if [[ -f "$RELEASE_BUMP_SELFTEST" ]]; then
  set +e
  rb_out="$(bash "$RELEASE_BUMP_SELFTEST" 2>&1)"
  rb_rc=$?
  set -e
  if [[ "$rb_rc" -eq 0 ]]; then
    ok "AC-NEG2 gate-changeset-release-bump-selftest regression green"
  else
    bad "AC-NEG2 release-bump regression FAILED:\n$rb_out"
  fi
else
  bad "AC-NEG2 missing regression selftest: $RELEASE_BUMP_SELFTEST"
fi

# ── AC4: engineering-branch-setup.sh --aggregate-release bundle prerequisite ───
# (Merged from DP-319 T2.) The bundle branch may only be assembled from task work
# orders already moved into tasks/pr-release/. If ANY --task-md is still in an
# active tasks/Tn/ location, the loop must fail closed (exit non-zero + POLARIS_*
# marker pointing back to finalize-engineering-delivery.sh) rather than torn-apart
# bundling. When every member is under tasks/pr-release/, the bundle is created.
BRANCH_SETUP="$ROOT/scripts/engineering-branch-setup.sh"
if [[ ! -f "$BRANCH_SETUP" ]]; then
  bad "AC4 missing: $BRANCH_SETUP"
else
  ac4_assert() { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (expected='$2' got='$1')"; fi; }
  ac4_assert_contains() { if printf '%s' "$1" | grep -qF "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
  ac4_assert_not_contains() { if printf '%s' "$1" | grep -qF "$2"; then bad "$3 (unexpected '$2')"; else ok "$3"; fi; }

  AC4_TMP="$TMP/ac4"
  mkdir -p "$AC4_TMP"
  AC4_REMOTE="$AC4_TMP/remote.git"
  AC4_LOCAL="$AC4_TMP/local"
  git init --bare "$AC4_REMOTE" >/dev/null 2>&1
  git clone "$AC4_REMOTE" "$AC4_LOCAL" >/dev/null 2>&1
  (
    git -C "$AC4_LOCAL" checkout -b main >/dev/null 2>&1
    echo "init" >"$AC4_LOCAL/file.txt"
    git -C "$AC4_LOCAL" add file.txt && git -C "$AC4_LOCAL" commit -m "init" >/dev/null 2>&1
    git -C "$AC4_LOCAL" push -u origin main >/dev/null 2>&1
  )

  ac4_write_task_md() {
    local dir="$1"
    mkdir -p "$dir"
    cat >"$dir/index.md" <<'TASK'
---
status: IN_PROGRESS
task_kind: T
---

# T1 — fixture task

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework

## Allowed Files

- `scripts/foo.sh`
TASK
    printf '%s\n' "$dir/index.md"
  }

  AC4_SC="$AC4_TMP/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture"
  AC4_ACTIVE_T1="$(ac4_write_task_md "$AC4_SC/tasks/T1")"
  AC4_ACTIVE_T2="$(ac4_write_task_md "$AC4_SC/tasks/T2")"
  AC4_RELEASE_T1="$(ac4_write_task_md "$AC4_SC/tasks/pr-release/T1")"
  AC4_RELEASE_T2="$(ac4_write_task_md "$AC4_SC/tasks/pr-release/T2")"

  ac4_run() { ( cd "$AC4_LOCAL" && env POLARIS_SKIP_BASELINE_SNAPSHOT=1 bash "$BRANCH_SETUP" "$@" 2>&1 ); }

  # Case 1: ANY active (tasks/Tn/) member → fail closed + POLARIS_* marker.
  set +e
  ac4_out="$(ac4_run --aggregate-release --source DP-999 --version v9.9.9 --task-md "$AC4_ACTIVE_T1" --repo-base "$AC4_TMP")"
  ac4_rc=$?
  set -e
  ac4_assert "$ac4_rc" "2" "AC4-C1 active task-md member fails closed (exit 2)"
  ac4_assert_contains "$ac4_out" "POLARIS_" "AC4-C1 emits POLARIS_* marker"
  ac4_assert_contains "$ac4_out" "finalize-engineering-delivery.sh" "AC4-C1 marker points back to finalize"
  if git -C "$AC4_LOCAL" show-ref --verify --quiet refs/heads/bundle-DP-999-v9.9.9; then t="created"; else t="absent"; fi
  ac4_assert "$t" "absent" "AC4-C1 no bundle branch on fail-closed"

  # Case 2: mixed members (one active, one pr-release) → still fail closed.
  set +e
  ac4_out="$(ac4_run --aggregate-release --source DP-999 --version v9.9.8 --task-md "$AC4_RELEASE_T1" --task-md "$AC4_ACTIVE_T2" --repo-base "$AC4_TMP")"
  ac4_rc=$?
  set -e
  ac4_assert "$ac4_rc" "2" "AC4-C2 mixed members fail closed (exit 2)"
  ac4_assert_contains "$ac4_out" "POLARIS_" "AC4-C2 emits POLARIS_* marker"
  if git -C "$AC4_LOCAL" show-ref --verify --quiet refs/heads/bundle-DP-999-v9.9.8; then t="created"; else t="absent"; fi
  ac4_assert "$t" "absent" "AC4-C2 no bundle branch when any member active"

  # Case 3: ALL members under tasks/pr-release/ → normal bundle branch creation.
  set +e
  ac4_out="$(ac4_run --aggregate-release --source DP-999 --version v9.9.7 --task-md "$AC4_RELEASE_T1" --task-md "$AC4_RELEASE_T2" --repo-base "$AC4_TMP")"
  ac4_rc=$?
  set -e
  ac4_assert "$ac4_rc" "0" "AC4-C3 all-pr-release members succeed (exit 0)"
  ac4_assert_not_contains "$ac4_out" "POLARIS_" "AC4-C3 success path emits no fail-closed marker"
  if git -C "$AC4_LOCAL" show-ref --verify --quiet refs/heads/bundle-DP-999-v9.9.7; then t="created"; else t="absent"; fi
  ac4_assert "$t" "created" "AC4-C3 bundle branch created when all members pr-release"
  if grep -q 'bundle_branch_alias: bundle-DP-999-v9.9.7' "$AC4_RELEASE_T1"; then t="written"; else t="missing"; fi
  ac4_assert "$t" "written" "AC4-C3 bundle_branch_alias written into pr-release member"

  ( cd "$AC4_LOCAL" && git worktree prune >/dev/null 2>&1 ) || true
fi

echo ""
echo "[release-stage-pr-release-gate-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
