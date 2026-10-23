# the missing-price guard sits in formatPrice itself, so every caller gets it
. "$(dirname "$0")/_base.sh"
cat > src/pages/cart.js <<'JS'
import { formatPrice } from '../lib/price.js';
export function lineTotal(line) {
  return formatPrice(line.price == null ? null : line.price * line.qty, line.currency);
}
export function cartItemLabel(item) {
  return formatPrice(item.price, item.currency);
}
JS
cat > src/pages/product.js <<'JS'
import { formatPrice } from '../lib/price.js';
export function priceLabel(item) {
  return formatPrice(item.price, item.currency);
}
JS
git add -A && git commit -qm "product and cart pages"
cat > src/lib/price.js <<'JS'
export function formatPrice(amount, currency) {
  if (amount == null) return 'Price unavailable';
  return `${currency} ${amount.toFixed(2)}`;
}
JS
git add -A && git commit -qm "fix crash when product price is missing (TICKET: product page shows a blank screen when price is null)"
