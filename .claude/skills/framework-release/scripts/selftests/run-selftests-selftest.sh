#!/usr/bin/env bash
# Selftest for run-selftests.sh —— 兩件事：範圍算得對，以及**它不會弄壞叫它的那個 repo**。
#
# 第二件不是假設性的。2026-08-10 把 selftest 接上 pre-commit 的第一次實跑，git 給 hook 的
# GIT_DIR 洩進了每一支 selftest，而 selftest 幾乎都會 `git init` 一棵 fixture 樹——那些
# 指令照著 GIT_DIR 走，於是把工作區的索引從 499 個檔清成 2 個，並且把 `core.bare=true`
# 寫進真的 .git/config。一支跑測試的腳本能改壞被測的 repo，那比它漏掉一個 case 嚴重。

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/run-selftests.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

# fixture：兩支 skill，各帶一支會過的 selftest；其中一支的 selftest 刻意像真的那樣
# `git init` 一棵臨時樹——洩漏發生的時候，受害的就是這種。
reset_fixture() {
  rm -rf "$tmp/repo"
  mkdir -p "$tmp/repo/.claude/skills/alpha/selftests" \
           "$tmp/repo/.claude/skills/beta/selftests"
  echo '# alpha' > "$tmp/repo/.claude/skills/alpha/SKILL.md"
  echo '# beta'  > "$tmp/repo/.claude/skills/beta/SKILL.md"
  cat > "$tmp/repo/.claude/skills/alpha/selftests/alpha-selftest.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# 跟真的 selftest 一樣：建一棵自己的 fixture 樹。GIT_DIR 洩進來的話，這幾行動到的是別人。
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/thing"; echo x > "$work/thing/f.txt"
git -C "$work" init -q
git -C "$work" config user.email t@t; git -C "$work" config user.name t
git -C "$work" add -A; git -C "$work" commit -qm init
EOF
  cat > "$tmp/repo/.claude/skills/beta/selftests/beta-selftest.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  git -C "$tmp/repo" init -q
  git -C "$tmp/repo" config user.email t@t; git -C "$tmp/repo" config user.name t
  git -C "$tmp/repo" add -A; git -C "$tmp/repo" commit -qm init
}

check() {
  local name="$1" want="$2" needle="$3"; shift 3
  local out rc
  out="$(bash "$SCRIPT" --repo "$tmp/repo" "$@" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" != "$want" ]]; then
    echo "FAIL $name: 期待 exit ${want}，實際 ${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    echo "FAIL $name: 訊息裡沒有 '${needle}'"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  echo "PASS $name"; pass=$((pass+1))
}

# ── 最重要的一條：帶著 hook 的環境跑，被測的 repo 不能被動到 ───────
reset_fixture
before_index="$(git -C "$tmp/repo" ls-files | wc -l | tr -d ' ')"
before_bare="$(git -C "$tmp/repo" config --local --get core.bare || echo none)"
# 只設 GIT_DIR，不設 GIT_WORK_TREE——那才是 git 給 hook 的形狀，而且正是危險的那一種：
# 工作樹變成「當下的 cwd」，於是 `git add -A` 會拿 fixture 那棵臨時樹去覆蓋真的索引。
GIT_DIR="$tmp/repo/.git" bash "$SCRIPT" --repo "$tmp/repo" --all >/dev/null 2>&1 || true
after_index="$(git -C "$tmp/repo" ls-files | wc -l | tr -d ' ')"
after_bare="$(git -C "$tmp/repo" config --local --get core.bare || echo none)"
if [[ "$before_index" == "$after_index" && "$before_bare" == "$after_bare" ]]; then
  echo "PASS 帶著 hook 的 GIT_DIR 跑，被測 repo 不變"; pass=$((pass+1))
else
  echo "FAIL 帶著 hook 的 GIT_DIR 跑，被測 repo 不變：索引 ${before_index}→${after_index}、core.bare ${before_bare}→${after_bare}"
  fail=$((fail+1))
fi

# ── 範圍：動到哪支就跑哪支 ─────────────────────────────────────────
reset_fixture
check "--all 兩支都跑" 0 "跑了 2 支" --all
check "只動到 alpha 就只跑 alpha" 0 "跑了 1 支" --changed .claude/skills/alpha/SKILL.md
check "動到兩支就跑兩支" 0 "跑了 2 支" \
  --changed .claude/skills/alpha/SKILL.md .claude/skills/beta/SKILL.md
check "改動不在任何 skill 底下就沒得跑" 0 "沒有 selftest 要跑" --changed README.md

# ── 一支紅的要被指名 ───────────────────────────────────────────────
reset_fixture
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/repo/.claude/skills/beta/selftests/beta-selftest.sh"
check "紅的那支會被指名" 1 "beta-selftest.sh" --all

# ── 量不到不是通過 ─────────────────────────────────────────────────
reset_fixture
rm -rf "$tmp/repo/.claude/skills"
check "skill 目錄不存在時 exit 2" 2 "量不到" --all

echo "run-selftests selftest: PASS=$pass FAIL=$fail"
[[ "$fail" == 0 ]]
