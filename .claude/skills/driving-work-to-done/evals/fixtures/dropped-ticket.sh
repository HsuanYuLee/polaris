# the rotate tool plus an open ticket about --keep, already signed and with a round in progress
. "$(dirname "$0")/rotate-tool.sh"
T=issues/tools/DP-1-keep-flag-is-ignored
mkdir -p "$T"
cat > "$T/index.md" <<'MD'
---
destination: workspace
plan:
  what:
    not_applicable: "fixture"
---
# DP-1 --keep is ignored

<!-- POLARIS-FROZEN-A-BEGIN -->
- **A-P1**: when rotate.sh runs with --keep N, at most N rotated files remain.
<!-- POLARIS-FROZEN-A-END -->
MD
bash .claude/skills/refinement/scripts/frozen-assertion-fence.sh seal "$T/index.md" --by dev >/dev/null
git -C . add -A && git commit -qm "DP-1"
bash .claude/skills/driving-work-to-done/scripts/spine-loop-state.sh init --state "$T/.spine/loop-state.json" --pack none --why "fixture" >/dev/null 2>&1
git add -A && git commit -qm "DP-1 round open"
