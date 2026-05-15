#!/usr/bin/env bash
# check-runtime-cache-residue.sh — block repo-local runtime cache residue.

set -euo pipefail

repo="."
source_container=""

usage() {
  cat >&2 <<'EOF'
usage: check-runtime-cache-residue.sh [--repo <workspace-root>] [--source-container <path>]

Blocks when temporary runtime cache files remain in:
  .polaris/runtime/external-writes/
  .codex/external-writes/
  .codex/tmp/

Durable drafts must be moved to the owning source container, for example:
  {source_container}/jira-comments/
  {source_container}/artifacts/external-writes/
  {source_container}/artifacts/research/
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --source-container)
      source_container="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "check-runtime-cache-residue: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$repo" || ! -d "$repo" ]]; then
  echo "check-runtime-cache-residue: --repo not found: ${repo:-<empty>}" >&2
  exit 2
fi

repo="$(cd "$repo" && pwd)"
if [[ -n "$source_container" ]]; then
  if [[ "$source_container" = /* ]]; then
    source_container_abs="$source_container"
  else
    source_container_abs="$repo/$source_container"
  fi
else
  source_container_abs=""
fi

scan_dirs=(
  ".polaris/runtime/external-writes"
  ".codex/external-writes"
  ".codex/tmp"
)

residue=()
for rel in "${scan_dirs[@]}"; do
  dir="$repo/$rel"
  [[ -d "$dir" ]] || continue
  while IFS= read -r -d '' path; do
    residue+=("${path#"$repo"/}")
  done < <(find "$dir" -type f -print0 2>/dev/null)
done

if [[ "${#residue[@]}" -eq 0 ]]; then
  echo "PASS: no runtime cache residue"
  exit 0
fi

cat >&2 <<'EOF'
BLOCKED: runtime cache residue found.

These paths are temporary transport or forbidden old scratch locations. Move
durable content to the owning source container, or delete it if it has no
durable value.
EOF

printf '\nResidue files:\n' >&2
printf '  - %s\n' "${residue[@]}" >&2

if [[ -n "$source_container_abs" ]]; then
  rel_container="${source_container_abs#"$repo"/}"
  cat >&2 <<EOF

Suggested durable destinations under:
  ${rel_container}

  - ${rel_container}/jira-comments/YYYYMMDD-{slug}.md
  - ${rel_container}/artifacts/external-writes/YYYYMMDD-{slug}.md
  - ${rel_container}/artifacts/research/YYYY-MM-DD-{slug}.md
EOF
else
  cat >&2 <<'EOF'

Pass --source-container <path> to print source-specific durable destinations.
EOF
fi

exit 1
