#!/usr/bin/env bash
# Purpose: Changeset-driven version-bump wrapper (mise run release-version).
#          Runs `changeset version` to consume pending changesets and bump the
#          package.json version, mirrors that version into the VERSION file,
#          verifies CHANGELOG.md gained the new version block, and collates that
#          block into Keep a Changelog "### <section>" structure from the custom
#          formatter's section-tagged lines (AC10). No-op safe: with no pending
#          changeset it exits 0 without bumping; an already-collated block is left
#          untouched. Fail-loud guards: pending changeset that does not advance the
#          version exits non-zero (AC-NEG3); a tagged block that collates to zero
#          Keep a Changelog sections exits non-zero (AC10).
# Inputs:  --repo <path> (default: repo root inferred from this script's location)
#          POLARIS_RELEASE_CHANGESET_CMD (optional) — override the changeset CLI
#            invocation (used by the hermetic selftest to inject a stub); defaults
#            to the workspace `pnpm exec changeset` / `npx changeset` resolution.
# Outputs: stdout progress; exit 0 success/no-op, 1 generic failure, 2 usage error.
# Side effects: mutates package.json version, VERSION, CHANGELOG.md, and deletes
#               consumed .changeset/*.md (via the changeset CLI).
# DP-334:  feature-branch release model — this wrapper compresses the changesets
#          accumulated at a single feat/DP-NNN HEAD into ONE version bump. One DP =
#          one version: pending changesets that span more than one distinct "dp-NNN"
#          marker fail-loud with POLARIS_RELEASE_VERSION_MULTI_DP_STACKING (AC-NEG2).
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash scripts/release-version.sh [--repo <path>]

Changeset-driven version bump wrapper:
  - no pending changeset            -> no-op, exit 0
  - pending changeset(s)            -> changeset version + VERSION mirror + CHANGELOG verify
  - pending but version not advanced -> fail-loud, exit non-zero (AC-NEG3)
USAGE
}

REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# No --repo given and no positional input → usage error (exit 2).
if [[ -z "$REPO_ROOT" ]]; then
  # Default to the repo containing this script only when invoked without args
  # AND that repo resolves; otherwise treat the absence as a usage error so the
  # caller is explicit. We keep the explicit-arg contract: bare invocation is an
  # error to avoid accidentally bumping the wrong tree.
  echo "POLARIS_RELEASE_VERSION_USAGE: --repo <path> is required" >&2
  usage >&2
  exit 2
fi

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "POLARIS_RELEASE_VERSION_REPO_MISSING: not a directory: $REPO_ROOT" >&2
  exit 1
fi

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

PKG_JSON="$REPO_ROOT/package.json"
VERSION_FILE="$REPO_ROOT/VERSION"
CHANGESET_DIR="$REPO_ROOT/.changeset"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

if [[ ! -f "$PKG_JSON" ]]; then
  echo "POLARIS_RELEASE_VERSION_NO_PACKAGE_JSON: $PKG_JSON" >&2
  exit 1
fi

read_pkg_version() {
  python3 - "$PKG_JSON" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["version"])
PY
}

# Count pending changesets: *.md under .changeset/ excluding README.md.
count_pending_changesets() {
  local n=0 f base
  [[ -d "$CHANGESET_DIR" ]] || { echo 0; return; }
  for f in "$CHANGESET_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "README.md" ]] && continue
    n=$((n + 1))
  done
  echo "$n"
}

# DP-334 D1 / AC-NEG2: one DP = one version. A framework release compresses the
# changesets accumulated at a single feat/DP-NNN HEAD into ONE version bump. The
# changeset filename slug carries the owning DP marker ("dp-NNN-..." — produced by
# polaris-changeset.sh from the task ticket key), so distinct DP markers across
# pending changesets mean two different DP aggregations were stacked into one
# compression. That is the forbidden cross-DP version-stacking path: refuse it
# fail-loud rather than press a multi-DP version.
#
# Discipline: only the "dp-NNN" marker drives the decision. Pending changesets
# with no DP marker at all (e.g. product-repo / ad-hoc changesets) carry no DP
# boundary signal, so they do not trigger the guard — the framework feat-HEAD
# release path is the caller that owns the one-DP invariant.
distinct_pending_dp_markers() {
  local f base
  [[ -d "$CHANGESET_DIR" ]] || return 0
  for f in "$CHANGESET_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "README.md" ]] && continue
    # Extract a leading "dp-NNN" marker from the changeset slug (case-insensitive).
    printf '%s\n' "$base" \
      | grep -oiE '^dp-[0-9]+' \
      | tr '[:upper:]' '[:lower:]'
  done | sort -u
}

assert_single_dp_aggregation() {
  local markers count
  markers="$(distinct_pending_dp_markers)"
  # No DP marker present → no cross-DP boundary signal to enforce (no-op).
  [[ -n "$markers" ]] || return 0
  count="$(printf '%s\n' "$markers" | grep -c .)"
  if [[ "$count" -gt 1 ]]; then
    {
      echo "POLARIS_RELEASE_VERSION_MULTI_DP_STACKING: pending changesets span $count distinct DPs; one DP = one version (DP-334 D1 / AC-NEG2)."
      echo "  distinct DP markers:"
      printf '    - %s\n' $markers
      echo "  Compress each feat/DP-NNN at its own HEAD into its own version; do not stack multiple DPs into a single version."
    } >&2
    return 1
  fi
  return 0
}

PENDING="$(count_pending_changesets)"

if [[ "$PENDING" -eq 0 ]]; then
  echo "release-version: no pending changeset; nothing to bump (no-op)."
  exit 0
fi

# Fail-loud before pressing the version if pending changesets stack across DPs.
if ! assert_single_dp_aggregation; then
  exit 1
fi

VERSION_BEFORE="$(read_pkg_version)"
echo "release-version: $PENDING pending changeset(s); current version=$VERSION_BEFORE"

# Resolve the changeset CLI invocation. The hermetic selftest injects a stub via
# POLARIS_RELEASE_CHANGESET_CMD. In production the workspace runs the local
# @changesets/cli devDependency installed via pnpm. Linked git worktrees do not
# inherit ignored node_modules/ from the primary checkout, so fall back to a
# sibling worktree's installed binary before reporting the dependency as missing.
resolve_installed_changeset_bin() {
  local candidate worktree

  candidate="$REPO_ROOT/node_modules/.bin/changeset"
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if git -C "$REPO_ROOT" rev-parse --git-common-dir >/dev/null 2>&1; then
    while IFS= read -r worktree; do
      [[ -n "$worktree" ]] || continue
      candidate="$worktree/node_modules/.bin/changeset"
      if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null \
      | awk '/^worktree / { sub(/^worktree /, ""); print }')
  fi

  return 1
}

run_changeset_version() {
  local changeset_bin
  if [[ -n "${POLARIS_RELEASE_CHANGESET_CMD:-}" ]]; then
    ( cd "$REPO_ROOT" && "${POLARIS_RELEASE_CHANGESET_CMD}" version )
    return
  fi
  if changeset_bin="$(resolve_installed_changeset_bin)"; then
    ( cd "$REPO_ROOT" && "$changeset_bin" version )
    return
  fi
  if command -v pnpm >/dev/null 2>&1; then
    if ( cd "$REPO_ROOT" && pnpm exec changeset --version >/dev/null 2>&1 ); then
      ( cd "$REPO_ROOT" && pnpm exec changeset version )
      return
    fi
  fi
  if command -v npx >/dev/null 2>&1; then
    if ( cd "$REPO_ROOT" && npx --no-install changeset --version >/dev/null 2>&1 ); then
      ( cd "$REPO_ROOT" && npx --no-install changeset version )
      return
    fi
  fi
  echo "POLARIS_TOOL_MISSING:changeset (declared devDependency @changesets/cli is not installed in this checkout/worktree; run 'mise run bootstrap' from the Polaris workspace root, or run from a worktree set that has node_modules/.bin/changeset)" >&2
  return 1
}

if ! run_changeset_version; then
  echo "POLARIS_RELEASE_VERSION_CHANGESET_FAILED: changeset version did not complete" >&2
  exit 1
fi

VERSION_AFTER="$(read_pkg_version)"

# AC-NEG3: pending changeset(s) existed but the version did not advance.
if [[ "$VERSION_AFTER" == "$VERSION_BEFORE" ]]; then
  echo "POLARIS_RELEASE_VERSION_NOT_ADVANCED: $PENDING pending changeset(s) consumed but version stayed at $VERSION_BEFORE" >&2
  exit 1
fi

# Mirror package.json version into VERSION file (AC2 / AC3).
printf '%s\n' "$VERSION_AFTER" > "$VERSION_FILE"

# Verify CHANGELOG gained a block for the new version (AC3).
if [[ ! -f "$CHANGELOG" ]]; then
  echo "POLARIS_RELEASE_VERSION_NO_CHANGELOG: $CHANGELOG missing after version bump" >&2
  exit 1
fi
if ! grep -q "$VERSION_AFTER" "$CHANGELOG"; then
  echo "POLARIS_RELEASE_VERSION_CHANGELOG_MISSING_BLOCK: CHANGELOG.md has no block for $VERSION_AFTER" >&2
  exit 1
fi

# Collate the new version block into Keep a Changelog structure (AC10).
#
# The custom formatter (.changeset/changelog-keepachangelog.cjs, T3) emits each
# changeset as a section-tagged release line "- [<Section>] <commit>: <payload>".
# After `changeset version`, those tagged lines land inside the freshly written
# "## <version>" block under the changesets default "### <Bump> Changes"
# subheadings. This collator regroups the tagged lines under Keep a Changelog
# "### Added / Changed / Fixed / Removed / Deprecated / Security" headings and
# strips the "[<Section>]" tag, normalising the block to the Keep a Changelog
# shape the release CHANGELOG is required to publish.
#
# Discipline: scoped to the newest "## <version>" block only (older history is
# left untouched); no-op safe + idempotent (a block with no "[<Section>]" tags is
# left unchanged); fail-loud (a tagged block that collates to zero buckets exits
# non-zero so a malformed formatter contract cannot pass silently).
collate_changelog_block() {
  python3 - "$CHANGELOG" "$VERSION_AFTER" "$(date +%Y-%m-%d)" <<'PY'
import re
import sys
from pathlib import Path

changelog_path = Path(sys.argv[1])
version = sys.argv[2]
release_date = sys.argv[3]

# Keep a Changelog canonical section order
# (https://keepachangelog.com/en/1.1.0/).
SECTION_ORDER = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]

text = changelog_path.read_text(encoding="utf-8")
lines = text.split("\n")

# Locate the newest "## <version>" heading and the extent of its block (up to the
# next "## " heading or end of file).
version_heading_re = re.compile(r"^## (?:\[)?" + re.escape(version) + r"(?:\])?(?:\s|$)")
start = None
for i, line in enumerate(lines):
    if version_heading_re.match(line):
        start = i
        break

if start is None:
    # CHANGELOG verify already guarantees the block exists; treat absence here as
    # a contract failure rather than silently passing.
    sys.stderr.write(
        "POLARIS_RELEASE_VERSION_COLLATE_BLOCK_MISSING: no '## %s' heading to collate\n"
        % version
    )
    sys.exit(1)

end = len(lines)
for j in range(start + 1, len(lines)):
    if lines[j].startswith("## "):
        end = j
        break

block = lines[start:end]

# Bucket tagged release lines by their "[<Section>]" tag. A tagged line and its
# indented continuation lines (changesets renders multi-line summaries with a
# two-space indent) travel together.
tag_re = re.compile(r"^- \[([A-Za-z]+)\]\s?(.*)$")
buckets = {name: [] for name in SECTION_ORDER}
tagged_count = 0
current_section = None

for raw in block[1:]:  # skip the "## <version>" heading itself
    m = tag_re.match(raw)
    if m:
        section = m.group(1).capitalize()
        if section not in buckets:
            # Unknown tag → fold into Changed so nothing is dropped.
            section = "Changed"
        current_section = section
        buckets[section].append("- " + m.group(2).rstrip())
        tagged_count += 1
        continue
    # Indented continuation of the current tagged entry.
    if current_section is not None and (raw.startswith("  ") or raw.strip() == ""):
        if raw.strip() == "":
            current_section = None  # blank line ends the entry
        else:
            buckets[current_section].append(raw.rstrip())

if tagged_count == 0:
    # Idempotent / no-op: block already collated (or no formatter-tagged lines).
    # Leave the file untouched and exit success.
    sys.exit(0)

emitted_sections = [name for name in SECTION_ORDER if buckets[name]]
if not emitted_sections:
    sys.stderr.write(
        "POLARIS_RELEASE_VERSION_COLLATE_EMPTY: %d tagged line(s) in '## %s' "
        "collated to zero Keep a Changelog sections\n" % (tagged_count, version)
    )
    sys.exit(1)

# Rewrite the changesets-default "## <version>" heading into the Keep a Changelog
# release heading "## [<version>] - <date>" (AC10). The collator only runs on a
# tagged (freshly pressed) block, so this rewrite is bounded to the new release
# and never rewrites already-published history. Idempotency still holds: once the
# block is collated the "[<Section>]" tags are gone, so a re-run sees
# tagged_count == 0 and exits before reaching this point, leaving the
# "## [<version>] - <date>" heading untouched.
kac_heading = "## [%s] - %s" % (version, release_date)
new_block = [kac_heading, ""]
for name in emitted_sections:
    new_block.append("### " + name)
    new_block.append("")
    new_block.extend(buckets[name])
    new_block.append("")

rebuilt = lines[:start] + new_block + lines[end:]
changelog_path.write_text("\n".join(rebuilt), encoding="utf-8")
sys.exit(0)
PY
}

if ! collate_changelog_block; then
  echo "POLARIS_RELEASE_VERSION_COLLATE_FAILED: could not collate '## $VERSION_AFTER' block into Keep a Changelog structure" >&2
  exit 1
fi

echo "release-version: bumped $VERSION_BEFORE -> $VERSION_AFTER; VERSION mirror + CHANGELOG synced + collated; changesets consumed."
exit 0
