#!/usr/bin/env bash
# Purpose: deterministic task.md body derivation from refinement.json (DP-230-T10).
#
# Replaces the previous breakdown LLM-judgment task derivation. Given a
# refinement.json `tasks[]` entry, emit a canonical task.md body that passes
# `validate-task-md.sh` and `validate-breakdown-ready.sh` — without any LLM
# reasoning step in the pipeline.
#
# Inputs come exclusively from structured fields on the refinement.json task:
#   id, title, scope, allowed_files, ac_ids, dependencies, estimate_points,
#   verification.detail
#
# DP-269: derive dispatches on source.type.
#   - dp   mode (default): legacy behavior unchanged — JIRA key N/A,
#            Repo polaris-framework (or --repo), Base branch main,
#            task identity = canonical DP-NNN-Tn.
#   - jira mode: task identity = real per-task `tasks[].jira_key`, Repo =
#            `source.repo`, Base branch = `source.base_branch`, JIRA key cell =
#            the real key. Fail-closes when `tasks[].jira_key` is null (no N/A
#            fallback) and when source.repo / source.base_branch are missing.
#
# fail-loud cases (no fallback):
#   - refinement.json file missing or invalid JSON
#   - task-id not found in `tasks[]`
#   - required field missing on the resolved task entry
#
# DP-360 T6 (D1/D2): when delivery inputs are supplied, derive additionally
# emits a task.md delivery/verification block. The block carries
# `deliverable.head_sha` (D1: the persisted artifact field that absorbs the
# delivered-head role, contract source #3 — not a mutable branch ref) plus a
# nested `deliverable.verification` sub-block (D2: PASS / FAIL status + ac_counts
# relocated from the head-sha-keyed completion_gate / ac_verification markers).
# This task only adds the derive writer's ability to emit the block; retiring the
# marker writers and switching consumers to read it is T7. The block is purely
# additive — with no delivery inputs the body is byte-for-byte the legacy output.
#
# Usage:
#   bash scripts/derive-task-md-from-refinement-json.sh \
#     --refinement-json <path> \
#     --task-id <DP-NNN-Tn> \
#     [--repo polaris-framework] \
#     [--deliverable-head-sha SHA --deliverable-pr-url URL --deliverable-pr-state STATE \
#      --verification-status STATUS \
#      --ac-total N --ac-pass N --ac-fail N --ac-manual-required N --ac-uncertain N]
#
# Output: task.md body on stdout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REFINEMENT_JSON=""
TASK_ID=""
REPO_NAME="polaris-framework"
# DP-344 D1: optional override for the changeset-detection repo root. When unset,
# derive auto-detects the resolved repo root (workspace root for DP-backed, or
# <workspace>/<source.repo> for a JIRA-Epic product repo). Selftests pass an
# explicit fixture root so the .changeset/config.json probe is hermetic.
REPO_ROOT_OVERRIDE=""

# DP-360 T6 delivery/verification block inputs (all optional; the block is only
# emitted when --deliverable-head-sha is supplied). Empty string = "not supplied".
DELIVERABLE_HEAD_SHA=""
DELIVERABLE_PR_URL=""
DELIVERABLE_PR_STATE=""
VERIFICATION_STATUS=""
AC_TOTAL=""
AC_PASS=""
AC_FAIL=""
AC_MANUAL_REQUIRED=""
AC_UNCERTAIN=""

usage() {
  cat >&2 <<'USAGE'
usage:
  derive-task-md-from-refinement-json.sh --refinement-json <path> --task-id <DP-NNN-Tn> [--repo <name>] [--repo-root <path>]
    [--deliverable-head-sha <sha> --deliverable-pr-url <url> --deliverable-pr-state <OPEN|MERGED|CLOSED>
     --verification-status <PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS>
     --ac-total <n> --ac-pass <n> --ac-fail <n> --ac-manual-required <n> --ac-uncertain <n>]

Emits a canonical task.md body on stdout, derived deterministically from the
structured `tasks[]` entry in the supplied refinement.json. No LLM judgment.

When --deliverable-head-sha is supplied, a delivery/verification block is appended
to the (T-task only) frontmatter: deliverable.head_sha (D1) plus a nested
deliverable.verification sub-block (D2 — status + ac_counts). The block is purely
additive; omit the delivery flags to derive the legacy body unchanged.

--repo-root overrides the changeset-detection repo root (DP-344 D1); when the
resolved repo root contains .changeset/config.json, derive injects the
deterministic .changeset/{slug}.md into ## Allowed Files.
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --refinement-json) REFINEMENT_JSON="${2:-}"; shift 2 ;;
    --task-id) TASK_ID="${2:-}"; shift 2 ;;
    --repo) REPO_NAME="${2:-}"; shift 2 ;;
    --repo-root) REPO_ROOT_OVERRIDE="${2:-}"; shift 2 ;;
    --deliverable-head-sha) DELIVERABLE_HEAD_SHA="${2:-}"; shift 2 ;;
    --deliverable-pr-url) DELIVERABLE_PR_URL="${2:-}"; shift 2 ;;
    --deliverable-pr-state) DELIVERABLE_PR_STATE="${2:-}"; shift 2 ;;
    --verification-status) VERIFICATION_STATUS="${2:-}"; shift 2 ;;
    --ac-total) AC_TOTAL="${2:-}"; shift 2 ;;
    --ac-pass) AC_PASS="${2:-}"; shift 2 ;;
    --ac-fail) AC_FAIL="${2:-}"; shift 2 ;;
    --ac-manual-required) AC_MANUAL_REQUIRED="${2:-}"; shift 2 ;;
    --ac-uncertain) AC_UNCERTAIN="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REFINEMENT_JSON" && -n "$TASK_ID" ]] || usage

if [[ ! -f "$REFINEMENT_JSON" ]]; then
  echo "ERROR: refinement.json not found: $REFINEMENT_JSON" >&2
  exit 2
fi

python3 - "$REFINEMENT_JSON" "$TASK_ID" "$REPO_NAME" "$SCRIPT_DIR" "$REPO_ROOT_OVERRIDE" \
  "$DELIVERABLE_HEAD_SHA" "$DELIVERABLE_PR_URL" "$DELIVERABLE_PR_STATE" \
  "$VERIFICATION_STATUS" \
  "$AC_TOTAL" "$AC_PASS" "$AC_FAIL" "$AC_MANUAL_REQUIRED" "$AC_UNCERTAIN" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

refinement_path, task_id, repo_name, script_dir, repo_root_override = sys.argv[1:6]
(
    deliverable_head_sha,
    deliverable_pr_url,
    deliverable_pr_state,
    verification_status,
    ac_total_arg,
    ac_pass_arg,
    ac_fail_arg,
    ac_manual_required_arg,
    ac_uncertain_arg,
) = sys.argv[6:15]


def fail(msg, code=2):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


# DP-360 T6 (D1/D2): build the optional task.md delivery/verification block.
#
# The block extends the canonical T-mode `deliverable:` frontmatter
# (deliverable.pr_url / pr_state / head_sha — validate-task-md.sh § 2.1 + DP-033
# D7) with a nested `verification:` sub-block that relocates the PASS / ac_counts
# payload from the head-sha-keyed completion_gate / ac_verification markers (D2).
# It is emitted ONLY when a delivered head_sha is supplied; otherwise derive
# returns "" and the body is the legacy (no-block) output (AC-NEG back-compat).
#
# This task adds the writer capability only — switching consumers to read the
# block and retiring the marker writers is T7.
VERIFICATION_STATUSES = (
    "PASS",
    "FAIL",
    "MANUAL_REQUIRED",
    "UNCERTAIN",
    "BLOCKED_ENV",
    "IN_PROGRESS",
)
PR_STATES = ("OPEN", "MERGED", "CLOSED")
AC_COUNT_FIELDS = ("ac_total", "ac_pass", "ac_fail", "ac_manual_required", "ac_uncertain")


def build_delivery_block(task_id: str) -> str:
    """Build the task.md delivery/verification frontmatter block, or "" when absent.

    Args:
        task_id: canonical task id, used for fail-loud error messages.

    Returns:
        The rendered `deliverable:` block (indented YAML, no trailing newline),
        or an empty string when no delivered head_sha was supplied — in which
        case the caller emits the legacy block-free body.

    Fail-louds (exit 2) when the supplied delivery inputs are malformed (bad SHA,
    bad PR url/state, unknown verification status, non-integer ac_counts, or
    ac_pass+ac_fail+ac_manual_required+ac_uncertain != ac_total) — no silent
    framework default, mirroring the AC-NEG1 fail-loud discipline elsewhere.
    """
    head_sha = deliverable_head_sha.strip()
    if not head_sha:
        # No delivery inputs → no block. Reject partial input loudly so a typo'd
        # flag set can never silently drop the delivery payload.
        partial = [
            label
            for label, value in (
                ("--deliverable-pr-url", deliverable_pr_url),
                ("--deliverable-pr-state", deliverable_pr_state),
                ("--verification-status", verification_status),
                ("--ac-total", ac_total_arg),
                ("--ac-pass", ac_pass_arg),
                ("--ac-fail", ac_fail_arg),
                ("--ac-manual-required", ac_manual_required_arg),
                ("--ac-uncertain", ac_uncertain_arg),
            )
            if value.strip()
        ]
        if partial:
            fail(
                f"task {task_id} delivery block inputs supplied ({', '.join(partial)}) "
                "without --deliverable-head-sha; supply the delivered head or none"
            )
        return ""

    if not re.fullmatch(r"[0-9a-fA-F]{7,40}", head_sha):
        fail(
            f"task {task_id} --deliverable-head-sha must be a 7-40 char hex SHA "
            f"(got: '{head_sha}')"
        )

    pr_url = deliverable_pr_url.strip()
    if not pr_url:
        fail(f"task {task_id} --deliverable-pr-url is required when a delivery block is emitted")
    if not re.fullmatch(r"https://github\.com/.+/pull/[0-9]+", pr_url):
        fail(
            f"task {task_id} --deliverable-pr-url must match "
            f"'https://github.com/.+/pull/[0-9]+' (got: '{pr_url}')"
        )

    pr_state = deliverable_pr_state.strip()
    if pr_state not in PR_STATES:
        fail(
            f"task {task_id} --deliverable-pr-state must be one of "
            f"{', '.join(PR_STATES)} (got: '{pr_state or '<empty>'}')"
        )

    status = verification_status.strip()
    if status not in VERIFICATION_STATUSES:
        fail(
            f"task {task_id} --verification-status must be one of "
            f"{', '.join(VERIFICATION_STATUSES)} (got: '{status or '<empty>'}')"
        )

    raw_counts = {
        "ac_total": ac_total_arg,
        "ac_pass": ac_pass_arg,
        "ac_fail": ac_fail_arg,
        "ac_manual_required": ac_manual_required_arg,
        "ac_uncertain": ac_uncertain_arg,
    }
    counts = {}
    for field in AC_COUNT_FIELDS:
        raw = raw_counts[field].strip()
        if not raw:
            fail(
                f"task {task_id} {field.replace('_', '-', 1)} is required when a "
                "delivery block is emitted"
            )
        if not re.fullmatch(r"[0-9]+", raw):
            fail(f"task {task_id} --{field.replace('_', '-')} must be a non-negative integer (got: '{raw}')")
        counts[field] = int(raw)
    counted = counts["ac_pass"] + counts["ac_fail"] + counts["ac_manual_required"] + counts["ac_uncertain"]
    if counted != counts["ac_total"]:
        fail(
            f"task {task_id} ac_counts inconsistent: ac_pass + ac_fail + "
            f"ac_manual_required + ac_uncertain ({counted}) must equal ac_total "
            f"({counts['ac_total']})"
        )

    lines = [
        "deliverable:",
        f"  pr_url: {pr_url}",
        f"  pr_state: {pr_state}",
        f"  head_sha: {head_sha}",
        "  verification:",
        f"    status: {status}",
        "    ac_counts:",
    ]
    for field in AC_COUNT_FIELDS:
        lines.append(f"      {field}: {counts[field]}")
    return "\n".join(lines)


# DP-316: canonical projection from the refinement.json `test_environment.level`
# enum (wider — includes component / integration) onto the task.md Level enum
# (narrower — only static / build / runtime, the values validate-task-md.sh
# accepts). The two enums are intentionally NOT reconciled at the validator
# layer (AC-NEG2); the derive bridge is the single place that translates between
# them. This table is the sole source of the mapping — DP-316-T2's lock-preflight
# placeholder reuses project_test_environment_level() rather than copying a second
# table (AC4 single-source / parity).
#
#   static      -> static  (identity)
#   component   -> build    (many-to-one: component-level work runs at build time)
#   integration -> build    (many-to-one: integration without a live URL is build,
#                            not runtime — avoids wrongly imposing runtime
#                            live-URL cross-field on a non-runtime task)
#   runtime     -> runtime  (identity)
#
# Any value outside this table (unknown / typo) fail-louds (AC-NEG1): no silent
# fallback to static, which would hide a typo behind a weaker verification level.
LEVEL_PROJECTION = {
    "static": "static",
    "component": "build",
    "integration": "build",
    "runtime": "runtime",
}


def project_test_environment_level(raw_level: str, task_id: str) -> str:
    """Project a refinement.json test_environment.level onto the task.md Level enum.

    Args:
        raw_level: the refinement.json `test_environment.level` value (already
            stripped non-empty by the caller).
        task_id: canonical task id, used for the fail-loud error message.

    Returns:
        The projected task.md Level (one of static / build / runtime).

    Fail-louds (exit 2) when raw_level is not in LEVEL_PROJECTION — an unknown or
    mistyped level must never silently fall back to static (DP-316 AC-NEG1).
    """
    projected = LEVEL_PROJECTION.get(raw_level)
    if projected is None:
        valid = ", ".join(sorted(LEVEL_PROJECTION))
        fail(
            f"task {task_id} test_environment.level '{raw_level}' is not a "
            f"projectable level (expected one of: {valid}); refusing to "
            "silently fall back to static"
        )
    return projected


try:
    data = json.loads(Path(refinement_path).read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    fail(f"refinement.json is not valid JSON: {exc}")

source = data.get("source") or {}
source_id = source.get("id")
source_type = source.get("type") or "dp"
source_container = source.get("container")
if not source_id:
    fail("refinement.json missing source.id")

# DP-302: derive output is source.type-free. Every value that used to dispatch on
# `source.type == "jira"` is now field-driven, so feeding the SAME refinement.json
# content (only source.repo / source.base_branch / tasks[].jira_key differing)
# produces a task.md whose structure is identical and whose values track the
# fields (AC1 / AC2). The derivation reads source.type for nothing that affects
# output; it is retained only as a rendered Operational Context cell value.
#
#   Repo        : source.repo when present, else the CLI --repo default
#                 (polaris-framework). No type branch.
#   Base branch : source.base_branch when present, else "main" (root tasks).
#                 No type branch.
# A jira source naturally carries source.repo / source.base_branch; a dp source
# omits them and falls back to the framework defaults — same code path, no
# `if source_type == ...`.
source_repo = source.get("repo")
if isinstance(source_repo, str) and source_repo.strip():
    repo_name = source_repo.strip()
# else: repo_name keeps the CLI --repo default (polaris-framework).

source_base_branch = source.get("base_branch")
root_base_branch = (
    source_base_branch.strip()
    if isinstance(source_base_branch, str) and source_base_branch.strip()
    else "main"
)

tasks = data.get("tasks") or []
# DP-260 T1: tasks[].id accepts both short form (T1/V1, optionally with a-suffix)
# and full form (DP-NNN-Tn / EPIC-NNN-Vn) — derive must accept either when the
# CLI canonical id is full form. Match full id first; fall back to short id
# when the canonical id's source prefix equals source.id. Reject foreign
# prefix at the validator layer, not here.
m_cli = re.match(r"^(?P<src>[A-Z][A-Z0-9]*-\d+)-(?P<short>[TV]\d+[a-z]?)$", task_id)
if not m_cli:
    fail(f"task id does not match canonical pattern (e.g. DP-230-T10): {task_id}")
cli_short_id = m_cli.group("short")
cli_source_id = m_cli.group("src")

match = None
# Pass 1: full-form match (entry.id == task_id).
for entry in tasks:
    if entry.get("id") == task_id:
        match = entry
        break
# Pass 2: short-form fallback (entry.id == short tail) only when the CLI source
# prefix equals refinement.json source.id.
if match is None and cli_source_id == source_id:
    for entry in tasks:
        if entry.get("id") == cli_short_id:
            match = entry
            break
if match is None:
    fail(f"task-id not found in refinement.json tasks[]: {task_id}")

required_fields = ("id", "title", "scope", "allowed_files", "verification", "estimate_points")
for field in required_fields:
    if field not in match or match[field] in (None, "", []):
        fail(f"task {task_id} missing required field: {field}")

verification = match["verification"] or {}
verify_detail = verification.get("detail") or ""
if not verify_detail.strip():
    fail(f"task {task_id} missing verification.detail")
# verify_command is the executable shell command form (preferred when set);
# verification.detail remains zh-TW prose used for Scope Trace / Test Plan / Gate
# rendering.
#
# DP-311 T6 (AC8 / AC-NEG7): the unconditional prose fallback is removed. The
# effective fence command still prefers verify_command and may use detail only
# when verify_command is null (legacy refinement.json shape predating the
# field), but BEFORE any task.md body is emitted the effective command must
# pass the SHARED executability helper
# (scripts/lib/check-verify-command-executability.sh: bash -n parse +
# outside-quote CJK detection — the same judgment validate-breakdown-ready.sh
# runs at readiness time, D9 no second copy). A prose detail (DP-252-T1 family)
# therefore fail-closes with exit 2 + POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE and
# derive produces no output; an executable detail / quoted-CJK pattern keeps
# passing (AC-NEG7 zero false-block).
verify_command = (verification.get("verify_command") or "").strip()
effective_verify_command = verify_command or verify_detail.strip()


def check_verify_command_executability(label: str, command_text: str) -> None:
    """Fail-close derive when the effective verify/test command is not executable bash.

    Args:
        label: context written into the structured marker (the canonical task id).
        command_text: the effective command destined for the Verify Command /
            Test Command fenced blocks.

    Delegates the verdict to the shared helper; on violation, relays the
    helper's stderr (reasons + POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE marker)
    and exits 2 without emitting any task.md body.
    """
    helper = Path(script_dir) / "lib" / "check-verify-command-executability.sh"
    if not helper.is_file():
        fail(f"missing shared executability helper: {helper}")
    proc = subprocess.run(
        ["bash", str(helper), "--label", label],
        input=command_text,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        sys.exit(2)

title = str(match["title"]).strip()
scope = str(match["scope"]).strip()
points = int(match["estimate_points"])
allowed_files = list(match["allowed_files"])
ac_ids = list(match.get("ac_ids") or [])
raw_dependencies = [str(dep).strip() for dep in list(match.get("dependencies") or []) if str(dep).strip()]

# Tn suffix: reuse the canonical CLI parse above (m_cli) for short id / mode.
short_id = cli_short_id
mode = short_id[0]

# DP-302 (AC3): references are generated from the resolved source.container, so a
# jira container yields `specs/companies/...` and a dp container yields
# `specs/design-plans/...` without any source.type branch or hardcoded literal.
# The container is an absolute path under docs-manager/src/content/docs/; we
# relativize against that marker. Test fixtures with a bare path (e.g. /tmp/dp-x)
# fall back to the container basename so the field stays deterministic. Computed
# here (before the V-task branch) so both T and V tasks share the same path
# derivation.
def container_reference_dir(container: str) -> str:
    if not container:
        return source_id
    marker = "src/content/docs/"
    idx = container.find(marker)
    if idx != -1:
        rel = container[idx + len(marker):].strip("/")
        return f"docs-manager/{marker}{rel}"
    return Path(container).name


ref_dir = container_reference_dir(str(source_container or ""))
container_references = [
    f"{ref_dir}/refinement.md",
    f"{ref_dir}/refinement.json",
]

# DP-302: identity + JIRA key cell are field-driven, not source.type-driven.
# The single code path keys off the per-task `tasks[].jira_key` field:
#   jira_key present : identity = the real per-task jira_key; JIRA key cell = it.
#   jira_key absent  : identity = canonical task_id (DP-NNN-Tn); cell = "N/A".
# The plain JIRA key (^[A-Z][A-Z0-9]*-[0-9]+$) and the DP pseudo identity both
# satisfy validate-task-md.sh is_valid_task_identity, so either path validates.
# A malformed jira_key is rejected here (loud), but a missing one is NOT a
# fail — it simply renders N/A. There is no `if source_type == ...` branch.
task_jira_key = match.get("jira_key")
if isinstance(task_jira_key, str) and task_jira_key.strip():
    task_jira_key = task_jira_key.strip()
    if not re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+", task_jira_key):
        fail(
            f"task {task_id} jira_key is not a valid JIRA key (got: '{task_jira_key}')"
        )
    task_identity = task_jira_key
    jira_key_cell = task_jira_key
else:
    task_identity = task_id
    jira_key_cell = "N/A"

# DP-338 D1: de-conflate the work_item_id atom from the branch-identity atom.
# `task_identity` (above) is the BRANCH identity — it equals the per-task jira_key
# for JIRA-Epic sources, so for those sources it must NOT also be the work_item_id
# (the internal task marker). The canonical work_item_id is always {source}-T{n}
# (= the canonical CLI task_id), regardless of source.type; for DP-backed sources
# the two atoms collapse to the same value. derive writes BOTH cells: the new
# "Work item ID" cell carries this canonical work_item_id, while the legacy
# "Task ID" cell keeps carrying task_identity so DP-328 branch identity is
# unchanged. parse-task-md.sh reads work_item_id from the new cell first.
work_item_id_cell = task_id


# DP-344 D1: changeset Allowed-Files injection. When the resolved repo root has a
# .changeset/config.json (the repo participates in Changesets), inject the
# deterministic .changeset/{slug}.md into the task's ## Allowed Files. The slug is
# computed by REUSING polaris-changeset.sh's `slug` subcommand (DP-344 D3 single
# slug source — no second kebab implementation here), so the injected path is
# byte-identical with the slug polaris-changeset writes (ASCII-only; CJK dropped).
def resolve_changeset_repo_root() -> str:
    """Resolve the repo root used to probe for .changeset/config.json.

    Detection is relative to the RESOLVED repo root, never the workspace root, so a
    product repo that does not use Changesets is not falsely injected with the
    framework workspace's .changeset (DP-344 AC-NEG1).

    Returns:
        The absolute repo-root path string, or "" when it cannot be resolved.

    Resolution order:
      1. --repo-root override (selftests pass a hermetic fixture root).
      2. <workspace>/<source.repo> when that directory exists (JIRA-Epic product
         repo). workspace = dirname(script_dir) (script_dir is <workspace>/scripts).
      3. <workspace> itself (DP-backed framework source: the framework workspace IS
         the repo root, where .changeset/config.json lives).
    """
    if repo_root_override.strip():
        return repo_root_override.strip()
    workspace_root = Path(script_dir).parent
    repo_field = (source.get("repo") or "").strip() if isinstance(source.get("repo"), str) else ""
    if repo_field:
        candidate = workspace_root / repo_field
        if candidate.is_dir():
            return str(candidate)
    return str(workspace_root)


def changeset_allowed_file_path() -> str:
    """Return the deterministic .changeset/{slug}.md to inject, or "" to skip.

    Returns "" (no injection) when the resolved repo root has no
    .changeset/config.json (non-changeset repo, AC-NEG1). Otherwise delegates the
    slug derivation to polaris-changeset.sh `slug` (single slug source, AC1/AC4),
    using task_identity as the ticket and the task title.
    """
    repo_root = resolve_changeset_repo_root()
    if not repo_root:
        return ""
    if not (Path(repo_root) / ".changeset" / "config.json").is_file():
        return ""
    changeset_helper = Path(script_dir) / "polaris-changeset.sh"
    if not changeset_helper.is_file():
        fail(f"missing slug source helper: {changeset_helper}")
    proc = subprocess.run(
        [
            "bash",
            str(changeset_helper),
            "slug",
            "--ticket",
            task_identity,
            "--title",
            title,
            "--print",
            "path",
        ],
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        fail(f"task {task_id} changeset slug derivation failed")
    return proc.stdout.strip()


# Inject for implementation (T) tasks only — a changeset is a PR deliverable; V
# (verification) tasks produce no PR/changeset. Idempotent: never append a path
# already present in allowed_files (AC-NEG2 re-derive idempotency).
if mode == "T":
    _changeset_path = changeset_allowed_file_path()
    if _changeset_path and _changeset_path not in allowed_files:
        allowed_files.append(_changeset_path)


# Branch slug: deterministic, lowercase, hyphen-separated, ASCII-only (DP-307
# D1/D2). Byte-identical with the canonical bash slugify in
# engineering-branch-setup.sh / resolve-task-branch.sh:
#   tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' \
#     | sed 's/^-//;s/-$//' | cut -c1-40
# Every non-[a-z0-9] character (CJK included) collapses into hyphens and gets
# trimmed; an all-CJK title slugifies to "" and the call sites below fall back
# to the literal "task" so the derived branch stays non-empty pure ASCII
# (AC-NEG4). Parity is enforced by
# scripts/selftests/branch-slug-producer-parity-selftest.sh.
def slugify(text: str) -> str:
    """Slugify a task title into the canonical ASCII-only branch slug.

    Args:
        text: raw task title (may contain CJK / punctuation / uppercase).

    Returns:
        Lowercase hyphen-separated slug, max 40 chars, possibly empty for
        input with no [a-z0-9] characters (callers apply the "task" fallback).
    """
    # ASCII-only lowercase mirrors `tr '[:upper:]' '[:lower:]'`; non-ASCII
    # letters fall through to the [^a-z0-9] -> "-" replacement below.
    lowered = "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in text)
    slug = re.sub(r"[^a-z0-9]", "-", lowered)
    slug = re.sub(r"-+", "-", slug)
    slug = slug.strip("-")
    slug_max_chars = 40  # parity with the bash producers' `cut -c1-40`
    return slug[:slug_max_chars]


# Empty-slug fallback: keeps the branch identity non-empty when the title has
# no [a-z0-9] characters at all (e.g. a pure zh-TW title).
slug = slugify(title) or "task"
# Branch identity uses task_identity (= tasks[].jira_key for JIRA-Epic-backed
# sources, else the canonical task_id), NOT the composite task_id. Leaking the
# internal composite work_item_id (e.g. EPIC-1234-T1) into the product branch
# violates the resolve-task-branch.sh AC-NEG5 invariant; task_identity collapses
# to task_id for DP-backed sources, so DP branches stay task/DP-NNN-Tn-...
# (DP-328 D1/D4; completes the DP-269 task_identity follow-through).
task_branch = f"task/{task_identity}-{slug}"

def short_work_item_id(value: str) -> str:
    m_short = re.fullmatch(r"[TV]\d+[a-z]?", value)
    if m_short:
        return value
    m_full = re.fullmatch(r"(?P<src>[A-Z][A-Z0-9]*-\d+)-(?P<short>[TV]\d+[a-z]?)", value)
    if m_full and m_full.group("src") == source_id:
        return m_full.group("short")
    return ""


def full_work_item_id(value: str) -> str:
    short = short_work_item_id(value)
    return f"{source_id}-{short}" if short else value


# Index tasks by normalized full id so dependency title lookup hits regardless of
# whether tasks[].id is short form (T1) or full form (DP-NNN-Tn). Keying by the raw
# entry.id would miss short-form entries when looked up by full id below, and the
# missing-entry path silently falls back to the full-id literal as the slug source.
task_by_id = {
    full_work_item_id(str(entry.get("id"))): entry
    for entry in tasks
    if isinstance(entry, dict)
}

local_dependencies = []
external_dependencies = []
for dep in raw_dependencies:
    short_dep = short_work_item_id(dep)
    if short_dep:
        local_dependencies.append(short_dep)
    else:
        # Cross-source full-form work items are allowed as source references, but
        # this DP-backed task writer cannot derive a local task branch from them.
        # Bare source ids such as DP-229 are invalid under the refinement schema
        # and should be caught before derive; keep this defensive split loud in
        # task DAG output by excluding them from task.md Depends on.
        external_dependencies.append(dep)

if mode == "T" and len(local_dependencies) > 1:
    fail(f"task {task_id} has non-linear local dependencies: {', '.join(local_dependencies)}")

full_form_dependencies = [f"{source_id}-{dep}" for dep in local_dependencies]
depends_on_frontmatter = ", ".join(full_form_dependencies)
depends_cell = ", ".join(full_form_dependencies) if full_form_dependencies else "N/A"
if local_dependencies:
    dep_full_id = f"{source_id}-{local_dependencies[-1]}"
    dep_title = str((task_by_id.get(dep_full_id) or {}).get("title") or dep_full_id)
    base_branch = f"task/{dep_full_id}-{slugify(dep_title) or 'task'}"
    branch_chain = f"{base_branch} -> {task_branch}"
else:
    # DP-302: root base branch is field-driven (source.base_branch or "main"),
    # resolved once above as root_base_branch — no source.type dispatch.
    base_branch = root_base_branch
    branch_chain = f"{root_base_branch} -> {task_branch}"

# --- Build artifacts ---
allowed_files_block = "\n".join(f"- `{p}`" for p in allowed_files)


# Default Action when the refinement's modules[] (codebase analysis of EXISTING
# modules being touched) records no entry for a path. An allowed file absent from
# that analysis is a net-new file the task creates, so "create" is the field-driven
# default — derived from the path's PRESENCE/ABSENCE in the authoritative modules
# array, NOT from any filename/path-shape heuristic (DP-325 T4 / AC5). Whenever a
# module entry exists, its recorded action wins outright.
DEFAULT_MODULE_ACTION = "create"


def module_action_for(path):
    """Resolve the change-table Action for an allowed file from the refinement.

    Reads the authoritative per-path `action` field from top-level
    `modules[]` (the canonical create/modify decision the refinement records),
    rather than inferring it from path/filename heuristics (DP-325 T4 / AC5).
    The Action a task.md presents follows the recorded field, so a
    create-vs-modify decision can never drift from path shape.

    Args:
        path: an allowed-file path string from the task's allowed_files.

    Returns:
        The action string recorded in modules[].action for that path; when the
        path is absent from the authoritative modules[] analysis (a net-new
        allowed file), the deterministic DEFAULT_MODULE_ACTION ("create") —
        never a path/filename heuristic.
    """
    return module_action_by_path.get(path, DEFAULT_MODULE_ACTION)


# Authoritative create/modify decision per path comes from refinement.json
# top-level modules[] (each entry carries {path, action, ...}); the T-task change
# table reads this field instead of guessing from the path shape (DP-325 T4 / AC5).
module_action_by_path = {
    str(mod["path"]): str(mod["action"])
    for mod in (data.get("modules") or [])
    if isinstance(mod, dict) and mod.get("path") and mod.get("action")
}

# Scope Trace Matrix — one row per AC id, owning files = allowed_files joined
# Use the first allowed file as canonical owning file for simplicity; surface
# stays "framework deterministic gate / selftest contract" for DP-backed work.
owning_anchor = f"`{allowed_files[0]}`"
trace_rows = []
ac_list = ac_ids if ac_ids else ["AC-N/A"]
for ac in ac_list:
    trace_rows.append(f"| {ac} | {owning_anchor} | framework deterministic gate / selftest contract | `{verify_detail}` |")
trace_block = "\n".join(trace_rows)

if mode == "V":
    # DP-360 T6: the delivery/verification block is a T-task lifecycle field
    # (deliverable). V tasks carry the symmetric ac_verification block instead, so
    # delivery inputs against a V task are a caller error — fail loud rather than
    # silently dropping the payload.
    if deliverable_head_sha.strip():
        fail(
            f"task {task_id} is a V task; the deliverable/verification block is a "
            "T-task lifecycle field (V tasks use ac_verification). Do not pass "
            "--deliverable-head-sha to a V task"
        )
    # DP-302: V-task base branch is field-driven (source.base_branch or "main"),
    # the same root_base_branch resolved above — no source.type dispatch.
    v_base_branch = root_base_branch
    ac_by_id = {
        str(item.get("id")): item
        for item in (data.get("acceptance_criteria") or [])
        if isinstance(item, dict) and item.get("id")
    }
    implementation_tasks = []
    for dep in raw_dependencies:
        short_dep = short_work_item_id(dep)
        if short_dep and short_dep.startswith("T"):
            implementation_tasks.append(short_dep)
    if not implementation_tasks:
        implementation_tasks = [
            short_work_item_id(str(entry.get("id")))
            for entry in tasks
            if isinstance(entry, dict)
            and short_work_item_id(str(entry.get("id"))).startswith("T")
        ]
    implementation_tasks = [item for item in implementation_tasks if item]
    implementation_cell = ", ".join(implementation_tasks) if implementation_tasks else "N/A"
    ac_rows = []
    for ac in ac_list:
        ac_item = ac_by_id.get(ac) or {}
        ac_text = str(ac_item.get("text") or ac)
        ac_summary = (ac_text[:80] + "...") if len(ac_text) > 80 else ac_text
        method = str((ac_item.get("verification") or {}).get("method") or verification.get("method") or "unit_test")
        ac_rows.append(f"| {ac} | {ac_summary} | {implementation_cell} | {method} |")
    if not ac_rows:
        ac_rows.append(f"| AC-N/A | {scope} | {implementation_cell} | {verification.get('method') or 'unit_test'} |")
    ac_block = "\n".join(ac_rows)

    # DP-302 (AC3): V-task references = container-derived refinement paths plus
    # the verify-AC SKILL reference; container paths track jira vs dp by container
    # (no source.type branch / no hardcoded design-plans literal).
    v_references = container_references + [".claude/skills/verify-AC/SKILL.md"]
    v_references_cell = "<br>".join(f"- `{r}`" for r in v_references)

    doc = f"""---
title: "{source_id} {short_id}: {title} ({points} pt)"
description: "{scope}"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
task_kind: {mode}
verification:
  behavior_contract:
    applies: false
    reason: "framework static AC verification；無 runtime / UI 行為變更"
depends_on: []
---

# {short_id}: {title} ({points} pt)

> Source: {source_id} | Task: {task_identity} | JIRA: {jira_key_cell} | Repo: {repo_name}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | {source_type} |
| Source ID | {source_id} |
| Work item ID | {work_item_id_cell} |
| Task ID | {task_identity} |
| JIRA key | {jira_key_cell} |
| Implementation tasks | {implementation_cell} |
| Base branch | {v_base_branch} |
| Depends on | {depends_cell} |
| References to load | {v_references_cell} |

## 目標

{scope}

## 驗收項目

| AC | 摘要 | 對應實作 task | 驗證類型 |
|----|------|--------------|---------|
{ac_block}

## 估點理由

{points} pt — {scope}

## 驗收計畫（AC level）

1. 逐項讀取 `refinement.json` AC 與本 V task 的驗收項目。
2. 確認 implementation tasks 已完成且 evidence current。
3. 執行 `{verify_detail}`，逐 AC 記錄 PASS / FAIL / MANUAL_REQUIRED / UNCERTAIN。
4. 驗收結果寫回 V task lifecycle metadata。

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A
"""

    sys.stdout.write(doc)
    sys.exit(0)

# DP-311 T6 (AC8): T-task bodies carry the effective command in the ## Test
# Command / ## Verify Command fenced blocks; gate it through the shared
# executability helper BEFORE building the body, so a violation emits nothing.
# (V-task bodies have no command fence — the branch above already returned.)
check_verify_command_executability(task_id, effective_verify_command)

# T-task change table (## 改動範圍): each row's Action follows the authoritative
# modules[].action field (DP-325 T4 / AC5), never a path/filename heuristic. The
# V-task branch returned above, so this only runs for T tasks whose allowed files
# the refinement records in top-level modules[].
change_summary = (scope[:80] + "...") if len(scope) > 80 else scope
change_rows = []
for path in allowed_files:
    action = module_action_for(path)
    change_rows.append(f"| `{path}` | {action} | {change_summary} |")
change_block = "\n".join(change_rows)

# DP-296 T1/T3: task_shape propagation (T-task only — the V-task branch returned
# above, AC2). The canonical source is the matched tasks[] entry's first-class
# `task_shape` field (DP-296 canonicalize; the legacy top-level shape array read
# is removed, AC-NEG1). Passthrough only — derive does not validate the enum
# (single classifier = validate-task-md.sh, DP-262 AC7). A missing or empty
# task_shape → omit the line and the reader defaults to implementation (AC8
# zero-shim).
raw_shape = match.get("task_shape")
task_shape_value = str(raw_shape).strip() if raw_shape not in (None, "") else ""
task_shape_line = f"task_shape: {task_shape_value}\n" if task_shape_value else ""

# ---------------------------------------------------------------------------
# DP-302: per-task body fields are field-driven, not hardcoded framework
# defaults. The four fields (behavior_contract / test_environment /
# verify_command / references) live under tasks[].verification and are
# validated-when-present by validate-refinement-json.sh (T1). derive consumes
# them with three regimes so the same code path serves dp and jira:
#
#   * fully populated (the three body-shaping fields present) → field-driven;
#     zero framework literal leaks into frontmatter / Test Environment.
#   * partially populated (some present, some absent) → fail-loud naming the
#     missing field (AC-NEG1). derive must NOT re-inject the framework default
#     for the absent field once the task started declaring body fields.
#   * none present → legacy framework-infra defaults (back-compat for historical
#     dp work orders that predate the fields, AC-NEG2). This is a temporary
#     compat path; refinement (T3) populates the fields for all new source.
#
# `references` is additive: the resolved container refinement paths are always
# emitted, with any task-declared references appended.
BODY_SHAPING_FIELDS = ("behavior_contract", "test_environment")
present_body_fields = [f for f in BODY_SHAPING_FIELDS if f in verification]
body_is_field_driven = len(present_body_fields) == len(BODY_SHAPING_FIELDS)
if present_body_fields and not body_is_field_driven:
    missing = [f for f in BODY_SHAPING_FIELDS if f not in verification]
    fail(
        f"task {task_id} partially declares per-task body fields "
        f"(present: {present_body_fields}); missing required body field(s): "
        f"{missing}. Populate all body fields or none — derive will not "
        "silently apply a framework default for the missing field"
    )

if body_is_field_driven:
    bc = verification.get("behavior_contract") or {}
    bc_applies = bool(bc.get("applies"))
    if bc_applies:
        # DP-302 revision: when applies=true the derived frontmatter must carry the
        # FULL behavior_contract sub-field set that validate-task-md.sh requires for
        # a runtime/product task (source_of_truth / fixture_policy / flow /
        # assertions, plus mode), so the derived task.md is constructible (passes
        # validate-task-md.sh / validate-breakdown-ready.sh). Rendering only
        # applies+mode produced a task.md that the pre-existing validator rejected,
        # i.e. an applies=true (jira/product) derive output was not constructible.
        # Fail-loud (no framework default) on any missing required sub-field — the
        # same discipline the AC-NEG1 body-field path uses; derive must NOT invent
        # defaults for an applies=true task.
        def bc_require(field):
            value = bc.get(field)
            text = str(value).strip() if value not in (None, "") else ""
            if not text:
                fail(
                    f"task {task_id} behavior_contract.applies=true requires a "
                    f"non-empty '{field}' (no framework default)"
                )
            return text

        bc_mode = bc_require("mode")
        bc_source = bc_require("source_of_truth")
        bc_fixture = bc_require("fixture_policy")
        bc_flow = bc_require("flow")
        raw_assertions = bc.get("assertions")
        assertions = [
            str(item).strip()
            for item in (raw_assertions or [])
            if isinstance(item, str) and str(item).strip()
        ]
        if not assertions:
            fail(
                f"task {task_id} behavior_contract.applies=true requires a "
                "non-empty 'assertions' list of non-empty strings (no framework default)"
            )
        bc_lines = [
            "    applies: true",
            f"    mode: {bc_mode}",
            f"    source_of_truth: {bc_source}",
            f"    fixture_policy: {bc_fixture}",
        ]
        # fixture_policy=mockoon_required additionally requires a flow_script
        # (validate-task-md.sh accepts flow_script / script_path / playwright_script).
        if bc_fixture == "mockoon_required":
            bc_flow_script = bc.get("flow_script") or bc.get("script_path") or bc.get("playwright_script")
            bc_flow_script = str(bc_flow_script).strip() if bc_flow_script not in (None, "") else ""
            if not bc_flow_script:
                fail(
                    f"task {task_id} behavior_contract.fixture_policy=mockoon_required "
                    "requires a non-empty 'flow_script' (no framework default)"
                )
            bc_lines.append(f"    flow_script: {bc_flow_script}")
        # Optional passthrough fields, emitted only when declared. mode=hybrid
        # additionally requires a non-empty allowed_differences list (validator).
        bc_baseline_ref = str(bc.get("baseline_ref") or "").strip()
        if bc_baseline_ref:
            bc_lines.append(f"    baseline_ref: {bc_baseline_ref}")
        bc_target_url = str(bc.get("target_url") or "").strip()
        if bc_target_url:
            bc_lines.append(f"    target_url: {bc_target_url}")
        bc_viewport = str(bc.get("viewport") or "").strip()
        if bc_viewport:
            bc_lines.append(f"    viewport: {bc_viewport}")
        raw_allowed_diff = bc.get("allowed_differences")
        allowed_diff = [
            str(item).strip()
            for item in (raw_allowed_diff or [])
            if isinstance(item, str) and str(item).strip()
        ]
        if bc_mode == "hybrid" and not allowed_diff:
            fail(
                f"task {task_id} behavior_contract.mode=hybrid requires a non-empty "
                "'allowed_differences' list (no framework default)"
            )
        bc_lines.append(f"    flow: {bc_flow}")
        bc_lines.append("    assertions:")
        for item in assertions:
            bc_lines.append(f"      - {item}")
        if allowed_diff:
            bc_lines.append("    allowed_differences:")
            for item in allowed_diff:
                bc_lines.append(f"      - {item}")
        behavior_contract_block = "\n".join(bc_lines)
    else:
        bc_reason = str(bc.get("reason") or "").strip()
        if not bc_reason:
            fail(
                f"task {task_id} behavior_contract.applies=false requires a "
                "non-empty 'reason' (no framework default)"
            )
        behavior_contract_block = (
            "    applies: false\n"
            f'    reason: "{bc_reason}"'
        )
    te = verification.get("test_environment") or {}
    te_level_raw = str(te.get("level") or "").strip()
    if not te_level_raw:
        fail(
            f"task {task_id} test_environment.level is required when "
            "test_environment is declared (no framework default)"
        )
    # DP-316: project the refinement-side level onto the task.md Level enum
    # through the single canonical mapping. Previously this copied te_level_raw
    # verbatim, so a refinement level=component / integration produced a task.md
    # with an out-of-enum Level that validate-task-md.sh rejected.
    te_level = project_test_environment_level(te_level_raw, task_id)
    te_dev_env = str(te.get("dev_env_config") or "N/A").strip() or "N/A"
    te_fixtures = str(te.get("fixtures") or "N/A").strip() or "N/A"
    te_runtime_target = str(te.get("runtime_verify_target") or "N/A").strip() or "N/A"
    te_bootstrap = str(te.get("env_bootstrap_command") or "N/A").strip() or "N/A"
else:
    # Legacy framework-infra default (temporary back-compat, AC-NEG2).
    behavior_contract_block = (
        "    applies: false\n"
        '    reason: "framework deterministic gate / selftest / helper；無 runtime / UI 行為變更"'
    )
    te_level = "static"
    te_dev_env = "N/A"
    te_fixtures = "tmpdir + repo-tracked selftest fixtures"
    te_runtime_target = "N/A"
    te_bootstrap = "N/A"


# DP-302 (AC3): T-task references = container-derived refinement paths plus any
# task-declared references (the container paths were resolved before the V-task
# branch so both T and V share them).
declared_references = []
if body_is_field_driven:
    raw_refs = verification.get("references") or []
    declared_references = [
        str(r).strip() for r in raw_refs if isinstance(r, str) and str(r).strip()
    ]
all_references = container_references + [
    r for r in declared_references if r not in container_references
]
references_cell = "<br>".join(f"- `{r}`" for r in all_references)

# DP-360 T6 (D1/D2): the delivery/verification block is T-task-only — V tasks
# carry the symmetric ac_verification lifecycle block, not deliverable, and the
# V-task branch already returned above. Emitted only when delivery inputs are
# supplied; otherwise build_delivery_block() returns "" and the frontmatter is
# unchanged (additive / back-compat).
delivery_block = build_delivery_block(task_id)
delivery_block_line = f"{delivery_block}\n" if delivery_block else ""

# DP-335 T1 (AC1): the `## Verification Handoff` paragraph is conditional on the
# task's AUTHORITATIVE verification declaration fields, not a path / filename
# heuristic (consumer-reads-authoritative-field canary). Two authoritative signals
# mark a "product-UI task that verifies itself" (no umbrella-V delegation):
#   * verification.behavior_contract.applies == true  (Layer D self-verification)
#   * verification.visual_regression declared/non-empty (Layer C self-verification)
# When either holds, the handoff reflects the task's OWN wiring and must NOT emit
# the phantom `{source_id}-V1（umbrella regression）` text nor the「framework work
# order」label. Otherwise (framework-infra task with applies=false and no
# visual_regression) the existing umbrella-V1 delegation text is preserved
# unchanged (no regression). `bc_applies` is recomputed here from the same
# `verification.behavior_contract` dict the frontmatter path read, because the
# field-driven branch above scopes its local `bc_applies` inside
# `if body_is_field_driven:` and the legacy back-compat branch never computed it.
_bc = verification.get("behavior_contract") or {}
handoff_bc_applies = bool(_bc.get("applies"))
_vr = verification.get("visual_regression")
# Non-empty when declared: a dict/list with content, or any other truthy value.
handoff_has_visual_regression = bool(_vr)
if handoff_bc_applies:
    verification_handoff_block = (
        "product UI work order；本 task 自身以 Layer D `verification.behavior_contract` "
        "驗收（無 umbrella V 委派）。"
    )
elif handoff_has_visual_regression:
    verification_handoff_block = (
        "product UI work order；本 task 自身以 Layer C `verification.visual_regression` "
        "驗收（無 umbrella V 委派）。"
    )
else:
    verification_handoff_block = (
        f"framework work order；驗收委派給 {source_id}-V1（umbrella regression）。"
    )

doc = f"""---
title: "{source_id} {short_id}: {title} ({points} pt)"
description: "{scope}"
draft: true
sidebar:
  hidden: true
status: IN_PROGRESS
task_kind: {mode}
{task_shape_line}verification:
  behavior_contract:
{behavior_contract_block}
depends_on: [{depends_on_frontmatter}]
{delivery_block_line}---

# {short_id}: {title} ({points} pt)

> Source: {source_id} | Task: {task_identity} | JIRA: {jira_key_cell} | Repo: {repo_name}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | {source_type} |
| Source ID | {source_id} |
| Work item ID | {work_item_id_cell} |
| Task ID | {task_identity} |
| JIRA key | {jira_key_cell} |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | {base_branch} |
| Branch chain | {branch_chain} |
| Task branch | {task_branch} |
| Depends on | {depends_cell} |
| References to load | {references_cell} |

## Verification Handoff

{verification_handoff_block}

## 目標

{scope}

## 改動範圍

| 檔案 | 動作 | 變更摘要 |
|------|------|----------|
{change_block}

## Allowed Files

{allowed_files_block}

## Scope Trace Matrix

| Goal / AC | Owning files | Surface / boundary | Tests |
|-----------|--------------|--------------------|-------|
{trace_block}

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | changed files all match Allowed Files | engineering |
| test | yes | `{verify_detail}` PASS | engineering |
| verify | yes | `{effective_verify_command}` PASS | engineering |
| ci-local | no | N/A | framework repo 無 ci-local |

## 估點理由

{points} pt — {scope}

## 測試計畫（code-level）

1. 先擴張對應 selftest，新增 failing cases 涵蓋 {', '.join(ac_list)}。
2. 實作 Allowed Files 內的 producer / hook / validator 變更。
3. 跑 `{verify_detail}` 直到 PASS。
4. 確認 CHANGELOG 與 VERSION（若有）同步。

## Test Command

```bash
{effective_verify_command}
```

## Test Environment

- **Level**: {te_level}
- **Dev env config**: {te_dev_env}
- **Fixtures**: {te_fixtures}
- **Runtime verify target**: {te_runtime_target}
- **Env bootstrap command**: {te_bootstrap}

## Verify Command

```bash
set -euo pipefail
{effective_verify_command}
```
"""

sys.stdout.write(doc)
PY
