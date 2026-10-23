. "$(dirname "$0")/_base.sh"
cat > src/lib/price.js <<'JS'
export function formatPrice(value, currency) {
  return `${currency} ${value.toFixed(2)}`;
}
JS
git add -A && git commit -qm "rename amount to value in formatPrice"
cat > PR_DRAFT.md <<'MD'
## Rename a parameter
Renames `amount` to `value` in `formatPrice`. No behaviour change.
MD
