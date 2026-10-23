# sourced by each fixture: puts a small shop app on main, then switches to the change branch
git branch -M main
mkdir -p src/pages src/lib
cat > src/lib/price.js <<'JS'
export function formatPrice(amount, currency) {
  return `${currency} ${amount.toFixed(2)}`;
}
JS
cat > package.json <<'JS'
{ "name": "shop", "private": true, "scripts": { "test": "node --test" } }
JS
git add -A && git commit -qm "shop app"
git checkout -q -b feat/change
