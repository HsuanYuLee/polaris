## Step 1 — Simplify Loop

在品質檢查前，先審查本次 diff 的簡潔性。

**執行方式**：invoke user-level `/simplify` skill（`~/.claude/skills/simplify/`）。若該 skill 不存在，降級為 inline 自審 — 跑一輪「讀 diff、找重複邏輯、抽共用、移除不必要複雜度」。

**迭代邏輯**：
- 每輪 `/simplify` 結束後，若 `git diff` 有新變動 → 再跑一輪（新改動可能引入新簡化機會）
- 無變動 → 進入 Step 2
- **最多 3 輪**。第 3 輪仍有修改則停止，記錄並報給使用者判斷

**不要**做：範圍超出本次 diff 的重構、重新命名無關檔案的變數、為了「美化」而動測試檔案。

---

## Step 1.3 — Self-Review（Phase 3 exit gate）

> **DP-032 D21（v3.63.0+）**：原 Step 4 Pre-PR Self-Review Loop 概念前移為 Phase 3 的 exit gate，發生在 Step 1 /simplify 之後、Step 1.5 Scope Gate 之前。Phase 3 = LLM 實作段（TDD → /simplify → Self-Review，可迭代，fail-cheap）；Phase 4 Step 1.5 起 = 機械自驗段（線性 fail-stop）。Self-Review blocking **絕不跨段回圈**。

啟動獨立 Reviewer sub-agent 對本地 diff 做 code review。

**Reviewer 規格**：見 `references/sub-agent-roles.md § Critic (Pre-PR Review)`。回傳 JSON `{ passed, blocking[], non_blocking[], summary }`，`blocking[]` 細項含 `file:line` + `rule`（引 handbook path）+ `message`。

**Reviewer baseline — handbook-first 硬規格**：

| 來源 | 用途 |
|------|------|
| `{company}/polaris-config/{project}/handbook/**/*.md` + `{repo}/CLAUDE.md` + `{repo}/.claude/rules/**/*.md` | **Primary compliance baseline**（judge against） |
| task.md `## 改動範圍` / `## 估點理由` | **Context only**（理解 PR 意圖，**不**作 compliance spec） |
| task.md `Allowed Files` / `verification.*` / `depends_on` | **不讀**（D20 Scope Gate / D15 verify evidence / D14 artifact gate 已處理） |

Rationale：handbook 是 repo long-term convention（repo SoT）；reviewer 以「這 PR 對 repo 是不是好的」為基準，不是「這 PR 是否符合 task.md 文字」。避免 task.md rubber stamp workaround。

**迭代規則**：

- `passed: true` → Phase 3 exit，進 Step 1.5 Scope Gate
- `passed: false` → 回 **Phase 3**（LLM 可自由改 test / 改實作 / 重跑 /simplify 任一），不只是回 /simplify
- 回到 Phase 3 後**必然重走** TDD → /simplify → Self-Review（Phase 3 exit condition 強制）
- **Hard cap 3 輪**，超過 → halt → 使用者手動介入
- **NO bypass**（無「強制繼續」flag；承 D11 / D12 / D14 / D15 / D16 / D20 一致立場：LLM 不自己決定跳過 gate）

**Evidence**：

- Self-Review **不寫 evidence file**，**不進 Layer A+B+C AND gate**（gate 仍只涵蓋 Layer A verify + Layer B behavioral + Layer C VR）
- Self-Review 是 LLM 語意 checkpoint，不是 CI-class gate；加 evidence 成本高、revision R5 重跑無益
- Self-Review 產出仍可記入 Phase 6 Detail artifact（`{source_container}/artifacts/engineering-{ticket}-{ts}.md`），可追溯不擋 PR
- **Revision mode R5 不重跑 Self-Review**（R5 只跑 Layer A+B+C 機械 evidence；Phase 3 全段不進 R5）

---

## Step 1.5 — Scope Gate（D20）

> **機械自驗段起點**。在 Phase 3 exit（Self-Review pass）之後、Step 2 之前，catches scope creep at the earliest mechanical checkpoint after LLM implementation completes.

### Developer mode

使用 `scripts/check-scope.sh`。一般 first-cut 可只傳 task.md；stacked PR / revision mode 必須傳入與 PR / rebase / `ci-local-run.sh` 一致的 effective base：

```bash
SCOPE_JSON=$(bash "${POLARIS_ROOT}/scripts/check-scope.sh" "<path/to/task.md>")
# stacked / revision context:
SCOPE_JSON=$(bash "${POLARIS_ROOT}/scripts/check-scope.sh" --base-branch "<effective-base>" "<path/to/task.md>")
```

Script 行為：
- 透過 `parse-task-md.sh` 讀取 task.md `## Allowed Files`
- 比對 `git diff --name-only {effective_base}..HEAD` 的實際改動檔案
- 輸出 `resolved_base`、`base_branch`、`base_ref`、`base_source`，供 flow gap gate 檢查 scope base 是否和 PR/effective base 一致

| 結果 | 動作 |
|------|------|
| exit 0 — 所有檔案在 scope 內 | ✅ 繼續 Step 2 前置 |
| exit 1 — scope 超出 | ❌ **HALT**。訊息：「Scope 超出 task.md Allowed Files {N} 個檔（{files}），回 `/breakdown {EPIC}` 更新 Allowed Files 或拆新子 task」 |

**嚴格立場**：
- **NO runtime override**（無 `allowed_files_override` 欄位）
- **NO bypass env var**
- Scope 超出 = 回到上游 breakdown 修正，不在 delivery flow 內自行豁免

### No-task request

無 task.md 不進入本 delivery flow；呼叫端必須 fail-stop，要求先補 `refinement` / `breakdown` 產生 work order。

---

## Step 2 前置 — Rebase Re-Sync（D6/D19）

> 在 Local CI Mirror 之前執行 rebase，確保 evidence 基於最新 base。

使用 `scripts/engineering-rebase.sh`：

```bash
REBASE_RESULT=$(bash "${POLARIS_ROOT}/scripts/engineering-rebase.sh" "<path/to/task.md>")
```

### Script protocol

| stdout | 意義 | 動作 |
|--------|------|------|
| `REBASE_NOOP` | base 無新 commit | 繼續 Step 2 |
| `REBASE_OK` | rebase 成功 | 繼續 Step 2 |
| `REBASE_CONFLICT: <files>` | 衝突，`.git/rebase-merge/` 保留 | **halt** — conflict resolution 是 LLM semantic work（同 Phase 3 TDD domain）；解完後 resume from Step 2 前置 |

### Post-rebase 衛生

Script 自動呼叫 `changeset-clean-inherited.sh`（D24）清理因 rebase 帶入的 inherited changeset。

### First-cut vs Revision

- **First-cut**：通常 `REBASE_NOOP`（branch 剛由 D4 `engineering-branch-setup.sh` 從最新 base 建立）
- **Revision R0**：always runs（base 可能在 review 期間前進）

### Evidence chain

Rebase 改變 HEAD → 舊 evidence 的 `head_sha` 自動失效 → 所有下游 evidence 自然重新產生。

### Local Extension

同行為；必須透過 task.md / local policy resolver 取得 upstream，不支援無 task.md rebase lane。

---

