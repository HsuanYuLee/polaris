#!/usr/bin/env bash
# Purpose: check-my-review-status.sh 的 selftest，斷言 review-status 狀態機，
#          含 DP-315 commit_id 基準的 approval-staleness 判定（AC4），以及
#          consumer 內已無 committer-date / pushed_at staleness 依據（AC-NF1 / AC-NEG2）。
# Inputs:  無（自行在 temp dir 建 mock gh + candidate fixtures）。
# Outputs: stdout "check-my-review-status selftest: PASS"；成功 exit 0，
#          任一斷言失敗時 exit 非 0。

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="$script_dir/check-my-review-status.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mock_bin="$tmp/bin"
mkdir -p "$mock_bin"

# Mock gh：reviews 帶 commit_id（DP-315 staleness 基準）；head.sha 改由 /pulls/N
# 物件的 .head.sha 投影取得（DP-355，與 check-pr-approval-status.sh 一致）。
# /commits 仍保留 fixture（且仍輸出 committer.date），用來證明 consumer 已不再讀
# /commits 分頁第一頁判 head——>30-commit case 故意把 /commits 第一頁 .[-1] 設成
# 非 head sha，若 head 仍取自 /commits 分頁就會誤分類。
cat > "$mock_bin/gh" <<'MOCK'
#!/usr/bin/env bash
# mock gh：僅支援 api 子命令，回傳預設 fixtures
set -euo pipefail

if [[ "$1" != "api" ]]; then
  echo "mock gh only supports api" >&2
  exit 2
fi
shift
endpoint="$1"
shift
jq_filter=""
# 解析 --jq 與 --paginate 旗標
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jq) jq_filter="$2"; shift 2 ;;
    --paginate) shift ;;
    *) shift ;;
  esac
done

# 由 endpoint 取出 PR / issue 編號
number="$(sed -E 's#.*pulls/([0-9]+).*#\1#' <<<"$endpoint")"
if [[ "$endpoint" == *"/issues/"* ]]; then
  number="$(sed -E 's#.*issues/([0-9]+).*#\1#' <<<"$endpoint")"
fi

payload='[]'
case "$endpoint" in
  # PR 1 — 從未 review → needs_first_review
  */pulls/1/reviews) payload='[]' ;;
  */pulls/1/commits) payload='[{"sha":"sha1","commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/1/comments|*/issues/1/comments) payload='[]' ;;

  # PR 2 — 只有 COMMENTED，head 未變（commit_id == head.sha）→ waiting_for_author（排除）
  */pulls/2/reviews) payload='[{"user":{"login":"reviewer"},"state":"COMMENTED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha2"}]' ;;
  */pulls/2/commits) payload='[{"sha":"sha2","commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/2/comments|*/issues/2/comments) payload='[]' ;;

  # PR 3 — CHANGES_REQUESTED，無新 push、作者未回覆 → waiting_for_author（排除）
  */pulls/3/reviews) payload='[{"user":{"login":"reviewer"},"state":"CHANGES_REQUESTED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha3"}]' ;;
  */pulls/3/commits) payload='[{"sha":"sha3","commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/3/comments) payload='[{"user":{"login":"carol"},"created_at":"2026-05-06T10:30:00Z"}]' ;;
  */issues/3/comments) payload='[]' ;;

  # PR 4 — APPROVED 但 head 已移動（review commit_id != head.sha）→ needs_re_approve（AC4）
  */pulls/4/reviews) payload='[{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha4-old"}]' ;;
  */pulls/4/commits) payload='[{"sha":"sha4-new","commit":{"committer":{"date":"2026-05-06T11:00:00Z"}}}]' ;;
  */pulls/4/comments|*/issues/4/comments) payload='[]' ;;

  # PR 5 — CHANGES_REQUESTED，作者回覆 + 新 push → needs_re_review
  */pulls/5/reviews) payload='[{"user":{"login":"reviewer"},"state":"CHANGES_REQUESTED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha5-old"}]' ;;
  */pulls/5/commits) payload='[{"sha":"sha5-new","commit":{"committer":{"date":"2026-05-06T11:00:00Z"}}}]' ;;
  */pulls/5/comments) payload='[{"user":{"login":"erin"},"created_at":"2026-05-06T11:30:00Z"}]' ;;
  */issues/5/comments) payload='[]' ;;

  # PR 6 — 最新 review 為 APPROVED，commit_id == head.sha、head 未變 → 非 actionable（排除）
  */pulls/6/reviews) payload='[{"user":{"login":"reviewer"},"state":"COMMENTED","submitted_at":"2026-05-06T08:00:00Z","commit_id":"sha6"},{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha6"}]' ;;
  */pulls/6/commits) payload='[{"sha":"sha6","commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/6/comments|*/issues/6/comments) payload='[]' ;;

  # PR 7 — shared-repo false-positive 守門（AC-NEG1 精神）：在 head approve，
  # 但較晚的不相干 commit 把 committer.date bump 到 approval 之後。
  # commit_id == head.sha、head 未變 ⇒ 非 actionable（排除）。若用 committer-date 基準會誤判 needs_re_approve。
  */pulls/7/reviews) payload='[{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha7"}]' ;;
  */pulls/7/commits) payload='[{"sha":"sha7","commit":{"committer":{"date":"2026-05-06T23:00:00Z"}}}]' ;;
  */pulls/7/comments|*/issues/7/comments) payload='[]' ;;

  # PR 8 — APPROVED 但 commit_id 為 null → fail-closed stale → needs_re_approve（AC-NEG3）
  */pulls/8/reviews) payload='[{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z","commit_id":null}]' ;;
  */pulls/8/commits) payload='[{"sha":"sha8","commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/8/comments|*/issues/8/comments) payload='[]' ;;

  # PR 9 — #12475-like（AC2 / EC4）：先 APPROVED at head（commit_id == head.sha），
  # 之後夾一筆「較晚」的 COMMENTED 且其 commit_id 為 stale（不是 head）。沒有新 push。
  # 最新 review 雖是 COMMENTED，但最高效力 review 是 head 上的 valid APPROVED ⇒ 非 actionable。
  # 若只看「最新 review」會誤把它翻成 needs_re_review（Gap 2 的回歸）。
  */pulls/9/reviews) payload='[{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha9"},{"user":{"login":"reviewer"},"state":"COMMENTED","submitted_at":"2026-05-06T12:00:00Z","commit_id":"sha9-old"}]' ;;
  */pulls/9/commits) payload='[{"sha":"sha9","commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/9/comments|*/issues/9/comments) payload='[]' ;;

  # PR 10 — over-broaden 守門（AC-NEG1）：APPROVED 但 commit_id 為 stale（不是 head），
  # 之後夾一筆較晚的 COMMENTED。head 已移動（有新 push）。沒有任何 APPROVED at head ⇒
  # valid_approve_at_head=false，最新 COMMENTED + pushed ⇒ 仍正確列入 needs_re_review。
  # 確保 Gap 2 修正沒有把「stale APPROVED + interleaved COMMENTED」誤放成 valid。
  */pulls/10/reviews) payload='[{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha10-old"},{"user":{"login":"reviewer"},"state":"COMMENTED","submitted_at":"2026-05-06T12:00:00Z","commit_id":"sha10-old"}]' ;;
  */pulls/10/commits) payload='[{"sha":"sha10-new","commit":{"committer":{"date":"2026-05-06T11:00:00Z"}}}]' ;;
  */pulls/10/comments|*/issues/10/comments) payload='[]' ;;

  # PR 11 — >30-commit COMMENTED at real head（AC1）：reviewer 在當前 head COMMENTED、
  # 之後無新 push（commit_id == head.sha）。/pulls/11 物件回傳真 head sha11-head；
  # /commits 第一頁 .[-1] 故意設成 sha11-page1-not-head（>30 commit，head 在後面分頁），
  # 證明 head 取自 /pulls/N 而非 /commits 分頁。預期 waiting_for_author（排除）。
  */pulls/11/reviews) payload='[{"user":{"login":"reviewer"},"state":"COMMENTED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha11-head"}]' ;;
  */pulls/11/commits) payload='[{"sha":"sha11-page1-not-head","commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/11/comments|*/issues/11/comments) payload='[]' ;;

  # PR 12 — >30-commit APPROVED at real head（AC2）：reviewer 在當前 head APPROVED
  # （commit_id == head.sha），無新 push。/pulls/12 物件回傳真 head sha12-head；
  # /commits 第一頁 .[-1] 故意設成 sha12-page1-not-head，證明 head 取自 /pulls/N。
  # 預期 valid_approve（排除）。
  */pulls/12/reviews) payload='[{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z","commit_id":"sha12-head"}]' ;;
  */pulls/12/commits) payload='[{"sha":"sha12-page1-not-head","commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/12/comments|*/issues/12/comments) payload='[]' ;;

  # /pulls/N 物件（無 trailing path）→ .head.sha 投影（DP-355 canonical head 來源）。
  # exact pattern，永遠不會 shadow 上方 */pulls/N/{reviews,commits,comments}。
  */pulls/1) payload='{"head":{"sha":"sha1"}}' ;;
  */pulls/2) payload='{"head":{"sha":"sha2"}}' ;;
  */pulls/3) payload='{"head":{"sha":"sha3"}}' ;;
  */pulls/4) payload='{"head":{"sha":"sha4-new"}}' ;;
  */pulls/5) payload='{"head":{"sha":"sha5-new"}}' ;;
  */pulls/6) payload='{"head":{"sha":"sha6"}}' ;;
  */pulls/7) payload='{"head":{"sha":"sha7"}}' ;;
  */pulls/8) payload='{"head":{"sha":"sha8"}}' ;;
  */pulls/9) payload='{"head":{"sha":"sha9"}}' ;;
  */pulls/10) payload='{"head":{"sha":"sha10-new"}}' ;;
  */pulls/11) payload='{"head":{"sha":"sha11-head"}}' ;;
  */pulls/12) payload='{"head":{"sha":"sha12-head"}}' ;;
esac

if [[ -n "$jq_filter" ]]; then
  jq -r "$jq_filter" <<<"$payload"
else
  printf '%s\n' "$payload"
fi
MOCK
chmod +x "$mock_bin/gh"

candidates="$tmp/candidates.json"
cat > "$candidates" <<'JSON'
[
  {"repo":"demo","number":1,"title":"first","url":"https://github.com/acme/demo/pull/1","author":"alice","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":2,"title":"commented no push","url":"https://github.com/acme/demo/pull/2","author":"bob","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":3,"title":"changes no push","url":"https://github.com/acme/demo/pull/3","author":"carol","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":4,"title":"approved stale","url":"https://github.com/acme/demo/pull/4","author":"dan","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":5,"title":"changes replied with push","url":"https://github.com/acme/demo/pull/5","author":"erin","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":6,"title":"multiple reviews latest approved no push","url":"https://github.com/acme/demo/pull/6","author":"frank","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":7,"title":"approve at head later unrelated commit","url":"https://github.com/acme/demo/pull/7","author":"grace","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":8,"title":"approved null commit_id","url":"https://github.com/acme/demo/pull/8","author":"heidi","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":9,"title":"approved at head plus interleaved commented","url":"https://github.com/acme/demo/pull/9","author":"ivan","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":10,"title":"stale approve plus interleaved commented with push","url":"https://github.com/acme/demo/pull/10","author":"judy","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":11,"title":"over 30 commit commented at head no push","url":"https://github.com/acme/demo/pull/11","author":"kevin","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":12,"title":"over 30 commit approved at head","url":"https://github.com/acme/demo/pull/12","author":"laura","created_at":"2026-05-06T08:00:00Z"}
]
JSON

# 回歸斷言（既有 schema 不變）：actionable 集合與各 status 必須對齊 DP-315 前
# selftest 對 PR 1/4/5 的斷言，再加上 commit_id 基準的 PR 7（valid → 排除）
# 與 PR 8（null → needs_re_approve）。DP-312 Gap 2 再加：PR 9（#12475-like，valid
# APPROVED at head + interleaved COMMENTED → 排除，AC2/EC4）與 PR 10（stale APPROVED +
# interleaved COMMENTED + push → 仍 needs_re_review，AC-NEG1 over-broaden 守門）。
assert_actionable() {
  local out="$1"
  python3 - "$out" <<'PY'
# 斷言 actionable 清單與各 PR 的 review_status 是否符合預期
import json
import sys
from pathlib import Path

items = json.loads(Path(sys.argv[1]).read_text())  # 讀取 actionable 輸出
by_number = {item["number"]: item for item in items}
# PR 7、PR 9 排除（valid approve at head）；PR 8、PR 10 必須出現
# PR 7、9、11、12 排除（valid approve / waiting_for_author at real head）；
# PR 8、10 必須出現。PR 11/12 是 >30-commit case：head 取自 /pulls/N 而非 /commits
# 分頁，DP-355 修正前 head 會誤取自 /commits 第一頁非-head sha 而被錯列入 actionable。
if sorted(by_number) != [1, 4, 5, 8, 10]:
    raise SystemExit(f"unexpected actionable PRs: {sorted(by_number)}")
if by_number[1]["review_status"] != "needs_first_review":
    raise SystemExit("PR 1 should need first review")
if by_number[4]["review_status"] != "needs_re_approve":
    raise SystemExit("PR 4 should need re-approve (commit_id != head.sha)")
if by_number[5]["review_status"] != "needs_re_review":
    raise SystemExit("PR 5 should need re-review")
if by_number[8]["review_status"] != "needs_re_approve":
    raise SystemExit("PR 8 (null commit_id) should fail-closed to needs_re_approve")
if 9 in by_number:
    raise SystemExit("PR 9 (#12475-like valid APPROVED at head + interleaved COMMENTED) "
                     "must not be actionable")
if by_number[10]["review_status"] != "needs_re_review":
    raise SystemExit("PR 10 (stale APPROVED + interleaved COMMENTED + push) should still "
                     "need re-review (not falsely marked valid)")
if 11 in by_number:
    raise SystemExit("PR 11 (>30-commit COMMENTED at real head, no push) must not be "
                     "actionable — head must come from /pulls/N .head.sha, not /commits page 1")
if 12 in by_number:
    raise SystemExit("PR 12 (>30-commit APPROVED at real head) must not be actionable — "
                     "head must come from /pulls/N .head.sha, not /commits page 1")
PY
}

out_positional="$tmp/out-positional.json"
PATH="$mock_bin:$PATH" ORG=acme "$checker" reviewer < "$candidates" > "$out_positional"
assert_actionable "$out_positional"

out_flags="$tmp/out-flags.json"
PATH="$mock_bin:$PATH" "$checker" --my-user reviewer --org acme < "$candidates" > "$out_flags"
assert_actionable "$out_flags"

if PATH="$mock_bin:$PATH" "$checker" --my-user reviewer < "$candidates" >/dev/null 2>&1; then
  echo "missing org should fail" >&2
  exit 1
fi

# Grep guard（AC-NF1 / AC-NEG2）：approval-staleness 基準只能是 commit_id。
# consumer 內不得殘留 committer-date 比較，也不得殘留 head.repo.pushed_at。
guard_consumer="$script_dir/check-my-review-status.sh"  # 守門基準：僅 commit_id
if grep -nE 'committer\.date|last_commit_time' "$guard_consumer"; then
  echo "AC-NEG2 violation: committer-date staleness basis still present in consumer" >&2
  exit 1
fi
if grep -nE 'head\.repo\.pushed_at|pushed_at' "$guard_consumer"; then
  echo "AC-NEG2 violation: head.repo.pushed_at still present in consumer" >&2
  exit 1
fi
if ! grep -q 'approval_staleness' "$guard_consumer"; then
  echo "AC4 violation: consumer does not route through the shared approval_staleness helper" >&2
  exit 1
fi

echo "check-my-review-status selftest: PASS"
