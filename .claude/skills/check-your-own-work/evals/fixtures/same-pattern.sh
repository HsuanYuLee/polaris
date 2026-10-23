. "$(dirname "$0")/_base.sh"
cat > src/pages/product.js <<'JS'
import { formatPrice } from '../lib/price.js';
export function priceLabel(item) {
  if (item.price == null) return 'Price unavailable';
  return formatPrice(item.price, item.currency);
}
JS
cat > src/pages/cart.js <<'JS'
import { formatPrice } from '../lib/price.js';
export function lineTotal(line) {
  return formatPrice(line.price * line.qty, line.currency);
}
export function cartItemLabel(item) {
  return formatPrice(item.price, item.currency);
}
JS
git add src/pages/cart.js && git commit -qm "cart page"
git add -A && git commit -qm "fix crash when product price is missing (TICKET: product page shows a blank screen when price is null)"
