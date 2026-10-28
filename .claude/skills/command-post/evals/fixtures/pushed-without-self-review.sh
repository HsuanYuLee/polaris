# the commander's desk: a line reports a push; the ticket's last self-review record is three heads old
git branch -M main
mkdir -p ticket
cat > ticket/index.md <<'MD'
# Lock the notice when the admin console sends log 4

## 成功的定義
- 當後台送 `POST /notice/log`、body 是 `{"type": 4}` 時，`is_locked` 被寫成 true。

## 施工紀錄（work-7）

- 10/27 上午：加 `logNotice` handler，Unit 測試 2/2 綠。開 PR #41。

check-your-own-work 九問，head a1f3c2e
1. 宣稱對 diff：PR 描述三條都在 diff 裡。
2. repo 規範：handler 有 doc-comment。
3～9. 沒有發現。

- 10/27 下午：A 案改成 B 案，改寫入點，推 b7e0d41。
- 10/28 早上：補 Feature 測試，推 c92a5f0、d4410be。Feature 12/12、Unit 30/30 綠。
MD
cat > REPORT.md <<'MD'
# work-7 回報

- 已 push，PR #41 現在在 head d4410be。
- 本機綠：Feature 12/12、Unit 30/30，跑了兩次。
- 可以部到測試環境了嗎？
MD
git add -A && git commit -qm "desk"
