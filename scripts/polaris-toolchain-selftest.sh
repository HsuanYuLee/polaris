#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d -t polaris-toolchain-root-selftest-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

bash "$ROOT_DIR/scripts/selftests/polaris-toolchain-selftest.sh"

mkdir -p "$TMP_DIR/bin"
cat >"$TMP_DIR/bin/mise" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "exec" ]]; then
  shift
  [[ "\${1:-}" == "--" ]] && shift
  if [[ "\${1:-}" == "bash" && "\${2:-}" == "-lc" ]]; then
    case "\${3:-}" in
      *"command -v node"*) echo "$TMP_DIR/bin/node"; exit 0 ;;
      *"command -v pnpm"*) echo "$TMP_DIR/bin/pnpm"; exit 0 ;;
      *) exit 0 ;;
    esac
  fi
  exec "\$@"
fi
exit 0
EOF
cat >"$TMP_DIR/bin/node" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-p" ]]; then
  echo "22.12.0"
  exit 0
fi
echo "true"
EOF
cat >"$TMP_DIR/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "10.10.0"
  exit 0
fi
exit 0
EOF
chmod +x "$TMP_DIR/bin/mise" "$TMP_DIR/bin/node" "$TMP_DIR/bin/pnpm"

PATH="$TMP_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$ROOT_DIR/scripts/polaris-toolchain.sh" doctor --required --json >/tmp/polaris-toolchain-doctor.json
python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("/tmp/polaris-toolchain-doctor.json").read_text())
env = data["minimum_environment"]
assert env["node"]["ok"] is True
assert env["node"]["path"].endswith("/node")
assert env["pnpm"]["ok"] is True
assert env["pnpm"]["path"].endswith("/pnpm")
PY

echo "polaris-toolchain-selftest PASS"
