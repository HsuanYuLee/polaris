#!/usr/bin/env bash
# workspace-changeset-visibility-selftest.sh — DP-559 的六條斷言各量一次。
#
# 兩件事疊起來會產生一個看 diff 看不出來的、不可逆的後果：`destination: workspace` 的
# 釋出不壓版，所以它留下的 changeset 沒有人會消化；而 `.changeset/` 以前不在 template-leak
# 的掃描範圍內。於是一份帶著 live 公司樣式的 changeset 在那裡完全安全，被下一張
# template-bound 的單壓進 CHANGELOG.md 的那一刻才變紅——而 CHANGELOG.md 會被同步到一個
# 公開的 repo，紅的還是別人的 commit。
#
# 不打真實 remote：origin 是本機的 bare repo。掃描那三條在一棵臨時的工作區上跑。
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE="$SCRIPTS/spine-release.sh"
SCAN="$SCRIPTS/scan-template-leaks.sh"

RAN=0
FAILED=0
pass() { RAN=$((RAN + 1)); printf 'PASS  %s\n' "$1"; }
fail() { RAN=$((RAN + 1)); FAILED=$((FAILED + 1)); printf 'FAIL  %s\n    %s\n' "$1" "${2:-}"; }

for f in "$RELEASE" "$SCAN"; do
  [[ -f "$f" ]] || { printf 'INCONCLUSIVE：量不到——%s 不在\n' "$f" >&2; exit 2; }
done

WORK="$(cd "$(mktemp -d -t polaris-dp559.XXXXXX)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# Description: 造一個帶 bare origin 的 repo，裡面有一張單與一份交付紀錄。
# Args:        $1 = repo 路徑，$2 = destination。
# Outputs:     base commit 的 sha。
build_repo() {
  local repo="$1" bare="$1.git"
  git init -q --bare "$bare"
  mkdir -p "$repo/issues/ns/TICKET/.spine" "$repo/.changeset"
  printf 'a ticket\n' > "$repo/issues/ns/TICKET/index.md"
  printf '1.0.0\n' > "$repo/VERSION"
  printf '# changelog\n' > "$repo/CHANGELOG.md"
  printf 'issues/\n' > "$repo/.gitignore"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.test
  git -C "$repo" config user.name "Self Test"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  git -C "$repo" branch -M main
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push -q -u origin main
  python3 - "$repo/issues/ns/TICKET/.spine/delivery.json" \
            "$(git -C "$repo" rev-parse HEAD)" "$2" <<'RECORD'
import json, sys
json.dump({"schema_version": 2, "producer": "record-delivery-intent.sh",
           "issue": "TICKET", "destination": sys.argv[3], "head_sha": sys.argv[2],
           "summary": "s", "judged_by": "selftest"}, open(sys.argv[1], "w"))
RECORD
}

# Description: 在 repo 的 .changeset/ 底下放 N 份 changeset。
seed_changesets() {
  local repo="$1" n="$2" i
  for ((i = 1; i <= n; i++)); do
    printf -- '---\n"pkg": patch\n---\n\n第 %s 份\n' "$i" > "$repo/.changeset/c$i.md"
  done
}

# Description: 問一次「走到哪了」，把整段輸出交回來。它只讀：不寫、不推、不建立任何東西，
#              也不 fetch。版號那一行是 `say` 印的，走 stderr。
preview() { bash "$RELEASE" --repo "$1" --issue issues/ns/TICKET --status 2>&1; }

# ── A-P2：workspace ＋ 0 份，那一行要說得出「沒有」 ──────────────────────────
WS0="$WORK/ws0"; build_repo "$WS0" workspace
line="$(preview "$WS0" | grep '版號' | head -1)"
if [[ "$line" == *"沒有待處理的 changeset"* ]]; then
  pass "A-P2 沒有待處理的 changeset 時，那一行說得出「沒有」"
else
  fail "A-P2 沒有待處理的 changeset 時，那一行說得出「沒有」" "拿到的是：$line"
fi

# ── A-P1：workspace ＋ 1 份／多份，都要說出份數與去向 ────────────────────────
ok=1; detail=""
for n in 1 3; do
  repo="$WORK/ws$n"; build_repo "$repo" workspace; seed_changesets "$repo" "$n"
  line="$(preview "$repo" | grep '版號' | head -1)"
  if [[ "$line" != *"${n} 份待處理"* || "$line" != *"CHANGELOG.md"* ]]; then
    ok=0; detail="$detail | ${n} 份時拿到：$line"
  fi
done
if [[ "$ok" -eq 1 ]]; then
  pass "A-P1 有待處理的 changeset 時說出份數與去向（1 份與 3 份各量一次）"
else
  fail "A-P1 有待處理的 changeset 時說出份數與去向（1 份與 3 份各量一次）" "$detail"
fi

# ── A-N1：說出來不擋人 ──────────────────────────────────────────────────────
preview "$WORK/ws3" >/dev/null 2>&1
rc_with=$?
preview "$WS0" >/dev/null 2>&1
rc_without=$?
if [[ "$rc_with" -eq "$rc_without" ]]; then
  pass "A-N1 待處理的 changeset 不改變離場碼（有 ${rc_with}，沒有 ${rc_without}）"
else
  fail "A-N1 待處理的 changeset 不改變離場碼" "有=$rc_with 沒有=$rc_without"
fi

# ── A-N2：template 那條路徑說的話沒有變 ─────────────────────────────────────
TP="$WORK/tp"; build_repo "$TP" template; seed_changesets "$TP" 2
line="$(preview "$TP" | grep '版號' | head -1)"
TP0="$WORK/tp0"; build_repo "$TP0" template
line0="$(preview "$TP0" | grep '版號' | head -1)"
if [[ "$line" == *"還沒壓"* && "$line" == *"2 份 changeset 待處理"* \
      && "$line0" == *"壓過了"* && "$line0" == *"沒有待處理的 changeset"* ]]; then
  pass "A-N2 template 那條路徑的兩種輸入說的話跟改動前一樣"
else
  fail "A-N2 template 那條路徑的兩種輸入說的話跟改動前一樣" "有=$line ／ 沒有=$line0"
fi

# ── A-P3／A-N3：掃描看不看得到 .changeset/ 的正文 ───────────────────────────
# 三種樣式各一份，而且三個字串**互不包含**：公司代號、JIRA 專案號、JIRA 站台網域。
# 都用同一個字根的話，三次量的其實是同一條樣式，而那看起來跟三種都測過一模一樣。
# 樣式由工作區底下 {公司}/workspace-config.yaml 推出來，所以 fixture 自己帶一份，
# 不借用這台機器上的那一份。
scan_tree() {
  local tree="$1"
  mkdir -p "$tree/.changeset" "$tree/.claude/skills" "$tree/globex"
  cat > "$tree/globex/workspace-config.yaml" <<'CONF'
jira:
  instance: zeta.atlassian.net
  projects:
    - key: ACME
CONF
  printf 'README\n' > "$tree/.changeset/README.md"
  printf '{}\n' > "$tree/.changeset/config.json"
  git -C "$tree" init -q
  git -C "$tree" config user.email selftest@example.test
  git -C "$tree" config user.name "Self Test"
}
hits_of() { bash "$SCAN" --workspace "$1" 2>&1 | grep -E '^hits: ' | head -1 | cut -d' ' -f2; }

CLEAN="$WORK/clean"; scan_tree "$CLEAN"
clean_hits="$(hits_of "$CLEAN")"
if [[ "$clean_hits" == "0" ]]; then
  pass "A-N3 .changeset/ 裡只有樣板與設定檔時，命中數是 0"
else
  fail "A-N3 .changeset/ 裡只有樣板與設定檔時，命中數是 0" "拿到的是：${clean_hits:-量不到}"
fi

ok=1; detail=""
for shape in globex ACME-1234 zeta.atlassian.net; do
  DIRTY="$WORK/dirty-$shape"; scan_tree "$DIRTY"
  printf -- '---\n"pkg": patch\n---\n\n%s 那件事\n' "$shape" > "$DIRTY/.changeset/leak.md"
  h="$(hits_of "$DIRTY")"
  if [[ -z "$h" || "$h" == "0" ]]; then
    ok=0; detail="${detail} | ${shape} 命中 ${h:-量不到}"
  fi
done
if [[ "$ok" -eq 1 ]]; then
  pass "A-P3 changeset 還在 .changeset/ 就被掃到（公司代號／專案號／站台網域各一次）"
else
  fail "A-P3 changeset 還在 .changeset/ 就被掃到（公司代號／專案號／站台網域各一次）" "$detail"
fi

printf 'WORKSPACE-CHANGESET-VISIBILITY %s/%s 條過\n' "$((RAN - FAILED))" "$RAN"
[[ "$FAILED" -eq 0 ]]
