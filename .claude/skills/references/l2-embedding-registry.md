# L2 Embedding Registry

Source-of-truth for DP-030 canary 下放：每個已腳本化的 mechanism 對應哪支 script、嵌進哪個 skill（L2）、哪個 hook fallback（L1）。`scripts/validate-l2-embedding.sh` 讀這份 registry 比對實際檔案，發現漏嵌或斷連會 exit 1。

> 來源：DP-030 BS#8（`specs/design-plans/DP-030-llm-to-script-migration/plan.md`）。Phase 1 POC 落地 `cross-session-carry-forward`（L2+L1）+ `no-cd-in-bash`（L1 only）。Phase 2B（2026-04-24, v3.53.0）加入三條 L1-only：`no-independent-cmd-chaining`、`max-five-consecutive-reads`、`no-file-reread`。Phase 2 逐 canary 擴充時必須同步更新這份 registry。

## Layer Legend

| Layer | 定義 |
|-------|------|
| `L2+L1` | Skill 內嵌 script call（primary）+ Claude Code hook fallback（skill bypass 兜底） |
| `L1-only` | 純 tool-use 檢查，與 skill flow 無關；只有 hook |
| `L2-only` | 只在 skill flow 內嵌，沒有 hook（罕見；需要理由） |

## 欄位語意

- **Canary** — `mechanism-registry.md` 對應 ID（即使 canary 已下移到 § Deterministic Quality Hooks 仍保留 ID 追蹤）
- **Script** — 實際檢查邏輯的 script 路徑（相對 repo root）
- **L2 Skill** — SKILL.md 路徑 + anchor（Step 標題字串）。`—` 表示無 L2 嵌入
- **L2 Expected Grep** — validator 在 SKILL.md 內 grep 的字串（通常是 script 路徑或 `check-{id}`）
- **L1 Hook** — hook script 路徑。`—` 表示無 hook
- **L1 Event / Matcher** — `settings.json` 註冊的 hook event + tool matcher
- **L1 Expected Grep** — validator 在 hook 檔案內 grep 的字串

## Entries

<!-- registry:start -->
| Canary | Script | Layer | L2 Skill | L2 Expected Grep | L1 Hook | L1 Event | L1 Matcher | L1 Expected Grep |
|--------|--------|-------|----------|------------------|---------|----------|------------|------------------|
| cross-session-carry-forward | scripts/check-carry-forward.sh | L2+L1 | .claude/skills/checkpoint/SKILL.md#Step 2.5 — L2 Deterministic Check: cross-session-carry-forward | scripts/check-carry-forward.sh | .claude/hooks/checkpoint-carry-forward-fallback.sh | PreToolUse | Write\|Edit | scripts/check-carry-forward.sh |
| no-cd-in-bash | scripts/check-no-cd-in-bash.sh | L1-only | — | — | .claude/hooks/no-cd-in-bash.sh | PreToolUse | Bash | scripts/check-no-cd-in-bash.sh |
| no-independent-cmd-chaining | scripts/check-no-independent-cmd-chaining.sh | L1-only | — | — | .claude/hooks/no-independent-cmd-chaining.sh | PreToolUse | Bash | scripts/check-no-independent-cmd-chaining.sh |
| max-five-consecutive-reads | scripts/check-consecutive-reads.sh | L1-only | — | — | .claude/hooks/consecutive-reads-monitor.sh | PostToolUse | Bash\|Edit\|Write\|Read\|Grep\|Glob\|Agent\|NotebookEdit | scripts/check-consecutive-reads.sh |
| no-file-reread | scripts/check-no-file-reread.sh | L1-only | — | — | .claude/hooks/no-file-reread-monitor.sh | PostToolUse | Read | scripts/check-no-file-reread.sh |
<!-- registry:end -->

## 新增條目的 Checklist

加新 canary 時，同一個 commit 內必須完成：

1. **Script** — `scripts/check-{canary-id}.sh` 實作完成且 `bash -n` pass
2. **L2 embed（若 Layer 含 L2）** — SKILL.md 內新增 Step 區段，按 `l2-script-conventions.md` 模板寫 retry budget + exit-code handling
3. **L1 hook（若 Layer 含 L1）** — `.claude/hooks/{hook-name}.sh` wrapper 寫好，呼叫同一支 `check-*.sh`
4. **`settings.json`** — PreToolUse / PostToolUse hook 已註冊（L1-only / L2+L1 都要）
5. **`mechanism-registry.md`** — 從原 section table 移除 canary，加到 § Deterministic Quality Hooks 表
6. **這份 registry** — 加入 entry；欄位名稱必須與實際檔案一致（validator 會 grep）
7. **Validator 自測** — 本地跑 `bash scripts/validate-l2-embedding.sh` → exit 0

## 常見錯誤

- **L2 Expected Grep 太鬆** — 只寫 `check` 會 match 多支 script，改用完整路徑 `scripts/check-{id}.sh`
- **Anchor 改了沒同步** — SKILL.md 的 Step 標題若改字，registry 的 anchor 要一起改；validator 抓不到 anchor 會 FAIL
- **Hook 檔名含路徑 `/`** — registry 的表格 cell 用 `/`（如 `scripts/check-*.sh`），別寫成絕對路徑（validator 以 repo root 當 base）
- **漏寫 L1 Expected Grep** — hook wrapper 不呼叫對應 script（例：改名沒同步）→ validator 會抓到

## References

- DP-030 plan: `specs/design-plans/DP-030-llm-to-script-migration/plan.md`
- Script conventions: `skills/references/l2-script-conventions.md`
- Validator: `scripts/validate-l2-embedding.sh`
- `/validate` integration: `.claude/skills/validate/SKILL.md` § Mechanisms check #11
