#!/usr/bin/env bash
set -euo pipefail

# validate-spec-boundary.sh
#
# Static guard for local/publishable spec boundary declarations. This is
# intentionally narrow: selftest coverage lands the contract first, and broader
# repo-wide enforcement can be enabled by future framework tasks.

usage() {
  cat >&2 <<'EOF'
usage: validate-spec-boundary.sh --selftest
       validate-spec-boundary.sh <spec.md|spec_dir>

Checks that specs under docs-manager/src/content/docs/specs declare either:
- storage_boundary: local_only|publish_ready
- spec_boundary: local_only|publish_ready
EOF
}

run_selftest() {
  local tmp good legacy bad dir_good
  tmp="$(mktemp -d -t spec-boundary-selftest.XXXXXX)"
  trap 'rm -rf "${tmp:-}"' EXIT

  good="$tmp/docs-manager/src/content/docs/specs/design-plans/DP-999-good/index.md"
  legacy="$tmp/docs-manager/src/content/docs/specs/design-plans/DP-998-legacy/index.md"
  bad="$tmp/docs-manager/src/content/docs/specs/design-plans/DP-997-bad/index.md"
  dir_good="$(dirname "$good")"
  mkdir -p "$(dirname "$good")" "$(dirname "$legacy")" "$(dirname "$bad")"

  cat > "$good" <<'MD'
---
title: good
storage_boundary: local_only
---
# Good
MD
  cat > "$legacy" <<'MD'
---
title: legacy
spec_boundary: publish_ready
---
# Legacy
MD
  cat > "$bad" <<'MD'
---
title: bad
---
# Bad
MD

  bash "$0" "$good" >/dev/null
  bash "$0" "$legacy" >/dev/null
  bash "$0" "$dir_good" >/dev/null
  if bash "$0" "$bad" >/dev/null 2>&1; then
    echo "[selftest] missing boundary declaration passed" >&2
    return 1
  fi

  echo "validate-spec-boundary selftest PASS"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--selftest" || "${1:-}" == "--self-test" ]]; then
  run_selftest
  exit $?
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

python3 - "$1" <<'PY'
from pathlib import Path
import re
import sys

target = Path(sys.argv[1])
if not target.exists():
    print(f"validate-spec-boundary: path not found: {target}", file=sys.stderr)
    raise SystemExit(2)

if target.is_file():
    files = [target]
else:
    files = sorted(
        p
        for p in target.rglob("*.md")
        if "/archive/" not in str(p)
        and "/tasks/pr-release/" not in str(p)
    )

errors = []
for path in files:
    normalized = str(path)
    if "docs-manager/src/content/docs/specs/" not in normalized:
        continue
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        errors.append(f"{path}: missing frontmatter boundary declaration")
        continue
    end = text.find("\n---\n", 4)
    if end == -1:
        errors.append(f"{path}: malformed frontmatter")
        continue
    frontmatter = text[4:end]
    if not re.search(r"^(?:storage_boundary|spec_boundary):\s*(?:local_only|publish_ready)\s*$", frontmatter, re.M):
        errors.append(f"{path}: missing storage_boundary/spec_boundary local_only|publish_ready")

if errors:
    print("validate-spec-boundary.sh FAIL", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"validate-spec-boundary.sh PASS - {target}")
PY
