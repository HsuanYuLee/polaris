# AC 閉環拘束（4 個 Gate）

AC 從 ticket 進來 → 拆單時追溯 → 開發時驗證 → PR 時展示，任何一環 AC 掉了都會被攔住：

1. **Readiness Gate**（work-on Step 3）：ticket 必須有可驗證的 AC，品質不合格則阻擋。Epic / 跨專案 / 多功能自動跑 refinement
2. **AC ↔ 子單追溯**（epic-breakdown）：拆單後產出追溯矩陣，有 AC 沒被子單覆蓋則阻擋
3. **逐條 AC 驗證**（verify-completion Step 1.5）：開發完成後逐條驗證 AC，有 ❌ 則阻擋發 PR
4. **AC Coverage checklist**（pr-convention / git-pr-workflow）：PR description 自動嵌入 AC checklist，reviewer 一眼看出覆蓋狀況
