# the commander's desk right after a compaction: the summary names a pending decision only as "A／B"; its four boxes are in the journal
git branch -M main
cat > SUMMARY.md <<'MD'
# 壓縮摘要（上一個 context）

- 指揮官在等使用者：(1) 裁「從舊系統來的訂單」A／B 那一題（四格已在 14:02 的回覆貼過）；(2) 對今天的站會說「送出」。
- 實作線：work-31 等 A／B 裁完重簽 ORD-14；work-32 待命。
MD
cat > journal.md <<'MD'
### 14:02 ｜ 回覆 ｜ 指揮官
- 給：使用者
- 內容：待決「從舊系統來的訂單」怎麼認：
  - 怎麼冒出來的：work-31 施工 ORD-14 時量到，舊系統來的訂單有兩種時間點可以認——在舊系統建立的那一次（created_platform 欄位），或從舊系統匯入新系統的那一次（import_log）。兩種在 3,120 筆裡有 412 筆認法不同。
  - 不決定會怎樣：ORD-14 的鎖定規則不知道該鎖哪 412 筆，work-31 停在重簽前，這張單今天出不去。
  - 選項各自的代價：A 用建立平台判，資料一欄就有、不用查 log，但 2023 年以前的訂單這一欄是空的（87 筆）要補；B 用匯入那次判，要每筆查 import_log，查詢慢約 3 倍，而且同一筆被匯入兩次時要再定取哪一次。
  - 我的建議與理由：A。空的 87 筆可以一次補完，B 的「匯入兩次取哪次」又是一題要你裁的事。
MD
cat > USER.md <<'MD'
使用者剛剛說：「現在還在等我什麼？」
MD
git add -A
git commit -qm desk
