#!/usr/bin/env bash
# polaris-external-write-gate.sh — preflight gate for external write bodies.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: polaris-external-write-gate.sh --surface <surface> --body-file <path> [options]

Options:
  --surface NAME       jira-comment|jira-description|slack|confluence|github-review|github-comment|pr-body|release|artifact
  --body-file PATH     Materialized markdown/plain-text body to validate
  --mode MODE          Language policy mode. Default: artifact
  --blocking           Blocking language gate. Default
  --advisory           Advisory language gate
  --language LANG      Override workspace language
  --workspace-root DIR Root used by validate-language-policy.sh
  --starlight          Also run validate-starlight-authoring.sh check
  --writer-token TOKEN Registered external-write writer identity (or POLARIS_EXTERNAL_WRITE_WRITER)
  --tool-identity ID   Canonical external tool identity; required for github-review
  --payload-file PATH  Structured payload to validate; required for github-review
EOF
  exit 2
}

# **署名標記的宣告源。** 字串與適用範圍都在這裡，別處不重寫一份字面值——要用的人跑
# `--print-attribution-mark` 問它。兩份各自演化的字面值會讓「送出時加的那一句」與「讀的
# 那一端認的那一句」慢慢對不上，而對不上的那一刻沒有任何輸出說得出來。
#
# 帳號記的是誰送的，不記誰想的。用別人的帳號貼出去的東西，下一輪讀回來作者是那個人，
# 於是它變成那個人的意圖——2026-08 有一條六步的鏈就是這樣走完的：我寫的一則留言在下一輪
# 被抬成「規格權威」，蓋掉真正提單的人寫的東西。
#
# Slack 不在這張表上：那個管道自己就標著「Sent using @Claude」，再署一次是同一個資訊的
# 第二份，而它佔的是末尾最後被讀到的位置。
POLARIS_ATTRIBUTION_MARK="由 Claude Code 代發"
# **這份 body 是為哪一顆 PR 寫的。** 寫下它的是撰寫那份 review 的人，在他還知道自己在看
# 哪一顆的時候；送出的那一步不補、也補不了——2026-09-07 撞到的那一次，送出端填的
# --pull-number 是對的（3100），錯的是它讀到的檔（另一個並行 reviewer 剛覆蓋掉的 #10720）。
# 所以任何在送出時才由送出端填的錨都是從它自己的認知推導的，量不到這件事。
POLARIS_REVIEW_TARGET_PREFIX="<!-- polaris-review-target:"
POLARIS_ATTRIBUTED_SURFACES=(
  "github-review"
  "github-comment"
)
if [[ "${1:-}" == "--print-attribution-mark" ]]; then
  printf '%s\n' "$POLARIS_ATTRIBUTION_MARK"
  exit 0
fi

surface=""
body_file=""
mode="artifact"
enforcement="--blocking"
language=""
workspace_root=""
starlight=0
writer_token="${POLARIS_EXTERNAL_WRITE_WRITER:-}"
tool_identity=""
payload_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface)
      surface="${2:-}"
      shift 2
      ;;
    --body-file)
      body_file="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --blocking)
      enforcement="--blocking"
      shift
      ;;
    --advisory)
      enforcement="--advisory"
      shift
      ;;
    --language)
      language="${2:-}"
      shift 2
      ;;
    --workspace-root)
      workspace_root="${2:-}"
      shift 2
      ;;
    --starlight)
      starlight=1
      shift
      ;;
    --writer-token)
      writer_token="${2:-}"
      shift 2
      ;;
    --tool-identity)
      tool_identity="${2:-}"
      shift 2
      ;;
    --payload-file)
      payload_file="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$surface" || -z "$body_file" ]]; then
  usage
fi

case "$surface" in
  jira-comment|jira-description|jira-summary|slack|confluence|github-review|github-comment|pr-body|release|artifact)
    ;;
  *)
    echo "error: unsupported surface: $surface" >&2
    echo "supported: jira-comment jira-description jira-summary slack confluence github-review github-comment pr-body release artifact" >&2
    exit 2
    ;;
esac

if [[ ! -f "$body_file" ]]; then
  echo "error: body file not found: $body_file" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace="${workspace_root:-$(cd "$script_dir/.." && pwd)}"
language_gate="$workspace/scripts/validate-language-policy.sh"
starlight_gate="$workspace/scripts/validate-starlight-authoring.sh"

# 誰可以用這支關卡往外寫。這份宣告以前住在 repo 根目錄的 hooks 裡，而那支 hook 在
# DP-462 的 teardown 被移除（它沒有任何接點），關卡卻還在讀它——於是這支關卡從那一刻起
# 對每一次呼叫都回 REGISTRY_MISSING，也就是 canonical 的 submit path 整段跑不起來。
#
# 宣告搬到讀它的那支腳本自己身上，理由是可攜性：一支被單獨下載的 skill 沒有 hooks
# 目錄，指過去的路徑在那裡永遠解不出來。一份宣告只有一個家，而它的家是用它的地方。
POLARIS_EXTERNAL_WRITERS=(
  "review-pr:github-review"
  # 回一則 review thread 的純留言（更正、補充、回作者的問題）。這個 surface 一直都在
  # 支援清單裡、散文那一份也一直寫著它適用，缺的只有這一筆登錄——於是一個每天都在做的
  # 動作被 fail-closed 擋住，而擋住它的結果不是那個動作不發生，是它改走別的路：
  # 2026-09-04 那一次繞去 validate-language-policy.sh，那條路不做 surface 與 payload 檢查。
  # **一道擋住日常動作的閘，會把自己教成一道沒有人走的閘。**
  "review-pr:github-comment"
)

if [[ -z "$writer_token" ]]; then
  echo "POLARIS_EXTERNAL_WRITE_WRITER_REQUIRED: surface=$surface" >&2
  exit 2
fi

writer_registered=0
for registered_writer in "${POLARIS_EXTERNAL_WRITERS[@]}"; do
  [[ "$registered_writer" == "$writer_token" ]] && { writer_registered=1; break; }
done
if [[ "$writer_registered" -ne 1 ]]; then
  echo "POLARIS_EXTERNAL_WRITE_WRITER_UNREGISTERED: writer=$writer_token" >&2
  exit 2
fi

# writer token 形如 {skill}:{surface}；surface 段必須與 --surface 相符，避免註冊給某一個
# surface 的 writer 被拿去寫另一個。
# （原本由已退役的 transition registry 提供，改由 token 自身推導，不新增對照表。）
#
# **這條檢查以前只管 github-review。** 那時候表上只有一筆，所以「跨 surface 用」沒有第二個
# 目標可跨；表上一多一筆，那個前提就不成立了——`review-pr:github-review` 這個 token 可以
# 拿去寫 jira-comment，而沒有任何一步會問。所以登錄多一筆的同一輪要把它放大到每一個 surface。
if [[ "${writer_token##*:}" != "$surface" ]]; then
  echo "POLARIS_EXTERNAL_WRITE_WRITER_SURFACE_MISMATCH:writer=$writer_token:surface=$surface" >&2
  exit 2
fi

# 宣告在檔案開頭（那裡也開著 --print-attribution-mark 的口）。這裡只用它。
attribution_required=0
for attributed_surface in "${POLARIS_ATTRIBUTED_SURFACES[@]}"; do
  [[ "$attributed_surface" == "$surface" ]] && { attribution_required=1; break; }
done
if [[ "$attribution_required" -eq 1 ]] && ! grep -qF "$POLARIS_ATTRIBUTION_MARK" "$body_file"; then
  echo "POLARIS_EXTERNAL_WRITE_ATTRIBUTION_MISSING:surface=$surface" >&2
  echo "這個 surface 掛在一個人的帳號底下送出，所以內容要說出這是誰代誰發的。" >&2
  echo "body 裡要出現「${POLARIS_ATTRIBUTION_MARK}」，例如結尾接一行：" >&2
  echo "  _（${POLARIS_ATTRIBUTION_MARK}）_" >&2
  exit 2
fi

if [[ "$surface" == "github-review" ]]; then
  [[ -f "$payload_file" ]] || {
    echo "POLARIS_EXTERNAL_WRITE_PAYLOAD_REQUIRED:github-review" >&2
    exit 2
  }
  payload_text_file="$(mktemp -t polaris-external-write-review.XXXXXX.txt)"
  trap 'rm -f "$payload_text_file"' EXIT
  python3 - "$payload_file" "$body_file" "$payload_text_file" "$POLARIS_REVIEW_TARGET_PREFIX" <<'PY'
import json, re, sys
from pathlib import Path

def fail(detail):
    print(f"POLARIS_EXTERNAL_WRITE_PAYLOAD_INVALID:{detail}", file=sys.stderr)
    raise SystemExit(2)

try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception as exc:
    fail(str(exc))
REQUIRED_ROOT_KEYS = {"owner", "repo", "pull_number", "event", "body", "comments"}
# commit_id 是選擇性的，但它一旦在就必須是一顆完整的 sha：submit 端用它把 review 綁在
# reviewer 實際讀過的那一版上（DP-459）。預覽 payload 時可以還沒有這一格。
OPTIONAL_ROOT_KEYS = {"commit_id"}
if not isinstance(data, dict) or not REQUIRED_ROOT_KEYS <= set(data) <= REQUIRED_ROOT_KEYS | OPTIONAL_ROOT_KEYS:
    fail("root keys must be owner,repo,pull_number,event,body,comments[,commit_id]")
if "commit_id" in data and not re.fullmatch(r"[0-9a-f]{40}", str(data["commit_id"])):
    fail("commit_id must be a full 40-character sha")
if any(not isinstance(data.get(key), str) or not data[key].strip() for key in ("owner", "repo", "body")):
    fail("owner/repo/body must be non-empty strings")
if type(data.get("pull_number")) is not int or data["pull_number"] < 1:
    fail("pull_number must be a positive integer")
if data.get("event") not in {"APPROVE", "COMMENT", "REQUEST_CHANGES"}:
    fail("event is invalid")
if not isinstance(data.get("comments"), list):
    fail("comments must be an array")
allowed = {"path", "body", "line", "side", "start_line", "start_side"}
for index, comment in enumerate(data["comments"]):
    if not isinstance(comment, dict) or not set(comment).issubset(allowed):
        fail(f"comments[{index}] keys invalid")
    if not isinstance(comment.get("path"), str) or not comment["path"] or not isinstance(comment.get("body"), str) or not comment["body"]:
        fail(f"comments[{index}] path/body required")
    if type(comment.get("line")) is not int or comment["line"] < 1:
        fail(f"comments[{index}].line must be positive")
    if comment.get("side", "RIGHT") not in {"LEFT", "RIGHT"}:
        fail(f"comments[{index}].side invalid")
    has_start_line = "start_line" in comment
    has_start_side = "start_side" in comment
    if has_start_line != has_start_side:
        fail(f"comments[{index}] start_line/start_side must be paired")
    if has_start_line:
        if type(comment["start_line"]) is not int or comment["start_line"] < 1:
            fail(f"comments[{index}].start_line must be a positive integer")
        if comment["start_line"] >= comment["line"]:
            fail(f"comments[{index}].start_line must be less than line")
        if comment["start_side"] not in {"LEFT", "RIGHT"}:
            fail(f"comments[{index}].start_side invalid")
body_text = Path(sys.argv[2]).read_text(encoding="utf-8")
if data["body"] != body_text:
    fail("payload body does not equal gated body file")
# **這份 body 是為哪一顆 PR 寫的，由 body 自己說。** 上面那一條比的是 payload 與檔案，兩邊
# 都由送出的那一端在同一刻讀出來，所以它們一致證明不了內容屬於這顆 PR：另一個並行 reviewer
# 在 payload 造好之前就覆蓋掉那個檔的話，兩邊會一致地都是別顆 PR 的正文。
#
# 錨是 HTML 註解，GitHub 算繪時看不見，所以它跟著 body 送出去、留在那則 review 上，之後
# 還答得出「這份正文當初是為誰寫的」。
target_prefix = sys.argv[4]
matches = re.findall(re.escape(target_prefix) + r"\s*([^\s>]+?)/([^\s>]+?)#(\d+)\s*-->", body_text)
if not matches:
    fail(
        "body 沒有帶 review target 錨。撰寫 review 的人要在 body 第一行寫下他正在看的那一顆："
        f"{target_prefix} {data['owner']}/{data['repo']}#{data['pull_number']} -->"
    )
if len(set(matches)) > 1:
    fail(f"body 帶著不只一顆 PR 的 review target 錨：{sorted(set(matches))}")
anchor_owner, anchor_repo, anchor_number = matches[0]
if (anchor_owner, anchor_repo, int(anchor_number)) != (data["owner"], data["repo"], data["pull_number"]):
    fail(
        "這份 body 不是為這顆 PR 寫的："
        f"body 的錨說 {anchor_owner}/{anchor_repo}#{anchor_number}，"
        f"payload 要送去 {data['owner']}/{data['repo']}#{data['pull_number']}"
    )
combined = [body_text] + [comment["body"] for comment in data["comments"]]
Path(sys.argv[3]).write_text("\n\n".join(combined), encoding="utf-8")
PY
  body_file="$payload_text_file"
fi

if [[ ! -x "$language_gate" ]]; then
  echo "error: language validator not executable: $language_gate" >&2
  exit 2
fi

cmd=(bash "$language_gate" "$enforcement" --mode "$mode")
if [[ -n "$language" ]]; then
  cmd+=(--language "$language")
fi
if [[ -n "$workspace_root" ]]; then
  cmd+=(--workspace-root "$workspace_root")
fi
cmd+=("$body_file")
"${cmd[@]}"

case "$body_file" in
  */docs-manager/src/content/docs/specs/*.md|docs-manager/src/content/docs/specs/*.md)
    starlight=1
    ;;
esac

if [[ "$starlight" -eq 1 ]]; then
  if [[ ! -x "$starlight_gate" ]]; then
    echo "error: Starlight authoring validator not executable: $starlight_gate" >&2
    exit 2
  fi
  bash "$starlight_gate" check "$body_file"
fi

echo "PASS external write gate: $surface -> $body_file"
