#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d -t verify-agents-mirror.XXXXXX)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/.claude/rules" "$tmp/scripts"
  cat > "$tmp/scripts/fallback.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$tmp/scripts/fallback.sh"
  cat > "$tmp/.claude/rules/mechanism-registry.md" <<'MD'
# Registry

## Runtime Annotation Registry

| mechanism | path | kind | runtime | fallback_script | governance_role |
|-----------|------|------|---------|-----------------|-----------------|
| portable-test | scripts/fallback.sh | script | portable | N/A | governance |
| claude-only-test | .claude/hooks/example.sh | hook | claude-code-only | scripts/fallback.sh | governance |
MD
  (cd "$tmp" && bash "${OLDPWD}/scripts/verify-agents-mirror-portable.sh")
  echo "PASS: verify-agents-mirror-portable self-test"
  exit 0
fi

REGISTRY=".claude/rules/mechanism-registry.md"
[[ -f "$REGISTRY" ]] || { echo "ERROR: missing $REGISTRY" >&2; exit 1; }

python3 - "$REGISTRY" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

registry = Path(sys.argv[1])
root = Path.cwd()
text = registry.read_text()
section = []
capture = False
for line in text.splitlines():
    if line.strip() == "## Runtime Annotation Registry":
        capture = True
        continue
    if capture and line.startswith("## "):
        break
    if capture:
        section.append(line)

rows = []
for line in section:
    stripped = line.strip()
    if not stripped.startswith("|"):
        continue
    cells = [cell.strip().strip("`") for cell in stripped.strip("|").split("|")]
    if cells and all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in cells):
        continue
    rows.append(cells)

if len(rows) < 2:
    print("ERROR: runtime annotation registry has no rows", file=sys.stderr)
    sys.exit(1)

header = [cell.lower() for cell in rows[0]]
idx = {name: header.index(name) for name in ("mechanism", "path", "runtime", "fallback_script", "governance_role")}
errors = []
checked = 0
for row_no, row in enumerate(rows[1:], start=2):
    runtime = row[idx["runtime"]].strip()
    path = row[idx["path"]].strip()
    fallback = row[idx["fallback_script"]].strip()
    role = row[idx["governance_role"]].strip()
    if runtime == "portable":
        checked += 1
        if path != "N/A" and not any(ch in path for ch in "*?[]") and not (root / path).exists():
            errors.append(f"row {row_no}: portable mechanism path missing: {path}")
    elif runtime == "claude-code-only" and role != "ux_enhancement_only":
        checked += 1
        if not fallback or fallback == "N/A" or not (root / fallback).exists():
            errors.append(f"row {row_no}: claude-only governance fallback missing: {fallback}")

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)
print(f"PASS: portable mirror smoke targets valid ({checked} targets)")
PY
