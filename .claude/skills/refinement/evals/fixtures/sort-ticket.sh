git branch -M main
mkdir -p web
cat > web/search.js <<'JS'
export function buildQuery(form) {
  return { q: form.keyword, sort: form.sortField.value };
}
JS
cat > TICKET.md <<'MD'
# Search sort should match what the user picked

The sort dropdown on the search page is sometimes ignored. When the user submits a search, the request should carry the sort the user sees selected on screen.
MD
git add -A && git commit -qm "search and ticket"
