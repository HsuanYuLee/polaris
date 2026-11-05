# the commander's desk: a PR goes to "chase until merged"; the reviewer answers in a Slack DM thread
git branch -M main
cat > USER.md <<'MD'
使用者 17:50 原話：「#NNNN 〔reviewer〕 在看了，叫 work-25 追到併。」
MD
cat > STATUS.md <<'MD'
# PROJ-1156（PR https://github.com/acme-org/product-service/pull/NNNN，base feat/PROJ-963）

- 17:40 使用者在 Slack 私訊 〔reviewer〕 請他 review，那一串：https://acme.slack.com/archives/D0XXXX/p1700000000000000
- 17:45 〔reviewer〕 在那一串回「我看一下」。PR 上目前沒有 review、沒有留言。
- verify-ac 判定：head 8acaeab 過 3/4，未到站 1 條（PROD-P1 要到 prod）。
MD
cat > LAST-ORDER.md <<'MD'
（上一次派給 work-25 的「追一顆 PR 到併」指令，PROJ-1150）

追 https://github.com/acme-org/product-service/pull/MMMM 到併。每 5 分鐘量一次：mergeable、mergeStateStatus、
每個 check 的最新一筆、head 上的有效票。任一樣變了當下處理：有衝突就解，check 紅就查根因，pending 超過 20 分鐘就回報。
MD
cat > TASK.md <<'MD'
把你要送給 work-25 的指令全文寫進 ORDER.md。上一次的指令在 LAST-ORDER.md。
MD
git add -A
git commit -qm desk
