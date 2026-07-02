#!/usr/bin/env bash
# scripts/auto-pass-runner.sh — DP-237 deterministic auto-pass runner.
#
# Runner-first contract (DP-237 T3): this script is the SINGLE next-action
# authority for /auto-pass orchestration. The orchestrator reads runner JSON
# (schema_version=1, fields documented below) and dispatches based on
# next_action / next_skill / terminal_status alone — it does NOT re-run
# auto-pass-probe.sh, re-parse the ledger, or walk .polaris/evidence/**
# between stages.
#
# Internally the runner still wraps existing tools (spec-source-resolver,
# auto-pass-probe, validate-auto-pass-ledger). Those are implementation
# detail; the orchestrator contract is the JSON shape below.
#
# The runner is read-only, with one declared exception:
# - It NEVER calls release, deploy, merge, or any code mutation.
# - It NEVER writes task.md, refinement.md, refinement.json, or any
#   workflow artifact — EXCEPT the DP-311 Terminal Complete Sequence:
#   before declaring terminal_status=complete it advances every required V
#   work item whose ac_verification block is PASS with
#   human_disposition=passed through the existing canonical task-level
#   writer scripts/mark-spec-implemented.sh (move → tasks/pr-release/ +
#   status IMPLEMENTED), then fail-closed confirms every required V work
#   item reached the canonical terminal contract (pr-release/ + IMPLEMENTED
#   + ac_verification PASS, same contract as
#   close-parent-spec-if-complete.sh). Any miss downgrades the result to
#   blocked_by_gate_failure instead of complete.
# - It NEVER reads inner-skill prose ("PASS" text) to escalate status;
#   missing / UNKNOWN markers are always blocked_by_gate_failure.
#
# Portability: runner authority is portable across LLM runtimes (Claude Code,
# Codex, others). It does NOT depend on Claude-only hooks, Claude-only env
# vars, or any specific MCP server. Runtime adapters may invoke the same
# script through the same JSON contract.
#
# Output (stable JSON, schema_version=1):
#   {
#     "schema_version": 1,
#     "source_id": "DP-237",
#     "stage": "source|breakdown|engineering|verify-AC",
#     "status": "PASS|UNKNOWN|HALT|FAIL|BLOCKED|ROUTE_BACK_AMEND|...",
#     "terminal_status": "complete|loop_cap_reached|blocked_by_gate_failure
#                         |paused_for_session_handoff|paused_for_user_external_write
#                         |null",
#     "next_action": "dispatch|blocked|terminal|resume|refinement_amendment|...",
#     "next_skill": "breakdown|engineering|verify-AC|refinement|null",
#     "next_work_item_id": "DP-237-T1|null",
#     "evidence_path": "/abs/path|null",
#     "reason": "short string"
#   }
#
# Usage:
#   scripts/auto-pass-runner.sh DP-NNN
#   scripts/auto-pass-runner.sh --source-id DP-NNN [--stage source]
#     [--repo /abs/path] [--ledger /abs/path]
#   scripts/auto-pass-runner.sh --source-id DP-NNN
#     --stage breakdown|engineering|verify-AC
#     --work-item-id DP-NNN-T1
#     [--head-sha SHA] [--ledger /abs/path] [--repo /abs/path]
#     [--pr-state-file /abs/path]
#
# DP-313 T1: at the engineering stage, --pr-state-file passes an explicit
# review-state classification (a fixture / pr-action-classifier.sh output JSON;
# never a live gh read inside the runner/probe) that the runner forwards to the
# probe. After the completion-gate marker is PASS, an actionable review state
# routes back to the owning skill: needs_code_changes → engineering (revision),
# planning_gap → breakdown, spec issue → refinement (amendment). Any
# non-actionable state (or no file) keeps parity with current behaviour and
# continues to verify-AC.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/auto-pass-runner.sh DP-NNN
  scripts/auto-pass-runner.sh --source-id DP-NNN [--stage source]
    [--repo /abs/path] [--ledger /abs/path]
  scripts/auto-pass-runner.sh --source-id DP-NNN
    --stage breakdown|engineering|verify-AC
    --work-item-id DP-NNN-T1
    [--head-sha SHA] [--ledger /abs/path] [--repo /abs/path]
    [--pr-state-file /abs/path]
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
        SOURCE_ID="$1"
        shift
      else
        echo "auto-pass-runner: unknown arg: $1" >&2
        usage
      fi
      ;;
  esac
done

if [[ -z "$SOURCE_ID" ]]; then
  usage
fi
if [[ -z "$STAGE" ]]; then
  STAGE="source"
fi
case "$STAGE" in
  source|breakdown|engineering|verify-AC) ;;
  *) echo "auto-pass-runner: unsupported stage: $STAGE" >&2; exit 2 ;;
esac
if [[ "$STAGE" == "source" && -z "$WORK_ITEM_ID" ]]; then
  WORK_ITEM_ID="$SOURCE_ID"
fi
if [[ "$STAGE" != "source" && -z "$WORK_ITEM_ID" ]]; then
  echo "auto-pass-runner: --work-item-id required for stage=$STAGE" >&2
  usage
fi
if [[ ! -d "$REPO" ]]; then
  echo "auto-pass-runner: repo not found: $REPO" >&2
  exit 2
fi

SCRIPT_DIR_RESOLVED="$(cd "$(dirname "$0")" && pwd)"
PROBE="$SCRIPT_DIR_RESOLVED/auto-pass-probe.sh"
LEDGER_VALIDATOR="$SCRIPT_DIR_RESOLVED/validate-auto-pass-ledger.sh"

if [[ ! -x "$PROBE" && ! -f "$PROBE" ]]; then
  echo "auto-pass-runner: probe not found at $PROBE" >&2
  exit 2
fi

# Capture probe output (the probe already returns JSON with schema_version=1).
PROBE_ARGS=(--repo "$REPO" --stage "$STAGE" --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID")
if [[ -n "$HEAD_SHA" ]]; then
  PROBE_ARGS+=(--head-sha "$HEAD_SHA")
fi
if [[ -n "$LEDGER" ]]; then
  PROBE_ARGS+=(--ledger "$LEDGER")
fi
# DP-313 T1: forward the explicit review-state input to the probe. The runner
# does not interpret the file itself; the probe owns the actionable / parity
# classification and emits a route-back the runner mirrors below.
if [[ -n "$PR_STATE_FILE" ]]; then
  PROBE_ARGS+=(--pr-state-file "$PR_STATE_FILE")
fi

# Probe writes JSON to stdout; stderr carries ledger-friction side effects and,
# for the DP-313 T3 fail-closed path, a POLARIS_TOOL_MISSING marker (review-state
# unavailable, probe exit 3). Capture stderr to a temp file so the runner can
# re-surface that marker instead of swallowing it (AC-NEG2): a fail-open here
# would silently let the work item be declared complete.
PROBE_STDERR_FILE="$(mktemp)"
trap 'rm -f "$PROBE_STDERR_FILE"' EXIT
set +e
PROBE_OUTPUT_RAW="$(bash "$PROBE" "${PROBE_ARGS[@]}" 2>"$PROBE_STDERR_FILE")"
PROBE_RC=$?
set -e
export PROBE_OUTPUT_RAW

# DP-313 T3 (AC-NEG2): the probe fails closed with exit 3 + POLARIS_TOOL_MISSING
# on stderr when --pr-state-file was supplied but the review state is unavailable
# (gh missing / PR state unreadable). Re-surface that marker on the runner's own
# stderr before mapping the blocked result, so hooks / orchestrator can grep it.
if [[ "$PROBE_RC" -eq 3 ]] && grep -q 'POLARIS_TOOL_MISSING' "$PROBE_STDERR_FILE"; then
  cat "$PROBE_STDERR_FILE" >&2
fi

python3 - "$STAGE" "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" "$LEDGER" "$PROBE_RC" "$LEDGER_VALIDATOR" "$REPO" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

stage, source_id, work_item_id, head_sha, ledger_arg, probe_rc, ledger_validator, repo = sys.argv[1:9]
probe_rc = int(probe_rc)
probe_raw = os.environ.get("PROBE_OUTPUT_RAW", "")
# fallback path: read from stdin file descriptor via env-passed text. Bash side
# uses a heredoc, so we pull from the shell-set variable indirectly. To keep
# this tractable, the bash shell passes the text via the PROBE_OUTPUT env var.

probe_data = None
probe_error = None
if probe_raw:
    try:
        probe_data = json.loads(probe_raw)
    except Exception as exc:
        probe_error = f"probe output not JSON: {exc}"
elif probe_rc == 3:
    # DP-313 T3 (AC-NEG2): probe fail-closed on an unavailable review-state read.
    # Stays blocked_by_gate_failure — never silently complete. The runner already
    # re-surfaced POLARIS_TOOL_MISSING on its own stderr above.
    probe_error = "review-state unavailable (POLARIS_TOOL_MISSING); fail-closed"
elif probe_rc != 0:
    probe_error = f"probe exited rc={probe_rc} with empty stdout"
else:
    probe_error = "probe produced empty stdout"


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    raise SystemExit(0)


# ── DP-311 T1: Terminal Complete Sequence ────────────────────────────────────
# Before the runner declares terminal_status=complete (fresh verify-AC PASS and
# the resume-complete rerun of the same stage), it must:
#   (a) advance every required V work item whose ac_verification frontmatter is
#       PASS with human_disposition=passed through the existing canonical
#       task-level writer scripts/mark-spec-implemented.sh, and
#   (b) fail-closed confirm that every required V work item reached the
#       canonical terminal contract — pr-release/ + status IMPLEMENTED +
#       ac_verification PASS — the single contract owned by
#       close-parent-spec-if-complete.sh (AC-NEG3: no second contract; this
#       gate only invokes the existing writer and re-reads the same canonical
#       V task file state, never the ac-verification marker alone).
# Non-PASS verdicts (FAIL / MANUAL_REQUIRED / UNCERTAIN / BLOCKED_ENV) are
# never advanced (AC-NEG1). ABANDONED V siblings keep the close-parent
# carve-out: left in place, not blocking. T (implementation) tasks are never
# touched (AC-NEG2).

V_STEM_RE = re.compile(r"^V\d+[a-z]*$")
T_STEM_RE = re.compile(r"^T\d+[a-z]*$")
# DP-317: task_shape values that take the DP-262 specs-only / no-PR completion
# path; the implementation T-assert leaves them in place (not advanced, not
# blocked). Absent / empty task_shape defaults to "implementation".
T_CARVE_OUT_SHAPES = frozenset({"audit", "confirmation"})
# Resolver lookup mirrors auto-pass-probe.sh resolve_source timeout budget.
RESOLVER_TIMEOUT_SECONDS = 5.0
# mark-spec-implemented does frontmatter rewrite + directory move; generous cap.
MARK_SPEC_TIMEOUT_SECONDS = 30.0


def read_frontmatter_lines(path):
    """Return frontmatter lines of a markdown file, or [] when absent/unreadable."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return []
    if not text.startswith("---\n"):
        return []
    end = text.find("\n---", 4)
    if end == -1:
        return []
    return text[4:end].splitlines()


def frontmatter_status(path):
    """Read the top-level `status:` frontmatter field (empty string when absent)."""
    for line in read_frontmatter_lines(path):
        if line.startswith("status:"):
            return line.split(":", 1)[1].strip().strip('"').strip("'")
    return ""


def ac_verification_fields(path):
    """Read (status, human_disposition) from the ac_verification frontmatter block.

    Same block-walk shape as close-parent-spec-if-complete.sh
    ac_verification_status(); extended with human_disposition because the
    advance-eligibility input needs both fields.
    """
    status = ""
    disposition = ""
    in_block = False
    for line in read_frontmatter_lines(path):
        if line == "ac_verification:":
            in_block = True
            continue
        if in_block and line and not line.startswith((" ", "-")):
            break
        if in_block:
            match = re.match(r"\s+status:\s*(\S+)", line)
            if match and not status:
                status = match.group(1)
            match = re.match(r"\s+human_disposition:\s*(\S+)", line)
            if match and not disposition:
                disposition = match.group(1)
    return status, disposition


def v_entry_status_file(entry):
    """Map a V task entry (file or folder-native dir) to its status file."""
    return entry / "index.md" if entry.is_dir() else entry


def list_v_entries(directory):
    """List V task entries (legacy V1.md and folder-native V1/) in a directory."""
    if not directory.is_dir():
        return []
    entries = []
    for child in sorted(directory.iterdir()):
        if child.name == "pr-release":
            continue
        if child.is_file() and child.suffix == ".md" and V_STEM_RE.match(child.stem):
            entries.append(child)
        elif child.is_dir() and V_STEM_RE.match(child.name) and (child / "index.md").is_file():
            entries.append(child)
    return entries


def v_entry_stem(entry):
    return entry.name if entry.is_dir() else entry.stem


def frontmatter_field(path, field):
    """Read a top-level frontmatter field (empty string when absent)."""
    prefix = f"{field}:"
    for line in read_frontmatter_lines(path):
        if line.startswith(prefix):
            return line.split(":", 1)[1].strip().strip('"').strip("'")
    return ""


def t_entry_status_file(entry):
    """Map a T task entry (file or folder-native dir) to its status file."""
    return entry / "index.md" if entry.is_dir() else entry


def t_entry_stem(entry):
    return entry.name if entry.is_dir() else entry.stem


def list_t_entries(directory):
    """List T task entries (legacy T1.md and folder-native T1/) in a directory."""
    if not directory.is_dir():
        return []
    entries = []
    for child in sorted(directory.iterdir()):
        if child.name == "pr-release":
            continue
        if child.is_file() and child.suffix == ".md" and T_STEM_RE.match(child.stem):
            entries.append(child)
        elif child.is_dir() and T_STEM_RE.match(child.name) and (child / "index.md").is_file():
            entries.append(child)
    return entries


def deliverable_verification_status(path):
    """Return deliverable.verification.status from a task.md, or "".

    DP-360 T7: the head-sha completion_gate marker is retired; the delivery
    evidence is the task.md `deliverable` block. The T-assert advance-eligibility
    now binds to deliverable.verification.status == PASS read from the task.md
    itself (never a marker file, never a branch ref). Walks the nested frontmatter
    block (deliverable: → verification: → status:) without a YAML dependency,
    mirroring the ac_verification_fields() block-walk shape.
    """
    in_deliverable = False
    in_verification = False
    for line in read_frontmatter_lines(path):
        if line == "deliverable:":
            in_deliverable = True
            in_verification = False
            continue
        # Leaving the deliverable block: a non-indented, non-empty line.
        if in_deliverable and line and not line.startswith((" ", "-")):
            break
        if in_deliverable:
            if re.match(r"\s{2}verification:\s*$", line):
                in_verification = True
                continue
            # A new 2-space key ends the verification sub-block.
            if in_verification and re.match(r"\s{2}\S", line) and not line.startswith("    "):
                in_verification = False
            if in_verification:
                match = re.match(r"\s{4}status:\s*(\S+)", line)
                if match:
                    return match.group(1).strip().strip('"').strip("'")
    return ""


def frontmatter_depends_on(path):
    """Return top-level depends_on entries from task.md frontmatter."""
    lines = read_frontmatter_lines(path)
    deps = []
    for idx, line in enumerate(lines):
        if not line.startswith("depends_on:"):
            continue
        rest = line.split(":", 1)[1].strip()
        if rest.startswith("[") and rest.endswith("]"):
            raw = rest[1:-1].strip()
            if raw:
                deps.extend(part.strip().strip('"').strip("'") for part in raw.split(","))
            break
        if rest:
            deps.append(rest.strip().strip('"').strip("'"))
            break
        for child in lines[idx + 1:]:
            if child and not child.startswith((" ", "-")):
                break
            match = re.match(r"\s*-\s+(.+?)\s*$", child)
            if match:
                deps.append(match.group(1).strip().strip('"').strip("'"))
        break
    return [dep for dep in deps if dep]


def source_context(repo_path, scripts_dir):
    """Resolve source container, task dirs, and DP prefix for source_id."""
    resolver = scripts_dir / "spec-source-resolver.sh"
    if not resolver.is_file():
        return None, gate_blocked(f"source context: helper missing: {resolver}")
    specs_root = repo_path / "docs-manager" / "src" / "content" / "docs" / "specs"
    cmd = ["bash", str(resolver), "--source-id", source_id]
    if specs_root.is_dir():
        cmd.extend(["--specs-root", str(specs_root)])
    try:
        proc = subprocess.run(
            cmd, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=RESOLVER_TIMEOUT_SECONDS,
        )
    except Exception as exc:
        return None, gate_blocked(f"source context: resolver invocation failed: {exc}")
    if proc.returncode != 0:
        stderr_text = (proc.stderr or b"").decode("utf-8", errors="replace").strip()
        return None, gate_blocked(
            "source context: resolver failed: " + (stderr_text or f"exit {proc.returncode}")
        )
    try:
        resolved = json.loads(proc.stdout.decode("utf-8"))
    except Exception as exc:
        return None, gate_blocked(f"source context: resolver output not JSON: {exc}")
    container = Path(resolved.get("container") or "")
    if not container.is_dir():
        return None, gate_blocked("source context: resolved container missing", container)
    dp_match = re.match(r"^(DP-\d{3})(?:-|$)", container.name)
    dp_prefix = dp_match.group(1) if (dp_match and container.parent.name == "design-plans") else None
    return {
        "container": container,
        "tasks_dir": container / "tasks",
        "pr_release_dir": container / "tasks" / "pr-release",
        "dp_prefix": dp_prefix,
    }, None


def qualified_key(stem, dp_prefix):
    return f"{dp_prefix}-{stem}" if dp_prefix else stem


def dependency_satisfied(dep, completed, dp_prefix):
    candidates = {dep}
    if dp_prefix and not dep.startswith(f"{dp_prefix}-"):
        candidates.add(f"{dp_prefix}-{dep}")
    if dp_prefix and dep.startswith(f"{dp_prefix}-"):
        candidates.add(dep.removeprefix(f"{dp_prefix}-"))
    return any(candidate in completed for candidate in candidates)


def next_ready_work_item(repo_path, scripts_dir):
    """Return the next dependency-ready active T/V work item, or None.

    Runner owns source-level next-action selection. Probe remains scoped to the
    current work item's evidence; it deliberately does not inspect sibling task
    DAG state.
    """
    ctx, blocked = source_context(repo_path, scripts_dir)
    if blocked is not None:
        return None, blocked
    tasks_dir = ctx["tasks_dir"]
    pr_release_dir = ctx["pr_release_dir"]
    dp_prefix = ctx["dp_prefix"]

    completed = set()
    for entry in list_t_entries(pr_release_dir):
        status_file = t_entry_status_file(entry)
        if frontmatter_status(status_file) == "IMPLEMENTED":
            stem = t_entry_stem(entry)
            completed.add(stem)
            completed.add(qualified_key(stem, dp_prefix))
    for entry in list_v_entries(pr_release_dir):
        status_file = v_entry_status_file(entry)
        if frontmatter_status(status_file) == "IMPLEMENTED":
            stem = v_entry_stem(entry)
            completed.add(stem)
            completed.add(qualified_key(stem, dp_prefix))

    for entry in list_t_entries(tasks_dir):
        status_file = t_entry_status_file(entry)
        if frontmatter_status(status_file) == "ABANDONED":
            continue
        if frontmatter_field(status_file, "task_shape") in T_CARVE_OUT_SHAPES:
            continue
        if deliverable_verification_status(status_file) == "PASS":
            continue
        deps = frontmatter_depends_on(status_file)
        if all(dependency_satisfied(dep, completed, dp_prefix) for dep in deps):
            return qualified_key(t_entry_stem(entry), dp_prefix), None

    for entry in list_v_entries(tasks_dir):
        status_file = v_entry_status_file(entry)
        if frontmatter_status(status_file) == "ABANDONED":
            continue
        deps = frontmatter_depends_on(status_file)
        if all(dependency_satisfied(dep, completed, dp_prefix) for dep in deps):
            return qualified_key(v_entry_stem(entry), dp_prefix), None

    return None, None


def gate_blocked(reason, evidence_path=None):
    """Build the blocked_by_gate_failure replacement payload for the V gate."""
    return {
        "status": "BLOCKED",
        "terminal_status": "blocked_by_gate_failure",
        "next_action": "blocked",
        "next_skill": None,
        "next_work_item_id": None,
        "evidence_path": str(evidence_path) if evidence_path else None,
        "reason": reason,
    }


def terminal_complete_v_gate(repo_path, scripts_dir):
    """Run the Terminal Complete Sequence; return a blocked payload or None.

    None means the gate passed (or is vacuous: no source tasks/ directory or
    no V work items at all — the breakdown missing_v_task gate owns that case)
    and the caller may keep terminal_status=complete.
    """
    mark_spec = scripts_dir / "mark-spec-implemented.sh"
    for required in (mark_spec,):
        if not required.is_file():
            return gate_blocked(f"terminal complete gate: helper missing: {required}")
    ctx, blocked = source_context(repo_path, scripts_dir)
    if blocked is not None:
        return blocked
    container = ctx["container"]
    tasks_dir = ctx["tasks_dir"]
    pr_release_dir = ctx["pr_release_dir"]

    active_v = list_v_entries(tasks_dir)
    pr_release_v = list_v_entries(pr_release_dir)
    active_t = list_t_entries(tasks_dir)
    pr_release_t = list_t_entries(pr_release_dir)
    if not active_v and not pr_release_v and not active_t and not pr_release_t:
        # Vacuous: source has no V or T work items on disk. Missing V coverage
        # is the breakdown missing_v_task gate's responsibility, not this gate's.
        return None

    # DP container → fully-qualified DP-NNN-{stem} key (deterministic Path 3 in
    # mark-spec-implemented). JIRA Epic container → bare stem key (Path 2).
    dp_prefix = ctx["dp_prefix"]

    # (a) Advance eligible V work items through the canonical writer.
    for entry in active_v:
        status_file = v_entry_status_file(entry)
        if frontmatter_status(status_file) == "ABANDONED":
            continue
        ac_status, disposition = ac_verification_fields(status_file)
        if ac_status != "PASS" or disposition != "passed":
            continue
        stem = v_entry_stem(entry)
        key = f"{dp_prefix}-{stem}" if dp_prefix else stem
        try:
            proc = subprocess.run(
                ["bash", str(mark_spec), key, "--workspace", str(repo_path), "--no-auto-archive"],
                check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=MARK_SPEC_TIMEOUT_SECONDS,
            )
        except Exception as exc:
            return gate_blocked(
                f"terminal complete gate: mark-spec-implemented invocation failed for {key}: {exc}",
                status_file,
            )
        if proc.returncode != 0:
            stderr_text = (proc.stderr or b"").decode("utf-8", errors="replace").strip()
            return gate_blocked(
                f"terminal complete gate: mark-spec-implemented failed for {key}: "
                + (stderr_text or f"exit {proc.returncode}"),
                status_file,
            )

    # (b) Fail-closed confirmation: every required V must now sit at the
    # canonical terminal. The ac-verification marker alone never satisfies
    # this check (AC2).
    remaining = [
        entry for entry in list_v_entries(tasks_dir)
        if frontmatter_status(v_entry_status_file(entry)) != "ABANDONED"
    ]
    if remaining:
        names = ", ".join(v_entry_stem(entry) for entry in remaining)
        return gate_blocked(
            f"terminal complete blocked: required V work item(s) not at canonical terminal: {names}",
            v_entry_status_file(remaining[0]),
        )
    for entry in list_v_entries(pr_release_dir):
        status_file = v_entry_status_file(entry)
        if frontmatter_status(status_file) != "IMPLEMENTED":
            return gate_blocked(
                f"terminal complete blocked: pr-release V {v_entry_stem(entry)} status is not IMPLEMENTED",
                status_file,
            )
        ac_status, _ = ac_verification_fields(status_file)
        if ac_status != "PASS":
            return gate_blocked(
                f"terminal complete blocked: pr-release V {v_entry_stem(entry)} ac_verification is not PASS",
                status_file,
            )

    # ── DP-317 T1 (DP-360 T7 reader): symmetric required-implementation-T assert
    # (c) Advance every required implementation T work item whose task.md
    #     deliverable.verification.status is PASS but still sits under tasks/, then
    #     (d) fail-closed confirm every required implementation T reached the
    #     canonical terminal (pr-release/ + IMPLEMENTED), reusing the same
    #     mark-spec-implemented writer and the close-parent pr-release contract
    #     (AC2: no second classifier). audit / confirmation carve-out tasks take
    #     the DP-262 no-PR path (left in place, not advanced, not blocked,
    #     AC-NEG1); ABANDONED T tasks keep the close-parent carve-out (AC-NEG2).
    for entry in list_t_entries(tasks_dir):
        status_file = t_entry_status_file(entry)
        if frontmatter_status(status_file) == "ABANDONED":
            continue
        if frontmatter_field(status_file, "task_shape") in T_CARVE_OUT_SHAPES:
            continue
        stem = t_entry_stem(entry)
        key = f"{dp_prefix}-{stem}" if dp_prefix else stem
        if deliverable_verification_status(status_file) != "PASS":
            continue
        try:
            proc = subprocess.run(
                ["bash", str(mark_spec), key, "--workspace", str(repo_path), "--no-auto-archive"],
                check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=MARK_SPEC_TIMEOUT_SECONDS,
            )
        except Exception as exc:
            return gate_blocked(
                f"terminal complete gate: mark-spec-implemented invocation failed for {key}: {exc}",
                status_file,
            )
        if proc.returncode != 0:
            stderr_text = (proc.stderr or b"").decode("utf-8", errors="replace").strip()
            return gate_blocked(
                f"terminal complete gate: mark-spec-implemented failed for {key}: "
                + (stderr_text or f"exit {proc.returncode}"),
                status_file,
            )

    # Fail-closed confirmation: every required implementation T must now sit at
    # the canonical terminal. audit / confirmation carve-out and ABANDONED T are
    # excluded; a remaining required implementation T in tasks/ blocks complete
    # (EC2: missing / non-PASS completion_gate marker → never advanced → blocks).
    remaining_t = [
        entry for entry in list_t_entries(tasks_dir)
        if frontmatter_status(t_entry_status_file(entry)) != "ABANDONED"
        and frontmatter_field(t_entry_status_file(entry), "task_shape") not in T_CARVE_OUT_SHAPES
    ]
    if remaining_t:
        # EC2: missing / non-PASS deliverable.verification.status → never advanced
        # → blocks complete (task.md block is the sole evidence, no marker).
        names = ", ".join(t_entry_stem(entry) for entry in remaining_t)
        return gate_blocked(
            "terminal complete blocked: required implementation T work item(s) "
            f"not at canonical terminal: {names}",
            t_entry_status_file(remaining_t[0]),
        )
    for entry in list_t_entries(pr_release_dir):
        status_file = t_entry_status_file(entry)
        if frontmatter_status(status_file) != "IMPLEMENTED":
            return gate_blocked(
                f"terminal complete blocked: pr-release T {t_entry_stem(entry)} status is not IMPLEMENTED",
                status_file,
            )
    return None


# Stage → expected next skill on PASS (forward dispatch).
STAGE_NEXT_SKILL = {
    "source": "breakdown",
    "breakdown": "engineering",
    "engineering": "verify-AC",
    "verify-AC": None,
}


def map_next_action(probe_status, probe_terminal, probe_next, probe_evidence, probe_reason):
    """Translate probe machine fields to runner next_action / next_skill / terminal_status.

    Probe contract recap (auto-pass-probe.sh):
      - status: PASS | UNKNOWN | BLOCKED | ROUTE_BACK_AMEND | MANUAL_REQUIRED |
                BLOCKED_ENV | UNCERTAIN | FAIL | (any other JSON-derived value)
      - terminal_status: complete | blocked_by_gate_failure | loop_cap_reached |
                         paused_for_user_external_write | null
      - next_action (probe field name conflict): probe uses this to hint the
        next stage or action token. The runner re-interprets:
          * PASS + non-terminal → dispatch to next skill
          * ROUTE_BACK_AMEND → refinement_amendment (loop, non-terminal)
          * MANUAL_REQUIRED / paused → terminal pause
          * UNKNOWN / BLOCKED / FAIL / UNCERTAIN → terminal blocked
    """
    # ── Terminal cases ───────────────────────────────────────────────────────
    if probe_terminal == "complete":
        return {
            "status": probe_status or "PASS",
            "terminal_status": "complete",
            "next_action": "terminal",
            "next_skill": None,
            "next_work_item_id": None,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "stage complete",
        }
    if probe_terminal == "loop_cap_reached":
        return {
            "status": probe_status or "BLOCKED",
            "terminal_status": "loop_cap_reached",
            "next_action": "terminal",
            "next_skill": None,
            "next_work_item_id": None,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "planning loop cap reached",
        }
    if probe_terminal == "paused_for_user_external_write":
        return {
            "status": probe_status or "MANUAL_REQUIRED",
            "terminal_status": "paused_for_user_external_write",
            "next_action": "terminal",
            "next_skill": None,
            "next_work_item_id": None,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "manual external write required",
        }
    if probe_terminal == "blocked_by_gate_failure":
        # AC-NEG3: missing / UNKNOWN markers must remain blocked even if
        # inner-skill prose contains "PASS"; we trust ONLY the machine field.
        # DP-269 AC3: probe_reason carries the specific cause from a breakdown
        # validation_fail / missing_v_task durable marker (emitted by
        # breakdown-emit-blocker-marker.sh). Forward it verbatim so the
        # orchestrator reports a readable blocker, not "marker missing".
        return {
            "status": probe_status or "UNKNOWN",
            "terminal_status": "blocked_by_gate_failure",
            "next_action": "blocked",
            "next_skill": None,
            "next_work_item_id": None,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "blocked by gate failure",
        }

    # ── Non-terminal cases ───────────────────────────────────────────────────
    if probe_status == "ROUTE_BACK_AMEND" or probe_next == "refinement_amendment":
        return {
            "status": "ROUTE_BACK_AMEND",
            "terminal_status": None,
            "next_action": "refinement_amendment",
            "next_skill": "refinement",
            "next_work_item_id": source_id,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "refinement amendment loop",
        }
    # DP-313 T1: engineering-stage review-state route-backs. The probe consumed
    # an explicit review-state classification (after completion gate PASS) and
    # emitted a non-terminal route-back. Both routes dispatch the owning skill
    # (revision = engineering, planning gap = breakdown); terminal_status stays
    # null so the orchestrator loops rather than stopping. Keyed on the probe
    # STATUS token only — probe next_action ("engineering" / "breakdown") would
    # collide with forward-stage hints (e.g. source PASS emits next="breakdown").
    if probe_status == "ROUTE_BACK_REVISION":
        return {
            "status": "ROUTE_BACK_REVISION",
            "terminal_status": None,
            "next_action": "dispatch",
            "next_skill": "engineering",
            "next_work_item_id": work_item_id,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "actionable review signal (revision)",
        }
    if probe_status == "ROUTE_BACK_BREAKDOWN":
        return {
            "status": "ROUTE_BACK_BREAKDOWN",
            "terminal_status": None,
            "next_action": "dispatch",
            "next_skill": "breakdown",
            "next_work_item_id": work_item_id,
            "evidence_path": probe_evidence,
            "reason": probe_reason or "review planning gap (breakdown)",
        }
    if probe_status == "PASS":
        next_skill = STAGE_NEXT_SKILL.get(stage)
        next_work_item_id = work_item_id if stage != "source" else None
        if stage == "engineering":
            selected, blocked = next_ready_work_item(
                Path(repo).resolve(),
                Path(ledger_validator).parent,
            )
            if blocked is not None:
                return blocked
            if selected:
                next_work_item_id = selected
                next_skill = "verify-AC" if "-V" in selected else "engineering"
        # On verify-AC PASS without explicit "complete" terminal, treat as
        # complete (probe always pairs PASS+complete for verify-AC, but be
        # defensive).
        if stage == "verify-AC":
            return {
                "status": "PASS",
                "terminal_status": "complete",
                "next_action": "terminal",
                "next_skill": None,
                "next_work_item_id": None,
                "evidence_path": probe_evidence,
                "reason": probe_reason or "verify-AC complete",
            }
        if stage == "engineering":
            next_work_item, blocked = next_ready_work_item(
                Path(repo).resolve(), Path(ledger_validator).parent
            )
            if blocked is not None:
                return blocked
            if next_work_item:
                next_skill = "verify-AC" if re.search(r"-V\d+$", next_work_item) else "engineering"
                return {
                    "status": "PASS",
                    "terminal_status": None,
                    "next_action": "dispatch",
                    "next_skill": next_skill,
                    "next_work_item_id": next_work_item,
                    "evidence_path": probe_evidence,
                    "reason": probe_reason or f"{stage} PASS",
                }
            return {
                "status": "PASS",
                "terminal_status": "complete",
                "next_action": "terminal",
                "next_skill": None,
                "next_work_item_id": None,
                "evidence_path": probe_evidence,
                "reason": probe_reason or "engineering complete",
            }
        return {
            "status": "PASS",
            "terminal_status": None,
            "next_action": "dispatch",
            "next_skill": next_skill,
            # Forward to a placeholder work item id — orchestrator owns the
            # exact next id; runner reports the source id when it cannot infer
            # a sibling task id from current evidence.
            "next_work_item_id": next_work_item_id,
            "evidence_path": probe_evidence,
            "reason": probe_reason or f"{stage} PASS",
        }

    # Default: any unrecognized probe status escalates to blocked. We do not
    # invent PASS semantics, and we do not read any inner-skill prose.
    return {
        "status": probe_status or "UNKNOWN",
        "terminal_status": "blocked_by_gate_failure",
        "next_action": "blocked",
        "next_skill": None,
        "next_work_item_id": None,
        "evidence_path": probe_evidence,
        "reason": probe_reason or "probe status not recognized",
    }


# ── Fail-stop: if probe itself failed to emit JSON, this is a blocker. ──────
if probe_data is None:
    emit({
        "schema_version": 1,
        "source_id": source_id,
        "stage": stage,
        "status": "UNKNOWN",
        "terminal_status": "blocked_by_gate_failure",
        "next_action": "blocked",
        "next_skill": None,
        "next_work_item_id": None,
        "evidence_path": None,
        "reason": probe_error or "probe failure",
    })

probe_status = probe_data.get("status")
probe_terminal = probe_data.get("terminal_status")
probe_next = probe_data.get("next_action")
probe_evidence = probe_data.get("evidence_path")
probe_reason = probe_data.get("reason")

# ── Ledger-level resume detection ────────────────────────────────────────────
# DP-237 AC-NEG4 / contract: when a ledger is provided and has
# pause.kind=session_handoff with required resume_artifact / next_work_item_id,
# the runner emits next_action=resume (non-terminal — the sidecar is expected
# to continue). This is a runner-layer signal, not a probe-layer one.
ledger_resume = None
if ledger_arg:
    ledger_path = Path(ledger_arg)
    if ledger_path.is_absolute() and ledger_path.is_file():
        try:
            ledger_payload = json.loads(ledger_path.read_text(encoding="utf-8"))
        except Exception:
            ledger_payload = None
        if isinstance(ledger_payload, dict):
            pause = ledger_payload.get("pause")
            if isinstance(pause, dict) and pause.get("kind") == "session_handoff":
                resume_artifact = pause.get("resume_artifact")
                next_id = pause.get("next_work_item_id")
                # Only surface as resume when both required fields are present;
                # otherwise leave pause handling to probe / ledger validator.
                if resume_artifact and next_id:
                    ledger_resume = {
                        "resume_artifact": resume_artifact,
                        "next_work_item_id": next_id,
                    }

if ledger_resume is not None:
    emit({
        "schema_version": 1,
        "source_id": source_id,
        "stage": stage,
        "status": "PASS",
        "terminal_status": None,
        "next_action": "resume",
        "next_skill": STAGE_NEXT_SKILL.get(stage),
        "next_work_item_id": ledger_resume["next_work_item_id"],
        "evidence_path": ledger_resume["resume_artifact"],
        "reason": "session_handoff resume",
    })

mapped = map_next_action(probe_status, probe_terminal, probe_next, probe_evidence, probe_reason)

# DP-311 T1: every path that would emit terminal_status=complete (fresh
# verify-AC PASS and the resume-complete rerun) funnels through map_next_action,
# so the Terminal Complete Sequence gate hooks here exactly once.
if mapped.get("terminal_status") == "complete":
    # ledger_validator lives in the same scripts/ directory as this runner,
    # spec-source-resolver.sh and mark-spec-implemented.sh.
    gate_result = terminal_complete_v_gate(Path(repo).resolve(), Path(ledger_validator).parent)
    if gate_result is not None:
        mapped = gate_result

payload = {
    "schema_version": 1,
    "source_id": source_id,
    "stage": stage,
}
payload.update(mapped)
print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
PY
