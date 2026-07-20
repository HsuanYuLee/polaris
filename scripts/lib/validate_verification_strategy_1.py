"""Structured validator authority extracted from scripts/validate-verification-strategy.sh."""

import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])


def fail(marker: str, message: str) -> None:
    print(f"{marker}: {message}", file=sys.stderr)
    raise SystemExit(2)


try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    fail("POLARIS_VERIFICATION_STRATEGY_INVALID", f"{path}: invalid JSON: {exc}")

strategy = data.get("verification_strategy")
if strategy is None:
    print(
        f"validate-verification-strategy.sh PASS - no verification_strategy present ({path})"
    )
    raise SystemExit(0)
if not isinstance(strategy, dict):
    fail(
        "POLARIS_VERIFICATION_STRATEGY_INVALID",
        "verification_strategy must be an object",
    )

mode = strategy.get("mode")
valid_modes = {"per_task_self_verify", "source_level_v_required", "external_ac_ticket"}
if mode not in valid_modes:
    fail(
        "POLARIS_VERIFICATION_STRATEGY_INVALID",
        f"verification_strategy.mode must be one of {sorted(valid_modes)} (got: {mode!r})",
    )

for field in ("reason", "authority"):
    value = strategy.get(field)
    if not isinstance(value, str) or not value.strip():
        fail(
            "POLARIS_VERIFICATION_STRATEGY_INVALID",
            f"verification_strategy.{field} must be a non-empty string",
        )

tasks = data.get("tasks")
if not isinstance(tasks, list):
    tasks = []


def short_task_id(task: dict) -> str:
    raw = str(task.get("id") or "").strip()
    if re.fullmatch(r"[TV][0-9]+[a-z]?", raw):
        return raw
    m = re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+-([TV][0-9]+[a-z]?)", raw)
    return m.group(1) if m else raw


v_tasks = [
    task
    for task in tasks
    if isinstance(task, dict) and short_task_id(task).startswith("V")
]
t_tasks = [
    task
    for task in tasks
    if isinstance(task, dict) and short_task_id(task).startswith("T")
]

if mode == "source_level_v_required" and not v_tasks:
    fail(
        "POLARIS_VERIFICATION_STRATEGY_MISSING_V_TASK",
        "verification_strategy.mode=source_level_v_required requires at least one V task in tasks[]",
    )

if mode == "per_task_self_verify":
    for idx, task in enumerate(t_tasks):
        verification = task.get("verification") if isinstance(task, dict) else None
        verify_command = (
            verification.get("verify_command")
            if isinstance(verification, dict)
            else None
        )
        if not isinstance(verify_command, str) or not verify_command.strip():
            fail(
                "POLARIS_VERIFICATION_STRATEGY_SELF_VERIFY_INCOMPLETE",
                f"per_task_self_verify requires tasks[{idx}] T task to declare verification.verify_command",
            )

if mode == "external_ac_ticket":
    ticket = (
        strategy.get("ticket")
        or strategy.get("ticket_key")
        or strategy.get("ac_ticket")
        or strategy.get("external_ticket")
    )
    if not isinstance(ticket, str) or not ticket.strip():
        fail(
            "POLARIS_VERIFICATION_STRATEGY_EXTERNAL_TICKET_MISSING",
            "external_ac_ticket requires ticket/ticket_key/ac_ticket/external_ticket",
        )

print(f"validate-verification-strategy.sh PASS - mode={mode} ({path})")
