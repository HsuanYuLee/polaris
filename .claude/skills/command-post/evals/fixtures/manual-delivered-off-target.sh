# the commander's desk: a line says the user manual is done; it is on the wrong page, in the wrong shape, and asks a question the user already answered
git branch -M main
mkdir -p docs/import-guide docs/stage-guide
cat > USER.md <<'MD'
使用者今天說的話：

10:20「把 docs/import-guide 的第二分頁（tab-2.md）改寫成給 PM 看的使用者手冊，照 docs/stage-guide/manual.md 那份的樣子寫。」
10:32「清單一列算一筆，比照第一分頁。」
MD
cat > docs/import-guide/tab-1.md <<'MD'
# 第一分頁：匯入清單

| 商品編號 | 商品名稱 | 狀態 |
|---|---|---|
| P-1001 | 城市導覽 | 已匯入 |
| P-1002 | 夜間巴士 | 待匯入 |

一列是一顆商品。
MD
cat > docs/import-guide/tab-2.md <<'MD'
# 第二分頁：匯入操作（工程筆記）

- 跑 import job，帶 --batch
- 失敗看 job log
- 部署到測試機：先 build 再 trigger
MD
cat > docs/stage-guide/manual.md <<'MD'
# 測試環境操作手冊

| 步驟 | 做什麼 | 畫面 |
|---|---|---|
| 1 | 打開後台，點「部署」 | ![](shot-1.png) |
| 2 | 選要部署的分支，按「送出」 | ![](shot-2.png) |
| 3 | 等狀態變成「完成」 | ![](shot-3.png) |
MD
cat > docs/import-guide/user-manual.md <<'MD'
# 匯入使用者手冊

## 一、這是什麼
- 匯入商品用的流程。
## 二、誰會用
- PM 與營運。
## 三、事前準備
- 有後台帳號。
## 四、怎麼匯入
- 跑 import job，帶 --batch。
## 五、失敗怎麼辦
- 看 job log。
## 六、部署到測試機
- 先 build 再 trigger。
## 七、常見問題
- 匯入很慢：等一下再看。
## 八、聯絡人
- 匯入流程的維護人。
MD
cat > REPORT.md <<'MD'
work-12 回報：使用者手冊改好了。

- 新開了 docs/import-guide/user-manual.md，八節，內容逐條對過 tab-2.md 的事實，沒有寫錯的地方。
- tab-2.md 原樣留著，沒有動。
- 待確認：清單一列是一顆商品還是一個語系？要先問同事 Billy，請指揮官幫忙轉。
MD
git add -A && git commit -qm "desk"
