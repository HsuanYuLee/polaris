#!/usr/bin/env bash
# Purpose: render refinement.json into the human-facing refinement.md derived view.
# Inputs:  <refinement.json> [--check]
# Outputs: writes <dir>/refinement.md (or --check compares without writing).
#
# DP-269: the jira-only schema fields (source.repo / source.base_branch /
# tasks[].jira_key) are machine-consumed by derive-task-md-from-refinement-json.sh
# and intentionally NOT surfaced in the rendered refinement.md. The generator
# (lib/refinement-md-generator.py) ignores unknown source/task fields, so the
# additive schema does not break the existing render output.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: render-refinement-md.sh <refinement.json> [--check]
USAGE
  exit 2
}

[[ $# -ge 1 ]] || usage
JSON_PATH="$1"
CHECK=0
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$(dirname "$JSON_PATH")/refinement.md"
TMP="$(mktemp -t refinement-md.XXXXXX)"
python3 "$SCRIPT_DIR/lib/refinement-md-generator.py" "$JSON_PATH" > "$TMP"
python3 - "$JSON_PATH" "$TMP" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
data = json.loads(json_path.read_text(encoding="utf-8"))
if (data.get("source") or {}).get("type") != "bug":
    raise SystemExit(0)

text = out_path.read_text(encoding="utf-8")
if "## Bug-specific Fields" in text:
    raise SystemExit(0)

text = re.sub(r"\n<!-- checksum: sha256:[0-9a-f]+ -->\n\Z", "\n", text)
steps = "; ".join(str(step) for step in data.get("reproduction_steps") or [])
bug_rows = [
    ("Reproduction steps", steps),
    ("Root cause", data.get("root_cause")),
    ("Source PR", data.get("source_pr")),
    ("Severity", data.get("severity")),
    ("Impact scope", data.get("impact_scope")),
    ("Regression", data.get("regression")),
]
section = "\n".join(
    ["## Bug-specific Fields", ""]
    + [f"- **{label}**: {value}" for label, value in bug_rows]
    + [""]
)
anchor = "\n## Hardened AC\n"
if anchor not in text:
    raise SystemExit("render-refinement-md: missing Hardened AC anchor")
payload = text.replace(anchor, f"\n{section}{anchor}", 1).rstrip() + "\n"
checksum = hashlib.sha256(payload.encode("utf-8")).hexdigest()
out_path.write_text(payload + f"\n<!-- checksum: sha256:{checksum} -->\n", encoding="utf-8")
PY
if [[ "$CHECK" -eq 1 ]]; then
  cmp -s "$TMP" "$OUT" || {
    echo "POLARIS_REFINEMENT_MD_HAND_EDIT_DETECTED" >&2
    rm -f "$TMP"
    exit 2
  }
  rm -f "$TMP"
  exit 0
fi
mv "$TMP" "$OUT"
