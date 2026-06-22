#!/usr/bin/env bash
# Purpose: selftest for scripts/script-ownership-audit.(py|sh) — asserts the
#          classifier recommends the correct bucket per fixture, including the
#          DP-289 T1 worktree-root non-blank-out and own-skill selftest =
#          skill_local correctness cases.
# Inputs:  none (builds synthetic fixture repos under a tmpdir).
# Outputs: stdout PASS line; exit 0 PASS, non-zero on assertion failure.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT="${ROOT_DIR}/scripts/script-ownership-audit.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fixture="${TMP_DIR}/repo"
mkdir -p "${fixture}/scripts" "${fixture}/.claude/skills/demo" "${fixture}/.claude/hooks"

cat >"${fixture}/scripts/manifest.json" <<'JSON'
{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/demo-only.sh",
      "kind": "support",
      "runner": "bash",
      "owner_surface": "skill_or_reference",
      "selftest": "N/A",
      "selftest_reason": "fixture",
      "lifecycle": "support_path",
      "relocation": "stay"
    },
    {
      "path": "scripts/hook-gate.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "hook",
      "selftest": "N/A",
      "selftest_reason": "fixture",
      "lifecycle": "hot_path",
      "relocation": "stay"
    },
    {
      "path": "scripts/orphan.sh",
      "kind": "support",
      "runner": "bash",
      "owner_surface": "skill_or_reference",
      "selftest": "N/A",
      "selftest_reason": "fixture",
      "lifecycle": "support_path",
      "relocation": "stay"
    }
  ]
}
JSON

for script in demo-only hook-gate orphan; do
  cat >"${fixture}/scripts/${script}.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
SH
  chmod +x "${fixture}/scripts/${script}.sh"
done

cat >"${fixture}/.claude/skills/demo/SKILL.md" <<'MD'
Run `bash scripts/demo-only.sh`.
MD
cat >"${fixture}/.claude/hooks/demo-hook.sh" <<'SH'
#!/usr/bin/env bash
bash scripts/hook-gate.sh
SH

json_out="$("${AUDIT}" --root "${fixture}" --format json)"
python3 - "$json_out" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
by_path = {row["path"]: row for row in data["scripts"]}

assert by_path["scripts/demo-only.sh"]["classification"] == "skill_local"
assert by_path["scripts/demo-only.sh"]["owner_skill"] == "demo"
assert by_path["scripts/hook-gate.sh"]["classification"] == "root_contract"
assert by_path["scripts/orphan.sh"]["classification"] == "sunset_orphan"
assert data["summary"]["root_scripts"] == 3
PY

"${AUDIT}" --root "${fixture}" --format table >/tmp/script-ownership-audit-selftest.table
grep -q 'scripts/demo-only.sh' /tmp/script-ownership-audit-selftest.table

# ------------------------------------------------------------------
# Case: worktree-root scan (DP-289 T1, AC1). When --root points at a
# directory nested under a .worktrees/ path (the shape of an engineering
# worktree), the audit must STILL classify consumers — SKIP_DIRS must
# only skip .worktrees directories nested INSIDE the scanned root, never
# the root itself. Previously every file was blanked out (0 consumers),
# turning the categorization Verify Command into a false-pass.
# ------------------------------------------------------------------
worktree_root="${TMP_DIR}/.worktrees/sample-engineering-DP-289-T1/repo"
mkdir -p "${worktree_root}/scripts" "${worktree_root}/.claude/skills/demo"
cat >"${worktree_root}/scripts/manifest.json" <<'JSON'
{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/wt-demo.sh",
      "kind": "support",
      "runner": "bash",
      "owner_surface": "skill_or_reference",
      "selftest": "N/A",
      "selftest_reason": "fixture",
      "lifecycle": "support_path",
      "relocation": "stay"
    }
  ]
}
JSON
cat >"${worktree_root}/scripts/wt-demo.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
SH
chmod +x "${worktree_root}/scripts/wt-demo.sh"
cat >"${worktree_root}/.claude/skills/demo/SKILL.md" <<'MD'
Run `bash scripts/wt-demo.sh`.
MD

wt_json="$("${AUDIT}" --root "${worktree_root}" --format json)"
python3 - "$wt_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
by_path = {row["path"]: row for row in data["scripts"]}

row = by_path["scripts/wt-demo.sh"]
# Non-empty classification: the consumer scan must reach the SKILL.md
# even though the scanned root lives under a .worktrees/ path.
assert row["consumer_count"] >= 1, (
    f"worktree-root scan blanked out consumers: {row}"
)
assert row["classification"] == "skill_local", (
    f"expected skill_local under worktree root, got {row['classification']}"
)
assert row["owner_skill"] == "demo", row
PY

# ------------------------------------------------------------------
# Case: own-owning-skill selftest = skill-owned (DP-289 T1, AC1). A
# script whose only non-skill consumers are its OWN owning-skill's
# selftest/fixtures is movable WITH the skill, so it classifies as
# skill_local — not demoted to keep_root_with_reason. Conservatism:
# a hook/rule/another-skill/another-script consumer still disqualifies
# skill_local (covered by the negative sub-case below).
# ------------------------------------------------------------------
selftest_fixture="${TMP_DIR}/selftest-owned"
mkdir -p "${selftest_fixture}/scripts" \
         "${selftest_fixture}/scripts/selftests" \
         "${selftest_fixture}/scripts/fixtures" \
         "${selftest_fixture}/.claude/skills/gamma" \
         "${selftest_fixture}/.claude/hooks"
cat >"${selftest_fixture}/scripts/manifest.json" <<'JSON'
{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/gamma-tool.sh",
      "kind": "support",
      "runner": "bash",
      "owner_surface": "skill_or_reference",
      "selftest": "N/A",
      "selftest_reason": "fixture",
      "lifecycle": "support_path",
      "relocation": "stay"
    },
    {
      "path": "scripts/gamma-leaky.sh",
      "kind": "support",
      "runner": "bash",
      "owner_surface": "skill_or_reference",
      "selftest": "N/A",
      "selftest_reason": "fixture",
      "lifecycle": "support_path",
      "relocation": "stay"
    }
  ]
}
JSON
for s in gamma-tool gamma-leaky; do
  cat >"${selftest_fixture}/scripts/${s}.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
SH
  chmod +x "${selftest_fixture}/scripts/${s}.sh"
done
# gamma-tool: single skill owner + own-skill selftest + own-skill fixture.
printf 'Run `bash scripts/gamma-tool.sh`.\n' \
  > "${selftest_fixture}/.claude/skills/gamma/SKILL.md"
printf '#!/usr/bin/env bash\nbash scripts/gamma-tool.sh\n' \
  > "${selftest_fixture}/scripts/selftests/gamma-tool-selftest.sh"
printf '# fixture referencing scripts/gamma-tool.sh\n' \
  > "${selftest_fixture}/scripts/fixtures/gamma-tool-fixture.sh"
# gamma-leaky: single skill owner BUT also leaks into a hook consumer,
# which must keep it OUT of skill_local (conservative disqualifier).
printf 'Run `bash scripts/gamma-leaky.sh`.\n' \
  >> "${selftest_fixture}/.claude/skills/gamma/SKILL.md"
printf '#!/usr/bin/env bash\nbash scripts/gamma-leaky.sh\n' \
  > "${selftest_fixture}/.claude/hooks/gamma-leaky-hook.sh"

st_json="$("${AUDIT}" --root "${selftest_fixture}" --format json)"
python3 - "$st_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
by_path = {row["path"]: row for row in data["scripts"]}

tool = by_path["scripts/gamma-tool.sh"]
assert tool["classification"] == "skill_local", (
    f"own-skill selftest/fixture consumer must classify skill_local: {tool}"
)
assert tool["owner_skill"] == "gamma", tool

leaky = by_path["scripts/gamma-leaky.sh"]
assert leaky["classification"] != "skill_local", (
    f"hook consumer must disqualify skill_local: {leaky}"
)
PY

echo "script-ownership-audit selftest: PASS"
