#!/usr/bin/env bash
# Hardened oracle runner: execute a measurement command so the tools cannot lie.
#
# The plain path (`bash -c "$cmd"` with the inherited PATH) is faithful to the
# environment, which is exactly the problem: whatever sits earliest on PATH gets
# executed, and its exit 0 is read as PASS. Three shapes, all taken from real
# incidents, defeat an unhardened runner:
#
#   (a) `rg` replaced by a BSD-grep-shaped shim that ignores `--pcre2`, so a
#       negative assertion (`! rg …`) inverts into exit 0.
#   (b) a test runner that silently skips everything, reports coverage 0, and
#       still exits 0.
#   (c) a curl error swallowed into a generic timeout, which downstream logic
#       treats as flaky rather than failed.
#
# Three counters, in the same order:
#
#   1. Capability probe, not location trust. Each required tool must answer a
#      declared probe (`rg:--pcre2 --version`). A shim that cannot do the thing
#      the command depends on fails the probe and the run stops. The probed
#      binary is then pinned by absolute path into a private bin directory that
#      leads PATH, so nothing can be swapped underneath the command mid-run.
#   2. Positive evidence, not merely exit 0. The command must emit something
#      that proves it measured (`--expect-evidence`). Silence is not success.
#   3. stderr and exit code are preserved verbatim. Nothing is remapped,
#      nothing is discarded, and both are recorded in the evidence record.
#
# Fail-closed everywhere: a tool that cannot be resolved, or cannot answer its
# probe, stops the run and names the tool. There is no fallback to the inherited
# PATH — a silent fallback would reinstate the exact hole being closed.
#
# 一條命令，N 條 assertion，跑一次（DP-529）。同一條量測命令常常同時是好幾條 assertion 的量測，而每
# 條 assertion 的正向證據不一樣。以前一份 --evidence-out 只能對一條 assertion，所以要產 N 份證據就得
# invoke N 次——而每一次都真的把那條命令再跑一遍。量出來的代價：十六條 assertion 共用一條 495 秒
# 的命令，跑十六趟兩小時十分，而十六份證據的 stdout 34 行裡 31 行逐位元組相同。
#
# `--assertion <ID>` 開一個分組，後面的 --expect-evidence / --forbid-evidence /
# --evidence-out 掛在那一組上。命令跑一次，逐組在同一份輸出上各自判、各自寫。
# **不是把同一份判定複製 N 份**——那會讓「這條 assertion 真的被檢查過」變成假的。
# 不給任何 --assertion 時，一切與以前相同。
#
# Usage:
#   run-hardened-oracle.sh --command <cmd>
#       [--require-tool <name>[:<probe args>]]...
#       [--expect-evidence <regex>]... [--forbid-evidence <regex>]...
#       [--evidence-out <path>]
#       [--assertion <id> [--expect-evidence …]... --evidence-out <path>]...
#       [--cwd <dir>] [--system-path <dir:dir:...>]
#
# Exit codes:
#   0  command exited 0, every probe answered, positive evidence present
#   1  command exited non-zero and that is a red (its own code is in the record)
#   2  hardening refused the run, or the verdict could not be reached — this
#      includes the command exiting 2, which the convention in
#      engineering/SKILL.md defines as "this run could not measure".
#      Verdicts written into the evidence record: PASS / FAIL / NOT_PASS /
#      UNMEASURABLE.

set -uo pipefail

# NO-CALLER: --system-path — 這棵樹上沒有人給過值，因為預設的四個目錄夠用。留著是因為
# 它是釘死 PATH 之後唯一的出路：把系統工具裝在別處的機器（nix、只有 homebrew 的機器）
# 上，沒有它連 git 都探不到，而這支腳本會正確地拒絕跑——一道無法在那台機器上成立的關卡
# 不是嚴謹，是關掉它。
DEFAULT_SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

COMMAND=""
HAVE_COMMAND="no"
CWD=""
SYSTEM_PATH="$DEFAULT_SYSTEM_PATH"
EVIDENCE_OUT=""
REQUIRE_TOOLS=()
EXPECT_PATTERNS=()
FORBID_PATTERNS=()

usage() {
  cat >&2 <<'EOF'
Usage:
  run-hardened-oracle.sh --command <cmd>
      [--require-tool <name>[:<probe args>]]...
      [--expect-evidence <regex>]... [--forbid-evidence <regex>]...
      [--evidence-out <path>]
      [--assertion <id> [--expect-evidence …]... --evidence-out <path>]...
      [--cwd <dir>] [--system-path <dir:dir:...>]

  --assertion opens a group: the --expect-evidence / --forbid-evidence /
  --evidence-out flags that follow belong to it. The command runs once and each
  group is judged separately against that single run.
EOF
}

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

# 分組用三個平行陣列存，索引就是組號。bash 3.2 沒有巢狀陣列，而樣式清單是變長的——
# 所以每一組的樣式存成一個字串，用換行分隔（樣式本身不會有換行）。
GROUP_IDS=()
GROUP_EXPECT=()
GROUP_FORBID=()
GROUP_OUT=()
CURRENT=-1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --command) COMMAND="${2:-}"; HAVE_COMMAND="yes"; shift 2 ;;
    --require-tool) REQUIRE_TOOLS+=("${2:-}"); shift 2 ;;
    --assertion)
      [[ -n "${2:-}" ]] || die POLARIS_ORACLE_GROUP_INCOMPLETE "--assertion 要帶一個 assertion ID。"
      GROUP_IDS+=("$2"); GROUP_EXPECT+=(""); GROUP_FORBID+=(""); GROUP_OUT+=("")
      CURRENT=$((${#GROUP_IDS[@]} - 1))
      shift 2 ;;
    --expect-evidence)
      if [[ "$CURRENT" -ge 0 ]]; then
        GROUP_EXPECT[$CURRENT]="${GROUP_EXPECT[$CURRENT]}${GROUP_EXPECT[$CURRENT]:+$'\n'}${2:-}"
      else
        EXPECT_PATTERNS+=("${2:-}")
      fi
      shift 2 ;;
    --forbid-evidence)
      if [[ "$CURRENT" -ge 0 ]]; then
        GROUP_FORBID[$CURRENT]="${GROUP_FORBID[$CURRENT]}${GROUP_FORBID[$CURRENT]:+$'\n'}${2:-}"
      else
        FORBID_PATTERNS+=("${2:-}")
      fi
      shift 2 ;;
    --evidence-out)
      if [[ "$CURRENT" -ge 0 ]]; then
        GROUP_OUT[$CURRENT]="${2:-}"
      else
        EVIDENCE_OUT="${2:-}"
      fi
      shift 2 ;;
    --cwd) CWD="${2:-}"; shift 2 ;;
    --system-path) SYSTEM_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ "$HAVE_COMMAND" == "yes" && -n "$COMMAND" ]] || { usage; exit 2; }

# 分組不完整就停。一組沒有自己的輸出路徑時沿用別人的，或兩組指到同一個檔案讓後寫的蓋掉
# 先寫的——兩種都會產出一份看起來正常、但屬於別條 assertion 的證據。
if [[ "${#GROUP_IDS[@]}" -gt 0 ]]; then
  seen_out=""
  for i in "${!GROUP_IDS[@]}"; do
    [[ -n "${GROUP_OUT[$i]}" ]] \
      || die POLARIS_ORACLE_GROUP_INCOMPLETE "assertion ${GROUP_IDS[$i]} 這一組沒有 --evidence-out。每一組都要有自己的輸出路徑。"
    case "$seen_out" in
      *"|${GROUP_OUT[$i]}|"*)
        die POLARIS_ORACLE_GROUP_DUPLICATE_OUT "assertion ${GROUP_IDS[$i]} 的 --evidence-out 跟前面某一組指到同一個檔案：${GROUP_OUT[$i]}" ;;
    esac
    seen_out="${seen_out}|${GROUP_OUT[$i]}|"
  done
  # 分組模式下，散在分組之外的 --evidence-out 沒有歸屬。它要嘛是打錯位置，要嘛是舊呼叫法
  # 沒清乾淨，兩種都不該安靜地多寫一份。
  [[ -z "$EVIDENCE_OUT" ]] \
    || die POLARIS_ORACLE_GROUP_INCOMPLETE "已經用了 --assertion 分組，但還有一個不屬於任何一組的 --evidence-out：${EVIDENCE_OUT}"
fi

require_python3

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PINNED_BIN="$WORK/pinned-bin"
mkdir -p "$PINNED_BIN"

STDOUT_FILE="$WORK/stdout.log"
STDERR_FILE="$WORK/stderr.log"

resolve_tool() {
  # Description: print the absolute path of a tool, searching the inherited
  #              PATH first and the declared system path second.
  # Args: $1 = tool name
  # Side effects: none; prints nothing when the tool cannot be resolved.
  local name="$1" candidate
  candidate="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  local dir
  IFS=':' read -r -a _dirs <<< "$SYSTEM_PATH"
  for dir in "${_dirs[@]}"; do
    if [[ -x "$dir/$name" ]]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
  done
  return 1
}

TOOL_RECORDS=()

for spec in "${REQUIRE_TOOLS[@]:-}"; do
  [[ -n "$spec" ]] || continue
  tool_name="${spec%%:*}"
  probe_args=""
  [[ "$spec" == *:* ]] && probe_args="${spec#*:}"

  resolved="$(resolve_tool "$tool_name" || true)"
  if [[ -z "$resolved" ]]; then
    die "POLARIS_ORACLE_TOOL_UNRESOLVED:$tool_name" \
      "required tool '$tool_name' could not be resolved; refusing to run with the inherited PATH as a fallback"
  fi

  probe_status=0
  if [[ -n "$probe_args" ]]; then
    # The probe is the trust test: a shim wearing the right name but lacking the
    # capability the command depends on fails here, wherever it sits on PATH.
    # shellcheck disable=SC2086
    "$resolved" $probe_args >/dev/null 2>&1 || probe_status=$?
    if [[ "$probe_status" -ne 0 ]]; then
      die "POLARIS_ORACLE_TOOL_CAPABILITY_FAILED:$tool_name" \
        "'$resolved' did not answer its capability probe ($tool_name $probe_args, exit $probe_status); the tool on PATH cannot do what this measurement depends on"
    fi
  fi

  ln -sf "$resolved" "$PINNED_BIN/$tool_name"
  TOOL_RECORDS+=("$tool_name|$resolved|$probe_args|$probe_status")
done

# The command runs against pinned binaries first, then a declared system path.
# The inherited PATH does not survive into the command.
export PATH="$PINNED_BIN:$SYSTEM_PATH"

run_dir="${CWD:-$PWD}"
[[ -d "$run_dir" ]] || die "POLARIS_ORACLE_CWD_MISSING" "working directory not found: $run_dir"

COMMAND_EXIT=0
(
  cd "$run_dir" || exit 127
  bash -c "$COMMAND"
) > "$STDOUT_FILE" 2> "$STDERR_FILE" || COMMAND_EXIT=$?

# Replay both streams verbatim on the runner's own descriptors. Nothing is
# merged, reordered, or dropped: a caller reading stderr sees what the command
# actually said.
cat "$STDOUT_FILE"
cat "$STDERR_FILE" >&2

combined="$WORK/combined.log"
cat "$STDOUT_FILE" "$STDERR_FILE" > "$combined"

# Description: 在同一份輸出上判一組正負向樣式。$1 = 換行分隔的正向樣式，$2 = 負向。
#              判定寫進 verdict / marker / detail 三個變數（呼叫端先宣告成 local）。
judge_group() {
  local expect="$1" forbid="$2" pattern
  verdict="PASS"; marker=""; detail=""
  # 慣例（宣告在 engineering/SKILL.md）：0 綠、1 量到了而且是紅的、2 量不到。
  # 以前這裡把任何非 0 都寫成 FAIL，於是「這一趟沒問到」與「問到了，答案是紅的」在證據上
  # 是同一個值——而報告的統計行因此對每一張單都印「量不到 0」，也就是那一格存在的理由
  # 剛好沒有發生。兩者的下一步不一樣：紅的去看程式碼，量不到去看那個東西存不存在。
  #
  # 已知的反例要說出來：**PHPUnit 的 error（不是 assertion 失敗）也回 2**（assertion
  # 失敗回 1）。所以一條直接跑 phpunit 的量測命令，測試拋例外的時候會被記成量不到而不是
  # 紅。兩種狀態都擋得住交付（record-delivery-intent.sh 對 FAIL 與 UNMEASURABLE 一起擋），
  # 所以那個誤判不會放行任何東西——它讓讀報告的人先去看環境而不是先去看程式碼。要避開它，
  # 就不要把第三方工具的離場碼直接當成判定，用一支自己的探針把它翻譯過。
  if [[ "$COMMAND_EXIT" -eq 2 ]]; then
    verdict="UNMEASURABLE"
    marker="POLARIS_ORACLE_UNMEASURABLE"
    detail="command exited 2 — 依慣例那是「這一趟量不到」，不是「量到了而且是紅的」"
    return
  fi
  if [[ "$COMMAND_EXIT" -ne 0 ]]; then
    verdict="FAIL"
    marker="POLARIS_ORACLE_COMMAND_FAILED"
    detail="command exited $COMMAND_EXIT"
    return
  fi
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    if ! grep -Eq "$pattern" "$combined"; then
      verdict="NOT_PASS"
      marker="POLARIS_ORACLE_NO_POSITIVE_EVIDENCE"
      detail="command exited 0 but never emitted the positive evidence it was required to produce: /$pattern/"
      return
    fi
  done <<< "$expect"
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    if grep -Eq "$pattern" "$combined"; then
      verdict="NOT_PASS"
      marker="POLARIS_ORACLE_FORBIDDEN_EVIDENCE"
      detail="command output matched a pattern that marks a non-measurement: /$pattern/"
      return
    fi
  done <<< "$forbid"
}

# Description: 那個路徑上現在躺著的那一份，verdict 是什麼。$1 = 路徑。
#              讀不到就印空字串並回 0——**「那裡沒有東西」是一個答案，不是一個死法**。
#              手寫的、被截斷的、根本不是 JSON 的檔案都走同一條路：空字串。
evidence_verdict_at() {
  [[ -f "$1" ]] || return 0
  python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding="utf-8")).get("verdict") or "")
except Exception:
    print("")
' "$1" 2>/dev/null
}

# Description: 蓋掉一份 PASS 之前先留一份。$1 = 輸出路徑，$2 = 這一趟的判定。
#
# **照寫，但不無聲地毀掉。** 「判非 PASS 就不寫」與「不覆蓋 PASS」這兩種做法都是 fail-open：
# 實作真的退化、oracle 判紅的那一天，磁碟上留下的會是昨天那份 PASS，而交付紀錄第一層讀的
# 正是它。現在那份 NOT_PASS 至少是誠實的。所以判定一個字都不變，變的只有「上一份還在不在」
# 與「有沒有人被告知」。
#
# 2026-08-29 DP-598 第二輪的實例：`--expect-evidence` 的樣式經過 eval 之後空白被吃掉，
# 一趟把十九份 PASS 覆寫成 NOT_PASS，連正確的 expect_evidence 一起換掉；第二次重跑讀的是
# 被汙染的樣式，於是又失敗一次，看起來像「這幾條真的量不到」。拿回來只因為那些證據剛好
# commit 過。
#
# `.superseded` 只在**真的要毀掉一份 PASS** 的時候出現，所以它不會變成每張單都有的雜訊。
preserve_superseded() {
  local out="$1" verdict="$2" was
  [[ "$verdict" != "PASS" ]] || return 0
  was="$(evidence_verdict_at "$out")"
  [[ "$was" == "PASS" ]] || return 0
  cp -p "$out" "${out}.superseded" || return 0
  echo "SUPERSEDED: ${out} 原本是 PASS，這一趟判 ${verdict}——原檔逐位元留在 ${out}.superseded"
}

# Description: 寫一份證據。$1 = 輸出路徑，$2/$3/$4 = 判定三件，$5/$6 = 這一份自己的樣式。
write_evidence() {
  local out="$1" verdict="$2" marker="$3" detail="$4" expect="$5" forbid="$6"
  preserve_superseded "$out" "$verdict"
  # 正負向樣式走環境變數，不擠進 argv：那串位置參數已經固定了九個再接一串工具紀錄，
  # 中間插兩個變長的清單要多一組長度欄位，而那正是會被下一個人數錯的東西。
  #
  # 記下來的理由：同一支 selftest 常常同時是好幾條 assertion 的量測命令，**分開它們的只有這幾個
  # 樣式**。沒有記下來的話，任何要重跑這份證據的人只能重跑那條命令，然後把「它綠了」讀成
  # 「每一條都綠了」。
  POLARIS_ORACLE_EXPECT="$expect" \
  POLARIS_ORACLE_FORBID="$forbid" \
    python3 - "$out" "$COMMAND" "$COMMAND_EXIT" "$verdict" "$marker" "$detail" \
    "$STDOUT_FILE" "$STDERR_FILE" "$run_dir" "${TOOL_RECORDS[@]:-}" <<'PY'
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

(out, command, exit_code, verdict, marker, detail, stdout_path, stderr_path,
 run_dir) = sys.argv[1:10]
tools = []
for record in sys.argv[10:]:
    if not record:
        continue
    name, resolved, probe, status = record.split("|", 3)
    tools.append({
        "name": name,
        "resolved_path": resolved,
        "capability_probe": probe or None,
        "capability_probe_exit": int(status),
    })

payload = {
    "schema_version": 1,
    "producer": "run-hardened-oracle.sh",
    "command": command,
    "command_exit_code": int(exit_code),
    "verdict": verdict,
    "marker": marker or None,
    "detail": detail or None,
    "tools": tools,
    "stdout": open(stdout_path, encoding="utf-8", errors="replace").read(),
    "stderr": open(stderr_path, encoding="utf-8", errors="replace").read(),
    "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    # Which tree the command was measuring. The measurement ledger keeps this
    # alongside the record so a red run can be located afterwards; leaving it out
    # made that a permanently empty field.
    #
    # Read from the directory the command actually ran in, not from this process's
    # cwd. They differ whenever --cwd is used — which is exactly when the measured
    # tree is not the one the caller is standing in — and the record then named a
    # commit the command never saw, while looking perfectly well-formed (DP-482).
    "head_sha": subprocess.run(
        ["git", "-C", run_dir, "rev-parse", "HEAD"], capture_output=True, text=True,
    ).stdout.strip() or None,
    # 量的是哪一棵樹，記下來。head_sha 單獨存在的時候只說得出「那時候它在這個 commit」，
    # 說不出「現在它還在不在」——而後者正是交付紀錄要問的問題，它原本靠呼叫者當下站的
    # 位置去問，於是在 --cwd 之下問錯了樹（DP-482）。
    "measured_in": os.path.abspath(run_dir),
    # 空字串要丟掉：bash 3.2 展開一個空陣列仍然給一個空元素，而一條空的 regex 什麼都符合
    # ——留著它，重跑那一層會永遠是綠的。
    "expect_evidence": [p for p in os.environ.get("POLARIS_ORACLE_EXPECT", "").split("\n") if p],
    "forbid_evidence": [p for p in os.environ.get("POLARIS_ORACLE_FORBID", "").split("\n") if p],
}
os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
with open(out, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

EXPECT_JOINED="$(printf '%s\n' "${EXPECT_PATTERNS[@]:-}")"
FORBID_JOINED="$(printf '%s\n' "${FORBID_PATTERNS[@]:-}")"

if [[ "${#GROUP_IDS[@]}" -eq 0 ]]; then
  # 舊的呼叫法：一組樣式、一份證據、一個判定。一個字都沒變。
  declare verdict marker detail
  judge_group "$EXPECT_JOINED" "$FORBID_JOINED"
  VERDICT="$verdict"; MARKER="$marker"; DETAIL="$detail"
  [[ -z "$EVIDENCE_OUT" ]] \
    || write_evidence "$EVIDENCE_OUT" "$VERDICT" "$MARKER" "$DETAIL" "$EXPECT_JOINED" "$FORBID_JOINED"
else
  # 分組：命令已經跑完了，這裡只是在同一份輸出上逐條判。逐條判是重點——把同一個判定複製
  # N 份會讓「這條 assertion 真的被檢查過」變成假的，而那正是這條路要買到的東西。
  NOT_PASSED=()
  for i in "${!GROUP_IDS[@]}"; do
    declare verdict marker detail
    judge_group "${GROUP_EXPECT[$i]}" "${GROUP_FORBID[$i]}"
    write_evidence "${GROUP_OUT[$i]}" "$verdict" "$marker" "$detail" \
      "${GROUP_EXPECT[$i]}" "${GROUP_FORBID[$i]}"
    if [[ "$verdict" == "PASS" ]]; then
      echo "PASS: ${GROUP_IDS[$i]} — 這一趟的輸出帶著它要求的正向證據"
    else
      NOT_PASSED+=("${GROUP_IDS[$i]}")
      echo "${GROUP_IDS[$i]}: $marker" >&2
      echo "  $detail" >&2
    fi
  done
  echo "ORACLE-GROUPS: 一趟執行，${#GROUP_IDS[@]} 條 assertion 各自判過，非 PASS ${#NOT_PASSED[@]} 條"
  if [[ "${#NOT_PASSED[@]}" -eq 0 ]]; then
    exit 0
  fi
  # 命令自己紅的時候每一組都是 FAIL，離場碼跟不分組時同一個意思：1 是命令紅了，2 是判定
  # 沒到。兩者混成一個的話，「跑不起來」與「跑起來但沒證據」在呼叫端分不出來。
  [[ "$COMMAND_EXIT" -ne 0 ]] && exit 1
  exit 2
fi

if [[ "$VERDICT" == "PASS" ]]; then
  echo "PASS: hardened oracle verdict PASS (command exit 0, positive evidence present)"
  exit 0
fi

echo "$MARKER" >&2
echo "$DETAIL" >&2
# The command's own exit code is preserved in the evidence record; the runner
# reports 1 for a genuine command failure and 2 for a hardening refusal.
[[ "$VERDICT" == "FAIL" ]] && exit 1
exit 2
