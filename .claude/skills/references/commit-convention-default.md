# Commit Convention — Polaris L3 Default

Polaris 提供的 commit message 兜底規範。當 repo **L1 tooling**（commitlint config / husky `commit-msg` hook）與 **L2 handbook**（`{repo}/.claude/rules/handbook/**`）皆未宣告 commit convention 時，LLM 依此 spec 寫 commit message。

**消費者**：`engineer-delivery-flow.md § Step 6a Commit`（Developer 與 Admin 兩角色共用）。

**Source**：DP-032 D22（`specs/design-plans/DP-032-engineering-deterministic-extraction/plan.md` § D22）。本檔等同 D22 § 2.5 之機讀化版本。

---

## 1. Fallback Chain（消費端解析順序）

LLM 寫 commit message 前依下列順序 probe，命中即停（**不混用上層規則**）：

| 層級 | 來源 | 角色 |
|------|------|------|
| **L1 Repo tooling** | `{repo}/.commitlintrc.*` / `{repo}/commitlint.config.*` / `package.json` 的 `commitlint` 欄位 / husky `commit-msg` hook 內容 | **最權威**（機器可讀規則 + commit-msg hook 擋位 SoT 同源）|
| **L2 Repo handbook** | `{repo}/.claude/rules/handbook/**/*.md` 的 commit convention 段 | **次高**（補 L1 未宣告的敘述要求；L1 有則 L2 僅作補充 context） |
| **L3 Polaris default**（本檔） | `references/commit-convention-default.md` | **兜底**（L1+L2 皆無時的最後基準） |

**規則衝突處理**：L1 有定義就完全用 L1（type enum、scope、subject limit 等）；L2 / L3 只在 L1 未宣告的維度補充。L2 若明示「覆蓋 L1」這類 repo 暫不處理，回到 handbook 層解決。

**task.md 角色**（context only，不作 compliance）：`## 改動範圍` / `## 估點理由` 提供 PR 意圖理解；`Allowed Files` / `verification.*` / `depends_on` **不讀**。

---

## 2. L3 Default Format

### 2.1 Headline 結構

```
{type}({TICKET}): {subject}
```

| 欄位 | 規則 |
|------|------|
| `type` | enum（見 § 2.2） |
| `{TICKET}` | JIRA / 工單 key（見 § 2.3） |
| `subject` | ≤ 70 char、動詞開頭、中英皆可（見 § 2.4） |

### 2.2 `type` Enum

| Type | 用途 |
|------|------|
| `feat` | 新功能 |
| `fix` | Bug 修正 |
| `refactor` | 重構（行為不變、結構變） |
| `test` | 測試新增 / 修改（無 prod 行為改動） |
| `docs` | 文件 |
| `chore` | 雜項（build / ci / config / dependency 升級） |
| `style` | 純樣式（formatting、空白、缺漏分號） |
| `perf` | 效能優化 |

不在表內的 type 不使用。Repo L1 / L2 若有自定 type → 走該層。

### 2.3 `{TICKET}` 推導

| 來源 | 優先序 |
|------|--------|
| task.md frontmatter `ticket` | 1（主） |
| Branch name 中的 ticket pattern（`task/TASK-123-*` / `feat/PROJ-123-*`）| 2（fallback） |
| 使用者 session 上下文已宣告的 ticket | 3（最後手段） |

**Admin 模式**（無 task.md / 無 ticket）：允許省略 → headline 變 `{type}: {subject}`（承既有 `engineer-delivery-flow.md § 6c JIRA Safety Net`）。

### 2.4 Subject 規則

- **長度**：≤ 70 char
- **動詞開頭**：「加」「修」「移除」「換成」「補」/ `add` / `fix` / `remove` / `replace` / `support` 等
- **語言**：中英皆可，**單條 commit 內語言一致**（不混用）
- **句尾**：不加句號 / 結尾標點
- **避免 vague**：禁用 `update code` / `fix bug` / `修一下` 等無資訊量的句子

### 2.5 Body（選填、建議）

Body 與 subject 之間空一行（git 慣例）。建議結構：

```
## Why
{問題 / 動機 — 一兩句點到}

## Changes
- {改動 1 — 條列，描述 what}
- {改動 2}
```

**規則**：

- **Why**：說明為什麼要做這 commit；不抄 PR body 的 Description（PR body 是功能 snapshot；commit 是 iteration 紀錄）
- **Changes**：條列具體改動；可省略（subject 夠精準時）
- 不在 commit body 重述 task.md 或 PR body 已有的內容
- Breaking change：在 body 末尾加 `BREAKING CHANGE: {說明}` paragraph（與 Conventional Commits 對齊）

---

## 3. Multi-commit 策略（L3 Default）

| 情境 | 預設 |
|------|------|
| 一般 task | **一 task 一 commit**（squash TDD 過程的多個 commit） |
| Repo handbook 明訂 multi-commit | 遵循 repo（L2 override） |
| Revision push | 同 first-cut 規格，**無特殊 prefix**（不加 `R{N}:` / `revision:`） |

**Rationale**：Phase 3 Self-Review 已做完 review，PR reviewer 是人審（讀 PR body 不讀 TDD 進程），squash 對 reviewer 幫助不大；commit history 整潔。

**Squash 做法**（impl 自選）：

- `git reset --soft {base}` + 重新 `git commit`（簡單、無 rebase 風險）
- `git rebase -i {base} --autosquash`（適合本來就用 `fixup!` commit）

Repo L1 commit-msg hook 仍會擋每個 commit；squash 後產生的單一 commit 必須通過 hook。

---

## 4. Revision Mode 規格

| 維度 | 規格 |
|------|------|
| Headline 格式 | 同 first-cut（同 § 2.1） |
| Type | 描述「這 commit 改了什麼」決定（多半是 `fix` 或原 type） |
| Body | 同 § 2.5；描述「這次 push 修了什麼」 |
| 特殊 prefix | **無**（不加 `R{N}:` / `revision:` / `address review:`） |
| Revision 脈絡承載 | **不在 commit msg / PR body**；走 D23 規範（review reply / commit msg 自身 / re-request review） |

**邊界**：commit msg 描述「這 commit 做了什麼」就好，不兼任「這次 push 為什麼再 push」（後者由 GitHub PR review thread reply 承載）。

---

## 5. Repo Hook 互動

L1 commit-msg hook（husky / commitlint / `.git/hooks/commit-msg`）是**結構擋**：

- LLM 寫完 msg → `git commit -m '...'` → hook 觸發
- Hook fail → exit ≠ 0 → LLM 讀 stderr → 依錯誤訊息修 msg → 重試
- Framework **不**新增 commit lint script，**不**收進 `ci-local.sh`（時序不 match：`ci-local.sh` 在 Step 2a 跑、commit message 在 Step 6a 才寫）

**LLM 修 msg 的解析優先序**：先讀 hook stderr 訊息（最具體）→ 對照 L1 config 規則 → 必要時 fallback 到 L2 / L3。

---

## 6. 範例

### 6.1 Developer（一 task 一 commit）

```
feat(TASK-123): 產品頁 BreadcrumbList 加首頁 entry

## Why
SEO 報告指出產品頁麵包屑缺首頁節點，影響 sitelinks 顯示。

## Changes
- 在 `composables/useBreadcrumbList.ts` 注入首頁 entry
- 對應 unit test 補首頁 entry 斷言
```

### 6.2 Developer（subject only）

```
refactor(PROJ-123): 抽出 useProductHeading composable
```

### 6.3 Admin（無 ticket）

```
chore: bump pnpm 9.12.3
```

```
docs(handbook): 更新 changeset convention L2 範例
```

### 6.4 Revision（同規格、無特殊 prefix）

```
fix(TASK-123): 修正 SSR 階段 breadcrumb hydration mismatch

## Why
Reviewer 指出 client-side 補 entry 會造成 hydration warning。

## Changes
- 改為 server-side 在 useFetch 完成後立即組 list
- 加 SSR 條件下的 unit test
```

---

## 7. Cross-LLM Notes

- 本 spec 為純文字 / 機讀規則，所有 LLM（Claude Code / Codex / Cursor / Gemini CLI）共用
- 不依賴 MCP / IDE plugin，僅需 git CLI 與 repo 既有 commit-msg hook
- `git ai-commit` 等 user-level 工具**不在**本 spec 範圍（DP-032 D22 已拔除依賴）

---

## 8. Do / Don't

- Do: 先 probe L1 → L2 → L3，命中後不混用
- Do: subject 動詞開頭、≤ 70 char、語言一致
- Do: 一 task 一 commit（除非 L2 override）
- Do: revision 同規格、無特殊 prefix
- Don't: 重複 PR body / task.md 內容到 commit body
- Don't: 在 commit msg 承載「為什麼又 push」（走 review reply / re-request review）
- Don't: 假設 `git ai-commit` 可用（已從 framework 拔除）
- Don't: 為了 satisfy hook 把 msg 寫得空洞（修到通過、保留資訊量）

---

## Source

- DP-032 plan.md § D22（`specs/design-plans/DP-032-engineering-deterministic-extraction/plan.md`）
- 配套 reference：`pr-body-builder.md`（D23）、`changeset-convention-default.md`（D24）
- 上層消費：`engineer-delivery-flow.md § Step 6a`
