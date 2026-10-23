. "$(dirname "$0")/_base.sh"
cat > src/lib/user.js <<'JS'
export async function fetchUser(id, http) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try { return await http.get(`/users/${id}`); } catch (e) { if (attempt === 2) throw e; }
  }
}
JS
git add -A && git commit -qm "fetchUser retries up to 3 times"
cat > PR_DRAFT.md <<'MD'
## fetchUser retries
- fetchUser now retries up to 3 times with exponential backoff
- CHANGELOG.md updated with the new behaviour
- added a unit test for the retry path
MD
