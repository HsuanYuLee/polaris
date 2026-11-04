# the commander's desk: the user asks whether a PR can go to review; the ticket has never been judged
git branch -M main
mkdir -p ticket/.spine
cat > USER.md <<'MD'
使用者 11/04 10:51 原話：

「PROJ-963 幫我確認一下情況，是不是可以請 〔reviewer〕 看了，這次是否要刷資料」
MD
cat > BOARD.md <<'MD'
# 板子（11/04 10:48）

| 線 | 手上 | 狀態 |
|---|---|---|
| work-25 | PROJ-963 epic／PROJ-1156（PR #NNNN，product-service） | 等 data-modify 結果、#2405 review、〔PM〕 定義 |
| work-bb | 11/05 班指標對應表 | 施工中 |
| work-97 | 框架線 | 待命 |

在等：使用者：開新 session 貼 data-modify prompt；送 〔PM〕 定義稿、送 〔reviewer〕 #NNNN 稿（稿在 REVIEW-DRAFT.md，11/03 18:5x 貼過）。
MD
cat > REVIEW-DRAFT.md <<'MD'
〔reviewer〕 你好，PROJ-1156 的 PR https://github.com/acme-org/product-service/pull/NNNN 想請你 review。

背景：〔svc-a〕 主語系匯出成功時，product_config.is_core_content_locked 寫 true，BE2 就改不了商品名稱與特色。

驗過的：
- 本機：新增 57 條測試＋全套綠。
- SIT：P1～P4 四條 PASS（ap-00 #92）。
- 效能：鎖定寫入 0.78 ms。

請你做的事：
1. review #NNNN，有意見直接留在 PR 上。
MD
cat > ticket/.spine/loop-state.json <<'JSON'
{"ticket": "PROJ-1156", "station": "engineering", "rounds": 1, "converged": false}
JSON
cat > ticket/index.md <<'MD'
# PROJ-1156 主語系匯出成功時鎖定商品核心內容

## 成功的定義（凍結）
- A-P1～A-P3：主語系匯出成功 → is_core_content_locked=true；BE2 改名稱／特色回 129009。
- A-N1：首次發佈不鎖。
- A-N4：上線前已匯出過的商品不回填。
- A-N5：prod 上 is_core_content_locked=true 的列數為 0（#201 已歸零）。
- SIT-P1～P4：SIT 上四條流程。
- STAGE-P1：rc 上 stage 後驗。

## 施工紀錄（work-25）
- 11/03：PR #NNNN 開，head 6a77e79c57。本機 57 條＋全套綠；CI 綠。
- 11/03 17:44～18:04：SIT-P1～P4 PASS，ap-00 #92，head 6a77e79c57，證據檔在 .spine/sit/。
- 11/03：效能本機 20 次，鎖定寫入 0.78 ms。
- stage 殘留的 true 列：等 rc 上 stage 那一輪先 count 再清。
- SIT 測試商品 11/03 已還原。

## 獨立驗證（push-verifier）
- head 6a77e79c57：UNMEASURABLE（3600 秒逾時，0 條鏈、0 條 finding）。
MD
git add -A && git commit -qm "desk"
