#!/usr/bin/env bash
# sync-company-skill-links.sh — 讓資料夾模式的 skill 在執行期登記得到
#
# 這一版 Claude Code 只登記 .claude/skills/{name}/SKILL.md。放在
# .claude/skills/{ns}/{name}/SKILL.md 的 skill 執行期看不到——六支公司 skill 在存在期間
# 一次都沒被載入過，沒有人發現，因為 routing 散文照樣把工作分派出去，只是分派到一份
# 從未被讀取的程序。
#
# 資料夾模式是這個 repo 的既有慣例，不只一個人在維護它。所以位置不動，改在深度一補一條
# symlink 讓執行期登記得到。symlink 由這支腳本產生，不由人手工維護——加一支新 skill 的人
# 不需要知道有這回事。
#
# 命名空間是自己描述的，不讀任何設定：.claude/skills/ 下**沒有 SKILL.md 但底下有 skill**
# 的目錄就是命名空間。所以之後多一間公司不用改這支腳本。
#
# Usage:
#   bash scripts/sync-company-skill-links.sh            # 建立缺少的、清掉指空的
#   bash scripts/sync-company-skill-links.sh --check    # 只檢查，不動檔案；不一致 exit 2
#   bash scripts/sync-company-skill-links.sh --stage    # 建立後 git add（給 pre-commit 用）
#
# Exit: 0 一致（或已修好）／2 --check 下不一致、或宿主環境撐不住 symlink

set -uo pipefail

MODE="apply"
case "${1:-}" in
  --check) MODE="check" ;;
  --stage) MODE="stage" ;;
  "") ;;
  *) echo "usage: $0 [--check|--stage]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$ROOT_DIR/.claude/skills"
[[ -d "$SKILLS_DIR" ]] || exit 0

missing=()
stale=()
created=()
removed=()

# 收集期望的 {ns}-{name} -> {ns}/{name}
declare -a want_link want_target
for ns_dir in "$SKILLS_DIR"/*/; do
  ns="$(basename "$ns_dir")"
  [[ "$ns" == "references" ]] && continue
  [[ -L "${ns_dir%/}" ]] && continue          # 深度一的 symlink 自己不是命名空間
  [[ -f "$ns_dir/SKILL.md" ]] && continue     # 有 SKILL.md 的是 skill，不是命名空間
  for skill_dir in "$ns_dir"*/; do
    [[ -f "$skill_dir/SKILL.md" ]] || continue
    name="$(basename "$skill_dir")"
    want_link+=("$ns-$name")
    want_target+=("$ns/$name")
  done
done

for i in "${!want_link[@]}"; do
  link="$SKILLS_DIR/${want_link[$i]}"
  target="${want_target[$i]}"
  if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
    continue
  fi
  missing+=("${want_link[$i]} -> $target")
  [[ "$MODE" == "check" ]] && continue
  rm -f "$link"
  ln -s "$target" "$link"
  # 宿主環境撐不住 symlink 時要明講並失敗，不得留下一個看起來有、實際叫不到的檔案。
  if [[ ! -L "$link" ]]; then
    echo "POLARIS_COMPANY_SKILL_LINK_UNSUPPORTED" >&2
    echo "  $link 建立後不是 symlink——這個檔案系統或 git 設定不支援 symlink。" >&2
    echo "  修法：git config core.symlinks true，再重新 checkout。" >&2
    exit 2
  fi
  created+=("${want_link[$i]}")
done

# 指向不存在目標的舊 symlink：來源被刪或改名時清掉它
for link in "$SKILLS_DIR"/*; do
  [[ -L "$link" ]] || continue
  target="$(readlink "$link")"
  [[ "$target" == */* ]] || continue          # 只管指向命名空間內部的
  if [[ ! -f "$SKILLS_DIR/$target/SKILL.md" ]]; then
    stale+=("$(basename "$link") -> $target")
    [[ "$MODE" == "check" ]] && continue
    rm -f "$link"
    removed+=("$(basename "$link")")
  fi
done

if [[ "$MODE" == "check" ]]; then
  if [[ ${#missing[@]} -gt 0 || ${#stale[@]} -gt 0 ]]; then
    echo "POLARIS_COMPANY_SKILL_LINK_DRIFT" >&2
    for m in "${missing[@]:-}"; do [[ -n "$m" ]] && echo "  缺少登記： $m" >&2; done
    for s in "${stale[@]:-}"; do [[ -n "$s" ]] && echo "  指向不存在： $s" >&2; done
    echo "  修法：bash scripts/sync-company-skill-links.sh" >&2
    exit 2
  fi
  echo "COMPANY SKILL LINKS OK (${#want_link[@]} linked)"
  exit 0
fi

if [[ "$MODE" == "stage" && ( ${#created[@]} -gt 0 || ${#removed[@]} -gt 0 ) ]]; then
  git -C "$ROOT_DIR" add -A -- ".claude/skills" >/dev/null 2>&1 || true
fi

for c in "${created[@]:-}"; do [[ -n "$c" ]] && echo "  + $c"; done
for r in "${removed[@]:-}"; do [[ -n "$r" ]] && echo "  - $r (指向不存在的來源)"; done
echo "COMPANY SKILL LINKS OK (${#want_link[@]} linked)"
