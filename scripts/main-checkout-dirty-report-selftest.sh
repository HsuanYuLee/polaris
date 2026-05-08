#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT="${SCRIPT_DIR}/main-checkout-dirty-report.sh"

make_fixture() {
  local tmp="$1"
  local origin="${tmp}/origin.git"
  local repo="${tmp}/repo"

  git init --bare "$origin" >/dev/null
  git clone "$origin" "$repo" >/dev/null 2>&1
  git -C "$repo" config user.email selftest@example.test
  git -C "$repo" config user.name "Self Test"
  echo base >"${repo}/shared.txt"
  echo local >"${repo}/local-only.txt"
  git -C "$repo" add shared.txt local-only.txt
  git -C "$repo" commit -m "base" >/dev/null
  git -C "$repo" push -u origin main >/dev/null 2>&1
  printf '%s\n%s\n' "$origin" "$repo"
}

assert_json() {
  local json_path="$1"
  local python_check="$2"
  python3 - "$json_path" "$python_check" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
code = compile(sys.argv[2], "<assert>", "exec")
ns = {"payload": payload}
exec(code, ns, ns)
PY
}

run_clean_behind_case() {
  local tmp repos origin repo peer report_json
  tmp="$(mktemp -d -t main-checkout-dirty-clean.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN
  repos="$(make_fixture "$tmp")"
  origin="$(printf '%s\n' "$repos" | sed -n '1p')"
  repo="$(printf '%s\n' "$repos" | sed -n '2p')"
  peer="${tmp}/peer"
  git clone "$origin" "$peer" >/dev/null 2>&1
  git -C "$peer" config user.email selftest@example.test
  git -C "$peer" config user.name "Self Test"
  echo upstream >>"${peer}/shared.txt"
  git -C "$peer" add shared.txt
  git -C "$peer" commit -m "upstream" >/dev/null
  git -C "$peer" push origin main >/dev/null 2>&1
  git -C "$repo" fetch origin main >/dev/null 2>&1

  report_json="${tmp}/clean-behind.json"
  bash "$REPORT" --repo "$repo" --format json >"$report_json"
  assert_json "$report_json" $'assert payload["behind"] == 1\nassert payload["tracked_dirty_count"] == 0\nassert payload["overlap_dirty_count"] == 0\nassert payload["local_only_dirty_count"] == 0'
}

run_mixed_partition_case() {
  local tmp repos origin repo peer worktree report_json
  tmp="$(mktemp -d -t main-checkout-dirty-mixed.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN
  repos="$(make_fixture "$tmp")"
  origin="$(printf '%s\n' "$repos" | sed -n '1p')"
  repo="$(printf '%s\n' "$repos" | sed -n '2p')"
  peer="${tmp}/peer"
  git clone "$origin" "$peer" >/dev/null 2>&1
  git -C "$peer" config user.email selftest@example.test
  git -C "$peer" config user.name "Self Test"
  echo upstream >>"${peer}/shared.txt"
  git -C "$peer" add shared.txt
  git -C "$peer" commit -m "upstream" >/dev/null
  git -C "$peer" push origin main >/dev/null 2>&1
  git -C "$repo" fetch origin main >/dev/null 2>&1

  echo local-change >>"${repo}/shared.txt"
  echo local-change >>"${repo}/local-only.txt"
  worktree="${tmp}/report-wt"
  git -C "$repo" worktree add --detach "$worktree" HEAD >/dev/null 2>&1

  report_json="${tmp}/mixed.json"
  bash "$REPORT" --repo "$worktree" --format json >"$report_json"
  assert_json "$report_json" $'assert payload["main_checkout"].endswith("/repo")\nassert payload["behind"] == 1\nassert payload["tracked_dirty_count"] == 2\nassert payload["overlap_dirty_count"] == 1\nassert payload["local_only_dirty_count"] == 1\nassert payload["overlap_dirty_files"] == ["shared.txt"]\nassert payload["local_only_dirty_files"] == ["local-only.txt"]'
}

run_clean_behind_case
run_mixed_partition_case

echo "PASS: main checkout dirty report selftest"
