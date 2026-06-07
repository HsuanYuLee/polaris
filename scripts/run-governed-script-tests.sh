#!/usr/bin/env bash
# Purpose: run the governed script-test suite (scripts/manifest.json) selected by
#          --profile and/or changed files. With --head-ref, the suite runs against
#          a PR-head isolated worktree (POLARIS_GOVERNED_TEST_ROOT) so compile/parity
#          --check-class selftests validate the PR head tree, not the lane checkout.
# Inputs:  --root <repo> --manifest <path> --profile <name> --changed-file <path>...
#          --base <ref> --head-ref <ref> --dry-run
# Outputs: stdout selection/run log; exit 0 PASS, 2 arg error, non-zero on test fail.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH=""
PROFILE=""
BASE_REF=""
HEAD_REF=""
DRY_RUN=false
CHANGED_FILES=()

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/run-governed-script-tests.sh [--root <repo>] [--manifest <path>] [--profile <name>] [--changed-file <path>...] [--base <ref> --head-ref <ref>] [--dry-run]

Runs the governed script test suite declared in scripts/manifest.json.
Selection uses union semantics:
  - tests matching --profile
  - tests whose changed_paths match --changed-file or git diff --name-only --base/--head-ref
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="$2"; shift 2 ;;
    --manifest) MANIFEST_PATH="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --changed-file) CHANGED_FILES+=("$2"); shift 2 ;;
    --base) BASE_REF="$2"; shift 2 ;;
    --head-ref) HEAD_REF="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "run-governed-script-tests: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"
if [[ -z "$MANIFEST_PATH" ]]; then
  MANIFEST_PATH="$ROOT_DIR/scripts/manifest.json"
fi

if [[ -n "$BASE_REF" || -n "$HEAD_REF" ]]; then
  if [[ -z "$BASE_REF" || -z "$HEAD_REF" ]]; then
    echo "run-governed-script-tests: --base and --head-ref must be provided together" >&2
    exit 2
  fi
  while IFS= read -r changed; do
    [[ -n "$changed" ]] && CHANGED_FILES+=("$changed")
  done < <(git -C "$ROOT_DIR" diff --name-only "${BASE_REF}...${HEAD_REF}")
fi

# DP-293 T1: when a PR head ref is given, materialise it in an isolated worktree and
# point compile/parity --check-class selftests at it via POLARIS_GOVERNED_TEST_ROOT.
# Without this, those selftests resolve ROOT from their own BASH_SOURCE (the lane
# checkout = main) and a clean PR head gets false-blocked by pre-existing main drift.
ISOLATED_HEAD_TREE=""
cleanup_isolated_head_tree() {
  if [[ -n "$ISOLATED_HEAD_TREE" && -d "$ISOLATED_HEAD_TREE" ]]; then
    git -C "$ROOT_DIR" worktree remove --force "$ISOLATED_HEAD_TREE" >/dev/null 2>&1 || true
    rm -rf "$ISOLATED_HEAD_TREE" 2>/dev/null || true
  fi
}
if [[ -n "$HEAD_REF" ]]; then
  ISOLATED_HEAD_TREE="$(mktemp -d -t polaris-governed-head.XXXXXX)"
  trap cleanup_isolated_head_tree EXIT
  if ! git -C "$ROOT_DIR" worktree add --detach --force "$ISOLATED_HEAD_TREE" "$HEAD_REF" >/dev/null 2>&1; then
    echo "run-governed-script-tests: failed to checkout head ref '$HEAD_REF' into isolated worktree" >&2
    exit 2
  fi
  export POLARIS_GOVERNED_TEST_ROOT="$ISOLATED_HEAD_TREE"
fi

python_args=("$MANIFEST_PATH" "$PROFILE")
if [[ ${#CHANGED_FILES[@]} -gt 0 ]]; then
  python_args+=("${CHANGED_FILES[@]}")
fi

selection_json="$(python3 - "${python_args[@]}" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
profile = sys.argv[2]
changed_files = sys.argv[3:]
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
tests = manifest.get("governed_tests", [])

def matches_changed(test):
    patterns = test.get("changed_paths") or []
    for changed in changed_files:
        for pattern in patterns:
            if changed == pattern or changed.startswith(pattern.rstrip("/") + "/"):
                return True
    return False

selected = []
seen = set()
for test in tests:
    if not test.get("enrolled", False):
        continue
    by_profile = bool(profile and profile in (test.get("profiles") or []))
    by_changed = matches_changed(test)
    if by_profile or by_changed:
        test_id = test.get("id")
        if test_id not in seen:
            selected.append({"id": test_id, "command": test.get("command")})
            seen.add(test_id)

print(json.dumps(selected, ensure_ascii=False))
PY
)"

count="$(python3 - "$selection_json" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
)"

echo "run-governed-script-tests: selected ${count} test(s)"
if [[ "$count" == "0" ]]; then
  exit 0
fi

python3 - "$selection_json" <<'PY' | while IFS= read -r row; do
import json, shlex, sys
for test in json.loads(sys.argv[1]):
    print(f"{test['id']}\t{test['command']}")
PY
  test_id="${row%%$'\t'*}"
  command="${row#*$'\t'}"
  echo "run-governed-script-tests: ${test_id}: ${command}"
  if [[ "$DRY_RUN" == true ]]; then
    continue
  fi
  (cd "$ROOT_DIR" && bash -lc "$command")
done
