#!/usr/bin/env bash
# Purpose: Detect DP closeout drift — active LOCKED design plans whose delivery
#          evidence (task.md deliverable block / merged PR / CHANGELOG) shows the
#          work shipped but the spec container was never archived (delivered
#          drift), or that have been LOCKED with zero delivery evidence past a
#          staleness threshold (stranded). High-confidence delivered drift is
#          closed out through the EXISTING scripts/mark-spec-implemented.sh
#          writer (flip IMPLEMENTED + archive); everything else is report-only.
#          PR evidence is scoped with `in:title` so only a DP's own delivery /
#          bundle PR counts (not body cross-references), and any OPEN title-PR
#          forces an in-flight classification (a DP with open delivery PRs — incl.
#          stacked, partly-merged — is never closed out).
# Inputs:  [--workspace <path>]      workspace root (default: resolved specs root)
#          [--json]                  emit machine-readable JSON report to stdout
#          [--stranded-days <N>]     LOCKED-without-evidence age threshold
#                                    (default 14; env CLOSEOUT_DRIFT_STRANDED_DAYS)
#          [--apply | --dry-run]     --apply (default) runs mark-spec-implemented
#                                    on high-confidence drift; --dry-run reports
#                                    only, never mutates.
#          env CLOSEOUT_DRIFT_GH_BIN       gh binary (default gh); fail-open skip
#                                          the merged-PR source when absent/unauth.
#          env CLOSEOUT_DRIFT_MARK_SPEC_BIN  override mark-spec-implemented.sh path
#                                          (selftest stub seam; single writer path).
#          env CLOSEOUT_DRIFT_NOW_EPOCH    override "now" (epoch secs) for staleness.
# Outputs: stdout — human summary, plus JSON report when --json is set.
#          exit 0 on a successful scan (drift findings are NOT errors);
#          exit 1 on usage / environment failure (cannot resolve specs root).
# Side effects: with --apply, invokes mark-spec-implemented.sh on high-confidence
#          delivered drift (the only closeout writer; no second writer here).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"

MARK_SPEC_BIN="${CLOSEOUT_DRIFT_MARK_SPEC_BIN:-${SCRIPT_DIR}/mark-spec-implemented.sh}"
GH_BIN="${CLOSEOUT_DRIFT_GH_BIN:-gh}"

WORKSPACE_ROOT=""
EMIT_JSON=0
STRANDED_DAYS="${CLOSEOUT_DRIFT_STRANDED_DAYS:-14}"
APPLY=1

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  sed -n '2,30p' "$0" >&2
  exit 2
}

# Extract the `status:` field from a spec frontmatter file (reused shape from
# archive-spec.sh frontmatter_status; kept identical so the two stay aligned).
frontmatter_status() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk -F ':' '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^status:/ {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$file"
}

# Extract `task_kind:` from a task frontmatter file.
frontmatter_task_kind() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk -F ':' '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^task_kind:/ {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE_ROOT="${2:-}"; shift 2 ;;
    --json) EMIT_JSON=1; shift ;;
    --stranded-days) STRANDED_DAYS="${2:-}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    -h|--help) usage ;;
    *) fail "unexpected argument: $1" ;;
  esac
done

if [[ -z "$WORKSPACE_ROOT" ]]; then
  WORKSPACE_ROOT="$(resolve_specs_workspace_root)" || fail "unable to resolve workspace root"
fi
[[ -d "$WORKSPACE_ROOT" ]] || fail "workspace not found: $WORKSPACE_ROOT"
WORKSPACE_ROOT="$(cd "$WORKSPACE_ROOT" && pwd)"
SPECS_ROOT="$(resolve_specs_root "$WORKSPACE_ROOT")" || fail "unable to resolve specs root"

CHANGELOG="$WORKSPACE_ROOT/CHANGELOG.md"

now_epoch() {
  if [[ -n "${CLOSEOUT_DRIFT_NOW_EPOCH:-}" ]]; then
    printf '%s\n' "$CLOSEOUT_DRIFT_NOW_EPOCH"
  else
    date +%s
  fi
}

# Portable mtime (epoch secs) for a path: try GNU stat, then BSD stat.
path_mtime_epoch() {
  local path="$1"
  stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || echo 0
}

# D7 readiness-probe carve-out: only probe gh availability for the read-only
# `pr list` query. Absent / unauth gh => fail-open skip the PR source; the
# detector still classifies from markers + CHANGELOG.
gh_available() {
  command -v "$GH_BIN" >/dev/null 2>&1
}

# Returns 0 if a merged PR whose TITLE references the DP exists, 1 otherwise.
# The `in:title` qualifier scopes the search to the DP's own delivery / bundle PRs
# (titled with the DP key, e.g. "[DP-238-T1] ..." / "chore(release): bundle DP-238").
# Without it, a plain full-text search also matches merged PRs that merely *mention*
# the DP in their body (cross-references), producing false "delivered" signals for
# DPs that have no merged delivery PR of their own. Caller must only invoke this
# when gh_available is true.
dp_has_merged_pr() {
  local dp="$1" out=""
  out="$("$GH_BIN" pr list --search "$dp in:title" --state merged --json number 2>/dev/null || printf '[]')"
  [[ -n "$out" && "$out" != "[]" ]]
}

# Returns 0 if an OPEN PR whose TITLE references the DP exists, 1 otherwise.
# An open delivery / bundle PR (in:title) means the DP is still in flight and not
# closeout-ready. Same `in:title` scoping rationale as dp_has_merged_pr. Caller must
# only invoke this when gh_available is true.
dp_has_open_pr() {
  local dp="$1" out=""
  out="$("$GH_BIN" pr list --search "$dp in:title" --state open --json number 2>/dev/null || printf '[]')"
  [[ -n "$out" && "$out" != "[]" ]]
}

# Collect the implementation (task_kind: T) task stems of a DP container.
# Handles folder-native (tasks/T{n}/index.md, tasks/pr-release/T{n}/index.md)
# and legacy flat (tasks/T{n}.md, tasks/pr-release/T{n}.md) layouts.
dp_task_stems() {
  local container="$1" file="" stem="" kind=""
  {
    find "$container/tasks" -maxdepth 1 -type f -name 'T*.md' 2>/dev/null
    find "$container/tasks" -maxdepth 2 -type f -path '*/T*/index.md' 2>/dev/null
    find "$container/tasks/pr-release" -maxdepth 1 -type f -name 'T*.md' 2>/dev/null
    find "$container/tasks/pr-release" -maxdepth 2 -type f -path '*/T*/index.md' 2>/dev/null
  } | while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    kind="$(frontmatter_task_kind "$file")"
    [[ "$kind" == "T" || -z "$kind" ]] || continue
    if [[ "$file" == */index.md ]]; then
      stem="$(basename "$(dirname "$file")")"
    else
      stem="$(basename "$file" .md)"
    fi
    [[ "$stem" == T* ]] || continue
    printf '%s\n' "$stem"
  done | sort -u
}

# Read the ac_verification.status field from a task frontmatter file. Mirrors
# scripts/close-parent-spec-if-complete.sh ac_verification_status reader: scan
# inside the `ac_verification:` block for a nested `status:` line. A missing
# block or empty status yields "" (callers treat "" as not-PASS, conservative).
# Portable awk only (no GNU match()-array extension) so BSD/GNU awk agree.
ac_verification_status() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    $0 == "ac_verification:" { in_block = 1; next }
    in_block && /^[^[:space:]-].*:/ { exit }
    in_block && /^[[:space:]]+status:/ {
      line = $0
      sub(/^[[:space:]]+status:[[:space:]]*/, "", line)
      sub(/[[:space:]].*$/, "", line)
      print line
      exit
    }
  ' "$file"
}

# Enumerate ACTIVE verification (task_kind: V) anchors of a DP container.
# Active = under tasks/ but NOT tasks/pr-release/ (pr-release V anchors are
# historically closed-out / verified and do not gate closeout). Handles
# folder-native (tasks/V{n}/index.md) and legacy flat (tasks/V{n}.md) layouts.
dp_active_v_anchors() {
  local container="$1" file="" stem=""
  {
    find "$container/tasks" -maxdepth 1 -type f -name 'V*.md' 2>/dev/null
    find "$container/tasks" -maxdepth 2 -type f -path '*/V*/index.md' 2>/dev/null
  } | while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    # Exclude anything under tasks/pr-release/ (already closed out).
    [[ "$file" == */tasks/pr-release/* ]] && continue
    if [[ "$file" == */index.md ]]; then
      stem="$(basename "$(dirname "$file")")"
    else
      stem="$(basename "$file" .md)"
    fi
    [[ "$stem" == V* ]] || continue
    printf '%s\n' "$file"
  done | sort -u
}

# Returns 0 (true) if the DP has at least one ACTIVE V anchor whose
# ac_verification.status is not PASS (including a missing ac_verification block,
# treated conservatively as not-PASS). Returns 1 (false) when every active V
# anchor is verified PASS, or when the DP has no active V anchors at all. A
# pending V anchor means AC verification is incomplete: the DP must hold at
# in-flight and must never be auto closed out before verification.
dp_v_verification_pending() {
  local container="$1" anchor="" status=""
  while IFS= read -r anchor; do
    [[ -n "$anchor" ]] || continue
    status="$(ac_verification_status "$anchor")"
    if [[ "$status" != "PASS" ]]; then
      return 0
    fi
  done < <(dp_active_v_anchors "$container")
  return 1
}

# Read whether a T task's task.md frontmatter records a delivered head + PASS
# verification via the `deliverable` block (DP-360 T7). A task is "delivered"
# when its task.md carries a non-empty `deliverable.head_sha` AND a nested
# `deliverable.verification.status: PASS`. The head-sha-keyed completion-gate
# marker is retired (D2/D4); the task.md `deliverable` block is the sole durable
# delivery-evidence record. Branch refs are never consulted (AC-NEG1).
# Echos "delivered" when both hold, "" otherwise (callers treat "" as not
# delivered, conservative — same posture as ac_verification_status).
# Portable awk only (no GNU match()-array) so BSD/GNU awk agree.
task_deliverable_delivered() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    # Stop scanning at the closing frontmatter fence.
    NR > 1 && $0 == "---" && seen_open { exit }
    NR == 1 && $0 == "---" { seen_open = 1; next }
    $0 == "deliverable:" { in_deliverable = 1; next }
    # A new top-level (col-0, non-list) key ends the deliverable block.
    in_deliverable && /^[^[:space:]-].*:/ { in_deliverable = 0 }
    in_deliverable && /^[[:space:]]+head_sha:[[:space:]]*[^[:space:]]/ {
      line = $0
      sub(/^[[:space:]]+head_sha:[[:space:]]*/, "", line)
      sub(/[[:space:]].*$/, "", line)
      if (line != "") have_head = 1
    }
    in_deliverable && /^[[:space:]]+verification:/ { in_verification = 1; next }
    # A sibling 2-space key under deliverable ends the verification sub-block.
    in_verification && /^[[:space:]][[:space:]][^[:space:]].*:/ && !/^[[:space:]][[:space:]][[:space:]]/ {
      in_verification = 0
    }
    in_verification && /^[[:space:]]+status:[[:space:]]*PASS/ { have_pass = 1 }
    END { if (have_head && have_pass) print "delivered" }
  ' "$file"
}

# Resolve the task.md path for a DP task stem (folder-native or legacy flat,
# active tasks/ or finalized tasks/pr-release/). Echos the first match.
dp_task_file_for_stem() {
  local container="$1" stem="$2" cand=""
  for cand in \
    "$container/tasks/$stem/index.md" \
    "$container/tasks/$stem.md" \
    "$container/tasks/pr-release/$stem/index.md" \
    "$container/tasks/pr-release/$stem.md"; do
    if [[ -f "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

# Count T tasks whose task.md `deliverable` block records delivery (head + PASS)
# for a DP container. Echos "<covered> <total>". (DP-360 T7: replaces the
# completion-gate marker count; same covered/total semantics feed classification.)
dp_marker_coverage() {
  local container="$2" stem="" file="" total=0 covered=0
  while IFS= read -r stem; do
    [[ -n "$stem" ]] || continue
    total=$((total + 1))
    file="$(dp_task_file_for_stem "$container" "$stem" || true)"
    if [[ -n "$file" && "$(task_deliverable_delivered "$file")" == "delivered" ]]; then
      covered=$((covered + 1))
    fi
  done < <(dp_task_stems "$container")
  printf '%s %s\n' "$covered" "$total"
}

# Returns 0 if CHANGELOG has a Fixed/Added section referencing the DP.
dp_in_changelog() {
  local dp="$1"
  [[ -f "$CHANGELOG" ]] || return 1
  grep -Eq "^###[[:space:]]+(Fixed|Added)[[:space:]].*\b${dp}\b" "$CHANGELOG"
}

# Enumerate active design-plan containers (excludes archive/). Mirrors the
# archive-spec.sh sweep_containers enumeration for design-plans.
active_dp_containers() {
  [[ -d "$SPECS_ROOT/design-plans" ]] || return 0
  find "$SPECS_ROOT/design-plans" -maxdepth 1 -type d -name 'DP-[0-9][0-9][0-9]-*' -print0 2>/dev/null \
    | tr '\0' '\n'
}

# --- main scan -------------------------------------------------------------

NOW="$(now_epoch)"
STRANDED_SECS=$((STRANDED_DAYS * 86400))
GH_OK=0
gh_available && GH_OK=1

# Accumulate results as TSV lines, then render report from them.
RESULTS_TSV="$(mktemp -t closeout-drift.XXXXXX)"
trap 'rm -f "$RESULTS_TSV"' EXIT

container=""
while IFS= read -r container; do
  [[ -n "$container" ]] || continue
  dp="$(basename "$container" | sed -E 's/^(DP-[0-9]{3})-.*/\1/')"
  anchor="$container/index.md"
  [[ -f "$anchor" ]] || anchor="$container/plan.md"
  status="$(frontmatter_status "$anchor")"

  # AC6: only active/ LOCKED containers are in scope. Non-LOCKED is a no-op.
  [[ "$status" == "LOCKED" ]] || continue

  read -r covered total < <(dp_marker_coverage "$dp" "$container")

  changelog_hit=0
  dp_in_changelog "$dp" && changelog_hit=1

  pr_unchecked=0
  pr_merged=0
  pr_open=0
  if [[ "$GH_OK" -eq 1 ]]; then
    if dp_has_merged_pr "$dp"; then
      pr_merged=1
    fi
    if dp_has_open_pr "$dp"; then
      pr_open=1
    fi
  else
    # AC5 D7 readiness-probe carve-out: gh absent -> skip PR source, annotate.
    pr_unchecked=1
  fi

  markers_complete=0
  if [[ "$total" -gt 0 && "$covered" -eq "$total" ]]; then
    markers_complete=1
  fi

  any_evidence=0
  if [[ "$markers_complete" -eq 1 || "$covered" -gt 0 || "$changelog_hit" -eq 1 || "$pr_merged" -eq 1 ]]; then
    any_evidence=1
  fi

  # AC1: read-only V-task verification gate. If any active V anchor has not
  # passed AC verification (status != PASS, including a missing ac_verification
  # block), the DP is not closeout-ready regardless of T-marker / merged-PR
  # evidence. pr-release V anchors are treated as already verified and excluded.
  verification_pending=0
  if dp_v_verification_pending "$container"; then
    verification_pending=1
  fi

  # Classification.
  classification=""
  if [[ "$pr_open" -eq 1 ]]; then
    # In-flight guard: an open delivery / bundle PR (in:title) means the DP is not
    # closeout-ready, regardless of marker / merged-PR evidence. Prevents archiving
    # in-flight delivery — including stacked delivery where some task PRs merged and
    # others are still open. A closeout false-negative (defer) is far safer than a
    # false-positive (wrongly archiving an in-flight DP).
    classification="in-flight"
  elif [[ "$verification_pending" -eq 1 ]]; then
    # AC1: an active V anchor still pending AC verification holds the DP at
    # in-flight (report-only). Closeout must wait until verification PASSes, so
    # the auto-archive path below is never taken while a V anchor is unverified.
    classification="in-flight"
  elif [[ "$markers_complete" -eq 1 && "$pr_merged" -eq 1 ]]; then
    # AC1/AC2: all task markers + confirmed merged PR + all V anchors verified
    # (or none) => high-confidence drift.
    classification="delivered-drift-high"
  elif [[ "$any_evidence" -eq 1 ]]; then
    if [[ "$covered" -gt 0 && "$markers_complete" -eq 0 ]]; then
      # Partial markers => active delivery in progress (AC-NEG1).
      classification="in-flight"
    else
      # Only CHANGELOG and/or merged PR but markers not complete (old DP, or
      # marker evidence missing) => low-confidence drift, report only (AC3).
      classification="delivered-drift-low"
    fi
  else
    # Zero delivery evidence.
    anchor_age=$((NOW - $(path_mtime_epoch "$anchor")))
    container_age=$((NOW - $(path_mtime_epoch "$container")))
    age=$anchor_age
    [[ "$container_age" -gt "$age" ]] && age=$container_age
    if [[ "$age" -ge "$STRANDED_SECS" ]]; then
      classification="stranded"   # AC3 / AC-NEG2: report only, no state change.
    else
      classification="in-flight"  # Recently locked, no evidence yet.
    fi
  fi

  action="report-only"
  if [[ "$classification" == "delivered-drift-high" && "$APPLY" -eq 1 ]]; then
    # AC2 / AC-NEG3: single closeout writer path. No second status writer here.
    if "$MARK_SPEC_BIN" "$dp" --status IMPLEMENTED >/dev/null 2>&1; then
      action="closed-out"
    else
      action="closeout-failed"
    fi
  elif [[ "$classification" == "delivered-drift-high" ]]; then
    action="would-close-out"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$dp" "$classification" "$action" "$covered" "$total" \
    "$changelog_hit" "$pr_merged" "$pr_open" "$pr_unchecked" "$verification_pending" \
    "$(basename "$container")" \
    >>"$RESULTS_TSV"
done < <(active_dp_containers)

# --- render ----------------------------------------------------------------

if [[ "$EMIT_JSON" -eq 1 ]]; then
  python3 - "$RESULTS_TSV" "$GH_OK" "$STRANDED_DAYS" <<'PY'
import json, sys
tsv, gh_ok, stranded_days = sys.argv[1], sys.argv[2] == "1", int(sys.argv[3])
results = []
with open(tsv, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        dp, classification, action, covered, total, changelog_hit, pr_merged, pr_open, pr_unchecked, verification_pending, container = line.split("\t")
        pr_unchecked_b = pr_unchecked == "1"
        merged_pr = "unchecked" if pr_unchecked_b else ("merged" if pr_merged == "1" else "none")
        results.append({
            "dp": dp,
            "container": container,
            "classification": classification,
            "action": action,
            "pr_evidence_unchecked": pr_unchecked_b,
            "evidence": {
                "completion_gate_markers": {"covered": int(covered), "total": int(total)},
                "changelog": changelog_hit == "1",
                "merged_pr": merged_pr,
                "in_flight_open_pr": pr_open == "1",
                "verification_pending": verification_pending == "1",
            },
        })
report = {
    "schema_version": 1,
    "report_kind": "closeout_drift",
    "gh_available": gh_ok,
    "stranded_threshold_days": stranded_days,
    "results": results,
}
print(json.dumps(report, ensure_ascii=False, indent=2))
PY
fi

# Human summary (always to stderr-free stdout after JSON, or alone).
{
  echo "closeout-drift scan: $(wc -l <"$RESULTS_TSV" | tr -d ' ') active LOCKED DP(s)"
  if [[ "$GH_OK" -ne 1 ]]; then
    echo "  NOTE: gh unavailable — merged-PR evidence unchecked (D7 fail-open)."
  fi
  while IFS=$'\t' read -r dp classification action covered total changelog_hit pr_merged pr_open pr_unchecked verification_pending container; do
    [[ -n "$dp" ]] || continue
    echo "  - ${dp} [${classification}] action=${action} markers=${covered}/${total} changelog=${changelog_hit} pr_merged=${pr_merged} pr_open=${pr_open} pr_unchecked=${pr_unchecked} verification_pending=${verification_pending}"
  done <"$RESULTS_TSV"
} >&2

exit 0
