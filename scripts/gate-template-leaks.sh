#!/usr/bin/env bash
# 為什麼這一道還在（門檻 2026-08-13，見 .claude/instructions/core/bootstrap.md）：
#   live company slug 進公開的 template repo。push 出去收不回來，而它藏在一份正常的 CHANGELOG 裡。
set -euo pipefail

# gate-template-leaks.sh
#
# Workspace PR-time / push-time gate: scan tracked files for template leaks
# (live company slug, JIRA prefix, internal Slack ID, internal URL) before they
# can reach a workspace PR or be pushed to remote. Wraps scripts/scan-template-leaks.sh
# in workspace mode with --blocking so leak scan failure exits non-zero.
#
# Recurrence prevention contract (rules/framework-iteration.md
# § "Template-Facing Examples Must Be Generic"):
#   * scan-template-leaks was previously only invoked inside sync-to-polaris.sh
#     (post-merge). By the time leaks were detected the workspace PR had already
#     merged, forcing a hard-reset + replacement PR.
#   * This gate runs the same scan at workspace PR creation (via
#     scripts/check-framework-pr-gate.sh) and at git push time (it is one of the
#     gates run-gates.sh runs, and scripts/githooks/pre-push
#     calls that) so leaks are caught before merge.

PREFIX="[polaris gate-template-leaks]"
REPO_ROOT=""

usage() {
  cat >&2 <<EOF
Usage: bash scripts/gate-template-leaks.sh [--repo <path>]

Runs scripts/scan-template-leaks.sh --blocking against the workspace root. Exits 0
on no material hits; exits 1 on hits; exits 2 on usage or environment error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) shift ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi

if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT" ]]; then
  echo "$PREFIX ERROR: cannot resolve repo root (--repo not given and not in git)." >&2
  exit 2
fi

SCAN="$REPO_ROOT/scripts/scan-template-leaks.sh"
if [[ ! -x "$SCAN" ]]; then
  echo "$PREFIX ERROR: scan-template-leaks.sh missing or not executable at $SCAN" >&2
  exit 2
fi

# v3.85.0 read the delivery record here and, for a destination=template push,
# dropped the scan's company carve-outs over the changed paths. The reasoning was
# that those carve-outs rest on "company surfaces never sync", which a template-bound
# delivery invalidates. Measured afterwards, it does not: sync copies
# .claude/rules/*.md at one level only and skips skills declaring company or personal, so
# the carved-out set and the copied set do not intersect for any destination, and
# sync re-scans the template tree itself after copying. The strict reading therefore
# added no detection the default scan lacks — this round's own leak, in an L1 rule,
# was caught by the plain scan — while blocking the first delivery that legitimately
# touched a company handbook. The premise was mine and was never measured; the
# wiring is gone rather than worked around.

# 追蹤範圍裡有沒有一支宣告不在表上的 skill。
#
# 這一段折進這道閘，不另開閘檔：它守的是同一條邊界（追蹤範圍 → 公開 repo），而且這道閘
# 本來就每次 commit 掃全部追蹤檔。同步那一端已經是正向表列了，所以一支宣告拼錯的 skill
# 不會出去——**看不出來的是它為什麼沒出去**。宣告錯的那一刻它就在 diff 裡；不指名的話，
# 下一次有人問「這支怎麼沒同步過去」，答案要從一份沉默裡挖出來。
echo "$PREFIX checking tracked SKILL.md declarations..." >&2
if ! python3 - "$REPO_ROOT" "$PREFIX" <<'DECLCHECK'
import os
import subprocess
import sys

root, prefix = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(
    root, "scripts", "lib"))
from skill_scope import declared_scope, WORKSPACE_FACING  # noqa: E402

listed = subprocess.run(
    ["git", "-C", root, "ls-files", "-z", "--", ".claude/skills/"],
    check=True, capture_output=True).stdout.decode()
paths = [p for p in listed.split("\0")
         if p and os.path.basename(p) == "SKILL.md"]
if not paths:
    # 掃到 0 個檔案跟「全部都對」在輸出上長得一樣。這是第三態，說出來。
    print(f"{prefix} 量不到：追蹤範圍裡一個 SKILL.md 都沒有。", file=sys.stderr)
    raise SystemExit(1)

table = ", ".join(sorted(WORKSPACE_FACING))
bad = [(rel, declared_scope(os.path.join(root, rel))) for rel in paths]
bad = [(rel, scope) for rel, scope in bad if scope not in WORKSPACE_FACING]
for rel, scope in bad:
    said = f"宣告 {scope}" if scope else "沒有宣告 scope"
    print(f"{prefix}   {rel} — {said}，不在表上（{table}）", file=sys.stderr)
if bad:
    print(f"{prefix} BLOCKED: {len(bad)} 支 skill 的宣告不在表上。`scope:` 只回答"
          f"「帶到哪」，值就是上面那幾個——補上或改對再 commit。", file=sys.stderr)
    raise SystemExit(1)
print(f"{prefix} \u2705 {len(paths)} 支 skill 的宣告都在表上。", file=sys.stderr)
DECLCHECK
then
  exit 1
fi

echo "$PREFIX scanning workspace tracked files for template leaks..." >&2
"$SCAN" --workspace "$REPO_ROOT" --source workspace --blocking && scan_rc=0 || scan_rc=$?

if [[ "$scan_rc" -eq 0 ]]; then
  echo "$PREFIX ✅ no material template leaks." >&2
  exit 0
fi

# 量不到與量到了東西是兩件事，這道閘不得把它們收斂成同一句話。以前這裡對任何非 0 都印
# 「BLOCKED: 有外洩」——於是一次什麼都沒掃到的執行，會被讀成一次抓到東西的執行。
if [[ "$scan_rc" -eq 2 ]]; then
  echo "$PREFIX 量不到：掃描沒有判定（理由在上面）。這不是「有外洩」，也不是「乾淨」。" >&2
  exit 2
fi

# scan-template-leaks already emitted POLARIS_TEMPLATE_LEAK summary to stderr.
echo "$PREFIX BLOCKED: workspace contains template leak hits. 面向 template 的例子要寫成通用的——把 live 的公司名換成佔位符再推。" >&2
exit 1
