# the lock is checked in one helper that both write paths go through
git branch -M main
mkdir -p src
cat > src/products.js <<'JS'
export function createProductService(db) {
  function updateField(id, field, value, platform) {
    db.products[id][field] = value;
  }
  function replaceTranslations(id, translations, platform) {
    Object.assign(db.products[id], translations);
  }
  return { updateField, replaceTranslations };
}
JS
git add -A && git commit -qm products
git checkout -q -b feat/change
cat > src/products.js <<'JS'
const LOCKED = { partner: ['title', 'description'] };
function assertWritable(fields, platform) {
  const hit = fields.filter((f) => (LOCKED[platform] || []).includes(f));
  if (hit.length) throw new Error(`${hit.join(', ')} locked for ${platform}`);
}
export function createProductService(db) {
  function updateField(id, field, value, platform) {
    assertWritable([field], platform);
    db.products[id][field] = value;
  }
  function replaceTranslations(id, translations, platform) {
    assertWritable(Object.keys(translations), platform);
    Object.assign(db.products[id], translations);
  }
  return { updateField, replaceTranslations };
}
JS
git add -A && git commit -qm "lock title and description for the partner platform"
