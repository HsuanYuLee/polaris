#!/usr/bin/env bash
# Selftest for scripts/lint-dp-keyed-source-symmetry.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$SCRIPT_DIR/lint-dp-keyed-source-symmetry.sh"

PASS=0
FAIL=0

ok() { echo "PASS $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d -t dp-keyed-source-symmetry.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

allowlist="$TMP/allowlist.txt"
cat >"$allowlist" <<'EOF'
[registry]
[auto-pass-prose]
[resolver-logic]
allowed-dp-only.sh:inherent:create-design-plan DP number allocation
EOF

cat >"$TMP/asymmetric.sh" <<'EOF'
resolve_by_dp() {
  find "$root/docs-manager/src/content/docs/specs/design-plans" -name 'DP-*'
}
EOF

cat >"$TMP/fixed.sh" <<'EOF'
resolve_by_dp() {
  find "$root/docs-manager/src/content/docs/specs/design-plans" -name 'DP-*'
}
resolve_by_jira_epic() {
  find "$root/docs-manager/src/content/docs/specs/companies" -name 'FOO-*'
}
EOF

cat >"$TMP/allowed-dp-only.sh" <<'EOF'
allocate_next_dp_number() {
  find docs-manager/src/content/docs/specs/design-plans -name 'DP-*'
}
EOF

cat >"$TMP/dev-grep.sh" <<'EOF'
echo "Developer note: DP-123 is mentioned in a fixture title, not resolver logic."
EOF

mkdir -p "$TMP/lib"
cat >"$TMP/delegating-wrapper.sh" <<'EOF'
#!/usr/bin/env bash
# design-plans/DP-* resolver compatibility shim
python3 "$(dirname "$0")/lib/delegated.py" "$@"
EOF
cat >"$TMP/lib/delegated.py" <<'EOF'
def resolve_by_jira_epic(root):
    return root / "docs-manager/src/content/docs/specs/companies"
EOF

cat >"$TMP/comment-only-wrapper.sh" <<'EOF'
#!/usr/bin/env bash
# lib/delegated.py is documentation, not an executed delegation.
resolve_by_dp() {
  find "$root/docs-manager/src/content/docs/specs/design-plans" -name 'DP-*'
}
EOF

cat >"$TMP/echo-only-wrapper.sh" <<'EOF'
#!/usr/bin/env bash
resolve_by_dp() {
  find "$root/docs-manager/src/content/docs/specs/design-plans" -name 'DP-*'
}
echo python3 lib/delegated.py
EOF

cat >"$TMP/heredoc-only-wrapper.sh" <<'EOF'
#!/usr/bin/env bash
resolve_by_dp() {
  find "$root/docs-manager/src/content/docs/specs/design-plans" -name 'DP-*'
}
cat <<'TEXT'
python3 lib/delegated.py
TEXT
EOF

run_lint() {
  POLARIS_PARITY_ALLOWLIST="$allowlist" \
  POLARIS_DP_KEYED_SOURCE_SURFACES="$1" \
    bash "$LINT" >"$TMP/out.txt" 2>"$TMP/err.txt"
}

run_lint "$TMP/asymmetric.sh"
rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'POLARIS_DP_KEYED_SOURCE_ASYMMETRY' "$TMP/err.txt"; then
  ok "asymmetric DP resolver fails closed"
else
  bad "asymmetric DP resolver should fail with marker (rc=$rc)"
fi

run_lint "$TMP/fixed.sh"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "companies counterpart passes"
else
  bad "companies counterpart should pass (rc=$rc)"
fi

( cd "$TMP" && POLARIS_PARITY_ALLOWLIST="$allowlist" POLARIS_DP_KEYED_SOURCE_SURFACES="allowed-dp-only.sh" bash "$LINT" >"$TMP/out.txt" 2>"$TMP/err.txt" )
rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "resolver-logic allowlist suppresses inherent DP-only surface"
else
  bad "allowlisted DP-only surface should pass (rc=$rc)"
fi

run_lint "$TMP/dev-grep.sh"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "ordinary DP mention does not trigger resolver lint"
else
  bad "ordinary DP mention should not trigger resolver lint (rc=$rc)"
fi

run_lint "$TMP/delegating-wrapper.sh"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "delegated Python counterpart is part of the shell validator surface"
else
  bad "delegated Python counterpart should satisfy resolver parity (rc=$rc)"
fi

run_lint "$TMP/comment-only-wrapper.sh"
rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'POLARIS_DP_KEYED_SOURCE_ASYMMETRY' "$TMP/err.txt"; then
  ok "comment-only module mention cannot masquerade as delegation"
else
  bad "comment-only module mention should fail closed (rc=$rc)"
fi

run_lint "$TMP/echo-only-wrapper.sh"
rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'POLARIS_DP_KEYED_SOURCE_ASYMMETRY' "$TMP/err.txt"; then
  ok "echo-only module mention cannot masquerade as delegation"
else
  bad "echo-only module mention should fail closed (rc=$rc)"
fi

run_lint "$TMP/heredoc-only-wrapper.sh"
rc=$?
if [[ "$rc" -eq 2 ]] && grep -q 'POLARIS_DP_KEYED_SOURCE_ASYMMETRY' "$TMP/err.txt"; then
  ok "heredoc-only module mention cannot masquerade as delegation"
else
  bad "heredoc-only module mention should fail closed (rc=$rc)"
fi

echo "----"
echo "lint-dp-keyed-source-symmetry selftest: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
