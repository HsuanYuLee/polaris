## Codex

Codex 讀 `AGENTS.md`。這個 workspace 自己維護一份，`.agents/skills` 是指向
`.claude/skills` 的 symlink，所以 skill 兩邊看到的是同一份。產品 repo 根目錄的
`AGENTS.md` 屬於那個 repo，不由這裡安裝或修改。

**Codex 有 hook，這個 workspace 在 `.codex/hooks.json` 登記了兩支**：`block-git-hook-bypass`
（擋 `--no-verify`）與 `gate-ship-point`（併 PR、打 tag、送部署請求之前問那張單判過了沒）。
第一次在這個 repo 開 Codex 時，要在 `/hooks` 裡 review 並 trust 它們；`hooks.json` 改過之後
要再 trust 一次，沒 trust 的 hook 不會跑。其餘 hook 在 Codex 這邊仍然不存在，包含語言檢查——
送出回覆前自己確認 `workspace-config.yaml` 的 `language`。
