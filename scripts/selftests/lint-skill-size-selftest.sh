#!/usr/bin/env bash
# DP-237 T5 selftest: lint-skill-size.sh deterministic skill-size cap enforcement.
#
# 覆蓋三條 AC6 路徑：
#   1. 正常 PASS：所有 LIMIT_FILES 都存在且 ≤ 對應 cap。
#   2. 違反 cap：fixture skill 行數 > limit，lint exit 1 並輸出該檔超標訊息。
#   3. 缺檔：LIMIT_FILES 列出的 skill 不存在，lint exit 1。
#   4. 真實 SKILL fixture：mirror live `.claude/skills/auto-pass/SKILL.md` cap=120，避免
#      script 被改成跳過該檔。
#
# Selftest 使用 sandbox repo（mktemp tmpdir）跑 lint，從不修改真實 repo 內容。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/lint-skill-size.sh"

if [[ ! -x "$SCRIPT" && ! -f "$SCRIPT" ]]; then
  echo "FAIL: lint-skill-size.sh not found at $SCRIPT" >&2
  exit 1
fi

# Confirm the live script enforces the auto-pass SKILL.md cap of 120 lines.
if ! grep -Fq ".claude/skills/auto-pass/SKILL.md" "$SCRIPT"; then
  echo "FAIL: lint-skill-size.sh must cap .claude/skills/auto-pass/SKILL.md" >&2
  exit 1
fi
if ! grep -Eq '\b120\b' "$SCRIPT"; then
  echo "FAIL: lint-skill-size.sh must record 120-line cap for auto-pass SKILL" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Build a sandbox repo that mirrors the live LIMIT_FILES paths so the script can
# be exercised against controlled fixtures. We extract the LIMIT_FILES entries
# from the script itself; this prevents the selftest from drifting when caps
# are extended to other skills.
LIMIT_FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && LIMIT_FILES+=("$line")
done < <(python3 - "$SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
match = re.search(r"LIMIT_FILES=\(([^)]+)\)", text)
if not match:
    sys.exit("LIMIT_FILES array not found")
for token in re.findall(r'"([^"]+)"', match.group(1)):
    print(token)
PY
)
LIMIT_VALUES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && LIMIT_VALUES+=("$line")
done < <(python3 - "$SCRIPT" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
match = re.search(r"LIMIT_VALUES=\(([^)]+)\)", text)
if not match:
    sys.exit("LIMIT_VALUES array not found")
for token in match.group(1).split():
    token = token.strip()
    if token:
        print(token)
PY
)

if (( ${#LIMIT_FILES[@]} == 0 || ${#LIMIT_FILES[@]} != ${#LIMIT_VALUES[@]} )); then
  echo "FAIL: LIMIT_FILES / LIMIT_VALUES are empty or misaligned" >&2
  exit 1
fi

build_sandbox() {
  local sandbox="$1"
  shift
  # remaining args: filename1 lines1 filename2 lines2 ...
  while [[ $# -gt 0 ]]; do
    local f="$1"; local n="$2"; shift 2
    mkdir -p "$sandbox/$(dirname "$f")"
    python3 - "$sandbox/$f" "$n" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
n = int(sys.argv[2])
path.write_text("\n".join(f"line {i}" for i in range(1, n + 1)) + "\n")
PY
  done
}

# Case 1: all skills exactly at limit → PASS
case1="$tmpdir/case1"
mkdir -p "$case1"
for i in "${!LIMIT_FILES[@]}"; do
  build_sandbox "$case1" "${LIMIT_FILES[$i]}" "${LIMIT_VALUES[$i]}"
done
out1="$tmpdir/case1.out"
if ! ( cd "$case1" && bash "$SCRIPT" ) >"$out1" 2>&1; then
  echo "FAIL: case 1 (within cap) should PASS" >&2
  cat "$out1" >&2
  exit 1
fi
grep -q "PASS: skill-size policy" "$out1" || {
  echo "FAIL: case 1 missing PASS line" >&2
  cat "$out1" >&2
  exit 1
}

# Case 2: first skill exceeds cap by 1 → FAIL (covers AC6 violation fixture).
case2="$tmpdir/case2"
mkdir -p "$case2"
build_sandbox "$case2" "${LIMIT_FILES[0]}" "$(( LIMIT_VALUES[0] + 1 ))"
for i in "${!LIMIT_FILES[@]}"; do
  (( i == 0 )) && continue
  build_sandbox "$case2" "${LIMIT_FILES[$i]}" "${LIMIT_VALUES[$i]}"
done
out2="$tmpdir/case2.out"
if ( cd "$case2" && bash "$SCRIPT" ) >"$out2" 2>&1; then
  echo "FAIL: case 2 (oversize fixture) should exit non-zero" >&2
  cat "$out2" >&2
  exit 1
fi
grep -q "${LIMIT_FILES[0]} has $(( LIMIT_VALUES[0] + 1 )) lines; limit is ${LIMIT_VALUES[0]}" "$out2" || {
  echo "FAIL: case 2 missing oversize error for ${LIMIT_FILES[0]}" >&2
  cat "$out2" >&2
  exit 1
}

# Case 3: required skill file missing → FAIL.
case3="$tmpdir/case3"
mkdir -p "$case3"
# Intentionally only build the second file (if any); otherwise build none.
if (( ${#LIMIT_FILES[@]} > 1 )); then
  for i in "${!LIMIT_FILES[@]}"; do
    (( i == 0 )) && continue
    build_sandbox "$case3" "${LIMIT_FILES[$i]}" "${LIMIT_VALUES[$i]}"
  done
fi
out3="$tmpdir/case3.out"
if ( cd "$case3" && bash "$SCRIPT" ) >"$out3" 2>&1; then
  echo "FAIL: case 3 (missing skill) should exit non-zero" >&2
  cat "$out3" >&2
  exit 1
fi
grep -q "missing required skill: ${LIMIT_FILES[0]}" "$out3" || {
  echo "FAIL: case 3 missing 'missing required skill' error" >&2
  cat "$out3" >&2
  exit 1
}

# Case 4: --report mode emits JSON list of {path,current_lines,limit,exceed_by}.
case4="$tmpdir/case4"
mkdir -p "$case4"
build_sandbox "$case4" "${LIMIT_FILES[0]}" "$(( LIMIT_VALUES[0] + 5 ))"
for i in "${!LIMIT_FILES[@]}"; do
  (( i == 0 )) && continue
  build_sandbox "$case4" "${LIMIT_FILES[$i]}" "${LIMIT_VALUES[$i]}"
done
out4="$tmpdir/case4.json"
( cd "$case4" && bash "$SCRIPT" --report ) >"$out4" 2>&1 || {
  echo "FAIL: case 4 --report should exit 0 even when over cap" >&2
  cat "$out4" >&2
  exit 1
}
python3 - "$out4" "${LIMIT_FILES[0]}" "${LIMIT_VALUES[0]}" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
target = sys.argv[2]
limit = int(sys.argv[3])
match = next((row for row in data if row["path"] == target), None)
if match is None:
    print(f"FAIL: --report missing entry for {target}", file=sys.stderr)
    sys.exit(1)
if match.get("limit") != limit:
    print(f"FAIL: --report limit mismatch: {match}", file=sys.stderr)
    sys.exit(1)
if match.get("current_lines") != limit + 5:
    print(f"FAIL: --report current_lines mismatch: {match}", file=sys.stderr)
    sys.exit(1)
if match.get("exceed_by") != 5:
    print(f"FAIL: --report exceed_by mismatch: {match}", file=sys.stderr)
    sys.exit(1)
PY

echo "PASS: lint-skill-size selftest"
