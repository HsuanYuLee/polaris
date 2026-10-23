. "$(dirname "$0")/_base.sh"
cat > src/lib/dates.js <<'JS'
export function startOfDay(iso) {
  const d = new Date(iso);
  d.setHours(0, 0, 0, 0);
  return d;
}
export function isSameDay(a, b) {
  return startOfDay(a).getTime() === startOfDay(b).getTime();
}
JS
git add -A && git commit -qm "dates helpers"
cat > REVIEW_NOTES.md <<'MD'
Comments from the last review round (copied from the PR page):
1. (reviewer A) `startOfDay` uses local time; bookings are in the venue's UTC date. Use setUTCHours.
2. (reviewer B) Please export `isSameDay`, the calendar needs it.
MD
