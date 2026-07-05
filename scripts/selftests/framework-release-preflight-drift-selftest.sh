#!/usr/bin/env bash
# Purpose: Regression coverage for framework-release preflight drift gates.
#          Release-version must fail before compression on stale changeset
#          package keys; docs lint must catch removed skill references in a
#          hermetic root; template leak scan must block template-facing company
#          fixture leaks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_VERSION="$ROOT/scripts/release-version.sh"
README_LINT="$ROOT/scripts/readme-lint.py"
LEAK_SCAN="$ROOT/scripts/scan-template-leaks.sh"

tmp="$(mktemp -d -t framework-release-preflight.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1" needle="$2" label="$3"
  grep -qF "$needle" "$file" || fail "$label missing '$needle'"
}

make_release_repo() {
  local repo="$1"
  mkdir -p "$repo/.changeset"
  cat >"$repo/package.json" <<'JSON'
{
  "name": "polaris-framework-workspace",
  "version": "1.0.0",
  "private": true
}
JSON
  printf '1.0.0\n' >"$repo/VERSION"
  cat >"$repo/CHANGELOG.md" <<'MD'
# Changelog
MD
  cat >"$repo/.changeset/config.json" <<'JSON'
{ "changelog": "./changelog-keepachangelog.cjs", "commit": false }
JSON
  cat >"$repo/.changeset/README.md" <<'MD'
# Changesets
MD
}

make_stub_changeset() {
  local path="$1"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
repo="$(pwd)"
python3 - "$repo/package.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
data["version"] = "1.0.1"
json.dump(data, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
cat >>"$repo/CHANGELOG.md" <<'MD'

## 1.0.1

### Patch Changes

- [Fixed] c0ffee0: should not be reached for stale package key
MD
rm -f "$repo"/.changeset/*.md
exit 0
SH
  chmod +x "$path"
}

echo "== Case 1: stale changeset package key fails before version compression =="
release_repo="$tmp/release-repo"
make_release_repo "$release_repo"
cat >"$release_repo/.changeset/dp-404-t5-wrong-package.md" <<'MD'
---
"polaris-framework-workspac": patch
---

Wrong package key fixture.
MD
stub="$tmp/stub-changeset.sh"
make_stub_changeset "$stub"
set +e
POLARIS_RELEASE_CHANGESET_CMD="$stub" "$RELEASE_VERSION" --repo "$release_repo" \
  >"$tmp/release-version.out" 2>"$tmp/release-version.err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "release-version accepted a stale changeset package key"
assert_contains "$tmp/release-version.err" "POLARIS_RELEASE_VERSION_CHANGESET_PACKAGE_MISMATCH" "release-version mismatch marker"
[[ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$release_repo/package.json")" == "1.0.0" ]] \
  || fail "release-version advanced package.json despite stale package key"
[[ -f "$release_repo/.changeset/dp-404-t5-wrong-package.md" ]] \
  || fail "release-version consumed stale changeset despite fail-fast"

echo "== Case 2: readme-lint catches removed skill references in a hermetic root =="
lint_root="$tmp/lint-root"
mkdir -p "$lint_root/.claude/skills/onboard" "$lint_root/docs"
cat >"$lint_root/.claude/skills/onboard/SKILL.md" <<'MD'
---
name: onboard
---

# onboard
MD
cat >"$lint_root/README.md" <<'MD'
# Polaris

1 workflow skills are available: `onboard`.
MD
cat >"$lint_root/docs/chinese-triggers.md" <<'MD'
| Skill | Trigger |
|-------|---------|
| **onboard** — setup | onboard |
MD
cat >"$lint_root/docs/workflow-guide.md" <<'MD'
Use the removed `legacy-flow` skill when this fixture should fail.
MD
set +e
POLARIS_README_LINT_ROOT="$lint_root" python3 "$README_LINT" \
  >"$tmp/readme-lint.out" 2>"$tmp/readme-lint.err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "readme-lint did not fail on removed skill reference"
assert_contains "$tmp/readme-lint.out" "legacy-flow" "readme-lint phantom skill output"

echo "== Case 3: template-facing company fixture leaks are blocking =="
leak_ws="$tmp/leak-ws"
mkdir -p "$leak_ws/acme" "$leak_ws/_template" "$leak_ws/scripts/selftests/fixtures/synthetic"
cat >"$leak_ws/acme/workspace-config.yaml" <<'YAML'
jira:
  instance: acme.atlassian.net
  projects:
    - key: ACME
github:
  org: acme-inc
YAML
cat >"$leak_ws/_template/company-ticket-template.md" <<'MD'
Do not ship ACME-123 into the template.
MD
cat >"$leak_ws/scripts/selftests/fixtures/synthetic/task.md" <<'MD'
Synthetic selftest payload ACME-999 stays excluded.
MD
set +e
"$LEAK_SCAN" --workspace "$leak_ws" --source workspace --blocking \
  >"$tmp/leak.out" 2>"$tmp/leak.err"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail "template leak scan accepted template-facing company fixture"
assert_contains "$tmp/leak.err" "POLARIS_TEMPLATE_LEAK" "template leak marker"
assert_contains "$tmp/leak.out" "_template/company-ticket-template.md" "template leak path"
if grep -q "fixtures/synthetic" "$tmp/leak.out"; then
  fail "selftest fixture carve-out was reported as template leak"
fi

echo "[framework-release-preflight-drift-selftest] PASS"
