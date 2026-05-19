#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MODE="changed"
declare -a EXPLICIT_FILES=()

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/gates/gate-evidence-producer-whitelist.sh [--repo <path>] [--staged] [--all-evidence] [--files <file>...]

Validates changed .polaris/evidence/*.json markers against scripts/lib/evidence-producers.json.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --staged) MODE="staged"; shift ;;
    --all-evidence) MODE="all"; shift ;;
    --files)
      MODE="files"
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        EXPLICIT_FILES+=("$1")
        shift
      done
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "gate-evidence-producer-whitelist: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -d "$REPO_ROOT" ]] || { echo "gate-evidence-producer-whitelist: repo not found: $REPO_ROOT" >&2; exit 2; }
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-auto-pass-proof.sh"
[[ -x "$VALIDATOR" || -f "$VALIDATOR" ]] || { echo "gate-evidence-producer-whitelist: missing validator: $VALIDATOR" >&2; exit 2; }

collect_files() {
  case "$MODE" in
    staged)
      git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true
      ;;
    all)
      find "$REPO_ROOT/.polaris/evidence" -type f -name '*.json' 2>/dev/null | sed "s#^$REPO_ROOT/##" || true
      ;;
    files)
      printf '%s\n' "${EXPLICIT_FILES[@]}"
      ;;
    changed)
      local branch upstream merge_base
      branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      upstream=""
      if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
        upstream="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
      fi
      if [[ -n "$upstream" ]]; then
        merge_base="$(git -C "$REPO_ROOT" merge-base "$upstream" HEAD 2>/dev/null || true)"
        if [[ -n "$merge_base" ]]; then
          git -C "$REPO_ROOT" diff --name-only --diff-filter=ACMR "$merge_base...HEAD" 2>/dev/null || true
        fi
      else
        git -C "$REPO_ROOT" diff --name-only --diff-filter=ACMR HEAD~1..HEAD 2>/dev/null || true
      fi
      git -C "$REPO_ROOT" diff --name-only --diff-filter=ACMR 2>/dev/null || true
      ;;
  esac
}

evidence_list="$(collect_files | while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  if [[ "$file" == "$REPO_ROOT"/.polaris/evidence/*.json || "$file" == "$REPO_ROOT"/.polaris/evidence/*/*.json || "$file" == "$REPO_ROOT"/.polaris/evidence/*/*/*.json ]]; then
    printf '%s\n' "$file"
  elif [[ "$file" == .polaris/evidence/*.json || "$file" == .polaris/evidence/*/*.json || "$file" == .polaris/evidence/*/*/*.json ]]; then
    printf '%s\n' "$REPO_ROOT/$file"
  fi
done | sort -u)"

evidence_files=()
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  evidence_files+=("$file")
done <<<"$evidence_list"

if [[ "${#evidence_files[@]}" -eq 0 ]]; then
  echo "PASS: evidence producer whitelist (no changed evidence markers)"
  exit 0
fi

existing=()
for file in "${evidence_files[@]}"; do
  [[ -f "$file" ]] && existing+=("$file")
done

if [[ "${#existing[@]}" -eq 0 ]]; then
  echo "PASS: evidence producer whitelist (changed markers deleted only)"
  exit 0
fi

(cd "$REPO_ROOT" && bash "$VALIDATOR" "${existing[@]}")
echo "PASS: evidence producer whitelist (${#existing[@]} file(s))"
