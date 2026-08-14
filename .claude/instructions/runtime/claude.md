## Claude Code

Claude Code 把這個檔當作第一段 context，每次壓縮後會重新注入。它要保持薄——這裡只放
身分、入口與判斷順序，細節在各支 skill 自己的目錄裡。

**最終回覆也受語言規則管。** hook 只在 tool call 上觸發，攔得到寫檔，攔不到你講的話。
送出任何回覆前自己確認 `workspace-config.yaml` 的 `language`，並且從第一句就用那個語言寫，
不要先寫英文再翻。
