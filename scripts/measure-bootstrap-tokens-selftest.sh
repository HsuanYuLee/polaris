#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d -t measure-bootstrap-tokens.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

ROOT="$TMP_DIR/workspace"
mkdir -p "$ROOT/.claude/rules" "$ROOT/.claude/skills/example" "$ROOT/.codex"

printf 'rule text 12345678\n' > "$ROOT/.claude/rules/example.md"
cat > "$ROOT/.claude/skills/example/SKILL.md" <<'MD'
---
name: example
description: "Use for example routing."
---

# Example
MD
printf 'claude runtime\n' > "$ROOT/CLAUDE.md"
printf 'agents runtime\n' > "$ROOT/AGENTS.md"
printf 'codex runtime\n' > "$ROOT/.codex/AGENTS.md"
printf 'local: true\n' > "$ROOT/workspace-config.yaml"

MEMORY="$TMP_DIR/MEMORY.md"
printf '# Memory Index\n\n## Hot (1)\n- entry\n' > "$MEMORY"

JSON_OUT="$TMP_DIR/report.json"
bash "$SCRIPT_DIR/measure-bootstrap-tokens.sh" \
  --root "$ROOT" \
  --memory-index "$MEMORY" \
  --json > "$JSON_OUT"

python3 - "$JSON_OUT" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    data = json.load(handle)

assert data["shared_polaris_estimated_tokens"] > 0
rows = {row["source"]: row for row in data["rows"]}
required = {
    ".claude/rules/*.md",
    ".claude/skills/*/SKILL.md frontmatter descriptions",
    "compiled runtime targets",
    "MEMORY.md index",
    "local overlays",
}
missing = required - rows.keys()
assert not missing, missing
for row in rows.values():
    assert row["confidence"] in {"exact", "tokenizer_estimated", "bytes_estimated", "manual_observed", "unsupported"}
    assert isinstance(row["bytes"], int)
    assert isinstance(row["estimated_tokens"], int)
PY

TRANSCRIPT="$TMP_DIR/transcript.txt"
printf 'observed adapter sample\n' > "$TRANSCRIPT"
bash "$SCRIPT_DIR/measure-bootstrap-tokens.sh" \
  --root "$ROOT" \
  --memory-index "$MEMORY" \
  --transcript "$TRANSCRIPT" \
  --json > "$JSON_OUT"

python3 - "$JSON_OUT" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    data = json.load(handle)

adapter_rows = [row for row in data["rows"] if row["scope"] == "adapter_specific"]
assert adapter_rows, "expected adapter transcript row"
assert adapter_rows[0]["confidence"] == "manual_observed"
assert data["adapter_specific_estimated_tokens"] > 0
PY

bash "$SCRIPT_DIR/measure-bootstrap-tokens.sh" --root "$ROOT" --memory-index "$MEMORY" --markdown >/dev/null
bash "$SCRIPT_DIR/measure-bootstrap-tokens.sh" --help >/dev/null

python3 - <<'PY'
import re
from pathlib import Path

workspace = Path("/Users/example.user/work")
slug = "-" + re.sub(r"[^A-Za-z0-9_-]+", "-", str(workspace).strip("/"))
assert slug == "-Users-example-user-work"
PY

echo "measure-bootstrap-tokens self-test PASS"
