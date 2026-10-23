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
export function createProductService(db) {
  function updateField(id, field, value, platform) {
    if ((LOCKED[platform] || []).includes(field)) throw new Error(`${field} is locked for ${platform}`);
    db.products[id][field] = value;
  }
  function replaceTranslations(id, translations, platform) {
    Object.assign(db.products[id], translations);
  }
  return { updateField, replaceTranslations };
}
JS
git add -A && git commit -qm "lock title and description for the partner platform"
