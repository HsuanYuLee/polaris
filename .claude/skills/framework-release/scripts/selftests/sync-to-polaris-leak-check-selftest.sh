#!/usr/bin/env bash
# Selftest for sync-to-polaris.sh 的外洩檢查 —— 內容變成公開之前的最後一道，三種收場要分辨
# 得出來，而且不得有降級的路徑。
#
# 這件事以前是安靜的（DP-524）：那一步用 `$INSTANCE_DIR/scripts/scan-template-leaks.sh` 找
# 掃描器，那是 DP-462 之前的佈局，檔案不存在。於是每一次同步都走 else 分支改用一條 legacy
# 檢查，而它結尾寫著 `Continuing push (warn only, not blocking)` 並 `return 0`——`--blocking`
# 這個旗標在真正的釋出路徑上從此沒有作用過。
#
# **測法是把那個函式抽出來單獨餵假掃描器。** 那支腳本是一路執行到底的，source 它會真的開始
# 同步；抽函式讓這一支完全不碰 ~/polaris、不連網、不需要真的公司設定。

set -euo pipefail

# macOS 的 sed 在 C locale 下遇到多位元組字元會回 "illegal byte sequence"，而這一支比對的
# 輸出裡有中文。
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="$SCRIPTS/sync-to-polaris.sh"
GATE="$SCRIPTS/gate-skill-script-references.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; echo "  ---- 實際 ----"; sed 's/^/  /' <<< "${2:-}"; }

# Description: 造一支假掃描器。$1 = 放哪個目錄，$2 = 它要回什麼離場碼（預設 0）。它把收到
# 的參數寫進 $tmp/args，這樣「有沒有帶 --blocking」也驗得到。
fake_scanner() {
  local exit_code="${2:-0}"
  mkdir -p "$1"
  cat > "$1/scan-template-leaks.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$tmp/args"
exit $exit_code
EOF
  chmod +x "$1/scan-template-leaks.sh"
}

# Description: 把那個函式抽出來跑一次。$1 = 假掃描器所在目錄（空字串＝掃描器不在），
# $2 = LEAK_BLOCKING。輸出（含 stderr）印到 stdout，離場碼原樣傳回去——離場碼是這一支要判
# 的東西，用印出來的字串回傳它等於多一層會翻譯錯的中介。
run_check() {
  local script_dir="$1" blocking="$2"
  [[ -n "$script_dir" ]] || script_dir="$tmp/empty"
  mkdir -p "$script_dir"
  (
    set +e
    SCRIPT_DIR="$script_dir"
    INSTANCE_DIR="$tmp/instance"
    POLARIS_DIR="$tmp/polaris"
    LEAK_BLOCKING="$blocking"
    COMPANY_DIRS=(acme)
    eval "$(sed -n '/^run_template_leak_check()/,/^}/p' "$SYNC")"
    run_template_leak_check
    exit $?
  ) 2>&1
}

# ── L-P3 掃到外洩就擋得住 ────────────────────────────────────────────────
fake_scanner "$tmp/hit" 1
out="$(run_check "$tmp/hit" true)" && rc_hit=0 || rc_hit=$?
if [[ "$rc_hit" -eq 1 ]] && grep -q -- '--blocking' "$tmp/args"; then
  ok '掃描器判紅 → 這一步非 0 收場，而且真的帶了 --blocking'
else
  bad '掃描器判紅 → 這一步非 0 收場，而且真的帶了 --blocking' "$out
args: $(cat "$tmp/args" 2>/dev/null | tr '\n' ' ')"
fi

# ── 正例：乾淨就過。只有反例的話一個永遠非 0 的檢查也會全綠 ──────────────
fake_scanner "$tmp/clean" 0
out_clean="$(run_check "$tmp/clean" true)" && rc_clean=0 || rc_clean=$?
if [[ "$rc_clean" -eq 0 ]]; then
  ok '掃描器判綠 → 這一步過'
else
  bad '掃描器判綠 → 這一步過' "$out_clean"
fi

# ── L-P2 掃描器不在就停，沒有降級的路徑 ─────────────────────────────────
out_missing="$(run_check "" true)" && rc_missing=0 || rc_missing=$?
if [[ "$out_missing" == *"POLARIS_TEMPLATE_LEAK_SCANNER_MISSING"* ]] \
   && [[ "$rc_missing" -ne 0 ]] \
   && [[ "$out_missing" != *"warn only"* ]]; then
  ok '掃描器不在 → 停，不用降級的路徑繼續'
else
  bad '掃描器不在 → 停，不用降級的路徑繼續' "$out_missing"
fi

# ── L-P4 三種收場分辨得出來 ─────────────────────────────────────────────
if [[ "$rc_clean" != "$rc_hit" && "$rc_hit" != "$rc_missing" && "$rc_clean" != "$rc_missing" ]]; then
  ok "乾淨／有外洩／掃描器不在，三種收場分辨得出來（${rc_clean} / ${rc_hit} / ${rc_missing}）"
else
  bad '三種收場分辨得出來' "乾淨=$rc_clean 有外洩=$rc_hit 不在=$rc_missing"
fi

# ── L-N2 人明講的降級仍然照做 ───────────────────────────────────────────
fake_scanner "$tmp/warn" 1
out="$(run_check "$tmp/warn" false)" && rc_warn=0 || rc_warn=$?
if [[ "$rc_warn" -eq 0 ]] && ! grep -q -- '--blocking' "$tmp/args"; then
  ok '人用旗標要求 warn-only 時照做，而且不帶 --blocking'
else
  bad '人用旗標要求 warn-only 時照做，而且不帶 --blocking' "$out
args: $(cat "$tmp/args" 2>/dev/null | tr '\n' ' ')"
fi

# ── L-N1 不再有第二份「公司樣式是什麼」的答案 ───────────────────────────
# 那條 legacy 路徑自己從 workspace-config.yaml 推 JIRA key／網域／Slack channel／GitHub org，
# 唯獨少了公司代號自己——而那是真掃描器的第一條樣式。兩份答案已經漂了。
# 比對的是程式碼，不是散文——上面那一段註解本來就會提到被刪掉的那條路徑叫什麼，對它判紅
# 會逼人把「為什麼刪掉」一起刪掉。
second_source="$(grep -nE "^leak_check\(\)|^ *echo \"   Continuing push|d\.get\('jira'|unique_patterns" "$SYNC" || true)"
if [[ -z "$second_source" ]]; then
  ok '腳本裡沒有第二份樣式清單'
else
  bad '腳本裡沒有第二份樣式清單' "$second_source"
fi

# ── L-P1 指名解得開：把姊妹腳本拿掉，既有那道閘要判紅 ───────────────────
# 這是「這條引用從此在管轄裡」唯一能被觀察到的樣子。以前它由 $INSTANCE_DIR 組出來，落在那
# 道閘自己 DISCLOSURE 的「變數的值追不回這支腳本自己的位置」那一格裡——揭露是對的，但沒有
# 任何東西會紅。
build_tree() {
  local root="$1" with_sibling="$2"
  rm -rf "$root"
  mkdir -p "$root/.claude/skills/framework-release/scripts"
  cp "$SYNC" "$root/.claude/skills/framework-release/scripts/"
  # 那支腳本還指名了別的姊妹；這兩棵樹之間唯一的差別要是「掃描器在不在」，其餘都補齊，
  # 不然紅的原因會是另一條引用。
  : > "$root/.claude/skills/framework-release/scripts/validate-language-policy.sh"
  mkdir -p "$root/.claude/skills/framework-release/scripts/lib"
  : > "$root/.claude/skills/framework-release/scripts/lib/skill_scope.py"
  if [[ "$with_sibling" == true ]]; then
    fake_scanner "$root/.claude/skills/framework-release/scripts"
  fi
  # 那道閘用 git ls-files 枚舉管轄——不是 repo 的話它連掃都掃不了。
  git init -q "$root"
  git -C "$root" config user.email t@t
  git -C "$root" config user.name t
  git -C "$root" add -A
  git -C "$root" commit -qm init
}
build_tree "$tmp/tree-with" true
with_rc=0; with_out="$(bash "$GATE" --repo "$tmp/tree-with" 2>&1)" || with_rc=$?
build_tree "$tmp/tree-without" false
without_rc=0; without_out="$(bash "$GATE" --repo "$tmp/tree-without" 2>&1)" || without_rc=$?
if [[ "$with_rc" -eq 0 && "$without_rc" -ne 0 \
      && "$without_out" == *"scan-template-leaks.sh"* ]]; then
  ok '姊妹腳本被拿掉時既有那道閘會紅——這條引用在管轄裡'
else
  bad '姊妹腳本被拿掉時既有那道閘會紅——這條引用在管轄裡' "有姊妹 rc=$with_rc / 沒有 rc=$without_rc
$without_out"
fi

echo "sync-to-polaris leak-check selftest: PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
