#!/usr/bin/env bash
# Purpose: Verify the generated-artifact discipline guard enumerates only new
# committed candidates, trusts the interface registry for classification, and
# requires every registered interface to have a wired freshness gate.
# Inputs: none; creates hermetic temporary git repositories.
# Outputs: PASS/FAIL assertions; exits non-zero on any contract regression.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/scripts/validate-generated-artifact-discipline.sh"
HANDBOOK="$ROOT/polaris-config/polaris-framework/handbook/generated-artifact-normalization.md"
PR_GATE="$ROOT/scripts/check-framework-pr-gate.sh"
MANIFEST="$ROOT/scripts/manifest.json"
WORKFLOW="$ROOT/.github/workflows/framework-pr.yml"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
ws="$tmpdir/workspace"
mkdir -p "$ws/scripts/lib" "$ws/.codex" "$ws/.github"

pass=0
fail=0

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected, got $actual)" >&2
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -Fq "$needle" "$file"; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (missing '$needle' in $file)" >&2
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -Fq "$needle" "$file"; then
    echo "FAIL: $label (unexpected '$needle' in $file)" >&2
    fail=$((fail + 1))
  else
    echo "PASS: $label"
    pass=$((pass + 1))
  fi
}

if [[ ! -x "$GUARD" ]]; then
  echo "FAIL: guard missing or not executable: $GUARD" >&2
  exit 1
fi

# AC12: the principle lives in the on-demand framework handbook and names all
# three dispositions. The guard deliberately does not decide real-consumer value.
assert_contains "handbook names committed interface" "committed interface" "$HANDBOOK"
assert_contains "handbook names gitignored regenerable artifact" "gitignored regenerable" "$HANDBOOK"
assert_contains "handbook names prohibited ceremony" "prohibited ceremony" "$HANDBOOK"
assert_contains "handbook keeps real-consumer judgment human-owned" "不判定 real consumer" "$HANDBOOK"
assert_contains "PR gate wires W20 blocking label" "W20 generated-artifact discipline" "$PR_GATE"
assert_contains "PR gate uses canonical guard" "scripts/validate-generated-artifact-discipline.sh" "$PR_GATE"
assert_contains "PR gate exposes test relocation seam" "POLARIS_VALIDATE_GENERATED_ARTIFACT_DISCIPLINE_BIN" "$PR_GATE"
assert_contains "workflow supplies committed PR base" 'POLARIS_FRAMEWORK_PR_BASE: ${{ github.event.pull_request.base.sha }}' "$WORKFLOW"
assert_contains "workflow fetches base history" "fetch-depth: 0" "$WORKFLOW"
assert_not_contains "workflow has no path allowlist blind spot" "paths:" "$WORKFLOW"

python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
actual = {row["path"] for row in manifest.get("generated_artifact_interfaces", [])}
expected = {
    "CLAUDE.md",
    "AGENTS.md",
    ".codex/AGENTS.md",
    ".github/copilot-instructions.md",
}
if actual != expected:
    raise SystemExit(f"runtime interface registry mismatch: expected={sorted(expected)} actual={sorted(actual)}")
PY
echo "PASS: shipped registry contains exactly four runtime interfaces"
pass=$((pass + 1))

cp "$GUARD" "$ws/scripts/validate-generated-artifact-discipline.sh"
cp "$ROOT/scripts/lib/validate_generated_artifact_discipline_1.py" "$ws/scripts/lib/"
cat >"$ws/scripts/compile-runtime-instructions.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$ws/scripts/compile-runtime-instructions.sh" "$ws/scripts/validate-generated-artifact-discipline.sh"

cat >"$ws/scripts/check-framework-pr-gate.sh" <<'SH'
#!/usr/bin/env bash
COMPILE_RUNTIME_INSTRUCTIONS="scripts/compile-runtime-instructions.sh"
run_gate "W11 runtime-instruction parity (compile --check)" "$COMPILE_RUNTIME_INSTRUCTIONS" --check
SH

cat >"$ws/scripts/manifest.json" <<'JSON'
{
  "generated_artifact_interfaces": [
    {
      "path": "CLAUDE.md",
      "classification": "committed_interface",
      "generator": "scripts/compile-runtime-instructions.sh",
      "freshness_gate": "scripts/compile-runtime-instructions.sh --check",
      "gate_entrypoint": "scripts/check-framework-pr-gate.sh",
      "gate_anchor": "run_gate \"W11 runtime-instruction parity (compile --check)\" \"$COMPILE_RUNTIME_INSTRUCTIONS\" --check"
    },
    {
      "path": "AGENTS.md",
      "classification": "committed_interface",
      "generator": "scripts/compile-runtime-instructions.sh",
      "freshness_gate": "scripts/compile-runtime-instructions.sh --check",
      "gate_entrypoint": "scripts/check-framework-pr-gate.sh",
      "gate_anchor": "run_gate \"W11 runtime-instruction parity (compile --check)\" \"$COMPILE_RUNTIME_INSTRUCTIONS\" --check"
    },
    {
      "path": ".codex/AGENTS.md",
      "classification": "committed_interface",
      "generator": "scripts/compile-runtime-instructions.sh",
      "freshness_gate": "scripts/compile-runtime-instructions.sh --check",
      "gate_entrypoint": "scripts/check-framework-pr-gate.sh",
      "gate_anchor": "run_gate \"W11 runtime-instruction parity (compile --check)\" \"$COMPILE_RUNTIME_INSTRUCTIONS\" --check"
    },
    {
      "path": ".github/copilot-instructions.md",
      "classification": "committed_interface",
      "generator": "scripts/compile-runtime-instructions.sh",
      "freshness_gate": "scripts/compile-runtime-instructions.sh --check",
      "gate_entrypoint": "scripts/check-framework-pr-gate.sh",
      "gate_anchor": "run_gate \"W11 runtime-instruction parity (compile --check)\" \"$COMPILE_RUNTIME_INSTRUCTIONS\" --check"
    }
  ]
}
JSON

cat >"$ws/.gitignore" <<'EOF'
ci-local.sh
docs-manager/src/content/docs/specs/**/artifacts/
.claude/memory/MEMORY.md
EOF
printf 'authoring source\n' >"$ws/source.txt"

git -C "$ws" init -q
git -C "$ws" config user.email "selftest@polaris.invalid"
git -C "$ws" config user.name "Polaris Selftest"
git -C "$ws" add scripts .gitignore source.txt
git -C "$ws" commit -qm "base"
base_sha="$(git -C "$ws" rev-parse HEAD)"

# AC13 / AC-NEG6: all four registered committed interfaces are candidates by
# header and pass because their shared freshness gate is wired.
for target in CLAUDE.md AGENTS.md .codex/AGENTS.md .github/copilot-instructions.md; do
  mkdir -p "$ws/$(dirname "$target")"
  printf '> Generated by `scripts/compile-runtime-instructions.sh`.\n' >"$ws/$target"
done
mkdir -p "$ws/docs"
printf 'This guide explains how a Generated by header is classified.\n' >"$ws/docs/guide.md"
printf 'Generated by a plain-text producer.\n' >"$ws/PLAIN.txt"
git -C "$ws" add CLAUDE.md AGENTS.md .codex/AGENTS.md .github/copilot-instructions.md docs/guide.md PLAIN.txt
git -C "$ws" commit -qm "add legal generated interfaces"
legal_sha="$(git -C "$ws" rev-parse HEAD)"

set +e
bash "$ws/scripts/validate-generated-artifact-discipline.sh" --root "$ws" --base "$base_sha" \
  >"$tmpdir/legal.out" 2>"$tmpdir/legal.err"
legal_rc=$?
set -e
assert_exit "unregistered plain-text Generated by header fails closed" 2 "$legal_rc"
assert_contains "plain-text Generated by line is a header candidate" \
  "POLARIS_GENERATED_ARTIFACT_DISCIPLINE_BLOCKED:path=PLAIN.txt reason=unregistered_interface" \
  "$tmpdir/legal.err"

# Remove the negative plain-header probe; the same commit range now contains
# only the four legal interfaces plus ordinary prose, so the positive case must pass.
git -C "$ws" rm -q PLAIN.txt
git -C "$ws" commit -qm "remove plain header negative probe"
set +e
bash "$ws/scripts/validate-generated-artifact-discipline.sh" --root "$ws" --base "$base_sha" \
  >"$tmpdir/legal-clean.out" 2>"$tmpdir/legal-clean.err"
legal_clean_rc=$?
set -e
assert_exit "four registered interfaces with wired freshness gate pass" 0 "$legal_clean_rc"
assert_contains "ordinary prose mentioning Generated by is not a header candidate" \
  "4 registered candidate(s)" "$tmpdir/legal-clean.out"
legal_sha="$(git -C "$ws" rev-parse HEAD)"

# The same committed HEAD must produce the same verdict under dirty overlays.
# Removing a candidate header and deleting registry rows only in the worktree
# cannot hide committed interfaces from the guard.
printf 'ordinary authoring text\n' >"$ws/CLAUDE.md"
printf '{"generated_artifact_interfaces": []}\n' >"$ws/scripts/manifest.json"
set +e
bash "$ws/scripts/validate-generated-artifact-discipline.sh" --root "$ws" --base "$base_sha" \
  >"$tmpdir/dirty-legal.out" 2>"$tmpdir/dirty-legal.err"
dirty_legal_rc=$?
set -e
assert_exit "dirty candidate and registry overlays do not change committed verdict" 0 "$dirty_legal_rc"
git -C "$ws" reset --hard -q "$legal_sha"

# AC-NEG6: ignored rebuild-on-demand files are outside the committed candidate
# set even when their contents carry a Generated by header.
mkdir -p "$ws/docs-manager/src/content/docs/specs/DP-X/artifacts" "$ws/.claude/memory"
printf '# Generated by local CI helper\n' >"$ws/ci-local.sh"
printf '# Generated by spec producer\n' >"$ws/docs-manager/src/content/docs/specs/DP-X/artifacts/evidence.md"
printf '# Generated by memory indexer\n' >"$ws/.claude/memory/MEMORY.md"
set +e
bash "$ws/scripts/validate-generated-artifact-discipline.sh" --root "$ws" --base "$base_sha" \
  >"$tmpdir/ignored.out" 2>"$tmpdir/ignored.err"
ignored_rc=$?
set -e
assert_exit "gitignored regenerable artifacts are not false positives" 0 "$ignored_rc"

# Renaming an existing tracked file creates a new tracked path with status R,
# not A. Moving it under .generated/ must still widen the candidate net.
mkdir -p "$ws/moved/.generated"
git -C "$ws" mv source.txt moved/.generated/from-source.txt
git -C "$ws" commit -qm "rename source into generated path"
set +e
bash "$ws/scripts/validate-generated-artifact-discipline.sh" --root "$ws" --base "$legal_sha" \
  >"$tmpdir/rename.out" 2>"$tmpdir/rename.err"
rename_rc=$?
set -e
assert_exit "rename into .generated path fails closed" 2 "$rename_rc"
assert_contains "rename bypass is enumerated by destination path" \
  "POLARIS_GENERATED_ARTIFACT_DISCIPLINE_BLOCKED:path=moved/.generated/from-source.txt reason=unregistered_interface" \
  "$tmpdir/rename.err"
git -C "$ws" reset --hard -q "$legal_sha"

# A commented copy of the registered invocation is prose, not executable wire.
# Even a dirty worktree restoration of the executable line cannot repair the
# committed HEAD verdict.
python3 - "$ws/scripts/check-framework-pr-gate.sh" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    'run_gate "W11 runtime-instruction parity (compile --check)" "$COMPILE_RUNTIME_INSTRUCTIONS" --check',
    '# run_gate "W11 runtime-instruction parity (compile --check)" "$COMPILE_RUNTIME_INSTRUCTIONS" --check',
)
open(path, "w", encoding="utf-8").write(text)
PY
git -C "$ws" add scripts/check-framework-pr-gate.sh
git -C "$ws" commit -qm "comment out freshness invocation"
commented_sha="$(git -C "$ws" rev-parse HEAD)"
sed -i.bak 's/^# run_gate /run_gate /' "$ws/scripts/check-framework-pr-gate.sh"
rm -f "$ws/scripts/check-framework-pr-gate.sh.bak"
set +e
bash "$ws/scripts/validate-generated-artifact-discipline.sh" --root "$ws" --base "$base_sha" \
  >"$tmpdir/commented.out" 2>"$tmpdir/commented.err"
commented_rc=$?
set -e
assert_exit "commented wire fails despite dirty executable overlay" 2 "$commented_rc"
assert_contains "commented wire reports structured unwired marker" \
  "reason=freshness_gate_unwired" "$tmpdir/commented.err"
git -C "$ws" reset --hard -q "$legal_sha"

# AC13 adversarial case: path/header heuristics only widen enumeration. An
# unregistered candidate must fail closed with a structured reason marker.
mkdir -p "$ws/tmp/.generated"
printf 'orphan\n' >"$ws/tmp/.generated/orphan.txt"
git -C "$ws" add -f tmp/.generated/orphan.txt
git -C "$ws" commit -qm "add unregistered generated artifact"
orphan_sha="$(git -C "$ws" rev-parse HEAD)"
# Dirty deletion and registry injection cannot hide an unregistered committed candidate.
rm -f "$ws/tmp/.generated/orphan.txt"
python3 - "$ws/scripts/manifest.json" <<'PY'
import json
import sys

path = sys.argv[1]
manifest = json.load(open(path, encoding="utf-8"))
manifest["generated_artifact_interfaces"].append({
    "path": "tmp/.generated/orphan.txt",
    "classification": "committed_interface",
    "generator": "scripts/compile-runtime-instructions.sh",
    "freshness_gate": "scripts/compile-runtime-instructions.sh --check",
    "gate_entrypoint": "scripts/check-framework-pr-gate.sh",
    "gate_anchor": 'run_gate "W11 runtime-instruction parity (compile --check)" "$COMPILE_RUNTIME_INSTRUCTIONS" --check',
})
json.dump(manifest, open(path, "w", encoding="utf-8"), indent=2)
PY
set +e
bash "$ws/scripts/validate-generated-artifact-discipline.sh" --root "$ws" --base "$legal_sha" \
  >"$tmpdir/unregistered.out" 2>"$tmpdir/unregistered.err"
unregistered_rc=$?
set -e
assert_exit "unregistered generated candidate fails closed" 2 "$unregistered_rc"
assert_contains "unregistered failure has structured marker" \
  "POLARIS_GENERATED_ARTIFACT_DISCIPLINE_BLOCKED:path=tmp/.generated/orphan.txt reason=unregistered_interface" \
  "$tmpdir/unregistered.err"
git -C "$ws" reset --hard -q "$orphan_sha"

# Restore the legal head, then register a fifth interface whose declared gate
# anchor is absent. Registration alone is insufficient: the freshness gate must
# be mechanically wired at the declared blocking entrypoint.
git -C "$ws" reset --hard -q "$legal_sha"
python3 - "$ws/scripts/manifest.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    manifest = json.load(handle)
manifest["generated_artifact_interfaces"].append({
    "path": "BROKEN.md",
    "classification": "committed_interface",
    "generator": "scripts/compile-runtime-instructions.sh",
    "freshness_gate": "scripts/compile-runtime-instructions.sh --check",
    "gate_entrypoint": "scripts/check-framework-pr-gate.sh",
    "gate_anchor": "W99 absent freshness gate",
})
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
printf '> Generated by `scripts/compile-runtime-instructions.sh`.\n' >"$ws/BROKEN.md"
git -C "$ws" add scripts/manifest.json BROKEN.md
git -C "$ws" commit -qm "add interface without wired gate"
set +e
bash "$ws/scripts/validate-generated-artifact-discipline.sh" --root "$ws" --base "$legal_sha" \
  >"$tmpdir/unwired.out" 2>"$tmpdir/unwired.err"
unwired_rc=$?
set -e
assert_exit "registered interface without wired gate fails closed" 2 "$unwired_rc"
assert_contains "unwired failure has structured marker" \
  "POLARIS_GENERATED_ARTIFACT_DISCIPLINE_BLOCKED:path=BROKEN.md reason=freshness_gate_unwired" \
  "$tmpdir/unwired.err"

echo "----------------------------------------"
echo "selftest summary: pass=$pass fail=$fail"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "PASS: generated-artifact discipline selftest"
