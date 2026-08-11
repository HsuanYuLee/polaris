#!/usr/bin/env bash
# evidence-report-selftest.sh — DP-510 的斷言，一條一個 case，離線可重跑。
#
# Usage: evidence-report-selftest.sh --assertion <ID>
#        evidence-report-selftest.sh --list
#        evidence-report-selftest.sh              （不帶參數＝跑全部）
#
# Exit: 0 這條成立 / 1 這條不成立 / 2 量不到（前置條件沒到，不得被讀成成立）
#
# 量的是可攜層：報告產不產得出來、唯不唯讀、沒過的時候還在不在、發佈是不是宣告驅動的。
#
# **B 段不在這裡。** 那四條量的是某一家公司那一層（憑證、站台、標記形狀、模板住哪），而它們
# 的量測必須指名那家公司——這支 skill 會被帶到沒有那家公司的環境去，所以那一段住在認領它的
# 那支 skill 自己的目錄裡，跟宣告放在一起。
#
# **一個位元組都不往外送。** 會打外部系統的那幾條全部走 --dry-run 或假的宣告樹：一支會在
# 別人的單上留下痕跡的量測，第二次就沒有人敢跑它。
#
# 每個 case 至少印一行 `MEASURED …`，說出它真的量到了什麼。掃不到目標、樣本數 0 一律走
# exit 2——一個什麼都沒掃到的負向檢查，跟一個掃過而且乾淨的檢查在輸出上長得一模一樣。

set -uo pipefail

SELFTEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELFTEST_DIR/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
SKILLS_ROOT="$(cd "$SKILL_DIR/.." && pwd)"

RENDER="$SCRIPTS_DIR/render-evidence-report.sh"
RESOLVE="$SCRIPTS_DIR/resolve-evidence-publish.sh"

# 可攜層裡不得出現的東西：某一家公司的站台、某一種 wiki 語法、某一個憑證變數名、某一個
# 外部系統的名字。這一份是判準，不是座標——它說的是「這一類詞不該出現」。
COMPANY_INTERFACE_TOKENS="atlassian.net JIRA_API_TOKEN JIRA_USERNAME JIRA_EMAIL JIRA_SITE thumbnail! rest/api slack_channel"

list_assertions() {
  grep -oE '^  A-[PN][0-9][A|PN0-9-]*\)' "$1" | tr -d ' )' | tr '|' '\n' | grep -E '^A-[PN][0-9]$'
}

ASSERTION=""
case "${1:-}" in
  "")
    rc=0; failed=""; unmeasured=""
    for one in $(list_assertions "$0"); do
      out="$(bash "$0" --assertion "$one" 2>&1)"; case "$?" in
        0) printf '  ✅ %s\n' "$one" ;;
        2) printf '  ❔ %s — %s\n' "$one" "$(printf '%s' "$out" | tail -1)"; unmeasured="${unmeasured}${one} " ;;
        *) printf '  ❌ %s — %s\n' "$one" "$(printf '%s' "$out" | tail -1)"; failed="${failed}${one} "; rc=1 ;;
      esac
    done
    [[ -z "$unmeasured" ]] || echo "量不到（不是過）：${unmeasured}" >&2
    [[ -z "$failed" ]] || echo "沒過：${failed}" >&2
    exit "$rc" ;;
  --list) list_assertions "$0"; exit 0 ;;
  --assertion) ASSERTION="${2:-}" ;;
  *) echo "用法：$0 [--assertion <ID>] [--list]" >&2; exit 2 ;;
esac
[[ -n "$ASSERTION" ]] || { echo "要 --assertion" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -f -r "$WORK"' EXIT

measured() { echo "MEASURED $*"; }
fail() { echo "FAILED $*" >&2; exit 1; }
unmeasurable() { echo "UNMEASURABLE $*" >&2; exit 2; }

for tool in python3 jq; do
  command -v "$tool" >/dev/null 2>&1 || unmeasurable "沒有 ${tool}，這一條量不到"
done

# ---------------------------------------------------------------- 共用的跑法

# 造一張假的單：斷言 ID 由呼叫者給，每一個 ID 後面接一個判定字母（P＝有證據且 PASS、
# F＝有證據但 FAIL、M＝根本沒有證據）。回單的目錄。
#
# 用假的單而不是樹上真的那幾張：真的單會隨著別人的工作改變，而這裡要量的是「三種判定各自
# 產不產得出來」——那需要一張永遠有一條紅、永遠有一條問不到的單。
make_issue() {
  local issue="$WORK/issues/${1}/backlog/TICKET-1-fake"; shift
  mkdir -p "$issue/.spine/evidence"
  {
    echo "---"
    echo "destination: workspace"
    echo "---"
    echo
    echo "<!-- POLARIS-FROZEN-A-BEGIN -->"
    local spec
    for spec in "$@"; do
      echo "- **${spec%:*} 說明**：一句話。"
    done
    echo "<!-- POLARIS-FROZEN-A-END -->"
  } > "$issue/index.md"
  local commands="[]"
  for spec in "$@"; do
    local aid="${spec%:*}" verdict="${spec##*:}"
    case "$verdict" in
      P|F)
        local v="PASS"; [[ "$verdict" == "P" ]] || v="FAIL"
        python3 - "$issue/.spine/evidence/${aid}.json" "$v" <<'PY'
import json, sys
path, verdict = sys.argv[1:3]
json.dump({
    "schema_version": 1, "producer": "run-hardened-oracle.sh",
    "command": "true", "command_exit_code": 0 if verdict == "PASS" else 1,
    "verdict": verdict, "marker": None, "detail": None, "tools": [],
    "stdout": "MEASURED fake\n", "stderr": "", "recorded_at": "2026-08-12T00:00:00Z",
    "head_sha": "0" * 40, "measured_in": "/fake",
    "expect_evidence": ["MEASURED"], "forbid_evidence": [],
}, open(path, "w"), ensure_ascii=False)
PY
        commands="$(printf '%s' "$commands" | jq --arg id "$aid" '. + [{assertion_id:$id, kind:"baseline", old_command_hash:null, new_command_hash:"sha256:0", new_command:"true", recorded_at:"2026-08-12T00:00:00Z"}]')"
        ;;
      M) : ;;  # 沒有證據，也不登錄——那正是「量不到」該長的樣子
    esac
  done
  printf '{"schema_version":1,"entries":%s}\n' "$commands" > "$issue/.spine/measurement-ledger.json"
  printf '%s\n' "$issue"
}

# 造一棵只有一行宣告的假 skill 樹，回它的路徑。宣告的命令把它收到的東西原樣寫進一個檔案，
# 所以「核心有沒有把兩個路徑原樣交出去」量得到。
make_skills_tree() {
  local namespace="${1:-fake-ns}" behaviour="${2:-ok}"
  local tree="$WORK/skills-${namespace}-${behaviour}"
  mkdir -p "$tree/fake-owner"
  cat > "$tree/fake-owner/answer.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
mode="\${1:-}"; shift || true
report=""; manifest=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --report) report="\${2:-}"; shift 2 ;;
    --manifest) manifest="\${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s\n%s\n%s\n' "\$mode" "\$report" "\$manifest" > "$tree/received.txt"
[[ "$behaviour" == "ok" ]] || { echo "[fake] 送不出去" >&2; exit 7; }
echo "[fake] 送出去了"
SH
  chmod +x "$tree/fake-owner/answer.sh"
  {
    echo "---"
    echo "name: fake-owner"
    echo "---"
    echo "<!-- FAKE-EVIDENCE-PUBLISH-${namespace}: bash ${tree}/fake-owner/answer.sh -->"
  } > "$tree/fake-owner/SKILL.md"
  printf '%s\n' "$tree"
}

# 這棵樹上所有屬於可攜層的檔案（verify-ac 自己），一行一個。
portable_files() {
  find "$SKILL_DIR" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.py' \) \
    -not -path '*/selftests/*'
}

case "$ASSERTION" in

# ---------------------------------------------------------------- A：證據離得開這台機器

  A-P1)
    issue="$(make_issue framework A-P1:P A-P2:P)"
    bash "$RENDER" --issue "$issue" --out "$WORK/out" >/dev/null 2>&1 \
      || fail "產不出來"
    [[ -f "$WORK/out/report.md" ]]    || fail "沒有 report.md"
    [[ -f "$WORK/out/manifest.json" ]] || fail "沒有 manifest.json"
    for field in .head '.assertions[0].id' '.assertions[0].verdict' \
                 '.assertions[0].command' '.assertions[0].evidence_file' .files; do
      value="$(jq -r "$field" < "$WORK/out/manifest.json")"
      [[ -n "$value" && "$value" != "null" ]] || fail "清單少了 ${field}"
    done
    files="$(jq -r '.files | length' < "$WORK/out/manifest.json")"
    [[ "$files" -gt 0 ]] || fail "清單沒有說要送出去哪些檔案"
    measured "兩個檔案都在；清單逐條帶著 id／判定／head／量測命令／證據檔，另有 ${files} 個要一起送出去的檔案"
    ;;

  A-P2)
    issue="$(make_issue framework A-P1:P A-P2:F A-P3:M)"
    before="$WORK/before.txt"; after="$WORK/after.txt"
    ( cd "$issue" && find . -type f -not -path './.spine/report/*' -exec shasum {} \; | sort ) > "$before"
    [[ -s "$before" ]] || unmeasurable "假的單裡一個檔案都沒有，這一條量不到"
    bash "$RENDER" --issue "$issue" >/dev/null 2>&1 || fail "產不出來"
    ( cd "$issue" && find . -type f -not -path './.spine/report/*' -exec shasum {} \; | sort ) > "$after"
    diff -q "$before" "$after" >/dev/null \
      || fail "跑完之後單裡的東西變了：$(diff "$before" "$after" | head -4 | tr '\n' ' ')"
    [[ ! -f "$issue/.spine/delivery.json" ]]   || fail "它寫了交付紀錄"
    [[ ! -f "$issue/.spine/loop-state.json" ]] || fail "它寫了輪次狀態"
    measured "$(grep -c . "$before") 個檔案跑前跑後逐個雜湊相同；沒有寫交付紀錄、沒有寫輪次狀態"
    ;;

  A-P3)
    # 三種輸入各一次：全過、有一條沒過、有一條沒有證據。
    for shape in "all-pass:A-P1:P A-P2:P" "has-fail:A-P1:P A-P2:F" "has-missing:A-P1:P A-P2:M"; do
      name="${shape%%:*}"; specs="${shape#*:}"
      # shellcheck disable=SC2086
      issue="$(make_issue "ns-${name}" $specs)"
      bash "$RENDER" --issue "$issue" --out "$WORK/out-$name" >/dev/null 2>&1 \
        || fail "${name} 這一種產不出報告——最想看報告的那一刻正是這一刻"
      [[ -s "$WORK/out-$name/report.md" ]] || fail "${name} 的報告是空的"
    done
    pass_word="$(grep -c '過' "$WORK/out-all-pass/report.md")"
    grep -q '沒過' "$WORK/out-has-fail/report.md" \
      || fail "有一條紅的那一份報告上看不出「沒過」"
    grep -qE '沒過|量不到' "$WORK/out-has-missing/report.md" \
      || fail "有一條沒有證據的那一份報告上看不出它沒站住"
    measured "三種輸入都產得出報告（全過、有一條沒過、有一條沒有證據），而且報告上分得出來（${pass_word} 處提到判定）"
    ;;

  A-P4)
    tree="$(make_skills_tree fake-ns ok)"
    issue="$(make_issue fake-ns A-P1:P)"
    out="$WORK/out-publish"
    # 核心不知道目的地是什麼，只知道要把兩個路徑交出去。所以量的是「交出去的是不是那兩個」。
    bash "$RENDER" --issue "$issue" --out "$out" >/dev/null 2>&1 || fail "產不出來"
    bash "$RESOLVE" publish --namespace fake-ns --skills "$tree" \
      --report "$out/report.md" --manifest "$out/manifest.json" >/dev/null 2>&1 \
      || fail "交不出去"
    [[ -f "$tree/received.txt" ]] || fail "宣告的命令沒有被叫到"
    got_mode="$(sed -n '1p' "$tree/received.txt")"
    got_report="$(sed -n '2p' "$tree/received.txt")"
    got_manifest="$(sed -n '3p' "$tree/received.txt")"
    [[ "$got_mode" == "publish" ]] || fail "模式名沒有交過去（拿到的是「${got_mode}」）"
    [[ "$got_report" == "$out/report.md" ]] || fail "報告路徑被改過了：${got_report}"
    [[ "$got_manifest" == "$out/manifest.json" ]] || fail "清單路徑被改過了：${got_manifest}"
    measured "宣告驅動：掃到 fake-ns 的宣告，把 publish 與那兩個路徑原樣交過去"
    ;;

  A-N1)
    hits="$WORK/company-hits.txt"; : > "$hits"
    scanned=0
    while IFS= read -r f; do
      scanned=$((scanned + 1))
      for token in $COMPANY_INTERFACE_TOKENS; do
        grep -qF "$token" "$f" 2>/dev/null && echo "$f: $token" >> "$hits"
      done
    done < <(portable_files)
    [[ "$scanned" -gt 0 ]] || unmeasurable "可攜層裡一個檔案都沒掃到，這一條量不到"
    [[ ! -s "$hits" ]] \
      || fail "可攜層裡出現了某一家公司的介面：$(tr '\n' ' ' < "$hits")"
    measured "掃過 ${scanned} 個可攜層檔案，$(echo $COMPANY_INTERFACE_TOKENS | wc -w | tr -d ' ') 個公司介面詞一個都沒出現（selftests/ 不算，那些詞是它的題目）"
    ;;

  A-N2)
    tree="$(make_skills_tree fake-ns boom)"
    issue="$(make_issue fake-ns A-P1:P)"
    before="$WORK/n2-before.txt"
    ( cd "$issue" && find . -type f -not -path './.spine/report/*' -exec shasum {} \; | sort ) > "$before"
    bash "$RENDER" --issue "$issue" --out "$WORK/out-boom" >/dev/null 2>&1 || fail "產不出來"
    bash "$RESOLVE" publish --namespace fake-ns --skills "$tree" \
      --report "$WORK/out-boom/report.md" --manifest "$WORK/out-boom/manifest.json" \
      >/dev/null 2>&1
    rc=$?
    [[ "$rc" -ne 0 ]] || fail "宣告的命令回了非 0，這裡卻當成成功"
    after="$WORK/n2-after.txt"
    ( cd "$issue" && find . -type f -not -path './.spine/report/*' -exec shasum {} \; | sort ) > "$after"
    diff -q "$before" "$after" >/dev/null \
      || fail "送不出去之後，單裡的判定或證據被改動了"
    verdict="$(jq -r '.assertions[0].verdict' < "$WORK/out-boom/manifest.json")"
    [[ "$verdict" == "PASS" ]] || fail "送不出去把一條 PASS 變成了 ${verdict}"
    [[ ! -f "$issue/.spine/delivery.json" ]] || fail "送不出去卻寫了交付紀錄"
    measured "宣告的命令回 ${rc}，而單裡 $(grep -c . "$before") 個檔案逐個雜湊不變、那條斷言仍是 PASS"
    ;;

  A-N3)
    tree="$(make_skills_tree other-ns ok)"
    issue="$(make_issue nobody-declared-this A-P1:P)"
    out="$WORK/out-silent"
    bash "$RENDER" --issue "$issue" --out "$out" --publish >"$WORK/n3.out" 2>"$WORK/n3.err"
    rc=$?
    [[ "$rc" -eq 4 ]] || fail "沒有人宣告的時候離場碼是 ${rc}，不是 4——那分不出「壞掉」與「要人回答」"
    grep -q 'nobody-declared-this' "$WORK/n3.err" \
      || fail "沒有指名是哪一個命名空間問不到"
    grep -q 'EVIDENCE-PUBLISH' "$WORK/n3.err" \
      || fail "沒有說出修法"
    [[ -f "$out/report.md" ]] || fail "報告沒有留在本機"
    # 不得沿用別人的宣告：這棵樹上真的有別的命名空間的宣告，而這張單的不是它們任何一個。
    grep -qF "$tree" "$WORK/n3.err" && fail "它去用了別的命名空間的宣告"
    measured "離場碼 4、指名了「nobody-declared-this」、附上修法、報告留在本機，而且沒有沿用任何別的命名空間的宣告"
    ;;

  *)
    echo "不認得的斷言：$ASSERTION" >&2
    echo "有的是：$(list_assertions "$0" | tr '\n' ' ')" >&2
    exit 2 ;;
esac
