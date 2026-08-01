#!/usr/bin/env bash
# Purpose: Verify the frozen fence seals, detects tampering, and fails closed.
# Inputs: Hermetic Markdown fixtures plus the repo's hand-signed 05-redesign.md.
# Outputs: PASS when equal-length edits stop, missing seals stop, unchanged
#          fences pass, seal round-trips, duplicate ids are refused at both seal
#          and verify time, and free-form ids are accepted.

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
NOGIT="$(mktemp -d)"
trap 'rm -rf "$WORK" "$NOGIT"' EXIT

# verify compares against git history by default, so fixtures need a resolvable
# HEAD. Files written but never committed read as new fences, which is the
# intended "nothing to compare against" path.
git -C "$WORK" init -q .
git -C "$WORK" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m base

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

# --- Case 5: any id shape seals, as long as ids are distinct -----------------
# There is no format rule. Nothing downstream reads an id's shape, and no frozen
# assertion asks for one; a format rule would be a convention the tool invented
# for itself. This case is the positive direction of that decision.
write_fixture "$WORK/free-form-ids.md" A-P1 B-N7
bash "$FENCE" seal "$WORK/free-form-ids.md" --by tester >/dev/null \
  || fail "seal refused a fence whose ids merely differ from an old convention"
bash "$FENCE" verify "$WORK/free-form-ids.md" >/dev/null \
  || fail "a fence sealed with free-form ids failed verify"

# --- Case 6: duplicate ids fail closed at both seal and verify ---------------
# The measurement ledger looks entries up by id equality, so a collision would
# let an unsanctioned command match a sibling's sanctioned entry (defeats A-N2).
write_fixture "$WORK/dupe-ids.md" A-P1 A-P1
out="$(bash "$FENCE" seal "$WORK/dupe-ids.md" --by tester 2>&1)" && \
  fail "seal accepted duplicate assertion ids"
grep -Fq "POLARIS_FROZEN_FENCE_ASSERTION_ID_DUPLICATE" <<<"$out" \
  || fail "seal rejection did not emit the duplicate-id marker; got: $out"
grep -Fq "A-P1" <<<"$out" || fail "seal rejection did not name the duplicated id"
grep -Fq "frozen_by:" "$WORK/dupe-ids.md" \
  && fail "seal wrote a seal despite refusing to sign"

# Unlike a format rule, this one is about artifact correctness, so it also has to
# hold at verify time — a collision introduced after signing must not slip through.
write_fixture "$WORK/dupe-after-seal.md" A-P1 A-N1
bash "$FENCE" seal "$WORK/dupe-after-seal.md" --by tester >/dev/null \
  || fail "seal failed on a distinct-id fixture"
python3 - "$WORK/dupe-after-seal.md" <<'PY'
import sys
path = sys.argv[1]
body = open(path, encoding="utf-8").read().replace("**A-N1 second", "**A-P1 second")
open(path, "w", encoding="utf-8").write(body)
PY
assert_marker "duplicate id at verify" POLARIS_FROZEN_FENCE_ASSERTION_ID_DUPLICATE \
  bash "$FENCE" verify "$WORK/dupe-after-seal.md"

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

# --- Case 11: re-sealing a tampered fence does not survive git history -------
# The seal alone only proves the fence and its frontmatter agree. A writer that
# edits the fence and re-seals in one breath gets a green verify, and `--by` is
# just a string an agent can supply. --against compares against a ref, which a
# writer inside the repo cannot rewrite in place.
GITWORK="$NOGIT/git-history"
mkdir -p "$GITWORK"
git -C "$GITWORK" init -q .
write_fixture "$GITWORK/tracked.md" A-P1 A-N1
bash "$FENCE" seal "$GITWORK/tracked.md" --by human >/dev/null \
  || fail "seal failed on the history fixture"
git -C "$GITWORK" add -A
git -C "$GITWORK" -c user.email=t@example.com -c user.name=t commit -qm base

bash "$FENCE" verify "$GITWORK/tracked.md" --against HEAD >/dev/null \
  || fail "an unchanged fence failed the history comparison"

python3 - "$GITWORK/tracked.md" <<'PY'
import sys
path = sys.argv[1]
body = open(path, encoding="utf-8").read().replace("the flow stops.", "the flow continues.")
open(path, "w", encoding="utf-8").write(body)
PY
bash "$FENCE" seal "$GITWORK/tracked.md" --by some-agent >/dev/null \
  || fail "re-seal unexpectedly failed; the case needs the seal itself to look consistent"
# The seal is now internally consistent again — that is precisely the attack. It
# has to fail anyway, with no flag asked for: freezing is committing.
assert_marker "tampered then re-sealed" POLARIS_FROZEN_FENCE_CHANGED_SINCE_REF \
  bash "$FENCE" verify "$GITWORK/tracked.md"

# Committing the change is what authorises it, and it is authorised because it is
# now a diff someone can read.
git -C "$GITWORK" add -A
git -C "$GITWORK" -c user.email=t@example.com -c user.name=t commit -qm "re-sign fence"
bash "$FENCE" verify "$GITWORK/tracked.md" >/dev/null \
  || fail "a committed re-signature still failed verify"

# --- Case 12: no history means no claim ---------------------------------------
# A fence outside git must not pass the comparison by default; that would let an
# untracked location silently buy back the exemption this check exists to remove.
write_fixture "$NOGIT/untracked.md" A-P1 A-N1
bash "$FENCE" seal "$NOGIT/untracked.md" --by human >/dev/null
assert_marker "fence outside git" POLARIS_FROZEN_FENCE_HISTORY_UNAVAILABLE \
  bash "$FENCE" verify "$NOGIT/untracked.md"

echo "PASS: frozen-assertion-fence-selftest.sh"
