#!/usr/bin/env bash
# Purpose: DP-421 T3 / AC3 + AC-NEG3 — selftest for the changeset-BODY language
#          gate added to scripts/gates/gate-changeset.sh. Language enforcement is
#          moved to the EARLIEST authoring point (changeset-gate time): an English
#          changeset body fails fail-closed here (reproducing the DP-417 scenario
#          where the violation was deferred to the release surface), while a zh-TW
#          changeset body that merely wraps English code identifiers (script names,
#          DP keys, commands, paths, error tokens) PASSES — the gate reuses the
#          shared scripts/validate-language-policy.sh carve-out, so no second
#          carve-out exists.
# Inputs:  none (hermetic tmp git repos with .changeset + workspace-config.yaml).
# Outputs: PASS/FAIL lines per scenario; exit 0 (all pass) / 1 (any fail).
# Covers:  (1) English changeset body -> BLOCKED exit 2 + POLARIS_CHANGESET_LANGUAGE_POLICY (AC3, DP-417 repro);
#          (2) zh-TW body with English code identifiers -> exit 0 (AC-NEG3);
#          (3) pure-English prose body -> BLOCKED exit 2 (AC3).

set -euo pipefail

# Hermetic: the fixture repo carries its own workspace-config.yaml; do not let an
# ambient override point the language resolver at another workspace.
unset POLARIS_WORKSPACE_CONFIG_ROOT

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/gates/gate-changeset.sh"
PCS="$ROOT/scripts/polaris-changeset.sh"
[[ -x "$GATE" ]] || { echo "FAIL: missing/not executable: $GATE" >&2; exit 1; }
[[ -x "$PCS" ]] || { echo "FAIL: missing/not executable: $PCS" >&2; exit 1; }

TMP="$(mktemp -d -t gate-changeset-lang-XXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1" >&2; }

TASK_REL="specs/tasks/T1/index.md"

# make_repo: hermetic git repo with changeset scaffolding, a zh-TW workspace
# language contract, and a seeded origin/main. Emits the repo path on stdout.
make_repo() {
  local name="$1"
  local r="$TMP/$name"
  mkdir -p "$r/.changeset" "$r/scripts" "$r/specs/tasks/T1"
  git -C "$r" init -q -b main
  git -C "$r" config user.email selftest@example.com
  git -C "$r" config user.name Selftest
  echo "seed" >"$r/README.md"
  printf '1.0.0\n' >"$r/VERSION"
  printf '# changelog\n' >"$r/CHANGELOG.md"
  # Workspace language contract that the changeset body gate enforces.
  printf 'language: zh-TW\n' >"$r/workspace-config.yaml"
  cat >"$r/package.json" <<'JSON'
{
  "name": "polaris-framework-workspace",
  "version": "1.0.0",
  "private": true
}
JSON
  cat >"$r/.changeset/config.json" <<'JSON'
{ "$schema": "x", "changelog": "@changesets/cli/changelog", "commit": false, "fixed": [], "linked": [], "access": "restricted", "baseBranch": "main", "updateInternalDependencies": "patch", "ignore": [], "privatePackages": {"tag": true} }
JSON
  printf '# Changesets\n' >"$r/.changeset/README.md"
  printf '#!/usr/bin/env bash\necho seed\n' >"$r/scripts/x.sh"
  cat >"$r/specs/tasks/T1/index.md" <<'MD'
---
status: IN_PROGRESS
---

# T1: changeset body language gate fixture (1 pt)

> Source: DP-421 | Task: DP-421-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task ID | DP-421-T1 |
| Base branch | main |
| Task branch | task/DP-421-T1-changeset-lang |

## Allowed Files

- `scripts/gates/gate-changeset.sh`
MD
  git -C "$r" add -A
  git -C "$r" commit -q -m "seed"
  git -C "$r" update-ref refs/remotes/origin/main HEAD
  printf '%s\n' "$r"
}

# author_changeset: create the task-bound changeset via the canonical producer so
# `polaris-changeset check` passes, then overwrite its BODY (keeping frontmatter)
# with the supplied text. Also mutates an impl file so the task delta is NOT
# changeset-only (otherwise the delta guard blocks before the language gate).
author_changeset() {
  local repo="$1" body="$2"
  local out csfile
  out="$(bash "$PCS" new --task-md "$repo/$TASK_REL" --repo "$repo" 2>/dev/null)"
  csfile="$(printf '%s\n' "$out" | sed -n 's/^polaris-changeset: wrote //p')"
  [[ -n "$csfile" && -f "$csfile" ]] || { echo "FAIL: could not author changeset in $repo (out=$out)" >&2; exit 1; }
  local fm
  fm="$(awk 'NR==1 && $0=="---" {print; infm=1; next} infm {print; if ($0=="---") exit}' "$csfile")"
  { printf '%s\n\n' "$fm"; printf '%s\n' "$body"; } >"$csfile"
  # Non-changeset impl delta so the changeset-only guard does not fire first.
  printf '#!/usr/bin/env bash\necho impl change\n' >"$repo/scripts/x.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "author changeset + impl"
}

# ── Scenario 1: English changeset body -> BLOCKED exit 2 (AC3, DP-417 repro) ────
R1="$(make_repo repo1)"
author_changeset "$R1" "Move the workspace-config language contract enforcement to the earliest authoring point so this changeset fails at the gate."
set +e
err1="$(bash "$GATE" --repo "$R1" --task-md "$R1/$TASK_REL" 2>&1 >/dev/null)"
rc1=$?
set -e
if [[ "$rc1" -eq 2 ]] && grep -q "POLARIS_CHANGESET_LANGUAGE_POLICY" <<<"$err1"; then
  ok "English changeset body -> exit 2 + POLARIS_CHANGESET_LANGUAGE_POLICY (AC3)"
else
  bad "English changeset body should BLOCK with POLARIS_CHANGESET_LANGUAGE_POLICY; exit=$rc1 stderr=$err1"
fi

# ── Scenario 2: zh-TW body wrapping English identifiers -> exit 0 (AC-NEG3) ─────
R2="$(make_repo repo2)"
author_changeset "$R2" "把語言 enforcement 下移到最早 authoring 點：\`scripts/gates/gate-changeset.sh\` 對 changeset body 以 workspace language 檢查，release surface 改為 parity；違規印 \`POLARIS_CHANGESET_LANGUAGE_POLICY\`。"
set +e
bash "$GATE" --repo "$R2" --task-md "$R2/$TASK_REL" >/dev/null 2>&1
rc2=$?
set -e
[[ "$rc2" -eq 0 ]] && ok "zh-TW body with English code identifiers -> exit 0 (AC-NEG3)" \
  || bad "zh-TW body with identifiers should PASS (exit 0); got exit $rc2"

# ── Scenario 3: pure-English prose body -> BLOCKED exit 2 (AC3) ─────────────────
R3="$(make_repo repo3)"
author_changeset "$R3" "This changeset description is written entirely in English prose without any technical identifiers at all."
set +e
err3="$(bash "$GATE" --repo "$R3" --task-md "$R3/$TASK_REL" 2>&1 >/dev/null)"
rc3=$?
set -e
if [[ "$rc3" -eq 2 ]] && grep -q "POLARIS_CHANGESET_LANGUAGE_POLICY" <<<"$err3"; then
  ok "pure-English prose body -> exit 2 + POLARIS_CHANGESET_LANGUAGE_POLICY (AC3)"
else
  bad "pure-English prose body should BLOCK with POLARIS_CHANGESET_LANGUAGE_POLICY; exit=$rc3 stderr=$err3"
fi

echo ""
echo "[gate-changeset-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
