"""Structured validator authority extracted from scripts/validate-memory-hygiene-plan.sh."""

import json
import re
import sys
from pathlib import Path

fmt = sys.argv[1]
input_path = sys.argv[2]
payload_text = (
    Path(input_path).read_text(encoding="utf-8") if input_path else sys.stdin.read()
)

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TOPIC_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
FILE_RE = re.compile(r"^[A-Za-z0-9._-]+\.md$")
VALID_TIERS = {"hot", "warm", "cold"}
FLAG_KEYS = {
    "stale_snapshot",
    "graduated_feedback",
    "nested_frontmatter",
    "fresh_write_hot",
}
SUMMARY_KEYS = FLAG_KEYS | {"created_backfill"}

issues = []
warnings = []

try:
    data = json.loads(payload_text)
except json.JSONDecodeError as exc:
    issues.append({"code": "invalid_json", "detail": str(exc)})
    data = {}

if not issues and not isinstance(data, dict):
    issues.append(
        {"code": "root_not_object", "detail": "plan root must be a JSON object"}
    )

if not issues:
    date_value = data.get("date")
    if not isinstance(date_value, str) or not DATE_RE.match(date_value):
        issues.append({"code": "invalid_date", "detail": "date must be YYYY-MM-DD"})

    summary = data.get("summary")
    if summary is not None:
        if not isinstance(summary, dict):
            issues.append(
                {
                    "code": "invalid_summary",
                    "detail": "summary must be an object when present",
                }
            )
        else:
            for key in SUMMARY_KEYS:
                value = summary.get(key)
                if not isinstance(value, int) or value < 0:
                    issues.append(
                        {"code": "invalid_summary_count", "detail": f"summary.{key}"}
                    )

    hot_order = data.get("hot_order")
    if hot_order is not None:
        if not isinstance(hot_order, list) or not all(
            isinstance(item, str) and FILE_RE.match(item) for item in hot_order
        ):
            issues.append(
                {
                    "code": "invalid_hot_order",
                    "detail": "hot_order must be an array of memory filenames",
                }
            )

    classifications = data.get("classifications")
    if not isinstance(classifications, list) or not classifications:
        issues.append(
            {
                "code": "missing_classifications",
                "detail": "classifications must be a non-empty array",
            }
        )
    else:
        seen = set()
        for idx, item in enumerate(classifications):
            prefix = f"classifications[{idx}]"
            if not isinstance(item, dict):
                issues.append({"code": "classification_not_object", "detail": prefix})
                continue
            file_name = item.get("file")
            tier = item.get("tier")
            topic = item.get("topic")
            reason = item.get("reason")
            pinned = item.get("pinned")
            pinned_reason = item.get("pinned_reason")
            archived = item.get("archived_in_index")
            trigger_count = item.get("trigger_count")
            flags = item.get("flags")
            created_backfill = item.get("created_backfill")

            if (
                not isinstance(file_name, str)
                or not FILE_RE.match(file_name)
                or file_name == "MEMORY.md"
            ):
                issues.append({"code": "invalid_file", "detail": f"{prefix}.file"})
            elif file_name in seen:
                issues.append({"code": "duplicate_file", "detail": file_name})
            else:
                seen.add(file_name)

            if tier not in VALID_TIERS:
                issues.append(
                    {"code": "invalid_tier", "detail": f"{prefix}.tier={tier}"}
                )

            if not isinstance(reason, str) or not reason.strip():
                issues.append({"code": "missing_reason", "detail": f"{prefix}.reason"})

            if not isinstance(trigger_count, int) or trigger_count < 0:
                issues.append(
                    {
                        "code": "invalid_trigger_count",
                        "detail": f"{prefix}.trigger_count",
                    }
                )

            if not isinstance(pinned, bool):
                issues.append({"code": "invalid_pinned", "detail": f"{prefix}.pinned"})
            elif pinned is True and (
                not isinstance(pinned_reason, str) or not pinned_reason.strip()
            ):
                issues.append(
                    {
                        "code": "missing_pinned_reason",
                        "detail": file_name or f"{prefix}.pinned_reason",
                    }
                )

            if not isinstance(archived, bool):
                issues.append(
                    {
                        "code": "invalid_archived_flag",
                        "detail": f"{prefix}.archived_in_index",
                    }
                )

            if tier == "warm":
                if topic is not None and (
                    not isinstance(topic, str) or not TOPIC_RE.match(topic)
                ):
                    issues.append(
                        {"code": "invalid_warm_topic", "detail": f"{prefix}.topic"}
                    )
            else:
                if topic is not None:
                    issues.append(
                        {"code": "non_warm_topic_present", "detail": f"{prefix}.topic"}
                    )

            if pinned is True and tier != "hot":
                issues.append({"code": "pinned_not_hot", "detail": file_name})

            if archived is True and tier != "cold":
                issues.append({"code": "archived_not_cold", "detail": file_name})

            if flags is not None:
                if not isinstance(flags, dict):
                    issues.append(
                        {"code": "invalid_flags", "detail": f"{prefix}.flags"}
                    )
                else:
                    for key in FLAG_KEYS:
                        if not isinstance(flags.get(key), bool):
                            issues.append(
                                {
                                    "code": "invalid_flag_value",
                                    "detail": f"{prefix}.flags.{key}",
                                }
                            )
                    grace = flags.get("grace_baseline")
                    if grace is not None and grace not in {"created", "mtime_fallback"}:
                        issues.append(
                            {
                                "code": "invalid_grace_baseline",
                                "detail": f"{prefix}.flags.grace_baseline",
                            }
                        )
                    if flags.get("nested_frontmatter") is True:
                        # DP-213: nested_frontmatter is normalized by apply itself,
                        # so validator only surfaces it as a warning (not a failure).
                        warnings.append(
                            {"code": "nested_frontmatter", "detail": file_name}
                        )

            if created_backfill is not None and (
                not isinstance(created_backfill, str)
                or not DATE_RE.match(created_backfill)
            ):
                issues.append(
                    {
                        "code": "invalid_created_backfill",
                        "detail": f"{prefix}.created_backfill",
                    }
                )

result = {
    "passed": not issues,
    "issues": issues,
    "warnings": warnings,
}

# Verdict goes to stderr (--format selects its representation). On PASS the
# plan JSON is re-emitted verbatim to stdout so the chain can pipe it to apply.
if fmt == "json":
    print(json.dumps(result, ensure_ascii=False), file=sys.stderr)
else:
    if result["passed"]:
        print("PASS: memory hygiene plan valid", file=sys.stderr)
    else:
        print("FAIL: memory hygiene plan invalid", file=sys.stderr)
        for issue in issues:
            print(f"  - {issue['code']}: {issue['detail']}", file=sys.stderr)
    if warnings:
        print("WARNINGS:", file=sys.stderr)
        for w in warnings:
            print(f"  - {w['code']}: {w['detail']}", file=sys.stderr)

if result["passed"]:
    # Verbatim pass-through (exact bytes read from input).
    sys.stdout.write(payload_text)
    sys.stdout.flush()

sys.exit(0 if result["passed"] else 1)
