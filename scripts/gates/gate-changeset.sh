#!/usr/bin/env bash
set -euo pipefail

# gate-changeset.sh — Single repo-native changeset verifier.
# In --staged mode it validates the prospective commit tree (HEAD + index) at
# pre-commit time. The default delivery mode retains the task/release defense in
# depth used by pre-push, completion, and PR creation.
#
# Usage:
#   bash scripts/gates/gate-changeset.sh [--repo <path>] [--staged]
#   bash scripts/gates/gate-changeset.sh [--repo <path>] [--task-md <path>]
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_CHANGESET_GATE=1

PREFIX="[polaris gate-changeset]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_SCRIPTS="${SCRIPT_DIR}/.."
RESOLVE_BY_BRANCH="${WORKSPACE_SCRIPTS}/resolve-task-md-by-branch.sh"
POLARIS_CHANGESET="${WORKSPACE_SCRIPTS}/polaris-changeset.sh"
LANG_POLICY="${WORKSPACE_SCRIPTS}/validate-language-policy.sh"

REPO_ROOT=""
TASK_MD=""
STAGED_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --staged) STAGED_MODE=1; shift ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-changeset.sh [--repo <path>] [--task-md <path>] [--staged]"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ "${POLARIS_SKIP_CHANGESET_GATE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_CHANGESET_GATE=1 — bypassing." >&2
  exit 0
fi

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

# Repos without changesets do not participate. In staged mode the index is the
# sole prospective-tree authority; an unstaged config must not enable/disable or
# otherwise influence the pre-commit verdict.
if [[ "$STAGED_MODE" -eq 1 ]]; then
  git -C "$REPO_ROOT" cat-file -e ':.changeset/config.json' 2>/dev/null || exit 0
elif [[ ! -f "$REPO_ROOT/.changeset/config.json" ]]; then
  exit 0
fi

# staged_disposition prints behavioral or metadata_only for the staged delta.
# This classifier is intentionally local to the single changeset verifier: the
# evidence classifier owns committed ranges, while pre-commit must inspect the
# index without manufacturing a commit object.
staged_disposition() {
  local changed
  changed="$(git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMRD 2>/dev/null || true)"
  STAGED_CHANGED="$changed" python3 - <<'PY'
import os

paths = [p.strip() for p in os.environ.get("STAGED_CHANGED", "").splitlines() if p.strip()]
behavioral_suffixes = (".sh", ".py", ".mjs", ".ts", ".js", ".json", ".yaml", ".yml", ".toml")
behavioral_prefixes = (
    ".claude/hooks/", ".claude/skills/", ".claude/rules/", ".codex/",
    ".github/workflows/", "polaris-config/",
)
behavioral_files = {"AGENTS.md", "CLAUDE.md"}

def behavioral(path):
    if path.startswith(".changeset/") and path.endswith(".md"):
        return False
    return path in behavioral_files or path.endswith(behavioral_suffixes) or path.startswith(behavioral_prefixes)

print("behavioral" if any(behavioral(p) for p in paths) else "metadata_only")
PY
}

# prospective_changeset_paths lists canonical candidates from the index. Git's
# index already represents HEAD plus staged additions/deletions, so an unstaged
# worktree file is invisible while a changeset committed earlier remains visible.
prospective_changeset_paths() {
  git -C "$REPO_ROOT" ls-files --cached -- '.changeset/*.md' 2>/dev/null \
    | grep -Ev '^\.changeset/README\.md$' || true
}

# A managed task branch must be satisfied by its own task-identity changeset,
# not an inherited sibling changeset from a stacked base. Subsequent commits in
# the same task still pass because that task-owned file remains in HEAD.
active_task_identity() {
  local branch
  branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  ACTIVE_BRANCH="$branch" python3 - <<'PY'
import os, re
branch = os.environ.get("ACTIVE_BRANCH", "")
m = re.match(r"^task/((?:DP-\d+-T\d+)|(?:[A-Z][A-Z0-9]*-\d+))-", branch)
if m:
    print(m.group(1).lower())
PY
}

prospective_changeset_is_canonical() {
  local path="$1" body
  body="$(git -C "$REPO_ROOT" show ":$path" 2>/dev/null || true)"
  CHANGESET_BODY="$body" python3 - "$REPO_ROOT" <<'PY'
import fnmatch, json, os, re, subprocess, sys

repo = sys.argv[1]
text = os.environ.get("CHANGESET_BODY", "")
lines = text.splitlines()
if len(lines) < 5 or lines[0].strip() != "---":
    raise SystemExit(1)
try:
    end = next(i for i, line in enumerate(lines[1:], 1) if line.strip() == "---")
except StopIteration:
    raise SystemExit(1)
entries = [line.strip() for line in lines[1:end] if line.strip()]
parsed = []
for line in entries:
    match = re.fullmatch(r'["\']([^"\']+)["\']\s*:\s*(patch|minor|major)', line)
    if not match:
        raise SystemExit(1)
    parsed.append(match.group(1))
if not parsed:
    raise SystemExit(1)
if not any(line.strip() for line in lines[end + 1:]):
    raise SystemExit(1)

# Validate package scopes against prospective repo metadata from the Git index.
# No Path.read_text/worktree probe is allowed in this staged verifier.
known = set()

def index_text(path):
    proc = subprocess.run(
        ["git", "-C", repo, "show", f":{path}"],
        capture_output=True, text=True,
    )
    return proc.stdout if proc.returncode == 0 else None

def add_package(path, include_private=True):
    raw = index_text(path)
    if raw is None:
        return
    try:
        data = json.loads(raw)
    except Exception:
        return
    name = data.get("name")
    if isinstance(name, str) and name and (include_private or not data.get("private", False)):
        known.add(name)

try:
    config = json.loads(index_text(".changeset/config.json") or "{}")
except Exception:
    config = {}
include_private = bool((config.get("privatePackages") or {}).get("tag"))
patterns = config.get("packages") if isinstance(config.get("packages"), list) else []
workspace = index_text("pnpm-workspace.yaml")
if not patterns and workspace:
    for line in workspace.splitlines():
        match = re.match(r"^\s*-\s+['\"]?([^'\"#\s]+)", line)
        if match:
            patterns.append(match.group(1))

listed = subprocess.run(
    ["git", "-C", repo, "ls-files", "--cached", "*package.json"],
    capture_output=True, text=True,
)
package_paths = [p for p in listed.stdout.splitlines() if p]
if patterns:
    for package_path in package_paths:
        directory = package_path.rsplit("/", 1)[0] if "/" in package_path else "."
        if any(fnmatch.fnmatch(directory, pattern) for pattern in patterns):
            add_package(package_path, include_private=include_private)
if not known:
    # Mirrors producer behavior: an all-private workspace with tag=false uses
    # the root package as the release owner.
    add_package("package.json", include_private=True)
if not known or any(scope not in known for scope in parsed):
    raise SystemExit(1)
PY
}

gate_staged_changeset() {
  local disposition path identity base
  disposition="$(staged_disposition)"
  [[ "$disposition" == "behavioral" ]] || exit 0
  identity="$(active_task_identity)"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    base="$(basename "$path" .md)"
    if [[ -n "$identity" && "$base" != "$identity"-* ]]; then
      continue
    fi
    if prospective_changeset_is_canonical "$path"; then
      echo "$PREFIX ✅ prospective commit tree contains canonical changeset: $path" >&2
      exit 0
    fi
  done < <(prospective_changeset_paths)

  cat >&2 <<EOF
$PREFIX BLOCKED: behavioral staged delta has no canonical changeset in the prospective commit tree.
  Marker: POLARIS_CHANGESET_STAGED_MISSING
  Repo:   $REPO_ROOT

Fix:
  Produce the repo-policy changeset, then stage it before committing.
EOF
  exit 2
}

if [[ "$STAGED_MODE" -eq 1 ]]; then
  gate_staged_changeset
fi

# RESOLVED_TASK_MDS holds the FULL resolved candidate set (one per line). When
# --task-md is supplied it is the single member; when resolved by branch it is
# every task.md matching the branch (a bundle alias legitimately multi-matches).
# TASK_MD stays the first member so the per-task changeset contract below is
# unchanged; the release-stage exemption (DP-319) consults the full set.
RESOLVED_TASK_MDS=""
if [[ -n "$TASK_MD" ]]; then
  RESOLVED_TASK_MDS="$TASK_MD"
else
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    exit 0
  fi
  # Resolve the branch against the repo being gated ($REPO_ROOT). In every real
  # callsite the gate script lives in that same repo, so this equals the prior
  # "$WORKSPACE_SCRIPTS/.." while also resolving multi-match members correctly in
  # hermetic fixtures (DP-319 all-members rule).
  RESOLVED_TASK_MDS="$(bash "$RESOLVE_BY_BRANCH" --scan-root "$REPO_ROOT" "$branch" 2>/dev/null || true)"
  TASK_MD="$(printf '%s\n' "$RESOLVED_TASK_MDS" | head -n 1 || true)"
fi

if [[ -z "$TASK_MD" ]]; then
  # Non-managed branch/admin workflow.
  exit 0
fi

if [[ ! -f "$TASK_MD" ]]; then
  echo "$PREFIX BLOCKED: resolved task.md does not exist: $TASK_MD" >&2
  exit 2
fi

# is_release_stage_exempt: DP-319 — release-stage exemption keyed off the
# pr-release TASK LIFECYCLE POSITION, not container archive timing or branch
# naming. A framework-release bundle finalizes every member task.md into
# */tasks/pr-release/*; once that has happened the bundle PR delta is
# legitimately behavioral (it carries the members' implementation), so the
# per-task changeset / PR-title contracts must NOT tear it apart.
#
# all-members rule (AC5): EVERY resolved member must live under */tasks/pr-release/*.
# If any member is still in tasks/Tn/ (active development), the bundle is not
# release-staged — fall through to the per-task contract. Echoes nothing; returns
# 0 when release-stage exempt, 1 otherwise (including empty input).
is_release_stage_exempt() {
  local members="$1"
  local saw_member=0 line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    saw_member=1
    case "$line" in
      */tasks/pr-release/*) ;;
      *) return 1 ;;
    esac
  done <<<"$members"
  [[ "$saw_member" -eq 1 ]]
}

task_base_ref() {
  local task_md="$1"
  local base
  base="$(awk -F'|' '
    $2 ~ /Base branch/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
      print $3
      exit
    }
  ' "$task_md")"
  [[ -n "$base" && "$base" != "N/A" ]] || base="origin/main"
  if git -C "$REPO_ROOT" rev-parse --verify -q "origin/${base}" >/dev/null 2>&1; then
    printf 'origin/%s\n' "$base"
  elif git -C "$REPO_ROOT" rev-parse --verify -q "$base" >/dev/null 2>&1; then
    printf '%s\n' "$base"
  else
    printf 'origin/main\n'
  fi
}

changeset_only_task_delta() {
  local task_md="$1"
  local base_ref merge_base changed non_changeset
  base_ref="$(task_base_ref "$task_md")"
  merge_base="$(git -C "$REPO_ROOT" merge-base "$base_ref" HEAD 2>/dev/null || true)"
  [[ -n "$merge_base" ]] || return 1
  changed="$(git -C "$REPO_ROOT" diff --name-only "${merge_base}..HEAD" -- 2>/dev/null || true)"
  [[ -n "$changed" ]] || return 1
  non_changeset="$(printf '%s\n' "$changed" | grep -Ev '^\.changeset/[^/]+\.md$' || true)"
  [[ -z "$non_changeset" ]]
}

# gate_changeset_body_language: DP-421 T3 — enforce the changeset BODY against the
# workspace-config.yaml language contract at the EARLIEST authoring point
# (changeset-gate time), so a non-target-language changeset fails HERE instead of
# being deferred to the release surface (the DP-417 scenario). Reuses the shared
# scripts/validate-language-policy.sh carve-out for technical identifiers (script
# names, DP keys, commands, paths, error tokens stay in their original form) — no
# second carve-out is defined. Gates every .changeset/*.md added in the task delta
# (README.md excluded). Returns 2 on a language violation, 0 otherwise; the
# language gate is additive and no-ops when the validator is absent.
# resolve_workspace_language: read the declared workspace-config.yaml `language`
# that governs the repo under gate by scanning UPWARD from REPO_ROOT and taking the
# highest (topmost) workspace-config.yaml in that ancestry. Echoes the language (or
# nothing when none is declared). Deliberately does NOT use the shared resolver's
# main-checkout fallback: the changeset body gate must resolve the OWN contract of
# the gated repo, so an independent repo (e.g. a hermetic fixture with no
# workspace-config.yaml) resolves to empty and is exempt — the outer Polaris
# workspace language must not leak into it. Worktrees live under the workspace root,
# so the plain upward scan still reaches the workspace-config.yaml that governs them.
resolve_workspace_language() {
  local dir highest="" cfg
  dir="$REPO_ROOT"
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    [[ -f "$dir/workspace-config.yaml" ]] && highest="$dir"
    dir="$(dirname "$dir")"
  done
  [[ -n "$highest" ]] || return 0
  cfg="$highest/workspace-config.yaml"
  awk -F ':' '
    /^[[:space:]]*language[[:space:]]*:/ {
      v=$2; sub(/#.*/, "", v)
      gsub(/^[[:space:]"'\''"]+|[[:space:]"'\''"]+$/, "", v)
      if (v != "") { print v; exit }
    }
  ' "$cfg"
}

gate_changeset_body_language() {
  local task_md="$1"
  local base_ref merge_base changed cs_file rc=0 language
  [[ -x "$LANG_POLICY" ]] || return 0
  language="$(resolve_workspace_language)"
  # No declared workspace language contract -> nothing to enforce.
  [[ -n "$language" ]] || return 0
  base_ref="$(task_base_ref "$task_md")"
  merge_base="$(git -C "$REPO_ROOT" merge-base "$base_ref" HEAD 2>/dev/null || true)"
  [[ -n "$merge_base" ]] || return 0
  changed="$(git -C "$REPO_ROOT" diff --name-only --diff-filter=d "${merge_base}..HEAD" -- 2>/dev/null \
    | grep -E '^\.changeset/[^/]+\.md$' || true)"
  [[ -n "$changed" ]] || return 0
  while IFS= read -r cs_file; do
    [[ -n "$cs_file" ]] || continue
    [[ "$(basename "$cs_file")" == "README.md" ]] && continue
    [[ -f "$REPO_ROOT/$cs_file" ]] || continue
    if ! bash "$LANG_POLICY" --blocking --mode artifact --language "$language" \
        "$REPO_ROOT/$cs_file" >/dev/null 2>&1; then
      cat >&2 <<EOF
$PREFIX BLOCKED: changeset body violates workspace language policy.
  Marker:    POLARIS_CHANGESET_LANGUAGE_POLICY
  Repo:      $REPO_ROOT
  Changeset: $cs_file

Fix:
  Rewrite the changeset description in the workspace language. Technical
  identifiers — script names, DP keys, commands, paths, error tokens — may stay
  in their original form (reuses validate-language-policy carve-out).
EOF
      rc=2
    fi
  done <<<"$changed"
  return "$rc"
}

# DP-319: this exemption runs BEFORE the changeset check and the
# evidence-classifier so an impl-bearing (behavioral) bundle delta is not
# misclassified and blocked (EC2 / AC1). It does not relax any other gate.
if is_release_stage_exempt "$RESOLVED_TASK_MDS"; then
  echo "$PREFIX ✅ release-stage (all members in tasks/pr-release/) — exempt from per-task changeset (DP-319; pr-release lifecycle position)." >&2
  exit 0
fi

if bash "$POLARIS_CHANGESET" check --task-md "$TASK_MD" --repo "$REPO_ROOT"; then
  if changeset_only_task_delta "$TASK_MD"; then
    cat >&2 <<EOF
$PREFIX BLOCKED: task delivery delta only contains .changeset/*.md.
  Marker:  POLARIS_CHANGESET_ONLY_TASK_DELTA
  Repo:    $REPO_ROOT
  Task.md: $TASK_MD

Fix:
  Route back to planning/refinement and disposition this task as absorbed/backfilled,
  or restore the task-owned implementation delta before opening an implementation PR.
EOF
    exit 2
  fi
  if ! gate_changeset_body_language "$TASK_MD"; then
    exit 2
  fi
  echo "$PREFIX ✅ changeset present for $(basename "$TASK_MD")." >&2
  exit 0
fi

# DP-305 AC8: release-bump / metadata-only push deltas are exempt — the release
# tail consumes the accumulated changesets via `mise run release:version`, so a
# resolved member task.md legitimately has no pending changeset on a release-bump
# HEAD. Classify the push delta via the SAME shared classifier gate-evidence.sh
# uses (DP-294); behavioral deltas fall through and stay fail-closed below. No
# manual POLARIS_SKIP_CHANGESET_GATE needed.
#
# DP-334 AC5: the release-stage exemption keys off the push-delta classifier
# (release_bump / metadata_only), not the legacy bundle model. It is therefore
# lifecycle-agnostic and already correct for the feat/DP-NNN model, where the
# version is squashed once at the feat HEAD (release:version consumes the
# accumulated member changesets there). No bundle_branch_alias coupling exists in
# this gate.
EVIDENCE_CLASSIFIER="${WORKSPACE_SCRIPTS}/lib/evidence-classifier.sh"
HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
if [[ -n "$HEAD_SHA" && -x "$EVIDENCE_CLASSIFIER" ]]; then
  cls_base="$(git -C "$REPO_ROOT" merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -n "$cls_base" && "$cls_base" != "$HEAD_SHA" ]]; then
    cls_disp="$(bash "$EVIDENCE_CLASSIFIER" classify --repo "$REPO_ROOT" --range "${cls_base}..${HEAD_SHA}" 2>/dev/null || true)"
  else
    cls_disp="$(bash "$EVIDENCE_CLASSIFIER" classify --repo "$REPO_ROOT" --head "$HEAD_SHA" 2>/dev/null || true)"
  fi
  case "$cls_disp" in
    release_bump|metadata_only)
      echo "$PREFIX ${cls_disp} delta — exempt from task-bound changeset (DP-305 AC8 classifier; no manual skip)." >&2
      exit 0
      ;;
  esac
fi

cat >&2 <<EOF
$PREFIX BLOCKED: missing task changeset.
  Repo:    $REPO_ROOT
  Task.md: $TASK_MD

Fix:
  bash "$POLARIS_CHANGESET" new --task-md "$TASK_MD" --repo "$REPO_ROOT"
EOF
exit 2
