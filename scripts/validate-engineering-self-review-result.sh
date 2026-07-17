#!/usr/bin/env bash
# Validate the head-and-worktree-bound Critic outcome used by engineering Phase 3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/tool-resolution.sh
source "$ROOT/scripts/lib/tool-resolution.sh"
PYTHON_BIN="$(polaris_require_python)"

"$PYTHON_BIN" - "$@" <<'PY'
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


def current_state(repo_raw):
    repo = Path(repo_raw).resolve()
    if not (repo / ".git").exists():
        raise ValueError(f"repo is not a git worktree: {repo}")
    head = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "HEAD"], text=True
    ).strip()
    diff = subprocess.check_output(
        ["git", "-C", str(repo), "diff", "--binary", "--no-ext-diff", "HEAD", "--"]
    )
    untracked_raw = subprocess.check_output(
        ["git", "-C", str(repo), "ls-files", "--others", "--exclude-standard", "-z"]
    )
    untracked = sorted(item for item in untracked_raw.split(b"\0") if item)
    digest = hashlib.sha256()
    digest.update(b"head\0" + head.encode("ascii") + b"\0")
    digest.update(b"diff\0" + diff + b"\0")
    for raw in untracked:
        rel = os.fsdecode(raw)
        path = repo / rel
        digest.update(b"untracked\0" + raw + b"\0")
        if path.is_symlink():
            digest.update(b"symlink\0" + os.readlink(path).encode("utf-8") + b"\0")
        elif path.is_file():
            digest.update(b"file\0" + path.read_bytes() + b"\0")
        else:
            digest.update(b"other\0")
    return {
        "reviewed_head_sha": head,
        "reviewed_state_sha256": "sha256:" + digest.hexdigest(),
    }


def load_json(path, errors, label):
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{label} is not readable JSON: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{label} must be a JSON object")
        return {}
    return value


def expected_action(verdict, review_round):
    if verdict == "PASS":
        return "proceed"
    return "human_review" if review_round == 4 else "remediate"


def validate_finding(item, errors, label):
    if not isinstance(item, dict):
        errors.append(f"{label} must be an object")
        return
    file_path = item.get("file")
    if not isinstance(file_path, str) or not file_path.strip():
        errors.append(f"{label}.file must be a non-empty repo-relative path")
    else:
        normalized = PurePosixPath(file_path)
        if normalized.is_absolute() or ".." in normalized.parts:
            errors.append(f"{label}.file must be a repo-relative path without '..'")
    line = item.get("line")
    if type(line) is not int or line < 1:
        errors.append(f"{label}.line must be a positive integer")
    for field in ("rule", "message"):
        value = item.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{label}.{field} must be a non-empty string")


def canonical_evidence_dir(repo_raw):
    repo = Path(repo_raw).resolve()
    common_raw = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "--git-common-dir"], text=True
    ).strip()
    common_dir = Path(common_raw)
    if not common_dir.is_absolute():
        common_dir = (repo / common_dir).resolve()
    return common_dir.parent / ".polaris" / "evidence" / "engineering-self-review"


def file_sha256(path):
    return "sha256:" + hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate_canonical_result_path(path, data, evidence_dir, errors, label):
    raw = Path(path)
    if raw.is_symlink():
        errors.append(f"{label} must not be a symlink")
        return
    resolved = raw.resolve()
    if resolved.parent != evidence_dir.resolve():
        errors.append(f"{label} must live in canonical engineering-self-review evidence dir")
    expected = (
        f"{data.get('work_item_id')}-r{data.get('review_round')}-"
        f"{data.get('reviewed_head_sha')}.json"
    )
    if resolved.name != expected:
        errors.append(f"{label} filename must equal {expected}")


def validate_transition(current, prior, errors, label="prior"):
    if prior.get("work_item_id") != current.get("work_item_id"):
        errors.append(f"{label}.work_item_id must equal current work_item_id")
    if prior.get("review_round") != current.get("review_round", 0) - 1:
        errors.append(f"{label}.review_round must be current round - 1")
    if prior.get("remediation_count") != current.get("remediation_count", -1) - 1:
        errors.append(f"{label}.remediation_count must be current count - 1")
    if prior.get("verdict") != "FAIL" or prior.get("next_action") != "remediate":
        errors.append(f"{label} must be a remediable FAIL")
    if (
        prior.get("reviewed_head_sha") == current.get("reviewed_head_sha")
        and prior.get("reviewed_state_sha256") == current.get("reviewed_state_sha256")
    ):
        errors.append("current review must follow a changed head or worktree state")


def validate_shape(data, errors, label="result"):
    required_exact = {
        "schema_version": 1,
        "marker_kind": "engineering_self_review",
        "writer": "write-engineering-self-review-result.sh",
        "owning_skill": "engineering",
        "reviewer": "critic",
    }
    for field, expected in required_exact.items():
        if data.get(field) != expected:
            errors.append(f"{label}.{field} must equal {expected!r}")

    work_item = data.get("work_item_id")
    if not isinstance(work_item, str) or not re.fullmatch(
        r"[A-Z][A-Z0-9]*-[0-9]+-[TV][0-9]+[a-z]*", work_item
    ):
        errors.append(f"{label}.work_item_id is invalid")

    head = data.get("reviewed_head_sha")
    if not isinstance(head, str) or not re.fullmatch(r"[0-9a-f]{40}", head):
        errors.append(f"{label}.reviewed_head_sha must be a full git SHA")
    state = data.get("reviewed_state_sha256")
    if not isinstance(state, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", state):
        errors.append(f"{label}.reviewed_state_sha256 must be sha256:<64 hex>")

    review_round = data.get("review_round")
    remediation = data.get("remediation_count")
    if type(review_round) is not int or not 1 <= review_round <= 4:
        errors.append(f"{label}.review_round must be an integer from 1 to 4")
    if type(remediation) is not int or not 0 <= remediation <= 3:
        errors.append(f"{label}.remediation_count must be an integer from 0 to 3")
    if type(review_round) is int and type(remediation) is int:
        if remediation != review_round - 1:
            errors.append(f"{label}.remediation_count must equal review_round - 1")

    terminal = data.get("terminal_review")
    if type(terminal) is not bool:
        errors.append(f"{label}.terminal_review must be boolean")
    elif type(review_round) is int and terminal != (review_round == 4):
        errors.append(f"{label}.terminal_review must be true only for round 4")

    verdict = data.get("verdict")
    if verdict not in {"PASS", "FAIL"}:
        errors.append(f"{label}.verdict must be PASS or FAIL")
    for field in ("blocking", "non_blocking"):
        findings = data.get(field)
        if not isinstance(findings, list):
            errors.append(f"{label}.{field} must be an array")
        else:
            for index, item in enumerate(findings):
                validate_finding(item, errors, f"{label}.{field}[{index}]")
    blocking = data.get("blocking")
    if verdict == "PASS" and blocking:
        errors.append(f"{label}.PASS verdict must have empty blocking")
    if verdict == "FAIL" and isinstance(blocking, list) and not blocking:
        errors.append(f"{label}.FAIL verdict must have at least one blocking item")
    if not isinstance(data.get("summary"), str) or not data.get("summary", "").strip():
        errors.append(f"{label}.summary must be a non-empty string")

    critic_digest = data.get("critic_result_sha256")
    if not isinstance(critic_digest, str) or not re.fullmatch(
        r"sha256:[0-9a-f]{64}", critic_digest
    ):
        errors.append(f"{label}.critic_result_sha256 must be sha256:<64 hex>")

    if type(review_round) is int and verdict in {"PASS", "FAIL"}:
        expected = expected_action(verdict, review_round)
        if data.get("next_action") != expected:
            errors.append(f"{label}.next_action must equal {expected}")

    reviewed_at = data.get("reviewed_at")
    if reviewed_at is None:
        errors.append(f"{label}.reviewed_at is required")
    else:
        try:
            dt.datetime.fromisoformat(str(reviewed_at).replace("Z", "+00:00"))
        except ValueError:
            errors.append(f"{label}.reviewed_at must be ISO8601")

    prior_file = data.get("prior_result_file")
    prior_digest = data.get("prior_result_sha256")
    if review_round == 1:
        if prior_file is not None or prior_digest is not None:
            errors.append(f"{label} round 1 must not link a prior result")
    elif type(review_round) is int and 2 <= review_round <= 4:
        if not isinstance(prior_file, str) or not re.fullmatch(
            r"[A-Z][A-Z0-9]*-[0-9]+-[TV][0-9]+[a-z]*-r[1-3]-[0-9a-f]{40}\.json",
            prior_file or "",
        ):
            errors.append(f"{label}.prior_result_file must be a canonical result basename")
        if not isinstance(prior_digest, str) or not re.fullmatch(
            r"sha256:[0-9a-f]{64}", prior_digest or ""
        ):
            errors.append(f"{label}.prior_result_sha256 must be sha256:<64 hex>")


def validate_history(path, evidence_dir, errors, seen=None):
    seen = set() if seen is None else seen
    resolved = Path(path).resolve()
    if resolved in seen:
        errors.append("prior chain must not contain a cycle")
        return {}
    seen.add(resolved)
    data = load_json(resolved, errors, f"history[{resolved.name}]")
    validate_shape(data, errors, f"history[{resolved.name}]")
    validate_canonical_result_path(
        resolved, data, evidence_dir, errors, f"history[{resolved.name}]"
    )
    review_round = data.get("review_round")
    if type(review_round) is int and review_round > 1:
        prior_file = data.get("prior_result_file")
        if isinstance(prior_file, str):
            prior_path = evidence_dir / prior_file
            if not prior_path.is_file():
                errors.append(f"history prior result does not exist: {prior_file}")
            else:
                expected_digest = data.get("prior_result_sha256")
                if file_sha256(prior_path) != expected_digest:
                    errors.append(f"history prior digest mismatch: {prior_file}")
                prior = validate_history(prior_path, evidence_dir, errors, seen)
                if prior:
                    validate_transition(data, prior, errors, f"history[{prior_file}]")
    return data


parser = argparse.ArgumentParser(allow_abbrev=False)
parser.add_argument("result", nargs="?")
parser.add_argument("--repo")
parser.add_argument("--prior")
parser.add_argument("--print-current-state", action="store_true")
parser.add_argument("--validate-history", action="store_true")
args = parser.parse_args()

if args.print_current_state:
    if not args.repo:
        parser.error("--print-current-state requires --repo")
    try:
        print(json.dumps(current_state(args.repo), sort_keys=True))
    except Exception as exc:
        print(f"POLARIS_ENGINEERING_SELF_REVIEW_STATE_UNAVAILABLE:{exc}", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(0)

if not args.result:
    parser.error("result path is required")
if not args.repo:
    parser.error("result validation requires --repo")

try:
    result_evidence_dir = canonical_evidence_dir(args.repo)
except Exception as exc:
    print(f"POLARIS_ENGINEERING_SELF_REVIEW_STATE_UNAVAILABLE:{exc}", file=sys.stderr)
    raise SystemExit(2)

if args.validate_history:
    history_errors = []
    validate_history(args.result, result_evidence_dir, history_errors)
    if history_errors:
        print("FAIL: engineering self-review history", file=sys.stderr)
        for error in history_errors:
            print(f"  - {error}", file=sys.stderr)
        raise SystemExit(1)
    print(f"PASS: engineering self-review history ({args.result})")
    raise SystemExit(0)

errors = []
data = load_json(args.result, errors, "result")
validate_shape(data, errors)
validate_canonical_result_path(
    args.result, data, result_evidence_dir, errors, "result"
)

review_round = data.get("review_round")
if review_round == 1 and args.prior:
    errors.append("round 1 must not provide --prior")
if type(review_round) is int and review_round > 1:
    if not args.prior:
        errors.append("round > 1 requires --prior")
    else:
        evidence_dir = result_evidence_dir
        prior_errors = []
        prior = load_json(args.prior, prior_errors, "prior")
        validate_canonical_result_path(
            args.prior, prior, evidence_dir, prior_errors, "prior"
        )
        if Path(args.prior).is_file():
            chained_prior = validate_history(args.prior, evidence_dir, prior_errors)
            if chained_prior:
                prior = chained_prior
        if data.get("prior_result_file") != Path(args.prior).resolve().name:
            prior_errors.append("result.prior_result_file must name --prior")
        if Path(args.prior).is_file() and data.get("prior_result_sha256") != file_sha256(
            args.prior
        ):
            prior_errors.append("result.prior_result_sha256 must match --prior bytes")
        validate_transition(data, prior, prior_errors)
        errors.extend(prior_errors)

if args.repo and data:
    try:
        current = current_state(args.repo)
    except Exception as exc:
        errors.append(f"current repo state unavailable: {exc}")
    else:
        if (
            data.get("reviewed_head_sha") != current["reviewed_head_sha"]
            or data.get("reviewed_state_sha256") != current["reviewed_state_sha256"]
        ):
            print(
                "POLARIS_ENGINEERING_SELF_REVIEW_STALE:"
                f"recorded_head={data.get('reviewed_head_sha')}:"
                f"current_head={current['reviewed_head_sha']}",
                file=sys.stderr,
            )
            errors.append("review outcome does not match current HEAD/worktree state")

if errors:
    print("FAIL: engineering self-review result", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"PASS: engineering self-review result ({args.result})")
PY
