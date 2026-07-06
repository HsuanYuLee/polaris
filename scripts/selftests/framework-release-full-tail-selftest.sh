#!/usr/bin/env bash
# Purpose: exercise framework-release-execute.sh full release-tail orchestration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER=""
TMPDIR="$(mktemp -d -t framework-release-full-tail.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT
REPO="$TMPDIR/repo"
TASK_DIR="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-347-fixture/tasks"
LOG="$TMPDIR/tail.log"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_task() {
  local id="$1"
  local branch="$2"
  local file="$TASK_DIR/${id}.md"
  mkdir -p "$TASK_DIR"
  cat >"$file" <<MD
---
deliverable:
  pr_url: https://example.test/pull/${id#T}
  pr_state: OPEN
  head_sha: $(git -C "$REPO" rev-parse "$branch")
  verification:
    status: PASS
    ac_counts:
      ac_total: 1
      ac_pass: 1
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0
---
# ${id}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-347 |
| Task ID | DP-347-${id} |
| JIRA key | N/A |
| Base branch | feat/DP-347 |
| Branch chain | feat/DP-347 -> ${branch} |
| Task branch | ${branch} |
| Depends on | N/A |
MD
}

init_repo() {
  git init -q -b main "$REPO"
  (
    cd "$REPO"
    git config user.name "Polaris Selftest"
    git config user.email "polaris-selftest@example.com"
    printf 'language: "zh-TW"\n' > workspace-config.yaml
    printf '3.76.64\n' > VERSION
    cat >package.json <<'JSON'
{"name":"polaris-framework-workspace","version":"3.76.64"}
JSON
    printf '# Changelog\n' > CHANGELOG.md
    mkdir -p scripts .changeset
    cat >.changeset/dp-347-fixture.md <<'MD'
---
"polaris-framework-workspace": patch
---

DP-347 fixture changeset
MD
    git add workspace-config.yaml VERSION package.json CHANGELOG.md .changeset/dp-347-fixture.md
    git commit -q -m "base"
    git remote add origin "$REPO"
    git fetch -q origin main:refs/remotes/origin/main
    git checkout -q -b feat/DP-347 main
    git checkout -q -b task/DP-347-T1-one feat/DP-347
    printf 't1\n' > t1.txt
    git add t1.txt
    git commit -q -m "t1"
    git checkout -q feat/DP-347
    git fetch -q origin \
      +refs/heads/feat/DP-347:refs/remotes/origin/feat/DP-347 \
      +refs/heads/task/DP-347-T1-one:refs/remotes/origin/task/DP-347-T1-one
  )
  cp "$SCRIPT_DIR/framework-release-execute.sh" "$REPO/scripts/framework-release-execute.sh"
  cp -R "$SCRIPT_DIR/lib" "$REPO/scripts/lib"
  cat >"$REPO/scripts/polaris-external-write-gate.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
body_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --body-file) body_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$body_file" && -f "$body_file" ]] || exit 2
echo "external-write-gate $(cat "$body_file")" >>"${FULL_TAIL_LOG:?}"
exit 0
SH
  chmod +x "$REPO/scripts/framework-release-execute.sh"
  chmod +x "$REPO/scripts/polaris-external-write-gate.sh"
  HELPER="$REPO/scripts/framework-release-execute.sh"
}

write_stubs() {
  cat >"$REPO/scripts/framework-release-pr-lane.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "01 pr-lane $*" >>"${FULL_TAIL_LOG:?}"
exit 0
SH
  cat >"$REPO/scripts/cascade-rebase-chain.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "02 cascade $*" >>"${FULL_TAIL_LOG:?}"
exit 0
SH
  cat >"$TMPDIR/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "run" || "${2:-}" != "release-version" ]]; then
  echo "unexpected mise command: $*" >&2
  exit 2
fi
if [[ -f "${FULL_TAIL_VERSION_FAIL_FILE:?}" ]]; then
  echo "03 release-version-fail" >>"${FULL_TAIL_LOG:?}"
  echo "POLARIS_RELEASE_VERSION_NOT_ADVANCED: fixture" >&2
  exit 1
fi
echo "03 release-version" >>"${FULL_TAIL_LOG:?}"
python3 - <<'PY'
import json
from pathlib import Path

pkg = Path("package.json")
data = json.loads(pkg.read_text())
data["version"] = "3.76.65"
pkg.write_text(json.dumps(data, separators=(",", ":")) + "\n")
Path("VERSION").write_text("3.76.65\n")
Path("CHANGELOG.md").write_text("# Changelog\n\n## [3.76.65] - 2026-07-04\n\n### Fixed\n\n- DP-347 fixture\n")
Path(".changeset/dp-347-fixture.md").unlink()
PY
SH
  cat >"$REPO/scripts/polaris-pr-create.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "04 pr-create $*" >>"${FULL_TAIL_LOG:?}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --body-file)
      echo "04 pr-create-body $(cat "$2")" >>"${FULL_TAIL_LOG:?}"
      shift 2
      ;;
    *) shift ;;
  esac
done
echo "https://github.com/example/repo/pull/77"
SH
  cat >"$REPO/scripts/framework-release-main-promotion.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "05 main-promotion $*" >>"${FULL_TAIL_LOG:?}"
exit 0
SH
  chmod +x "$TMPDIR/mise" "$REPO/scripts"/*.sh
}

init_repo
write_stubs
make_task T1 task/DP-347-T1-one
export FULL_TAIL_LOG="$LOG"
export FULL_TAIL_VERSION_FAIL_FILE="$TMPDIR/version-fail"
export PATH="$TMPDIR:$PATH"

bash "$HELPER" --repo "$REPO" --source-id DP-347 --full-tail \
  --task-md "$TASK_DIR/T1.md" >"$TMPDIR/full-tail.out" 2>&1
grep -q "PASS full-tail source=DP-347" "$TMPDIR/full-tail.out" \
  || fail "full-tail PASS trace missing"
grep -q "01 pr-lane" "$LOG" || fail "pr-lane did not run"
grep -q "02 cascade" "$LOG" || fail "cascade did not run"
grep -q "03 release-version" "$LOG" || fail "release-version did not run"
grep -q "04 pr-create" "$LOG" || fail "pr-create did not run"
grep -q "Polaris 框架發版" "$LOG" || fail "release PR title/body should follow zh-TW workspace language"
if grep -q "framework release" "$LOG"; then
  fail "release PR default prose must not remain English under zh-TW workspace language"
fi
grep -q "05 main-promotion" "$LOG" || fail "main promotion did not run"
[[ "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" == "feat/DP-347" ]] \
  || fail "full-tail should operate on feat branch"
git -C "$REPO" log -1 --pretty=%s | grep -q "compress DP-347 version" \
  || fail "version compression commit missing"
git -C "$REPO" show HEAD:VERSION | grep -q "3.76.65" \
  || fail "version compression commit does not carry VERSION"

# Failure path: release-version fails after landing/rebase, so release PR and
# main promotion must not run.
git -C "$REPO" reset -q --hard HEAD~1
git -C "$REPO" checkout -q feat/DP-347
: >"$LOG"
touch "$FULL_TAIL_VERSION_FAIL_FILE"
if bash "$HELPER" --repo "$REPO" --source-id DP-347 --full-tail \
  --task-md "$TASK_DIR/T1.md" >"$TMPDIR/full-tail-fail.out" 2>&1; then
  fail "full-tail should fail when release-version fails"
fi
grep -q "03 release-version-fail" "$LOG" || fail "negative fixture did not reach release-version"
if grep -qE "04 pr-create|05 main-promotion" "$LOG"; then
  fail "release-version failure must not create PR or promote main"
fi

grep -q "framework-release-execute.sh" "$SCRIPT_DIR/../.claude/skills/framework-release/SKILL.md" \
  || fail "framework-release skill must mention deterministic executor"
grep -q "framework-release-execute" "$SCRIPT_DIR/../.claude/rules/mechanism-registry.md" \
  || fail "mechanism registry must mention framework-release-execute"

echo "PASS: framework-release full-tail selftest"
