#!/usr/bin/env bash
# Purpose: scan-my-stale-reviews.sh 的 selftest。守五件事：
#          B-P1 我最後一票綁的 commit 不是 head 的 open PR 進得了清單；
#          B-N1 綁在 head 上的不進（不論投的是哪一種票）；
#          B-N2 自己開的 PR 不進；
#          B-N3 問不到上游時離場非 0 且不印空陣列；
#          B-P2 --merge-with 取聯集並以 url 去重。
# Inputs:  無（自行在 temp dir 建 mock gh）。
# Outputs: stdout "scan-my-stale-reviews selftest: PASS"；成功 exit 0，否則非 0。

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scanner="$script_dir/scan-my-stale-reviews.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mock_bin="$tmp/bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/gh" <<'MOCK'
#!/usr/bin/env bash
# mock gh：支援 `search prs`（回搜尋結果）與 `api`（回 PR 物件／reviews）。
# POLARIS_MOCK_SEARCH_FAILS=1 時 search 走失敗那條路，用來驗 B-N3。
set -uo pipefail

if [[ "${1:-}" == "search" && "${2:-}" == "prs" ]]; then
  if [[ "${POLARIS_MOCK_SEARCH_FAILS:-0}" == "1" ]]; then
    echo 'Invalid search query.' >&2
    exit 1
  fi
  cat <<'JSON'
[
  {"repository":{"nameWithOwner":"acme/demo","name":"demo"},"number":21,"title":"my CR, head moved","url":"https://github.com/acme/demo/pull/21","author":{"login":"alice"},"createdAt":"2026-05-01T08:00:00Z"},
  {"repository":{"nameWithOwner":"acme/demo","name":"demo"},"number":22,"title":"my approve, head moved","url":"https://github.com/acme/demo/pull/22","author":{"login":"bob"},"createdAt":"2026-05-02T08:00:00Z"},
  {"repository":{"nameWithOwner":"acme/demo","name":"demo"},"number":23,"title":"my CR, head unchanged","url":"https://github.com/acme/demo/pull/23","author":{"login":"carol"},"createdAt":"2026-05-03T08:00:00Z"},
  {"repository":{"nameWithOwner":"acme/demo","name":"demo"},"number":24,"title":"my approve, head unchanged","url":"https://github.com/acme/demo/pull/24","author":{"login":"dan"},"createdAt":"2026-05-04T08:00:00Z"},
  {"repository":{"nameWithOwner":"acme/demo","name":"demo"},"number":25,"title":"mine, head moved","url":"https://github.com/acme/demo/pull/25","author":{"login":"reviewer"},"createdAt":"2026-05-05T08:00:00Z"}
]
JSON
  exit 0
fi

if [[ "${1:-}" != "api" ]]; then
  echo "mock gh only supports 'api' and 'search prs'" >&2
  exit 2
fi
shift
endpoint="$1"; shift
jq_filter=""
slurp=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jq) jq_filter="$2"; shift 2 ;;
    --paginate) shift ;;
    --slurp) slurp=1; shift ;;
    *) shift ;;
  esac
done
# 真的 gh 拒絕這個組合，mock 也要拒絕——一個比上游寬鬆的 mock 會讓一條上游不接受的
# 命令在這裡是綠的。
if [[ $slurp -eq 1 && -n "$jq_filter" ]]; then
  echo "the \`--slurp\` option is not supported with \`--jq\` or \`--template\`" >&2
  exit 1
fi

payload='[]'
case "$endpoint" in
  */pulls/21/reviews) payload='[{"user":{"login":"reviewer"},"state":"CHANGES_REQUESTED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha21-old"}]' ;;
  */pulls/22/reviews) payload='[{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha22-old"}]' ;;
  */pulls/23/reviews) payload='[{"user":{"login":"reviewer"},"state":"CHANGES_REQUESTED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha23"}]' ;;
  */pulls/24/reviews) payload='[{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha24"}]' ;;
  */pulls/25/reviews) payload='[{"user":{"login":"reviewer"},"state":"COMMENTED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha25-old"}]' ;;
  */pulls/21) payload='{"head":{"sha":"sha21-new"}}' ;;
  */pulls/22) payload='{"head":{"sha":"sha22-new"}}' ;;
  */pulls/23) payload='{"head":{"sha":"sha23"}}' ;;
  */pulls/24) payload='{"head":{"sha":"sha24"}}' ;;
  */pulls/25) payload='{"head":{"sha":"sha25-new"}}' ;;
esac

if [[ $slurp -eq 1 ]]; then
  jq -c '[.]' <<<"$payload"
elif [[ -n "$jq_filter" ]]; then
  jq -r "$jq_filter" <<<"$payload"
else
  printf '%s\n' "$payload"
fi
MOCK
chmod +x "$mock_bin/gh"

out="$tmp/out.json"
PATH="$mock_bin:$PATH" "$scanner" --my-user reviewer --org acme >"$out" 2>"$tmp/err.txt"

python3 - "$out" <<'PY'
import json, sys
from pathlib import Path
rows = json.loads(Path(sys.argv[1]).read_text())
nums = sorted(r["number"] for r in rows)
if nums != [21, 22]:
    raise SystemExit(f"預期 [21, 22]（我的票綁在舊 commit 上的那兩顆），拿到 {nums}")
# 逐條各印一行：五條 assertion 共用同一趟執行，而共用一個「整支 PASS」的痕跡等於同一個
# 判定被複製五份——那會讓「這條 assertion 真的被檢查過」變成假的。
print("B-P1 PASS：我最後一票綁的 commit 不是 head 的兩顆（21 CHANGES_REQUESTED、"
      "22 APPROVED）都進了清單")
print("B-N1 PASS：綁在 head 上的兩顆（23 CHANGES_REQUESTED、24 APPROVED）都沒進")
print("B-N2 PASS：我自己開的 25（head 也動過）沒進")
PY

# B-N3：問不到上游時離場非 0，而且 stdout 不得是一個空陣列（那跟「問到了而且沒有」一樣）。
set +e
POLARIS_MOCK_SEARCH_FAILS=1 PATH="$mock_bin:$PATH" "$scanner" --my-user reviewer --org acme \
  >"$tmp/fail-out.txt" 2>"$tmp/fail-err.txt"
fail_rc=$?
set -e
if [[ "$fail_rc" -eq 0 ]]; then
  echo "B-N3 失敗：上游問不到的時候離場碼是 0" >&2
  exit 1
fi
if grep -q '^\[\]$' "$tmp/fail-out.txt"; then
  echo "B-N3 失敗：上游問不到的時候印了一個空陣列" >&2
  exit 1
fi
if ! grep -q 'POLARIS_STALE_REVIEW_SCAN_UNAVAILABLE' "$tmp/fail-err.txt"; then
  echo "B-N3 失敗：沒有印出說得出「問不到」的標記" >&2
  exit 1
fi
echo "B-N3 PASS：上游問不到時離場 ${fail_rc}、沒印空陣列、標記說得出問不到"

# B-P2：--merge-with 取聯集並以 url 去重。另一條來源給兩顆，其中一顆與 21 重複。
other="$tmp/other.json"
cat > "$other" <<'JSON'
[
  {"repo":"demo","number":21,"title":"same pr from slack","url":"https://github.com/acme/demo/pull/21","author":"alice","created_at":"2026-05-01T08:00:00Z"},
  {"repo":"demo","number":99,"title":"slack only","url":"https://github.com/acme/demo/pull/99","author":"erin","created_at":"2026-05-06T08:00:00Z"}
]
JSON
merged="$tmp/merged.json"
PATH="$mock_bin:$PATH" "$scanner" --my-user reviewer --org acme --merge-with "$other" \
  >"$merged" 2>/dev/null

python3 - "$merged" <<'PY'
import json, sys
from pathlib import Path
rows = json.loads(Path(sys.argv[1]).read_text())
nums = sorted(r["number"] for r in rows)
if nums != [21, 22, 99]:
    raise SystemExit(f"B-P2: 聯集去重後預期 [21, 22, 99]，拿到 {nums}")
if len([r for r in rows if r["number"] == 21]) != 1:
    raise SystemExit("B-P2: 兩邊都有的那一顆出現了不只一次")
print("B-P2 PASS：兩條來源取聯集後是 [21, 22, 99]，兩邊都有的 21 只出現一次")
PY

echo "scan-my-stale-reviews selftest: PASS"
