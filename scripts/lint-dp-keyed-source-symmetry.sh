#!/usr/bin/env bash
# Purpose: fail closed when resolver/reader/container-enum source surfaces grow
#          DP-keyed logic without an adjacent JIRA Epic / companies counterpart.
# Inputs:
#   POLARIS_PARITY_ALLOWLIST             default scripts/lib/spec-source-parity-allowlist.txt
#   POLARIS_DP_KEYED_SOURCE_SURFACES     newline-separated file list override
# Exit:
#   0 pass, 2 asymmetry detected, 3 usage / IO error

set -euo pipefail

PREFIX="[dp-keyed-source-symmetry]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ALLOWLIST="${POLARIS_PARITY_ALLOWLIST:-$SCRIPT_DIR/lib/spec-source-parity-allowlist.txt}"

[[ -f "$ALLOWLIST" ]] || { echo "$PREFIX allowlist not found: $ALLOWLIST" >&2; exit 3; }

if [[ -n "${POLARIS_DP_KEYED_SOURCE_SURFACES:-}" ]]; then
  SURFACES="$POLARIS_DP_KEYED_SOURCE_SURFACES"
else
  SURFACES="$(cat <<'EOF'
scripts/resolve-task-md.sh
scripts/detect-closeout-drift.sh
scripts/auto-pass-probe.sh
scripts/evidence-classifier.sh
scripts/validate-auto-pass-report.sh
EOF
)"
fi

export POLARIS_DP_SYMMETRY_ALLOWLIST="$ALLOWLIST"
export POLARIS_DP_SYMMETRY_SURFACES="$SURFACES"
export POLARIS_DP_SYMMETRY_ROOT="$ROOT_DIR"
export POLARIS_DP_SYMMETRY_PREFIX="$PREFIX"

python3 - <<'PY'
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

allowlist_path = Path(os.environ["POLARIS_DP_SYMMETRY_ALLOWLIST"])
surfaces_raw = os.environ.get("POLARIS_DP_SYMMETRY_SURFACES", "")
root = Path(os.environ["POLARIS_DP_SYMMETRY_ROOT"])
prefix = os.environ["POLARIS_DP_SYMMETRY_PREFIX"]


def parse_allowlist(path: Path) -> set[str]:
    entries: set[str] = set()
    section = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section == "resolver-logic":
            entries.add(line.split(":", 1)[0].strip())
    return entries


allowlisted = parse_allowlist(allowlist_path)
surfaces = [line.strip() for line in surfaces_raw.splitlines() if line.strip()]

dp_signal = re.compile(
    r"(_by_dp\b|resolve_by_dp\b|DP-\[|DP-\*|\^DP-|design-plans/DP-|design-plans/.+DP-|active_dp_containers|dp_task_stems)",
    re.IGNORECASE,
)
surface_signal = re.compile(
    r"(resolve|resolver|task-md|source|container|containers|changelog|drift|report|marker|verification)",
    re.IGNORECASE,
)
counterpart_signal = re.compile(
    r"(companies/|JIRA[-_ ]?Epic|jira_epic|resolve_by_jira|source_key_for_container|SOURCE_ID_PATTERN|resolver-compatible|resolve_task_md|\[A-Z\]\[A-Z0-9\]\+\?-\[0-9\]|[A-Z]\[A-Z0-9\].*\[TV\])",
    re.IGNORECASE,
)
delegated_module_signal = re.compile(
    r"(?m)^\s*(?:exec\s+)?(?:python3|\"?\$[A-Z_]+\"?)\b[^\n#]*?"
    r"(lib/[A-Za-z0-9_.-]+\.py)",
)

errors: list[str] = []
scanned = 0


def shell_executable_text(text: str) -> str:
    executable: list[str] = []
    delimiter: str | None = None
    strip_tabs = False
    start = re.compile(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
    for line in text.splitlines():
        if delimiter is not None:
            candidate = line.lstrip("\t") if strip_tabs else line
            if candidate.strip() == delimiter:
                delimiter = None
                strip_tabs = False
            continue
        if line.lstrip().startswith("#"):
            continue
        executable.append(line)
        match = start.search(line)
        if match:
            strip_tabs = match.group(1) == "-"
            delimiter = match.group(3)
    return "\n".join(executable)

for surface in surfaces:
    rel = surface
    path = Path(surface)
    if not path.is_absolute():
        path = root / surface
    if not path.exists():
        continue
    scanned += 1
    if rel in allowlisted or str(path) in allowlisted:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"{prefix} failed to read {surface}: {exc}", file=sys.stderr)
        sys.exit(3)
    # A migrated shell shim and the Python module it delegates to form one
    # validator surface. Evaluate their combined authority so moving structured
    # logic out of the shim cannot create a false DP-only asymmetry.
    delegated_text: list[str] = []
    # Only executable command lines establish delegation. A comment mentioning
    # lib/counterpart.py must not be able to import a parity counterpart into
    # an otherwise DP-only shell surface.
    executable_text = shell_executable_text(text)
    for relative_module in sorted(set(delegated_module_signal.findall(executable_text))):
        module_path = path.parent / relative_module
        if not module_path.is_file():
            continue
        try:
            delegated_text.append(module_path.read_text(encoding="utf-8"))
        except OSError as exc:
            print(f"{prefix} failed to read delegated module {module_path}: {exc}", file=sys.stderr)
            sys.exit(3)
    if delegated_text:
        text = "\n".join([text, *delegated_text])
    if not dp_signal.search(text):
        continue
    if not surface_signal.search(text):
        continue
    if counterpart_signal.search(text):
        continue
    errors.append(
        f"POLARIS_DP_KEYED_SOURCE_ASYMMETRY: {rel} has DP-keyed resolver/reader/container logic "
        "without a companies/JIRA-Epic counterpart; add the counterpart or document an inherent "
        "DP-only surface under [resolver-logic] in scripts/lib/spec-source-parity-allowlist.txt"
    )

if errors:
    print(f"{prefix} FAIL: DP-keyed source asymmetry", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(2)

print(f"{prefix} PASS: {scanned} resolver/reader/container surface(s) inspected")
PY
