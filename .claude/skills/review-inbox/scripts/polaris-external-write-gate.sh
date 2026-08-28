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

if [[ "$surface" == "github-review" ]]; then
  # writer token 形如 {skill}:{surface}；surface 段必須與 --surface 相符，
  # 避免註冊給其他 surface 的 writer 被拿來送 GitHub review。
  # （原本由已退役的 transition registry 提供，改由 token 自身推導，不新增對照表。）
  if [[ "${writer_token##*:}" != "$surface" ]]; then
    echo "POLARIS_EXTERNAL_WRITE_WRITER_SURFACE_MISMATCH:writer=$writer_token:surface=$surface" >&2
    exit 2
  fi
  [[ -f "$payload_file" ]] || {
    echo "POLARIS_EXTERNAL_WRITE_PAYLOAD_REQUIRED:github-review" >&2
    exit 2
  }
  payload_text_file="$(mktemp -t polaris-external-write-review.XXXXXX.txt)"
  trap 'rm -f "$payload_text_file"' EXIT
  python3 - "$payload_file" "$body_file" "$payload_text_file" <<'PY'
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
