# the commander's desk: a line answered "can we do it" with a recommended route; the user then said "do it"
git branch -M main
mkdir -p ticket
cat > USER.md <<'MD'
使用者原話（11/04）：

10:56「昨天 〔PM〕 提出希望可以做到，過去曾經從 svc-a 匯出主語系的商品，也要有鎖定，這做得到嗎？」
11:01「〔PM〕 的意思是，他提的新條件，我們能不能朔及既往，這應該沒有違背新需求」
11:03「可以，還有這應該是加鎖對吧？」
MD
cat > JOURNAL.md <<'MD'
### 2026-11-04 10:56 ｜ 回覆 ｜ 指揮官
- 給：work-25
- 內容：使用者問能不能，先查根據，不動 code、不重簽。回我：
1. 認得出來嗎：svc-a export_logs 能不能撈出「主語系、匯出成功」的 product_oid 清單。
2. 幾顆。
3. 怎麼回填：兩條路各寫做法與風險——(a) data-modify：svc-a 唯讀 SELECT 撈清單 → product DB UPDATE product_config（跨兩個 DB，要兩張單）；(b) 用 PROJ-1156 保留的批次 API PUT product-configs/core-content-lock。
4. 爆炸半徑。
5. 跟 #NNNN 的關係：要不要改 code。

### 2026-11-04 11:00 ｜ 紀錄 ｜ work-25
- 發生什麼：回：回填做得到、不改 code；全部讀 code 沒量 prod。export_logs join export_items.status=3 join documents.master_lang 認得出（會少算後段失敗的；換過主語系判錯；2019-10 前判不出）。回填建議走批次 API PUT product-configs/core-content-lock（有 log、刷 cache、1000 顆一批、查無整批回滾）。順序：要等 #NNNN 上 prod 之後，否則 v2.98.0 鎖法連 scm/psp 一起擋。幾顆要 prod SELECT 才有數字
MD
cat > ticket/index.md <<'MD'
# PROJ-1156 主語系匯出成功時鎖定商品核心內容（PR #NNNN）

## 成功的定義（凍結）
- A-P1：主語系匯出成功 → is_core_content_locked=true。
- A-N4：上線前已匯出過的商品不回填。（11/03 RD 草案寫的）

## 跟 〔PM〕 確認過的（已決）
- 新匯出、主語系匯出成功才鎖。
- 上線前已匯出過的不回填。
MD
git add -A && git commit -qm "desk"
