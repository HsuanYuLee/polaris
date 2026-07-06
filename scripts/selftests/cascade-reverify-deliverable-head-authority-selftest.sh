#!/usr/bin/env bash
# Purpose: regression selftest for cascade --onto reverify metadata. The rebased
# aggregate head must be written under deliverable.verification while the
# top-level deliverable.head_sha remains the task PR head authority.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASCADE="${ROOT}/scripts/cascade-rebase-chain.sh"

tmp="$(mktemp -d -t cascade-reverify-head-authority.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
verify_stub="$tmp/run-verify-stub.sh"
task_rel="docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks/T1/index.md"
task="$repo/$task_rel"

cat >"$verify_stub" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
task_md=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) task_md="${2:-}"; shift 2 ;;
    --repo) shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$task_md" && -f "$task_md" ]]
SH
chmod +x "$verify_stub"

git init -q -b main "$repo"
git -C "$repo" config user.email selftest@example.com
git -C "$repo" config user.name selftest

mkdir -p "$(dirname "$task")"
printf 'base\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m "base"

git -C "$repo" checkout -q -b feat/DP-999
printf 'task-pr-head\n' >"$repo/task.txt"
git -C "$repo" add task.txt
git -C "$repo" commit -q -m "task pr head"
task_pr_head="$(git -C "$repo" rev-parse HEAD)"

cat >"$task" <<MD
---
deliverable:
  pr_url: https://github.com/example/repo/pull/999
  pr_state: OPEN
  head_sha: ${task_pr_head}
  verification:
    status: PASS
    evidence_path: /tmp/original-verify.json
---

# DP-999-T1
MD
git -C "$repo" add "$task_rel"
git -C "$repo" commit -q -m "record task deliverable"

git -C "$repo" checkout -q main
printf 'main advance\n' >>"$repo/README.md"
git -C "$repo" commit -q -am "main advances"

git -C "$repo" checkout -q feat/DP-999
out="$tmp/cascade.out"
POLARIS_RUN_VERIFY_COMMAND="$verify_stub" bash "$CASCADE" --repo "$repo" --onto main >"$out"

aggregate_head="$(git -C "$repo" rev-parse HEAD)"

python3 - "$task" "$task_pr_head" "$aggregate_head" "$out" <<'PY'
from pathlib import Path
import re
import sys

task_path, task_pr_head, aggregate_head, output_path = sys.argv[1:5]
text = Path(task_path).read_text(encoding="utf-8")
fm = text.split("---", 2)[1]
out = Path(output_path).read_text(encoding="utf-8")

def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")

require(f"  head_sha: {task_pr_head}" in fm, "top-level deliverable.head_sha changed away from task PR head")
require(f"    aggregate_head_sha: {aggregate_head}" in fm, "verification aggregate_head_sha missing or stale")
require(f"  head_sha: {aggregate_head}" not in fm, "aggregate head leaked into top-level deliverable.head_sha")
require('"task_pr_head_sha"' in out, "reverify evidence missing task_pr_head_sha")
require('"aggregate_head_sha"' in out, "reverify evidence missing aggregate_head_sha")
require('"head_sha"' not in out, "reverify evidence still emits ambiguous head_sha")
require(len(re.findall(r"^deliverable:", fm, flags=re.MULTILINE)) == 1, "deliverable block duplicated")
require(len(re.findall(r"^  verification:", fm, flags=re.MULTILINE)) == 1, "verification block duplicated")
PY

echo "[cascade-reverify-deliverable-head-authority-selftest] PASS"
