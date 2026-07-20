"""Enforce selftest corpus debt, latency, and reproducible quality metrics."""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any


MARKER = "POLARIS_CORPUS_BUDGET"


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} unreadable: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"{label} must be a JSON object")
    return data


def changed_paths(root: Path, base_ref: str | None) -> dict[str, str]:
    if not base_ref:
        return {}
    result = subprocess.run(
        ["git", "-C", str(root), "diff", "--name-status", f"{base_ref}...HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise ValueError(f"cannot derive changed files from {base_ref}: {result.stderr.strip()}")
    changed: dict[str, str] = {}
    for line in result.stdout.splitlines():
        cells = line.split("\t")
        if len(cells) < 2:
            continue
        status = cells[0][0]
        path = cells[-1]
        changed[path] = status
    return changed


def load_base_entries(root: Path, base_ref: str | None) -> list[dict[str, Any]] | None:
    if not base_ref:
        return None
    result = subprocess.run(
        ["git", "-C", str(root), "show", f"{base_ref}:scripts/script-layer-governance-ledger.json"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise ValueError(f"cannot read base ledger from {base_ref}: {result.stderr.strip()}")
    try:
        entries = json.loads(result.stdout)["entries"]
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        raise ValueError(f"base ledger from {base_ref} is malformed: {exc}") from exc
    if not isinstance(entries, list):
        raise ValueError(f"base ledger from {base_ref} entries must be a list")
    return entries


def validate_metric(metric: dict[str, Any], budget: dict[str, Any], errors: list[str]) -> int:
    required = {"head_sha", "duration_ms", "per_test", "tracked_debt", "false_positive_reproducers", "route_backs"}
    missing = sorted(required - metric.keys())
    if missing:
        errors.append(f"metrics missing fields: {', '.join(missing)}")
        return 0
    per_test = metric.get("per_test")
    if not isinstance(per_test, list) or not per_test:
        errors.append("metrics per_test must be a non-empty list")
        return 0
    max_ms = int(budget["per_test_max_ms"])
    for item in per_test:
        if not isinstance(item, dict) or not isinstance(item.get("path"), str) or not isinstance(item.get("duration_ms"), int):
            errors.append("metrics per_test entries require path and integer duration_ms")
            continue
        if item["duration_ms"] > max_ms:
            errors.append(f"per-test latency exceeds {max_ms}ms: {item['path']}={item['duration_ms']}ms")

    debt = metric.get("tracked_debt")
    if not isinstance(debt, list):
        errors.append("metrics tracked_debt must be a list")
    else:
        for item in debt:
            if not isinstance(item, dict) or not all(item.get(field) for field in ("path", "reproducer")):
                errors.append("tracked debt entries require path and reproducer")
            elif item.get("base_exit_code") in (None, 0):
                errors.append(f"tracked debt is not reproduced red on base: {item.get('path', '<unknown>')}")

    false_positives = metric.get("false_positive_reproducers")
    if not isinstance(false_positives, list):
        errors.append("false_positive_reproducers must be a list")
    else:
        for item in false_positives:
            if not isinstance(item, dict) or not all(item.get(field) for field in ("reproducer", "expected", "observed", "disposition")):
                errors.append("false-positive entries require reproducer, expected, observed, and disposition")
            elif item["expected"] == item["observed"]:
                errors.append(f"semantic-invalid false-positive reproducer: {item['reproducer']}")
        if len(false_positives) > int(budget["false_positive_max"]):
            errors.append(
                f"false-positive count {len(false_positives)} exceeds draining baseline {budget['false_positive_max']}"
            )

    route_backs = metric.get("route_backs")
    if not isinstance(route_backs, list):
        errors.append("route_backs must be a list")
    else:
        for item in route_backs:
            if not isinstance(item, dict) or not all(item.get(field) for field in ("path", "owner", "reason", "reproducer")):
                errors.append("route-back entries require path, owner, reason, and reproducer")
        if len(route_backs) > int(budget["route_back_max"]):
            errors.append(f"route-back count {len(route_backs)} exceeds draining baseline {budget['route_back_max']}")
    return int(metric.get("duration_ms", 0))


def validate(args: argparse.Namespace) -> list[str]:
    ledger = load_json(args.ledger, "ledger")
    manifest = load_json(args.manifest, "manifest")
    governance = manifest.get("script_layer_governance")
    if not isinstance(governance, dict) or not isinstance(governance.get("corpus_budget"), dict):
        return ["manifest missing script_layer_governance.corpus_budget"]
    budget = governance["corpus_budget"]
    required_budget = {
        "test_nonterminal_max",
        "owner_nonterminal_max",
        "tracked_debt_max",
        "per_test_max_ms",
        "full_run_median_target_ms",
        "minimum_full_runs",
        "false_positive_max",
        "route_back_max",
    }
    missing = sorted(required_budget - budget.keys())
    if missing:
        return [f"corpus budget missing fields: {', '.join(missing)}"]

    entries = ledger.get("entries")
    if not isinstance(entries, list):
        return ["ledger entries must be a list"]
    test_debt = [entry for entry in entries if entry.get("surface") == "test" and entry.get("terminal") is False]
    errors: list[str] = []
    if len(test_debt) > int(budget["test_nonterminal_max"]):
        errors.append(
            f"test migration debt increased: {len(test_debt)} > {budget['test_nonterminal_max']}"
        )
    owners: dict[str, int] = {}
    for entry in test_debt:
        owner = str(entry.get("owner") or "")
        owners[owner] = owners.get(owner, 0) + 1
    owner_max = budget["owner_nonterminal_max"]
    if not isinstance(owner_max, dict):
        errors.append("owner_nonterminal_max must be an object")
    else:
        for owner, count in owners.items():
            if owner not in owner_max:
                errors.append(f"test debt has unbudgeted owner: {owner or '<none>'}")
            elif count > int(owner_max[owner]):
                errors.append(f"test debt for {owner} increased: {count} > {owner_max[owner]}")

    base_entries = load_base_entries(args.root.resolve(), args.base_ref)
    if base_entries is not None:
        base_debt = [entry for entry in base_entries if entry.get("surface") == "test" and entry.get("terminal") is False]
        if len(test_debt) > len(base_debt):
            errors.append(f"test migration debt regressed from prior wave: {len(test_debt)} > {len(base_debt)}")
        base_owners: dict[str, int] = {}
        for entry in base_debt:
            owner = str(entry.get("owner") or "")
            base_owners[owner] = base_owners.get(owner, 0) + 1
        for owner, count in owners.items():
            if count > base_owners.get(owner, 0):
                errors.append(
                    f"test debt for {owner or '<none>'} regressed from prior wave: {count} > {base_owners.get(owner, 0)}"
                )

    root = args.root.resolve()
    changed = changed_paths(root, args.base_ref)
    by_path = {entry.get("path"): entry for entry in entries if isinstance(entry, dict)}
    for path, status in changed.items():
        entry = by_path.get(path)
        if not isinstance(entry, dict) or entry.get("surface") != "test":
            continue
        if entry.get("disposition") == "migrate" or entry.get("terminal") is False:
            errors.append(f"changed test remains migration debt: {path}")
        if status == "A" and entry.get("language") == "bash":
            errors.append(f"new Bash selftest must use pytest or explicit non-test classification: {path}")

    durations: list[int] = []
    for metric_path in args.metrics:
        metric = load_json(metric_path, "metrics")
        if int(metric.get("tracked_debt_count", len(metric.get("tracked_debt", [])))) > int(budget["tracked_debt_max"]):
            errors.append(
                f"tracked red debt increased: {metric.get('tracked_debt_count')} > {budget['tracked_debt_max']}"
            )
        durations.append(validate_metric(metric, budget, errors))
    if len(durations) >= int(budget["minimum_full_runs"]):
        median = statistics.median(durations[-int(budget["minimum_full_runs"]):])
        if median > int(budget["full_run_median_target_ms"]):
            errors.append(
                f"full-run median {int(median)}ms exceeds target {budget['full_run_median_target_ms']}ms"
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--base-ref")
    parser.add_argument("--metrics", type=Path, action="append", default=[])
    args = parser.parse_args()
    try:
        errors = validate(args)
    except ValueError as exc:
        errors = [str(exc)]
    if errors:
        for error in errors:
            print(f"{MARKER}: {error}", file=sys.stderr)
        return 2
    print("PASS: selftest corpus budget")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
