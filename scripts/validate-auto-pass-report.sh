#!/usr/bin/env bash
# Purpose: validate an auto-pass terminal report JSON against the report
#          contract (.claude/skills/references/auto-pass-report.md): schema
#          shape, follow-up DP seed threshold, overlap disposition,
#          friction_log_summary ledger aggregation, plus DP-311 T3 fail-closed
#          cross-checks — (a) report.terminal_status=complete ↔ referenced
#          ledger terminal state; (b) report.verification.status=PASS ↔
#          head-bound .polaris/evidence/ac-verification/{work_item}-{head}.json
#          PASS marker (stale summaries are not trusted).
# Inputs:  $1 = /path/to/report.json. Optional env POLARIS_WORKSPACE_ROOT
#          overrides the evidence root used for marker lookup (hermetic
#          selftests); default resolves the main checkout via
#          scripts/lib/main-checkout.sh from the report location.
# Outputs: "PASS: ..." on stdout. On failure: error list on stderr; cross-check
#          violations additionally emit structured POLARIS_AUTO_PASS_REPORT_*
#          markers and exit 2; schema-only violations exit 1.
set -euo pipefail

if [[ $# -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
  cat >&2 <<'USAGE'
usage:
  scripts/validate-auto-pass-report.sh /path/to/report.json

env:
  POLARIS_WORKSPACE_ROOT  override evidence root for head-bound
                          ac_verification marker lookup (selftests)
USAGE
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# DP-330 T2: workspace root for follow_up_dp_seed.contract_evidence path:line
# validation. This is the repo containing scripts/, resolved from this script's
# location — distinct from EVIDENCE_ROOT (which can be overridden to a hermetic
# temp dir for ac_verification marker selftests). contract_evidence points at
# real source files, so it always resolves against the actual repo.
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# DP-311 T3: resolve the evidence root for head-bound ac_verification markers.
# Order: explicit env override → main checkout resolved from the report path
# (worktree-safe; markers live only in the main checkout) → main checkout
# resolved from this script's location.
EVIDENCE_ROOT="${POLARIS_WORKSPACE_ROOT:-}"
if [[ -z "$EVIDENCE_ROOT" ]]; then
  # shellcheck source=lib/main-checkout.sh
  source "$SCRIPT_DIR/lib/main-checkout.sh"
  report_dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd || true)"
  if [[ -n "$report_dir" ]]; then
    EVIDENCE_ROOT="$(resolve_main_checkout "$report_dir" 2>/dev/null || true)"
  fi
  if [[ -z "$EVIDENCE_ROOT" ]]; then
    EVIDENCE_ROOT="$(resolve_main_checkout "$SCRIPT_DIR" 2>/dev/null || true)"
  fi
fi

# DP-303 T5: resolve the specs root used for the follow_up_dp_seed collision
# check. The seed's DP number must not already be occupied across the active
# (design-plans/DP-*) and archive (design-plans/archive/DP-*) namespaces — the
# same occupancy semantics as scripts/allocate-design-plan-number.sh. Order:
# explicit POLARIS_SPECS_ROOT override (hermetic selftests) → workspace docs
# specs root resolved from this script's location.
SPECS_ROOT="${POLARIS_SPECS_ROOT:-$WORKSPACE_ROOT/docs-manager/src/content/docs/specs}"

python3 - "$1" "$EVIDENCE_ROOT" "$WORKSPACE_ROOT" "$SPECS_ROOT" <<'PY'
"""Purpose: auto-pass report contract validation body (see bash header).

Inputs: argv[1]=report path, argv[2]=evidence root ('' when unresolvable),
        argv[3]=workspace root for follow_up_dp_seed.contract_evidence
        path:line validation, argv[4]=specs root for follow_up_dp_seed
        collision check (DP-303 T5).
Outputs: PASS line on stdout; error list + POLARIS_AUTO_PASS_REPORT_* markers
on stderr. Exit 2 on cross-check violation, 1 on schema violation.
"""
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
evidence_root = sys.argv[2] if len(sys.argv) > 2 else ""
workspace_root = Path(sys.argv[3]).resolve() if len(sys.argv) > 3 else Path.cwd().resolve()
specs_root = sys.argv[4] if len(sys.argv) > 4 else ""
sys.path.insert(0, str(workspace_root / "scripts" / "lib"))
from contract_evidence import validate_contract_evidence_entries
TERMINAL = {
    "complete",
    "paused_for_refinement",
    "paused_for_user_external_write",
    "loop_cap_reached",
    "blocked_by_gate_failure",
    "user_aborted",
}
OVERLAP = {"keep", "narrow", "deprecate-note", "follow-up-sunset"}
# DP-228 AC4: source-neutral schema. source_id must match resolver-compatible
# {PREFIX}-NNN — no hard-coded DP regex.
SOURCE_ID_PATTERN = re.compile(r"[A-Z][A-Z0-9]*-[0-9]+")
# DP-311 T3: head-bound marker filename suffix — abbreviated or full git sha.
HEAD_SHA_PATTERN = re.compile(r"[0-9a-f]{7,40}")

# DP-311 T3 structured cross-check markers (exit 2, fail-closed).
CROSS_LEDGER_UNREADABLE = "POLARIS_AUTO_PASS_REPORT_LEDGER_UNREADABLE"
CROSS_LEDGER_MISMATCH = "POLARIS_AUTO_PASS_REPORT_LEDGER_TERMINAL_MISMATCH"
CROSS_MARKER_MISSING = "POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISSING"
CROSS_MARKER_MISMATCH = "POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISMATCH"
# DP-303 T5 follow_up_dp_seed collision marker (exit 2, fail-closed).
SEED_COLLISION = "POLARIS_AUTO_PASS_REPORT_SEED_COLLISION"
# Resolver-compatible {PREFIX}-NNN extracted from a design-plans subdir name.
SEED_DP_DIR_PATTERN = re.compile(r"(?P<prefix>[A-Z][A-Z0-9]*)-(?P<num>[0-9]+)")


def fail(errors, cross_errors=()):
    """Print the error list (+ structured markers) and exit 2/1.

    Args:
        errors: schema-level error strings (exit 1 tier).
        cross_errors: (token, detail) tuples from DP-311 cross-checks
            (exit 2 tier; each also emits "{token}:{report_path}").
    """
    print("FAIL: auto-pass report validation", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    for _token, detail in cross_errors:
        print(f"  - {detail}", file=sys.stderr)
    for token, _detail in cross_errors:
        print(f"{token}:{path}", file=sys.stderr)
    raise SystemExit(2 if cross_errors else 1)


def validate_contract_evidence(raw, prefix, require_non_empty):
    """Append follow_up_dp_seed.contract_evidence shape errors to ``errors``.

    Delegates to the shared contract_evidence helper (T1-delivered). When
    framework_gap is true, contract_evidence must be a non-empty array of
    workspace-root-bound repo/path:line strings; when false, it is optional.

    Args:
        raw: the seed's contract_evidence field (any JSON value).
        prefix: field path used in diagnostics.
        require_non_empty: whether missing/empty evidence is an error
            (mirrors framework_gap).
    """
    errors.extend(validate_contract_evidence_entries(
        raw,
        repo_root=workspace_root,
        prefix=prefix,
        require_non_empty=require_non_empty,
        missing_error=f"{prefix} is required when follow_up_dp_seed.framework_gap is true",
        not_array_error=f"{prefix} must be an array of repo/path:line strings",
        empty_error=f"{prefix} must contain at least one repo/path:line string when follow_up_dp_seed.framework_gap is true",
        item_empty_error="{field} must be a non-empty repo/path:line string",
        shape_error="{field} must match repo/path:line with a positive line number",
        outside_root_error="{field} must point inside the workspace root: {path}",
        not_found_error="{field} file not found: {path}",
        unreadable_error="{field} file could not be read: {path} ({exc})",
        out_of_range_error="{field} line {line} is outside file range for {path}",
    ))


def seed_dp_identity(seed_path):
    """Extract the design-plan identity ({PREFIX}-NNN) a seed.path would create.

    Args:
        seed_path: the seed's ``path`` field (e.g.
            ``docs-manager/.../design-plans/DP-999-follow-up/index.md``).

    Returns:
        (prefix, number) tuple for the design-plans subdir, or None when the
        path is not under design-plans or carries no resolver-compatible id.
    """
    parts = Path(seed_path).parts
    if "design-plans" not in parts:
        return None
    idx = parts.index("design-plans")
    # Skip the optional ``archive`` segment; the seed names a new active DP dir.
    rest = [p for p in parts[idx + 1:] if p != "archive"]
    if not rest:
        return None
    match = SEED_DP_DIR_PATTERN.match(rest[0])
    if not match:
        return None
    return (match.group("prefix"), int(match.group("num")))


def seed_number_occupied(specs_root_path, prefix, number):
    """Report whether {prefix}-{number} is already a plan dir (active+archive).

    Mirrors scripts/allocate-design-plan-number.sh occupancy semantics: a
    design-plans (or design-plans/archive) subdir matching the same prefix and
    number that contains an index.md or plan.md counts as occupied.

    Args:
        specs_root_path: specs root directory (may not exist).
        prefix: design-plan prefix (e.g. "DP").
        number: design-plan number to test for occupancy.

    Returns:
        The occupying directory Path on collision, else None.
    """
    base = Path(specs_root_path) / "design-plans"
    if not base.is_dir():
        return None
    candidates = list(base.glob(f"{prefix}-*")) + list((base / "archive").glob(f"{prefix}-*"))
    for parent in candidates:
        if not parent.is_dir():
            continue
        match = SEED_DP_DIR_PATTERN.match(parent.name)
        if not match or match.group("prefix") != prefix or int(match.group("num")) != number:
            continue
        if (parent / "index.md").is_file() or (parent / "plan.md").is_file():
            return parent
    return None


if not path.is_file():
    fail([f"report not found: {path}"])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    fail([f"invalid JSON: {exc}"])

errors = []
cross_errors = []
if data.get("schema_version") != 1:
    errors.append("schema_version must be 1")
report_source_id = data.get("source_id")
if not report_source_id:
    errors.append("source_id is required")
elif not SOURCE_ID_PATTERN.fullmatch(str(report_source_id)):
    errors.append("source_id must match {PREFIX}-NNN (resolver-compatible)")
terminal = data.get("terminal_status")
if terminal not in TERMINAL:
    errors.append(f"invalid terminal_status: {terminal}")
for field in ("created_at", "ledger_path"):
    if not data.get(field):
        errors.append(f"{field} is required")
for field in ("required_prs", "issues", "blockers", "manual_items", "follow_ups", "overlap_disposition"):
    if not isinstance(data.get(field), list):
        errors.append(f"{field} must be an array")
verification = data.get("verification")
if not isinstance(verification, dict) or not verification.get("status"):
    errors.append("verification.status is required")

for idx, row in enumerate(data.get("overlap_disposition") or []):
    disposition = row.get("disposition") if isinstance(row, dict) else None
    if disposition not in OVERLAP:
        errors.append(f"overlap_disposition[{idx}].disposition invalid: {disposition}")
    if disposition == "follow-up-sunset" and not row.get("candidate"):
        errors.append(f"overlap_disposition[{idx}] follow-up-sunset requires candidate")

seed_needed = (
    terminal != "complete"
    or bool(data.get("issues"))
    or bool(data.get("blockers"))
    or bool(data.get("manual_items"))
    or bool(data.get("follow_ups"))
    or any(row.get("disposition") == "follow-up-sunset" for row in data.get("overlap_disposition") or [] if isinstance(row, dict))
)
seed = data.get("follow_up_dp_seed")
if seed_needed:
    if not isinstance(seed, dict):
        errors.append("follow_up_dp_seed is required when report has issue threshold")
    else:
        for field in ("path", "reason", "source_report"):
            if not seed.get(field):
                errors.append(f"follow_up_dp_seed.{field} is required")
        # DP-330 T2: framework_gap=true requires contract_evidence (≥1
        # repo/path:line); false makes it optional. Threshold trigger and the
        # path/reason/source_report requirements above are unchanged.
        framework_gap = seed.get("framework_gap")
        if not isinstance(framework_gap, bool):
            errors.append("follow_up_dp_seed.framework_gap must be a boolean")
        else:
            validate_contract_evidence(
                seed.get("contract_evidence"),
                "follow_up_dp_seed.contract_evidence",
                framework_gap,
            )
        # DP-303 T5 (AC8): the seeded follow-up DP number must not already be
        # occupied across the active + archive design-plans namespaces (the
        # writer must take a fresh number via allocate-design-plan-number.sh or
        # verify the given number is free). An occupied number fails closed.
        seed_path = seed.get("path")
        if isinstance(seed_path, str) and seed_path and specs_root:
            identity = seed_dp_identity(seed_path)
            if identity is not None:
                prefix, number = identity
                occupier = seed_number_occupied(specs_root, prefix, number)
                if occupier is not None:
                    cross_errors.append((
                        SEED_COLLISION,
                        f"follow_up_dp_seed.path targets {prefix}-{number:03d} but that "
                        f"number is already occupied by {occupier} (active + archive). "
                        "Take a fresh number via allocate-design-plan-number.sh.",
                    ))
else:
    if seed is not None:
        errors.append("follow_up_dp_seed must be null when no issue threshold is present")

tail = data.get("framework_release_tail")
if tail is not None:
    if not isinstance(tail, dict):
        errors.append("framework_release_tail must be an object or null")
    elif "framework-release" not in str(tail.get("trigger", "")):
        errors.append("framework_release_tail.trigger must reference framework-release")

# DP-214: friction_log_summary is computed from the ledger referenced by ledger_path.
# It is validator-owned: the report writer MAY include a snapshot, but if present it
# must match the ledger aggregation exactly. Validator will not silently rewrite it.
FRICTION_KIND_ENUM = {
    "inner_skill_halt_bypass",
    "manual_artifact_patch",
    "deterministic_gap",
    "env_bypass",
    "validator_contract_conflict",
    "missing_helper_script",
    "language_drift_repair",
    "other",
}
FRICTION_STAGE_ENUM = {"source", "breakdown", "engineering", "verify-AC", "framework-release", "post-task"}


def aggregate_friction(entries):
    """Aggregate ledger friction_log[] into the friction_log_summary shape.

    Args:
        entries: ledger friction_log list (possibly None).

    Returns:
        dict with total / by_stage / by_kind counters.
    """
    summary = {"total": 0, "by_stage": {}, "by_kind": {}}
    for entry in entries or []:
        if not isinstance(entry, dict):
            continue
        summary["total"] += 1
        stage = entry.get("stage")
        if stage in FRICTION_STAGE_ENUM:
            summary["by_stage"][stage] = summary["by_stage"].get(stage, 0) + 1
        kind = entry.get("friction_kind")
        if kind in FRICTION_KIND_ENUM:
            summary["by_kind"][kind] = summary["by_kind"].get(kind, 0) + 1
    return summary


# Load the referenced ledger once; consumed by the friction_log_summary check
# and the DP-311 T3 report↔ledger terminal cross-check.
ledger_payload = None
ledger_read_error = None
ledger_path_value = data.get("ledger_path")
if isinstance(ledger_path_value, str) and ledger_path_value:
    ledger_p = Path(ledger_path_value)
    if ledger_p.is_file():
        try:
            raw_ledger = json.loads(ledger_p.read_text(encoding="utf-8"))
        except Exception as exc:
            ledger_read_error = f"ledger_path JSON invalid: {exc}"
            errors.append(ledger_read_error)
        else:
            if isinstance(raw_ledger, dict):
                ledger_payload = raw_ledger
            else:
                ledger_read_error = "ledger_path JSON is not an object"
                errors.append(ledger_read_error)
    else:
        ledger_read_error = f"ledger file not found: {ledger_p}"
else:
    ledger_read_error = "ledger_path is missing or empty"

ledger_friction = None
if ledger_payload is not None:
    ledger_friction = ledger_payload.get("friction_log") or []
    if not isinstance(ledger_friction, list):
        errors.append("ledger friction_log must be an array when present")
        ledger_friction = []

computed_summary = aggregate_friction(ledger_friction) if ledger_friction is not None else None
declared_summary = data.get("friction_log_summary")
if declared_summary is not None:
    if not isinstance(declared_summary, dict):
        errors.append("friction_log_summary must be an object when present")
    elif computed_summary is None:
        errors.append("friction_log_summary present but ledger could not be read")
    elif declared_summary != computed_summary:
        errors.append(
            "friction_log_summary does not match ledger aggregation; "
            f"expected {json.dumps(computed_summary, sort_keys=True)}, "
            f"got {json.dumps(declared_summary, sort_keys=True)}"
        )

# ── DP-311 T3 cross-check (a): report complete ↔ ledger terminal (AC5) ──────
# A complete report must reference a readable ledger whose durable terminal
# truth is "complete", or the complete-eligible write-time state (terminal
# null/empty AND no unresolved pause) that scripts/auto-pass-finalize-ledger.sh
# flips at the mark-spec-implemented parent-flip callsite (D5 ordering: the
# report write precedes the ledger finalize inside the closeout chain).
if terminal == "complete":
    if ledger_payload is None:
        cross_errors.append((
            CROSS_LEDGER_UNREADABLE,
            f"terminal_status=complete but referenced ledger is unreadable ({ledger_read_error})",
        ))
    else:
        ledger_terminal = ledger_payload.get("terminal_status")
        ledger_pause = ledger_payload.get("pause")
        if ledger_terminal == "complete":
            pass
        elif ledger_terminal in (None, "") and not ledger_pause:
            pass  # complete-eligible: finalize helper flips this state at parent flip
        else:
            pause_kind = ledger_pause.get("kind") if isinstance(ledger_pause, dict) else ledger_pause
            cross_errors.append((
                CROSS_LEDGER_MISMATCH,
                "terminal_status=complete but ledger terminal_status="
                f"{ledger_terminal!r} (pause={pause_kind!r}) is not complete or complete-eligible",
            ))


def marker_satisfies(marker_path, work_item, pinned_head):
    """Check one head-bound ac_verification marker file against the report claim.

    Args:
        marker_path: Path to a {work_item}-{head}.json candidate.
        work_item: expected work_item_id from report.verification.
        pinned_head: report.verification.head_sha when declared, else None.

    Returns:
        True when the marker is a PASS marker consistently bound to the
        work item (and to pinned_head when declared).
    """
    filename_head = marker_path.name[len(work_item) + 1:-len(".json")]
    try:
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
    except Exception:
        return False
    if not isinstance(marker, dict) or marker.get("status") != "PASS":
        return False
    if marker.get("work_item_id") not in (None, work_item):
        return False
    marker_head = marker.get("head_sha")
    if marker_head not in (None, filename_head):
        return False
    if pinned_head and filename_head != str(pinned_head):
        return False
    return True


# ── DP-311 T3 cross-check (b): verification PASS ↔ head-bound marker (AC6) ──
# A PASS verification claim is only trusted when the V work item has a durable
# head-bound .polaris/evidence/ac-verification/{work_item}-{head}.json PASS
# marker; the report's own prose/summary is never accepted as evidence.
if isinstance(verification, dict) and verification.get("status") == "PASS":
    work_item = verification.get("work_item_id")
    pinned_head = verification.get("head_sha")
    if not work_item:
        cross_errors.append((
            CROSS_MARKER_MISSING,
            "verification.status=PASS requires verification.work_item_id to locate the head-bound marker",
        ))
    elif not evidence_root:
        cross_errors.append((
            CROSS_MARKER_MISSING,
            "verification.status=PASS but the workspace root for "
            ".polaris/evidence/ac-verification marker lookup could not be resolved",
        ))
    else:
        marker_dir = Path(evidence_root) / ".polaris" / "evidence" / "ac-verification"
        if pinned_head is not None and not HEAD_SHA_PATTERN.fullmatch(str(pinned_head)):
            cross_errors.append((
                CROSS_MARKER_MISMATCH,
                f"verification.head_sha must be a 7-40 char hex sha, got {pinned_head!r}",
            ))
        else:
            candidates = []
            if pinned_head:
                pinned_path = marker_dir / f"{work_item}-{pinned_head}.json"
                if pinned_path.is_file():
                    candidates.append(pinned_path)
            elif marker_dir.is_dir():
                prefix = f"{work_item}-"
                for entry in sorted(marker_dir.iterdir()):
                    if not entry.name.startswith(prefix) or not entry.name.endswith(".json"):
                        continue
                    suffix = entry.name[len(prefix):-len(".json")]
                    if HEAD_SHA_PATTERN.fullmatch(suffix):
                        candidates.append(entry)
            if not candidates:
                cross_errors.append((
                    CROSS_MARKER_MISSING,
                    "verification.status=PASS but no head-bound ac_verification marker "
                    f"found for {work_item} under {marker_dir}",
                ))
            elif not any(marker_satisfies(c, work_item, pinned_head) for c in candidates):
                cross_errors.append((
                    CROSS_MARKER_MISMATCH,
                    f"verification.status=PASS but no head-bound marker for {work_item} "
                    f"under {marker_dir} is a consistent PASS marker (stale summary is not trusted)",
                ))

if errors or cross_errors:
    fail(errors, cross_errors)
print(f"PASS: auto-pass report validation ({path})")
PY
