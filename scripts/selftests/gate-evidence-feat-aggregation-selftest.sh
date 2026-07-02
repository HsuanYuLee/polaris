#!/usr/bin/env bash
# Purpose: Verify gate-evidence.sh feat-aggregation evidence-awareness branch
#          (DP-351 G1) against REAL release state. On a feat/DP-NNN -> main release
#          push, the gate enumerates the DP's canonical tasks/pr-release/ set
#          (worktree-aware via resolve_specs_root) and, for EACH task, reads that
#          task's OWN head_sha from its task.md frontmatter `deliverable.head_sha`
#          (never the aggregated feat HEAD) and resolves a PASS marker bound to
#          that per-task head — either a completion_gate marker (via the existing
#          evidence-classifier marker-pass reader) OR a persistent Layer B verify
#          marker (.polaris/evidence/verify/, exit_code 0). No new evidence file
#          type, no new resolver. All present -> exit 0 with NO POLARIS_SKIP_EVIDENCE;
#          any missing / unresolvable -> fail-closed exit 2 whose message never
#          instructs the operator to set POLARIS_SKIP_EVIDENCE.
# Inputs:  none (self-contained git fixtures under a mktemp workdir).
# Outputs: exit 0 + "PASS" on success; exit 1 + "FAIL (...)" on first failure.
# Side effects: creates/removes temp git repos and markers under $WORKDIR only.
#
# Real-state fidelity (the bug this rewrite catches):
#   Per-task evidence is keyed on each task's OWN PR head_sha — never on the
#   aggregated feat HEAD (the feat SHA never matched any one task's evidence). The
#   previous version of this selftest wrote markers keyed on `git rev-parse HEAD`
#   (= feat HEAD) and so passed 8/8 against a head-binding-bugged gate, modelling a
#   world that never exists at release time. This version keys evidence on distinct
#   per-task heads (recorded in task.md frontmatter) and additionally models that
#   completion-gate markers do NOT persist (worktree-local, gitignored, swept)
#   while verify markers DO persist — the exact shape of the real DP-351 release.
#
# Coverage:
#   IS0  / AC12    PASS:    empty feat/DP-NNN bootstrap branch whose HEAD equals
#                           origin/main and origin/feat/DP-NNN does not yet exist
#                           -> exit 0; this is branch creation, not release
#                           aggregation, so pr-release evidence is not required.
#   IS2  / AC1     PASS:    feat/DP-NNN head; completion-gate ABSENT but every
#                           pr-release task has a persistent PASS verify marker
#                           keyed on that task's OWN frontmatter head_sha
#                           (!= feat HEAD) -> exit 0; run did NOT rely on
#                           POLARIS_SKIP_EVIDENCE; message says feat-aggregation.
#   IS2b / AC-NF1  PASS:    same, but evidence is a completion_gate marker (the
#                           other supported existing marker type) keyed on the
#                           per-task head -> exit 0. Proves both marker types
#                           resolve at the per-task head, not the feat HEAD.
#   IS5  / AC-NEG3 BLOCKED: feat/DP-NNN head but one constituent task has NO marker
#                           at its per-task head -> fail-closed exit 2; stderr does
#                           NOT suggest POLARIS_SKIP_EVIDENCE.
#   ISMH / AC-NEG3 BLOCKED: feat/DP-NNN head but a pr-release task.md carries no
#                           frontmatter deliverable.head_sha (per-task head unknown)
#                           -> fail-closed exit 2 (cannot synthesize a head).
#   IS6  / AC-NEG4 BLOCKED: feat/DP-NNN head but the DP container is unresolvable
#                           (empty pr-release set) -> fail-closed exit 2.
#   AC-NEG1        BLOCKED: head is a per-task branch (task/DP-NNN-Tn-... -> feat),
#                           NOT feat/DP-NNN: aggregation must NOT trigger; the
#                           existing behavioral head-bound-evidence requirement
#                           still fires -> exit 2, and no feat-aggregation message.
#   AC-NEG2a       UNCHANGED: a non-feat behavioral push to main still requires
#                           evidence (exit 2).
#   AC-NEG2b       UNCHANGED: a pure release_bump delta stays exempt (exit 0) via
#                           the existing classifier branch.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-evidence.sh"
WORKDIR="$(mktemp -d -t dp351-gate-evidence-feat-agg.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

# Distinct per-task head SHAs, deliberately != any feat HEAD (a real git commit).
# Evidence is keyed on these; the gate must read them from task.md frontmatter.
PER_T1="1111111111111111111111111111111111111111"
PER_T2="2222222222222222222222222222222222222222"

if [[ ! -x "$GATE" ]]; then
  echo "FAIL: gate is not executable: $GATE" >&2
  exit 1
fi

# run_gate <repo>: invoke the gate against a fixture repo with
# POLARIS_WORKSPACE_ROOT / POLARIS_SPECS_ROOT unset. resolve_specs_root
# short-circuits to those env vars first, so an inherited workspace/specs root
# (e.g. when run under run-verify-command.sh) would otherwise resolve away from
# the fixture and break the worktree-awareness assertions. Unsetting them — and
# never setting POLARIS_SKIP_EVIDENCE — keeps each fixture hermetic and proves
# the feat-aggregation exemption does not lean on the manual skip bypass.
run_gate() {
  local repo="$1"
  (cd "$repo" && env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT -u POLARIS_SKIP_EVIDENCE "$GATE" --repo "$repo")
}

# setup_repo <repo> <branch>: a minimal git repo on <branch> with one commit.
setup_repo() {
  local repo="$1"
  local branch="$2"
  rm -rf "$repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "DP-351 selftest"
  printf 'language: zh-TW\n' >"$repo/workspace-config.yaml"
  git -C "$repo" add -A
  git -C "$repo" -c commit.gpgsign=false commit -q -m "init"
  if [[ "$branch" != "main" ]]; then
    git -C "$repo" checkout -q -b "$branch"
  fi
}

# write_dp_container <repo> <dp> <Tn[=head]...>: emit a DP container under the
# canonical specs path with one tasks/pr-release/<Tn>/index.md per task id (status
# IMPLEMENTED). Each token is `Tn=head` to record that task's own
# deliverable.head_sha in frontmatter; a bare `Tn` (no '=') deliberately omits
# head_sha so the missing-head fail-closed boundary can be exercised. Markers are
# written separately so a fixture can omit one (AC-NEG3).
write_dp_container() {
  local repo="$1"
  local dp="$2"
  shift 2
  local base="$repo/docs-manager/src/content/docs/specs/design-plans"
  local container="$base/${dp}-active-fixture"
  local token tn head
  for token in "$@"; do
    tn="${token%%=*}"
    head="${token#*=}"
    [[ "$head" == "$token" ]] && head=""
    mkdir -p "$container/tasks/pr-release/$tn"
    {
      printf -- '---\n'
      printf 'title: "%s %s"\n' "$dp" "$tn"
      printf 'status: IMPLEMENTED\n'
      printf 'task_kind: T\n'
      printf 'task_shape: implementation\n'
      printf 'deliverable:\n'
      printf '  pr_url: https://example.com/pr/1\n'
      printf '  pr_state: OPEN\n'
      [[ -n "$head" ]] && printf '  head_sha: %s\n' "$head"
      printf -- '---\n\n'
      printf '# %s %s\n\n' "$dp" "$tn"
      printf '| 欄位 | 值 |\n|------|-----|\n| Task ID | %s-%s |\n' "$dp" "$tn"
    } >"$container/tasks/pr-release/$tn/index.md"
  done
  cat >"$container/index.md" <<MD
---
title: "$dp fixture"
status: IMPLEMENTED
---

# $dp
MD
  git -C "$repo" add -A >/dev/null
  git -C "$repo" -c commit.gpgsign=false commit -q -m "$dp pr-release fixture"
}

# write_verify_marker <repo> <dp> <Tn> <head_sha>: write a persistent Layer B
# verify marker at the canonical path the gate's verify-marker fallback consumes
# ($repo/.polaris/evidence/verify/), keyed on {work_item_id}-{head_sha}, exit_code
# 0. This is the marker type that survives in the real DP-351 release (the
# completion-gate dir is worktree-local + gitignored + swept).
write_verify_marker() {
  local repo="$1"
  local dp="$2"
  local tn="$3"
  local head_sha="$4"
  local work_item_id="${dp}-${tn}"
  local marker_dir="$repo/.polaris/evidence/verify"
  mkdir -p "$marker_dir"
  python3 - "$marker_dir/polaris-verified-${work_item_id}-${head_sha}.json" "$work_item_id" "$head_sha" <<'PY'
import json
import sys

out, work_item_id, head_sha = sys.argv[1], sys.argv[2], sys.argv[3]
payload = {
    "ticket": work_item_id,
    "head_sha": head_sha,
    "exit_code": 0,
    "writer": "run-verify-command.sh",
    "level": "static",
}
with open(out, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
PY
}

# write_completion_marker <repo> <dp> <Tn> <head_sha>: DP-360 T7 — the head-sha
# completion_gate marker is retired; the durable delivery-evidence record is the
# task.md `deliverable` block (head_sha + verification.status=PASS), which the
# evidence-classifier marker-pass reader now consumes. This helper patches the
# pr-release task.md to add the `deliverable.verification` PASS sub-block (the
# head is already written by write_dp_container) and re-commits. Used by IS2b to
# prove the task.md deliverable block also resolves at the per-task head — the
# second supported evidence path alongside the Layer B verify marker.
write_completion_marker() {
  local repo="$1"
  local dp="$2"
  local tn="$3"
  local head_sha="$4"  # already recorded in the task.md by write_dp_container
  local task_md="$repo/docs-manager/src/content/docs/specs/design-plans/${dp}-active-fixture/tasks/pr-release/${tn}/index.md"
  TASK_MD="$task_md" python3 - <<'PY'
import os
from pathlib import Path

task_md = Path(os.environ["TASK_MD"])
text = task_md.read_text(encoding="utf-8")
assert text.startswith("---\n"), task_md
end = text.find("\n---\n", 4)
assert end != -1, task_md
# Append the verification PASS sub-block under the existing `deliverable:` key,
# just before the closing frontmatter fence.
block = (
    "  verification:\n"
    "    status: PASS\n"
    "    ac_counts:\n"
    "      ac_total: 1\n"
    "      ac_pass: 1\n"
)
task_md.write_text(text[:end + 1] + block + text[end + 1:], encoding="utf-8")
PY
  git -C "$repo" add -A >/dev/null
  git -C "$repo" -c commit.gpgsign=false commit -q -m "${dp}-${tn} deliverable verification PASS"
}

assert_no_skip_hint() {
  local out_file="$1"
  local label="$2"
  if grep -q 'POLARIS_SKIP_EVIDENCE' "$out_file"; then
    echo "FAIL ($label): fail-closed message must NOT instruct setting POLARIS_SKIP_EVIDENCE" >&2
    cat "$out_file" >&2
    exit 1
  fi
}

# ── IS0 / AC12: empty feat/DP-NNN bootstrap branch, before any task PR lands. ──
repo0="$WORKDIR/is0"
setup_repo "$repo0" "feat/DP-386"
git -C "$repo0" update-ref refs/remotes/origin/main HEAD
set +e
run_gate "$repo0" >"$WORKDIR/is0.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (IS0: empty feat bootstrap branch): expected exit 0, got $rc" >&2
  cat "$WORKDIR/is0.out" >&2
  exit 1
fi
grep -q 'empty feat-aggregation bootstrap branch feat/DP-386' "$WORKDIR/is0.out" || {
  echo "FAIL (IS0): expected empty feat bootstrap branch message" >&2
  cat "$WORKDIR/is0.out" >&2
  exit 1
}
assert_no_skip_hint "$WORKDIR/is0.out" "IS0"

# ── IS2 / AC1: feat/DP-NNN, completion-gate ABSENT, persistent verify markers at
#    per-task heads (!= feat HEAD) → exit 0. This is the real DP-351 release shape.
repo2="$WORKDIR/is2"
setup_repo "$repo2" "feat/DP-210"
write_dp_container "$repo2" "DP-210" "T1=$PER_T1" "T2=$PER_T2"
# Aggregated feat HEAD carries a behavioral delta (the realistic release case). The
# feat-aggregation branch must exempt it via per-task evidence, proving it runs
# BEFORE and independent of the release_bump / metadata_only classifier.
printf '#!/usr/bin/env bash\necho aggregated\n' >"$repo2/aggregated-impl.sh"
git -C "$repo2" add -A
git -C "$repo2" -c commit.gpgsign=false commit -q -m "aggregated behavioral delta"
# Evidence keyed on each task's OWN head, NOT the feat HEAD. completion-gate dir is
# intentionally left absent (models the swept, gitignored real state).
write_verify_marker "$repo2" "DP-210" "T1" "$PER_T1"
write_verify_marker "$repo2" "DP-210" "T2" "$PER_T2"
set +e
run_gate "$repo2" >"$WORKDIR/is2.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (IS2: feat head + per-task verify markers): expected exit 0, got $rc" >&2
  cat "$WORKDIR/is2.out" >&2
  exit 1
fi
grep -q 'feat-aggregation' "$WORKDIR/is2.out" || {
  echo "FAIL (IS2): expected feat-aggregation exemption message" >&2
  cat "$WORKDIR/is2.out" >&2
  exit 1
}
assert_no_skip_hint "$WORKDIR/is2.out" "IS2"

# ── IS2b / AC-NF1: same, but evidence is a completion_gate marker keyed on the
#    per-task head (the other supported existing marker type) → exit 0. ──────────
repo2b="$WORKDIR/is2b"
setup_repo "$repo2b" "feat/DP-220"
write_dp_container "$repo2b" "DP-220" "T1=$PER_T1" "T2=$PER_T2"
printf '#!/usr/bin/env bash\necho aggregated\n' >"$repo2b/aggregated-impl.sh"
git -C "$repo2b" add -A
git -C "$repo2b" -c commit.gpgsign=false commit -q -m "aggregated behavioral delta"
write_completion_marker "$repo2b" "DP-220" "T1" "$PER_T1"
write_completion_marker "$repo2b" "DP-220" "T2" "$PER_T2"
set +e
run_gate "$repo2b" >"$WORKDIR/is2b.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (IS2b: feat head + per-task completion_gate markers): expected exit 0, got $rc" >&2
  cat "$WORKDIR/is2b.out" >&2
  exit 1
fi
grep -q 'feat-aggregation' "$WORKDIR/is2b.out" || {
  echo "FAIL (IS2b): expected feat-aggregation exemption message" >&2
  cat "$WORKDIR/is2b.out" >&2
  exit 1
}
assert_no_skip_hint "$WORKDIR/is2b.out" "IS2b"

# ── IS5 / AC-NEG3: feat/DP-NNN but one task has NO marker at its per-task head ──
repo5="$WORKDIR/is5"
setup_repo "$repo5" "feat/DP-510"
write_dp_container "$repo5" "DP-510" "T1=$PER_T1" "T2=$PER_T2"
printf '#!/usr/bin/env bash\necho aggregated\n' >"$repo5/aggregated-impl.sh"
git -C "$repo5" add -A
git -C "$repo5" -c commit.gpgsign=false commit -q -m "aggregated behavioral delta"
write_verify_marker "$repo5" "DP-510" "T1" "$PER_T1"
# Deliberately omit the T2 marker (no evidence at PER_T2).
set +e
run_gate "$repo5" >"$WORKDIR/is5.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (IS5: feat head + missing constituent marker): expected exit 2, got $rc" >&2
  cat "$WORKDIR/is5.out" >&2
  exit 1
fi
assert_no_skip_hint "$WORKDIR/is5.out" "IS5"

# ── ISMH / AC-NEG3: feat/DP-NNN but a pr-release task.md has no frontmatter
#    deliverable.head_sha (per-task head unknown) → fail-closed exit 2. ──────────
repomh="$WORKDIR/ismh"
setup_repo "$repomh" "feat/DP-530"
# T1 carries a head + verify marker; T2 deliberately omits head_sha (bare token).
write_dp_container "$repomh" "DP-530" "T1=$PER_T1" "T2"
printf '#!/usr/bin/env bash\necho aggregated\n' >"$repomh/aggregated-impl.sh"
git -C "$repomh" add -A
git -C "$repomh" -c commit.gpgsign=false commit -q -m "aggregated behavioral delta"
write_verify_marker "$repomh" "DP-530" "T1" "$PER_T1"
# Even a verify marker at PER_T2 would be unreachable: with no frontmatter head the
# gate cannot know which head to look up, so it must fail closed.
write_verify_marker "$repomh" "DP-530" "T2" "$PER_T2"
set +e
run_gate "$repomh" >"$WORKDIR/ismh.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (ISMH: missing frontmatter head_sha): expected exit 2, got $rc" >&2
  cat "$WORKDIR/ismh.out" >&2
  exit 1
fi
assert_no_skip_hint "$WORKDIR/ismh.out" "ISMH"

# ── IS6 / AC-NEG4: feat/DP-NNN but container unresolvable → fail-closed ────────
repo6="$WORKDIR/is6"
setup_repo "$repo6" "feat/DP-610"
# (intentionally no write_dp_container)
set +e
run_gate "$repo6" >"$WORKDIR/is6.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (IS6: feat head + unresolvable container): expected exit 2, got $rc" >&2
  cat "$WORKDIR/is6.out" >&2
  exit 1
fi
assert_no_skip_hint "$WORKDIR/is6.out" "IS6"

# ── AC-NEG1: per-task branch head (NOT feat/DP-NNN) → aggregation must NOT fire ─
repo1="$WORKDIR/neg1"
setup_repo "$repo1" "task/DP-710-T1-feature"
write_dp_container "$repo1" "DP-710" "T1=$PER_T1"
printf '#!/usr/bin/env bash\necho impl\n' >"$repo1/task-impl.sh"
git -C "$repo1" add -A
git -C "$repo1" -c commit.gpgsign=false commit -q -m "task behavioral change"
# Even with a per-task verify marker present, a task-branch head must not be
# exempted by the feat-aggregation branch (anchored to ^feat/DP-NNN$).
write_verify_marker "$repo1" "DP-710" "T1" "$PER_T1"
set +e
run_gate "$repo1" >"$WORKDIR/neg1.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (AC-NEG1: task-branch head): expected exit 2 (head-bound evidence still required), got $rc" >&2
  cat "$WORKDIR/neg1.out" >&2
  exit 1
fi
if grep -q 'feat-aggregation' "$WORKDIR/neg1.out"; then
  echo "FAIL (AC-NEG1): feat-aggregation exemption must NOT fire for a task-branch head" >&2
  cat "$WORKDIR/neg1.out" >&2
  exit 1
fi

# ── AC-NEG2a: non-feat behavioral push to main still requires evidence ─────────
repo2na="$WORKDIR/neg2a"
setup_repo "$repo2na" "main"
git -C "$repo2na" remote add origin "$repo2na" 2>/dev/null || true
git -C "$repo2na" checkout -q -b "task/ABC-123-feature"
printf '#!/usr/bin/env bash\necho hi\n' >"$repo2na/scripts-change.sh"
git -C "$repo2na" add -A
git -C "$repo2na" -c commit.gpgsign=false commit -q -m "behavioral change"
set +e
run_gate "$repo2na" >"$WORKDIR/neg2a.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (AC-NEG2a: non-feat behavioral push): expected exit 2 (evidence still required), got $rc" >&2
  cat "$WORKDIR/neg2a.out" >&2
  exit 1
fi
if grep -q 'feat-aggregation' "$WORKDIR/neg2a.out"; then
  echo "FAIL (AC-NEG2a): feat-aggregation exemption must NOT fire for a non-feat head" >&2
  cat "$WORKDIR/neg2a.out" >&2
  exit 1
fi

# ── AC-NEG2b: pure release_bump delta stays exempt (existing classifier branch) ─
repo2nb="$WORKDIR/neg2b"
setup_repo "$repo2nb" "main"
printf 'v1.0.0\n' >"$repo2nb/VERSION"
git -C "$repo2nb" add -A
git -C "$repo2nb" -c commit.gpgsign=false commit -q -m "seed VERSION"
git -C "$repo2nb" remote add origin "$repo2nb" 2>/dev/null || true
git -C "$repo2nb" fetch -q origin main 2>/dev/null || true
git -C "$repo2nb" checkout -q -b "task/ABC-456-bump"
printf 'v1.0.1\n' >"$repo2nb/VERSION"
git -C "$repo2nb" add -A
git -C "$repo2nb" -c commit.gpgsign=false commit -q -m "bump VERSION"
set +e
run_gate "$repo2nb" >"$WORKDIR/neg2b.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (AC-NEG2b: release_bump delta): expected exit 0 (still exempt), got $rc" >&2
  cat "$WORKDIR/neg2b.out" >&2
  exit 1
fi
grep -q 'release_bump' "$WORKDIR/neg2b.out" || {
  echo "FAIL (AC-NEG2b): expected release_bump exemption message (existing classifier branch)" >&2
  cat "$WORKDIR/neg2b.out" >&2
  exit 1
}
if grep -q 'feat-aggregation' "$WORKDIR/neg2b.out"; then
  echo "FAIL (AC-NEG2b): release_bump path must not be re-routed through feat-aggregation" >&2
  cat "$WORKDIR/neg2b.out" >&2
  exit 1
fi

echo "PASS"
