// Purpose: changesets getReleaseLine custom formatter for the Polaris framework
//          workspace. Maps each changeset's Conventional Commits type prefix to
//          a Keep a Changelog section (Added / Changed / Fixed / Removed /
//          Deprecated / Security) and emits a section-tagged release line so the
//          release-version collator (DP-295-T2) can regroup changesets into
//          "## [X.Y.Z] - date" -> "### <section>" blocks.
// Inputs:  changeset objects from @changesets/cli (summary, releases, commit).
// Outputs: release-line strings consumed by changesets changelog assembly /
//          the Polaris release-version collator.
// Contract: see polaris-config/polaris-framework/handbook/changeset-convention.md
//
// Module shape follows the changesets ChangelogFunctions contract:
//   module.exports = { getReleaseLine, getDependencyReleaseLine }
// (see https://github.com/changesets/changesets/blob/main/docs/modifying-changelog-format.md)

"use strict";

// Conventional Commits type -> Keep a Changelog section.
// Keep a Changelog sections: Added, Changed, Deprecated, Removed, Fixed, Security.
// (https://keepachangelog.com/en/1.1.0/ , https://www.conventionalcommits.org/en/v1.0.0/)
const TYPE_TO_SECTION = {
  feat: "Added",
  fix: "Fixed",
  perf: "Changed",
  refactor: "Changed",
  docs: "Changed",
  style: "Changed",
  test: "Changed",
  chore: "Changed",
  build: "Changed",
  ci: "Changed",
  revert: "Removed",
  security: "Security",
  deprecate: "Deprecated",
  deprecated: "Deprecated",
};

// Fallback section when no recognized Conventional Commits prefix is present.
const DEFAULT_SECTION = "Changed";

// Match a leading Conventional Commits token: "<type>" or "<type>(<scope>)",
// optionally followed by "!", then a ":" separator.
// Example matches: "feat:", "fix(ci):", "refactor!:".
const CC_PREFIX = /^([a-zA-Z]+)(?:\([^)]*\))?!?:\s*/;

/**
 * Classify a changeset summary into a Keep a Changelog section name based on
 * its leading Conventional Commits type. Falls back to DEFAULT_SECTION when no
 * recognized prefix is found.
 */
function classifySection(summary) {
  const firstLine = String(summary == null ? "" : summary)
    .split("\n")[0]
    .trim();
  const match = firstLine.match(CC_PREFIX);
  if (!match) {
    return DEFAULT_SECTION;
  }
  const type = match[1].toLowerCase();
  return Object.prototype.hasOwnProperty.call(TYPE_TO_SECTION, type)
    ? TYPE_TO_SECTION[type]
    : DEFAULT_SECTION;
}

/**
 * Strip the leading Conventional Commits prefix from a summary line, leaving the
 * human-facing payload. If no prefix is present, return the trimmed line as-is.
 */
function stripPrefix(summaryLine) {
  return String(summaryLine).replace(CC_PREFIX, "").trim();
}

/**
 * changesets getReleaseLine: render one changeset into a release line.
 * The line is prefixed with a recoverable "[<section>]" tag so the
 * release-version collator can bucket it under the right Keep a Changelog
 * "### <section>" heading. Multi-line summaries keep their continuation lines
 * indented.
 */
function getReleaseLine(changeset, _type, _changelogOpts) {
  const section = classifySection(changeset.summary);
  const lines = String(changeset.summary || "")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0);

  const headPayload = lines.length > 0 ? stripPrefix(lines[0]) : "";
  const commit =
    changeset.commit && typeof changeset.commit === "string"
      ? `${changeset.commit.slice(0, 7)}: `
      : "";

  let out = `- [${section}] ${commit}${headPayload}`;
  for (const tail of lines.slice(1)) {
    out += `\n  ${tail}`;
  }
  return out;
}

/**
 * changesets getDependencyReleaseLine: this single-package, private workspace
 * does not publish or track inter-package dependency bumps, so dependency
 * release lines are intentionally empty.
 */
function getDependencyReleaseLine(_changesets, dependenciesUpdated, _changelogOpts) {
  if (!dependenciesUpdated || dependenciesUpdated.length === 0) {
    return "";
  }
  return "";
}

module.exports = {
  getReleaseLine,
  getDependencyReleaseLine,
  // Exposed for the collator and the T3 selftest; not part of the changesets
  // ChangelogFunctions contract.
  classifySection,
};
