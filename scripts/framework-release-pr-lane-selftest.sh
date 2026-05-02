#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/framework-release-pr-lane.sh"
TMPDIR="$(mktemp -d -t framework-release-pr-lane.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

make_task() {
  local file="$1"
  local task_id="$2"
  local base="$3"
  local chain="$4"
  local branch="$5"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<MD
# ${task_id}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | ${task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | ${base} |
| Branch chain | ${chain} |
| Task branch | ${branch} |
| Depends on | N/A |
| References to load | - \`scripts/framework-release-pr-lane.sh\` |
MD
}

write_state() {
  cat > "$TMPDIR/pr-state.tsv" <<'EOF'
task/DP-999-T1-one	1	OPEN	main	1111111111111111111111111111111111111111	https://example.test/pull/1
task/DP-999-T2-two	2	OPEN	task/DP-999-T1-one	2222222222222222222222222222222222222222	https://example.test/pull/2
task/DP-999-T3-three	3	OPEN	task/DP-999-T2-two	3333333333333333333333333333333333333333	https://example.test/pull/3
EOF
}

cat > "$TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
STATE="${FRAMEWORK_PR_LANE_STATE:?}"

cmd="${1:-}"; shift || true
sub="${1:-}"; shift || true
[[ "$cmd $sub" == "pr view" || "$cmd $sub" == "pr edit" || "$cmd $sub" == "pr merge" ]] || {
  echo "unexpected gh command: $cmd $sub $*" >&2
  exit 2
}

if [[ "$cmd $sub" == "pr view" ]]; then
  branch="$1"
  awk -F '\t' -v branch="$branch" '
    $1 == branch {
      printf "{\"number\":%s,\"state\":\"%s\",\"baseRefName\":\"%s\",\"headRefName\":\"%s\",\"headRefOid\":\"%s\",\"mergeStateStatus\":\"CLEAN\",\"url\":\"%s\"}\n", $2, $3, $4, $1, $5, $6
      found=1
    }
    END { if (!found) exit 1 }
  ' "$STATE"
  exit 0
fi

if [[ "$cmd $sub" == "pr edit" ]]; then
  number="$1"; shift
  base=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) base="$2"; shift 2 ;;
      --repo) shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$base" ]] || exit 2
  python3 - "$STATE" "$number" "$base" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
number = sys.argv[2]
base = sys.argv[3]
rows = []
for line in path.read_text().splitlines():
    parts = line.split("\t")
    if parts[1] == number:
        parts[3] = base
    rows.append("\t".join(parts))
path.write_text("\n".join(rows) + "\n")
PY
  exit 0
fi

if [[ "$cmd $sub" == "pr merge" ]]; then
  number="$1"
  python3 - "$STATE" "$number" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
number = sys.argv[2]
rows = []
for line in path.read_text().splitlines():
    parts = line.split("\t")
    if parts[1] == number:
        parts[2] = "MERGED"
    rows.append("\t".join(parts))
path.write_text("\n".join(rows) + "\n")
PY
  exit 0
fi
SH
chmod +x "$TMPDIR/gh"

TASK_DIR="$TMPDIR/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks"
make_task "$TASK_DIR/T1.md" "DP-999-T1" "main" "main -> task/DP-999-T1-one" "task/DP-999-T1-one"
make_task "$TASK_DIR/T2.md" "DP-999-T2" "task/DP-999-T1-one" "main -> task/DP-999-T1-one -> task/DP-999-T2-two" "task/DP-999-T2-two"
make_task "$TASK_DIR/T3.md" "DP-999-T3" "task/DP-999-T2-two" "main -> task/DP-999-T1-one -> task/DP-999-T2-two -> task/DP-999-T3-three" "task/DP-999-T3-three"

export GH_BIN="$TMPDIR/gh"
export FRAMEWORK_PR_LANE_STATE="$TMPDIR/pr-state.tsv"

write_state
bash "$HELPER" --repo "$TMPDIR" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >/tmp/framework-pr-lane-dryrun.out

write_state
bash "$HELPER" --repo "$TMPDIR" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" --execute >/tmp/framework-pr-lane-execute.out
awk -F '\t' '$2 == "2" && $3 == "MERGED" && $4 == "main" { ok=1 } END { exit ok ? 0 : 1 }' "$FRAMEWORK_PR_LANE_STATE"
awk -F '\t' '$2 == "3" && $3 == "MERGED" && $4 == "main" { ok=1 } END { exit ok ? 0 : 1 }' "$FRAMEWORK_PR_LANE_STATE"

write_state
python3 - "$FRAMEWORK_PR_LANE_STATE" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
rows = []
for line in path.read_text().splitlines():
    parts = line.split("\t")
    if parts[1] == "2":
        parts[3] = "main"
    rows.append("\t".join(parts))
path.write_text("\n".join(rows) + "\n")
PY
if bash "$HELPER" --repo "$TMPDIR" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >/tmp/framework-pr-lane-wrong-base.out 2>&1; then
  echo "expected wrong base fixture to fail" >&2
  exit 1
fi
grep -q "expected 'task/DP-999-T1-one'" /tmp/framework-pr-lane-wrong-base.out

echo "[framework-release-pr-lane-selftest] PASS"
