#!/usr/bin/env bash
# Purpose: DP-295-T3 selftest — assert the changesets Keep a Changelog custom
#          formatter (.changeset/changelog-keepachangelog.cjs) maps Conventional
#          Commits types to Keep a Changelog sections and that the convention
#          reference exists.
# Inputs:  none (drives the formatter via node + synthetic changeset fixtures)
# Outputs: stdout "PASS: changeset-changelog-format" on success; exit non-zero on failure
# Side effects: none (hermetic; only reads tracked repo files, no tmp writes)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FORMATTER="$ROOT/.changeset/changelog-keepachangelog.cjs"
REFERENCE="$ROOT/.claude/skills/references/changeset-convention.md"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# --- existence ---------------------------------------------------------------
test -f "$FORMATTER" || fail "formatter missing: $FORMATTER"
test -f "$REFERENCE" || fail "convention reference missing: $REFERENCE"

command -v node >/dev/null 2>&1 || {
  printf 'POLARIS_TOOL_MISSING:node\n' >&2
  fail "node runtime required to drive the changeset formatter"
}

# --- module shape: getReleaseLine + getDependencyReleaseLine -----------------
node -e '
const fmt = require(process.argv[1]);
const mod = fmt.default || fmt;
if (typeof mod.getReleaseLine !== "function") {
  console.error("getReleaseLine is not a function");
  process.exit(1);
}
if (typeof mod.getDependencyReleaseLine !== "function") {
  console.error("getDependencyReleaseLine is not a function");
  process.exit(1);
}
if (typeof mod.classifySection !== "function") {
  console.error("classifySection helper is not exported");
  process.exit(1);
}
' "$FORMATTER" || fail "formatter module shape invalid (missing exports)"

# --- Conventional Commits type -> Keep a Changelog section mapping -----------
# Each pair: "<summary>|<expected section header>"
node -e '
const fmt = require(process.argv[1]);
const mod = fmt.default || fmt;
const cases = [
  ["feat: add release wrapper", "Added"],
  ["feat(release): scoped feature", "Added"],
  ["fix: correct version mirror", "Fixed"],
  ["fix(ci): patch gate", "Fixed"],
  ["perf: speed up collator", "Changed"],
  ["refactor: thin framework-release", "Changed"],
  ["docs: document changeset convention", "Changed"],
  ["chore: bump dep", "Changed"],
  ["build: adjust pipeline", "Changed"],
  ["revert: undo formatter change", "Removed"],
  ["security: patch token leak", "Security"],
  ["deprecate: legacy VERSION edit", "Deprecated"],
  ["no conventional prefix here", "Changed"],
];
for (const [summary, expected] of cases) {
  const got = mod.classifySection(summary);
  if (got !== expected) {
    console.error(`classifySection(${JSON.stringify(summary)}) = ${JSON.stringify(got)}, expected ${JSON.stringify(expected)}`);
    process.exit(1);
  }
}
' "$FORMATTER" || fail "Conventional Commits type -> Keep a Changelog section mapping incorrect"

# --- getReleaseLine output carries the section tag + summary text ------------
# The release line must be section-taggable so the collator can regroup
# changesets into Keep a Changelog "### Added/Changed/Fixed/..." sections.
node -e '
const fmt = require(process.argv[1]);
const mod = fmt.default || fmt;
const changeset = {
  summary: "feat: add changeset-driven version bump",
  releases: [{ name: "polaris-framework-workspace", type: "minor" }],
  commit: "abc1234def",
};
const line = mod.getReleaseLine(changeset, "minor", null);
if (typeof line !== "string" || line.length === 0) {
  console.error("getReleaseLine did not return a non-empty string");
  process.exit(1);
}
// Section tag must be recoverable from the line (the collator keys on it).
if (!line.includes("[Added]")) {
  console.error("release line missing [Added] section tag: " + line);
  process.exit(1);
}
// Summary payload (sans the conventional prefix) must survive.
if (!line.includes("add changeset-driven version bump")) {
  console.error("release line dropped the summary payload: " + line);
  process.exit(1);
}
' "$FORMATTER" || fail "getReleaseLine output contract violated"

# --- empty dependency updates -> empty string -------------------------------
node -e '
const fmt = require(process.argv[1]);
const mod = fmt.default || fmt;
const out = mod.getDependencyReleaseLine([], []);
if (out !== "") {
  console.error("getDependencyReleaseLine([], []) should be empty, got: " + JSON.stringify(out));
  process.exit(1);
}
' "$FORMATTER" || fail "getDependencyReleaseLine empty-case contract violated"

# --- reference documents the CC type -> section mapping ----------------------
grep -q 'Keep a Changelog' "$REFERENCE" || fail "reference does not mention Keep a Changelog"
grep -q 'Conventional Commits' "$REFERENCE" || fail "reference does not mention Conventional Commits"
for section in Added Changed Fixed Removed Deprecated Security; do
  grep -q "$section" "$REFERENCE" || fail "reference missing section name: $section"
done

echo "PASS: changeset-changelog-format"
