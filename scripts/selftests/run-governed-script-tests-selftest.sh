#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPERS="${ROOT_DIR}/scripts/selftests/lib/script-test-helpers.sh"
# shellcheck source=scripts/selftests/lib/script-test-helpers.sh
. "${HELPERS}"

TMP_DIR="$(script_test_temp_dir)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/scripts"
cat >"${TMP_DIR}/scripts/profile.sh" <<'SH'
#!/usr/bin/env bash
echo profile >> governed.log
SH
cat >"${TMP_DIR}/scripts/changed.sh" <<'SH'
#!/usr/bin/env bash
echo changed >> governed.log
SH
cat >"${TMP_DIR}/scripts/shared.sh" <<'SH'
#!/usr/bin/env bash
echo shared >> governed.log
SH
chmod +x "${TMP_DIR}/scripts/"*.sh

cat >"${TMP_DIR}/scripts/manifest.json" <<'JSON'
{
  "version": 1,
  "scripts": [],
  "governed_tests": [
    {
      "id": "profile",
      "command": "bash scripts/profile.sh",
      "profiles": ["release"],
      "changed_paths": ["scripts/profile.sh"],
      "fixtures": [],
      "enrolled": true,
      "owner": "polaris-framework"
    },
    {
      "id": "changed",
      "command": "bash scripts/changed.sh",
      "profiles": ["core"],
      "changed_paths": ["scripts/changed.sh"],
      "fixtures": [],
      "enrolled": true,
      "owner": "polaris-framework"
    },
    {
      "id": "shared",
      "command": "bash scripts/shared.sh",
      "profiles": ["core"],
      "changed_paths": ["scripts/lib/shared.sh"],
      "fixtures": [],
      "enrolled": true,
      "owner": "polaris-framework"
    }
  ]
}
JSON

bash "${ROOT_DIR}/scripts/run-governed-script-tests.sh" --root "${TMP_DIR}" --profile release --changed-file scripts/changed.sh --changed-file scripts/lib/shared.sh

grep -q '^profile$' "${TMP_DIR}/governed.log"
grep -q '^changed$' "${TMP_DIR}/governed.log"
grep -q '^shared$' "${TMP_DIR}/governed.log"
[[ "$(wc -l < "${TMP_DIR}/governed.log" | tr -d ' ')" == "3" ]]

echo "run-governed-script-tests self-test PASS"
