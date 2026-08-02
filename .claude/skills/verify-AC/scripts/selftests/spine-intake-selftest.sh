#!/usr/bin/env bash
# Purpose: Verify the spine's on-ramp asks for a filing decision when a piece of
#          engineering arrives, and reports the station instead when one is already
#          past the first gate.
# Inputs:  Hermetic sources/ fixtures under mktemp.
# Outputs: PASS when a cold project gets the full on-ramp, an open source at
#          engineering or verify-ac gets the station line instead, a source still at refinement
#          or already converged does not suppress the on-ramp, a slash command
#          is skipped, and a state written before stations is not read as an
#          open one.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

ROOT_DIR="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
HOOK="$ROOT_DIR/.claude/hooks/spine-intake.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Description: run the hook against a fixture project and echo what it injects.
# Args: $1 = project dir, $2 = the user's message
run_hook() {
  CLAUDE_PROJECT_DIR="$1" bash "$HOOK" <<<"$(python3 -c '
import json, sys
print(json.dumps({"user_prompt": sys.argv[1]}))' "$2")"
}

# Description: write a loop state for one source inside a fixture project.
# Args: $1 = project dir, $2 = source name, $3 = station ("" to omit the field),
#       $4 = status
make_source() {
  local proj="$1" name="$2" station="$3" status="$4"
  mkdir -p "$proj/sources/$name/.spine"
  python3 - "$proj/sources/$name/.spine/loop-state.json" "$station" "$status" <<'PY'
import json, sys
path, station, status = sys.argv[1:4]
payload = {"schema_version": 2, "producer": "spine-loop-state.sh",
           "max_rounds": 3, "rounds": [], "status": status}
if station:
    payload["station"] = station
json.dump(payload, open(path, "w"), ensure_ascii=False)
PY
}

echo "spine-intake selftest"

# A cold project has nothing in flight, so every message is a piece of work
# arriving and the filing decision is the point of the on-ramp.
cold="$WORK/cold"
mkdir -p "$cold"
out="$(run_hook "$cold" "幫我在 b2c-web 做 X")"
grep -q "先說出立案判斷" <<<"$out" || fail "a cold project did not get the on-ramp: $out"
echo "  ok  nothing in flight asks for the filing decision"

# Past the first gate, re-asking is a ritual: the decision was signed and the
# station is on disk. Asking again every turn also re-inserts the human decision
# point that running to the end is meant to remove.
for station in engineering verify-ac; do
  proj="$WORK/open-$station"
  make_source "$proj" DP-000-selftest "$station" open
  out="$(run_hook "$proj" "繼續")"
  grep -q "先說出立案判斷" <<<"$out" \
    && fail "an open source at $station still got the on-ramp: $out"
  grep -q "DP-000-selftest 在 $station" <<<"$out" \
    || fail "the hook did not name the source and station: $out"
done
echo "  ok  an open source reports its station instead of re-asking"

# refinement is the on-ramp itself, so a source sitting there must not suppress it.
proj="$WORK/at-refinement"
make_source "$proj" DP-000-selftest refinement open
grep -q "先說出立案判斷" <<<"$(run_hook "$proj" "另一件事")" \
  || fail "a source still at refinement wrongly suppressed the on-ramp"

# Delivered is what ends it, and only the station says that. A converged loop is
# a converged round, not a shipped source — reading it as delivered hands the
# on-ramp back to a source that is standing at verify-ac with its evidence complete,
# which is exactly what happened here before this line existed.
proj="$WORK/delivered"
make_source "$proj" DP-000-selftest delivered converged
grep -q "先說出立案判斷" <<<"$(run_hook "$proj" "下一件")" \
  || fail "a delivered source wrongly suppressed the on-ramp"
proj="$WORK/converged-at-verify-ac"
make_source "$proj" DP-000-selftest verify-ac converged
grep -q "DP-000-selftest 在 verify-ac" <<<"$(run_hook "$proj" "繼續")" \
  || fail "a converged loop at verify-ac was wrongly read as delivered"
echo "  ok  refinement and delivered do not count as in flight; a converged loop still does"

# A state written before stations existed does not know where it is, and
# guessing "engineering" from it would silence the on-ramp on a guess.
proj="$WORK/legacy"
make_source "$proj" DP-000-selftest "" open
grep -q "先說出立案判斷" <<<"$(run_hook "$proj" "某件事")" \
  || fail "a pre-stations state was read as an open source"
echo "  ok  a state that predates stations is not read as in flight"

# A slash command is already an explicit entry; saying so again is noise.
[[ -z "$(run_hook "$cold" "/assert 某件事")" ]] || fail "a slash command was not skipped"
echo "  ok  slash commands are skipped"

echo "PASS: spine-intake"
