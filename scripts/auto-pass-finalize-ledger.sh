#!/usr/bin/env bash
# Purpose: DP-311 T2 — 在 source 仍 LOCKED 的 closeout 階段，把 complete-eligible source
#          對應的 auto-pass ledger terminal_status 推進成 complete。這是 ledger terminal
#          finalize 的 sanctioned deterministic writer（取代 orchestrator prose 補寫）。
# Inputs:  --source-container <abs dir>（必填，DP-backed 或 JIRA Epic-backed container 皆可）
#          --anchor <abs file>（parent anchor；預設依 index.md / refinement.md / plan.md 解析）
#          --ledger <abs file>（預設取 {container}/artifacts/auto-pass/ 最新 *-ledger.json）
#          --source-id <KEY>（與 ledger source.id 交叉比對）
# Outputs: stdout FINALIZED / NOOP 訊息。exit 0 = 寫入成功或 idempotent NOOP；
#          exit 2 = contract violation（stderr 帶 POLARIS_LEDGER_FINALIZE_* marker）。
# NOOP 條件（exit 0、ledger 不動）：anchor 非 LOCKED（含已 IMPLEMENTED 重跑）、archived
#          container（frozen legacy ledger 不碰）、non-complete terminal（loop_cap_reached /
#          blocked_by_gate_failure / user_aborted / paused_for_user_external_write / legacy
#          值）、未解除 pause、container 無 ledger（非 auto-pass source）。
# Ordering: callsite 在 scripts/mark-spec-implemented.sh 的 parent / bare-DP 分支，於翻
#          IMPLEMENTED 之前呼叫（AC-NF1）；task-level path 不觸發（EC7）。
#          validate-auto-pass-ledger.sh 的 LOCKED precondition 維持嚴格，不在此放寬。

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/auto-pass-finalize-ledger.sh --source-container /abs/path/to/container
    [--anchor /abs/path/to/parent-anchor.md]
    [--ledger /abs/path/to/ledger.json]
    [--source-id DP-NNN|EPIC-NNN]
USAGE
  exit 2
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 1
fi

CONTAINER=""
ANCHOR=""
LEDGER=""
SOURCE_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --source-container) CONTAINER="${2:-}"; shift 2 ;;
    --anchor)           ANCHOR="${2:-}"; shift 2 ;;
    --ledger)           LEDGER="${2:-}"; shift 2 ;;
    --source-id)        SOURCE_ID="${2:-}"; shift 2 ;;
    -h|--help)          usage ;;
    *)
      echo "ERROR: unexpected argument: $1" >&2
      usage
      ;;
  esac
done

if [ -z "$CONTAINER" ]; then
  echo "POLARIS_LEDGER_FINALIZE_CONTAINER_MISSING: --source-container is required" >&2
  exit 2
fi
if [ ! -d "$CONTAINER" ]; then
  echo "POLARIS_LEDGER_FINALIZE_CONTAINER_MISSING:${CONTAINER}" >&2
  exit 2
fi

# AC-NEG5: archived container 一律 NOOP——不對 archived container 嘗試 LOCKED-required
# 寫入，也不 migrate frozen archived legacy ledger。
case "$CONTAINER" in
  */specs/design-plans/archive/*|*/specs/companies/*/archive/*)
    echo "NOOP: archived container — frozen ledger untouched (${CONTAINER})"
    exit 0
    ;;
esac

# Description: 解析 parent anchor（未指定 --anchor 時依 mark-spec 同序 fallback）。
# Args:        無（讀 CONTAINER / ANCHOR globals）
# Side effects: 設定 ANCHOR；找不到 anchor 時 exit 2
resolve_anchor() {
  if [ -n "$ANCHOR" ]; then
    [ -f "$ANCHOR" ] && return 0
    echo "POLARIS_LEDGER_FINALIZE_ANCHOR_MISSING:${ANCHOR}" >&2
    exit 2
  fi
  local candidate
  for candidate in "$CONTAINER/index.md" "$CONTAINER/refinement.md" "$CONTAINER/plan.md"; do
    if [ -f "$candidate" ]; then
      ANCHOR="$candidate"
      return 0
    fi
  done
  echo "POLARIS_LEDGER_FINALIZE_ANCHOR_MISSING:${CONTAINER}" >&2
  exit 2
}

resolve_anchor

# anchor 必須仍是 LOCKED 才寫；其他 status（含 IMPLEMENTED 重跑）為 idempotent NOOP。
anchor_status=""
if head -1 "$ANCHOR" | grep -q '^---$'; then
  anchor_status=$(sed -n '/^---$/,/^---$/p' "$ANCHOR" | grep '^status:' | head -1 | sed 's/^status:[[:space:]]*//' || true)
fi
if [ "$anchor_status" != "LOCKED" ]; then
  echo "NOOP: source anchor status is '${anchor_status:-missing}' (not LOCKED) — ledger untouched"
  exit 0
fi

# EC6: 未指定 --ledger 時鎖定本次 closeout 的 ledger = container artifacts 內最新一份
# （檔名 {YYYYMMDD-HHMMSS}-ledger.json，字典序即時間序）；歷史 ledger 不碰。
if [ -z "$LEDGER" ]; then
  shopt -s nullglob
  ledger_candidates=("$CONTAINER"/artifacts/auto-pass/*-ledger.json)
  shopt -u nullglob
  if [ "${#ledger_candidates[@]}" -eq 0 ]; then
    echo "NOOP: no auto-pass ledger under ${CONTAINER}/artifacts/auto-pass/ — nothing to finalize"
    exit 0
  fi
  LEDGER="${ledger_candidates[$((${#ledger_candidates[@]} - 1))]}"
fi
if [ ! -f "$LEDGER" ]; then
  echo "POLARIS_LEDGER_FINALIZE_LEDGER_MISSING:${LEDGER}" >&2
  exit 2
fi

python3 - "$LEDGER" "$CONTAINER" "$SOURCE_ID" <<'PY'
"""Purpose: finalize the auto-pass ledger terminal_status to complete (DP-311 T2).

Inputs: argv[1]=ledger path, argv[2]=source container, argv[3]=expected source id ('' to skip).
Outputs: FINALIZED / NOOP on stdout; POLARIS_LEDGER_FINALIZE_* marker on stderr + exit 2
on contract violation. Atomic in-place rewrite (tmp + os.replace) on the write path only.
"""
import json
import os
import sys
import tempfile
from pathlib import Path

ledger_path = Path(sys.argv[1])
container = sys.argv[2]
expected_source_id = sys.argv[3]

# AC-NEG4: non-complete terminal 一律保留，不得被 closeout chain 改寫成 complete。
# legacy / 未知字串值同樣視為「非 complete 的既有 terminal」保留（不 migrate，AC-NEG5）。
try:
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"POLARIS_LEDGER_FINALIZE_INVALID_JSON:{ledger_path}: {exc}", file=sys.stderr)
    raise SystemExit(2)

source = ledger.get("source") or {}
ledger_container = source.get("container")
if not ledger_container or Path(ledger_container).resolve() != Path(container).resolve():
    print(
        f"POLARIS_LEDGER_FINALIZE_CONTAINER_MISMATCH:{ledger_path}: "
        f"ledger source.container={ledger_container!r} != --source-container={container!r}",
        file=sys.stderr,
    )
    raise SystemExit(2)

if expected_source_id and source.get("id") != expected_source_id:
    print(
        f"POLARIS_LEDGER_FINALIZE_SOURCE_ID_MISMATCH:{ledger_path}: "
        f"ledger source.id={source.get('id')!r} != --source-id={expected_source_id!r}",
        file=sys.stderr,
    )
    raise SystemExit(2)

terminal = ledger.get("terminal_status")
if terminal == "complete":
    print(f"NOOP: ledger already complete ({ledger_path})")
    raise SystemExit(0)
if terminal not in (None, ""):
    print(f"NOOP: non-complete terminal '{terminal}' preserved ({ledger_path})")
    raise SystemExit(0)
if ledger.get("pause"):
    pause_kind = (ledger.get("pause") or {}).get("kind")
    print(f"NOOP: unresolved pause '{pause_kind}' — not finalized ({ledger_path})")
    raise SystemExit(0)

ledger["terminal_status"] = "complete"

fd, tmp_path = tempfile.mkstemp(dir=str(ledger_path.parent), prefix=".finalize-", suffix=".json")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(ledger, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(tmp_path, ledger_path)
except Exception:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print(f"FINALIZED: terminal_status=complete ({ledger_path})")
PY
