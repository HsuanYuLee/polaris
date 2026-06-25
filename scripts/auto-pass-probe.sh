#!/usr/bin/env bash
# Purpose: auto-pass durable-evidence probe — for a given stage
#          (source/breakdown/engineering/verify-AC) read the durable delivery
#          evidence and emit the machine terminal status (PASS /
#          blocked_by_gate_failure / etc.) as JSON.
# Inputs:  --stage, --source-id, --work-item-id, [--head-sha], [--ledger],
#          [--pr-state-file], [--repo].
# Outputs: probe JSON on stdout; exit 0 on emit, 2 on usage error,
#          3 on fail-closed review-state unavailability (POLARIS_TOOL_MISSING).
#
# DP-360 T7: the engineering and verify-AC stages no longer read head-sha-keyed
# completion-gate / ac-verification markers. The delivered head and the
# verification disposition are read from the canonical task.md `deliverable`
# block (deliverable.head_sha + deliverable.verification.status), resolved by
# work_item_id through the single canonical resolve-task-md.sh (so a task.md
# that moved to pr-release/ or container archive after delivery still resolves).
# The three-layer local pre-push gate makes the pushed head verified-by-
# construction, so the persisted task.md head is the delivered-head authority —
# the probe NEVER falls back to a mutable branch ref. The breakdown stage still
# reads the task-snapshot marker (planning freshness, untouched); the amendment
# loop still reads spec-issue-{id}-{head}.json (distinct from ac-verification).
#
# DP-313 T1: at the engineering stage, AFTER the completion-gate marker is PASS,
# the probe optionally consumes a review-state classification supplied as
# EXPLICIT INPUT via --pr-state-file (a fixture / classifier-output JSON; the
# probe NEVER calls gh or any network itself). When the review state is
# actionable it routes back to the owning skill (engineering revision /
# breakdown / refinement amendment); otherwise it stays at parity with current
# behaviour and continues to verify-AC.
#
# DP-313 T3 (AC-NEG2): when --pr-state-file IS supplied (the orchestrator
# attempted a review-state read) but the state is UNAVAILABLE — the file is
# missing / unreadable / not JSON, or it explicitly signals gh/PR-state
# unavailability (tool_missing:true, or pr_state:UNKNOWN with no readiness) —
# the probe FAILS CLOSED: it writes POLARIS_TOOL_MISSING to stderr and exits 3
# instead of silently continuing to verify-AC and declaring the work item
# complete. Omitting --pr-state-file entirely is NOT a failure (parity,
# AC-NEG1): no review-state was requested, so the probe continues to verify-AC.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/auto-pass-probe.sh DP-NNN
  scripts/auto-pass-probe.sh --stage source --source-id DP-NNN [--repo PATH] [--ledger /absolute/path/to/ledger.json]
  scripts/auto-pass-probe.sh --stage breakdown|engineering|verify-AC
    --source-id DP-NNN --work-item-id DP-NNN-T1 [--repo PATH]
    [--head-sha SHA] [--ledger /absolute/path/to/ledger.json]
    [--pr-state-file /absolute/path/to/review-state.json]
USAGE
  exit 2
}

REPO="$(pwd)"
STAGE=""
SOURCE_ID=""
WORK_ITEM_ID=""
HEAD_SHA=""
LEDGER=""
PR_STATE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --stage) STAGE="${2:-}"; shift 2 ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --pr-state-file) PR_STATE_FILE="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *)
      if [[ -z "$STAGE" && -z "$SOURCE_ID" && "$1" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
        STAGE="source"
        SOURCE_ID="$1"
        WORK_ITEM_ID="$1"
        shift
      else
        echo "auto-pass-probe: unknown arg: $1" >&2
        usage
      fi
      ;;
  esac
done

if [[ -z "$STAGE" || -z "$SOURCE_ID" ]]; then
  usage
fi
case "$STAGE" in
  source|breakdown|engineering|verify-AC) ;;
  *) echo "auto-pass-probe: unsupported stage: $STAGE" >&2; exit 2 ;;
esac
if [[ "$STAGE" != "source" && -z "$WORK_ITEM_ID" ]]; then
  usage
fi
if [[ "$STAGE" == "source" && -z "$WORK_ITEM_ID" ]]; then
  WORK_ITEM_ID="$SOURCE_ID"
fi
if [[ ! -d "$REPO" ]]; then
  echo "auto-pass-probe: repo not found: $REPO" >&2
  exit 2
fi

SCRIPT_DIR_RESOLVED="$(cd "$(dirname "$0")" && pwd)"
RESOLVER="$SCRIPT_DIR_RESOLVED/spec-source-resolver.sh"
TASK_MD_RESOLVER="$SCRIPT_DIR_RESOLVED/resolve-task-md.sh"
TASK_MD_PARSER="$SCRIPT_DIR_RESOLVED/parse-task-md.sh"

python3 - "$REPO" "$STAGE" "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" "$LEDGER" "$RESOLVER" "$PR_STATE_FILE" "$TASK_MD_RESOLVER" "$TASK_MD_PARSER" <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
stage, source_id, work_item_id, head_sha, ledger_arg, resolver_path, pr_state_file = sys.argv[2:9]
task_md_resolver_path, task_md_parser_path = sys.argv[9:11]


def marker(path):
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"status": "UNKNOWN", "invalid_json": True}


def emit(status, terminal_status, next_action, evidence_path=None, reason=None):
    payload = {
        "schema_version": 1,
        "stage": stage,
        "source_id": source_id,
        "work_item_id": work_item_id,
        "status": status,
        "terminal_status": terminal_status,
        "next_action": next_action,
        "evidence_path": str(evidence_path) if evidence_path else None,
        "reason": reason,
    }
    # DP-220: deterministic friction trigger — UNKNOWN means probe could not
    # determine outcome from durable evidence; flag as deterministic_gap so the
    # /auto-pass ledger has an audit trail. NOOP when AUTO_PASS_LEDGER_PATH is
    # unset or ledger missing (helper handles both).
    if status == "UNKNOWN":
        ledger_env = os.environ.get("AUTO_PASS_LEDGER_PATH", "")
        if ledger_env:
            helper = repo / "scripts" / "append-auto-pass-friction.sh"
            if helper.is_file():
                try:
                    summary = f"probe UNKNOWN: stage={stage} source={source_id} work_item={work_item_id} reason={reason or 'n/a'} (auto-trigger from auto-pass-probe, DP-220)"
                    subprocess.run(
                        [
                            "bash",
                            str(helper),
                            ledger_env,
                            "--stage",
                            stage if stage in {"source", "breakdown", "engineering", "verify-AC", "framework-release", "post-task"} else "post-task",
                            "--kind",
                            "deterministic_gap",
                            "--contract-evidence",
                            ".claude/skills/references/friction-capture-contract.md:85",
                            "--summary",
                            summary[:280],
                        ],
                        check=False,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=2.0,
                    )
                except Exception:
                    pass
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    raise SystemExit(0)


def status_of(path):
    data = marker(path)
    if not data:
        return None
    return data.get("status") or "UNKNOWN"


def resolve_task_md(wid):
    """Resolve the canonical task.md path for work_item_id (active or archived).

    DP-360 T7: delegates to the single canonical resolve-task-md.sh so a task.md
    that moved to pr-release/ or container archive after delivery still resolves.
    Returns the path string or None.
    """
    try:
        out = subprocess.run(
            ["bash", task_md_resolver_path, "--scan-root", str(repo),
             "--include-archive", wid],
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
    """Read one parse-task-md.sh --field value (stripped) or empty string."""
    try:
        out = subprocess.run(
            ["bash", task_md_parser_path, task_md, "--no-resolve", "--field", key],
            capture_output=True, text=True, timeout=30,
        )
    except Exception:
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def head_bound(recorded, requested):
    """True when the recorded delivery head matches the requested head.

    Accepts full/abbreviated prefix matches in either direction so a 40-char
    recorded sha matches a 7-char probe head and vice versa.
    """
    if not recorded:
        return False
    return (
        recorded == requested
        or requested.startswith(recorded)
        or recorded.startswith(requested)
    )


def ac_verification_status(task_md):
    """Read the V-task `ac_verification.status` frontmatter block value.

    DP-360 T7: the verify-AC disposition for a V work item lives in the V-task's
    own `ac_verification` frontmatter block (the canonical V-task lifecycle
    record read by the runner / close-parent / detect-closeout-drift), NOT a
    head-sha-keyed marker. Mirrors close-parent-spec-if-complete's reader.
    Returns the status string or "" when absent.
    """
    try:
        lines = Path(task_md).read_text(encoding="utf-8").splitlines()
    except OSError:
        return ""
    in_block = False
    for line in lines:
        if line == "ac_verification:":
            in_block = True
            continue
        if in_block and line and not line.startswith((" ", "-")) and ":" in line:
            break
        if in_block:
            m = re.match(r"\s+status:\s*(\S+)", line)
            if m:
                return m.group(1).strip().strip('"').strip("'")
    return ""


def frontmatter_status(path: Path):
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    for raw in text[4:end].splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        if key.strip() == "status":
            return value.strip().strip('"').strip("'")
    return None


def refinement_hash(container: Path):
    digest = hashlib.sha256()
    for name in ("refinement.md", "refinement.json"):
        path = container / name
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return "sha256:" + digest.hexdigest()


def resolve_source(sid):
    """Call spec-source-resolver.sh to find the source container.

    Returns (resolver_json_dict, error_tuple_or_None).
    error_tuple shape: (status, terminal_status, next_action, evidence_path, reason)
    so callers can directly forward to emit().
    """
    specs_root_default = repo / "docs-manager" / "src" / "content" / "docs" / "specs"
    cmd = ["bash", resolver_path, "--source-id", sid]
    if specs_root_default.is_dir():
        cmd.extend(["--specs-root", str(specs_root_default)])
    try:
        proc = subprocess.run(
            cmd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5.0,
        )
    except FileNotFoundError:
        return None, ("UNKNOWN", "blocked_by_gate_failure", "blocked", None,
                      f"spec-source-resolver.sh not found at {resolver_path}")
    except Exception as exc:
        return None, ("UNKNOWN", "blocked_by_gate_failure", "blocked", None,
                      f"spec-source-resolver.sh invocation failed: {exc}")
    if proc.returncode != 0:
        stderr_text = (proc.stderr or b"").decode("utf-8", errors="replace").strip()
        # POLARIS_SOURCE_MISSING / DUPLICATE / INVALID → BLOCKED (not UNKNOWN)
        return None, ("BLOCKED", "blocked_by_gate_failure", "blocked", None,
                      stderr_text or f"resolver exit {proc.returncode}")
    try:
        return json.loads(proc.stdout.decode("utf-8")), None
    except Exception as exc:
        return None, ("UNKNOWN", "blocked_by_gate_failure", "blocked", None,
                      f"resolver output not JSON: {exc}")


def _counter_count(value):
    # DP-246 T2 dual-shape: legacy int N or {"count": N, "evidence_ids": [...]}.
    # Mirrors validate-auto-pass-ledger.sh._counter_count() to keep probe parity.
    if isinstance(value, bool):
        return 0
    if isinstance(value, int):
        return value if value >= 0 else 0
    if isinstance(value, dict):
        count = value.get("count")
        if isinstance(count, int) and not isinstance(count, bool) and count >= 0:
            return count
    return 0


def ledger_terminal():
    if not ledger_arg:
        return None
    ledger_path = Path(ledger_arg)
    if not ledger_path.is_absolute() or not ledger_path.is_file():
        return ("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "ledger missing or not absolute")
    try:
        data = json.loads(ledger_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return ("UNKNOWN", "blocked_by_gate_failure", "blocked", ledger_path, f"ledger invalid JSON: {exc}")
    loops = data.get("loop_counters") or {}
    eng_count = _counter_count(loops.get("engineering_to_breakdown", 0))
    brk_count = _counter_count(loops.get("breakdown_to_refinement_inbox", 0))
    if max(eng_count, brk_count) >= 3:
        return ("BLOCKED", "loop_cap_reached", "blocked", ledger_path, "planning loop cap reached")
    drift = data.get("drift_retry") or {}
    if _counter_count(drift.get(work_item_id, 0)) >= 3:
        return ("BLOCKED", "blocked_by_gate_failure", "blocked", ledger_path, "drift retry cap reached")
    return None


def _resolve_or_emit(sid):
    """Resolve source via resolver; if resolver errored, emit() and never return."""
    resolved, err = resolve_source(sid)
    if err is not None:
        emit(*err)
    return resolved


def emit_tool_missing(reason, evidence_path=None):
    """Fail-closed exit for an unavailable review-state read (DP-313 T3, AC-NEG2).

    The orchestrator supplied --pr-state-file (it attempted a gh/PR-state read)
    but the resulting state is unavailable. Per pr-state-contract.md § Fail-Closed
    Rules and the Tool Missing Discipline, the probe must NOT silently continue to
    verify-AC and let the work item be declared complete. It writes
    POLARIS_TOOL_MISSING to stderr (so hooks / orchestrator can grep it) and exits
    3 with no stdout JSON, which the runner maps to blocked_by_gate_failure.

    Args:
        reason: short human-readable cause for the unavailability.
        evidence_path: the offending --pr-state-file path, or None.
    """
    detail = f": {evidence_path}" if evidence_path else ""
    print(f"POLARIS_TOOL_MISSING:gh review-state unavailable ({reason}){detail}",
          file=sys.stderr)
    raise SystemExit(3)


def review_state_route(state_file_arg):
    """Map an explicit review-state classification to a route-back emit tuple.

    DP-313 T1: the review state arrives as EXPLICIT INPUT — a fixture /
    classifier-output JSON path. The probe NEVER calls gh or any network here;
    the orchestrator owns the live gh read + head-rebind and hands the probe a
    materialized state file.

    The fixture shape mirrors pr-action-classifier.sh output:
        {"readiness_state": "<vocab token>", "revision_class": "<R3 class>"}
    using the pr-state-contract.md readiness vocabulary and the
    engineering-revision-flow.md R3 classes (code_drift / plan_gap / spec_issue).

    DP-313 T3 (AC-NEG2): a SUPPLIED-but-UNAVAILABLE review state (missing file /
    unreadable / not JSON / explicit gh-or-PR-state unavailability sentinel) is a
    fail-closed condition, not parity — it calls emit_tool_missing() and never
    returns. Only an ABSENT --pr-state-file (state_file_arg == "") stays at parity
    (the orchestrator did not request a review-state read).

    Args:
        state_file_arg: absolute path to the review-state JSON, or "" when no
            explicit input was supplied.

    Returns:
        An emit() tuple (status, terminal_status, next_action, evidence_path,
        reason) for an actionable route-back, or None when no review-state was
        requested OR the state is present-and-non-actionable — in which case the
        caller keeps parity with current behaviour (continue to verify-AC).
        terminal_status stays null for every route-back (non-terminal dispatch,
        mirroring the refinement_amendment shape in auto-pass-execution-flow.md).
    """
    # No review-state requested at all → parity (AC-NEG1): the orchestrator did
    # not attempt a read, so there is nothing to fail closed on.
    if not state_file_arg:
        return None
    # From here on a read WAS requested. Any unavailability fails closed (AC-NEG2).
    state_path = Path(state_file_arg)
    if not state_path.is_file():
        emit_tool_missing("pr-state file missing", state_path)
    try:
        data = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception as exc:
        emit_tool_missing(f"pr-state file not JSON: {exc}", state_path)
    if not isinstance(data, dict):
        emit_tool_missing("pr-state file is not a JSON object", state_path)
    # Explicit unavailability sentinel: the orchestrator's gh read failed and it
    # recorded that in the state file rather than a real classification.
    if data.get("tool_missing") is True:
        emit_tool_missing("classifier reported tool_missing", state_path)
    readiness = data.get("readiness_state")
    revision_class = data.get("revision_class")
    # A file with neither a readiness token nor a revision class carries no usable
    # PR state (e.g. pr_state:UNKNOWN with no classification) → fail closed.
    if not readiness and not revision_class:
        emit_tool_missing("pr-state file has no readiness_state/revision_class", state_path)
    # Spec issue (R3 spec_issue) routes to refinement amendment regardless of the
    # collapsed readiness token, matching engineering-revision-flow.md R3a.
    if revision_class == "spec_issue":
        return ("ROUTE_BACK_AMEND", None, "refinement_amendment", state_path,
                "review spec issue (amendment loop)")
    if readiness == "needs_code_changes":
        return ("ROUTE_BACK_REVISION", None, "engineering", state_path,
                "actionable review signal (revision)")
    if readiness == "planning_gap":
        return ("ROUTE_BACK_BREAKDOWN", None, "breakdown", state_path,
                "review planning gap (breakdown)")
    # review_required / awaiting_re_review / mergeable_ready / wait_ci and any
    # other present, non-actionable state → parity: continue to verify-AC.
    return None


if stage == "source":
    # AC12: source resolution delegated to spec-source-resolver.sh; non-DP keys
    # (JIRA / Epic) resolve via companies/{company}/{KEY} containers and must
    # not fall back to UNKNOWN solely because the id is not DP-shaped.
    resolved = _resolve_or_emit(source_id)
    container = Path(resolved["container"])
    # AC-NEG7: archived source is read-only; auto-pass must not treat it as
    # an active LOCKED delivery surface.
    if resolved.get("archived"):
        emit("BLOCKED", "blocked_by_gate_failure", "blocked", container,
             "source is archived (read-only); auto-pass requires active source")
    missing = [name for name in ("refinement.md", "refinement.json") if not (container / name).is_file()]
    if not resolved.get("primary_doc"):
        missing.insert(0, "primary doc (index.md|plan.md|refinement.md)")
    if missing:
        emit("BLOCKED", "blocked_by_gate_failure", "blocked", container,
             "missing source artifacts: " + ", ".join(missing))
    primary_doc = Path(resolved["primary_doc"])
    status = resolved.get("status") or frontmatter_status(primary_doc)
    if status != "LOCKED":
        emit("BLOCKED", "blocked_by_gate_failure", "blocked", primary_doc,
             f"source status must be LOCKED, got {status or 'missing'}")
    try:
        refinement = json.loads((container / "refinement.json").read_text(encoding="utf-8"))
    except Exception as exc:
        emit("BLOCKED", "blocked_by_gate_failure", "blocked", container / "refinement.json",
             f"refinement.json invalid JSON: {exc}")
    ref_source = refinement.get("source") or {}
    if ref_source.get("id") and ref_source.get("id") != source_id:
        emit("BLOCKED", "blocked_by_gate_failure", "blocked", container / "refinement.json",
             "refinement.json source.id mismatch")
    if ledger_arg:
        ledger_path = Path(ledger_arg)
        if not ledger_path.is_absolute() or not ledger_path.is_file():
            emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None,
                 "ledger missing or not absolute")
        try:
            ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        except Exception as exc:
            emit("UNKNOWN", "blocked_by_gate_failure", "blocked", ledger_path,
                 f"ledger invalid JSON: {exc}")
        ledger_source = ledger.get("source") or {}
        if ledger_source.get("id") != source_id:
            emit("BLOCKED", "blocked_by_gate_failure", "blocked", ledger_path,
                 "ledger source.id mismatch")
        if ledger_source.get("refinement_hash") != refinement_hash(container):
            emit("BLOCKED", "blocked_by_gate_failure", "blocked", ledger_path,
                 "ledger refinement hash stale")
    emit("PASS", None, "breakdown", container)


ledger_result = ledger_terminal()
if ledger_result:
    emit(*ledger_result)


def resolve_evidence_root():
    """Resolve the .polaris/evidence root SYMMETRICALLY with the marker writer.

    DP-338 D2: for a JIRA-Epic-backed source the spec container lives in the
    Polaris workspace (companies/{co}/{EPIC}) but the breakdown / engineering
    evidence is written into the PRODUCT repo — the marker writer
    (breakdown-emit-task-snapshot.sh) emits a relative .polaris/evidence path
    from the product-repo cwd. The orchestrator invokes this probe with --repo =
    the workspace main-checkout, so reading {repo}/.polaris/evidence would miss
    the marker. We therefore resolve the product repo the same way the canonical
    resolve-task-base.sh::derive_repo_path does — the task.md `Repo:` header maps
    to {workspace_root}/{repo_name} — and read evidence there.

    This is a READER-only change (AC9: single writer untouched). It NEVER writes
    or band-aids a marker into the workspace root (AC-NEG2): when the product
    repo or its evidence is absent the reader simply does not find the marker and
    the stage blocks fail-loud.

    DP-backed sources keep reading {repo}/.polaris/evidence unchanged (symmetry).
    JIRA sources fall back to {repo} only when the product repo cannot be
    resolved (no task.md yet / no Repo header / repo dir absent) — that fallback
    is a resolution miss, not a synthesized workspace-root marker, so a genuinely
    missing marker still blocks.

    Returns the evidence root Path ({...}/.polaris/evidence).
    """
    default_root = repo / ".polaris" / "evidence"
    resolved, err = resolve_source(source_id)
    if err is not None or not resolved:
        return default_root
    if resolved.get("source_type") != "jira":
        return default_root
    container = Path(resolved.get("container") or "")
    # The work_item_id is the de-conflated canonical {Epic}-T{n} (DP-338 D1);
    # its trailing stem maps to {container}/tasks/{stem}[/index.md|.md]. Resolve
    # the task.md within the already-resolved container (resolve-task-md.sh keys
    # JIRA tasks by delivery_ticket_key, not by work_item_id, so we locate the
    # file by container + stem instead and read its `Repo:` header).
    stem = work_item_id.split("-")[-1]
    task_md = None
    for candidate in (
        container / "tasks" / stem / "index.md",
        container / "tasks" / f"{stem}.md",
        container / "tasks" / "pr-release" / stem / "index.md",
        container / "tasks" / "pr-release" / f"{stem}.md",
    ):
        if candidate.is_file():
            task_md = str(candidate)
            break
    if task_md is None:
        return default_root
    repo_name = task_field(task_md, "repo")
    if not repo_name:
        return default_root
    # specs_root = {workspace_root}/docs-manager/src/content/docs/specs; the
    # product repo is a sibling of the workspace root at {workspace_root}/{repo}.
    # Walk up the container to the nearest `specs` ancestor, then strip the
    # canonical docs-manager suffix to get the workspace root (mirrors
    # resolve-task-base.sh::derive_repo_path's specs-ancestor walk).
    specs_dir = None
    for ancestor in container.parents:
        if ancestor.name == "specs":
            specs_dir = ancestor
            break
    if specs_dir is None:
        return default_root
    suffix = Path("docs-manager") / "src" / "content" / "docs" / "specs"
    if specs_dir.match(str(suffix) + "/*") or str(specs_dir).endswith(str(suffix)):
        workspace_root = Path(str(specs_dir)[: -(len(str(suffix)) + 1)])
    else:
        workspace_root = specs_dir.parent
    product_repo = workspace_root / repo_name
    if not product_repo.is_dir():
        return default_root
    return product_repo / ".polaris" / "evidence"


evidence = resolve_evidence_root()

if stage == "breakdown":
    for subdir, terminal, action, default_reason in (
        ("validation-fail", "blocked_by_gate_failure", "blocked", "breakdown validation failed"),
        ("missing-v-task", "blocked_by_gate_failure", "breakdown", "missing V task"),
    ):
        path = evidence / subdir / f"{work_item_id}.json"
        if path.is_file():
            # DP-269 AC3: surface the marker's own `reason` (specific cause
            # written by breakdown-emit-blocker-marker.sh) so the orchestrator
            # reports a readable blocked_by_gate_failure cause instead of the
            # generic "breakdown PASS marker missing". Fall back to the subdir's
            # default reason only when the marker omits one.
            marker_data = marker(path) or {}
            marker_reason = marker_data.get("reason")
            reason = marker_reason if isinstance(marker_reason, str) and marker_reason.strip() else default_reason
            emit(status_of(path) or "BLOCKED", terminal, action, path, reason)
    # AC13: amendment inbox scan is source-neutral. Use spec-source-resolver
    # to find the source container (DP under design-plans/ or JIRA Epic under
    # companies/{company}/{KEY}/), then look at {container}/refinement-inbox/.
    inbox_resolved, inbox_err = resolve_source(source_id)
    inbox_matches = []
    if inbox_err is None and inbox_resolved:
        container_path = Path(inbox_resolved["container"])
        # DP-212 amendment loop: only unconsumed inbox records trigger amendment.
        # Files with `consumed: true` in YAML frontmatter have already been
        # processed by a prior refinement amendment round and must not re-route.
        for p in sorted((container_path / "refinement-inbox").glob("*.md")):
            try:
                head = p.read_text(encoding="utf-8")
            except Exception:
                continue
            if head.startswith("---"):
                end = head.find("\n---", 3)
                fm = head[3:end] if end > 0 else head[3:]
            else:
                fm = head
            consumed = False
            for line in fm.splitlines():
                stripped = line.strip()
                if stripped.startswith("consumed:"):
                    val = stripped.split(":", 1)[1].strip().lower()
                    if val in ("true", "yes"):
                        consumed = True
                    break
            if not consumed:
                inbox_matches.append(p)
    if inbox_matches:
        # DP-212: refinement-inbox presence is now a non-terminal signal —
        # auto-pass dispatches `refinement` in amendment mode, then loops
        # back to breakdown. terminal_status stays null so the orchestrator
        # does not stop unless counter cap or scope guard fires.
        emit("ROUTE_BACK_AMEND", None, "refinement_amendment", inbox_matches[0], "refinement inbox present (amendment loop)")
    path = evidence / "task-snapshot" / f"{work_item_id}.json"
    if status_of(path) == "PASS":
        emit("PASS", None, "engineering", path)
    emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "breakdown PASS marker missing")

if stage == "engineering":
    if not head_sha:
        emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "engineering probe requires --head-sha")
    for subdir, reason in (
        ("blocked-conflict", "blocked conflict"),
        ("unsupported-mutation", "unsupported mutation"),
    ):
        path = evidence / subdir / f"{work_item_id}-{head_sha}.json"
        if path.is_file():
            emit(status_of(path) or "BLOCKED", "blocked_by_gate_failure", "blocked", path, reason)
    # DP-360 T7: the delivered head + completion disposition are read from the
    # canonical task.md `deliverable` block (no head-sha-keyed completion-gate
    # marker). The local three-layer pre-push gate makes the pushed head
    # verified-by-construction, so a task.md whose deliverable.head_sha is bound
    # to the probe head and whose deliverable.verification.status == PASS is the
    # engineering-stage PASS signal. We NEVER fall back to a branch ref.
    task_md = resolve_task_md(work_item_id)
    if task_md is None:
        emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None,
             "task.md not resolvable for delivered-head read")
    recorded_head = task_field(task_md, "deliverable_head_sha")
    if not head_bound(recorded_head, head_sha):
        emit("UNKNOWN", "blocked_by_gate_failure", "blocked", Path(task_md),
             "deliverable.head_sha not bound to probe head")
    if task_field(task_md, "deliverable_verification_status") == "PASS":
        # DP-313 T1: AFTER the delivered head/disposition is PASS, consume the
        # explicit review-state classification (if any) before forwarding to
        # verify-AC. Non-actionable / absent state → parity (continue).
        route = review_state_route(pr_state_file)
        if route is not None:
            emit(*route)
        emit("PASS", None, "verify-AC", Path(task_md))
    emit("UNKNOWN", "blocked_by_gate_failure", "blocked", Path(task_md),
         "task.md deliverable.verification.status not PASS")

if stage == "verify-AC":
    if not head_sha:
        emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None, "verify-AC probe requires --head-sha")
    spec_issue = evidence / "ac-verification" / f"spec-issue-{work_item_id}-{head_sha}.json"
    if spec_issue.is_file():
        # DP-212: spec_issue → non-terminal amendment loop (same as breakdown
        # inbox presence). terminal_status stays null; orchestrator continues
        # to dispatch refinement amendment mode until cap or scope guard fires.
        emit(status_of(spec_issue) or "ROUTE_BACK_AMEND", None, "refinement_amendment", spec_issue, "verify-AC spec issue (amendment loop)")
    # DP-360 T7: the verify-AC disposition for a V work item is read from the
    # V-task's `ac_verification` frontmatter block (the canonical V-task
    # lifecycle record, also read by the runner / close-parent / drift detector),
    # resolved by work_item_id (active or archived). This block is NOT head-keyed
    # and is NOT a separate marker — it is the V-task's own authority. We NEVER
    # fall back to a branch ref.
    task_md = resolve_task_md(work_item_id)
    if task_md is None:
        emit("UNKNOWN", "blocked_by_gate_failure", "blocked", None,
             "task.md not resolvable for verification disposition read")
    status = ac_verification_status(task_md) or "UNKNOWN"
    if status == "PASS":
        emit("PASS", "complete", "report", Path(task_md))
    if status in {"MANUAL_REQUIRED", "BLOCKED_ENV"}:
        emit(status, "paused_for_user_external_write", "user", Path(task_md), status)
    if status in {"UNCERTAIN", "FAIL", "UNKNOWN"}:
        emit(status, "blocked_by_gate_failure", "blocked", Path(task_md), "verification not pass")
    emit("UNKNOWN", "blocked_by_gate_failure", "blocked", Path(task_md),
         "V-task ac_verification.status missing")
PY
