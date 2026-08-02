#!/usr/bin/env bash
# Purpose: Ship what the second gate signed off, reading {source}/.spine/delivery.json.
# Inputs:  --source <dir>, optional --repo, --execute (default is a preview).
# Outputs: version compression, main promotion, and — for a template-bound
#          source — template sync, tag and GitHub release. Exit 1 on any refusal.
#
# Why this exists separately from framework-release-execute.sh
# ------------------------------------------------------------
# That executor takes --task-md and orders itself around task PRs landing into a
# feat branch. A spine source has no task.md and no aggregation branch, so it
# cannot be expressed in that shape. Rather than widen the old executor to accept
# a shape it was not designed for, this composes the same underlying helpers —
# release-version.sh, framework-release-main-promotion.sh, sync-to-polaris.sh —
# from the delivery record instead. The old path is untouched and still works.
#
# The destination decides how far this goes. A workspace-bound source is promoted
# and stops: it gets no version and no changeset, because CHANGELOG.md itself
# syncs to the template and a workspace-only entry there would announce work that
# never shipped. Only a template-bound source runs the full tail.
#
# One honest tension, named rather than hidden: compressing the version adds a
# commit, which leaves the delivery record behind its own HEAD. This re-pins it,
# but only after proving the delta is exactly that one mechanical commit and the
# fence still holds. A re-pin across anything else is refused — otherwise the
# release tool would be a way to launder unsigned work past the gate.

set -euo pipefail

SOURCE_DIR=""
REPO_PATH=""
EXECUTE=0
PROBE_TAG=""

die() {
  # Description: print a POLARIS marker plus context to stderr and exit 1.
  # Args: $1 = marker, $2.. = message lines
  local marker="$1"; shift
  echo "$marker" >&2
  printf '%s\n' "$@" >&2
  exit 1
}

step() { echo "" >&2; echo "── $* ──" >&2; }
note() { echo "   $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)  SOURCE_DIR="${2:-}"; shift 2 ;;
    --repo)    REPO_PATH="${2:-}"; shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    # Answers "has origin already released this version?" and exits. The tail asks
    # the same question through this path, so a test can reach it without a
    # release; two answers to one question is how the skip below went wrong.
    --origin-has-tag) PROBE_TAG="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: spine-release.sh --source <dir> [--repo <path>] [--execute]" >&2
      echo "Without --execute this previews what it would do and changes nothing." >&2
      exit 0
      ;;
    *) die "POLARIS_SPINE_RELEASE_USAGE" "unknown argument: $1" ;;
  esac
done

[[ -n "$SOURCE_DIR" || -n "$PROBE_TAG" ]] || die "POLARIS_SPINE_RELEASE_USAGE" "--source is required"
[[ -n "$REPO_PATH" ]] || REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_PATH="$(cd "$REPO_PATH" && pwd)"

# Description: print the sha origin has for a tag, empty when origin has none.
# Args: $1 = tag name. Side effects: one network read of origin's refs.
origin_tag_sha() {
  local tag="$1"
  git -C "$REPO_PATH" ls-remote --tags origin "refs/tags/$tag" 2>/dev/null \
    | awk -v ref="refs/tags/$tag" '$2 == ref { print $1 }'
}

if [[ -n "$PROBE_TAG" ]]; then
  origin_tag_sha "$PROBE_TAG"
  exit 0
fi
# The spine finds its own parts next to itself, not inside the repo being
# released — a released repo need not carry a copy of the spine.
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 交付紀錄是 verify-ac 的產物，重釘也得由它來寫。這裡跨 skill 取用，不自己複製一份：
# 兩份會漂，而漂掉的那一刻正好是「判定過的東西」與「出貨的東西」對不上的時候。
VERIFY_AC="$(cd "$SCRIPTS/../../verify-ac/scripts" && pwd)"

RECORD="$REPO_PATH/$SOURCE_DIR/.spine/delivery.json"
[[ -f "$RECORD" ]] || die "POLARIS_SPINE_RELEASE_NO_RECORD" \
  "$SOURCE_DIR has no delivery record; the second gate has not handed anything over." \
  "Run verify-ac, then: bash .claude/skills/verify-ac/scripts/record-delivery-intent.sh --source $SOURCE_DIR ..."

# Description: echo one field from the delivery record.
# Args: $1 = field name
record_field() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' \
    "$RECORD" "$1"
}

DESTINATION="$(record_field destination)"
VERSION_BUMP="$(record_field version_bump)"
SUMMARY="$(record_field changelog_summary)"
RECORDED_HEAD="$(record_field head_sha)"
JUDGED_BY="$(record_field judged_by)"

case "$DESTINATION" in
  workspace|template) ;;
  *) die "POLARIS_SPINE_RELEASE_BAD_DESTINATION" \
       "delivery record declares destination='${DESTINATION:-<empty>}'; expected workspace or template" ;;
esac

BRANCH="$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git -C "$REPO_PATH" rev-parse HEAD)"

step "delivery record"
note "source        $SOURCE_DIR"
note "destination   $DESTINATION"
note "judged by     ${JUDGED_BY:-unknown}"
note "recorded head ${RECORDED_HEAD:0:12}"
note "current head  ${HEAD_SHA:0:12}"
note "branch        $BRANCH"

# The fence and the record must both still hold, checked here rather than trusted
# from whenever verify-ac ran.
if ! bash "$VERIFY_AC/frozen-assertion-fence.sh" verify "$REPO_PATH/$SOURCE_DIR/index.md" >/dev/null 2>&1; then
  die "POLARIS_SPINE_RELEASE_FENCE_UNVERIFIED" \
    "$SOURCE_DIR/index.md no longer matches what was signed; refusing to ship." \
    "  bash .claude/skills/verify-ac/scripts/frozen-assertion-fence.sh verify $SOURCE_DIR/index.md"
fi
if ! bash "$SCRIPTS/gate-spine-delivery.sh" --repo "$REPO_PATH" >/dev/null 2>&1; then
  die "POLARIS_SPINE_RELEASE_RECORD_STALE" \
    "the delivery record describes a different commit than HEAD; re-run verify-ac's handoff step."
fi
note "fence verified, record current"

if [[ "$EXECUTE" -ne 1 ]]; then
  step "preview only"
  note "would promote $BRANCH onto main"
  if [[ "$DESTINATION" == "template" ]]; then
    note "would compress version (bump=$VERSION_BUMP), sync to template, tag and release"
  else
    note "workspace-bound: no version, no template sync, no tag"
  fi
  note "would then land locally: main fast-forwarded, hooks reinstalled, merged branch deleted"
  note "re-run with --execute to do it"
  exit 0
fi

# ── version ───────────────────────────────────────────────────────────────────
# Workspace-bound work deliberately skips this: CHANGELOG.md syncs outward, so an
# entry for work that never leaves would announce something nobody can see.
if [[ "$DESTINATION" == "template" ]]; then
  step "version"
  before="$(cat "$REPO_PATH/VERSION" 2>/dev/null || echo unknown)"
  bash "$SCRIPTS/release-version.sh" --repo "$REPO_PATH" >&2
  after="$(cat "$REPO_PATH/VERSION" 2>/dev/null || echo unknown)"

  if [[ "$before" != "$after" ]]; then
    note "$before -> $after"
    git -C "$REPO_PATH" add -A
    git -C "$REPO_PATH" commit -q -m "chore(release): compress $after" \
      -m "${SUMMARY:-spine release}"

    # Re-pin, but only across the commit just made. Anything else means work
    # arrived that the second gate never saw, and shipping it would make the
    # record a formality.
    new_head="$(git -C "$REPO_PATH" rev-parse HEAD)"
    parent="$(git -C "$REPO_PATH" rev-parse HEAD^)"
    [[ "$parent" == "$HEAD_SHA" ]] || die "POLARIS_SPINE_RELEASE_UNEXPECTED_DELTA" \
      "the version commit is not sitting directly on the judged head; refusing to re-pin."
    bash "$VERIFY_AC/record-delivery-intent.sh" --source "$SOURCE_DIR" \
      --version-bump "$VERSION_BUMP" --summary "$SUMMARY" --head "$new_head" >&2
    HEAD_SHA="$new_head"
  else
    note "no pending changeset — version unchanged at $after"
  fi
fi

step "push"
git -C "$REPO_PATH" push origin "$BRANCH" >&2

# ── promotion ─────────────────────────────────────────────────────────────────
step "promote main"
workspace_repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[[ -n "$workspace_repo" ]] || die "POLARIS_SPINE_RELEASE_NO_REPO" \
  "could not resolve the workspace repository from gh"
pr_number="$(gh pr list --repo "$workspace_repo" --head "$BRANCH" --state open \
  --json number -q '.[0].number' 2>/dev/null || true)"
[[ -n "$pr_number" ]] || die "POLARIS_SPINE_RELEASE_NO_PR" \
  "no open PR found for $BRANCH; delivery means opening one first."
note "PR #$pr_number"

bash "$SCRIPTS/framework-release-main-promotion.sh" \
  --repo "$REPO_PATH" --workspace-repo "$workspace_repo" \
  --pr "$pr_number" --base main --head "$BRANCH" --execute >&2

# Description: leave the checkout running what was just released.
#   Promotion moves origin/main, but the local checkout stays on a branch that is
#   now merged and disposable, with local main still at the pre-release commit.
#   A later session starting from main would silently build on the old state.
#
#   The part that is easy to miss is the hooks: .git/hooks/ is generated per
#   machine and is not in the repository, so a release that adds a gate does not
#   activate it until install-git-hooks.sh runs again. Syncing the file is not
#   the same as arming the gate.
#
#   Skipped entirely when the tree is dirty — landing is housekeeping and must
#   never be a reason to touch someone's uncommitted work.
land_locally() {
  step "land locally"

  if [[ -n "$(git -C "$REPO_PATH" status --porcelain)" ]]; then
    note "working tree is dirty — leaving the checkout alone."
    note "when ready: git checkout main && git merge --ff-only origin/main && bash .claude/skills/framework-release/scripts/install-git-hooks.sh"
    return 0
  fi

  git -C "$REPO_PATH" fetch --quiet origin main

  # Move the ref before checking it out, rather than checking out a possibly
  # far-behind main and fast-forwarding afterwards. Both end in the same place,
  # but this one never materialises the old tree, so nothing watching the
  # working directory sees a flicker back to the pre-release state.
  local previous_main
  previous_main="$(git -C "$REPO_PATH" rev-parse --short main 2>/dev/null || echo none)"
  git -C "$REPO_PATH" branch -f main origin/main
  git -C "$REPO_PATH" checkout --quiet main
  note "main $previous_main -> $(git -C "$REPO_PATH" rev-parse --short main)"

  # Idempotent, and the only step that actually arms a newly released gate.
  bash "$SCRIPTS/install-git-hooks.sh" >/dev/null 2>&1 \
    && note "git hooks reinstalled — newly released gates are now armed" \
    || note "git hooks reinstall failed; run bash .claude/skills/framework-release/scripts/install-git-hooks.sh"

  # Only ever deletes a branch git itself proves is contained in main.
  if git -C "$REPO_PATH" merge-base --is-ancestor "$BRANCH" main 2>/dev/null; then
    git -C "$REPO_PATH" branch -q -D "$BRANCH" 2>/dev/null || true
    git -C "$REPO_PATH" push --quiet origin --delete "$BRANCH" 2>/dev/null \
      && note "deleted merged branch $BRANCH (local and remote)" \
      || note "deleted merged branch $BRANCH (local)"
  else
    note "$BRANCH is not contained in main — leaving it in place"
  fi
}

if [[ "$DESTINATION" != "template" ]]; then
  land_locally
  step "done"
  note "workspace-bound source promoted; nothing syncs outward."
  exit 0
fi

# ── template ──────────────────────────────────────────────────────────────────
step "sync to template"
bash "$SCRIPTS/sync-to-polaris.sh" --push >&2

step "tag and release"
version="$(cat "$REPO_PATH/VERSION")"
tag="v$version"
# The question is whether *this* repository has already released the version, so
# it is asked of origin. The local tag namespace cannot answer it: the template
# repository is a remote here and versions the same way, so its tags land locally
# with identical names pointing at entirely different commits. Reading local tags
# made the tail skip its own tag and still print "shipped at v3.85.1" — the
# release existed nowhere on origin (2026-08-02).
remote_tag="$(origin_tag_sha "$tag")"
if [[ -n "$remote_tag" ]]; then
  note "$tag already on origin — leaving it alone"
else
  # -f because a same-named tag may already sit locally, pointing at the template
  # repository's commit; this repository's tag has to point at what shipped here.
  git -C "$REPO_PATH" tag -f -a "$tag" -m "${SUMMARY:-$tag}" >/dev/null
  git -C "$REPO_PATH" push origin "$tag" >&2
  gh release create "$tag" --repo "$workspace_repo" \
    --title "$tag" --notes "${SUMMARY:-$tag}" >&2
  note "released $tag"
fi

land_locally

step "done"
note "$SOURCE_DIR shipped at $tag"
