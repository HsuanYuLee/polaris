#!/usr/bin/env bash
# Selftest for gate-dangling-declarations.sh —— 每個 case 先做出一個已知的落差再看它抓不抓得到。

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/gate-dangling-declarations.sh"
tmp="$(mktemp -d)"
trap 'status=$?; rm -rf "$tmp"; exit $status' EXIT

pass=0
fail=0

# fixture：一個 repo，一個活著的腳本、一個 mise 任務、一個 hook 註冊。
reset_fixture() {
  rm -rf "$tmp/repo"
  mkdir -p "$tmp/repo/.claude/hooks" "$tmp/repo/tools"
  echo 'echo hi' > "$tmp/repo/tools/live.sh"
  echo 'echo hook' > "$tmp/repo/.claude/hooks/live-hook.sh"
  cat > "$tmp/repo/mise.toml" <<'EOF'
[tasks.alive]
description = "points at something that exists"
run = "bash tools/live.sh"
EOF
  cat > "$tmp/repo/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/live-hook.sh\"" }
        ]
      }
    ]
  }
}
EOF
  git -C "$tmp/repo" init -q
  git -C "$tmp/repo" config user.email t@t; git -C "$tmp/repo" config user.name t
  git -C "$tmp/repo" add -A; git -C "$tmp/repo" commit -qm init
}

check() {
  local name="$1" want="$2" needle="${3:-}"
  local out rc
  out="$(bash "$SCRIPT" --repo "$tmp/repo" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" != "$want" ]]; then
    echo "FAIL $name: 期待 exit ${want}，實際 ${rc}"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  if [[ -n "$needle" && "$out" != *"$needle"* ]]; then
    echo "FAIL $name: 訊息裡沒有 '${needle}'"; echo "$out" | sed 's/^/     /'; fail=$((fail+1)); return
  fi
  echo "PASS $name"; pass=$((pass+1))
}

reset_fixture
check "全部指得到時回 0" 0 "DECLARATIONS-LIVE 2"

# 這支閘存在的那一次：檔案被刪，宣告留著。
reset_fixture
rm "$tmp/repo/tools/live.sh"
check "mise 任務指向被刪的檔案時回 1" 1 "mise.toml"

reset_fixture
rm "$tmp/repo/.claude/hooks/live-hook.sh"
check "hook 註冊指向被刪的檔案時回 1" 1 "live-hook.sh"

# 沒有 mise.toml / settings.json 不是錯，只是沒有東西可掃。
reset_fixture
rm "$tmp/repo/mise.toml" "$tmp/repo/.claude/settings.json"
check "兩個宣告面都不存在時回 0" 0 "DECLARATIONS-LIVE 0"

# 展不開的路徑不猜，但要數出來——一個不被判定的第三態如果安靜，下次就會有人以為全掃過了。
reset_fixture
cat >> "$tmp/repo/mise.toml" <<'EOF'

[tasks.interpolated]
description = "path built at runtime"
run = "bash $SOME_DIR/whatever.sh"
EOF
check "帶變數的路徑不判定但有數出來" 0 "解不開的帶變數路徑 1 個"

# 散文提到一個不存在的檔名不算宣告——把敘述算進來這支閘就沒人敢看了。
reset_fixture
mkdir -p "$tmp/repo/docs"
echo 'run `bash tools/deleted-long-ago.sh` if you are nostalgic' > "$tmp/repo/docs/notes.md"
git -C "$tmp/repo" add -A >/dev/null; git -C "$tmp/repo" commit -qm docs >/dev/null
check "散文裡的檔名不算宣告" 0 "DECLARATIONS-LIVE 2"

echo "gate-dangling-declarations selftest: PASS=$pass FAIL=$fail"
[[ "$fail" == 0 ]]
