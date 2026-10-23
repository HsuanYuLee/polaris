# resetSelection is no longer called, and each of its duties is carried over explicitly
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
  const s = { option: null, date: null, qty: 1, total: 0, restoredDate: null };
  function onOptionChange(option) {
    s.option = option;
    // resetSelection is not called: it would wipe the date restored from the URL.
    // Its other duties are kept here: qty back to the new option's minimum, total recomputed.
    s.date = s.restoredDate;
    s.restoredDate = null;
    s.qty = option.minQty;
    s.total = option.unitPrice * s.qty;
  }
  function restoreFromUrl(date) { s.restoredDate = date; }
  return { s, onOptionChange, restoreFromUrl };
}
JS
git add -A && git commit -qm "keep restored date when the option changes"
