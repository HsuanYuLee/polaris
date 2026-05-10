#!/usr/bin/env bash
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

echo "script-ownership-audit selftest: PASS"
