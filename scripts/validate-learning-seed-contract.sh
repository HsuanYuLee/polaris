#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/validate-learning-seed-contract.sh --producer learning --diff-range <base..head>
  bash scripts/validate-learning-seed-contract.sh --producer refinement --source-container <DP-folder>
  bash scripts/validate-learning-seed-contract.sh --self-test
USAGE
}

self_test() {
  local tmp repo
  tmp="$(mktemp -d -t learning-seed-contract.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN
  repo="$tmp/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.test
  git -C "$repo" config user.name "Self Test"
  mkdir -p "$repo/docs-manager/src/content/docs/specs/design-plans/DP-001-test/artifacts"
  echo ok > "$repo/README.md"
  git -C "$repo" add .
  git -C "$repo" commit -q -m init
  local base
  base="$(git -C "$repo" rev-parse HEAD)"

  echo forbidden > "$repo/docs-manager/src/content/docs/specs/design-plans/DP-001-test/index.md"
  git -C "$repo" add .
  git -C "$repo" commit -q -m forbidden
  if (cd "$repo" && bash "$OLDPWD/scripts/validate-learning-seed-contract.sh" --producer learning --diff-range "$base..HEAD") >/dev/null 2>&1; then
    echo "self-test failed: learning forbidden file passed" >&2
    exit 1
  fi

  git -C "$repo" reset -q --hard "$base"
  echo report > "$repo/docs-manager/src/content/docs/specs/design-plans/DP-001-test/artifacts/research-report.md"
  git -C "$repo" add .
  git -C "$repo" commit -q -m allowed
  (cd "$repo" && bash "$OLDPWD/scripts/validate-learning-seed-contract.sh" --producer learning --diff-range "$base..HEAD") >/dev/null

  local container="$repo/docs-manager/src/content/docs/specs/design-plans/DP-002-refinement"
  mkdir -p "$container"
  (cd "$repo" && bash "$OLDPWD/scripts/validate-learning-seed-contract.sh" --producer refinement --source-container "$container") >/dev/null
  echo title > "$container/index.md"
  (cd "$repo" && bash "$OLDPWD/scripts/validate-learning-seed-contract.sh" --producer refinement --source-container "$container") >/dev/null
  echo md > "$container/refinement.md"
  echo '{}' > "$container/refinement.json"
  (cd "$repo" && bash "$OLDPWD/scripts/validate-learning-seed-contract.sh" --producer refinement --source-container "$container") >/dev/null

  if (cd "$repo" && bash "$OLDPWD/scripts/validate-learning-seed-contract.sh" --diff-range "$base..HEAD") >/dev/null 2>&1; then
    echo "self-test failed: missing producer passed" >&2
    exit 1
  fi
  if (cd "$repo" && bash "$OLDPWD/scripts/validate-learning-seed-contract.sh" --producer refinement) >/dev/null 2>&1; then
    echo "self-test failed: missing source-container passed" >&2
    exit 1
  fi
  echo "PASS: validate-learning-seed-contract self-test"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

PRODUCER=""
DIFF_RANGE=""
SOURCE_CONTAINER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --producer) PRODUCER="${2:-}"; shift 2 ;;
    --diff-range) DIFF_RANGE="${2:-}"; shift 2 ;;
    --source-container) SOURCE_CONTAINER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

case "$PRODUCER" in
  learning)
    [[ -n "$DIFF_RANGE" ]] || { echo "ERROR: --producer learning requires --diff-range" >&2; exit 64; }
    while read -r path; do
      if [[ "$path" =~ ^docs-manager/src/content/docs/specs/design-plans/DP-[^/]+/(index\.md|plan\.md|refinement\.md|refinement\.json)$ ]]; then
        echo "ERROR: learning Route A may not write canonical DP file: $path" >&2
        exit 1
      fi
    done < <(git diff --name-only "$DIFF_RANGE")
    echo "PASS: learning seed diff respects Route A contract"
    ;;
  refinement)
    [[ -n "$SOURCE_CONTAINER" ]] || { echo "ERROR: --producer refinement requires --source-container" >&2; exit 64; }
    [[ -d "$SOURCE_CONTAINER" ]] || { echo "ERROR: source container not found: $SOURCE_CONTAINER" >&2; exit 64; }
    echo "PASS: refinement structural audit accepted $(basename "$SOURCE_CONTAINER")"
    ;;
  *)
    echo "ERROR: --producer must be learning or refinement" >&2
    usage
    exit 64
    ;;
esac
