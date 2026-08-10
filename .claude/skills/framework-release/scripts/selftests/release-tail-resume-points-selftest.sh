#!/usr/bin/env bash
# release-tail-resume-points-selftest.sh — 量釋出尾段的兩個接不回去的點，以及「走到哪」（DP-501）。
#
# 兩個點都是**一個判斷被拿來答兩件事**：
#   交付紀錄釘的不是 HEAD → 不分「上一趟自己壓的版號」與「有人塞了沒被判定看過的東西」
#   tag 在不在 origin 上   → 同時被拿來決定「要不要建 GitHub release」
#
# 兩件事的答案都在別的系統手上（git、GitHub），所以這裡量的是「它有沒有去問對的那個系統」，
# 而不是「它有沒有記帳」。不打真實 remote：origin 是本機的 bare repo，gh 是 PATH 上的 stub。
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE="$SCRIPTS/spine-release.sh"

EXPECTED=10
RAN=0
FAILED=0
pass() { RAN=$((RAN + 1)); printf 'PASS  %s\n' "$1"; }
fail() { RAN=$((RAN + 1)); FAILED=$((FAILED + 1)); printf 'FAIL  %s\n    %s\n' "$1" "${2:-}"; }

[[ -f "$RELEASE" ]] || { printf 'INCONCLUSIVE：量不到——%s 不在\n' "$RELEASE" >&2; exit 2; }

WORK="$(cd "$(mktemp -d -t polaris-dp501.XXXXXX)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# Description: 造一個帶 bare origin 的 repo，裡面有一張單與一份交付紀錄。
# Args:        $1 = repo 路徑。
# Side effects: 建立 repo、$1.git、issues/ns/TICKET/{index.md,.spine/delivery.json}。
# Outputs:     base commit 的 sha。
build_repo() {
  local repo="$1" bare="$1.git"
  git init -q --bare "$bare"
  mkdir -p "$repo/issues/ns/TICKET/.spine" "$repo/.changeset"
  printf 'a ticket\n' > "$repo/issues/ns/TICKET/index.md"
  printf '1.0.0\n' > "$repo/VERSION"
  printf '# changelog\n' > "$repo/CHANGELOG.md"
  # issues/ 是 versioned-elsewhere：單住在自己的 repo，框架 repo 忽略它。fixture 不照著
  # 這個形狀的話，交付紀錄會被算進壓版那個 commit 的差異裡——而真實世界不會。
  printf 'issues/\n' > "$repo/.gitignore"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.test
  git -C "$repo" config user.name "Self Test"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  git -C "$repo" branch -M main
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push -q -u origin main
  git -C "$repo" rev-parse HEAD
}

# Description: 寫一份釘在指定 head 上的交付紀錄。
# Args: $1 = repo，$2 = head sha。
write_record() {
  python3 - "$1/issues/ns/TICKET/.spine/delivery.json" "$2" <<'RECORD'
import json, sys
json.dump({"schema_version": 2, "producer": "record-delivery-intent.sh",
           "issue": "TICKET", "destination": "template", "head_sha": sys.argv[2],
           "summary": "s", "judged_by": "selftest"}, open(sys.argv[1], "w"))
RECORD
}

# Description: 造一個 gh stub，行為由環境變數決定。
# Args: $1 = stub 目錄，$2 = `gh release view` 的 exit code（0 表示 release 存在）。
make_gh_stub() {
  mkdir -p "$1"
  cat > "$1/gh" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "repo view") echo owner/name ;;
  "release view") exit $2 ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$1/gh"
}

REPO="$WORK/repo"
BASE="$(build_repo "$REPO")"

# ── T-P1：壓完版沒重釘就被切斷，重跑要認得出來 ──────────────────────────────
# 紀錄釘在 BASE，HEAD 是一個只碰壓版那幾條路徑的 commit——那正是被切斷時留下的狀態。
write_record "$REPO" "$BASE"
printf '1.1.0\n' > "$REPO/VERSION"
printf '# changelog\n\n## 1.1.0\n' > "$REPO/CHANGELOG.md"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "chore(release): compress 1.1.0"

out="$(bash "$RELEASE" --repo "$REPO" --issue issues/ns/TICKET --record-state 2>&1)"
if [[ "$out" == "resumable-version-commit" ]]; then
  pass "T-P1 壓完版沒重釘的狀態被認出來，不是一句「對不上」"
else
  fail "T-P1 壓完版沒重釘的狀態被認出來，不是一句「對不上」" "拿到的是：$out"
fi

# 認出來還不夠——認出來之後那一趟真的要去重釘。舊的那一版的問題正是「修好它的那段程式碼
# 排在拒絕的後面」，所以這一條要的是：判斷的結果被消費，而且消費點在壓版那一步之前。
gate_line="$(grep -n 'RESUMED_VERSION_COMMIT=1' "$RELEASE" | head -1 | cut -d: -f1)"
use_line="$(grep -n 'repin_across_version_commit "\$HEAD_SHA"' "$RELEASE" | head -1 | cut -d: -f1)"
version_line="$(grep -n 'step "version"' "$RELEASE" | head -1 | cut -d: -f1)"
if [[ -n "$gate_line" && -n "$use_line" && -n "$version_line" \
      && "$gate_line" -lt "$use_line" && "$use_line" -lt "$version_line" ]]; then
  pass "T-P1 認出來之後真的去重釘，而且排在壓版那一步之前"
else
  fail "T-P1 認出來之後真的去重釘，而且排在壓版那一步之前" \
       "gate=$gate_line use=$use_line version=$version_line"
fi

# ── T-N2：放寬不得擴大 ─────────────────────────────────────────────────────
printf 'more\n' > "$REPO/VERSION"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "another"
out="$(bash "$RELEASE" --repo "$REPO" --issue issues/ns/TICKET --record-state 2>&1)"
if [[ "$out" == stale:* && "$out" == *"不只一個 commit"* ]]; then
  pass "T-N2 中間不只一個 commit 時拒絕，並說出是這一項不成立"
else
  fail "T-N2 中間不只一個 commit 時拒絕，並說出是這一項不成立" "拿到的是：$out"
fi

git -C "$REPO" reset -q --hard "$BASE"
printf '1.1.0\n' > "$REPO/VERSION"
printf 'sneaked in\n' > "$REPO/src.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "chore(release): compress 1.1.0"
out="$(bash "$RELEASE" --repo "$REPO" --issue issues/ns/TICKET --record-state 2>&1)"
if [[ "$out" == stale:* && "$out" == *src.txt* ]]; then
  pass "T-N2 那個 commit 碰到壓版碰不到的檔案時拒絕，並指名是哪一個"
else
  fail "T-N2 那個 commit 碰到壓版碰不到的檔案時拒絕，並指名是哪一個" "拿到的是：$out"
fi

# ── T-P2：tag 與 release 各問各的 ──────────────────────────────────────────
git -C "$REPO" tag -a v9.9.9 -m x
git -C "$REPO" push -q origin v9.9.9

STUB_NO_RELEASE="$WORK/bin-no-release"
make_gh_stub "$STUB_NO_RELEASE" 1
out="$(PATH="$STUB_NO_RELEASE:$PATH" bash "$RELEASE" --repo "$REPO" --tail-plan v9.9.9 2>&1)"
if [[ "$out" == *"tag skip"* && "$out" == *"release create"* ]]; then
  pass "T-P2 tag 已經在 origin 上而 release 不在時，release 仍然要建"
else
  fail "T-P2 tag 已經在 origin 上而 release 不在時，release 仍然要建" "拿到的是：${out//$'\n'/ / }"
fi

STUB_HAS_RELEASE="$WORK/bin-has-release"
make_gh_stub "$STUB_HAS_RELEASE" 0
out="$(PATH="$STUB_HAS_RELEASE:$PATH" bash "$RELEASE" --repo "$REPO" --tail-plan v8.8.8 2>&1)"
if [[ "$out" == *"tag push"* && "$out" == *"release skip"* ]]; then
  pass "T-P2 反過來也分得開：tag 還沒推、release 已經在"
else
  fail "T-P2 反過來也分得開：tag 還沒推、release 已經在" "拿到的是：${out//$'\n'/ / }"
fi

# ── T-P3：說得出走到哪，問不到的要說出問不到 ───────────────────────────────
git -C "$REPO" reset -q --hard "$BASE"
write_record "$REPO" "$BASE"
STUB_BROKEN="$WORK/bin-broken"
mkdir -p "$STUB_BROKEN"
printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB_BROKEN/gh"
chmod +x "$STUB_BROKEN/gh"
status_out="$(PATH="$STUB_BROKEN:$PATH" bash "$RELEASE" --repo "$REPO" --issue issues/ns/TICKET --status 2>&1)"
missing=""
for row in 交付紀錄 版號 推分支 促進main 同步template tag release 釋出紀錄 本機收尾; do
  [[ "$status_out" == *"${row}："* ]] || missing="$missing ${row}"
done
if [[ -z "$missing" ]]; then
  pass "T-P3 九個步驟每一個都有一行說它做到哪"
else
  fail "T-P3 九個步驟每一個都有一行說它做到哪" "少了：$missing"
fi

if [[ "$status_out" == *"release：問不到"* ]]; then
  pass "T-P3 問不到的那一項說出它問不到，不是省略、也不是猜一個"
else
  fail "T-P3 問不到的那一項說出它問不到，不是省略、也不是猜一個" \
       "$(printf '%s' "$status_out" | grep -F 'release：' | head -1)"
fi

# ── T-N1：不看任何一份本機的進度帳 ─────────────────────────────────────────
# 種一份宣稱「全部做完了」的進度檔，再跑一次。輸出必須一個字都不變——它要是讀了那份帳，
# 這裡就會看到不一樣的答案。
cat > "$REPO/issues/ns/TICKET/.spine/release-progress.json" <<'PROGRESS'
{"promoted": true, "tagged": true, "released": true, "synced": true, "landed": true}
PROGRESS
again="$(PATH="$STUB_BROKEN:$PATH" bash "$RELEASE" --repo "$REPO" --issue issues/ns/TICKET --status 2>&1)"
# 「兩次一樣」單獨拿出來會空過：兩次都吐同一句「不認得的參數」也一樣。所以連同「它真的
# 印出了那張表」一起要求。
if [[ "$again" == "$status_out" && "$again" == *"交付紀錄："* ]]; then
  pass "T-N1 種一份宣稱全部做完的進度檔，回答一個字都沒變"
else
  fail "T-N1 種一份宣稱全部做完的進度檔，回答一個字都沒變" \
       "$(diff <(printf '%s' "$status_out") <(printf '%s' "$again") | head -4)"
fi

# ── T-N3：只讀就是不寫 ─────────────────────────────────────────────────────
rm -f "$REPO/issues/ns/TICKET/.spine/release-progress.json"
before_head="$(git -C "$REPO" rev-parse HEAD)"
before_tree="$(cd "$REPO" && find . -path ./.git -prune -o -type f -print | sort | xargs shasum 2>/dev/null | shasum)"
before_refs="$(git -C "$REPO" show-ref | shasum)"
ran_out="$(PATH="$STUB_BROKEN:$PATH" bash "$RELEASE" --repo "$REPO" --issue issues/ns/TICKET --status 2>&1)"
ran_rc=$?
after_head="$(git -C "$REPO" rev-parse HEAD)"
after_tree="$(cd "$REPO" && find . -path ./.git -prune -o -type f -print | sort | xargs shasum 2>/dev/null | shasum)"
after_refs="$(git -C "$REPO" show-ref | shasum)"
# 「什麼都沒動」在一個根本沒跑起來的東西上也成立，所以要求它真的跑完並印出那張表。
if [[ "$ran_rc" -eq 0 && "$ran_out" == *"交付紀錄："* \
      && "$before_head" == "$after_head" && "$before_tree" == "$after_tree" \
      && "$before_refs" == "$after_refs" ]]; then
  pass "T-N3 只讀模式真的跑完了，而 HEAD、工作樹與 refs 全都沒動"
else
  fail "T-N3 只讀模式真的跑完了，而 HEAD、工作樹與 refs 全都沒動" \
       "rc=$ran_rc 有表嗎：$([[ "$ran_out" == *"交付紀錄："* ]] && echo yes || echo no) refs 變了嗎：$([[ "$before_refs" == "$after_refs" ]] && echo no || echo yes)"
fi

printf -- '---\n'
if [[ "$RAN" -ne "$EXPECTED" ]]; then
  printf 'INCONCLUSIVE：預期 %s 條，實際跑了 %s 條——量不到不是通過。\n' "$EXPECTED" "$RAN" >&2
  exit 2
fi
printf 'release tail resume points：%s 條，紅 %s 條。\n' "$EXPECTED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
