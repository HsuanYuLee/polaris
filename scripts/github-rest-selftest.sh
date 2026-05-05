#!/usr/bin/env bash
# Selftest for scripts/lib/github-rest.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d -t polaris-github-rest-selftest-XXXXXX)"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

assert_eq() {
  local got="$1"
  local want="$2"
  local label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s: want=%q got=%q\n' "$label" "$want" "$got" >&2
  fi
}

assert_json_eq() {
  local json="$1"
  local expr="$2"
  local want="$3"
  local label="$4"
  local got
  got="$(printf '%s' "$json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(${expr})")"
  assert_eq "$got" "$want" "$label"
}

mkdir -p "$WORK_DIR/bin"
cat >"$WORK_DIR/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

log="${FAKE_GH_LOG:?}"
printf '%s\n' "$*" >>"$log"

if [[ "${FAKE_RATE_LIMIT_ONCE:-0}" == "1" && ! -f "${FAKE_RATE_LIMIT_MARK:?}" ]]; then
  touch "$FAKE_RATE_LIMIT_MARK"
  echo "API rate limit exceeded" >&2
  exit 1
fi

[[ "${1:-}" == "api" ]] || exit 1
shift
endpoint="${1:-}"

case "$endpoint" in
  repos/acme/demo/pulls/7)
    cat <<'JSON'
{"number":7,"title":"Demo PR","body":"Body","state":"open","draft":false,"html_url":"https://github.com/acme/demo/pull/7","user":{"login":"alice"},"head":{"ref":"task/demo","sha":"abc123"},"base":{"ref":"main"}}
JSON
    ;;
  repos/acme/demo/pulls)
    cat <<'JSON'
[{"number":7,"title":"Demo PR","body":"Body","state":"open","draft":false,"html_url":"https://github.com/acme/demo/pull/7","user":{"login":"alice"},"head":{"ref":"task/demo","sha":"abc123"},"base":{"ref":"main"}}]
JSON
    ;;
  repos/acme/demo/commits/abc123/check-runs)
    cat <<'JSON'
{"check_runs":[{"name":"unit","status":"completed","conclusion":"success","output":{"summary":"ok"}},{"name":"lint","status":"completed","conclusion":"failure","output":{"summary":"bad"}},{"name":"build","status":"in_progress","conclusion":null,"output":{"summary":""}}]}
JSON
    ;;
  repos/acme/demo/commits/abc123/statuses)
    cat <<'JSON'
[{"context":"deploy","state":"pending","description":"waiting"}]
JSON
    ;;
  *)
    echo "unsupported endpoint: $endpoint" >&2
    exit 1
    ;;
esac
SH
chmod +x "$WORK_DIR/bin/gh"

repo="$WORK_DIR/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email selftest@example.com
git -C "$repo" config user.name selftest
git -C "$repo" remote add origin git@github.com:acme/demo.git
touch "$repo/file"
git -C "$repo" add file
git -C "$repo" commit -q -m init
git -C "$repo" checkout -q -b task/demo

# shellcheck source=lib/github-rest.sh
. "$SCRIPT_DIR/lib/github-rest.sh"

export PATH="$WORK_DIR/bin:$PATH"
export FAKE_GH_LOG="$WORK_DIR/gh.log"
: >"$FAKE_GH_LOG"

pr_json="$(polaris_pr_view_rest acme/demo 7)"
assert_json_eq "$pr_json" "d['state']" "OPEN" "pr_view.state"
assert_json_eq "$pr_json" "d['headRefName']" "task/demo" "pr_view.head"

current_json="$(polaris_current_branch_pr_rest "$repo")"
assert_json_eq "$current_json" "d['number']" "7" "current_branch.number"

checks_json="$(polaris_pr_checks_rest acme/demo 7)"
assert_eq "$(printf '%s' "$checks_json" | jq '[.[] | select(.state == "SUCCESS")] | length')" "1" "checks.success"
assert_eq "$(printf '%s' "$checks_json" | jq '[.[] | select(.state == "FAILURE")] | length')" "1" "checks.failure"
assert_eq "$(printf '%s' "$checks_json" | jq '[.[] | select(.state == "PENDING")] | length')" "2" "checks.pending"

export FAKE_RATE_LIMIT_ONCE=1
export FAKE_RATE_LIMIT_MARK="$WORK_DIR/rate-limit-seen"
retry_json="$(POLARIS_GH_API_BACKOFF_SECONDS=0 polaris_pr_view_rest acme/demo 7)"
assert_json_eq "$retry_json" "d['title']" "Demo PR" "retry.rate_limit"

set +e
polaris_gh_api "repos/acme/demo/not-found" >/dev/null 2>"$WORK_DIR/not-found.err"
not_found_rc=$?
set -e
assert_eq "$not_found_rc" "1" "non_rate_failure.rc"

if [[ "$FAIL" -ne 0 ]]; then
  printf 'github-rest selftest: %s passed, %s failed\n' "$PASS" "$FAIL" >&2
  exit 1
fi

printf 'github-rest selftest: %s passed\n' "$PASS"
