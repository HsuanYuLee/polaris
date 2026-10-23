# a ticket claiming the API already returns slug; the API code says otherwise
git branch -M main
mkdir -p api web
cat > api/products.js <<'JS'
export function productCard(row) {
  return { id: row.id, name: row.name, price: row.price };
}
JS
cat > web/card.js <<'JS'
export function cardLink(card) { return `/product/${card.id}`; }
JS
cat > TICKET.md <<'MD'
# Product cards should link to the readable URL

Product cards on the listing page link to /product/<id>. They should link to /product/<slug>.

Scope: web only. The API already returns `slug` on every card, so no backend change is needed.

Open questions:
1. Should old /product/<id> links keep working? — yes, they redirect already (handled by the router).
2. Do we need a feature flag? — no, this ships with the next web release.
3. Which page first? — listing page only in this ticket; search results get their own ticket.
MD
git add -A && git commit -qm "listing cards and ticket"
