#!/usr/bin/env bash
# Rename a Design Plan container to a new DP-NNN number and update local refs.

set -euo pipefail

from=""
to=""
dry_run=false

usage() {
  cat >&2 <<'EOF'
usage: migrate-design-plan-number.sh --from <DP container path> --to DP-NNN [--dry-run]

Renames the specified active or archive DP container, replaces the old DP id
inside the moved container, rewrites exact old-container route/path references
under docs-manager specs and CHANGELOG.md, and refreshes sidebar metadata.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      from="${2:-}"
      shift 2
      ;;
    --to)
      to="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$from" || -z "$to" ]]; then
  usage
fi
if [[ ! -d "$from" || ! -f "$from/plan.md" ]]; then
  echo "error: source container must exist and contain plan.md: $from" >&2
  exit 2
fi
if [[ ! "$to" =~ ^DP-[0-9]{3}$ ]]; then
  echo "error: --to must be DP-NNN, got: $to" >&2
  exit 2
fi

old_name="$(basename "$from")"
if [[ ! "$old_name" =~ ^DP-[0-9]{3}-.+ ]]; then
  echo "error: source container name must start with DP-NNN-: $old_name" >&2
  exit 2
fi
old_id="${old_name%%-*}-${old_name#DP-???-}"
old_id="${old_name:0:6}"
suffix="${old_name#DP-???-}"
new_name="$to-$suffix"
parent="$(cd "$(dirname "$from")" && pwd)"
target="$parent/$new_name"

if [[ -e "$target" ]]; then
  echo "error: target already exists: $target" >&2
  exit 1
fi

specs_root="docs-manager/src/content/docs/specs"

if [[ "$dry_run" == "true" ]]; then
  echo "DRY_RUN migrate $from -> $target"
  exit 0
fi

mv "$from" "$target"

python3 - "$target" "$old_id" "$to" "$old_name" "$new_name" "$specs_root" <<'PY'
import sys
from pathlib import Path

target = Path(sys.argv[1])
old_id = sys.argv[2]
new_id = sys.argv[3]
old_name = sys.argv[4]
new_name = sys.argv[5]
specs_root = Path(sys.argv[6])

def replace_in_file(path: Path, replacements):
    if not path.is_file():
        return False
    text = path.read_text(encoding="utf-8", errors="replace")
    new = text
    for old, fresh in replacements:
        new = new.replace(old, fresh)
    if new != text:
        path.write_text(new, encoding="utf-8")
        return True
    return False

for path in sorted(target.rglob("*")):
    if path.suffix in {".md", ".json"}:
        replace_in_file(path, [(old_id, new_id), (old_name, new_name)])

global_targets = []
if specs_root.exists():
    global_targets.extend(p for p in specs_root.rglob("*") if p.suffix in {".md", ".json"})
changelog = Path("CHANGELOG.md")
if changelog.exists():
    global_targets.append(changelog)

for path in global_targets:
    if target in path.parents or path == target:
        continue
    replace_in_file(path, [(old_name, new_name)])
PY

bash scripts/sync-spec-sidebar-metadata.sh --apply "$target/plan.md" >/dev/null
echo "$target"
