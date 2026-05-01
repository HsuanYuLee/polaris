---
name: git-pr-workflow
description: >
  Admin-role delivery skill for framework/docs repos. Executes the full engineer delivery flow
  (simplify → quality → behavioral verify → review → rebase → commit → PR) without JIRA ceremony.
  Trigger: '發 PR', 'open PR', 'create PR', 'PR workflow', '準備發 PR'.
  For product repos with JIRA tickets, use engineering instead.
  PR body logic is in references/pr-body-builder.md (shared by both roles).
tier: meta
admin_only: true
metadata:
  author: Polaris
  version: 4.0.0
---

# git-pr-workflow (v4.0.0) — Admin Delivery Entry

**用途：** 框架、docs、通用 repo 的 PR 生命週期自動化。v4.0.0：execution backbone 抽出到 `references/engineer-delivery-flow.md`，本 skill 僅負責 Admin 角色的輸入解析和路由。

**角色：Admin**（框架維護者）— 豁免 JIRA ticket、task.md、planning ceremony。**不豁免** execution discipline（simplify / quality / verify / review 照跑）。

**產品 repo 禁用**：在產品 repo（kkday-b2c-web、member-ci 等）觸發時，skill-routing 會引導使用者改用 `engineering`。

---

## 適用場景

| 適用 | 不適用 |
|------|--------|
| Polaris 框架自身（`~/work/`） | 產品 repo（走 `engineering`） |
| 通用 docs / template repo | 有 JIRA ticket 的開發（走 `engineering`） |
| 無 ticket 的 hotfix / cleanup | 需要 task.md 的計劃性開發 |

---

## Step 1：Branch（若尚未建立）

若當前在 `main` 且有 uncommitted changes：

```bash
git create-branch --ci
```

或依 `references/branch-creation.md` 手動建分支。

若已在 topic branch → 跳過。

---

## Step 2：Execute Engineer Delivery Flow

讀取 `references/engineer-delivery-flow.md`，以 **Role: Admin** 執行 Step 1-7：

| Delivery Flow Step | Admin 行為 |
|-------------------|-----------|
| Step 1 Simplify | ✅ 正常執行 |
| Step 2 Quality Check | ✅ 正常執行 |
| Step 3 Behavioral Verify | ✅ Layer A 正常執行；Layer B 跳過（無 task.md） |
| Step 4 Pre-PR Review | ✅ 正常執行 |
| Step 5 Rebase | ✅ 正常執行（base = upstream 或 `origin/main`） |
| Step 6 Commit + Changeset | ✅ commit 正常；changeset 依 repo 是否使用決定 |
| Step 7 PR Create | ✅ title 用 conventional commit 格式（無 JIRA key） |
| Step 8 JIRA Transition | ⏭️ 跳過（無 ticket） |

### Admin-Specific Context（傳給 delivery flow）

```
Role: admin
Branch: <current branch>
Base branch: <upstream or origin/main>
PR title format: <type>(<scope>): <summary>
Evidence file key: /tmp/polaris-verified-<branch-slug>.json
```

---

## JIRA Ticket Safety Net

如果 branch name 或 commit 含 JIRA key pattern（`[A-Z]+-\d+`），自動帶入 changeset。

如果完全無 JIRA key 且 repo 的 changeset guideline 要求 ticket key：
- Branch 名含 `wip/` 或 `polaris/` → 允許省略
- 其他 → 提示使用者補 key，或依 `references/pr-input-resolver.md` fallback

---

## Post-PR: Feature Branch PR Gate

Task PR 建立完成後，執行 `references/feature-branch-pr-gate.md` 的偵測邏輯（靜默執行）。

## Post-PR L2 Deterministic Checks

PR 建立後（或既有 PR 推送新 commit 後），跑兩項 advisory check。兩者 exit 0 恆成立，stdout 若有訊息代表 Admin 要依訊息補動作。

### Step 3 — L2 Deterministic Check: version-bump-reminder

改動若落在 framework distribution/tooling files（由 `scripts/check-version-bump-reminder.sh` 的 portable allowlist 定義）且本次未同步 bump `VERSION`，提醒升版。

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/check-version-bump-reminder.sh" \
  --mode post-pr \
  --base "<PR base branch, e.g. main>" \
  --repo "$CLAUDE_PROJECT_DIR"
```

根據 exit code（advisory — script 恆 exit 0）：
- **exit 0 + 無 stdout** — 沒 framework distribution/tooling 改動或已 bump VERSION，繼續
- **exit 0 + 有 stdout** — Admin 依 repo version policy 決定是否 bump `VERSION` + 更新 `CHANGELOG.md`；後續 release tail 由對應 local policy / local skill 接手

此 canary 原列 `rules/mechanism-registry.md § Framework Iteration`（behavioral），DP-030 Phase 2C 下放為 deterministic。L1 fallback 由 PostToolUse hook on `git commit`（`.claude/hooks/version-bump-reminder.sh`）補位。

### Step 4 — L2 Deterministic Check: post-task-feedback-reflection

本 session 若出現自糾正信號但無新 feedback memory 檔案，提醒反思。

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/check-feedback-signals.sh" \
  --skill git-pr-workflow
```

根據 exit code（advisory — script 恆 exit 0）：
- **exit 0 + 無 stdout** — 無反思訊號，繼續
- **exit 0 + 有 stdout** — 依訊息決定是否寫 feedback memory

L1 fallback 由 Stop hook 在對話結束時再檢一次。兩個 check 均遵循 `skills/references/l2-script-conventions.md` advisory 約定。

## Handbook Maintenance (post-PR)

After PR is created, check if the repo has a handbook (`{repo}/.claude/rules/handbook/`). If it exists, run stale detection per `skills/references/repo-handbook.md` § Step 4.

## Do / Don't

- Do: 確認當前 repo 是框架/docs repo，不是產品 repo
- Do: 遵循 `engineer-delivery-flow.md` 完整流程（不跳步驟）
- Don't: 在產品 repo 使用本 skill（走 `engineering`）
- Don't: 跳過 quality check 或 behavioral verify
- Don't: 用模糊 title（如「fix bug」「update code」）

## Post-Task Reflection (required)

> **Non-optional.** Execute before reporting task completion.

Run the checklist in [post-task-reflection-checkpoint.md](../references/post-task-reflection-checkpoint.md).
