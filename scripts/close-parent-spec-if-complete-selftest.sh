#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d -t close-parent-resolver-selftest-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

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
      *) exit 0 ;;
    esac
  fi
  exec "\$@"
fi
exit 0
EOF
cat >"$TMP_DIR/bin/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script="${1:-}"
if [[ "$script" == *"reconcile-spec-lifecycle.mjs" ]]; then
  parent="${@: -1}"
  python3 - "$parent" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if text.startswith("---\n"):
    end = text.find("\n---\n", 4)
    if end != -1:
        fm = text[:end]
        body = text[end:]
        if re.search(r"^status:", fm, re.M):
            fm = re.sub(r"^status:.*$", "status: IMPLEMENTED", fm, flags=re.M)
        else:
            fm += "\nstatus: IMPLEMENTED"
        path.write_text(fm + body, encoding="utf-8")
        print("status: IMPLEMENTED")
        raise SystemExit(0)
path.write_text("---\nstatus: IMPLEMENTED\n---\n" + text, encoding="utf-8")
print("status: IMPLEMENTED")
PY
  exit 0
fi
echo "fake node"
EOF
chmod +x "$TMP_DIR/bin/mise" "$TMP_DIR/bin/node"

PATH="$TMP_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  CLOSE_PARENT_SPEC_SELFTEST=1 bash "$SCRIPT_DIR/close-parent-spec-if-complete.sh"

if PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  CLOSE_PARENT_SPEC_SELFTEST=1 bash "$SCRIPT_DIR/close-parent-spec-if-complete.sh" >/tmp/close-parent-missing-node.out 2>&1; then
  echo "expected close-parent missing runtime resolver fixture to fail" >&2
  exit 1
fi
grep -q "POLARIS_TOOL_MISSING tool=mise" /tmp/close-parent-missing-node.out

echo "close-parent-spec-if-complete-selftest PASS"
