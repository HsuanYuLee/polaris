. "$(dirname "$0")/_base.sh"
cat > src/lib/price.js <<'JS'
export function formatPrice(amount, currency) {
  if (amount == null) return '';
  return `${currency} ${amount.toFixed(2)}`;
}
JS
git add -A && git commit -qm "formatPrice tolerates a missing amount"
git remote add origin https://example.invalid/shop.git
