#!/usr/bin/env python3
"""Build a lean review-inbox runtime execution plan.

The plan is intentionally separate from prompt generation. It tells the
orchestrator which review packets can be executed, in what order, and whether a
runtime adapter is allowed to use a sub-agent for the work.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build review-inbox runtime plan JSON.")
    parser.add_argument("--manifest", default="", help="Prompt manifest JSON from build-review-prompt.sh.")
    parser.add_argument("--out", default="", help="Output path. Defaults to stdout.")
    parser.add_argument(
        "--adapter",
        choices=("main_session_sequential", "constrained_code_reviewer"),
        default="main_session_sequential",
        help="Runtime adapter contract for the plan.",
    )
    parser.add_argument(
        "--auto-adapter",
        action="store_true",
        help="Select adapter from candidate count, cluster size, raw diff lines, and quality evidence.",
    )
    parser.add_argument("--candidate-threshold", type=int, default=5, help="Auto adapter candidate-count threshold.")
    parser.add_argument("--cluster-threshold", type=int, default=3, help="Auto adapter cluster-size threshold.")
    parser.add_argument("--diff-lines-threshold", type=int, default=5000, help="Auto adapter total raw diff line threshold.")
    parser.add_argument(
        "--adapter-evidence",
        choices=("missing", "failed", "passed"),
        default="missing",
        help="T7 dual-run quality evidence status for constrained_code_reviewer.",
    )
    return parser.parse_args()


def load_json_array(path: str) -> list[dict[str, Any]]:
    if not path:
        return []
    data = json.loads(Path(path).read_text())
    if not isinstance(data, list):
        raise SystemExit(f"manifest must be a JSON array: {path}")
    return [item for item in data if isinstance(item, dict)]


def pr_number(candidate: dict[str, Any]) -> int:
    try:
        return int(candidate.get("number") or 0)
    except (TypeError, ValueError):
        return 0


def safe_id(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-")
    if cleaned:
        return cleaned[:80]
    return hashlib.sha1(value.encode("utf-8")).hexdigest()[:12]


def candidate_key(candidate: dict[str, Any]) -> str:
    return str(candidate.get("url") or f"{candidate.get('repo')}#{candidate.get('number')}")


def manifest_by_url(manifest: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {str(item.get("pr_url") or ""): item for item in manifest if item.get("pr_url")}


def safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def raw_diff_lines(candidate: dict[str, Any]) -> int:
    for key in ("raw_diff_lines", "diff_lines", "changed_lines"):
        value = safe_int(candidate.get(key), 0)
        if value > 0:
            return value
    return safe_int(candidate.get("additions"), 0) + safe_int(candidate.get("deletions"), 0)


def select_adapter(
    candidates: list[dict[str, Any]],
    requested_adapter: str,
    auto_adapter: bool,
    candidate_threshold: int,
    cluster_threshold: int,
    diff_lines_threshold: int,
    adapter_evidence: str,
) -> tuple[str, dict[str, Any]]:
    candidate_count = len(candidates)
    max_cluster_size = max([safe_int(item.get("cluster_size"), 1) for item in candidates] or [0])
    total_raw_diff_lines = sum(raw_diff_lines(item) for item in candidates)
    threshold_hit = (
        candidate_count >= candidate_threshold
        or max_cluster_size >= cluster_threshold
        or total_raw_diff_lines > diff_lines_threshold
    )

    if not auto_adapter:
        return requested_adapter, {
            "auto_adapter": False,
            "selected_adapter": requested_adapter,
            "fallback_reason": "",
            "candidate_threshold": candidate_threshold,
            "cluster_threshold": cluster_threshold,
            "diff_lines_threshold": diff_lines_threshold,
            "adapter_evidence": adapter_evidence,
            "max_cluster_size": max_cluster_size,
            "total_raw_diff_lines": total_raw_diff_lines,
            "threshold_hit": threshold_hit,
        }

    if adapter_evidence != "passed":
        return "main_session_sequential", {
            "auto_adapter": True,
            "selected_adapter": "main_session_sequential",
            "fallback_reason": "T7 dual-run quality evidence is not passed.",
            "candidate_threshold": candidate_threshold,
            "cluster_threshold": cluster_threshold,
            "diff_lines_threshold": diff_lines_threshold,
            "adapter_evidence": adapter_evidence,
            "max_cluster_size": max_cluster_size,
            "total_raw_diff_lines": total_raw_diff_lines,
            "threshold_hit": threshold_hit,
        }

    if threshold_hit:
        return "constrained_code_reviewer", {
            "auto_adapter": True,
            "selected_adapter": "constrained_code_reviewer",
            "fallback_reason": "",
            "candidate_threshold": candidate_threshold,
            "cluster_threshold": cluster_threshold,
            "diff_lines_threshold": diff_lines_threshold,
            "adapter_evidence": adapter_evidence,
            "max_cluster_size": max_cluster_size,
            "total_raw_diff_lines": total_raw_diff_lines,
            "threshold_hit": threshold_hit,
        }

    return "main_session_sequential", {
        "auto_adapter": True,
        "selected_adapter": "main_session_sequential",
        "fallback_reason": "Candidate count, cluster size, and raw diff lines are below auto-adapter thresholds.",
        "candidate_threshold": candidate_threshold,
        "cluster_threshold": cluster_threshold,
        "diff_lines_threshold": diff_lines_threshold,
        "adapter_evidence": adapter_evidence,
        "max_cluster_size": max_cluster_size,
        "total_raw_diff_lines": total_raw_diff_lines,
        "threshold_hit": threshold_hit,
    }


def cluster_order_key(group: list[dict[str, Any]]) -> tuple[int, str, int]:
    first_index = min(int(item["_input_index"]) for item in group)
    lead = next((item for item in group if item.get("cluster_role") == "cluster_lead"), group[0])
    return (first_index, str(lead.get("repo") or ""), pr_number(lead))


def step_for(
    step_number: int,
    candidate: dict[str, Any],
    manifest: dict[str, Any],
    adapter: str,
    lead_summary_path: str,
) -> dict[str, Any]:
    role = str(candidate.get("cluster_role") or "standalone")
    phase = role if role in {"cluster_lead", "cluster_sibling"} else "standalone"
    requires_lead_summary = phase == "cluster_sibling"
    return {
        "step": step_number,
        "phase": phase,
        "execution_mode": adapter,
        "general_purpose_subagent_allowed": False,
        "repo": candidate.get("repo"),
        "number": candidate.get("number"),
        "pr_url": candidate.get("url"),
        "prompt_file": manifest.get("file", ""),
        "model_tier": candidate.get("model_tier", "standard_coding"),
        "cluster_key": candidate.get("cluster_key", ""),
        "cluster_role": role,
        "cluster_size": candidate.get("cluster_size", 1),
        "ticket_key": candidate.get("ticket_key"),
        "root_ticket_key": candidate.get("root_ticket_key"),
        "root_topic_key": candidate.get("root_topic_key"),
        "lead_pr_url": candidate.get("cluster_lead_url", ""),
        "lead_summary_path": lead_summary_path if candidate.get("cluster_key") else "",
        "requires_lead_summary": requires_lead_summary,
        "fallback_on_uncertain": "mark needs_standard_review and rerun as standard_coding",
    }


def build_plan(
    candidates: list[dict[str, Any]],
    manifest: list[dict[str, Any]],
    adapter: str,
    adapter_decision: dict[str, Any],
) -> dict[str, Any]:
    manifest_map = manifest_by_url(manifest)
    indexed = []
    for idx, raw in enumerate(candidates):
        item = dict(raw)
        item["_input_index"] = idx
        indexed.append(item)

    groups: dict[str, list[dict[str, Any]]] = {}
    for item in indexed:
        key = str(item.get("cluster_key") or candidate_key(item))
        groups.setdefault(key, []).append(item)

    ordered_groups = sorted(groups.values(), key=cluster_order_key)
    steps: list[dict[str, Any]] = []
    clusters: list[dict[str, Any]] = []
    step_number = 1

    for group in ordered_groups:
        group.sort(
            key=lambda item: (
                0 if item.get("cluster_role") == "cluster_lead" else 1,
                str(item.get("repo") or ""),
                pr_number(item),
            )
        )
        cluster_key = str(group[0].get("cluster_key") or "")
        lead = next((item for item in group if item.get("cluster_role") == "cluster_lead"), group[0])
        lead_summary_path = ""
        if cluster_key and len(group) > 1:
            lead_summary_path = f"/tmp/review-inbox-lead-summaries/{safe_id(cluster_key)}.md"
        clusters.append(
            {
                "cluster_key": cluster_key,
                "size": len(group),
                "lead_pr_url": lead.get("url"),
                "lead_summary_path": lead_summary_path,
                "members": [candidate_key(item) for item in group],
            }
        )
        for item in group:
            manifest_item = manifest_map.get(str(item.get("url") or ""), {})
            steps.append(step_for(step_number, item, manifest_item, adapter, lead_summary_path))
            step_number += 1

    return {
        "schema": "review-inbox-runtime-plan.v1",
        "adapter_policy": {
            "requested_adapter": "auto" if adapter_decision["auto_adapter"] else adapter,
            "selected_adapter": adapter,
            "general_purpose_subagent_allowed": False,
            "allowed_adapters": ["main_session_sequential", "constrained_code_reviewer"],
            "fallback": "main_session_sequential",
            "fallback_reason": adapter_decision["fallback_reason"],
            "reason": "DP-094 AC1 showed general-purpose Agent envelope dominates per-PR token cost.",
            "auto_adapter": adapter_decision["auto_adapter"],
            "adapter_evidence": adapter_decision["adapter_evidence"],
            "candidate_threshold": adapter_decision["candidate_threshold"],
            "cluster_threshold": adapter_decision["cluster_threshold"],
            "diff_lines_threshold": adapter_decision["diff_lines_threshold"],
            "max_cluster_size": adapter_decision["max_cluster_size"],
            "total_raw_diff_lines": adapter_decision["total_raw_diff_lines"],
            "threshold_hit": adapter_decision["threshold_hit"],
        },
        "summary": {
            "candidate_count": len(indexed),
            "step_count": len(steps),
            "cluster_count": len([cluster for cluster in clusters if cluster["size"] > 1]),
            "sibling_count": len([step for step in steps if step["phase"] == "cluster_sibling"]),
        },
        "clusters": clusters,
        "steps": steps,
    }


def main() -> int:
    args = parse_args()
    try:
        candidates = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"build-review-runtime-plan: invalid JSON input: {exc}", file=sys.stderr)
        return 2
    if not isinstance(candidates, list):
        print("build-review-runtime-plan: input must be a JSON array", file=sys.stderr)
        return 2

    manifest = load_json_array(args.manifest)
    adapter, adapter_decision = select_adapter(
        candidates,
        args.adapter,
        args.auto_adapter,
        args.candidate_threshold,
        args.cluster_threshold,
        args.diff_lines_threshold,
        args.adapter_evidence,
    )
    plan = build_plan(candidates, manifest, adapter, adapter_decision)
    payload = json.dumps(plan, ensure_ascii=False, indent=2)
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(payload + "\n")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
