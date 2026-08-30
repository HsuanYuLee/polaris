#!/usr/bin/env bash
# Measurement-change ledger: the paper trail behind a swapped oracle command.
#
# The assertion layer is frozen; the measurement layer is deliberately open so a
# loop can improve how it measures without waking a human. The hole that opens
# is that an implementation could quietly swap in a command that measures
# nothing. This ledger closes it by making every swap carry a triple:
#
#   old command hash -> new command hash -> evidence the new command went red
#                                           before the implementation existed
#
# A command that cannot go red measured nothing, so evidence whose failure is an
# environment error (interpreter missing, not executable, tool absent) is
# rejected the same way a green "red evidence" is.
#
# Hashing is delegated to frozen-assertion-fence.sh. There is exactly one hash
# implementation in this spine.
#
# Subcommands:
#   record --ledger <p> --assertion-id <id> --new-command <cmd> --baseline
#   record --ledger <p> --assertion-id <id> --new-command <cmd>
#          --old-command <cmd> --red-evidence <path>
#   verify --ledger <p> --assertion-id <id> --command <cmd>
#   show   --ledger <p> [--assertion-id <id>]
#
# Red evidence is a JSON file:
#   {"command": "<verbatim new command>", "command_exit_code": 3,
#    "recorded_at": "2026-08-01T10:00:00Z", "head_sha": "<sha at capture>",
#    "stderr": "...", "stdout": "..."}
#
# 欄位名以 run-hardened-oracle.sh 寫出來的那份為準（見下方讀取處的註解）。這幾行以前寫的是
# exit_code / captured_at，而程式讀的是 command_exit_code / recorded_at——2026-08-27 手寫一份反向對照組證據時撞到。
#
# What this gate proves mechanically: the evidence exists, binds to this exact
# command, records a genuine non-zero exit, and is not an environment error; and
# the ledger chain is continuous. Capture ordering is carried as recorded fact
# (captured_at must precede the record) rather than claimed in prose.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FENCE="$SCRIPT_DIR/frozen-assertion-fence.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  record-measurement-change.sh record --ledger <path> --assertion-id <id> \
      --new-command <cmd> --baseline
  record-measurement-change.sh record --ledger <path> --assertion-id <id> \
      --new-command <cmd> --old-command <cmd> --red-evidence <path>
  （兩種 record 都可加 --exempt-path <字串> --exempt-why <理由>）
  record-measurement-change.sh verify --ledger <path> --assertion-id <id> --command <cmd>
  record-measurement-change.sh show --ledger <path> [--assertion-id <id>]
EOF
}

# NO-CALLER: --exempt-path — 這棵樹上沒有一張單需要它。留著是因為它是「命令裡不准有這台
# 機器的路徑」那道拒絕唯一的出路，而那道拒絕會直接讓命令登錄不進去；一道沒有出路的關卡
# 會被整個繞過。理由跟豁免一起寫進登錄，所以用過的痕跡在 diff 裡看得見。
# NO-CALLER: --exempt-why — 上面那個的另一半。兩個一定成對，只給一個是用法錯誤。

die() {
  # Description: emit a POLARIS marker plus human message, then fail closed.
  # Args: $1 = marker, $2.. = message
  local marker="$1"
  shift
  echo "$marker" >&2
  echo "$*" >&2
  exit 2
}

require_python3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:python3" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
}

reject_machine_paths() {
  # Description: refuse a measurement command that writes down where it is
  #              instead of asking (DP-496 L-P3). Always says what it measured.
  # Args: $1 = command string, $2 = label for messages, $3.. = exempt substrings
  # Exit:  非 0 並印出 POLARIS_MEASUREMENT_COMMAND_CARRIES_A_PATH 時代表擋下來了。
  #
  # 判準只有一條：命令字串裡不得出現這台機器的家目錄的**字面值**。它一句話蓋掉三種
  # ——單的目錄、落腳的工作區、家目錄下的東西——因為那三種在這台機器上都以家目錄開頭。
  # 規則本身不綁機器：每一台各自拿自己的 $HOME 比。
  #
  # 每一種都有一個當場問得到的來源，所以這不是「不准指過去」，是「不准把答案抄下來」：
  #   單的目錄       → spine-loop-state.sh find
  #   落腳的工作區   → spine-loop-state.sh landing
  #   命令跑在哪     → 由執行者供給（run-hardened-oracle.sh --cwd），命令自己不提
  #   家目錄下的東西 → 寫 $HOME，不要寫展開後的值
  #
  # 最後那一條不是 L-N3 禁止的「特殊寫法」：L-N3 擋的是為了讓 hash 穩定而發明的編碼
  # （glob、佔位符），那些仍然在講位置。`$HOME` 不講位置，它就是在問。
  local command_str="$1" label="$2"
  shift 2
  local home="${HOME:-}"
  if [[ -z "$home" ]]; then
    die "POLARIS_MEASUREMENT_PATH_CHECK_UNMEASURABLE" \
      "\$HOME 是空的，這一次沒辦法判斷命令裡有沒有寫死路徑——不放行，因為量不到不是通過"
  fi

  case "$command_str" in
    *"$home"*) ;;
    *) echo "[measurement] ${label}：命令裡沒有寫死這台機器的路徑" >&2; return 0 ;;
  esac

  local exempt
  for exempt in "$@"; do
    [[ -n "$exempt" ]] || continue
    case "$command_str" in
      *"$exempt"*)
        echo "[measurement] ${label}：命中豁免「${exempt}」，放行" >&2
        return 0 ;;
    esac
  done

  die "POLARIS_MEASUREMENT_COMMAND_CARRIES_A_PATH" \
    "${label} 把這台機器的路徑抄進命令裡了（含 ${home}）。位置會變，抄下來的就是死指標——
單的目錄問 spine-loop-state.sh find、落腳的工作區問 spine-loop-state.sh landing、
命令跑在哪由執行者供給、家目錄底下的東西寫 \$HOME。
真的三種都不是的話，用 --exempt-path 與 --exempt-why 具名寫進登錄。"
}

reject_written_down_position() {
  # Description: refuse a measurement command that writes down **where this ticket
  #              currently sits** instead of asking at run time (DP-595 A-P1).
  # Args: $1 = command string, $2 = ledger path, $3 = label, $4.. = exempt substrings
  # Exit:  非 0 並印出 POLARIS_MEASUREMENT_COMMAND_CARRIES_A_POSITION 時代表擋下來了。
  #
  # 判準：命令字串裡不得出現「斜線＋這張單自己的目錄名」。寫下那一段，就是把單當下所在的
  # 那一格抄進去了——而格子是狀態的投影，`record` 與釋出尾段都會重算它，於是那條路徑在下
  # 一次重算之後就是死指標。
  #
  # 它蓋掉三種寫法，因為三種都帶著那一段：
  #   /Users/…/issues/{命名空間}/in-progress/{單}/probes/x.sh   展開後的絕對路徑
  #   $HOME/…/issues/{命名空間}/in-progress/{單}/probes/x.sh    以 $HOME 開頭（上面那道放行的）
  #   ../../../../issues/{命名空間}/in-progress/{單}/scripts/x.py  相對於另一棵樹
  #
  # 收得下的那一種不含它：`$(… spine-loop-state.sh find <單名>)/probes/x.sh` 只出現單名，
  # 前面沒有斜線——它在問，不是在抄。
  local command_str="$1" ledger="$2" label="$3"
  shift 3
  local issue_dir issue_name
  issue_dir="$(dirname "$(dirname "$ledger")")"
  issue_name="$(basename "$issue_dir")"
  case "$issue_name" in
    ""|"."|".."|"/")
      echo "[measurement] ${label}：從登錄檔的位置（${ledger}）解不出這是哪一張單，這一條判準這一次沒有量到" >&2
      return 0 ;;
  esac

  case "$command_str" in
    *"/$issue_name"*) ;;
    *) echo "[measurement] ${label}：命令裡沒有寫下這張單的位置（找的是「/${issue_name}」）" >&2; return 0 ;;
  esac

  local exempt
  for exempt in "$@"; do
    [[ -n "$exempt" ]] || continue
    case "$command_str" in
      *"$exempt"*)
        echo "[measurement] ${label}：命中豁免「${exempt}」，放行" >&2
        return 0 ;;
    esac
  done

  die "POLARIS_MEASUREMENT_COMMAND_CARRIES_A_POSITION" \
    "${label} 把這張單當下所在的位置抄進命令裡了（字串裡有「/${issue_name}」）。
格子是狀態的投影，record 與釋出尾段都會重算它——抄下來的那條路徑在下一次重算之後就是死指標，
而重跑時它只會說「開不到檔」。改成執行當下才問位置：
  bash \"\$(bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh find ${issue_name})/probes/probe.sh\"
不要在後面接 | tail -1：find 命中不是剛好一個的時候會回非 0，而那個離場碼會被 tail 吃掉。
真的不是在講位置的話，用 --exempt-path 與 --exempt-why 具名寫進登錄。"
}

command_hash() {
  # Description: hash a command string through the single spine hash helper.
  # Args: $1 = command string
  [[ -x "$FENCE" || -f "$FENCE" ]] \
    || die "POLARIS_MEASUREMENT_HASH_HELPER_MISSING" "frozen-assertion-fence.sh not found at $FENCE"
  printf '%s' "$1" | bash "$FENCE" hash --stdin
}

file_hash() {
  # Description: hash a file through the single spine hash helper.
  # Args: $1 = file path
  bash "$FENCE" hash --file "$1"
}

latest_new_hash() {
  # Description: print the currently sanctioned command hash for an assertion,
  #              bare (no `sha256:` prefix) so it compares against command_hash.
  # Args: $1 = ledger path, $2 = assertion id
  # Side effects: none; prints nothing when the assertion has no entry yet.
  require_python3
  python3 - "$1" "$2" <<'PY'
import json
import os
import sys

ledger, assertion = sys.argv[1:3]
if not os.path.exists(ledger):
    sys.exit(0)
try:
    data = json.load(open(ledger, encoding="utf-8"))
except (json.JSONDecodeError, OSError):
    print("POLARIS_MEASUREMENT_LEDGER_UNREADABLE", file=sys.stderr)
    sys.exit(2)
for entry in reversed(data.get("entries", [])):
    if entry.get("assertion_id") == assertion:
        print(entry.get("new_command_hash", "").removeprefix("sha256:"))
        break
PY
}

recorded_exemption() {
  # Description: print the path exemption recorded for an assertion's current
  #              command, or nothing. Judgement reads the exemption off the very
  #              record it is judging, so a hand-added exemption is a diff.
  # Args: $1 = ledger path, $2 = assertion id
  require_python3
  python3 - "$1" "$2" <<'PY'
import json
import os
import sys

ledger, assertion = sys.argv[1:3]
if not os.path.exists(ledger):
    sys.exit(0)
try:
    data = json.load(open(ledger, encoding="utf-8"))
except (json.JSONDecodeError, OSError):
    sys.exit(0)
for entry in reversed(data.get("entries", [])):
    if entry.get("assertion_id") == assertion:
        print((entry.get("path_exemption") or {}).get("path", ""))
        break
PY
}

validate_red_evidence() {
  # Description: fail closed unless the evidence proves a real red run of this command.
  # Args: $1 = evidence path, $2 = new command string
  # Side effects: exits 2 with a POLARIS_MEASUREMENT_* marker on any violation.
  local evidence="$1" new_command="$2"

  [[ -f "$evidence" ]] \
    || die "POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING" \
      "no red evidence at '$evidence'; a measurement command that was never seen failing measured nothing"

  require_python3
  python3 - "$evidence" "$new_command" <<'PY'
import json
import re
import sys

path, new_command = sys.argv[1:3]

# A failure that only proves the command could not start proves nothing about
# what the command measures.
ENVIRONMENT_EXIT_CODES = {126, 127}
ENVIRONMENT_PATTERNS = (
    r"command not found",
    r"No such file or directory",
    r"Permission denied",
    r"POLARIS_TOOL_MISSING",
    r"executable file not found",
)

def fail(marker, message):
    print(marker, file=sys.stderr)
    print(message, file=sys.stderr)
    sys.exit(2)

try:
    data = json.load(open(path, encoding="utf-8"))
except (json.JSONDecodeError, OSError) as exc:
    fail("POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING",
         f"red evidence at {path} is not readable JSON: {exc}")

if data.get("command") != new_command:
    fail("POLARIS_MEASUREMENT_EVIDENCE_COMMAND_MISMATCH",
         "red evidence records a different command than the one being registered\n"
         f"  evidence: {data.get('command')!r}\n"
         f"  new:      {new_command!r}")

# Field names come from the only producer of these records,
# run-hardened-oracle.sh. They were once read under different names here
# (exit_code / captured_at), which nothing ever caught because this script's
# fixtures wrote those names too — so the two halves of the one measurement-change
# path agreed with their own tests and with nothing else. The first real handoff
# between them failed closed.
exit_code = data.get("command_exit_code")
if not isinstance(exit_code, int):
    fail("POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING",
         f"red evidence at {path} has no integer command_exit_code")

if exit_code == 0:
    fail("POLARIS_MEASUREMENT_EVIDENCE_NOT_RED",
         f"red evidence at {path} exited 0; the command was never observed failing")

stream = f"{data.get('stderr', '')}\n{data.get('stdout', '')}"
if exit_code in ENVIRONMENT_EXIT_CODES or any(
    re.search(p, stream, re.IGNORECASE) for p in ENVIRONMENT_PATTERNS
):
    fail("POLARIS_MEASUREMENT_EVIDENCE_ENVIRONMENT_ERROR",
         f"red evidence at {path} failed because the command could not run "
         f"(exit {exit_code}); that is an environment error, not a measurement")

if not data.get("recorded_at"):
    fail("POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING",
         f"red evidence at {path} has no recorded_at timestamp")
PY
}

cmd_record() {
  local ledger="" assertion="" new_command="" old_command="" evidence="" baseline="no"
  local have_new="no" have_old="no" exempt_path="" exempt_why=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ledger) ledger="${2:-}"; shift 2 ;;
      --assertion-id) assertion="${2:-}"; shift 2 ;;
      --new-command) new_command="${2:-}"; have_new="yes"; shift 2 ;;
      --old-command) old_command="${2:-}"; have_old="yes"; shift 2 ;;
      --red-evidence) evidence="${2:-}"; shift 2 ;;
      --exempt-path) exempt_path="${2:-}"; shift 2 ;;
      --exempt-why) exempt_why="${2:-}"; shift 2 ;;
      --baseline) baseline="yes"; shift ;;
      *) usage; exit 2 ;;
    esac
  done

  [[ -n "$ledger" ]] || { usage; exit 2; }
  [[ -n "$assertion" ]] || { usage; exit 2; }
  [[ "$have_new" == "yes" && -n "$new_command" ]] || { usage; exit 2; }

  # 豁免要帶理由。一個沒有理由的豁免跟沒有規則的差別只有它看起來很嚴格（L-N5）。
  if [[ -n "$exempt_path" && -z "$exempt_why" ]]; then
    die "POLARIS_MEASUREMENT_EXEMPTION_UNJUSTIFIED" \
      "--exempt-path 要配 --exempt-why：豁免的理由跟豁免本身一起留下來，不然下一個人看到的是一條沒有來由的例外"
  fi
  [[ -n "$exempt_why" && -z "$exempt_path" ]] && { usage; exit 2; }

  reject_machine_paths "$new_command" "新命令" "$exempt_path"
  reject_written_down_position "$new_command" "$ledger" "新命令" "$exempt_path"

  local current
  current="$(latest_new_hash "$ledger" "$assertion")" || exit 2

  local new_hash old_hash="" evidence_hash="" kind
  new_hash="$(command_hash "$new_command")"

  if [[ "$baseline" == "yes" ]]; then
    if [[ -n "$current" ]]; then
      die "POLARIS_MEASUREMENT_BASELINE_ALREADY_SET" \
        "assertion '$assertion' already has a sanctioned command; a later swap needs --old-command and --red-evidence, not --baseline"
    fi
    kind="baseline"
  else
    if [[ -z "$current" ]]; then
      die "POLARIS_MEASUREMENT_BASELINE_MISSING" \
        "assertion '$assertion' has no baseline command; record the first command with --baseline"
    fi
    [[ "$have_old" == "yes" ]] \
      || die "POLARIS_MEASUREMENT_CHAIN_BROKEN" "a measurement change requires --old-command"
    old_hash="$(command_hash "$old_command")"
    if [[ "$old_hash" != "$current" ]]; then
      die "POLARIS_MEASUREMENT_CHAIN_BROKEN" \
        "--old-command does not match the sanctioned command for '$assertion' (sanctioned sha256:$current, given sha256:$old_hash)"
    fi
    [[ -n "$evidence" ]] \
      || die "POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING" \
        "a measurement change requires --red-evidence; an unaccompanied swap is exactly what this ledger rejects"
    validate_red_evidence "$evidence" "$new_command" || exit 2
    evidence_hash="$(file_hash "$evidence")"
    kind="change"
  fi

  require_python3
  python3 - "$ledger" "$assertion" "$kind" "$new_command" "$new_hash" "$old_hash" "$evidence" "$evidence_hash" "$exempt_path" "$exempt_why" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

(ledger, assertion, kind, new_command, new_hash,
 old_hash, evidence_path, evidence_hash, exempt_path, exempt_why) = sys.argv[1:11]

data = {"schema_version": 1, "entries": []}
if os.path.exists(ledger):
    try:
        data = json.load(open(ledger, encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        print("POLARIS_MEASUREMENT_LEDGER_UNREADABLE", file=sys.stderr)
        print(f"{ledger}: {exc}", file=sys.stderr)
        sys.exit(2)

entry = {
    "assertion_id": assertion,
    "kind": kind,
    "old_command_hash": f"sha256:{old_hash}" if old_hash else None,
    "new_command_hash": f"sha256:{new_hash}",
    "new_command": new_command,
    "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}

# 豁免記在這一筆上，不記在 skill 裡：豁免的字串是機器特定的，而 skill 要出貨到公開的
# template。理由跟它一起留下來，因為之後判定要靠這一筆決定放不放行（DP-496 L-P3 / L-N5）。
if exempt_path:
    entry["path_exemption"] = {"path": exempt_path, "why": exempt_why}

if evidence_path:
    evidence = json.load(open(evidence_path, encoding="utf-8"))
    entry["red_evidence"] = {
        "path": evidence_path,
        "hash": f"sha256:{evidence_hash}",
        "command_exit_code": evidence.get("command_exit_code"),
        "recorded_at": evidence.get("recorded_at"),
        "head_sha": evidence.get("head_sha"),
    }
    if evidence.get("recorded_at", "") > entry["recorded_at"]:
        print("POLARIS_MEASUREMENT_EVIDENCE_NOT_RED", file=sys.stderr)
        print(f"red evidence recorded_at {evidence.get('recorded_at')} is after this record; "
              "the command must be seen failing before the change is registered", file=sys.stderr)
        sys.exit(2)

data.setdefault("entries", []).append(entry)
os.makedirs(os.path.dirname(os.path.abspath(ledger)) or ".", exist_ok=True)
with open(ledger, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"RECORDED: {assertion} {kind} sha256:{new_hash}")
PY
}

cmd_verify() {
  local ledger="" assertion="" command_str="" have_command="no"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ledger) ledger="${2:-}"; shift 2 ;;
      --assertion-id) assertion="${2:-}"; shift 2 ;;
      --command) command_str="${2:-}"; have_command="yes"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done

  [[ -n "$ledger" && -n "$assertion" && "$have_command" == "yes" ]] || { usage; exit 2; }

  # 同一條規則在兩端都要成立。只擋在登錄那一端的話，一份被手改過的 ledger 就把它繞過了
  # ——而判定這一端本來就要讀這一筆，所以豁免從那一筆自己身上取。
  reject_machine_paths "$command_str" "送審的命令" "$(recorded_exemption "$ledger" "$assertion")"

  local current
  current="$(latest_new_hash "$ledger" "$assertion")" || exit 2
  [[ -n "$current" ]] \
    || die "POLARIS_MEASUREMENT_COMMAND_UNREGISTERED" \
      "assertion '$assertion' has no sanctioned measurement command in $ledger"

  local given
  given="$(command_hash "$command_str")"
  if [[ "$given" != "$current" ]]; then
    die "POLARIS_MEASUREMENT_COMMAND_UNREGISTERED" \
      "the command offered for '$assertion' is not the sanctioned one (sanctioned sha256:$current, given sha256:$given); register the change with red evidence first"
  fi
  echo "PASS: measurement command for '$assertion' matches sanctioned sha256:$current"
}

cmd_show() {
  local ledger="" assertion=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ledger) ledger="${2:-}"; shift 2 ;;
      --assertion-id) assertion="${2:-}"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [[ -n "$ledger" && -f "$ledger" ]] \
    || die "POLARIS_MEASUREMENT_LEDGER_UNREADABLE" "ledger not readable: ${ledger:-<missing>}"

  require_python3
  python3 - "$ledger" "$assertion" <<'PY'
import json
import sys

ledger, assertion = sys.argv[1:3]
data = json.load(open(ledger, encoding="utf-8"))
for entry in data.get("entries", []):
    if assertion and entry.get("assertion_id") != assertion:
        continue
    evidence = entry.get("red_evidence") or {}
    print(f"{entry['assertion_id']} {entry['kind']} "
          f"old={entry.get('old_command_hash')} new={entry['new_command_hash']} "
          f"evidence={evidence.get('hash')}")
PY
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] || { usage; exit 2; }
  shift
  case "$sub" in
    record) cmd_record "$@" ;;
    verify) cmd_verify "$@" ;;
    show) cmd_show "$@" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
