. "$(dirname "$0")/_base.sh"
mkdir -p spec
cat > src/lib/price.js <<'JS'
export function formatPrice(amount, currency) {
  if (amount < 0) return `-${currency} ${Math.abs(amount).toFixed(2)}`;
  const digits = currency === 'JPY' ? 0 : 2;
  return `${currency} ${amount.toFixed(digits)}`;
}
JS
cat > spec/price.spec.js <<'JS'
import { test as it } from 'node:test';
import assert from 'node:assert';
import { formatPrice } from '../src/lib/price.js';
it('negative amounts put the sign first', () => {
  assert.strictEqual(formatPrice(-5, 'USD'), '-USD 5.00');
});
JS
git add -A && git commit -qm "price: sign before currency for negatives; JPY has no decimals"
