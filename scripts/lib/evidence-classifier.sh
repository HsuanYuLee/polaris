#!/usr/bin/env bash
# Purpose: DP-294 T4 / AC4+AC5 — shared evidence-disposition classifier.
#          Single source of truth for two evidence exemptions consumed by both
#          the D15 pre-push gate (scripts/gates/gate-evidence.sh) and the closeout
#          consumer (scripts/check-local-extension-completion.sh):
#            (AC4) classify a commit/range as release_bump | metadata_only |
#                  behavioral, so metadata-only / release-bump deltas are exempt
#                  from head_sha-bound verification evidence WITHOUT a manual
#                  POLARIS_SKIP_EVIDENCE bypass; behavioral deltas stay fail-closed.
#            (AC5) validate a non-ticket framework T-task's delivery evidence —
#                  the task.md `deliverable` block (head_sha-bound +
#                  verification.status=PASS) — as the evidence source-of-truth
#                  (DP-360 T7: the head-sha completion_gate marker is retired),
#                  mirroring scripts/check-delivery-completion.sh.
# Inputs:  subcommand + flags (see usage()).
# Outputs: classify → one of release_bump|metadata_only|behavioral on stdout, exit 0.
#          marker-pass → resolved task.md path on stdout + exit 0 when valid;
#                        exit 2 otherwise.
# Exit:    0 ok / 2 contract failure / 64 usage error.
#
# NOTE (canonical contract, AC-NEG1/AC-NEG2): this file does NOT introduce a
# second classifier for any surface already owned elsewhere. DP-360 T7 retires the
# completion_gate head-sha marker; the delivery-head + PASS authority is now the
# task.md `deliverable` block read through scripts/parse-task-md.sh. This reader
# never falls back to a branch ref (AC-NEG1) and never reads a marker file
# (AC-NEG2). The field contract stays aligned with
# scripts/check-delivery-completion.sh.

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
  Exit 0 (and print the resolved task.md path) when the task.md for {work-item-id}
  carries a deliverable block whose head_sha is bound to {head-sha} and whose
  verification.status is PASS (DP-360 T7: reads task.md, not a marker file; never
  falls back to a branch ref). Exit 2 otherwise.
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

# Validate a framework T-task's delivery evidence as SoT. DP-360 T7 teardown:
# the head-sha-keyed completion_gate marker is retired; the durable evidence
# record is now the task.md `deliverable` block (D1/D2/D4). This reader resolves
# the task.md by work_item_id through the canonical resolve-task-md.sh and asserts
# the same head-bound PASS contract the marker used to carry:
#   - deliverable.head_sha is bound to the requested head (full/abbrev either way)
#   - deliverable.verification.status == PASS
# It NEVER falls back to a branch ref (AC-NEG1) and NEVER reads a marker file
# (AC-NEG2). On success it prints the resolved task.md path; exit 2 otherwise.
# Mirrors the field contract in scripts/check-delivery-completion.sh
# (check_audit_confirmation_completion) which also now reads the task.md block.
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

  local ec_lib_dir
  ec_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$repo" WORK_ITEM_ID="$work_item_id" HEAD_SHA="$head_sha" \
    RESOLVER="$ec_lib_dir/../resolve-task-md.sh" \
    PARSER="$ec_lib_dir/../parse-task-md.sh" python3 - <<'PY'
import os
import subprocess
import sys
from pathlib import Path

work_item_id = os.environ["WORK_ITEM_ID"]
head_sha = os.environ["HEAD_SHA"]
repo_root = os.environ["REPO_ROOT"]
resolver = os.environ["RESOLVER"]
parser = os.environ["PARSER"]


def resolve_task_md(work_item_id):
    """Resolve the canonical task.md path for work_item_id (active or archived).

    Uses scripts/resolve-task-md.sh — the single canonical resolver — so a task.md
    that moved to pr-release/ or container archive after delivery still resolves.
    Returns the path string or None.
    """
    try:
        out = subprocess.run(
            ["bash", resolver, "--scan-root", repo_root, "--include-archive", work_item_id],
            capture_output=True, text=True, timeout=30,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    lines = out.stdout.strip().splitlines()
    if not lines:
        return None
    candidate = Path(lines[-1].strip())
    return str(candidate) if candidate.is_file() else None


def field(task_md, key):
    """Read one parse-task-md.sh --field value (stripped) or empty string."""
    try:
        out = subprocess.run(
            ["bash", parser, task_md, "--no-resolve", "--field", key],
            capture_output=True, text=True, timeout=30,
        )
    except Exception:
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def head_bound(recorded, requested):
    """True when recorded delivery head matches the requested head (full/abbrev)."""
    if not recorded:
        return False
    return (
        recorded == requested
        or requested.startswith(recorded)
        or recorded.startswith(requested)
    )


task_md = resolve_task_md(work_item_id)
if task_md is None:
    sys.stderr.write(f"no task.md resolvable for {work_item_id}\n")
    raise SystemExit(2)

recorded_head = field(task_md, "deliverable_head_sha")
if not head_bound(recorded_head, head_sha):
    sys.stderr.write(
        f"deliverable.head_sha mismatch: recorded={recorded_head!r} requested={head_sha!r}\n"
    )
    raise SystemExit(2)

status = field(task_md, "deliverable_verification_status")
if status != "PASS":
    sys.stderr.write(f"deliverable.verification.status != PASS (got {status!r})\n")
    raise SystemExit(2)

print(task_md)
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
