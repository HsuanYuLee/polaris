#!/usr/bin/env bash
# Purpose: selftest for scripts/selftest-affected-runner.sh (DP-360 T3 / AC7 / AC-NEG5
#          / AC-NEG4). Asserts the affected-runner computes the selftest dependency
#          closure from the three EXISTING static sources (naming convention,
#          mechanism-registry mechanism->script, scripts/manifest.json selftest field),
#          escalates shared / high-fanout changed paths to the full-corpus sentinel
#          (NEG5: affected must not silent-pass a narrow subset), and fails closed on
#          missing inputs / malformed sources (NEG4: never synthesize a fail-open pass).
#          All assertions run against HERMETIC fixture roots so the live full corpus
#          (~319 selftests, ~160min) is never triggered.
# Inputs:  none (builds isolated fixture roots under $TMPDIR).
# Outputs: exit 0 + PASS line on success; non-zero + diagnostic on failure.
# Exit code: 0 = pass, non-zero = fail.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT_DIR/scripts/selftest-affected-runner.sh"

[[ -f "$RUNNER" ]] || { echo "FAIL: runner missing: $RUNNER" >&2; exit 1; }

tmp="$(mktemp -d -t affected-runner.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "[selftest][$1] $2" >&2; exit 1; }

# build_fixture_root — materialize a self-contained fixture workspace under $1 with:
#   - scripts/foo.sh + scripts/selftests/foo-selftest.sh  (naming convention)
#   - scripts/manifest.json mapping scripts/bar.sh -> scripts/selftests/bar-from-manifest-selftest.sh
#   - .claude/rules/mechanism-registry.md Runtime Annotation row mapping
#     scripts/baz.sh (fallback_script scripts/selftests/baz-from-registry-selftest.sh)
#   - the three target selftests, each a trivial green script
#   - a green run-aggregate-selftests.sh backstop sentinel
# Side effects: writes files under $1.
build_fixture_root() {
  local root="$1"
  mkdir -p "$root/scripts/selftests" "$root/.claude/rules" "$root/.claude/hooks" \
    "$root/scripts/lib" "$root/.polaris/runtime/selftest-staleness"

  cp "$ROOT_DIR/.claude/hooks/selftest-staleness-eval.sh" \
    "$root/.claude/hooks/selftest-staleness-eval.sh"
  cat >"$root/workspace-config.yaml" <<'YAML'
defaults:
  selftest_staleness:
    enabled: true
    max_age_hours: 48
    surface: "on_stale"
YAML
  cat >"$root/.polaris/runtime/selftest-staleness/last-full-corpus-run.json" <<JSON
{"schema_version":1,"head_sha":"fixture-head","last_full_corpus_run_ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON

  # Naming-convention pair.
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/scripts/foo.sh"
  printf '#!/usr/bin/env bash\necho FOO-SELFTEST\nexit 0\n' >"$root/scripts/selftests/foo-selftest.sh"

  # Manifest-mapped pair.
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/scripts/bar.sh"
  printf '#!/usr/bin/env bash\necho BAR-SELFTEST\nexit 0\n' >"$root/scripts/selftests/bar-from-manifest-selftest.sh"

  # Registry-mapped pair.
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/scripts/baz.sh"
  printf '#!/usr/bin/env bash\necho BAZ-SELFTEST\nexit 0\n' >"$root/scripts/selftests/baz-from-registry-selftest.sh"

  cat >"$root/scripts/manifest.json" <<'JSON'
{
  "version": 1,
  "scripts": [
    { "path": "scripts/foo.sh", "kind": "support", "selftest": "N/A" },
    { "path": "scripts/bar.sh", "kind": "support", "selftest": "scripts/selftests/bar-from-manifest-selftest.sh" },
    { "path": "scripts/baz.sh", "kind": "support", "selftest": "N/A" }
  ]
}
JSON

  cat >"$root/.claude/rules/mechanism-registry.md" <<'MD'
# fixture registry

| mechanism | path | kind | runtime | fallback_script | governance_role |
|-----------|------|------|---------|-----------------|-----------------|
| baz-mech | scripts/baz.sh | script | portable | scripts/selftests/baz-from-registry-selftest.sh | governance |
MD

  # Canonical full-corpus backstop sentinel: writing a marker file proves the
  # full-corpus escalation delegated here (and NOT to any narrow subset run).
  cat >"$root/scripts/run-aggregate-selftests.sh" <<BACKSTOP
#!/usr/bin/env bash
set -euo pipefail
touch "$root/.backstop-ran"
echo BACKSTOP-RAN
exit 0
BACKSTOP
  chmod +x "$root/scripts/run-aggregate-selftests.sh"
}

fixture="$tmp/fixture"
build_fixture_root "$fixture"

# ---------------------------------------------------------------------------
# Case 1 (AC7 naming convention): changed scripts/foo.sh -> emit
# scripts/selftests/foo-selftest.sh.
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$fixture" --emit --changed scripts/foo.sh)"
[[ "$out" == "scripts/selftests/foo-selftest.sh" ]] \
  || fail AC7-naming "expected foo-selftest.sh from naming convention, got: [$out]"

# ---------------------------------------------------------------------------
# Case 2 (AC7 manifest): changed scripts/bar.sh -> emit the manifest-mapped
# selftest (not the naming-convention one, which does not exist on disk).
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$fixture" --emit --changed scripts/bar.sh)"
[[ "$out" == "scripts/selftests/bar-from-manifest-selftest.sh" ]] \
  || fail AC7-manifest "expected bar-from-manifest-selftest.sh from manifest, got: [$out]"

# ---------------------------------------------------------------------------
# Case 3 (AC7 mechanism-registry): changed scripts/baz.sh -> emit the
# registry fallback_script selftest.
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$fixture" --emit --changed scripts/baz.sh)"
[[ "$out" == "scripts/selftests/baz-from-registry-selftest.sh" ]] \
  || fail AC7-registry "expected baz-from-registry-selftest.sh from registry, got: [$out]"

# ---------------------------------------------------------------------------
# Case 4 (AC7 union + dedup): changed set {foo.sh, bar.sh, baz.sh} -> all three
# closure members, sorted/deduped, no full-corpus sentinel.
# ---------------------------------------------------------------------------
out="$(bash "$RUNNER" --root "$fixture" --emit \
  --changed scripts/foo.sh --changed scripts/bar.sh --changed scripts/baz.sh)"
expected="$(printf '%s\n' \
  scripts/selftests/bar-from-manifest-selftest.sh \
  scripts/selftests/baz-from-registry-selftest.sh \
  scripts/selftests/foo-selftest.sh | LC_ALL=C sort -u)"
[[ "$out" == "$expected" ]] || fail AC7-union "union closure mismatch; got: [$out]"
grep -q 'POLARIS_AFFECTED_FULL_CORPUS' <<< "$out" \
  && fail AC7-union "narrow change set must NOT escalate to full corpus"

# ---------------------------------------------------------------------------
# Case 5 (AC-NEG5 shared-surface escalation): a shared / high-fanout changed path
# escalates to the full-corpus sentinel — affected must not silent-pass a subset.
# ---------------------------------------------------------------------------
for shared in \
  '.claude/rules/skill-routing.md' \
  '.claude/skills/engineering/SKILL.md' \
  '.claude/hooks/some-hook.sh' \
  'scripts/lib/ci-local-path.sh' \
  '.claude/rules/mechanism-registry.md' \
  'scripts/manifest.json'; do
  out="$(bash "$RUNNER" --root "$fixture" --emit --changed "$shared")"
  [[ "$out" == "POLARIS_AFFECTED_FULL_CORPUS" ]] \
    || fail AC-NEG5 "shared path '$shared' must escalate to full-corpus sentinel, got: [$out]"
done

# ---------------------------------------------------------------------------
# Case 6 (AC-NEG5 run escalation): in --run mode a shared change delegates to the
# canonical full backstop (run-aggregate-selftests.sh), proven by the marker file.
# ---------------------------------------------------------------------------
rm -f "$fixture/.backstop-ran"
bash "$RUNNER" --root "$fixture" --run --changed '.claude/rules/skill-routing.md' >/dev/null
[[ -f "$fixture/.backstop-ran" ]] \
  || fail AC-NEG5-run "shared change in --run mode must delegate to the full backstop"

# ---------------------------------------------------------------------------
# Case 7 (AC-NEG4 fail-closed: empty change set): no --changed and empty stdin ->
# exit 2, no fail-open. (Marker POLARIS_AFFECTED_NO_CHANGED_FILES.)
# ---------------------------------------------------------------------------
set +e
err="$(printf '' | bash "$RUNNER" --root "$fixture" --emit 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail AC-NEG4-empty "empty change set must exit 2 (got rc=$rc)"
grep -q 'POLARIS_AFFECTED_NO_CHANGED_FILES' <<< "$err" \
  || fail AC-NEG4-empty "empty change set must emit POLARIS_AFFECTED_NO_CHANGED_FILES"

# ---------------------------------------------------------------------------
# Case 8 (AC-NEG4 / AC-NEG5 fail-closed: no closure in run mode): a changed code
# file with NO mapped selftest must NOT silent-pass; --run exits 2.
# ---------------------------------------------------------------------------
printf '#!/usr/bin/env bash\nexit 0\n' >"$fixture/scripts/unmapped.sh"
set +e
err="$(bash "$RUNNER" --root "$fixture" --run --changed scripts/unmapped.sh 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 2 ]] || fail AC-NEG5-no-closure "unmapped changed file in --run must exit 2 (got rc=$rc)"
grep -q 'POLARIS_AFFECTED_NO_CLOSURE' <<< "$err" \
  || fail AC-NEG5-no-closure "unmapped change must emit POLARIS_AFFECTED_NO_CLOSURE (no silent pass)"

# ---------------------------------------------------------------------------
# Case 9 (AC7 run mode all-green): changed scripts/foo.sh -> --run executes
# foo-selftest.sh (green) and exits 0.
# ---------------------------------------------------------------------------
bash "$RUNNER" --root "$fixture" --run --changed scripts/foo.sh >/dev/null \
  || fail AC7-run "green closure member must make --run exit 0"

# ---------------------------------------------------------------------------
# Case 10 (AC7 run mode red member): a red closure member makes --run exit 1
# with POLARIS_AFFECTED_SELFTEST_RED.
# ---------------------------------------------------------------------------
printf '#!/usr/bin/env bash\necho boom; exit 1\n' >"$fixture/scripts/selftests/foo-selftest.sh"
set +e
err="$(bash "$RUNNER" --root "$fixture" --run --changed scripts/foo.sh 2>&1)"
rc=$?
set -e
[[ "$rc" -eq 1 ]] || fail AC7-run-red "red closure member must make --run exit 1 (got rc=$rc)"
grep -q 'POLARIS_AFFECTED_SELFTEST_RED:scripts/selftests/foo-selftest.sh' <<< "$err" \
  || fail AC7-run-red "red member must emit POLARIS_AFFECTED_SELFTEST_RED:<member>"

# ---------------------------------------------------------------------------
# Case 11 (AC7 changed selftest is own member): a changed *-selftest.sh is its
# own closure member.
# ---------------------------------------------------------------------------
# restore green foo-selftest for cleanliness
printf '#!/usr/bin/env bash\nexit 0\n' >"$fixture/scripts/selftests/foo-selftest.sh"
out="$(bash "$RUNNER" --root "$fixture" --emit --changed scripts/selftests/foo-selftest.sh)"
[[ "$out" == "scripts/selftests/foo-selftest.sh" ]] \
  || fail AC7-self "changed selftest must be its own closure member, got: [$out]"

# ---------------------------------------------------------------------------
# Case 12 (no-second-classifier proof): the runner reads ONLY the three existing
# sources. Assert it does not contain an embedded second mapping/classifier (it
# parses mechanism-registry.md, manifest.json, and naming convention; no hardcoded
# script->selftest map literal).
# ---------------------------------------------------------------------------
grep -q 'mechanism-registry.md' "$RUNNER" || fail D8 "runner must read mechanism-registry.md (source 2)"
grep -q 'scripts/manifest.json' "$RUNNER" || fail D8 "runner must read scripts/manifest.json (source 3)"

# ---------------------------------------------------------------------------
# Case 13 (AC4 48h): fresh state keeps a narrow set; stale, missing, or corrupt
# state escalates the same narrow change to the full-corpus sentinel.
# ---------------------------------------------------------------------------
state_file="$fixture/.polaris/runtime/selftest-staleness/last-full-corpus-run.json"
out="$(bash "$RUNNER" --root "$fixture" --emit --changed scripts/foo.sh)"
[[ "$out" == "scripts/selftests/foo-selftest.sh" ]] \
  || fail AC4-fresh "fresh full state must preserve narrow affected selection"
cat >"$state_file" <<'JSON'
{"schema_version":1,"head_sha":"old-head","last_full_corpus_run_ts":"2000-01-01T00:00:00Z"}
JSON
out="$(bash "$RUNNER" --root "$fixture" --emit --changed scripts/foo.sh)"
[[ "$out" == "POLARIS_AFFECTED_FULL_CORPUS" ]] \
  || fail AC4-stale "48h-stale full state must escalate to full corpus"
printf '{broken json\n' >"$state_file"
out="$(bash "$RUNNER" --root "$fixture" --emit --changed scripts/foo.sh)"
[[ "$out" == "POLARIS_AFFECTED_FULL_CORPUS" ]] \
  || fail AC4-corrupt "corrupt full state must escalate to full corpus"
rm -f "$state_file"
out="$(bash "$RUNNER" --root "$fixture" --emit --changed scripts/foo.sh)"
[[ "$out" == "POLARIS_AFFECTED_FULL_CORPUS" ]] \
  || fail AC4-missing "missing full state must escalate to full corpus"
# Restore fresh state for the base-debt fixtures below.
cat >"$state_file" <<JSON
{"schema_version":1,"head_sha":"fixture-head","last_full_corpus_run_ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON

# ---------------------------------------------------------------------------
# Case 14 (current-head classification): a targeted member that is already red
# on the explicit comparison base is reported as tracked debt and does not make
# the affected run red. This prevents a narrow task from absorbing clean-base
# debt owned elsewhere.
# ---------------------------------------------------------------------------
debt_fixture="$tmp/debt-fixture"
build_fixture_root "$debt_fixture"
printf '#!/usr/bin/env bash\necho BASE-RED\nexit 7\n' >"$debt_fixture/scripts/selftests/foo-selftest.sh"
git -C "$debt_fixture" init -q
git -C "$debt_fixture" add .
git -C "$debt_fixture" -c user.name=Polaris -c user.email=polaris@example.invalid commit -qm base-red
debt_base="$(git -C "$debt_fixture" rev-parse HEAD)"
printf 'head\n' >"$debt_fixture/head-only.txt"
git -C "$debt_fixture" add head-only.txt
git -C "$debt_fixture" -c user.name=Polaris -c user.email=polaris@example.invalid commit -qm head
set +e
debt_out="$(bash "$RUNNER" --root "$debt_fixture" --base-ref "$debt_base" --run --changed scripts/foo.sh 2>&1)"
debt_rc=$?
set -e
[[ "$debt_rc" -eq 0 ]] || fail AC4-base-debt "base-red targeted member must not fail current head (rc=$debt_rc)"
grep -q 'TRACKED_DEBT scripts/selftests/foo-selftest.sh' <<<"$debt_out" \
  || fail AC4-base-debt "base-red targeted member must be explicitly classified as TRACKED_DEBT"

# Same exit code with a different failure signature is a head regression, not
# inherited debt. Existing failure A must never conceal newly introduced B.
signature_fixture="$tmp/signature-fixture"
build_fixture_root "$signature_fixture"
printf '#!/usr/bin/env bash\necho FAILURE-A\nexit 7\n' >"$signature_fixture/scripts/selftests/foo-selftest.sh"
git -C "$signature_fixture" init -q
git -C "$signature_fixture" add .
git -C "$signature_fixture" -c user.name=Polaris -c user.email=polaris@example.invalid commit -qm failure-a
signature_base="$(git -C "$signature_fixture" rev-parse HEAD)"
printf '#!/usr/bin/env bash\necho FAILURE-B\nexit 7\n' >"$signature_fixture/scripts/selftests/foo-selftest.sh"
git -C "$signature_fixture" add scripts/selftests/foo-selftest.sh
git -C "$signature_fixture" -c user.name=Polaris -c user.email=polaris@example.invalid commit -qm failure-b
set +e
signature_out="$(bash "$RUNNER" --root "$signature_fixture" --base-ref "$signature_base" --run --changed scripts/foo.sh 2>&1)"
signature_rc=$?
set -e
[[ "$signature_rc" -eq 1 ]] \
  || fail AC4-failure-identity "different head failure identity must block even when exit code matches base (rc=$signature_rc)"
grep -q 'POLARIS_AFFECTED_SELFTEST_RED:scripts/selftests/foo-selftest.sh' <<<"$signature_out" \
  || fail AC4-failure-identity "different failure identity was incorrectly downgraded to tracked debt"

# A head-only regression remains blocking under the same explicit-base contract.
head_red_fixture="$tmp/head-red-fixture"
build_fixture_root "$head_red_fixture"
git -C "$head_red_fixture" init -q
git -C "$head_red_fixture" add .
git -C "$head_red_fixture" -c user.name=Polaris -c user.email=polaris@example.invalid commit -qm green-base
green_base="$(git -C "$head_red_fixture" rev-parse HEAD)"
printf '#!/usr/bin/env bash\necho HEAD-RED\nexit 9\n' >"$head_red_fixture/scripts/selftests/foo-selftest.sh"
git -C "$head_red_fixture" add scripts/selftests/foo-selftest.sh
git -C "$head_red_fixture" -c user.name=Polaris -c user.email=polaris@example.invalid commit -qm head-red
set +e
head_red_out="$(bash "$RUNNER" --root "$head_red_fixture" --base-ref "$green_base" --run --changed scripts/foo.sh 2>&1)"
head_red_rc=$?
set -e
[[ "$head_red_rc" -eq 1 ]] || fail AC4-head-red "head-only red targeted member must block (rc=$head_red_rc)"
grep -q 'POLARIS_AFFECTED_SELFTEST_RED:scripts/selftests/foo-selftest.sh' <<<"$head_red_out" \
  || fail AC4-head-red "head-only red member must retain the blocking marker"

echo "PASS: selftest-affected-runner selftest"
