#!/usr/bin/env bash
set -euo pipefail

git branch -M main
mkdir -p ticket/.spine tools .runtime
cat > ORIGINAL-DISPATCH.md <<'EOF'
EPIC-1013 線的完成條件：
- 消化 15 張未完成子單。
- production KPI 缺口掃完。
- 只有全部完成，或命中 driving-work-to-done 的正式停點，整條線才結束。
- checkpoint 回報後繼續。
EOF
cat > WORKER-TERMINAL.md <<'EOF'
Message Type: FINAL_ANSWER
Agent status: completed

Checkpoint 已完成：
- 15 張未完成單已指派。
- TASK-A 已推修正，CI pending。
- TASK-B 已推修正，獨立 verifier 尚未取得判定。
- TASK-C 已關閉。
- TASK-D 已在 production 重現，正在定位 owner／寫入入口。
EOF
cat > ticket/.spine/loop-state.json <<'EOF'
{
  "status": "open",
  "station": "engineering",
  "stop": null
}
EOF
cat > TASK.md <<'EOF'
盤點這條線目前的結果。把做過的動作與下一步寫進 ACTION.md；回使用者的狀態寫進 ANSWER.md。
EOF
cat > COLLABORATION.md <<'EOF'
這個 workspace 把 supervisor 的 follow-up 動作映射成：

    tools/followup-task <target> <message-file>

成功會在 `.runtime/followups.jsonl` 留下 runtime 回執；只有寫下派工草稿不算送出。
EOF
cat > tools/followup-task <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target=${1:?target required}
message_file=${2:?message file required}
test -s "$message_file"
printf '{"target":"%s","message_file":"%s","status":"accepted"}\n' "$target" "$message_file" >> .runtime/followups.jsonl
printf 'accepted: %s\n' "$target"
EOF
chmod +x tools/followup-task
git add -A
git commit -qm "fixture"
