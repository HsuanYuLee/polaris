## Verify Command Introspection Authority

`validate-task-md` 在檢查 repo-local shell script flag 前，必須先由
`scripts/lib/validate_safe_cli_introspection_1.py` 分類，不能用動態 `--help` 猜分類：

- `test`：路徑位於 `test` / `tests` / `selftest` / `selftests`，或檔名以
  `-selftest.sh`、`_selftest.sh`、`-test.sh`、`_test.sh` 結尾。分類必須使用解析後仍位於
  repo 內的 canonical relative path；lexical `selftests/../` 與指向 repo 外的 symlink
  不得取得 test 資格。validator 永不執行合法 test-classified script。
- `non_cli`：未通過 DP-422 canonical literal-help prefix。沒有 flag 時不做
  introspection；帶 flag 時以 `POLARIS_VERIFY_COMMAND_UNSAFE_INTROSPECTION` fail-closed。
- `safe_cli`：只有通過 canonical prefix 的 script 才能為了 flag discovery 執行
  `--help`。執行必須建立獨立 session，timeout 時終止並 reap 整個 process group。

合法 safe CLI 的 unsupported flag 仍沿用 DP-065 diagnostic；missing script 只有同時列在
`## 改動範圍` `create` 與 `## Allowed Files` 的 create-set 才可在 planning 階段略過。
不得以加長 timeout、只 kill direct child、替個別 selftest 補 `--help` 特例，或完全移除
flag validation 取代這個分類契約。

## 6. Validator Mapping

**T mode rules（filename `T*.md`，§ 3 Implementation Schema）**：

| Rule | Layer | Script | Exit code | Bypass env var |
|------|-------|--------|-----------|----------------|
| 標題 / Header / 章節存在性 / Operational Context cells / Test Command 含 code block | Implementation single-file | `scripts/validate-task-md.sh <path>` | 1 (violations) / 2 (usage) | — |
| Test Environment Level enum + Runtime contract（`Runtime verify target` / `Env bootstrap` / Verify Command host alignment） | Implementation single-file (DP-023) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| `## 改動範圍` / `## 估點理由` / `## 目標` 非空 + Operational Context 含 JIRA key | Implementation single-file (DP-025) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| `Depends on` (cell) 非空 ⇒ `Base branch` `task/...` | Implementation single-file (DP-028 cross-field, T mode only) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| `## Allowed Files` 章節存在 + 非空 | Implementation single-file (DP-033 D5 升 Hard，無 grace) | `scripts/validate-task-md.sh`（Phase A A2 升級） | 1 / 2 | — |
| frontmatter `verification.behavior_contract` 欄位形狀（存在時） | Implementation single-file (DP-109 behavior intent) | `scripts/validate-task-md.sh <path>` | 1 / 2 | — |
| Lifecycle-conditional 結構（`deliverable` / `extension_deliverable` / `jira_transition_log`） | Implementation single-file (DP-032 D2/D3 + DP-033 D5/D7 + DP-048) | `scripts/validate-task-md.sh`（只在欄位存在時檢查；`deliverable` / `extension_deliverable` 必驗 schema、`jira_transition_log` 寬鬆 list-of-maps） | 1 / 2 | — |

**V mode rules（filename `V*.md`，§ 4 Verification Schema）**：

| Rule | Layer | Script | Exit code | Bypass env var |
|------|-------|--------|-----------|----------------|
| 標題 / Header / 章節存在性 / Operational Context cells (V 版，§ 4.2) / 驗收步驟含 code block | Verification single-file (DP-033 Phase B) | `scripts/validate-task-md.sh <path>`（V mode） | 1 / 2 | — |
| Test Environment Level enum + Runtime contract（**完全共用 T mode**，§ 4.4 / § 3.3） | Verification single-file (DP-023 reuse) | `scripts/validate-task-md.sh <path>`（V mode） | 1 / 2 | — |
| `## 驗收項目` / `## 估點理由` / `## 目標` 非空 + Operational Context 含 JIRA key | Verification single-file (DP-033 Phase B) | `scripts/validate-task-md.sh <path>`（V mode） | 1 / 2 | — |
| Lifecycle-conditional 結構（`ac_verification` / `ac_verification_log` / `jira_transition_log`） | Verification single-file (DP-033 Phase B § 4.7 對稱 D7) | `scripts/validate-task-md.sh`（V mode；`ac_verification` 必驗 schema、`ac_verification_log` / `jira_transition_log` 寬鬆 list-of-maps） | 1 / 2 | — |

**Shared rules（T/V 共用，filename pattern 擴展為 `[TV]*.md`）**：

| Rule | Layer | Script | Exit code | Bypass env var |
|------|-------|--------|-----------|----------------|
| frontmatter `depends_on[]` 引用存在性 + DAG 無 cycle + 線性 chain (≤1 dep) | Cross-file (DP-025 / DP-028) | `scripts/validate-task-md-deps.sh <tasks_dir>` | 1 / 2 | — |
| **V→T pass / T→V fail 方向性**（DP-033 D4，§ 5.3） | Cross-file (DP-033 Phase B B4) | `scripts/validate-task-md-deps.sh` | 1 / 2 | — |
| `## Test Environment` Fixtures path 存在性（T/V 共用） | Cross-file (DP-025) | `scripts/validate-task-md-deps.sh <tasks_dir>` | 1 / 2 | — |
| 完結 task 物理位置（`status: IMPLEMENTED` ⇒ 位於 `tasks/pr-release/`，T/V 共用） | Single-file (DP-033 D6 § 5.5) | `scripts/validate-task-md.sh`（檢查 frontmatter status × 檔案路徑） | 2 (hard fail) | — |
| 同 key 唯一性（active 與 pr-release 不並存，T/V 共用） | Cross-file (DP-033 D6 § 5.5) | `scripts/validate-task-md-deps.sh`（filename pattern `[TV]*.md`） | 2 (hard fail) | — |
| PR-release scope skip（`tasks/pr-release/` 下檔案完全跳過 schema 驗證） | Both validators | 上述 scripts 內建 `case */pr-release/*: continue` | n/a | — |
| Filename `T*.md` / `V*.md` → schema dispatch | PreToolUse Hook | `.claude/hooks/pipeline-artifact-gate.sh` → `scripts/pipeline-artifact-gate.sh` | 2 (block Edit/Write) | `POLARIS_SKIP_ARTIFACT_GATE=1`（emergency only） |
| 全部上述規則自動 dispatch | PreToolUse Hook（physical block） | 同上 | 2 | 同上 |

### Scan mode

兩個 validator 都支援 `--scan <workspace_root>` 模式，遞迴掃所有 `specs/*/tasks/T*.md`、`specs/*/tasks/V*.md` 與 folder-native `tasks/[TV]*/index.md` 並列 PASS / FAIL，永遠 exit 0（report mode），用於 migration 盤點。

### Bypass 慣例

- `POLARIS_SKIP_ARTIFACT_GATE=1` 是唯一支援的 bypass，僅供 migration / 結構性 schema 變更暫時違規時使用
- 不開新 bypass（DP-025 D3 + DP-032 NO-bypass 立場）— validator script 本身壞掉 → 修 script，不繞 script

### Reader Fallback 規則（DP-033 D8）

所有用 task key 找 file 的 reader 在 `tasks/` 頂層找不到時，**必須 fallback** `tasks/pr-release/`。否則 depends_on chain 會在完結 task 後斷裂（最常見：T5 還在做但 depends_on 已完工的 T1）。

| Reader | 用途 | Fallback 行為 |
|--------|------|---------------|
| `parse-task-md.sh` / `resolve-task-md.sh` | 給 task key 找 task.md path | 先 `tasks/{key}.md` / `tasks/{key}/index.md` → 找不到 fallback `tasks/pr-release/{key}.md` / `tasks/pr-release/{key}/index.md` |
| `validate-task-md-deps.sh` | 解 depends_on chain（最關鍵 — chain 跨完結 task 是常態） | 同上；保 T5 depends_on 已完結 T1 不假錯 |
| `verify-AC` | 讀 V-key task.md 取 fixture / verify 設定 | 同上 |
| `engineering` | 從 branch / ticket key 推 task.md path（first-cut + revision R0 / 修 PR base） | 同上 |
| 未來 Specs Viewer / docs UI | 渲染 task.md（完結 task 仍可見，可加 visual marker） | 同上 |

**統一 lookup 優先順序**：

```
1. tasks/{key}.md              # active
2. tasks/{key}/index.md          # folder-native active fallback
3. tasks/pr-release/{key}.md     # pr-release fallback
4. tasks/pr-release/{key}/index.md
3. fail (broken ref / not found)
```

**Hard fail invariant（D8 + § 5.5）**：同一 key 在 legacy / folder-native source **同時存在**，或在 active `tasks/` 與 `tasks/pr-release/` **同時存在** → validator hard fail（exit 2）。此狀態為 ambiguity 或 D6 move-first 失敗的 silent corruption signal，不應發生；validator 早期偵測比下游 reader 拿到錯版本好。

### Producer / Consumer 對應

| Producer | 寫入時機 | Hook trigger |
|----------|---------|--------------|
| `breakdown` Step 14 (Path A) | 產 T*.md | Edit/Write → hook 跑 T mode validator + deps validator |
| `breakdown` Step D | 產 V*.md（Phase B 規格已落地；producer cutover 從 `{JIRA-KEY}.md` → `V{n}.md` 移交 DP-039 atomic 切） | Edit/Write → hook 跑 V mode validator + deps validator |
| `engineering` Step 7c | 寫入 frontmatter `deliverable` | hook 跑 T mode validator（含 lifecycle 結構檢查） |
| `engineering` `jira-transition.sh` | append `jira_transition_log[]`（T*.md） | 同上 |
| `engineering` Step 8a | T*.md `status: IMPLEMENTED` + pr-release move | hook 跑 T mode validator → `mark-spec-implemented.sh` move-first（先 mv 到 `pr-release/` 再 update frontmatter）|
| `verify-AC`（DP-039 重構後） | 每跑完一輪 AC verification 寫回 V*.md `ac_verification`（覆寫摘要） + `ac_verification_log[]`（append）+ `jira_transition_log[]`（append） | hook 跑 V mode validator（lifecycle 結構檢查） |
| `verify-AC` 全 PASS + human_disposition=passed（DP-039 重構後） | V*.md `status: IMPLEMENTED` + pr-release move | hook 跑 V mode validator → `mark-spec-implemented.sh`（**同一支 closer，filename dispatch 對 T/V 共用**） |

| Consumer | 讀取方式 |
|----------|---------|
| `engineering`（first-cut + revision R0） | `scripts/parse-task-md.sh` 中央 parser；不直接 grep |
| `verify-AC`（DP-039 重構後） | 同 `scripts/parse-task-md.sh`（filename dispatch 自動識別 V*.md，**T/V 共用同一支 parser**） |
| `pr-base-gate.sh` | `scripts/resolve-task-md-by-branch.sh` + `scripts/resolve-task-base.sh`（DP-028 三層消費） |
| `mark-spec-implemented.sh` | 直接編輯 frontmatter `status`；filename dispatch 對 T/V 共用 move-first 流程 |

---

## Appendix A — v0 → v1 TODO 收斂紀錄（2026-04-26）

v0 草稿留有 6 個 `<!-- TODO discuss -->`，已在 2026-04-26 review 全部鎖定（見 `specs/design-plans/DP-033-task-md-lifecycle-closure/plan.md` § Discussion Log 2026-04-26 entry）：

| # | 主題 | 章節 | 鎖定結果 |
|---|------|------|----------|
| 1 | Reader fallback 規則 | § 1 Overview + § 6 | 加 callout（active → pr-release fallback）；folder 從 `archive/` 改名 `pr-release/`（語意精準、與 memory archive 詞義脫鉤） |
| 2 | `jira_transition_log[]` schema | § 2.1 + § 3.6 | 寬鬆 list-of-maps；`time`（ISO 8601）建議不強制；其他欄位 freeform；validator 不檢內容 |
| 3 | `deliverable` 寫入 atomic 機制 | § 2.1 + § 3.6 | atomic + verify, fail-stop（retry 3 次 backoff → HARD STOP，不繼續下游）；validator 必驗 schema |
| 4 | Header 行 `Epic:` 是否升 Hard | § 2.3 | 維持 **Soft** — Bug task 是真實無 Epic 場景（hotfix-auto-ticket） |
| 5 | `## Allowed Files` 升 Hard 的 grace 策略 | § 3.1 | **直接 Hard、不開 grace、不留 warn-only**；既有 active T 缺漏由 A7 migration script 強制 backfill |
| 6 | `status: IMPLEMENTED` 但未 pr-release 移動 | § 5.5 | validator **HARD FAIL**（exit 2）；`mark-spec-implemented.sh` 鎖定 move-first 順序，永不出現 transient 不一致狀態 |

伴隨修正：

- **D2 修正**：移除 frontmatter `type` 欄位 — filename pattern 為唯一 type 訊號。BS#11（filename ↔ type 一致性）整條作廢
- **新增 D7**：Lifecycle write-back contracts（jira_transition_log 寬鬆 + deliverable atomic）
- **新增 D8**：Reader fallback 規則（跨 active / pr-release 邊界）

---

## See Also

- `pipeline-handoff.md § Artifact Schemas` — 整個 pipeline artifact 的 high-level overview（task.md 是其中一類）；本檔為 task.md 的詳細 spec
- `epic-folder-structure.md` — `specs/{EPIC}/tasks/` 在 Epic folder 中的位置
- `engineer-delivery-flow.md` — engineering 消費 task.md 的完整步驟（含 deliverable 寫回時機）
- `branch-creation.md` + DP-028 三層消費模型 — `Base branch` / `Task branch` / `Depends on` cells 的 deterministic 解析路徑
- DP plans — 章節級語境：DP-023（runtime contract）/ DP-025（schema enforcement）/ DP-028（depends_on binding）/ DP-032（lifecycle write-back）/ DP-033（本 reference 的母 plan）
