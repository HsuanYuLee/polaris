#!/usr/bin/env bash
# Selftest for run-hardened-oracle.sh 的分組模式（DP-529）——一條命令、N 條 assertion、跑一次。
#
# 為什麼要有這一支：同一條量測命令常常同時是好幾條 assertion 的量測，而以前一份 --evidence-out
# 只能對一條，所以產 N 份證據要 invoke N 次，每一次都真的把命令再跑一遍。量到的代價是
# 十六條 assertion 共用一條 495 秒的命令跑成兩小時十分，而十六份證據 34 行裡 31 行逐位元組相同。
#
# 這一支守的是那條路省下來的東西**不是靠複製買到的**：每一組要在同一份輸出上各自判、
# 各自寫。把同一個判定複製 N 份也會很快，而且看起來一模一樣——差別只在「這條 assertion 真的被
# 檢查過」是不是真的。

set -euo pipefail

export LC_ALL="${LC_ALL:-en_US.UTF-8}"

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORACLE="$SCRIPTS/run-hardened-oracle.sh"
REPO="$(cd "$SCRIPTS/../../../.." && pwd)"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; echo "  ---- 實際 ----"; sed 's/^/  /' <<< "${2:-}"; }

# Description: 造一支假的量測命令。每被執行一次就往計數檔加一行，這樣「跑了幾次」量得到。
#              $1 = 它要回的離場碼。
make_command() {
  cat > "$tmp/cmd.sh" <<EOF
#!/usr/bin/env bash
echo x >> "$tmp/count"
echo "MEASURED alpha"
echo "MEASURED beta"
echo "SKIPPED: 沒有樣本"
exit ${1:-0}
EOF
  chmod +x "$tmp/cmd.sh"
  : > "$tmp/count"
  rm -f "$tmp"/*.json
}

runs() { wc -l < "$tmp/count" | tr -d ' '; }
field() { python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]))" "$1" "$2"; }

# ── Q-P1 一條命令跑一次，N 份證據都產得出來 ─────────────────────────────────
make_command 0
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --assertion Q-A --expect-evidence 'MEASURED alpha' --evidence-out "$tmp/A.json" \
  --assertion Q-B --expect-evidence 'MEASURED beta'  --evidence-out "$tmp/B.json" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$(runs)" -eq 1 && -f "$tmp/A.json" && -f "$tmp/B.json" ]]; then
  ok "兩條 assertion 共用一條命令 → 命令只跑一次（$(runs)），兩份證據都在"
else
  bad '兩條 assertion 共用一條命令 → 命令只跑一次，兩份證據都在' "rc=$rc 跑了 $(runs) 次
$out"
fi

# ── Q-P2 每份證據記自己的判準，不是同一份複製兩次 ───────────────────────────
if [[ "$(field "$tmp/A.json" expect_evidence)" == "['MEASURED alpha']" \
   && "$(field "$tmp/B.json" expect_evidence)" == "['MEASURED beta']" ]]; then
  ok '每份證據記的是自己那條的樣式'
else
  bad '每份證據記的是自己那條的樣式' "A=$(field "$tmp/A.json" expect_evidence)
B=$(field "$tmp/B.json" expect_evidence)"
fi

# ── Q-P3 分得出誰沒過 ───────────────────────────────────────────────────────
make_command 0
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --assertion Q-A --expect-evidence 'MEASURED alpha' --evidence-out "$tmp/A.json" \
  --assertion Q-C --expect-evidence 'MEASURED gamma' --evidence-out "$tmp/C.json" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 \
   && "$(field "$tmp/A.json" verdict)" == PASS \
   && "$(field "$tmp/C.json" verdict)" == NOT_PASS \
   && "$out" == *"非 PASS 1 條"* ]]; then
  ok '一條缺證據 → 只有它非 PASS，其餘照舊，離場碼說得出有東西沒過'
else
  bad '一條缺證據 → 只有它非 PASS，其餘照舊' "rc=$rc A=$(field "$tmp/A.json" verdict) C=$(field "$tmp/C.json" verdict)
$out"
fi

# ── Q-N1 判定不互相汙染 ─────────────────────────────────────────────────────
# 上面那一趟就是證據：Q-C 要的樣式不在，而 Q-A 仍然 PASS。反過來也要成立——一組的
# forbid 命中不得把別組拖下水。
make_command 0
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --assertion Q-A --expect-evidence 'MEASURED alpha' --evidence-out "$tmp/A.json" \
  --assertion Q-D --expect-evidence 'MEASURED beta' --forbid-evidence 'SKIPPED' --evidence-out "$tmp/D.json" 2>&1)" && rc=0 || rc=$?
if [[ "$(field "$tmp/A.json" verdict)" == PASS \
   && "$(field "$tmp/D.json" verdict)" == NOT_PASS \
   && "$(field "$tmp/D.json" marker)" == POLARIS_ORACLE_FORBIDDEN_EVIDENCE \
   && "$(field "$tmp/A.json" forbid_evidence)" == "[]" ]]; then
  ok '一組的負向樣式命中不影響另一組，而且不會被記進另一組'
else
  bad '一組的負向樣式命中不影響另一組' "A=$(field "$tmp/A.json" verdict)/$(field "$tmp/A.json" forbid_evidence) D=$(field "$tmp/D.json" verdict)
$out"
fi

# ── Q-N2 命令自己紅的時候沒有一條是綠的 ─────────────────────────────────────
make_command 3
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --assertion Q-A --expect-evidence 'MEASURED alpha' --evidence-out "$tmp/A.json" \
  --assertion Q-B --expect-evidence 'MEASURED beta'  --evidence-out "$tmp/B.json" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 \
   && "$(field "$tmp/A.json" verdict)" == FAIL \
   && "$(field "$tmp/B.json" verdict)" == FAIL ]]; then
  ok '命令非 0 收場 → 每一份證據都不是 PASS，離場碼 1（跑不起來，不是沒證據）'
else
  bad '命令非 0 收場 → 每一份證據都不是 PASS' "rc=$rc A=$(field "$tmp/A.json" verdict) B=$(field "$tmp/B.json" verdict)
$out"
fi

# ── Q-N3 分組不完整就停 ─────────────────────────────────────────────────────
make_command 0
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --assertion Q-A --expect-evidence 'MEASURED alpha' 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 && "$out" == *"POLARIS_ORACLE_GROUP_INCOMPLETE"* && "$out" == *"Q-A"* ]]; then
  ok '一組沒有自己的輸出路徑 → 停下來並指名是哪一組'
else
  bad '一組沒有自己的輸出路徑 → 停下來並指名是哪一組' "rc=$rc
$out"
fi

make_command 0
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --assertion Q-A --expect-evidence 'MEASURED alpha' --evidence-out "$tmp/same.json" \
  --assertion Q-B --expect-evidence 'MEASURED beta'  --evidence-out "$tmp/same.json" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 && "$out" == *"POLARIS_ORACLE_GROUP_DUPLICATE_OUT"* ]]; then
  ok '兩組指到同一個檔案 → 停，不讓後寫的蓋掉先寫的'
else
  bad '兩組指到同一個檔案 → 停' "rc=$rc
$out"
fi

make_command 0
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --evidence-out "$tmp/loose.json" \
  --assertion Q-A --expect-evidence 'MEASURED alpha' --evidence-out "$tmp/A.json" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 && "$out" == *"不屬於任何一組"* ]]; then
  ok '分組模式下還有一個沒有歸屬的 --evidence-out → 停，不安靜地多寫一份'
else
  bad '分組模式下還有一個沒有歸屬的 --evidence-out → 停' "rc=$rc
$out"
fi

# ── Q-P4 舊的呼叫法一個字都不用改 ───────────────────────────────────────────
make_command 0
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --expect-evidence 'MEASURED alpha' --evidence-out "$tmp/old.json" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"PASS: hardened oracle verdict PASS"* \
   && "$(field "$tmp/old.json" verdict)" == PASS \
   && "$(field "$tmp/old.json" expect_evidence)" == "['MEASURED alpha']" ]]; then
  ok '不分組時綠的那一趟：輸出、證據、離場碼都跟以前一樣'
else
  bad '不分組時綠的那一趟跟以前一樣' "rc=$rc
$out"
fi

make_command 0
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --expect-evidence 'MEASURED gamma' --evidence-out "$tmp/old.json" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 && "$out" == *"POLARIS_ORACLE_NO_POSITIVE_EVIDENCE"* \
   && "$(field "$tmp/old.json" verdict)" == NOT_PASS ]]; then
  ok '不分組時缺證據的那一趟：離場碼 2、marker 不變'
else
  bad '不分組時缺證據的那一趟不變' "rc=$rc
$out"
fi

make_command 4
out="$(bash "$ORACLE" --command "bash $tmp/cmd.sh" --cwd "$REPO" \
  --expect-evidence 'MEASURED alpha' --evidence-out "$tmp/old.json" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 1 && "$(field "$tmp/old.json" command_exit_code)" == 4 \
   && "$(field "$tmp/old.json" verdict)" == FAIL ]]; then
  ok '不分組時命令紅的那一趟：離場碼 1，命令自己的離場碼原樣記著'
else
  bad '不分組時命令紅的那一趟不變' "rc=$rc
$out"
fi

echo "run-hardened-oracle groups selftest: PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
