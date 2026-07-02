#!/usr/bin/env bash
# Purpose: friction→DP intake 機械化掃描器（DP-360 D11）。掃描 workspace 內所有
#          auto-pass ledger 的 `friction_log[]`，判定哪些 ledger 的 friction 訊號
#          尚未被轉成 follow-up DP（CONVERTED-vs-UNCONVERTED），把 UN-CONVERTED 的
#          entry 以穩定、可 grep 的格式列為「下一輪 intake」供 /intake-triage 或
#          DP-seeding 步驟消費。純 read-only + idempotent；不 mutate 任何 ledger /
#          report / backlog。
# Inputs:  --root <path>     掃描 root（預設 cwd）。掃描下列兩條 container glob 的
#                            ledger：
#                              <root>/docs-manager/src/content/docs/specs/design-plans/DP-*/artifacts/auto-pass/*-ledger.json
#                              <root>/docs-manager/src/content/docs/specs/companies/*/*/artifacts/auto-pass/*-ledger.json
#          --ledger <path>   只掃單一 ledger（與 --root 互斥）。
#          --json            以 JSON array 輸出（machine consumption）。
# Outputs: stdout 下一輪 intake 清單（text header + per-entry line，或 --json array）；
#          exit 0 = 掃描完成（即使 unconverted>0 也算成功，這是 reporter 不是 gate）；
#          exit 2 = usage / 缺工具 / IO error（fail-closed），stderr 帶 POLARIS_* token。
# Side effects: 無（read-only；不寫檔、不改 git state）。

set -euo pipefail

# CONVERTED 判定的唯一 deterministic 訊號（見 auto-pass-report.md）：一個 ledger 的
# sibling terminal report 若存在且 follow_up_dp_seed 非 null，代表該 ledger 的 friction
# 訊號已被 route 成 follow-up DP seed，視為 CONVERTED；否則 UN-CONVERTED。不另做
# polaris-backlog.md 的 fuzzy text-match（避免第二條 drift 來源）。
INTAKE_SUMMARY_MAX_CHARS=80

ROOT=""
SINGLE_LEDGER=""
JSON_MODE=0

usage() {
  sed -n '2,21p' "$0" >&2
  exit 2
}

die_usage() {
  # Args: $1 = error message。輸出 POLARIS_USAGE token 後 fail-closed。
  echo "POLARIS_USAGE: $1" >&2
  usage
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --ledger) SINGLE_LEDGER="${2:-}"; shift 2 ;;
    --json) JSON_MODE=1; shift ;;
    --help|-h) usage ;;
    -*) die_usage "unknown option: $1" ;;
    *) die_usage "unexpected argument: $1" ;;
  esac
done

if [[ -n "$ROOT" && -n "$SINGLE_LEDGER" ]]; then
  die_usage "--root and --ledger are mutually exclusive"
fi

# 缺工具 fail-stop + repair hint（不靜默安裝）。python3 是 Polaris-runtime tool。
if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3 — run 'mise install' to provision the Polaris runtime" >&2
  exit 2
fi

if [[ -n "$SINGLE_LEDGER" ]]; then
  if [[ ! -f "$SINGLE_LEDGER" ]]; then
    echo "POLARIS_IO_ERROR: --ledger path not found: $SINGLE_LEDGER" >&2
    exit 2
  fi
else
  if [[ -z "$ROOT" ]]; then
    ROOT="$(pwd)"
  fi
  if [[ ! -d "$ROOT" ]]; then
    echo "POLARIS_IO_ERROR: --root path is not a directory: $ROOT" >&2
    exit 2
  fi
fi

PY_ARGS=("$JSON_MODE" "$INTAKE_SUMMARY_MAX_CHARS" "$SINGLE_LEDGER" "$ROOT")

python3 - "${PY_ARGS[@]}" <<'PY'
"""Purpose: friction→DP intake 掃描器本體。

讀取一組 auto-pass ledger，依「sibling report.follow_up_dp_seed 非 null」判定
CONVERTED，把 UN-CONVERTED 的 friction_log[] entry 以 deterministic 排序輸出為
下一輪 intake（text 或 JSON）。純 read-only。
"""
import json
import sys
from pathlib import Path

json_mode = sys.argv[1] == "1"
summary_max = int(sys.argv[2])
single_ledger = sys.argv[3]
root = sys.argv[4]


def fail(token: str, message: str) -> None:
    """以 POLARIS_* token fail-closed 退出（exit 2）。"""
    print(f"{token}: {message}", file=sys.stderr)
    sys.exit(2)


def discover_ledgers(root_dir: Path) -> list[Path]:
    """枚舉 root 下 active 與 archived container glob 的所有 ledger，依絕對路徑排序去重。

    掃描四條 container glob，涵蓋 DP-backed 與 JIRA-Epic-backed source 各自的 active 與
    archive lifecycle 位置。archive glob 確保 release-tail friction 不因 DP / Epic 被移到
    `.../archive/` 而從 intake 靜默消失（DP-393 T3）。

    Args:
        root_dir: 掃描 root。

    Returns:
        排序後的 ledger 路徑清單（deterministic）。
    """
    specs = root_dir / "docs-manager" / "src" / "content" / "docs" / "specs"
    # 四條 glob：active DP / active company / archived DP / archived company。archive glob
    # 對齊 archive-spec.sh 的搬移目的地（design-plans/archive/DP-*、companies/*/archive/*），
    # 是為了掃描而擴充，不改動 is_converted() 的 CONVERTED 判定。
    patterns = [
        "design-plans/DP-*/artifacts/auto-pass/*-ledger.json",
        "companies/*/*/artifacts/auto-pass/*-ledger.json",
        "design-plans/archive/DP-*/artifacts/auto-pass/*-ledger.json",
        "companies/*/archive/*/artifacts/auto-pass/*-ledger.json",
    ]
    found: set[Path] = set()
    for pattern in patterns:
        for path in specs.glob(pattern):
            if path.is_file():
                found.add(path)
    return sorted(found, key=lambda p: str(p))


def derive_source_id(ledger_path: Path) -> str:
    """從 ledger 路徑推導 source id（DP-NNN 或 JIRA-Epic 的 container 目錄名）。

    Args:
        ledger_path: ledger 絕對路徑（.../<source-dir>/artifacts/auto-pass/<file>）。

    Returns:
        source container 目錄名；無法推導時回 'unknown'。
    """
    # <source-dir>/artifacts/auto-pass/<ledger>.json
    parts = ledger_path.parts
    try:
        auto_pass_idx = len(parts) - 1 - parts[::-1].index("auto-pass")
    except ValueError:
        return "unknown"
    # source-dir = auto-pass 的祖父層（auto-pass <- artifacts <- source-dir）
    source_idx = auto_pass_idx - 2
    if source_idx >= 0:
        return parts[source_idx]
    return "unknown"


def is_converted(ledger_path: Path) -> bool:
    """判定 ledger 的 friction 是否已轉 DP（CONVERTED）。

    規則：sibling terminal report（同目錄 *-report.json）存在且 follow_up_dp_seed
    非 null → CONVERTED。任一 sibling report 滿足即視為 CONVERTED。

    Args:
        ledger_path: ledger 絕對路徑。

    Returns:
        True 表示 CONVERTED；False 表示 UN-CONVERTED。
    """
    report_dir = ledger_path.parent
    for report_path in sorted(report_dir.glob("*-report.json"), key=lambda p: str(p)):
        if not report_path.is_file():
            continue
        try:
            report = json.loads(report_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            # 壞 report 不主張 CONVERTED：保守視為「尚未確認轉換」，繼續看下一個。
            continue
        if not isinstance(report, dict):
            continue
        if report.get("follow_up_dp_seed") is not None:
            return True
    return False


def load_friction_log(ledger_path: Path) -> list:
    """讀取並驗證 ledger 的 friction_log[]。

    Args:
        ledger_path: ledger 絕對路徑。

    Returns:
        friction_log entry 清單（缺欄位回空清單）。

    壞 JSON / 結構不符時 fail-closed（exit 2）。
    """
    try:
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    except OSError as exc:
        fail("POLARIS_IO_ERROR", f"ledger could not be read: {ledger_path} ({exc})")
    except json.JSONDecodeError as exc:
        fail("POLARIS_LEDGER_MALFORMED", f"ledger invalid JSON: {ledger_path} ({exc})")
    if not isinstance(ledger, dict):
        fail("POLARIS_LEDGER_MALFORMED", f"ledger root must be an object: {ledger_path}")
    friction_log = ledger.get("friction_log", [])
    if friction_log is None:
        friction_log = []
    if not isinstance(friction_log, list):
        fail(
            "POLARIS_LEDGER_MALFORMED",
            f"ledger.friction_log must be an array: {ledger_path}",
        )
    return friction_log


if single_ledger:
    ledgers = [Path(single_ledger).resolve()]
else:
    ledgers = discover_ledgers(Path(root).resolve())

ledgers_scanned = len(ledgers)
unconverted_entries = []

for ledger_path in ledgers:
    if is_converted(ledger_path):
        continue
    source_id = derive_source_id(ledger_path)
    ledger_basename = ledger_path.name
    for entry in load_friction_log(ledger_path):
        if not isinstance(entry, dict):
            continue
        unconverted_entries.append(
            {
                "source": source_id,
                "ledger": ledger_basename,
                "ts": str(entry.get("ts", "")),
                "kind": str(entry.get("friction_kind", "")),
                "summary": str(entry.get("summary", "")),
            }
        )

# Deterministic 排序：先 source id，再 ts（穩定且可重現）。
unconverted_entries.sort(key=lambda e: (e["source"], e["ts"], e["ledger"], e["kind"]))

if json_mode:
    payload = {
        "unconverted": len(unconverted_entries),
        "ledgers_scanned": ledgers_scanned,
        "entries": unconverted_entries,
    }
    print(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True))
else:
    print(
        f"friction-intake unconverted={len(unconverted_entries)} "
        f"ledgers-scanned={ledgers_scanned}"
    )
    for entry in unconverted_entries:
        summary = entry["summary"][:summary_max]
        print(
            f"INTAKE source={entry['source']} ledger={entry['ledger']} "
            f"ts={entry['ts']} kind={entry['kind']} summary={summary}"
        )

sys.exit(0)
PY
