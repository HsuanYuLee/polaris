"""Structured validator authority extracted from scripts/validate-skill-flow-transition-registry.sh."""

import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
registry_path = Path(sys.argv[2])
source_closeout = sys.argv[3] == "1"
errors = []

allowed_source_kinds = {
    "artifact",
    "api_response",
    "command_exit",
    "file_state",
    "git_state",
    "lifecycle_state",
    "structured_payload",
}
required_exclusions = {
    "research",
    "exploration",
    "design",
    "code_generation",
    "prose_generation",
    "intent_clarification",
    "business_judgment",
}
observation_groups = ("inputs", "outputs", "preconditions", "postconditions")
path_fields = ("producer", "consumer", "validator", "blocking_invoke_point")

try:
    data = json.loads(registry_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID:{exc}", file=sys.stderr)
    raise SystemExit(2)

if not isinstance(data, dict):
    print(
        "POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID:registry root 必須是 object",
        file=sys.stderr,
    )
    raise SystemExit(2)

manifest_path = root / "scripts/manifest.json"
try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(
        f"POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID:無法讀取 script manifest：{exc}",
        file=sys.stderr,
    )
    raise SystemExit(2)
manifest_rows = manifest.get("scripts") if isinstance(manifest, dict) else None
if not isinstance(manifest_rows, list):
    print(
        "POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID:script manifest scripts 必須是 array",
        file=sys.stderr,
    )
    raise SystemExit(2)

aggregate_runner = root / "scripts/run-aggregate-selftests.sh"
aggregate_result = subprocess.run(
    ["bash", str(aggregate_runner), "--root", str(root), "--list"],
    check=False,
    capture_output=True,
    text=True,
)
if aggregate_result.returncode != 0:
    detail = aggregate_result.stderr.strip() or f"exit={aggregate_result.returncode}"
    print(
        f"POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID:無法解析 aggregate enrollment：{detail}",
        file=sys.stderr,
    )
    raise SystemExit(2)
enrolled_selftests = {
    line.strip() for line in aggregate_result.stdout.splitlines() if line.strip()
}

if data.get("schema_version") != 1:
    errors.append("schema_version 必須是 1")
if data.get("authority") != "scripts/lib/skill-flow-transition-registry.json":
    errors.append("authority 必須指向 canonical registry")
exclusions = data.get("llm_owned_exclusions")
if (
    not isinstance(exclusions, list)
    or any(not isinstance(value, str) for value in exclusions)
    or set(exclusions) != required_exclusions
):
    errors.append("llm_owned_exclusions 必須完全符合 canonical LLM-owned boundary")

transitions = data.get("transitions")
if not isinstance(transitions, list) or not transitions:
    errors.append("transitions 必須是非空 array")
    transitions = []

seen_ids = set()
callable_owners = {}
required_transition_ids = {
    "skill_flow_transition_registry.resolve",
    "engineering.self_review_outcome",
    "engineering.no_pr_delivery",
    "review_pr.external_write_submission",
    "engineering.artifact_location_resolution",
    "engineering.declared_verification_orchestration",
    "cli.safe_introspection",
}
for index, transition in enumerate(transitions):
    prefix = f"transitions[{index}]"
    if not isinstance(transition, dict):
        errors.append(f"{prefix} 必須是 object")
        continue
    transition_id = transition.get("id")
    if not isinstance(transition_id, str) or not re.fullmatch(
        r"[a-z0-9_]+(?:\.[a-z0-9_]+)+", transition_id
    ):
        errors.append(f"{prefix}.id 必須是穩定的 dotted identifier")
    elif transition_id in seen_ids:
        errors.append(f"transition id 重複：{transition_id}")
    else:
        seen_ids.add(transition_id)

    for group in observation_groups:
        observations = transition.get(group)
        if not isinstance(observations, list) or not observations:
            errors.append(f"{prefix}.{group} 必須是非空 array")
            continue
        for observation_index, observation in enumerate(observations):
            observation_prefix = f"{prefix}.{group}[{observation_index}]"
            if not isinstance(observation, dict):
                errors.append(f"{observation_prefix} 必須是 object")
                continue
            for field in ("name", "source", "predicate"):
                if (
                    not isinstance(observation.get(field), str)
                    or not observation[field].strip()
                ):
                    errors.append(f"{observation_prefix}.{field} 不得為空")
            source_kind = observation.get("source_kind")
            if source_kind not in allowed_source_kinds:
                errors.append(
                    f"{observation_prefix}.source_kind 無法機械觀測：{source_kind}"
                )
            if observation.get("observable") is not True:
                errors.append(f"{observation_prefix}.observable 必須是 true")
            if observation.get("mechanically_decidable") is not True:
                errors.append(
                    f"{observation_prefix}.mechanically_decidable 必須是 true"
                )

    callable_interface = transition.get("callable_interface")
    if not isinstance(callable_interface, dict):
        errors.append(f"{prefix}.callable_interface 必須是 object")
        callable_interface = {}
    for field in ("path", "protocol", "selector", "output"):
        if (
            not isinstance(callable_interface.get(field), str)
            or not callable_interface[field].strip()
        ):
            errors.append(f"{prefix}.callable_interface.{field} 不得為空")
    if callable_interface.get("protocol") != "cli":
        errors.append(f"{prefix}.callable_interface.protocol 必須是 cli")

    paths = [(field, transition.get(field)) for field in path_fields]
    paths.append(("callable_interface.path", callable_interface.get("path")))
    resolved_paths = {}
    for field, value in paths:
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{prefix}.{field} 必須指定一個 repo-relative path")
            continue
        candidate = (root / value).resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            errors.append(f"{prefix}.{field} 超出 workspace root：{value}")
            continue
        if not candidate.is_file():
            errors.append(f"{prefix}.{field} path 不存在：{value}")
        else:
            resolved_paths[field] = candidate

    callable_path = callable_interface.get("path")
    if callable_path != transition.get("producer"):
        errors.append(f"{prefix}.producer 必須等於 callable_interface.path")

    producer_value = transition.get("producer")
    validator_value = transition.get("validator")
    consumer_value = transition.get("consumer")
    blocking_value = transition.get("blocking_invoke_point")

    if isinstance(producer_value, str) and producer_value:
        prior_owner = callable_owners.get(producer_value)
        if prior_owner is not None and prior_owner != transition_id:
            errors.append(
                "POLARIS_SKILL_FLOW_TRANSITION_OWNER_COLLISION:"
                f"callable owner {producer_value} 同時屬於 {prior_owner} 與 {transition_id}"
            )
        else:
            callable_owners[producer_value] = transition_id

    if source_closeout:
        transition_is_required = (
            isinstance(transition_id, str) and transition_id in required_transition_ids
        )
        if transition_is_required and transition.get("owner_source") != "DP-422":
            errors.append(
                "POLARIS_SKILL_FLOW_TRANSITION_OWNER_COLLISION:"
                f"{transition_id} owner_source 必須唯一歸屬 DP-422"
            )
        forbidden_source_fields = sorted(
            field
            for field in ("source_type", "dp_only", "jira_only")
            if field in transition
        )
        if forbidden_source_fields:
            errors.append(
                "POLARIS_SKILL_FLOW_TRANSITION_SOURCE_TYPE_FAST_PATH:"
                f"{transition_id} 不得宣告 {forbidden_source_fields}"
            )
        source_types = transition.get("source_types")
        if "source_types" in transition and (
            not isinstance(source_types, list)
            or any(not isinstance(value, str) for value in source_types)
            or not {"dp", "jira"}.issubset(set(source_types))
        ):
            errors.append(
                "POLARIS_SKILL_FLOW_TRANSITION_SOURCE_TYPE_FAST_PATH:"
                f"{transition_id} source_types additional contract 必須至少對稱包含 dp 與 jira"
            )

    # Callsite authority 是 manifest 的 exact-path selftest enrollment；不掃描 script 或 prose 內容。
    for role, owned_path in (
        ("producer", producer_value),
        ("validator", validator_value),
    ):
        if not isinstance(owned_path, str):
            continue
        matches = [
            row
            for row in manifest_rows
            if isinstance(row, dict) and row.get("path") == owned_path
        ]
        if len(matches) != 1:
            errors.append(
                f"{prefix}.{role} 在 script manifest 必須恰有一筆 exact-path enrollment"
            )
            continue
        if matches[0].get("selftest") != consumer_value:
            errors.append(f"{prefix}.{role} 的 manifest selftest 必須等於 consumer")

    if not isinstance(consumer_value, str) or consumer_value not in enrolled_selftests:
        errors.append(
            f"{prefix}.consumer 必須存在於 aggregate runner canonical --list 集合"
        )
    if blocking_value != consumer_value:
        errors.append(
            f"{prefix}.blocking_invoke_point 必須等於已 enrollment 的 consumer selftest"
        )

if source_closeout:
    missing = sorted(required_transition_ids - seen_ids)
    if missing:
        errors.append(
            "POLARIS_SKILL_FLOW_TRANSITION_COVERAGE_GAP:"
            f"DP-422 source-closeout transition missing={missing}"
        )

if errors:
    for error in errors:
        print(
            f"POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID:{error}", file=sys.stderr
        )
    raise SystemExit(2)
profile = " + DP-422 source closeout" if source_closeout else ""
print(
    f"PASS: skill-flow transition registry ({len(transitions)} transition(s){profile})"
)
