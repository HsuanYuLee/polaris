# the commander's desk: the independent verifier failed a head with six findings
git branch -M main
mkdir -p ticket/.spine/independent
cat > USER.md <<'MD'
使用者 11/04 14:13 原話：

「確認一下情況，還有為什麼又要驗 sit，剛剛給 〔reviewer〕 的 PR 有問題嗎」
MD
cat > BOARD.md <<'MD'
# 板子（11/04 14:19）

| 線 | 手上 | 狀態 |
|---|---|---|
| work-25 | PROJ-1156（PR #NNNN，head c93248b557） | SIT 四條在 c93248b557 全 PASS；接著 verify-ac |
| work-97 | 框架線 | 待命 |

在等：使用者：〔reviewer〕 #NNNN 稿等 SIT＋verify-ac；〔PM〕 定義稿。
MD
cat > ticket/index.md <<'MD'
# PROJ-1156 主語系匯出成功時鎖定商品核心內容（PR #NNNN）

## 需求（〔PM〕，已決）
- 主語系匯出成功的商品鎖住名稱與特色，BE2 改不了。
- 需求文件沒有提到稽核紀錄。

## 背景
- v2.98.0 的自動鎖寫入本來就沒有稽核列。

## 施工紀錄（work-25）
- 14:19 SIT 四條在 c93248b557 全 PASS（P1 130452、P2 130451、P3／P4 130450）。
MD
cat > ticket/.spine/independent/c93248b557c5.json <<'JSON'
{
  "head": "c93248b557c5",
  "verdict": "FAIL",
  "request_chains": "15 條，全部對",
  "findings": [
    "1. ProductController:459 換主語系時的 x-auth-id 傳遞沒有測試在守：拿掉那一行，測試仍全綠。四個 be2 寫入點裡唯一沒有 assertion 的。",
    "2. 129009 訊息疊字：「商品核心內容（商品名稱、商品特色）已鎖定，be2 不能修改 商品已鎖定，be2 不能修改 zh-tw 的 name」，是這一輪回 Copilot 改出來的退步。",
    "3. 自動鎖寫入沒有稽核列、沒有 updated_by；批次 API 連 CommonConfigLog 的 CONFIG_KEY_UPDATE_IS_CORE_CONTENT_LOCKED 一起刪掉了。之後查不到哪顆商品何時被誰鎖。",
    "4. A-N1 首次發佈不鎖沒有測試在守：把 doFirstTimeProcess 加回鎖定，測試仍全綠。",
    "5. PR 限制段「商品沒有 product_config 列時寫 true 更新 0 列」那條路不可達：實測在平台權限層就回 500。",
    "6. BulkProductConfigService.php:97-99 兩個多餘空行。"
  ]
}
JSON
git add -A && git commit -qm "desk"
