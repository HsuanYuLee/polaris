#!/usr/bin/env bash
# scripts/validate-l2-embedding.sh
#
# Purpose: 驗證 L2 embedding registry 裡每個 entry 對應的 script / SKILL.md embed /
#          hook 都實際存在且字串一致。漏一個就 exit 1。
# Registry: .claude/skills/references/l2-embedding-registry.md
# Exit codes:
#   0 — 全部 entry 驗證通過（或 registry 無 entry）
#   1 — 至少一個 entry 驗證失敗（missing file / missing grep / anchor 不存在）
#   2 — Registry 檔不存在或格式錯誤（meta error）
#
# Usage:
#   scripts/validate-l2-embedding.sh              # human-readable report
#   scripts/validate-l2-embedding.sh --quiet      # 只輸出 FAIL row + summary
#
# Invoked by:
#   - .claude/skills/validate/SKILL.md Mechanisms mode check #11
#   - Local smoke test during DP-030 Phase 2 rollout

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$REPO_ROOT/.claude/skills/references/l2-embedding-registry.md"
QUIET=0

for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    -h|--help)
      sed -n '3,18p' "$0"
      exit 0
      ;;
  esac
done

log() { [[ $QUIET -eq 0 ]] && echo "$@"; }
fail_line() { echo "  🔴 $*" >&2; }

if [[ ! -f "$REGISTRY" ]]; then
  echo "ERROR: registry missing at $REGISTRY" >&2
  exit 2
fi

# --- Extract table between <!-- registry:start --> and <!-- registry:end --> ---
table=$(awk '
  /<!-- registry:start -->/ {inside=1; next}
  /<!-- registry:end -->/ {inside=0}
  inside && /^\|/ {print}
' "$REGISTRY")

if [[ -z "$table" ]]; then
  echo "ERROR: registry table markers not found or empty" >&2
  exit 2
fi

# Skip header row + separator row. Data rows start at line 3.
data_rows=$(echo "$table" | awk 'NR>=3')

if [[ -z "$data_rows" ]]; then
  log "Registry has no data entries — nothing to validate."
  exit 0
fi

total=0
pass=0
fail=0

# Parse each row. Columns (| Canary | Script | Layer | L2 Skill | L2 Expected Grep | L1 Hook | L1 Event | L1 Matcher | L1 Expected Grep |).
# Escaped pipes in cell content (`\|`, used in regex matchers like `Bash\|Edit`)
# are temporarily replaced with record-separator (\x1e) before the IFS split so
# they don't corrupt column boundaries.
trim_restore() { printf '%s' "$1" | sed 's/\x1e/|/g' | awk '{$1=$1; print}'; }

while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  row_protected=$(printf '%s' "$row" | sed 's/\\|/\x1e/g')
  IFS='|' read -r _ canary script layer l2_skill l2_grep l1_hook l1_event l1_matcher l1_grep _ <<< "$row_protected"

  # Trim whitespace on every field; restore escaped pipes back from \x1e.
  canary="$(trim_restore "$canary")"
  script="$(trim_restore "$script")"
  layer="$(trim_restore "$layer")"
  l2_skill="$(trim_restore "$l2_skill")"
  l2_grep="$(trim_restore "$l2_grep")"
  l1_hook="$(trim_restore "$l1_hook")"
  l1_event="$(trim_restore "$l1_event")"
  l1_matcher="$(trim_restore "$l1_matcher")"
  l1_grep="$(trim_restore "$l1_grep")"

  [[ -z "$canary" || "$canary" == "Canary" ]] && continue

  total=$((total+1))
  row_errors=""

  # --- Script existence ---
  if [[ -n "$script" && "$script" != "—" ]]; then
    if [[ ! -f "$REPO_ROOT/$script" ]]; then
      row_errors+="  - script not found: $script"$'\n'
    fi
  else
    row_errors+="  - script column empty"$'\n'
  fi

  # --- L2 embed check ---
  if [[ "$l2_skill" != "—" && -n "$l2_skill" ]]; then
    # Anchor format: path/to/SKILL.md#Step N — ...
    skill_file="${l2_skill%%#*}"
    anchor="${l2_skill#*#}"
    if [[ -z "$skill_file" || ! -f "$REPO_ROOT/$skill_file" ]]; then
      row_errors+="  - L2 skill file not found: $skill_file"$'\n'
    else
      # Anchor must appear in SKILL.md (as any heading text)
      if ! grep -qF "$anchor" "$REPO_ROOT/$skill_file"; then
        row_errors+="  - L2 anchor missing in $skill_file: $anchor"$'\n'
      fi
      # L2 Expected Grep must appear in SKILL.md
      if [[ -n "$l2_grep" && "$l2_grep" != "—" ]]; then
        if ! grep -qF "$l2_grep" "$REPO_ROOT/$skill_file"; then
          row_errors+="  - L2 expected grep missing in $skill_file: $l2_grep"$'\n'
        fi
      fi
    fi
  fi

  # --- L1 hook check ---
  if [[ "$l1_hook" != "—" && -n "$l1_hook" ]]; then
    if [[ ! -f "$REPO_ROOT/$l1_hook" ]]; then
      row_errors+="  - L1 hook file not found: $l1_hook"$'\n'
    else
      # Hook file must reference the script (indirect — grep for check-X.sh basename)
      if [[ -n "$l1_grep" && "$l1_grep" != "—" ]]; then
        if ! grep -qF "$l1_grep" "$REPO_ROOT/$l1_hook"; then
          row_errors+="  - L1 expected grep missing in $l1_hook: $l1_grep"$'\n'
        fi
      fi
    fi
    # settings.json must register this hook path (any event)
    settings="$REPO_ROOT/.claude/settings.json"
    if [[ -f "$settings" ]]; then
      hook_basename="$(basename "$l1_hook")"
      if ! grep -qF "$hook_basename" "$settings"; then
        row_errors+="  - hook not registered in .claude/settings.json: $hook_basename"$'\n'
      fi
    fi
  fi

  # --- Layer consistency ---
  case "$layer" in
    L2+L1)
      [[ -z "$l2_skill" || "$l2_skill" == "—" ]] && \
        row_errors+="  - Layer L2+L1 declared but L2 Skill empty"$'\n'
      [[ -z "$l1_hook" || "$l1_hook" == "—" ]] && \
        row_errors+="  - Layer L2+L1 declared but L1 Hook empty"$'\n'
      ;;
    L1-only)
      [[ -n "$l2_skill" && "$l2_skill" != "—" ]] && \
        row_errors+="  - Layer L1-only but L2 Skill populated"$'\n'
      [[ -z "$l1_hook" || "$l1_hook" == "—" ]] && \
        row_errors+="  - Layer L1-only but L1 Hook empty"$'\n'
      ;;
    L2-only)
      [[ -z "$l2_skill" || "$l2_skill" == "—" ]] && \
        row_errors+="  - Layer L2-only but L2 Skill empty"$'\n'
      [[ -n "$l1_hook" && "$l1_hook" != "—" ]] && \
        row_errors+="  - Layer L2-only but L1 Hook populated"$'\n'
      ;;
    *)
      row_errors+="  - Unknown Layer value: '$layer' (expected L2+L1 / L1-only / L2-only)"$'\n'
      ;;
  esac

  if [[ -z "$row_errors" ]]; then
    pass=$((pass+1))
    log "✅ $canary — $layer"
  else
    fail=$((fail+1))
    echo "🔴 $canary — $layer" >&2
    printf '%s' "$row_errors" >&2
  fi
done <<< "$data_rows"

echo ""
echo "L2 embedding validation: $total total | $pass ✅ | $fail 🔴"

if (( fail > 0 )); then
  exit 1
fi
exit 0
