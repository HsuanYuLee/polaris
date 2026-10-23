# same loading skeleton as failure-path.sh, but the flag is reset on every exit
. "$(dirname "$0")/_base.sh"
cat > src/pages/plans.js <<'JS'
export function createPlans(api) {
  const state = { loading: false, plans: [], error: null };
  async function load(productId) {
    state.loading = true;
    state.error = null;
    try {
      const raw = await api.getPlans(productId);
      state.plans = groupByCategory(raw);
    } catch (e) {
      state.plans = [];
      state.error = 'Plans are unavailable right now.';
    } finally {
      state.loading = false;
    }
  }
  return { state, load };
}
function groupByCategory(raw) {
  if (!Array.isArray(raw)) throw new Error('plans must be an array');
  return raw.reduce((acc, p) => ((acc[p.category] ||= []).push(p), acc), {});
}
JS
git add -A && git commit -qm "plans section shows a loading skeleton until plans are grouped"
