#!/usr/bin/env bash
# Selftest for gate-source-destination.sh 讀 sync-to-polaris.sh 的「不同步」宣告這條線。
#
# 這條線靠一行註解維繫，而一條靠註解維繫的關係跟沒有那條關係的差別只有它看起來很完整。
# 所以這一支守三件事：宣告在不在、宣告旁邊那段行為在不在、以及閘有沒有真的照它判。
#
# 為什麼要有這條線（DP-525）：那道閘只認一個很小的安全子集，而 `.changeset/` 不在裡面。
# 於是 DP-523 與 DP-517 兩張只改 `.changeset/` 的單被判紅，兩次的處理都是回頭把
# `destination` 改成 `template`——那是一個假紅逼出來的假宣告。
#
# 測法是造假樹：閘的判定全部相對於 --repo，所以一棵有 git、有假 sync 腳本、有假單的
# 目錄就夠了。不碰 ~/polaris、不連網、不需要真的公司設定。

set -euo pipefail

# macOS 的 sed 在 C locale 下遇到多位元組字元會回 "illegal byte sequence"，而這一支比對的
# 輸出裡有中文。
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SCRIPTS/gate-source-destination.sh"
SYNC="$SCRIPTS/sync-to-polaris.sh"
REAL_ROOT="$(cd "$SCRIPTS/../../../.." && pwd)"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; echo "  ---- 實際 ----"; sed 's/^/  /' <<< "${2:-}"; }

SYNC_REL=".claude/skills/framework-release/scripts/sync-to-polaris.sh"

# Description: 造一棵假工作區。$1 = 放哪裡，$2 = 假 sync 腳本要不要帶那行宣告
# （true／false）。單本身一定有 loop-state.json 與 destination: workspace，因為這一支要
# 問的是位置怎麼判，不是那兩個前置條件。
build_tree() {
  local root="$1" declared="$2"
  rm -rf "$root"
  mkdir -p "$root/$(dirname "$SYNC_REL")" "$root/issues/ns/T/.spine" "$root/.changeset"
  {
    echo '#!/usr/bin/env bash'
    echo '# 假的同步腳本，只帶這一支要問的那一件事。'
    if [[ "$declared" == true ]]; then
      echo '# <!-- POLARIS-NOT-SYNCED: .changeset/ — 本 repo 自己的發版設定 -->'
    fi
    echo 'true'
  } > "$root/$SYNC_REL"
  printf -- '---\ndestination: workspace\n---\n\n# T\n' > "$root/issues/ns/T/index.md"
  echo '{}' > "$root/issues/ns/T/.spine/loop-state.json"
  git init -q "$root"
  git -C "$root" config user.email t@t
  git -C "$root" config user.name t
}

# Description: 對假樹跑一次閘，離場碼原樣傳回去。$1 = 樹根，其餘 = 要判的路徑。
run_gate() {
  local root="$1"; shift
  local args=(); local p
  for p in "$@"; do args+=(--changed "$p"); done
  bash "$GATE" --repo "$root" --issue issues/ns/T "${args[@]}" 2>&1
}

build_tree "$tmp/declared" true
build_tree "$tmp/bare" false

# ── N-P1 閘去問已經有答案的那一份 ───────────────────────────────────────────
out="$(run_gate "$tmp/declared" .changeset/foo.md)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"$SYNC_REL 宣告 .changeset/ 不同步"* ]]; then
  ok '只改 .changeset/ 的單判綠，而且理由指名那份宣告'
else
  bad '只改 .changeset/ 的單判綠，而且理由指名那份宣告' "rc=$rc
$out"
fi

# ── N-P2 那份宣告是唯一的答案 ───────────────────────────────────────────────
# 同一棵樹、同一個檔案，差別只有那一行宣告在不在。閘裡若還藏著第二份 .changeset 清單，
# 這一條會是綠的——而那正是要擋的形狀。
out_bare="$(run_gate "$tmp/bare" .changeset/foo.md)" && rc_bare=0 || rc_bare=$?
if [[ "$rc_bare" -eq 1 && "$out_bare" == *"POLARIS_SOURCE_DESTINATION_ESCAPE"* ]]; then
  ok '把宣告拿掉，同一張單就判紅——閘裡沒有第二份清單'
else
  bad '把宣告拿掉，同一張單就判紅——閘裡沒有第二份清單' "rc=$rc_bare
$out_bare"
fi

# ── N-P2（續）閘的原始碼裡沒有寫死的 .changeset ─────────────────────────────
# 上一條是行為，這一條是原始碼。行為那一條在「閘寫死了 .changeset 但假樹剛好也宣告了」
# 的世界裡仍然會綠，所以兩條都要。註解裡講得到它（那是在說為什麼有這條線），程式碼不行。
hardcoded="$(grep -nE '^[^#]*["'"'"']\.changeset' "$GATE" || true)"
if [[ -z "$hardcoded" ]]; then
  ok '閘的程式碼裡沒有寫死的 .changeset 路徑'
else
  bad '閘的程式碼裡沒有寫死的 .changeset 路徑' "$hardcoded"
fi

# ── N-P3 宣告與它描述的行為綁在一起 ─────────────────────────────────────────
# 真的那支腳本要同時有兩樣東西：那行宣告，以及把模板端 .changeset/ 移除的那段程式碼。
# 少了宣告，閘會開始判假紅；少了那段程式碼，宣告就變成一句沒有人在執行的話。
decl="$(grep -c 'POLARIS-NOT-SYNCED:' "$SYNC" || true)"
prune="$(grep -c 'rm -rf "$POLARIS_DIR/.changeset"' "$SYNC" || true)"
if [[ "$decl" -ge 1 && "$prune" -ge 1 ]]; then
  ok "真的那支同步腳本兩樣都在（宣告 ${decl} 行、移除 ${prune} 行）"
else
  bad '真的那支同步腳本兩樣都在' "宣告=$decl 移除=$prune"
fi

# ── N-P3（續）閘找的路徑就是那支腳本真的在的地方 ────────────────────────────
if [[ -f "$REAL_ROOT/$SYNC_REL" ]] && grep -q "$SYNC_REL" "$GATE"; then
  ok '閘指名的路徑上真的有那支腳本'
else
  bad '閘指名的路徑上真的有那支腳本' "root=$REAL_ROOT
$(grep -n 'SYNC_SCRIPT = ' "$GATE" || true)"
fi

# ── N-N2 .changeset/ 不進同步的複製清單 ─────────────────────────────────────
# 這張單改的是「閘怎麼判」，不是「什麼會被複製出去」。把 .changeset/ 加進複製清單也能讓
# 那道閘不再判紅——而那是往完全相反的方向解，每個採用這套框架的 workspace 都會被塞進一批
# 不屬於它的待壓版紀錄。
copies="$(grep -nE 'copy_(file|dir|dir_filtered)[^#]*\.changeset' "$SYNC" || true)"
if [[ -z "$copies" && "$prune" -ge 1 ]]; then
  ok '.changeset/ 沒有出現在任何一條複製指令上，而移除它的那段還在'
else
  bad '.changeset/ 沒有出現在任何一條複製指令上，而移除它的那段還在' "複製=$copies 移除=$prune"
fi

# ── N-N1 安全子集不因此變寬 ─────────────────────────────────────────────────
for victim in .claude/skills/refinement/SKILL.md .claude/rules/style-and-language.md README.md; do
  out_v="$(run_gate "$tmp/declared" "$victim")" && rc_v=0 || rc_v=$?
  if [[ "$rc_v" -eq 1 && "$out_v" == *"$victim"* ]]; then
    ok "會出去的位置仍然判紅：$victim"
  else
    bad "會出去的位置仍然判紅：$victim" "rc=$rc_v
$out_v"
  fi
done

# ── N-N1（續）一綠一紅同時出現時，紅的那個說了算 ────────────────────────────
out_mix="$(run_gate "$tmp/declared" .changeset/foo.md README.md)" && rc_mix=0 || rc_mix=$?
if [[ "$rc_mix" -eq 1 && "$out_mix" == *"留得住 1、認不出來 1"* ]]; then
  ok '一個宣告過的加一個沒宣告的 → 判紅，而且兩邊都算得出來'
else
  bad '一個宣告過的加一個沒宣告的 → 判紅，而且兩邊都算得出來' "rc=$rc_mix
$out_mix"
fi

# ── N-N3 讀不到宣告不等於放行，而且不安靜 ───────────────────────────────────
rm -f "$tmp/declared/$SYNC_REL"
out_gone="$(run_gate "$tmp/declared" .changeset/foo.md)" && rc_gone=0 || rc_gone=$?
if [[ "$rc_gone" -eq 1 && "$out_gone" == *"讀不到"* && "$out_gone" == *"$SYNC_REL"* ]]; then
  ok '那支腳本整個不在時判紅，而且說出這一次沒讀到宣告'
else
  bad '那支腳本整個不在時判紅，而且說出這一次沒讀到宣告' "rc=$rc_gone
$out_gone"
fi

# ── 讀得到的時候也要說出讀到幾條 ────────────────────────────────────────────
# 「讀到 0 條」與「讀不到」是兩件事，而它們在判定上長得一樣（都判紅）。輸出上要分得出來，
# 不然下一次沒有人知道那道閘是失去了宣告還是失去了那個檔案。
out_count="$(run_gate "$tmp/bare" README.md)" && : || true
if [[ "$out_count" == *"0 條宣告"* ]]; then
  ok '腳本在、宣告是 0 條時說出「0 條」，跟「讀不到」分得開'
else
  bad '腳本在、宣告是 0 條時說出「0 條」，跟「讀不到」分得開' "$out_count"
fi

echo "gate-source-destination declaration selftest: PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
