. "$(dirname "$0")/_base.sh"
cat > src/pages/plans.js <<'JS'
export function createPlans(api) {
  const state = { loading: false, plans: [] };
  async function load(productId) {
    state.loading = true;
    const raw = await api.getPlans(productId);
    state.plans = groupByCategory(raw);
    state.loading = false;
  }
  return { state, load };
}
function groupByCategory(raw) {
  if (!Array.isArray(raw)) throw new Error('plans must be an array');
  return raw.reduce((acc, p) => ((acc[p.category] ||= []).push(p), acc), {});
}
JS
git add -A && git commit -qm "plans section shows a loading skeleton until plans are grouped"
