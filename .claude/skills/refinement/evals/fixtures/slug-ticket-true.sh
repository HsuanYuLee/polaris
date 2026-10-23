# same ticket as slug-ticket.sh, but here the API really does return slug
. "$(dirname "$0")/slug-ticket.sh"
cat > api/products.js <<'JS'
export function productCard(row) {
  return { id: row.id, slug: row.slug, name: row.name, price: row.price };
}
JS
git add -A && git commit -qm "api returns slug"
