#!/usr/bin/env bash
# 裝 / 移除 / 檢查這個 repo 的 git hook。
#
# 只有兩個 hook，各擋一件「push 或 commit 出去就收不回來」的事。判準與理由寫在
# 同目錄 run-gates.sh 與 run-selftests.sh 的檔頭；這裡只負責把它們接上 git。
#
# Usage:
#   bash .claude/skills/framework-release/scripts/install-git-hooks.sh            # 裝
#   bash .claude/skills/framework-release/scripts/install-git-hooks.sh --remove   # 移除
#   bash .claude/skills/framework-release/scripts/install-git-hooks.sh --status   # 看狀態

set -euo pipefail

MODE="install"
case "${1:-}" in
  --remove) MODE="remove" ;;
  --status) MODE="status" ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; sed -n '8,11p' "$0" >&2; exit 2 ;;
esac

# 不能寫成「工作區根目錄 ＋ `/.git/hooks`」：linked worktree 的 `.git` 是一個**檔案**，那條路徑不
# 存在，於是從 worktree 裝 hook 會炸在寫檔那一行。hook 目錄本來就只有一份，問 git 要。
HOOK_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/hooks"
MARKER="# [polaris-git-hooks]"

# Description: 只在檔案是我們裝的（帶 marker）時才刪，別人手寫的 hook 不動。
# Args: $1 = hook 名（pre-commit / pre-push）
remove_hook() {
  local f="$HOOK_DIR/$1"
  if [[ -f "$f" ]] && grep -qF "$MARKER" "$f"; then
    rm -f "$f"; echo "removed: $1"
  fi
}

case "$MODE" in
  status)
    for h in pre-commit pre-push; do
      f="$HOOK_DIR/$h"
      if [[ -f "$f" ]] && grep -qF "$MARKER" "$f"; then echo "installed: $h"
      elif [[ -f "$f" ]]; then echo "foreign:   ${h}（不是我們裝的，沒有動它）"
      else echo "missing:   $h"; fi
    done
    exit 0
    ;;
  remove)
    remove_hook pre-commit; remove_hook pre-push; exit 0
    ;;
esac

mkdir -p "$HOOK_DIR"

for h in pre-commit pre-push; do
  f="$HOOK_DIR/$h"
  if [[ -f "$f" ]] && ! grep -qF "$MARKER" "$f"; then
    echo "$h 已存在而且不是我們裝的，跳過不覆蓋：$f" >&2
    continue
  fi
done

cat > "$HOOK_DIR/pre-commit" <<'EOF'
#!/usr/bin/env bash
# [polaris-git-hooks]
# 由 .claude/skills/framework-release/scripts/install-git-hooks.sh 產生，不要直接改。
set -euo pipefail
# 見 pre-push 的同一行：hook 環境裡有 GIT_DIR，`--show-toplevel` 會回工作目錄而不是 repo 根。
REPO_ROOT="$(env -u GIT_DIR -u GIT_WORK_TREE git rev-parse --show-toplevel)"

# 資料夾模式的 company skill 需要深度一的 symlink 才叫得到。加了 skill 的人不需要
# 知道這件事，這裡替他補上並 stage；撐不住 symlink 的環境會明講，不會靜默放行。
if [[ -x "$REPO_ROOT/.claude/skills/framework-release/scripts/sync-company-skill-links.sh" ]]; then
  bash "$REPO_ROOT/.claude/skills/framework-release/scripts/sync-company-skill-links.sh" --stage >/dev/null || {
    bash "$REPO_ROOT/.claude/skills/framework-release/scripts/sync-company-skill-links.sh" --check
    exit 1
  }
fi

# 個人的規劃內容不該進這個 repo——它會被同步到公開的 template。
if [[ -x "$REPO_ROOT/.claude/skills/framework-release/scripts/gate-no-tracked-specs.sh" ]]; then
  bash "$REPO_ROOT/.claude/skills/framework-release/scripts/gate-no-tracked-specs.sh" --repo "$REPO_ROOT"
fi

# 八道掃全樹的閘，合計 1.3 秒。擋在這裡的話，過不了閘的 commit 從來不存在；擋在 push
# 的話它已經在歷史裡，修要改寫歷史。
bash "$REPO_ROOT/.claude/skills/framework-release/scripts/run-gates.sh" --repo "$REPO_ROOT"

# selftest 全套 68 秒，每個 commit 跑它會被學會跳過。所以這裡只跑這次改動動到的那幾支
# skill 的——全套留給 push。
bash "$REPO_ROOT/.claude/skills/framework-release/scripts/run-selftests.sh" --repo "$REPO_ROOT" --staged
EOF

cat > "$HOOK_DIR/pre-push" <<'EOF'
#!/usr/bin/env bash
# [polaris-git-hooks]
# 由 .claude/skills/framework-release/scripts/install-git-hooks.sh 產生，不要直接改。
set -euo pipefail
# git 跑 hook 時環境裡已經有 GIT_DIR，而 `rev-parse --show-toplevel` 在那個情況下回的是
# 當下的工作目錄。這裡拿掉它再問，並且把答案往下傳——被呼叫的那支不該自己再解一次根。
REPO_ROOT="$(env -u GIT_DIR -u GIT_WORK_TREE git rev-parse --show-toplevel)"

# 刪 branch 與推 tag 不帶內容，不必過內容閘。
while read -r _local_ref local_sha _remote_ref _remote_sha; do
  [[ "$local_sha" == 0000000000000000000000000000000000000000 ]] && exit 0
done || true

bash "$REPO_ROOT/.claude/skills/framework-release/scripts/run-gates.sh" --repo "$REPO_ROOT"

# 這裡刻意**不**跑全套 selftest。全套 87.7 秒，掛在每次推送上會把一個很短的動作變成一個
# 很長的，然後被關掉——而一個被關掉的檢查比沒有檢查糟，因為它看起來還在。commit 那一站
# 已經跑過這次動到的 skill；「沒動到的那些還是綠的嗎」由釋出尾段問，那本來就是慢的一站。
EOF

chmod +x "$HOOK_DIR/pre-commit" "$HOOK_DIR/pre-push"
echo "installed: pre-commit, pre-push"
