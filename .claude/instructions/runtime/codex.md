## Codex

Codex 讀 `AGENTS.md`。這個 workspace 自己維護一份，`.agents/skills` 是指向
`.claude/skills` 的 symlink，所以 skill 兩邊看到的是同一份。產品 repo 根目錄的
`AGENTS.md` 屬於那個 repo，不由這裡安裝或修改。

**Codex 沒有 hook。** 任何靠 hook 擋下來的東西在 Codex 這邊都不存在，包含語言檢查。
送出回覆前自己確認 `workspace-config.yaml` 的 `language`。
