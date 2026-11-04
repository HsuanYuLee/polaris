# 施工線的現場（單與 TERMINAL.md 不進 commit：單本來就住在另一個 repo）：改動已 commit、已 push，push 之後才開 PR；驗證者在 push 那一刻問不到 PR，沒有派
git branch -M main
git remote add origin git@github.com:acme/workspace.git
T=issues/framework/in-progress/DP-NNN-gate-reads-tag-listing
mkdir -p $T/.spine src
echo 'print("v2")' > src/tool.py
git add -A && git commit -qm "base"
git checkout -qb feat/DP-NNN-gate-reads-tag-listing
echo 'print("v3")' > src/tool.py
git add -A && git commit -qm "DP-NNN：gate 讀 tag 清單"
H=$(git rev-parse HEAD)
cat > $T/index.md <<MD
# DP-NNN-gate-reads-tag-listing

<!-- POLARIS-FROZEN-A-BEGIN -->
- **A-P1**：gate 讀 tag 清單時，清單裡的每一行都被當成 tag 判。
<!-- POLARIS-FROZEN-A-END -->

## 施工紀錄
- 改動在 feat/DP-NNN-gate-reads-tag-listing，head ${H}。
MD
echo '{"schema_version":2,"rounds":[],"status":"open","station":"engineering","stop":null,"stops":[]}' > $T/.spine/loop-state.json
cat > TERMINAL.md <<MD
剛剛這個 session 跑過的兩條命令與輸出：

\$ git push -u origin HEAD
To github.com:acme/workspace.git
 * [new branch]      feat/DP-NNN-gate-reads-tag-listing -> feat/DP-NNN-gate-reads-tag-listing

\$ gh pr create --repo acme/workspace --base main --head feat/DP-NNN-gate-reads-tag-listing --title 'DP-NNN：gate 讀 tag 清單' --body-file pr.md
https://github.com/acme/workspace/pull/NNNN
MD
