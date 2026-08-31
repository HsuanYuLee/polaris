#!/usr/bin/env bash
# issue_destination.sh — 讀一張單宣告的 destination，只有這一份實作。
#
# 一張單的 `destination` 是人在第一關做的決定，寫在 `{單}/index.md` 的 frontmatter。
# 現在有兩個地方要問這件事：`gate-source-destination.sh`（宣告 workspace 的東西有沒有落在
# 會出去的位置）與 `release-version.sh`（一份留下來的 changeset 該不該算進「一張單一個版本」
# 的計數）。**同一個判斷寫兩次，兩份可以各自寫錯而沒有人發現**——守副本的閘比的是位元組，
# 看不見「同一件事被重寫一次而寫錯」。所以它在這裡，不在任何一個呼叫端裡。
#
# 只讀 frontmatter：正文裡的 `destination:` 是散文，不是宣告。
#
# 用法：source 這個檔，然後 read_issue_destination <index.md 的路徑>
# 印出：宣告的值（`workspace` / `template` / 任何寫錯的字串），或空字串
# 離場碼：0 讀到了一個非空的值／1 檔案不在、或 frontmatter 裡沒有這一格
#
# **離場碼不判對錯**：值認不認得由呼叫端決定，因為兩個呼叫端對一個認不得的值要做的事不同。

read_issue_destination() {
  local index="$1" value
  [[ -f "$index" ]] || return 1
  value="$(awk '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---"   { exit }
    inside && /^destination:[[:space:]]*/ {
      sub(/^destination:[[:space:]]*/, "")
      gsub(/[[:space:]]*(#.*)?$/, "")
      print
      exit
    }
  ' "$index")"
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}
