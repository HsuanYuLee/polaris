#!/usr/bin/env bash
# Purpose: 證明「現在過了幾條」這支報告該印的都印、該擋的一件都不擋，而且它跟交付那條路
#          用的是同一段判定。
# Inputs:  mktemp 底下的 hermetic git repo，assertion 的校驗值、量測登錄與證據都照真流程產生。
# Outputs: PASS 當三種判定都印得出來、缺東西的時候整份照印、唯讀（一個檔案都不寫）、
#          做到第幾層自己說得出來，而且同一份 fixture 上報告與交付給出同一個答案。

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT="$ROOT_DIR/scripts/report-assertions.sh"
RECORD="$ROOT_DIR/scripts/record-delivery-intent.sh"
FENCE="$ROOT_DIR/scripts/frozen-assertion-fence.sh"
ORACLE="$ROOT_DIR/scripts/run-hardened-oracle.sh"
LEDGER_SCRIPT="$ROOT_DIR/scripts/record-measurement-change.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; PASS=$((PASS + 1)); }

# Description: 造一張封好、有兩條 assertion、兩條都量過的單，回傳單的絕對路徑。
# Args: $1 = case 名字
new_issue() {
  local name="$1" repo="$WORK/$1" issue
  issue="$repo/issues/DP-000-selftest"
  mkdir -p "$issue"
  git init -q "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  {
    echo "---"
    echo "title: selftest source"
    echo "destination: template"
    echo "---"
    echo
    echo "<!-- POLARIS-FROZEN-A-BEGIN -->"
    echo "- **A-P1** the thing holds."
    echo "- **A-P2** the other thing holds."
    echo "<!-- POLARIS-FROZEN-A-END -->"
  } > "$issue/index.md"
  bash "$FENCE" seal "$issue/index.md" --by selftest >/dev/null
  git -C "$repo" add -A
  git -C "$repo" commit -qm "seal selftest source"
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  # 兩條 assertion 共用同一條命令，這是真單的常態——順便讓「重跑去重」有東西可以量。
  local aid
  for aid in A-P1 A-P2; do
    bash "$LEDGER_SCRIPT" record --ledger "$issue/.spine/measurement-ledger.json" \
      --assertion-id "$aid" --new-command 'echo MEASURED' --baseline >/dev/null
    (cd "$repo" && bash "$ORACLE" --command 'echo MEASURED' --expect-evidence MEASURED \
       --evidence-out "$issue/.spine/evidence/$aid.json" >/dev/null)
  done
  printf '%s' "$issue"
}

# Description: 跑報告，回傳輸出；exit code 放進全域 RC。
run_report() {
  RC=0
  OUT="$(bash "$REPORT" "$@" 2>&1)" || RC=$?
}

echo "report-assertions selftest"

# W-P1：一條一條說出來，而且三種判定都有名字。
issue="$(new_issue green)"
run_report --issue "$issue"
[[ "$RC" -eq 0 ]] || fail "全綠應該 exit 0；拿到 ${RC}：$OUT"
grep -q 'PASS  A-P1' <<<"$OUT" || fail "沒有逐條印出 A-P1：$OUT"
grep -q 'PASS  A-P2' <<<"$OUT" || fail "沒有逐條印出 A-P2：$OUT"
grep -Fq '2 條——過 2、沒過 0、量不到 0' <<<"$OUT" \
  || fail "三種判定要一起印，包含 0 的那幾種：$OUT"
ok "逐條印，而且過／沒過／量不到三種都印"

# W-N1：唯讀。它印得出交付判得出來的事，但不留下任何下游拿得去當證據的東西。
before="$(find "$issue" -type f | sort | xargs shasum | shasum)"
run_report --issue "$issue" --rerun
after="$(find "$issue" -type f | sort | xargs shasum | shasum)"
[[ "$before" == "$after" ]] || fail "報告動了單裡的檔案，它應該是唯讀的"
ok "跑完一個檔案都沒動"

# 做到第幾層要自己說。一份沒說自己做到第幾層的報告，讀起來永遠像做滿了。
grep -Fq 'LAYERS: 檔案自洽、登錄相符、重跑一次' <<<"$OUT" \
  || fail "--rerun 要說出三層都做了：$OUT"
grep -Fq '重跑了 1 趟，2 條 assertion 各自判過自己的樣式' <<<"$OUT" \
  || fail "重跑要說出跑了幾趟、判了幾條：$OUT"
run_report --issue "$issue"
grep -Fq '（沒做：重跑一次）' <<<"$OUT" || fail "沒加 --rerun 要說出那一層沒做：$OUT"
ok "做到第幾層自己說得出來，沒做的那一層也說"

# W-P3：缺東西的時候仍然整份印出來。交付那條路是任一條不成立就整支拒絕、什麼都不印，
# 而那正是「現在到底過了幾條」問不到的原因。
issue="$(new_issue partial)"
rm "$issue/.spine/evidence/A-P2.json"
run_report --issue "$issue"
[[ "$RC" -eq 1 ]] || fail "有沒過的應該 exit 1；拿到 ${RC}：$OUT"
grep -q 'PASS  A-P1' <<<"$OUT" || fail "缺一條的時候另一條就不印了：$OUT"
grep -q 'FAIL  A-P2' <<<"$OUT" || fail "沒說出是哪一條缺：$OUT"
grep -Fq '沒有證據' <<<"$OUT" || fail "沒說出它是怎麼缺的：$OUT"
ok "缺東西的時候整份照印，並指名是哪一條、怎麼缺的"

# W-N4：量不到是第三種，不是通過的溫和版本，而且要有自己的 exit code。
issue="$(new_issue unmeasurable)"
printf 'not json at all' > "$issue/.spine/evidence/A-P2.json"
run_report --issue "$issue"
[[ "$RC" -eq 2 ]] || fail "有量不到的應該 exit 2；拿到 ${RC}：$OUT"
grep -q '????  A-P2' <<<"$OUT" || fail "量不到沒有自己的判定符號：$OUT"
grep -Fq '量不到 1' <<<"$OUT" || fail "量不到沒有被算進去：$OUT"
ok "量不到是第三種，有自己的 exit code，而且被數出來"

# W-P2：報告與交付是同一段判定。這裡不比對程式碼長什麼樣（那證明不了執行時用的是哪一份），
# 比的是行為：同一份 fixture 上，報告說得出來的，交付就擋得住；報告全綠的，交付就記得下來。
issue="$(new_issue shared_ok)"
repo="$WORK/shared_ok"
run_report --issue "$issue" --rerun
[[ "$RC" -eq 0 ]] || fail "乾淨的 fixture 報告應該全綠：$OUT"
(cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest --summary 'x' >/dev/null 2>&1) \
  || fail "報告說全綠，交付卻記不下來——兩邊判的不是同一件事"
ok "報告全綠時交付記得下來"

issue="$(new_issue shared_forged)"
repo="$WORK/shared_forged"
python3 - "$issue/.spine/evidence/A-P2.json" <<'PY'
import json, sys
path = sys.argv[1]
evidence = json.load(open(path))
evidence["command"] = "true"   # 自洽，但沒有人登錄過這條命令
json.dump(evidence, open(path, "w"))
PY
run_report --issue "$issue"
[[ "$RC" -eq 1 ]] || fail "指名未登錄命令的證據，報告應該判紅；拿到 ${RC}：$OUT"
grep -Fq '登錄過的那一條' <<<"$OUT" || fail "報告沒說出命令對不上登錄：$OUT"
(cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest --summary 'x' >/dev/null 2>&1) \
  && fail "報告判紅，交付卻記得下來——兩邊判的不是同一件事"
ok "報告判紅時交付也擋得住，同一份 fixture 兩邊同一個答案"

# B-P1／B-P2／B-N3：重跑要把證據記下的工具交還給 oracle。
#
# 假工具住在 mktemp 底下——也就是 oracle 釘死的那幾個系統目錄之外，跟真單裡的 gh 同一個
# 處境。量測時 `--require-tool` 把它 symlink 進釘死的 PATH，命令才跑得起來；重跑時若不
# 交還，同一條命令就是 exit 127。
TOOLBOX="$WORK/toolbox"
mkdir -p "$TOOLBOX"
cat > "$TOOLBOX/polaris-faketool" <<'TOOL'
#!/usr/bin/env bash
echo "FAKE-OK"
TOOL
chmod +x "$TOOLBOX/polaris-faketool"

# Description: 造一張單，唯一那條 assertion 的命令非得靠 $TOOLBOX 裡那支工具才跑得起來。
# Args: $1 = case 名字
new_tool_issue() {
  local name="$1" repo="$WORK/$1" issue cmd
  issue="$repo/issues/DP-000-selftest"
  cmd='polaris-faketool'
  mkdir -p "$issue"
  git init -q "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  {
    echo "---"; echo "title: selftest source"; echo "destination: template"; echo "---"
    echo
    echo "<!-- POLARIS-FROZEN-A-BEGIN -->"
    echo "- **A-P1** the tool-borne thing holds."
    echo "<!-- POLARIS-FROZEN-A-END -->"
  } > "$issue/index.md"
  bash "$FENCE" seal "$issue/index.md" --by selftest >/dev/null
  git -C "$repo" add -A
  git -C "$repo" commit -qm "seal selftest source"
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  bash "$LEDGER_SCRIPT" record --ledger "$issue/.spine/measurement-ledger.json" \
    --assertion-id A-P1 --new-command "$cmd" --baseline >/dev/null
  (cd "$repo" && PATH="$TOOLBOX:$PATH" bash "$ORACLE" --command "$cmd" \
     --require-tool 'polaris-faketool:--version' --expect-evidence FAKE-OK \
     --evidence-out "$issue/.spine/evidence/A-P1.json" >/dev/null)
  printf '%s' "$issue"
}

# 反向對照組先跑：把證據裡那份工具清單拿掉，同一條命令就該紅。它同時證明第三層不會好心地
# 從現在的 PATH 補一支工具進去——那支工具此刻確實在 PATH 上（$TOOLBOX 還掛著）。
issue="$(new_tool_issue tools_stripped)"
python3 - "$issue/.spine/evidence/A-P1.json" <<'PY'
import json, sys
path = sys.argv[1]
evidence = json.load(open(path))
evidence["tools"] = []
json.dump(evidence, open(path, "w"))
PY
PATH="$TOOLBOX:$PATH" run_report --issue "$issue" --rerun
[[ "$RC" -eq 1 ]] || fail "證據沒記工具、命令又非得靠它，重跑該紅；拿到 ${RC}：$OUT"
grep -Fq '重跑一次是紅的' <<<"$OUT" || fail "反向對照組沒有紅在重跑那一層：$OUT"
grep -Fq '（沒有輸出）' <<<"$OUT" \
  && fail "判紅卻說不出理由——理由在 oracle 的 stderr 上：$OUT"
grep -Fq 'command not found' <<<"$OUT" \
  || fail "紅的理由要帶著命令自己說的那句話：$OUT"
ok "工具沒交還就是紅的，而且說得出為什麼"
# 上面那支工具此刻確實在 PATH 上（$TOOLBOX 還掛著），證據裡卻沒有它。它仍然紅，表示這一層
# 交還的就是證據記的那幾個，不從現在的環境推導出額外的工具。
ok "第三層不從現在的環境補一支工具進去"

issue="$(new_tool_issue tools_handed_back)"
PATH="$TOOLBOX:$PATH" run_report --issue "$issue" --rerun
[[ "$RC" -eq 0 ]] || fail "證據記著工具，重跑該把它交還給 oracle；拿到 ${RC}：$OUT"
grep -Fq 'LAYERS: 檔案自洽、登錄相符、重跑一次' <<<"$OUT" || fail "三層沒做滿：$OUT"
ok "證據記下的工具（連能力探針一起）重跑時交還得回去"

# B-P3：DP-506 之前的證據沒有 tools 這個欄位。那表示當初沒探過工具，照沒探過跑就是了，
# 不是量不到、也不是紅。上面那個反向對照組拿掉的是欄位的值，這裡拿掉的是欄位本身。
issue="$(new_issue no_tools_field)"
python3 - "$issue/.spine/evidence/A-P1.json" <<'PY'
import json, sys
path = sys.argv[1]
evidence = json.load(open(path))
evidence.pop("tools", None)
json.dump(evidence, open(path, "w"))
PY
run_report --issue "$issue" --rerun
[[ "$RC" -eq 0 ]] || fail "舊證據沒有 tools 欄位不該因此變紅；拿到 ${RC}：$OUT"
ok "沒有工具清單的舊證據照沒探過跑"

# 一趟執行不得把另一條 assertion 的答案借給這一條。兩條 assertion 跑同一條命令、各自要求
# 不同的證據樣式，是真單的常態；那一趟的輸出只判一次的話，第二條拿到的是第一條的答案，而它
# 自己的樣式從來沒有被檢查過——一條沒被量到的 assertion 看起來就跟過了一樣。
issue="$(new_issue shared_command_different_needles)"
python3 - "$issue/.spine/evidence/A-P2.json" <<'PY'
import json, sys
path = sys.argv[1]
evidence = json.load(open(path))
# 同一條登錄過的命令（前兩層照樣綠），但這一條 assertion 要的是輸出裡沒有的那句話。
evidence["expect_evidence"] = ["NOT-IN-THE-OUTPUT"]
json.dump(evidence, open(path, "w"))
PY
run_report --issue "$issue" --rerun
[[ "$RC" -eq 2 ]] || fail "共用命令但樣式不同，第二條該自己被量；拿到 ${RC}：$OUT"
grep -q 'PASS  A-P1' <<<"$OUT" || fail "樣式還在的那一條該是綠的：$OUT"
# oracle 對「命令跑完了但沒有它被要求產出的正向證據」回 exit 2 而不是 1，所以這一條落在
# 量不到那一格。它一樣不是通過：報告 exit 2、交付照樣拒絕。
grep -q '????  A-P2' <<<"$OUT" || fail "樣式不在的那一條該被判成量不到：$OUT"
grep -Fq '重跑了 1 趟，2 條 assertion 各自判過自己的樣式' <<<"$OUT" \
  || fail "樣式不同不是多跑一趟的理由，該是一趟兩判：$OUT"
ok "同一條命令跑一趟，兩條 assertion 的樣式各判各的"
grep -Fq '量不到 1' <<<"$OUT" || fail "重跑那一層的量不到沒有被數出來：$OUT"
ok "重跑跑不出結果時是量不到，照樣印出來、照樣被數，exit 不是 0"

# 指到一張不存在的單是量不到，不是「沒有東西要證明」。
run_report --issue "$WORK/nosuch"
[[ "$RC" -eq 2 ]] || fail "單不在應該 exit 2；拿到 ${RC}：$OUT"
ok "單不在是量不到"

echo "PASS: report-assertions（$PASS 項）"
