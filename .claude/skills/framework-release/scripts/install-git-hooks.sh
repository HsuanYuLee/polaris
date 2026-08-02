#!/usr/bin/env bash
# 裝 / 移除 / 檢查這個 repo 的 git hook。
#
# 只有兩個 hook，各擋一件「push 或 commit 出去就收不回來」的事。判準與理由寫在
# 同目錄 pre-push-quality-gate.sh 的檔頭；這裡只負責把它接上 git。
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

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_DIR="$REPO_ROOT/.git/hooks"
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
REPO_ROOT="$(git rev-parse --show-toplevel)"

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
EOF

cat > "$HOOK_DIR/pre-push" <<'EOF'
#!/usr/bin/env bash
# [polaris-git-hooks]
# 由 .claude/skills/framework-release/scripts/install-git-hooks.sh 產生，不要直接改。
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"

# 刪 branch 與推 tag 不帶內容，不必過內容閘。
while read -r _local_ref local_sha _remote_ref _remote_sha; do
  [[ "$local_sha" == 0000000000000000000000000000000000000000 ]] && exit 0
done || true

bash "$REPO_ROOT/.claude/skills/framework-release/scripts/pre-push-quality-gate.sh"
EOF

chmod +x "$HOOK_DIR/pre-commit" "$HOOK_DIR/pre-push"
echo "installed: pre-commit, pre-push"
