#!/usr/bin/env bash
# Cost floor: how many files does the flow force into existence?
#
# The new spine claims a source is one frozen block plus one living document.
# That claim is only worth something if it can be measured, so this check counts
# the artifacts a piece of work was *forced* to produce — "forced" meaning the
# flow does not complete without it — and asserts the count stays at the floor:
#
#   code work  -> at most 2 (the living document and the code)
#   docs work  -> at most 1 (the living document)
#
# Anything a person chose to write is not counted. The number under scrutiny is
# the toll the process charges, not the volume of work someone did.
#
# The second half of the check names the old layers explicitly. A forced
# task.md, completion-gate marker, ac-verification marker, task snapshot,
# ledger or verify report means the flow still runs on the machine the spine was
# built to replace, and that is a failure even when the count happens to fit.
#
# Usage:
#   check-spine-cost-floor.sh --inventory <path.json>
#
# Inventory shape:
#   {
#     "kind": "code" | "docs",
#     "artifacts": [
#       {"path": "…", "forced": true, "reason": "流程不產生它就走不完"},
#       {"path": "…", "forced": false}
#     ]
#   }

set -uo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  check-spine-cost-floor.sh --inventory <path.json>
EOF
}

INVENTORY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory) INVENTORY="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$INVENTORY" ]] || { usage; exit 2; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

if [[ ! -f "$INVENTORY" ]]; then
  echo "POLARIS_SPINE_COST_FLOOR_INVENTORY_MISSING" >&2
  echo "no inventory at $INVENTORY" >&2
  exit 2
fi

python3 - "$INVENTORY" <<'PY'
import json
import re
import sys

path = sys.argv[1]

# The floor comes straight from the assertion: one living document, plus the
# code when there is code.
FLOOR = {"code": 2, "docs": 1}

# The layers the spine exists to stop depending on. A forced artifact matching
# any of these means the old machine is still load-bearing.
LEGACY_PATTERNS = (
    (r"(^|/)tasks/[TV][0-9]+/index\.md$", "task.md schema chain"),
    (r"(^|/)tasks/[TV][0-9]+\.md$", "task.md schema chain"),
    (r"\.polaris/evidence/completion-gate/", "completion-gate marker layer"),
    (r"\.polaris/evidence/ac-verification/", "ac-verification marker layer"),
    (r"\.polaris/evidence/task-snapshot/", "task-snapshot marker layer"),
    # Anchored on where the old ledger actually lives. It was once a bare
    # `-ledger\.json$`, which also matched the spine's own
    # `.spine/measurement-ledger.json` — the first real source measured got
    # told its own ledger was a layer it should stop depending on, and the
    # false positive fired before the count check, hiding the real number.
    (r"(^|/)artifacts/auto-pass/.*-ledger\.json$", "auto-pass ledger layer"),
    (r"(^|/)verify-report\.md$", "closeout chain"),
)


def fail(marker, message):
    print(marker, file=sys.stderr)
    print(message, file=sys.stderr)
    sys.exit(2)


try:
    data = json.load(open(path, encoding="utf-8"))
except (json.JSONDecodeError, OSError) as exc:
    fail("POLARIS_SPINE_COST_FLOOR_INVENTORY_MISSING",
         f"inventory at {path} is not readable JSON: {exc}")

kind = data.get("kind")
if kind not in FLOOR:
    fail("POLARIS_SPINE_COST_FLOOR_BAD_KIND",
         f"kind must be one of {sorted(FLOOR)} (got {kind!r})")

artifacts = data.get("artifacts")
if not isinstance(artifacts, list):
    fail("POLARIS_SPINE_COST_FLOOR_INVENTORY_MISSING",
         f"inventory at {path} has no artifacts list")

forced = [a for a in artifacts if a.get("forced")]

unjustified = [a["path"] for a in forced if not str(a.get("reason", "")).strip()]
if unjustified:
    fail("POLARIS_SPINE_COST_FLOOR_UNJUSTIFIED",
         "every forced artifact has to say why the flow cannot finish without it:\n"
         + "\n".join(f"  {p}" for p in unjustified))

legacy = []
for artifact in forced:
    for pattern, layer in LEGACY_PATTERNS:
        if re.search(pattern, artifact["path"]):
            legacy.append((artifact["path"], layer))
            break
if legacy:
    fail("POLARIS_SPINE_COST_FLOOR_LEGACY_ARTIFACT_FORCED",
         "the flow still cannot finish without the layers the spine replaces:\n"
         + "\n".join(f"  {p}  ({layer})" for p, layer in legacy))

limit = FLOOR[kind]
if len(forced) > limit:
    fail("POLARIS_SPINE_COST_FLOOR_EXCEEDED",
         f"{kind} work forced {len(forced)} files into existence, floor is {limit}:\n"
         + "\n".join(f"  {a['path']}" for a in forced))

optional = len(artifacts) - len(forced)
print(f"PASS: spine cost floor — {kind} work forced {len(forced)}/{limit} file(s) "
      f"({optional} produced by choice, not counted)")
PY
