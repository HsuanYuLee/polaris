#!/bin/bash
set -eo pipefail

# ─── JIRA Attachment Uploader ───
# Uploads file(s) to a JIRA issue and returns attachment metadata (id, filename, url).
# Shared across skills (VR screenshots, evidence reports, design docs).
#
# Usage:
#   jira-upload-attachment.sh <issue-key> <file> [file2 ...]
#   jira-upload-attachment.sh --print-target <issue-key>   # 只印 "site<TAB>account"，不送任何東西
#   jira-upload-attachment.sh TASK-3653 /tmp/screenshot.png
#   jira-upload-attachment.sh EPIC-483 ./diff-homepage-desktop.png ./diff-homepage-mobile.png
#
# Output (JSON per file, one per line):
#   {"filename":"screenshot.png","id":"12345","url":"…/rest/api/3/attachment/content/12345"}
#
# Env:
#   JIRA_USERNAME / JIRA_EMAIL — Atlassian account identifier；兩個名字都認，因為兩個名字
#                                都真的在用（環境變數叫前者，.env.secrets 裡寫的是後者）。
#   JIRA_API_TOKEN             — Atlassian API token
#   JIRA_SITE                  — 覆寫站台位址。**沒有預設值**：見下。
#
# 站台位址從「認得這張單前綴的那一份」workspace-config.yaml 的 `jira.instance` 來，那裡本來
# 就是它的權威。這裡以前預設成 `https://example.atlassian.net`——一個預設的站台位址會把附件
# POST 到一個沒有人擁有的主機，而那條路上沒有任何一步會說「你沒設站台」，只會回一個看起來
# 像網路問題的錯誤。問不到就停下來並說出去哪裡設。
#
# Secrets file auto-detection:
#   Searches for .env.secrets in $POLARIS_COMPANY_DIR and workspace company dirs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 往上逐層找，不寫死層數：這支 skill 在頂層還有一份 symlink，兩條路徑的深度不一樣。以前
# 寫的是 `$SCRIPT_DIR/..`（＝ skill 自己的目錄），底下不會有任何一個 workspace-config.yaml，
# 於是這一整段候選清單永遠是空的——一個搬家留下的洞，執行期才會炸。
candidate_company_dirs() {
  [[ -n "${POLARIS_COMPANY_DIR:-}" ]] && printf '%s\n' "$POLARIS_COMPANY_DIR"

  local dir="$SCRIPT_DIR" cfg
  while [[ "$dir" != "/" ]]; do
    for cfg in "$dir"/*/workspace-config.yaml; do
      [[ -f "$cfg" ]] || continue
      # `_template/` 那份講的是別人將來的 repo：project key 是佔位的 `PROJ`、站台是佔位的
      # `your-domain.atlassian.net`。讓它參與比對就是把「找到了但找錯」從另一扇門放回來。
      [[ "$(basename "$(dirname "$cfg")")" != "_template" ]] || continue
      dirname "$cfg"
    done
    dir="$(dirname "$dir")"
  done
}

# ── Load credentials ──
load_credentials() {
  # 環境變數已經給了就用它。兩個名字都認：這台機器上叫 JIRA_USERNAME，而 .env.secrets 的
  # 慣例是 JIRA_EMAIL。以前只認後者，於是即使憑證就在環境裡，它也一定走進下面那條分支。
  JIRA_ACCOUNT="${JIRA_USERNAME:-${JIRA_EMAIL:-}}"
  if [[ -n "$JIRA_ACCOUNT" && -n "$JIRA_API_TOKEN" ]]; then return 0; fi

  local dir
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    local secrets="$dir/.env.secrets"
    if [[ -f "$secrets" ]]; then
      # shellcheck disable=SC1090
      source "$secrets"
      JIRA_ACCOUNT="${JIRA_USERNAME:-${JIRA_EMAIL:-}}"
      [[ -n "$JIRA_ACCOUNT" && -n "$JIRA_API_TOKEN" ]] && return 0
    fi
  done < <(candidate_company_dirs | awk '!seen[$0]++')

  # 說出找了哪幾個名字、以及環境裡實際有的是哪幾個。一句「credentials not found」讓人
  # 沒辦法分辨「我沒設」與「我設的名字跟它找的不一樣」，而後者正是這支腳本壞了兩個月的原因。
  echo "ERROR: JIRA credentials not found." >&2
  echo "  looked for: JIRA_USERNAME or JIRA_EMAIL, plus JIRA_API_TOKEN" >&2
  echo "  actually set in this environment: $(env | grep -o '^JIRA_[A-Z_]*' | sort | tr '\n' ' ')" >&2
  echo "  or create .env.secrets in one of: $(candidate_company_dirs | awk '!seen[$0]++' | tr '\n' ' ')" >&2
  return 1
}

# ── Resolve the site from the config that knows THIS ticket ──
#
# 判準是「哪一份設定的 jira.projects[].key 認得這張單的前綴」，不是「哪一份先被列到」。
# 一棵樹上有四份 workspace-config.yaml，而依字母序最先命中的是 `_template/` 那份範本
# （instance 寫著佔位的 `your-domain.atlassian.net`、project key 寫著 `PROJ`）。取第一個
# 的那一版會回一個看起來完全正常的錯站台——DP-511 踩過兩次的同一個形狀。
resolve_site() {
  local issue_key="$1"
  if [[ -n "${JIRA_SITE:-}" ]]; then
    printf '%s\n' "${JIRA_SITE%/}"
    return 0
  fi
  local prefix="${issue_key%%-*}"
  local instance
  instance="$(candidate_company_dirs | awk '!seen[$0]++' | python3 -c "
import re, sys
prefix = sys.argv[1]
for line in sys.stdin:
    directory = line.strip()
    if not directory:
        continue
    try:
        text = open(directory + '/workspace-config.yaml', encoding='utf-8').read()
    except OSError:
        continue
    # 只讀 jira 區塊：頂層另外還有一個 projects:，把它讀進來會讓前綴比對對上別的東西。
    block = re.search(r'^jira:\n(.*?)(?=^\S)', text, re.S | re.M)
    if not block:
        continue
    keys = re.findall(r'^\s+-\s+key:\s*\"?([A-Za-z0-9_]+)', block.group(1), re.M)
    if prefix not in keys:
        continue
    found = re.search(r'^\s+instance:\s*\"?([^\"\s#]+)', block.group(1), re.M)
    if found:
        print(found.group(1))
        break
" "$prefix" 2>/dev/null)"
  if [[ -z "$instance" ]]; then
    echo "ERROR: JIRA site unknown — no workspace-config.yaml lists project key '$prefix' under jira.projects." >&2
    echo "  fix: add it to the workspace-config.yaml of the company this ticket belongs to," >&2
    echo "       or pass JIRA_SITE explicitly. There is no default: a default site silently POSTs" >&2
    echo "       attachments at a host nobody owns." >&2
    return 1
  fi
  case "$instance" in
    http://*|https://*) printf '%s\n' "${instance%/}" ;;
    *) printf 'https://%s\n' "${instance%/}" ;;
  esac
}

# ── Upload a single file ──
upload_file() {
  local issue_key="$1" filepath="$2" site="$3"
  local filename; filename="$(basename "$filepath")"

  if [[ ! -f "$filepath" ]]; then
    echo "ERROR: File not found: $filepath" >&2
    return 1
  fi

  local response
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -u "$JIRA_ACCOUNT:$JIRA_API_TOKEN" \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@$filepath" \
    "$site/rest/api/3/issue/$issue_key/attachments" 2>/dev/null)

  local http_code; http_code=$(echo "$response" | tail -1)
  local body; body=$(echo "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    echo "ERROR: Upload failed (HTTP $http_code) for $filename: $body" >&2
    return 1
  fi

  # Parse response — JIRA returns array of attachment objects
  echo "$body" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for att in data:
    print(json.dumps({
        'filename': att['filename'],
        'id': att['id'],
        'url': att['content'],
        'thumbnail': att.get('thumbnail', ''),
        'mimeType': att.get('mimeType', ''),
    }))
" 2>/dev/null
}

# ── Main ──
main() {
  # 站台與憑證的權威在這裡，只有這裡。要往同一個 issue 貼留言的呼叫者問這一個模式，
  # 不要自己再算一次——兩份會漂，而漂掉的那一次會把東西送到另一個地方。
  if [[ "${1:-}" == "--print-target" ]]; then
    [[ -n "${2:-}" ]] || { echo "Usage: $0 --print-target <issue-key>" >&2; exit 1; }
    load_credentials || exit 1
    local target; target="$(resolve_site "$2")" || exit 1
    printf '%s\t%s\n' "$target" "$JIRA_ACCOUNT"
    return 0
  fi

  if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <issue-key> <file> [file2 ...]" >&2
    exit 1
  fi

  local issue_key="$1"; shift

  load_credentials || exit 1
  local site; site="$(resolve_site "$issue_key")" || exit 1

  local success=0 fail=0
  for filepath in "$@"; do
    if upload_file "$issue_key" "$filepath" "$site"; then
      success=$((success + 1))
    else
      fail=$((fail + 1))
    fi
  done

  echo "---" >&2
  echo "Uploaded: $success, Failed: $fail (site $site)" >&2
  [[ $fail -eq 0 ]] || exit 1
}

main "$@"
