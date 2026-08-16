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
        default="constrained_code_reviewer",
        help="Runtime adapter contract for the plan. The reviewer envelope is the default.",
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
    """一張 PR 的 raw diff 行數，供 plan 的 summary 使用（不再參與 adapter 選擇）。"""
    for key in ("raw_diff_lines", "diff_lines", "changed_lines"):
        value = safe_int(candidate.get(key), 0)
        if value > 0:
            return value
    return safe_int(candidate.get("additions"), 0) + safe_int(candidate.get("deletions"), 0)


def select_adapter(requested_adapter: str) -> tuple[str, dict[str, Any]]:
    """決定 plan 要求哪一個 adapter，並說出為什麼不是 reviewer envelope。

    以前這裡還有兩層閘：一份 T7 dual-run 證據，以及 candidate count / cluster size /
    raw diff 行數三個門檻。兩層都是為了省 token 而設的，而它們擋掉的正好是 review 真正
    有價值的那一段——把接線追到消費端、對照姊妹 repo、讀未改動的區域。那份 T7 證據屬
    DP-113 的舊層、早就不存在，所以那道閘實際上是一個永遠傳 missing 的旗標。

    現在只剩一個問題：呼叫端指名了什麼。執行期沒有 reviewer adapter 時的降級由
    orchestrator 做，而它必須把降級說出來——一個安靜的降級下一次就會被當成沒有降級。
    """
    if requested_adapter == "constrained_code_reviewer":
        return requested_adapter, {"fallback_reason": ""}
    return requested_adapter, {
        "fallback_reason": (
            "呼叫端以 --adapter main_session_sequential 指名主 session 執行；"
            "reviewer envelope 讀 diff 以外檔案的範圍在主 session 不適用。"
        )
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
            "requested_adapter": adapter,
            "selected_adapter": adapter,
            "general_purpose_subagent_allowed": False,
            "allowed_adapters": ["main_session_sequential", "constrained_code_reviewer"],
            "fallback": "main_session_sequential",
            "fallback_reason": adapter_decision["fallback_reason"],
            "reason": "DP-094 AC1 showed general-purpose Agent envelope dominates per-PR token cost.",
            "total_raw_diff_lines": sum(raw_diff_lines(item) for item in indexed),
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
    adapter, adapter_decision = select_adapter(args.adapter)
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
