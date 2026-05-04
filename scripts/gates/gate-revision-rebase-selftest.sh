#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/gate-revision-rebase.sh"

tmp="$(mktemp -d -t gate-revision-rebase-selftest.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

mk_repo() {
  local repo="$1" branch="$2"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email selftest@example.test
  git -C "$repo" config user.name "Self Test"
  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "base"
  git -C "$repo" checkout -q -b "$branch"
  printf 'change\n' >> "$repo/README.md"
  git -C "$repo" commit -q -am "change"
}

mk_fake_gh() {
  local bin="$1" mode="$2"
  mkdir -p "$bin"
  cat > "$bin/gh" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}/\${2:-}" = "pr/view" ]; then
  if [ "$mode" = "has-pr" ]; then
    printf '{"number":123,"baseRefName":"main"}\n'
    exit 0
  fi
  exit 1
fi
exit 1
EOF
  chmod +x "$bin/gh"
}

write_evidence() {
  local file="$1" repo="$2" ticket="$3" head="$4" status="${5:-not_needed}"
  mkdir -p "$(dirname "$file")"
  python3 - "$file" "$repo" "$ticket" "$head" "$status" <<'PY'
import json
import pathlib
import sys

file, repo, ticket, head, status = sys.argv[1:6]
pathlib.Path(file).write_text(json.dumps({
    "repo": repo,
    "task_md": "/tmp/task.md",
    "branch": "task/TASK-1234-demo",
    "head_sha": head,
    "evidence_ids": [ticket],
    "resolved_base": "main",
    "rebase_status": status,
    "pr_number": 123,
    "pr_base_before": "main",
    "pr_base_after": "main",
    "pr_base_synced": False,
    "writer": "revision-rebase.sh",
    "at": "2026-05-05T00:00:00Z",
}) + "\n", encoding="utf-8")
PY
}

# 1. No existing PR: allow first-cut push.
repo1="$tmp/repo1"
mk_repo "$repo1" "task/TASK-1234-demo"
mk_fake_gh "$tmp/bin-no-pr" "no-pr"
PATH="$tmp/bin-no-pr:$PATH" POLARIS_EVIDENCE_ROOT="$tmp/evidence1" bash "$GATE" --repo "$repo1" >/tmp/gate-rr-1.out 2>&1

# 2. Existing PR + missing evidence: block.
repo2="$tmp/repo2"
mk_repo "$repo2" "task/TASK-1234-demo"
mk_fake_gh "$tmp/bin-has-pr" "has-pr"
if PATH="$tmp/bin-has-pr:$PATH" POLARIS_EVIDENCE_ROOT="$tmp/evidence2" bash "$GATE" --repo "$repo2" >/tmp/gate-rr-2.out 2>&1; then
  echo "[selftest] expected missing evidence to block" >&2
  cat /tmp/gate-rr-2.out >&2
  exit 1
fi
grep -q "BLOCKED: existing PR" /tmp/gate-rr-2.out

# 3. Existing PR + matching durable evidence: pass.
head2="$(git -C "$repo2" rev-parse HEAD)"
ev2="$tmp/evidence2/revision-rebase/polaris-revision-rebase-TASK-1234-${head2}.json"
write_evidence "$ev2" "$repo2" "TASK-1234" "$head2"
PATH="$tmp/bin-has-pr:$PATH" POLARIS_EVIDENCE_ROOT="$tmp/evidence2" bash "$GATE" --repo "$repo2" >/tmp/gate-rr-3.out 2>&1
grep -q "revision-rebase evidence valid" /tmp/gate-rr-3.out

# 4. Existing PR + stale/malformed status: block.
write_evidence "$ev2" "$repo2" "TASK-1234" "$head2" "conflict"
if PATH="$tmp/bin-has-pr:$PATH" POLARIS_EVIDENCE_ROOT="$tmp/evidence2" bash "$GATE" --repo "$repo2" >/tmp/gate-rr-4.out 2>&1; then
  echo "[selftest] expected conflict evidence to block" >&2
  cat /tmp/gate-rr-4.out >&2
  exit 1
fi
grep -q "malformed or stale" /tmp/gate-rr-4.out

rm -f /tmp/gate-rr-1.out /tmp/gate-rr-2.out /tmp/gate-rr-3.out /tmp/gate-rr-4.out
echo "[gate-revision-rebase-selftest] PASS"
