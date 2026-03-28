# PR & Review 規則

## PR 建立
- **PR 建立後自動轉 JIRA 為 CODE REVIEW**：不需使用者手動操作
- **PR 建立後自動掛 `need review` label**：`gh pr create` 完成後執行 `gh pr edit <number> --add-label "need review"`
- **品質檢查未通過不發 PR**：測試失敗或覆蓋率不足時，先補測試再繼續
- **改 code 並 push 前必跑 `dev-quality-check`**：品質檢查統一走此 skill，不在各 skill 各自寫驗證邏輯
- **改動程式碼不能降低整體覆蓋率**：Codecov `project` check 要求覆蓋率不低於 base branch（threshold 1%）
- **Pre-push 品質閘門（hook 強制）**：`.claude/hooks/pre-push-quality-gate.sh` 攔截 `git push`，檢查 `dev-quality-check` 是否已通過（marker file `/tmp/.quality-gate-passed-{branch}`）。未通過則阻擋 push。主要 branch（main/master/develop）不攔截。Marker 24 小時後過期

## Review
- **禁止 self-review 自己的 PR**：無論任何情境（fix-bug、fix-pr-review、發 PR 後），都不可對自己的 PR 提交 GitHub review comment。Review 只用於審查他人的程式碼
- **PR 提交 review / re-review 前先 rebase**：fix-pr-review 流程開始時先 rebase base branch 再修正；review-pr / git-pr-workflow 發出 review request 前也要 rebase
- **Review 完附上 PR approve 狀況**：review-pr 完成後回報「目前 X/2 approves，還需 Y 個」或「已達 2 approves，可以 merge」
- **Pre-PR review loop 最多 3 rounds**：超過 3 輪仍有 blocking issues，列出剩餘問題詢問使用者
- **每個 review comment 都必須回應**：不論是否修正，都要回覆（已修正 / 不修正原因 / 需討論）
