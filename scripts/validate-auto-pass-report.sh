#!/usr/bin/env bash
# Purpose: validate an auto-pass terminal report JSON against the report
#          contract (.claude/skills/references/auto-pass-report.md): schema
#          shape, follow-up DP seed threshold, overlap disposition,
#          friction_log_summary ledger aggregation, plus DP-311 T3 fail-closed
#          cross-checks — (a) report.terminal_status=complete ↔ referenced
#          ledger terminal state; (b) report.verification.status=PASS ↔ the V
#          work item's task.md `deliverable` block (deliverable.head_sha bound to
#          verification.head_sha + deliverable.verification.status=PASS). DP-360
#          T7: the head-sha-keyed ac_verification marker is retired; the task.md
#          block is the sole delivery-evidence source. Stale summaries / branch
#          refs are never trusted.
# Inputs:  $1 = /path/to/report.json. Optional env POLARIS_WORKSPACE_ROOT
#          overrides the scan root used to resolve the V work item's task.md
#          (hermetic selftests); default resolves the main checkout via
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
  POLARIS_WORKSPACE_ROOT  override scan root for resolving the V work item's
                          task.md deliverable block (selftests)
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

RESOLVER="$SCRIPT_DIR/resolve-task-md.sh" PARSER="$SCRIPT_DIR/parse-task-md.sh" \
PR_OWNERSHIP_GATE="$SCRIPT_DIR/auto-pass-pr-ownership-gate.sh" \
python3 - "$1" "$EVIDENCE_ROOT" "$WORKSPACE_ROOT" "$SPECS_ROOT" <<'PY'
"""Purpose: auto-pass report contract validation body (see bash header).

Inputs: argv[1]=report path, argv[2]=evidence root ('' when unresolvable),
        argv[3]=workspace root for follow_up_dp_seed.contract_evidence
        path:line validation, argv[4]=specs root for follow_up_dp_seed
        collision check (DP-303 T5). Env RESOLVER/PARSER point at the canonical
        resolve-task-md.sh / parse-task-md.sh used to read the V work item's
        task.md deliverable block (DP-360 T7).
Outputs: PASS line on stdout; error list + POLARIS_AUTO_PASS_REPORT_* markers
on stderr. Exit 2 on cross-check violation, 1 on schema violation.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
evidence_root = sys.argv[2] if len(sys.argv) > 2 else ""
workspace_root = Path(sys.argv[3]).resolve() if len(sys.argv) > 3 else Path.cwd().resolve()
specs_root = sys.argv[4] if len(sys.argv) > 4 else ""
sys.path.insert(0, str(workspace_root / "scripts" / "lib"))
from contract_evidence import validate_contract_evidence_entries
TERMINAL = {
    "complete",
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
TERMINAL_PARENT_NOT_ARCHIVED = "POLARIS_AUTO_PASS_TERMINAL_PARENT_NOT_ARCHIVED"
PR_OWNERSHIP_BLOCKED = "POLARIS_AUTO_PASS_PR_OWNERSHIP_BLOCKED"
PR_DRAFT_BLOCKED = "POLARIS_AUTO_PASS_PR_DRAFT_BLOCKED"
# DP-417 T6 / AC6 + AC-NEG2: a review-driven revision / head rebind may only
# reach `complete` once its PR-visible evidence publication marker is current at
# the revised head (stale/old head or missing → fail-closed, exit 2).
PR_EVIDENCE_PUBLICATION_STALE = "POLARIS_AUTO_PASS_PR_EVIDENCE_PUBLICATION_STALE"
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


def read_frontmatter_status(index_path):
    """Read a specs index.md frontmatter status value, if present."""
    try:
        text = Path(index_path).read_text(encoding="utf-8", errors="replace")
    except Exception:
        return None
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    for line in text[4:end].splitlines():
        if line.startswith("status:"):
            return line.split(":", 1)[1].strip().strip('"')
    return None


def source_parent_lifecycle(specs_root_path, source_id):
    """Resolve active/archive parent lifecycle for report source_id."""
    if not specs_root_path or not source_id:
        return None
    base = Path(specs_root_path)
    active_parent = base / "design-plans"
    archive_parent = active_parent / "archive"
    active_matches = sorted(active_parent.glob(f"{source_id}-*/index.md")) if active_parent.is_dir() else []
    archive_matches = sorted(archive_parent.glob(f"{source_id}-*/index.md")) if archive_parent.is_dir() else []
    if active_matches:
        first = active_matches[0]
        return {"namespace": "active", "path": str(first), "status": read_frontmatter_status(first)}
    if archive_matches:
        first = archive_matches[0]
        return {"namespace": "archive", "path": str(first), "status": read_frontmatter_status(first)}
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


def required_pr_ownership_required(row):
    """Whether required_prs[] row opted into DP-231 T7 PR ownership checks."""
    if not isinstance(row, dict):
        return False
    keys = {
        "auto_pass_pr_ownership_required",
        "auto_pass_pr_ownership",
        "pr_ownership",
        "isDraft",
        "is_draft",
        "draft",
        "publisher",
        "writer",
        "provenance",
        "engineering_completion_marker",
        "completion_marker",
        "completion_gate",
        "base_freshness",
    }
    return any(key in row for key in keys)


def run_pr_ownership_gate(row):
    """Run the shared DP-231 T7 PR ownership gate against a required_prs row."""
    gate = os.environ.get("PR_OWNERSHIP_GATE")
    if not gate:
        return (PR_OWNERSHIP_BLOCKED, "auto-pass PR ownership gate path missing")
    # DP-417 T3: the shared gate's --stdin mode is unreachable — its python
    # heredoc occupies stdin, so a piped row reads as empty and every
    # ownership-bearing required_prs[] row falsely blocks as
    # "input is not readable JSON". Drive the gate through its working
    # --state-file mode so a legitimately owned published PR can PASS and a
    # draft PR reports PR_DRAFT_BLOCKED (AC6), reusing the single gate path.
    state_path = None
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            handle.write(json.dumps(row, ensure_ascii=False))
            state_path = handle.name
        proc = subprocess.run(
            ["bash", gate, "--state-file", state_path],
            text=True,
            capture_output=True,
            timeout=30,
        )
    except Exception as exc:
        return (PR_OWNERSHIP_BLOCKED, f"auto-pass PR ownership gate failed to run: {exc}")
    finally:
        if state_path:
            try:
                os.unlink(state_path)
            except OSError:
                pass
    if proc.returncode == 0:
        return None
    detail = (proc.stderr or proc.stdout or "").strip().splitlines()
    reason = detail[0] if detail else f"auto-pass PR ownership gate exit {proc.returncode}"
    token = PR_DRAFT_BLOCKED if PR_DRAFT_BLOCKED in reason else PR_OWNERSHIP_BLOCKED
    return (token, reason)


for idx, row in enumerate(data.get("required_prs") or []):
    if not isinstance(row, dict):
        continue
    if not required_pr_ownership_required(row):
        continue
    gate_error = run_pr_ownership_gate(row)
    if gate_error is not None:
        token, detail = gate_error
        cross_errors.append((token, f"required_prs[{idx}] failed auto-pass PR ownership gate: {detail}"))

if terminal == "complete" and report_source_id:
    lifecycle = source_parent_lifecycle(specs_root, str(report_source_id))
    if lifecycle and lifecycle["namespace"] == "active" and lifecycle.get("status") != "IMPLEMENTED":
        cross_errors.append((
            TERMINAL_PARENT_NOT_ARCHIVED,
            f"{TERMINAL_PARENT_NOT_ARCHIVED}: complete report references active parent {lifecycle['path']} with status={lifecycle.get('status') or 'UNKNOWN'}; run mark-spec-implemented.sh {report_source_id} --auto-archive before terminal complete",
        ))

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


def archived_ledger_relocation(report_path, declared_path):
    """Resolve a ledger moved with its archived source container.

    The report writer records an absolute ledger path before source closeout.
    Archiving moves both files together, so that path becomes stale.  Accept
    only the deterministic moved-file identity: an archived source container,
    the same source-container basename, the exact ``artifacts/auto-pass``
    directory, and the same ledger basename.  Anything else remains a hard
    unreadable-ledger failure.
    """
    try:
        report_real = report_path.resolve(strict=True)
    except (OSError, RuntimeError):
        return (False, None)
    report_lexical = Path(os.path.abspath(os.path.normpath(str(report_path))))
    report_dir = report_lexical.parent
    if report_dir.name != "auto-pass" or report_dir.parent.name != "artifacts":
        return (False, None)

    container = report_dir.parent.parent
    archive_dir = container.parent
    dp_archive = archive_dir.name == "archive" and archive_dir.parent.name == "design-plans"
    company_archive = (
        archive_dir.name == "archive"
        and archive_dir.parent.parent.name == "companies"
    )
    if not (dp_archive or company_archive):
        return (False, None)

    # An archived report is always governed by relocation identity. It may
    # declare either the exact pre-archive path recorded before the move or the
    # exact current archive path after a canonical report rewrite. Compare only
    # normalized lexical paths: resolving the declared path would let a later
    # symlink at the old active location rewrite the ledger basename/identity.
    declared = Path(declared_path)
    if not declared.is_absolute():
        return (True, None)
    declared_lexical = Path(os.path.abspath(os.path.normpath(str(declared))))
    ledger_name = declared_lexical.name
    if not ledger_name:
        return (True, None)
    expected_archive = report_dir / ledger_name
    expected_active = archive_dir.parent / container.name / "artifacts" / "auto-pass" / ledger_name
    if declared_lexical not in (expected_active, expected_archive):
        return (True, None)

    candidate = expected_archive
    if candidate.is_symlink() or not candidate.is_file():
        return (True, None)
    try:
        candidate_real = candidate.resolve(strict=True)
    except (OSError, RuntimeError):
        return (True, None)
    if (
        candidate_real.parent != report_real.parent
        or candidate_real.name != ledger_name
        or candidate_real == report_real
    ):
        return (True, None)
    return (True, candidate_real)


# Load the referenced ledger once; consumed by the friction_log_summary check
# and the DP-311 T3 report↔ledger terminal cross-check.
ledger_payload = None
ledger_read_error = None
ledger_path_value = data.get("ledger_path")
if isinstance(ledger_path_value, str) and ledger_path_value:
    ledger_p = Path(ledger_path_value)
    relocation_applies, relocated_ledger = archived_ledger_relocation(path, ledger_path_value)
    if relocation_applies:
        if relocated_ledger is None:
            ledger_read_error = (
                "archived ledger relocation target is missing or unsafe: "
                f"{path.resolve(strict=False).parent / ledger_p.name}"
            )
        else:
            ledger_p = relocated_ledger
    if ledger_read_error is None:
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


def head_bound(recorded, requested):
    """True when the recorded delivery head matches requested (full/abbrev)."""
    if not recorded or not requested:
        return False
    recorded, requested = str(recorded), str(requested)
    return (
        recorded == requested
        or requested.startswith(recorded)
        or recorded.startswith(requested)
    )


def row_pick(row, *paths):
    """Return the first present, non-None value among nested key paths in row."""
    for path in paths:
        cur = row
        found = True
        for key in path:
            if isinstance(cur, dict) and key in cur:
                cur = cur[key]
            else:
                found = False
                break
        if found and cur is not None:
            return cur
    return None


def required_pr_evidence_publication_error(row):
    """DP-417 T6 / AC6 + AC-NEG2: PR-visible evidence publication ownership for a
    review-driven revision / head rebind.

    A required_prs[] row that declares a REVISED head (`revised_head_sha`, i.e. the
    head the PR rebound to after a review-driven revision) may only reach terminal
    `complete` once its PR-visible evidence publication marker is CURRENT at that
    revised head. A stale (old-head) or missing evidence-publication head fails
    closed so a revision that changed the head but did NOT re-publish evidence can
    never silently PASS. Freshness is decided by the module head_bound() comparator
    above — no second comparator. Rows without a revised head (first-cut delivery,
    not a head rebind) are not subject to this gate; route-back (terminal !=
    complete) is the AC6 escape hatch and is enforced by the caller.

    Returns (token, detail) on violation, else None.
    """
    if not isinstance(row, dict):
        return None
    revised = row_pick(
        row,
        ("revised_head_sha",),
        ("head_rebind_head_sha",),
        ("revision", "head_sha"),
        ("head_rebind", "head_sha"),
    )
    if revised is None:
        return None
    revised = str(revised)
    if not HEAD_SHA_PATTERN.fullmatch(revised):
        return (
            PR_EVIDENCE_PUBLICATION_STALE,
            f"revised_head_sha must be a 7-40 char hex sha, got {revised!r}",
        )
    published = row_pick(
        row,
        ("evidence_publication_head_sha",),
        ("evidence_publication", "head_sha"),
        ("evidence_publication", "head"),
    )
    if published is None or not str(published).strip():
        return (
            PR_EVIDENCE_PUBLICATION_STALE,
            "review-driven revision/head rebind requires a PR-visible evidence "
            f"publication marker current at the revised head {revised!r} "
            "(evidence publication head missing — revision did not re-publish evidence)",
        )
    published = str(published)
    if not head_bound(published, revised):
        return (
            PR_EVIDENCE_PUBLICATION_STALE,
            f"PR-visible evidence publication head {published!r} is stale: not current "
            f"at the revised head {revised!r} (revision changed the head but evidence "
            "was not re-published)",
        )
    return None


def resolve_task_md(work_item, scan_root):
    """Resolve the canonical task.md for work_item via resolve-task-md.sh.

    Uses the single canonical resolver (active or archived) so a V task.md that
    moved to pr-release/ still resolves. Returns the path string or None.
    """
    resolver = os.environ.get("RESOLVER")
    if not resolver or not scan_root:
        return None
    try:
        out = subprocess.run(
            ["bash", resolver, "--scan-root", scan_root, "--include-archive", work_item],
            capture_output=True, text=True, timeout=30,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    lines = out.stdout.strip().splitlines()
    if not lines:
        return None
    candidate = Path(lines[-1].strip())
    return str(candidate) if candidate.is_file() else None


def task_field(task_md, key):
    """Read one parse-task-md.sh --field value (stripped) or '' on any failure."""
    parser = os.environ.get("PARSER")
    if not parser:
        return ""
    try:
        out = subprocess.run(
            ["bash", parser, task_md, "--no-resolve", "--field", key],
            capture_output=True, text=True, timeout=30,
        )
    except Exception:
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


# ── DP-417 T6 / AC6 + AC-NEG2: revision/head-rebind evidence publication ──────
# PR-visible evidence publication ownership must be CLOSED at the revised head
# before terminal `complete`. Each required_prs[] row that declares a revised
# head (review-driven revision / head rebind) must carry a PR-visible evidence
# publication marker current at that head; stale (old head) or missing → fail
# closed (never a silent PASS). Non-complete terminals are the AC6 route-back
# escape hatch and are NOT gated here. Reuses head_bound() above (single
# comparator); complements the per-PR ownership gate run at required_prs above.
if terminal == "complete":
    for idx, row in enumerate(data.get("required_prs") or []):
        pub_error = required_pr_evidence_publication_error(row)
        if pub_error is not None:
            token, detail = pub_error
            cross_errors.append((token, f"required_prs[{idx}] {detail}"))

# ── DP-311 T3 cross-check (b), amended DP-360 T7: verification PASS ↔ task.md ──
# A PASS verification claim is only trusted when the V work item's task.md
# `deliverable` block records a delivered head (deliverable.head_sha) bound to
# the report's verification.head_sha AND deliverable.verification.status=PASS.
# DP-360 T7 retires the head-sha-keyed ac_verification marker; the task.md block
# is the sole durable delivery-evidence record. This reader NEVER reads a marker
# file (AC-NEG2) and NEVER falls back to a branch ref (AC-NEG1); the report's own
# prose/summary is never accepted as evidence.
if isinstance(verification, dict) and verification.get("status") == "PASS":
    work_item = verification.get("work_item_id")
    pinned_head = verification.get("head_sha")
    # Scan root for the canonical resolver: explicit evidence-root override
    # (hermetic selftests) else the resolved workspace root.
    scan_root = evidence_root or str(workspace_root)
    if not work_item:
        cross_errors.append((
            CROSS_MARKER_MISSING,
            "verification.status=PASS requires verification.work_item_id to locate the task.md deliverable block",
        ))
    elif pinned_head is not None and not HEAD_SHA_PATTERN.fullmatch(str(pinned_head)):
        cross_errors.append((
            CROSS_MARKER_MISMATCH,
            f"verification.head_sha must be a 7-40 char hex sha, got {pinned_head!r}",
        ))
    else:
        task_md = resolve_task_md(work_item, scan_root)
        if task_md is None:
            cross_errors.append((
                CROSS_MARKER_MISSING,
                "verification.status=PASS but no task.md resolvable for "
                f"{work_item} (deliverable block is the sole delivery-evidence source)",
            ))
        else:
            recorded_head = task_field(task_md, "deliverable_head_sha")
            block_status = task_field(task_md, "deliverable_verification_status")
            if not recorded_head:
                # No delivered head recorded at all → the delivery-evidence
                # record is absent (MISSING).
                cross_errors.append((
                    CROSS_MARKER_MISSING,
                    f"verification.status=PASS but {work_item} task.md has no "
                    "deliverable.head_sha (delivery-evidence record absent)",
                ))
            elif block_status != "PASS":
                # The block exists but its verification status contradicts the
                # report's PASS claim (stale summary is not trusted) → MISMATCH.
                cross_errors.append((
                    CROSS_MARKER_MISMATCH,
                    f"verification.status=PASS but {work_item} task.md "
                    f"deliverable.verification.status={block_status!r} is not PASS "
                    "(stale summary is not trusted)",
                ))
            elif pinned_head and not head_bound(recorded_head, pinned_head):
                cross_errors.append((
                    CROSS_MARKER_MISMATCH,
                    f"verification.head_sha={pinned_head!r} does not match the "
                    f"{work_item} task.md deliverable.head_sha={recorded_head!r}",
                ))

if errors or cross_errors:
    fail(errors, cross_errors)
print(f"PASS: auto-pass report validation ({path})")
PY
