git branch -M main
mkdir -p src
cat > src/booking.js <<'JS'
export function createBooking() {
  const s = { option: null, date: null, qty: 1, total: 0 };
  function resetSelection(option) {
    s.date = null;
    s.qty = option.minQty;
    s.total = option.unitPrice * s.qty;
  }
  function onOptionChange(option) {
    s.option = option;
    resetSelection(option);
  }
  return { s, onOptionChange };
}
JS
git add -A && git commit -qm booking
git checkout -q -b feat/change
cat > src/booking.js <<'JS'
export function createBooking() {
  const s = { option: null, date: null, qty: 1, total: 0 };
  function recalcPrice() {
    s.total = s.option.unitPrice * s.qty;
  }
  function onOptionChange(option) {
    s.option = option;
    // no resetSelection here: it would wipe the date the user just restored from the URL
    recalcPrice();
  }
  return { s, onOptionChange };
}
JS
git add -A && git commit -qm "keep restored date when the option changes"
