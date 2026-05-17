## 5. Cross-section Invariants

跨欄位 / 跨檔案規則。validator 的 cross-field 檢查邏輯都源自本節。

### 5.1 Test Environment Level → Verify Command（DP-023）

| Level | Verify Command 要求 |
|-------|---------------------|
| `static` | fenced code block 必填；可為純 grep / file existence check；`Runtime verify target` 預期 `N/A` |
| `build` | fenced code block 必填；可包含 `pnpm build` + 後續 artifact 檢查 |
| `runtime` | fenced code block 必填；**必須**包含 http/https URL；URL host **必須等於** `Runtime verify target` host |

違反 → `validate-task-md.sh` exit 1 → `pipeline-artifact-gate.sh` PreToolUse hook 擋 Edit/Write（exit 2）。**T/V 共用**（V mode 完整 reuse § 3.3 cross-field rules）。

### 5.2 depends_on 規則（DP-025 + DP-028）

| 規則 | Validator | 違反行為 |
|------|-----------|----------|
| frontmatter `depends_on` 須為 array of task id strings | `validate-task-md-deps.sh` | exit 1 |
| 每個 entry 必對應同 `tasks/` dir 既有 task.md（`tasks/{ID}.md` 或 `tasks/{ID}/index.md`；找不到時 fallback `tasks/pr-release/{ID}.md` / `tasks/pr-release/{ID}/index.md` — DP-033 D6 + D8）；**T/V 跨類型 reference 合法**（V→T / V→V，§ 5.3） | `validate-task-md-deps.sh`（filename pattern `[TV]*.md` / `[TV]*/index.md`） | exit 1，列出 broken ref |
| graph 須為 DAG（無 cycle） | `validate-task-md-deps.sh`（DFS coloring，跨 T/V 同圖） | exit 1，印出 cycle chain |
| 陣列長度 ≤ 1（強制線性 chain — DP-028 D5；T/V 共用） | `validate-task-md-deps.sh`（is-linear-dag） | exit 1，建議線性化或拆 Epic |
| **T→V 禁止**（DP-033 D4，§ 5.3）— T*.md 的 `depends_on` 不可指向 V*.md | `validate-task-md-deps.sh`（cross-type direction check） | exit 1，列出違規 + 建議拆 Epic |
| `Depends on`（Operational Context cell）非空 ⇒ `Base branch` cell 必須 `task/...`（DP-028 cross-field，T mode 適用；V mode 不檢此 cross-field — V 通常從 `feat/...` 或 `develop` 跑驗收） | `validate-task-md.sh`（T mode only） | exit 1 |

### 5.3 V → T / T → V 方向性（DP-033 D4，Phase B 已實作）

跨類型 `depends_on` 方向性規則（由 `validate-task-md-deps.sh` filename pattern 從 `T*.md` 擴展為 `[TV]*.md` 後 enforce）：

| 方向 | 範例 | 規則 | Validator 行為 |
|------|------|------|---------------|
| V→T | `V1.md` `depends_on: [T2]` | **合法** — 驗收前提是相關實作完成 | pass |
| V→V | `V2.md` `depends_on: [V1]` | **合法** — 驗收 chain（前置驗收先過再跑下一輪） | pass（仍受 DP-028 線性 chain 限制：≤ 1 dep） |
| T→V | `T5.md` `depends_on: [V1]` | **禁止** — 實作不應卡在驗收（避免循環依賴 + Epic 內 phase 化） | exit 1，列出違規 task |
| T→T | `T2.md` `depends_on: [T1]` | 合法（既有規則 § 5.2） | pass |

**分段驗收場景**（T1+T2 → V1 → T3+T4 → V2）：

由 `breakdown` SKILL.md Step 6 / Step 7.5 Quality Challenge 偵測（兩組互不依賴 AC + 兩組互不依賴實作 task 群），主動提示「建議拆 Epic」（兩個交付 = 兩個 Epic 是 PM 視角的自然分法） — validator 不 enforce（advisory，留 PM 判斷）。原因：

- schema 規則最簡單（validator 邏輯乾淨）
- 兩個交付 = 兩個 Epic 是 PM 視角的自然分法（JIRA 上看兩個 Epic 比帶 phase label 的單一 Epic 直覺）
- 過去 EPIC-478 / EPIC-521 / EPIC-542 都是「實作完一次驗收」模式，無真實分段需求

**未來擴張空間**：若分段驗收需求強烈，再開新 DP 升級到 Path B（允許 T→V 加警示）或 Path C（雙欄位 `depends_on` + `requires_ac`）。Phase B 不預先支援。

### 5.4 Fixture 路徑存在性（DP-025）

`## Test Environment` 的 `Fixtures:` 若非 `N/A`，path 必須在以下任一位置存在：

1. `{epic_dir}/{path}`（相對於 Epic folder）
2. `{company_base_dir}/{path}`（相對於 company base）
3. `{workspace_root}/{path}`（相對於 workspace root）

由 `validate-task-md-deps.sh` enforce。違反 → exit 1，列出 checked candidates。

### 5.5 完結 task 物理位置（DP-033 D6 + D7，Hard invariant）

兩條 invariant 由 validator hard-enforce，違反 → exit 2（PreToolUse hook 擋 Edit/Write，或 `--scan` 模式列為 FAIL）：

#### Invariant: 完結 task 物理位置

- task frontmatter `status: IMPLEMENTED` ⇒ **必須** 位於 `tasks/pr-release/{filename}`，不得停留於頂層 `tasks/`
- 違反場景：`tasks/T5.md` 內 frontmatter `status: IMPLEMENTED` → validator **HARD FAIL**（exit 2）
- **Mitigation 機制**：`mark-spec-implemented.sh` **鎖定 move-first 順序**（`mv tasks/T.md tasks/pr-release/T.md` → 再 update frontmatter）。永不出現 transient「在頂層 tasks/ 內標完結」狀態 → validator 可放心 fail-loud
- 不留 grace、不開 warn-only：手寫 `status: IMPLEMENTED` 而未跑 `mark-spec-implemented.sh` 的人類路徑 → 由 hook 擋下 → 提示走 helper script

#### Invariant: 同 key 唯一性

- 同一 task key（`T{n}` / `V{n}`）不可同時存在 legacy 與 folder-native source，也不可同時存在 `tasks/` 與 `tasks/pr-release/`
- 違反場景：`tasks/T1.md` 與 `tasks/T1/index.md` 並存，或 `tasks/T1.md` 與 `tasks/pr-release/T1/index.md` 並存 → validator **HARD FAIL**（同 key ambiguity / D6 move-first 失敗的 silent corruption signal）；`V1` 同樣 HARD FAIL
- 由 `validate-task-md-deps.sh`（cross-file 階段，filename pattern `[TV]*.md`）enforce — T/V 共用同一條 invariant

#### 邊界

- Validator 永遠 skip `tasks/pr-release/` 下的所有檔案（不論 schema） — 完結檔保留歷史樣貌，不重跑
- engineering Step 8a 透過 `mark-spec-implemented.sh` 自動觸發 pr-release move
- Reader fallback 規則（用 task key 找 file 時）見 § 6 Validator Mapping

---

