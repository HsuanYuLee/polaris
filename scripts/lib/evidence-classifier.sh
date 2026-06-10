#!/usr/bin/env bash
# Purpose: DP-294 T4 / AC4+AC5 — shared evidence-disposition classifier.
#          Single source of truth for two evidence exemptions consumed by both
#          the D15 pre-push gate (scripts/gates/gate-evidence.sh) and the closeout
#          consumer (scripts/check-local-extension-completion.sh):
#            (AC4) classify a commit/range as release_bump | metadata_only |
#                  behavioral, so metadata-only / release-bump deltas are exempt
#                  from head_sha-bound verification evidence WITHOUT a manual
#                  POLARIS_SKIP_EVIDENCE bypass; behavioral deltas stay fail-closed.
#            (AC5) validate a non-ticket framework T-task's engineering-owned
#                  completion_gate marker (status=PASS, head_sha-bound, evidence
#                  artifact present) as the evidence source-of-truth, mirroring the
#                  canonical contract in scripts/check-delivery-completion.sh.
# Inputs:  subcommand + flags (see usage()).
# Outputs: classify → one of release_bump|metadata_only|behavioral on stdout, exit 0.
#          marker-pass → marker path on stdout + exit 0 when valid; exit 2 otherwise.
# Exit:    0 ok / 2 contract failure / 64 usage error.
#
# NOTE (canonical contract, AC-NEG1): this file does NOT introduce a second
# classifier for any surface already owned elsewhere. The completion_gate marker
# field contract mirrors scripts/check-delivery-completion.sh exactly; a follow-up
# DP should extract that embedded reader into this lib so there is a single
# reader. Until then the field set asserted here is kept byte-for-byte aligned.

set -euo pipefail

ec_usage() {
  cat >&2 <<'USAGE'
usage:
  evidence-classifier.sh classify --repo <abs> (--range <gitrange> | --head <sha>)
  evidence-classifier.sh marker-pass --repo <abs> --work-item-id <ID> --head-sha <sha>

classify:
  Prints exactly one disposition token (release_bump | metadata_only | behavioral)
  for the changed-file set of the given range/commit. Empty deltas and any
  behavioral file (code / config / hooks / skills / rules) classify as behavioral
  (fail-closed).

marker-pass:
  Exit 0 (and print the marker path) when an engineering-owned completion_gate
  marker exists for {work-item-id}-{head-sha} with status=PASS, matching
  work_item_id, head_sha-bound freshness, and a resolvable evidence artifact.
  Exit 2 otherwise.
USAGE
}

# Behavioral file detector + disposition classifier over a status-annotated
# changed-file list passed via the EC_NAMESTATUS env var ("<status>\t<path>" per
# line, as `git diff --name-status` emits) and a package.json unified diff passed
# via EC_PKGJSON_DIFF. Both are passed by env (not stdin) because the python
# program itself is delivered on stdin via the heredoc; reading data from stdin
# too would collide with the program read. Kept in python for readable
# path/extension/status rules (Decision Priority: readability over shell brevity).
#
# DP-295 AC7: a changeset-driven release bump touches some combination of VERSION,
# CHANGELOG.md, package.json (version-only), and consumed .changeset/*.md files
# (deletions). Those deltas classify as release_bump so head_sha-bound evidence
# stays exempt (belt-and-suspenders with the PR-internal verify-before-bump rule).
# Any non-version package.json edit, any .changeset config/content change, or any
# .changeset/*.md that is added/modified rather than deleted stays fail-closed.
_ec_classify_status() {
  python3 - <<'PY'
import os

BEHAVIORAL_SUFFIXES = (".sh", ".py", ".mjs", ".ts", ".js", ".json", ".yaml", ".yml", ".toml")
BEHAVIORAL_PREFIXES = (
    ".claude/hooks/",
    ".claude/skills/",
    ".claude/rules/",
    ".agents/",
    ".codex/",
    ".github/workflows/",
)
RELEASE_BUMP_FILES = {"VERSION", "CHANGELOG.md"}

# Parse "<status>\t<path>" lines. git quotes paths containing non-ASCII bytes
# (e.g. CJK changeset slugs); strip the surrounding quotes so prefix/suffix tests
# operate on the logical path. Rename status (R###) carries two tab-separated
# paths; classify on the destination path and treat as a modify.
def parse_status(line):
    parts = line.split("\t")
    if len(parts) < 2:
        return None, None
    code = parts[0].strip()
    path = parts[-1].strip()
    if path.startswith('"') and path.endswith('"'):
        path = path[1:-1]
    return code[:1], path

entries = []
for ln in os.environ.get("EC_NAMESTATUS", "").splitlines():
    if not ln.strip():
        continue
    code, path = parse_status(ln)
    if path:
        entries.append((code, path))

# Empty delta: nothing to prove exempt → fail-closed.
if not entries:
    print("behavioral")
    raise SystemExit(0)


def package_json_version_only():
    """True iff the package.json diff changes only the "version" value line."""
    diff = os.environ.get("EC_PKGJSON_DIFF", "")
    if not diff.strip():
        return False
    changed = []
    for ln in diff.splitlines():
        if ln.startswith("+++") or ln.startswith("---"):
            continue
        if ln.startswith("+") or ln.startswith("-"):
            changed.append(ln[1:].strip())
    if not changed:
        return False
    # Every added/removed body line must be a "version": "..." declaration.
    return all(c.lstrip().startswith('"version"') for c in changed)


def is_release_bump_delta(code, path):
    if path in RELEASE_BUMP_FILES:
        return True
    if path == "package.json":
        # Only a pure version bump (modify) qualifies; add/delete of the manifest
        # is not a routine release bump.
        return code == "M" and package_json_version_only()
    if path.startswith(".changeset/") and path.endswith(".md"):
        # Only consumed (deleted) changeset entries count; authoring a changeset
        # (add/modify) is a behavioral PR delta, and .changeset/README.md content
        # is not a consumption.
        base = path[len(".changeset/"):]
        return code == "D" and base != "README.md"
    return False


def is_behavioral(path):
    if path.endswith(BEHAVIORAL_SUFFIXES):
        return True
    for pre in BEHAVIORAL_PREFIXES:
        if path.startswith(pre):
            return True
    return False


# Release-bump deltas (incl. package.json / .changeset that are otherwise
# behavioral-by-suffix) are evaluated first so they are not pre-empted by the
# behavioral-suffix screen.
non_release = [(c, p) for (c, p) in entries if not is_release_bump_delta(c, p)]

if not non_release:
    print("release_bump")
    raise SystemExit(0)

if any(is_behavioral(p) for (_, p) in non_release):
    print("behavioral")
    raise SystemExit(0)

# Remaining files are non-behavioral metadata/docs (e.g. *.md, LICENSE) mixed
# with — or instead of — release-bump deltas. Treat the aggregate as metadata.
print("metadata_only")
PY
}

ec_classify() {
  local repo="" range="" head="" base="" tip=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --range) range="${2:-}"; shift 2 ;;
      --head) head="${2:-}"; shift 2 ;;
      *) echo "ERROR: classify: unknown arg: $1" >&2; ec_usage; return 64 ;;
    esac
  done
  [[ -n "$repo" ]] || { echo "ERROR: classify: --repo required" >&2; return 64; }
  if [[ -z "$range" && -z "$head" ]]; then
    echo "ERROR: classify: one of --range / --head required" >&2
    return 64
  fi

  local namestatus="" pkgdiff=""
  if [[ -n "$range" ]]; then
    namestatus="$(git -C "$repo" diff --name-status "$range" 2>/dev/null || true)"
    pkgdiff="$(git -C "$repo" diff "$range" -- package.json 2>/dev/null || true)"
  elif git -C "$repo" rev-parse -q --verify "${head}^1" >/dev/null 2>&1; then
    # Single commit: diff against its first parent.
    base="${head}^1"; tip="$head"
    namestatus="$(git -C "$repo" diff --name-status "$base" "$tip" 2>/dev/null || true)"
    pkgdiff="$(git -C "$repo" diff "$base" "$tip" -- package.json 2>/dev/null || true)"
  else
    # Root commit has no parent; show its own tree as additions.
    namestatus="$(git -C "$repo" show --name-status --format= "$head" 2>/dev/null || true)"
    pkgdiff="$(git -C "$repo" show --format= "$head" -- package.json 2>/dev/null || true)"
  fi

  EC_NAMESTATUS="$namestatus" EC_PKGJSON_DIFF="$pkgdiff" _ec_classify_status
}

# Validate an engineering-owned completion_gate marker as evidence SoT. Mirrors
# the field contract enforced in scripts/check-delivery-completion.sh
# (check_audit_confirmation_completion): marker_kind=completion_gate, status=PASS,
# work_item_id match, freshness.head_sha bound (full/abbrev either direction),
# and a resolvable evidence artifact (freshness.evidence_artifact|source_artifact).
ec_marker_pass() {
  local repo="" work_item_id="" head_sha=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --work-item-id) work_item_id="${2:-}"; shift 2 ;;
      --head-sha) head_sha="${2:-}"; shift 2 ;;
      *) echo "ERROR: marker-pass: unknown arg: $1" >&2; ec_usage; return 64 ;;
    esac
  done
  [[ -n "$repo" && -n "$work_item_id" && -n "$head_sha" ]] \
    || { echo "ERROR: marker-pass: --repo, --work-item-id, --head-sha required" >&2; return 64; }

  REPO_ROOT="$repo" WORK_ITEM_ID="$work_item_id" HEAD_SHA="$head_sha" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

work_item_id = os.environ["WORK_ITEM_ID"]
head_sha = os.environ["HEAD_SHA"]
repo_root = os.environ["REPO_ROOT"]

# Markers anchor at the main checkout; resolve it when REPO_ROOT is a worktree
# (same traversal as check-delivery-completion.sh completion_gate_marker_path).
roots = [Path(repo_root)]
git_file = Path(repo_root) / ".git"
if git_file.is_file():
    text = git_file.read_text(encoding="utf-8", errors="ignore").strip()
    if text.startswith("gitdir:"):
        git_dir = (git_file.parent / text.split(":", 1)[1].strip()).resolve()
        common = git_dir.parent.parent
        if common.name == ".git":
            roots.append(common.parent)

marker = None
for root in roots:
    marker_dir = root / ".polaris" / "evidence" / "completion-gate"
    for path in sorted(marker_dir.glob(f"{work_item_id}-*.json")):
        suffix = path.name[len(work_item_id) + 1:-len(".json")]
        if suffix == head_sha or head_sha.startswith(suffix) or suffix.startswith(head_sha):
            marker = path
            break
    if marker:
        break

if marker is None:
    sys.stderr.write(f"no completion_gate marker for {work_item_id}@{head_sha}\n")
    raise SystemExit(2)

try:
    data = json.loads(marker.read_text(encoding="utf-8"))
except Exception as exc:
    sys.stderr.write(f"invalid completion_gate marker JSON: {exc}\n")
    raise SystemExit(2)

if data.get("marker_kind") != "completion_gate":
    sys.stderr.write("marker_kind != completion_gate\n"); raise SystemExit(2)
if data.get("status") != "PASS":
    sys.stderr.write("status != PASS\n"); raise SystemExit(2)
if data.get("work_item_id") != work_item_id:
    sys.stderr.write("work_item_id mismatch\n"); raise SystemExit(2)

freshness = data.get("freshness") or {}
marker_head = str(freshness.get("head_sha") or "")
if not (marker_head == head_sha or head_sha.startswith(marker_head) or marker_head.startswith(head_sha)):
    sys.stderr.write("freshness.head_sha mismatch\n"); raise SystemExit(2)

evidence = freshness.get("evidence_artifact") or freshness.get("source_artifact")
if not evidence or not Path(evidence).is_file():
    sys.stderr.write(f"evidence artifact missing: {evidence}\n"); raise SystemExit(2)

print(str(marker))
raise SystemExit(0)
PY
}

# CLI dispatch (only when executed directly, so the file can also be sourced).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sub="${1:-}"
  [[ -n "$sub" ]] || { ec_usage; exit 64; }
  shift
  case "$sub" in
    classify) ec_classify "$@" ;;
    marker-pass) ec_marker_pass "$@" ;;
    -h|--help) ec_usage; exit 0 ;;
    *) echo "ERROR: unknown subcommand: $sub" >&2; ec_usage; exit 64 ;;
  esac
fi
