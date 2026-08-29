#!/usr/bin/env bash
# Purpose: DP-512 的量測。問兩件事：**沒回到提出者那裡的意見會不會被看見**（A 段），以及
#          **回覆這個動作有沒有主人、有沒有繞過既有的對外寫入紀律**（B 段）。
# Inputs:  mktemp 底下的假 repo ＋ `fixtures/gh`（假的 gh，由環境變數驅動）。
# Outputs: 每條 assertion 一行 `✅ <id>` 或 `❌ <id>`；`--assertion <id>` 只跑一條。
# Exit:    0 全綠 / 1 有紅的 / 2 量不到
#
# 這是一個負向 assertion 的儀器：「沒有沒回的意見」跟「我沒問到意見」在輸出上長得一樣。所以每一種
# 「問不到」都有自己的出口，而且 A-P3 專門量那件事。
#
# 每條 assertion 前面都有 preflight：目標檔案在不在、樣本數夠不夠。preflight 不過用離場碼 2 停下來，
# 不讓它走進判定——一個因為掃到 0 個檔案而變綠的量測，什麼都沒量。

set -uo pipefail

SKILLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SELF_SKILL="$SKILLS_ROOT/swe-knowledge"
CHECK="$SELF_SKILL/scripts/check-swe-done.sh"
RESOLVER="$SELF_SKILL/scripts/resolve-external-write-gate.sh"
SKILL_MD="$SELF_SKILL/SKILL.md"
FIXTURE_GH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/gh"
REPO_ROOT="$(cd "$SKILLS_ROOT/../.." && pwd)"

ONLY=""
[[ "${1:-}" == "--assertion" ]] && ONLY="${2:-}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

RED=0
say()  { printf '%s\n' "$*"; }
ok()   { printf '  ✅ %s\n' "$1"; }
no()   { printf '  ❌ %s — %s\n' "$1" "$2"; RED=1; }
want() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }
die()  { printf 'UNMEASURABLE %s\n' "$*" >&2; exit 2; }
# 有一種量不到不該把整支停掉：那一條的前置條件永遠不會再成立（它問的是某一趟交付的
# diff，而那一趟早就併進主幹了），而其餘幾條每一次都量得到。用 die 的話，一條永久量不到
# 的 assertion 會讓這支 selftest 永遠非 0 收場，然後被當成紅的。
# 它仍然不是綠的——收在 SKIPPED 裡，最後一行印出來。
SKIPPED=()
skip() { printf '  ❔ %s — 量不到：%s\n' "$1" "$2"; SKIPPED+=("$1"); }

for f in "$CHECK" "$RESOLVER" "$SKILL_MD" "$FIXTURE_GH"; do
  [[ -f "$f" ]] || die "$f 不在，什麼都量不到。"
done

# Description: 造一個乾淨的假 repo，站在一條 feature branch 上，origin 指向一個假位址。
# Args: $1 = case 名字
# Outputs: repo 路徑
new_repo() {
  local repo="$WORK/$1"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  echo base > "$repo/file.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  git -C "$repo" remote add origin git@github.com:acme/widget.git
  git -C "$repo" checkout -q -b feat/x
  printf '%s' "$repo"
}

# Description: 用假的 gh 跑一次檢查。
# Args: $1 = repo, $2 = FAKE_COMMENTS, 其餘用預設
# Outputs: 設定 OUT 與 RC
run_check() {
  local repo="$1" comments="${2:-}"
  RC=0
  OUT="$(PATH="$(dirname "$FIXTURE_GH"):$PATH" \
        FAKE_PR_FACTS="${FAKE_PR_FACTS_OVERRIDE:-OPEN	101	me}" \
        FAKE_COMMENTS="$comments" \
        FAKE_COMMENTS_RC="${FAKE_COMMENTS_RC_OVERRIDE:-0}" \
        FAKE_CALL_LOG="${FAKE_CALL_LOG:-}" \
        bash "$CHECK" --repo "$repo" --base main 2>&1)" || RC=$?
}

# 一串三則：#1 是 alice 提的串頭，#2 是 me（作者）回的，#3 是 bob 提的另一個串頭。
THREE_MIXED=$'1\t-\talice\n2\t1\tme\n3\t-\tbob'
ALL_ANSWERED=$'1\t-\talice\n2\t1\tme'
NONE_AT_ALL=''

# ── A-P1：沒回的意見會被看見 ────────────────────────────────────────────────
if want A-P1; then
  repo="$(new_repo a_p1)"
  run_check "$repo" $'1\t-\talice\n5\t-\tbob'
  if [[ "$RC" -eq 0 ]]; then
    no A-P1 "有兩條沒回卻判綠"
  elif printf '%s' "$OUT" | grep -q '第 5 條不成立' \
    && printf '%s' "$OUT" | grep -q '沒回：#1' \
    && printf '%s' "$OUT" | grep -q '沒回：#5'; then
    say "MEASURED 兩條沒回的意見都被逐條指名，而且完成條件因此不成立"
    ok A-P1
  else
    no A-P1 "紅了但沒有逐條指名是哪幾條：$OUT"
  fi
fi

# ── A-P2：三種輸入判得不一樣 ────────────────────────────────────────────────
if want A-P2; then
  repo="$(new_repo a_p2_none)"; run_check "$repo" "$NONE_AT_ALL"; rc_none="$RC"; out_none="$OUT"
  repo="$(new_repo a_p2_all)";  run_check "$repo" "$ALL_ANSWERED"; rc_all="$RC";  out_all="$OUT"
  repo="$(new_repo a_p2_some)"; run_check "$repo" "$THREE_MIXED";  rc_some="$RC"; out_some="$OUT"
  if [[ "$rc_none" -ne 0 || "$rc_all" -ne 0 ]]; then
    no A-P2 "沒有意見（rc=${rc_none}）或意見全回過（rc=${rc_all}）不該紅"
  elif [[ "$rc_some" -eq 0 ]]; then
    no A-P2 "有一條沒回卻判綠"
  elif printf '%s' "$out_some" | grep -q '沒回：#3' \
    && ! printf '%s' "$out_all" | grep -q '沒回：' \
    && ! printf '%s' "$out_none" | grep -q '沒回：'; then
    say "MEASURED 三種輸入三種答案：沒有意見 rc=${rc_none}、全回過 rc=${rc_all}、有一條沒回 rc=$rc_some"
    ok A-P2
  else
    no A-P2 "三種輸入裡有兩種長得一樣"
  fi
fi

# ── A-P3：量不到不得回綠 ────────────────────────────────────────────────────
if want A-P3; then
  repo="$(new_repo a_p3)"
  FAKE_COMMENTS_RC_OVERRIDE=1 run_check "$repo" "$NONE_AT_ALL"
  rc_api="$RC"; out_api="$OUT"
  # 另一種問不到：連 gh 都不在。這一條原本就有，一起量，因為它們共用同一個「不得回綠」。
  repo="$(new_repo a_p3_nogh)"
  mkdir -p "$WORK/nogh-bin"
  for tool in bash git sed grep awk cut find sort printf; do
    real="$(command -v "$tool" 2>/dev/null)" && ln -sf "$real" "$WORK/nogh-bin/$tool"
  done
  RC=0
  OUT="$(PATH="$WORK/nogh-bin" bash "$CHECK" --repo "$repo" --base main 2>&1)" || RC=$?
  rc_nogh="$RC"; out_nogh="$OUT"
  if [[ "$rc_api" -eq 0 || "$rc_nogh" -eq 0 ]]; then
    no A-P3 "問不到卻判綠（api rc=${rc_api}、沒有 gh rc=${rc_nogh}）"
  elif printf '%s' "$out_api" | grep -q '量不到第 5 條' \
    && printf '%s' "$out_nogh" | grep -q '量不到第 2 條'; then
    say "MEASURED 兩種問不到各自說出自己是哪一種，而且都不是綠的"
    ok A-P3
  else
    no A-P3 "紅了但沒說出是哪一種量不到：$out_api / $out_nogh"
  fi
fi

# ── A-P4：別人的回覆不算我的回覆 ────────────────────────────────────────────
if want A-P4; then
  repo="$(new_repo a_p4)"
  # #1 是 alice 提的，#2 是另一位 reviewer bob 在同一串裡接話——作者一個字都沒說。
  run_check "$repo" $'1\t-\talice\n2\t1\tbob'
  if [[ "$RC" -eq 0 ]]; then
    no A-P4 "只有另一位 reviewer 接過話就判成回過了"
  elif printf '%s' "$OUT" | grep -q '沒回：#1'; then
    say "MEASURED 同一串裡有別人接話，但作者沒回——仍然算沒回"
    ok A-P4
  else
    no A-P4 "紅了但不是因為這一條：$OUT"
  fi
fi

# ── A-N1：不長出第二個權威 ──────────────────────────────────────────────────
if want A-N1; then
  repo="$(new_repo a_n1)"
  before="$(find "$repo" -not -path '*/.git/*' | sort)"
  run_check "$repo" "$THREE_MIXED"
  after="$(find "$repo" -not -path '*/.git/*' | sort)"
  # 第二個權威長什麼樣：另一支腳本也印得出完成判定的結論。
  others="$(grep -rl 'SWE-DONE-OK\|SWE-DONE-INCOMPLETE' "$SELF_SKILL/scripts" 2>/dev/null \
            | grep -v '/selftests/' | grep -v 'check-swe-done.sh' || true)"
  if [[ "$before" != "$after" ]]; then
    no A-N1 "跑完之後工作區多了東西：$(comm -13 <(printf '%s' "$before") <(printf '%s' "$after") | tr '\n' ' ')"
  elif [[ -n "$others" ]]; then
    no A-N1 "還有別的東西也在回答完成判定：$others"
  else
    say "MEASURED 跑完之後一個檔案都沒多，而且只有 check-swe-done.sh 回答完成判定"
    ok A-N1
  fi
fi

# ── A-N2：只問這條 branch 自己的 PR ─────────────────────────────────────────
if want A-N2; then
  repo="$(new_repo a_n2)"
  log="$WORK/calls.txt"; : > "$log"
  FAKE_CALL_LOG="$log" run_check "$repo" "$THREE_MIXED"
  asked="$(grep 'pulls/' "$log" | grep -c '' || true)"
  wrong="$(grep 'pulls/' "$log" | grep -v 'pulls/101/' | grep -c '' || true)"
  if [[ "$asked" -eq 0 ]]; then
    die "A-N2 量不到：一次 pulls/ 都沒問到，樣本是空的"
  elif [[ "$wrong" -ne 0 ]]; then
    no A-N2 "問到了不屬於這條 branch 的 PR：$(grep 'pulls/' "$log" | grep -v 'pulls/101/')"
  else
    say "MEASURED 問了 ${asked} 次 pulls/，全部都是這條 branch 的 PR #101"
    ok A-N2
  fi
fi

# ── A-N3：不動判定那條路 ────────────────────────────────────────────────────
if want A-N3; then
  judge_paths=(
    ".claude/skills/verify-ac/scripts/run-hardened-oracle.sh"
    ".claude/skills/verify-ac/scripts/record-delivery-intent.sh"
    ".claude/skills/verify-ac/scripts/record-measurement-change.sh"
    ".claude/skills/verify-ac/scripts/lib/assertion_verdicts.py"
  )
  base="$(git -C "$REPO_ROOT" merge-base HEAD origin/main 2>/dev/null || true)"
  if [[ -z "$base" ]]; then
    die "A-N3 量不到：算不出跟預設分支的共同祖先"
  fi
  # 這一條問的是**那一趟交付**動了什麼，而 merge-base 給的是**現在這條分支**動了什麼。
  # 那張單併進主幹之後，這兩個就不是同一件事了：任何後來動到被守著的那幾個檔案的單，
  # 都會被這一條當成「那張單改了判定路徑」而判紅——一支永久留在樹裡的 selftest 去審別人
  # 的交付。判準用這支 selftest 自己：它是在那一趟被加進來的，diff 裡沒有那個新增，這
  # 條分支就不是它，量不到（不是綠）。
  own="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  own_rel="${own#"$REPO_ROOT"/}"
  mine=yes
  git -C "$REPO_ROOT" diff --name-status "$base"..HEAD 2>/dev/null \
    | grep -qE "^A[[:space:]]+${own_rel}$" || mine=no
  if [[ "$mine" == no ]]; then
    skip A-N3 "這條 assertion 問的是加進這支 selftest 的那一趟，而現在這條分支不是它"
  else
  changed=""
  for p in "${judge_paths[@]}"; do
    [[ -f "$REPO_ROOT/$p" ]] || die "A-N3 量不到：$p 不在，樣本不成立"
    a="$(git -C "$REPO_ROOT" rev-parse "$base:$p" 2>/dev/null || true)"
    b="$(git -C "$REPO_ROOT" rev-parse "HEAD:$p" 2>/dev/null || true)"
    [[ -n "$a" && "$a" == "$b" ]] || changed="${changed} ${p}"
  done
  if [[ -n "$changed" ]]; then
    no A-N3 "判定那條路被動到了：${changed}"
  else
    say "MEASURED 判定那條路的 ${#judge_paths[@]} 個檔案，blob 跟共同祖先逐一相同"
    ok A-N3
  fi
  fi
fi

# ── B-P1：動作說得出來，而且真的跑得起來 ────────────────────────────────────
if want B-P1; then
  line="$(grep -n 'comments/<comment_id>/replies' "$SKILL_MD" | head -1 || true)"
  if [[ -z "$line" ]]; then
    no B-P1 "SKILL.md 裡沒有說出怎麼把處置回到那條意見上"
  else
    cmd="${line#*:}"; cmd="${cmd#*:}"
    body="$WORK/reply.md"; echo '處置：已修，見 commit abc123。' > "$body"
    log="$WORK/b_p1_calls.txt"; : > "$log"
    runnable="${cmd//<owner>/acme}"
    runnable="${runnable//<name>/widget}"
    runnable="${runnable//<n>/101}"
    runnable="${runnable//<comment_id>/9}"
    runnable="${runnable//<file>/$body}"
    rc=0
    PATH="$(dirname "$FIXTURE_GH"):$PATH" FAKE_CALL_LOG="$log" \
      bash -c "$runnable" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      no B-P1 "那一行跑不起來（離場碼 ${rc}）：$runnable"
    elif grep -q 'pulls/101/comments/9/replies' "$log"; then
      say "MEASURED SKILL.md 裡那一行填上座標之後真的跑得起來，而且送到了那條意見的 replies"
      ok B-P1
    else
      no B-P1 "跑起來了但沒送到那條意見上：$(cat "$log")"
    fi
  fi
fi

# ── B-P2：落地 → 過關 → 才送，順序不得顛倒 ─────────────────────────────────
if want B-P2; then
  section="$(awk '/^## 回覆 reviewer$/{f=1} f&&/^## /&&!/^## 回覆 reviewer$/{exit} f' "$SKILL_MD")"
  if [[ -z "$section" ]]; then
    die "B-P2 量不到：找不到〈回覆 reviewer〉那一段"
  fi
  pos_file="$(printf '%s\n' "$section" | grep -n '把回覆寫成一個檔案' | head -1 | cut -d: -f1)"
  pos_gate="$(printf '%s\n' "$section" | grep -n 'resolve-external-write-gate.sh' | head -1 | cut -d: -f1)"
  pos_send="$(printf '%s\n' "$section" | grep -n 'comments/<comment_id>/replies' | head -1 | cut -d: -f1)"
  if [[ -z "$pos_file" || -z "$pos_gate" || -z "$pos_send" ]]; then
    no B-P2 "三步裡有一步沒寫出來（落地=$pos_file 關卡=$pos_gate 送=${pos_send}）"
  elif [[ "$pos_file" -lt "$pos_gate" && "$pos_gate" -lt "$pos_send" ]]; then
    say "MEASURED 三步照順序出現在同一段裡：落地 L${pos_file} → 過關 L${pos_gate} → 送 L${pos_send}"
    ok B-P2
  else
    no B-P2 "順序不對：落地 L${pos_file} / 關卡 L${pos_gate} / 送 L${pos_send}"
  fi
fi

# ── B-P3：用既有的那一支，不新增 ────────────────────────────────────────────
if want B-P3; then
  # 先在一棵假的宣告樹上量：有人宣告就回它、沒有人宣告就說出來並回非 0。
  fake="$WORK/fake-skills"
  mkdir -p "$fake/alpha" "$fake/beta"
  printf '# alpha\n' > "$fake/alpha/SKILL.md"
  printf '# beta\n\n<!-- ACME-EXTERNAL-WRITE-GATE: bash /somewhere/gate.sh -->\n' > "$fake/beta/SKILL.md"
  got="$(bash "$RESOLVER" --skills-root "$fake" 2>/dev/null)"; rc_found=$?
  rm -f "$fake/beta/SKILL.md"; printf '# beta\n' > "$fake/beta/SKILL.md"
  none_out="$(bash "$RESOLVER" --skills-root "$fake" 2>&1)"; rc_none=$?
  # 再在真的樹上量：有宣告的話它指到的東西要真的在，而且不得住在這支 skill 自己底下。
  real_out="$(bash "$RESOLVER" 2>&1)"; rc_real=$?
  real_note="這個環境沒有人宣告（離場碼 ${rc_real}），真樹那一半跳過"
  real_bad=""
  if [[ "$rc_real" -eq 0 ]]; then
    target="$(printf '%s' "$real_out" | awk '{for(i=1;i<=NF;i++) if ($i ~ /\.sh$/) {print $i; exit}}')"
    if [[ -z "$target" || ! -f "$REPO_ROOT/$target" ]]; then
      real_bad="宣告指到的東西不在：${target:-空的}"
    elif [[ "$target" == *"/swe-knowledge/"* ]]; then
      real_bad="那道檢查被複製進這支 skill 自己底下了：$target"
    else
      real_note="真樹上宣告解到 ${target}，檔案在，而且不住在這支 skill 底下"
    fi
  fi
  copies="$(grep -rl 'POLARIS_EXTERNAL_WRITE_WRITER' "$SELF_SKILL" 2>/dev/null \
            | grep -v '/selftests/' || true)"
  if [[ "$rc_found" -ne 0 || "$got" != "bash /somewhere/gate.sh" ]]; then
    no B-P3 "有人宣告的時候沒有回那一行（rc=${rc_found}，拿到「${got}」）"
  elif [[ "$rc_none" -eq 0 ]]; then
    no B-P3 "沒有人宣告的時候回了 0——那分不出「沒有那一層」與「檢查全過」"
  elif ! printf '%s' "$none_out" | grep -q '沒有人宣告'; then
    no B-P3 "沒有人宣告的時候沒有說出來：$none_out"
  elif [[ -n "$real_bad" ]]; then
    no B-P3 "$real_bad"
  elif [[ -n "$copies" ]]; then
    no B-P3 "那道檢查被複製了一份進來：$copies"
  else
    say "MEASURED 假樹上有宣告回那一行、沒宣告回非 0 並說出來；$real_note"
    ok B-P3
  fi
fi

# ── B-N1：不帶包住那個 API 呼叫的腳本 ───────────────────────────────────────
if want B-N1; then
  scripts="$(find "$SELF_SKILL/scripts" -type f -not -path '*/selftests/*' | sort)"
  [[ -n "$scripts" ]] || die "B-N1 量不到：這支 skill 底下一個腳本都沒有"
  wrappers="$(printf '%s\n' "$scripts" | xargs grep -l '/replies' 2>/dev/null || true)"
  if [[ -n "$wrappers" ]]; then
    no B-N1 "有腳本把那個 API 呼叫包起來了：$wrappers"
  else
    say "MEASURED 盤點 $(printf '%s\n' "$scripts" | grep -c '') 支腳本，沒有一支包住回覆那個呼叫"
    ok B-N1
  fi
fi

# ── B-N2：不擴大對外能力 ────────────────────────────────────────────────────
if want B-N2; then
  scripts="$(find "$SELF_SKILL/scripts" -type f -not -path '*/selftests/*' | sort)"
  [[ -n "$scripts" ]] || die "B-N2 量不到：這支 skill 底下一個腳本都沒有"
  # 註解裡出現這些字多半在否認它們，所以掃的是去掉註解之後的行。
  writes="$(printf '%s\n' "$scripts" | while read -r f; do
    grep -vE '^\s*#' "$f" | grep -nE 'curl |--method (POST|PUT|PATCH|DELETE)|gh (pr|issue|api) [a-z]* *--method' \
      | sed "s#^#${f}:#" || true
  done)"
  if [[ -n "$writes" ]]; then
    no B-N2 "腳本裡出現了往外寫的呼叫：$writes"
  else
    say "MEASURED 盤點 $(printf '%s\n' "$scripts" | grep -c '') 支腳本，去掉註解之後 0 個往外寫的呼叫"
    ok B-N2
  fi
fi

# ── B-N3：不靜默送出 ────────────────────────────────────────────────────────
if want B-N3; then
  sends="$(grep 'method POST' "$SKILL_MD" | grep -c '' || true)"
  section="$(awk '/^## 回覆 reviewer$/{f=1} f&&/^## /&&!/^## 回覆 reviewer$/{exit} f' "$SKILL_MD")"
  in_section="$(printf '%s\n' "$section" | grep -c 'method POST' || true)"
  if [[ "$sends" -eq 0 ]]; then
    die "B-N3 量不到：整份散文裡一個送出動作都沒有，樣本是空的"
  elif [[ "$sends" -ne 1 || "$in_section" -ne 1 ]]; then
    no B-N3 "散文裡有 ${sends} 個送出動作（其中 ${in_section} 個在那一段裡）——多的那些繞得過三步"
  else
    say "MEASURED 整份散文只有 1 個往外送的動作，而且就在講三步的那一段裡"
    ok B-N3
  fi
fi

[[ "${#SKIPPED[@]}" -eq 0 ]] \
  || say "量不到（不是過）：${SKIPPED[*]}"
exit "$RED"
