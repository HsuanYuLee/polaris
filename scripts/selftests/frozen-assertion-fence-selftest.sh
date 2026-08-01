#!/usr/bin/env bash
# Purpose: Verify the frozen fence seals, detects tampering, and fails closed.
# Inputs: Hermetic Markdown fixtures plus the repo's hand-signed 05-redesign.md.
# Outputs: PASS when equal-length edits stop, missing seals stop, unchanged
#          fences pass, seal round-trips, non-canonical ids are refused at seal
#          time, and fences signed under historical ids still verify.

set -euo pipefail

for tool in python3 shasum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:$tool" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
done

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FENCE="$ROOT_DIR/scripts/frozen-assertion-fence.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_marker() {
  # Description: run a command expected to fail with a specific POLARIS marker.
  # Args: $1 = case name, $2 = expected marker, $3.. = command
  local name="$1" marker="$2"
  shift 2
  local out status
  out="$("$@" 2>&1)" && status=0 || status=$?
  [[ "$status" -ne 0 ]] || fail "$name unexpectedly passed"
  grep -Fq "$marker" <<<"$out" || fail "$name did not emit $marker; got: $out"
}

write_fixture() {
  # Description: write a two-assertion fence document with the given ids.
  # Args: $1 = target path, $2 = first id, $3 = second id
  cat > "$1" <<EOF
---
title: "fixture"
description: "hermetic fence fixture"
---

Prose before the fence.

<!-- POLARIS-FROZEN-A-BEGIN -->

- **$2 first assertion**：when X happens, Y follows.
- **$3 second assertion**：when Z happens, the flow stops.

<!-- POLARIS-FROZEN-A-END -->

Prose after the fence.
EOF
}

# --- Case 1: an unsealed fence stops -----------------------------------------
write_fixture "$WORK/unsealed.md" AC-P1 AC-N1
assert_marker "unsealed fence" POLARIS_FROZEN_FENCE_SEAL_MISSING \
  bash "$FENCE" verify "$WORK/unsealed.md"

# --- Case 2: seal round-trips, then verify passes ----------------------------
write_fixture "$WORK/sealed.md" AC-P1 AC-N1
bash "$FENCE" seal "$WORK/sealed.md" --by tester --at 2026-08-01T00:00:00Z >/dev/null \
  || fail "seal failed on a canonical fixture"
bash "$FENCE" verify "$WORK/sealed.md" >/dev/null \
  || fail "verify failed immediately after seal"

# Sealing writes only frontmatter, so re-sealing is idempotent on the hash.
first_hash="$(bash "$FENCE" hash "$WORK/sealed.md" --block A)"
bash "$FENCE" seal "$WORK/sealed.md" --by tester --at 2026-08-01T00:00:00Z >/dev/null
second_hash="$(bash "$FENCE" hash "$WORK/sealed.md" --block A)"
[[ "$first_hash" == "$second_hash" ]] \
  || fail "seal mutated the fence inner content ($first_hash != $second_hash)"

# --- Case 3: an equal-length edit inside the fence still stops ---------------
cp "$WORK/sealed.md" "$WORK/tampered.md"
python3 - "$WORK/tampered.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
before = text
# "stops" -> "halts": same character count, so a length check would miss it.
text = text.replace("the flow stops.", "the flow halts.")
assert text != before, "fixture edit did not apply"
assert len(text) == len(before), "fixture edit changed the length"
open(path, "w", encoding="utf-8").write(text)
PY
assert_marker "equal-length tamper" POLARIS_FROZEN_FENCE_HASH_MISMATCH \
  bash "$FENCE" verify "$WORK/tampered.md"

# --- Case 4: prose outside the fence does not trip the seal ------------------
cp "$WORK/sealed.md" "$WORK/outside.md"
printf '\nAn extra paragraph outside the fence.\n' >> "$WORK/outside.md"
bash "$FENCE" verify "$WORK/outside.md" >/dev/null \
  || fail "an edit outside the fence wrongly invalidated the seal"

# --- Case 5: seal refuses non-canonical assertion ids ------------------------
write_fixture "$WORK/legacy-ids.md" A-P1 A-N1
out="$(bash "$FENCE" seal "$WORK/legacy-ids.md" --by tester 2>&1)" && \
  fail "seal accepted non-canonical assertion ids"
grep -Fq "POLARIS_FROZEN_FENCE_ASSERTION_ID_NOT_CANONICAL" <<<"$out" \
  || fail "seal rejection did not emit the canonical-id marker; got: $out"
grep -Fq "A-P1" <<<"$out" || fail "seal rejection did not name the violating id A-P1"
grep -Fq "A-N1" <<<"$out" || fail "seal rejection did not name the violating id A-N1"
grep -Fq "frozen_by:" "$WORK/legacy-ids.md" \
  && fail "seal wrote a seal despite refusing to sign"

# --- Case 6: fences signed under historical ids still verify -----------------
# The canonical-id rule is a signing-time rule. Applying it at verify time would
# retroactively break every fence a human already signed.
write_fixture "$WORK/historical.md" A-P1 A-N1
historical_hash="$(bash "$FENCE" hash "$WORK/historical.md" --block A)"
python3 - "$WORK/historical.md" "$historical_hash" <<'PY'
import sys
path, digest = sys.argv[1:3]
lines = open(path, encoding="utf-8").read().split("\n")
end = lines.index("---", 1)
seal = ["frozen_by: historical-signer", "frozen_at: 2026-07-31T19:02:31Z",
        "assertions_hash:", f"  A: sha256:{digest}"]
open(path, "w", encoding="utf-8").write("\n".join(lines[:end] + seal + lines[end:]))
PY
bash "$FENCE" verify "$WORK/historical.md" >/dev/null \
  || fail "a fence signed under historical ids failed verify"

# --- Case 7: unterminated and missing fences fail closed ---------------------
printf -- '---\ntitle: "x"\n---\n\nno fence here\n' > "$WORK/no-fence.md"
assert_marker "no fence" POLARIS_FROZEN_FENCE_NO_BLOCK \
  bash "$FENCE" verify "$WORK/no-fence.md"

printf -- '---\ntitle: "x"\n---\n\n<!-- POLARIS-FROZEN-A-BEGIN -->\n- **AC-P1 x**：y\n' \
  > "$WORK/unterminated.md"
assert_marker "unterminated fence" POLARIS_FROZEN_FENCE_UNTERMINATED \
  bash "$FENCE" verify "$WORK/unterminated.md"

# --- Case 8: seal requires a human signer ------------------------------------
write_fixture "$WORK/nosigner.md" AC-P1 AC-N1
assert_marker "seal without signer" POLARIS_FROZEN_FENCE_SIGNER_MISSING \
  bash "$FENCE" seal "$WORK/nosigner.md"

# --- Case 9: the helper computes the documented sed|shasum recipe ------------
# A human signs by hand with the recipe printed in the frontmatter. If the
# helper drifted from that recipe, every hand-signed fence would break. This
# compares the helper against an independent execution of the recipe itself.
recipe_hash="$(
  sed -n '/<!-- POLARIS-FROZEN-A-BEGIN -->/,/<!-- POLARIS-FROZEN-A-END -->/p' "$WORK/sealed.md" \
    | sed '1d;$d' | shasum -a 256 | awk '{print $1}'
)"
helper_hash="$(bash "$FENCE" hash "$WORK/sealed.md" --block A)"
[[ "$recipe_hash" == "$helper_hash" ]] \
  || fail "helper hash ($helper_hash) drifted from the documented recipe ($recipe_hash)"

# --- Case 10: the fence already signed by a human still verifies -------------
# Specs live outside the git worktree (docs-manager/src/content/docs/specs is
# workspace-owned and gitignored), so this anchor only fires where the signed
# document is reachable.
SIGNED_ROOT="${POLARIS_WORKSPACE_ROOT:-$ROOT_DIR}"
SIGNED="$SIGNED_ROOT/docs-manager/src/content/docs/specs/framework-review-2026-07/05-redesign.md"
if [[ -f "$SIGNED" ]]; then
  bash "$FENCE" verify "$SIGNED" >/dev/null \
    || fail "the hand-signed 05-redesign.md fence did not verify against its recorded seal"
else
  echo "SKIP: hand-signed fence not reachable at $SIGNED" >&2
fi

echo "PASS: frozen-assertion-fence-selftest.sh"
