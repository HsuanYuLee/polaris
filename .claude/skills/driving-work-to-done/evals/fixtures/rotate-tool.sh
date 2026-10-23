# a small log-rotation tool whose --keep flag is parsed but never used; README has a typo
git branch -M main
mkdir -p scripts
cat > scripts/rotate.sh <<'SH'
#!/usr/bin/env bash
# Rotate app.log: move it to app.log.N and start a fresh one.
set -euo pipefail
KEEP=5
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) KEEP="$2"; shift 2 ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
done
n=$(ls app.log.* 2>/dev/null | wc -l | tr -d ' ')
mv app.log "app.log.$((n + 1))"
: > app.log
SH
chmod +x scripts/rotate.sh
printf '# rotate\nRun scripts/rotate.sh to recieve a fresh app.log.\n' > README.md
git add -A && git commit -qm "rotate tool"
