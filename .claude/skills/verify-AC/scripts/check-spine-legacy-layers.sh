#!/usr/bin/env bash
# Legacy layers: is the flow still load-bearing on the machine the spine replaced?
#
# A forced task.md, completion-gate marker, ac-verification marker, task
# snapshot, auto-pass ledger or verify report means the old layer is still
# required for the flow to finish. "Forced" means the flow does not complete
# without it; anything a person chose to write is not judged here.
#
# This used to also count the forced artifacts and refuse anything above a
# "cost floor" of 2. Three things were wrong with that at once, found 2026-08-03:
#
#   1. The comparison was `len(forced) > limit` — an upper bound. Every line of
#      prose called it a floor. A lower bound is satisfied by construction, so
#      the name described something that would have carried no information.
#   2. As an upper bound it was red on every real ticket ever measured: the
#      spine itself writes index.md, loop-state.json and measurement-ledger.json,
#      so the forced count is a constant 3 against a limit of 2.
#   3. Nobody called it, which is why (2) went unnoticed. It lived in prose only.
#
# Counting a constant carries no information. What does carry information is
# which layers are load-bearing, so that is all that is left.
#
# Usage:
#   check-spine-legacy-layers.sh --inventory <path.json>
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
  check-spine-legacy-layers.sh --inventory <path.json>
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
  echo "POLARIS_SPINE_LEGACY_INVENTORY_MISSING" >&2
  echo "no inventory at $INVENTORY" >&2
  exit 2
fi

python3 - "$INVENTORY" <<'PY'
import json
import re
import sys

path = sys.argv[1]

KINDS = ("code", "docs")

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
    fail("POLARIS_SPINE_LEGACY_INVENTORY_MISSING",
         f"inventory at {path} is not readable JSON: {exc}")

kind = data.get("kind")
if kind not in KINDS:
    fail("POLARIS_SPINE_LEGACY_BAD_KIND",
         f"kind must be one of {sorted(KINDS)} (got {kind!r})")

artifacts = data.get("artifacts")
if not isinstance(artifacts, list):
    fail("POLARIS_SPINE_LEGACY_INVENTORY_MISSING",
         f"inventory at {path} has no artifacts list")

forced = [a for a in artifacts if a.get("forced")]

unjustified = [a["path"] for a in forced if not str(a.get("reason", "")).strip()]
if unjustified:
    fail("POLARIS_SPINE_LEGACY_UNJUSTIFIED",
         "every forced artifact has to say why the flow cannot finish without it:\n"
         + "\n".join(f"  {p}" for p in unjustified))

# Judged against every artifact, not just the forced ones. The `forced` filter was
# inherited from the counting doctrine, and it made this half unable to fire at all:
# the enumerator only ever sets forced=True on index.md, the .spine state files and
# .changeset/*.md, so no legacy path could reach this loop. A check that cannot go
# red is worse than one nobody calls — it reports green and means nothing.
#
# Touching an old-layer artifact at all is the signal. A delivery that writes a
# tasks/T1/index.md or an auto-pass ledger is running the machine the spine
# replaced, whether or not the flow would technically finish without it.
legacy = []
for artifact in artifacts:
    for pattern, layer in LEGACY_PATTERNS:
        if re.search(pattern, artifact["path"]):
            legacy.append((artifact["path"], layer))
            break
if legacy:
    fail("POLARIS_SPINE_LEGACY_ARTIFACT_FORCED",
         "this delivery still produces the layers the spine replaces:\n"
         + "\n".join(f"  {p}  ({layer})" for p, layer in legacy))

# The count is reported, never judged. It is a constant the spine writes itself,
# so a threshold on it would only ever be theatre — but leaving the number unsaid
# would make "nothing was counted" and "the count was fine" look alike.
optional = len(artifacts) - len(forced)
print(f"PASS: no legacy layer is load-bearing — {kind} work forced {len(forced)} "
      f"file(s), {optional} more produced by choice (count reported, not judged)")
PY
