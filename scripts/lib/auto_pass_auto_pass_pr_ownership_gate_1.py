import json
import sys
from pathlib import Path

state_file, read_stdin = sys.argv[1], sys.argv[2] == "1"

DRAFT = "POLARIS_AUTO_PASS_PR_DRAFT_BLOCKED"
OWNERSHIP = "POLARIS_AUTO_PASS_PR_OWNERSHIP_BLOCKED"
ALLOWED_PUBLISHERS = {
    "polaris-pr-create",
    "polaris-pr-create.sh",
    "scripts/polaris-pr-create.sh",
}
FRESH_VALUES = {"fresh", "current", "pass", "passed", "clean", "ok"}


def blocked(marker, reason):
    print(f"{marker}:{reason}", file=sys.stderr)
    raise SystemExit(2)


try:
    raw = (
        sys.stdin.read() if read_stdin else Path(state_file).read_text(encoding="utf-8")
    )
    data = json.loads(raw)
except Exception as exc:
    blocked(OWNERSHIP, f"input is not readable JSON ({exc})")
if not isinstance(data, dict):
    blocked(OWNERSHIP, "input must be a JSON object")


def ownership_payload(obj):
    for key in ("auto_pass_pr_ownership", "pr_ownership"):
        nested = obj.get(key)
        if isinstance(nested, dict):
            merged = dict(obj)
            merged.update(nested)
            return merged
    return obj


payload = ownership_payload(data)


def first(*paths):
    for path in paths:
        cur = payload
        found = True
        for key in path:
            if isinstance(cur, dict) and key in cur:
                cur = cur[key]
            else:
                found = False
                break
        if found:
            return cur
    return None


def as_bool(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"true", "yes", "1"}:
            return True
        if lowered in {"false", "no", "0"}:
            return False
    return None


def completion_pass(value):
    if value is True:
        return True
    if isinstance(value, str):
        return value.strip().upper() == "PASS"
    if isinstance(value, dict):
        status = value.get("status")
        if isinstance(status, str):
            return status.strip().upper() == "PASS"
        if value.get("pass") is True or value.get("present") is True:
            return True
    return False


def freshness_pass(value):
    if value is None:
        return False
    if value is True:
        return True
    if isinstance(value, str):
        return value.strip().lower() in FRESH_VALUES
    if isinstance(value, dict):
        if value.get("is_fresh") is True or value.get("fresh") is True:
            return True
        for key in ("status", "state", "result"):
            raw = value.get(key)
            if isinstance(raw, str) and raw.strip().lower() in FRESH_VALUES:
                return True
    return False


def present_pass(value):
    if value is True:
        return True
    if isinstance(value, str):
        return value.strip().upper() in {"PASS", "PRESENT", "OK", "FOUND"}
    if isinstance(value, dict):
        status = value.get("status")
        if isinstance(status, str) and status.strip().upper() in {
            "PASS",
            "PRESENT",
            "OK",
            "FOUND",
        }:
            return True
        if (
            value.get("present") is True
            or value.get("pass") is True
            or value.get("found") is True
        ):
            return True
    return False


pr_url = first(("pr_url",), ("url",), ("pr", "url"), ("pull_request", "url"))
if not isinstance(pr_url, str) or not pr_url.strip():
    blocked(OWNERSHIP, "pr_url is required")

draft_value = first(
    ("isDraft",),
    ("is_draft",),
    ("draft",),
    ("pr", "isDraft"),
    ("pull_request", "isDraft"),
)
draft_bool = as_bool(draft_value)
if draft_bool is None:
    blocked(OWNERSHIP, "isDraft/is_draft=false is required")
if draft_bool:
    blocked(DRAFT, f"draft PR is not a valid auto-pass delivery PR: {pr_url}")

publisher = first(
    ("publisher",),
    ("writer",),
    ("created_by",),
    ("provenance", "writer"),
    ("pr_create_evidence", "writer"),
)
publisher = str(publisher or "").strip()
if publisher not in ALLOWED_PUBLISHERS:
    blocked(
        OWNERSHIP,
        f"publisher must be polaris-pr-create.sh, got {publisher or '<missing>'}",
    )

completion = first(
    ("engineering_completion_marker",),
    ("completion_marker",),
    ("completion_gate",),
    ("deliverable", "verification"),
    ("verification",),
)
if not completion_pass(completion):
    blocked(OWNERSHIP, "engineering completion marker must be PASS/present")

freshness = first(("base_freshness",), ("readiness", "base_freshness"), ("freshness",))
if not freshness_pass(freshness):
    blocked(OWNERSHIP, "PR base freshness must be fresh/current")

no_bypass_required = as_bool(
    first(("engineering_no_bypass_required",), ("no_bypass_required",))
)
if no_bypass_required:
    required = [
        (
            "task.md lineage",
            first(("task_md_lineage",), ("lineage", "task_md"), ("lineage",)),
        ),
        ("resolver lock", first(("resolver_lock",), ("work_order_lock",))),
        (
            "readiness pack snapshot",
            first(
                ("readiness_pack_snapshot",),
                ("baseline_snapshot",),
                ("planner_owned_baseline_snapshot",),
            ),
        ),
        (
            "skill boundary marker",
            first(
                ("skill_boundary_marker",),
                ("skill_workflow_boundary_marker",),
                ("boundary_marker",),
            ),
        ),
    ]
    for label, value in required:
        if not present_pass(value):
            blocked(
                OWNERSHIP, f"{label} must be present/PASS for engineering no-bypass"
            )

print(f"PASS: auto-pass PR ownership gate ({pr_url})")
