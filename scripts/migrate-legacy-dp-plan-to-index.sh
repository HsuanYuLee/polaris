#!/usr/bin/env bash
# Purpose: Inventory and migrate legacy DP `plan.md` primary docs to folder-native
#          `index.md` without losing historical body/frontmatter.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: migrate-legacy-dp-plan-to-index.sh --workspace PATH (--dry-run|--execute) [--include-archive]

Modes:
  --dry-run          Inventory legacy DP plan.md files. Fails when active
                     non-archive legacy plans remain.
  --execute          Migrate active legacy plan.md files to index.md. Archive
                     plans are explicit allowlist by default.
  --include-archive  With --execute, migrate archive plan.md files too.
EOF
}

WORKSPACE=""
MODE=""
INCLUDE_ARCHIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --execute) MODE="execute"; shift ;;
    --include-archive) INCLUDE_ARCHIVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$WORKSPACE" || -z "$MODE" ]]; then
  usage
  exit 2
fi

python3 - "$WORKSPACE" "$MODE" "$INCLUDE_ARCHIVE" <<'PY'
import sys
from pathlib import Path

workspace = Path(sys.argv[1]).expanduser().resolve()
mode = sys.argv[2]
include_archive = sys.argv[3] == "1"
design_plans = workspace / "docs-manager/src/content/docs/specs/design-plans"

if not workspace.exists():
    print(f"POLARIS_LEGACY_DP_PLAN_WORKSPACE_MISSING: {workspace}", file=sys.stderr)
    raise SystemExit(2)
if not design_plans.exists():
    print(f"POLARIS_LEGACY_DP_PLAN_ROOT_MISSING: {design_plans}", file=sys.stderr)
    raise SystemExit(2)

plans = sorted(design_plans.rglob("plan.md"))


def is_archive(path: Path) -> bool:
    rel = path.relative_to(design_plans)
    return rel.parts[:1] == ("archive",)


active = [path for path in plans if not is_archive(path)]
archive = [path for path in plans if is_archive(path)]

print(
    "legacy-dp-plan inventory: "
    f"active={len(active)} archive_allowlisted={len(archive)} mode={mode}"
)
for path in active:
    print(f"  active: {path.relative_to(workspace).as_posix()}")
for path in archive[:20]:
    print(f"  archive-allowlisted: {path.relative_to(workspace).as_posix()}")
if len(archive) > 20:
    print(f"  archive-allowlisted: ... {len(archive) - 20} more")

if mode == "dry-run":
    if active:
        print(
            "POLARIS_LEGACY_DP_PLAN_ACTIVE: active design-plan plan.md files must be migrated to index.md",
            file=sys.stderr,
        )
        raise SystemExit(1)
    raise SystemExit(0)

if mode != "execute":
    print(f"POLARIS_LEGACY_DP_PLAN_USAGE: unknown mode {mode}", file=sys.stderr)
    raise SystemExit(2)

targets = list(active)
if include_archive:
    targets.extend(archive)

if not targets:
    print("legacy-dp-plan migrate: no matching plan.md files to migrate.")
    raise SystemExit(0)

for plan in targets:
    index = plan.parent / "index.md"
    if index.exists():
        print(
            f"POLARIS_LEGACY_DP_PLAN_INDEX_EXISTS: refusing to overwrite {index}",
            file=sys.stderr,
        )
        raise SystemExit(1)
    content = plan.read_text(encoding="utf-8")
    index.write_text(content, encoding="utf-8")
    plan.unlink()
    print(f"migrated: {plan.relative_to(workspace).as_posix()} -> {index.relative_to(workspace).as_posix()}")

raise SystemExit(0)
PY
