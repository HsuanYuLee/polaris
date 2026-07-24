# Refinement Source Mode

`refinement` 各種 source（JIRA Epic / Task / Story、ticketless DP-NNN、topic、
free-text、article、paragraph、artifact path）
的 progressive-disclosure reference。

當 `refinement` 將 source 解析為以下類型時使用：

- `jira`：既有 JIRA Epic / Task / Story（含 Epic-backed source）
- `bug`：既有 JIRA Bug 或明確 `source_kind=bug` source；sub-step contract 見
  `refinement-bug-source-mode.md`
- `dp`：既有 `DP-NNN` design-plan container（ticketless source）
- `topic`：必須成為 DP container 的新 ticketless topic
- `free-text` / `article` / `paragraph`：由 resolver 產生 slug+hash 的 workspace-local
  source container proposal，metadata 保存 text_hash / url / archive_snapshot / selector /
  paragraph_index
- `artifact_path`：`docs-manager/src/content/docs/specs/**` 底下的 path

核心邊界：`refinement` owns design record 與 artifact output。`refinement` 不主動 dispatch
breakdown / engineering / verify-AC，也不寫 JIRA 以外的 status 欄位；JIRA 寫入只發生在
JIRA-backed source 的 comment / label / description 與 source-state transition 等明確路徑。

## T0. Resolve Source

透過 `spec-source-resolver.md` resolve source。下表列出每種 source type 的 locator / 入口
規則；DP-specific operational detail 收斂於本檔末尾的「DP Inherent Property Appendix」。

| Input | Action |
|-------|--------|
| `PROJ-NNN` (JIRA key) | 透過 JIRA fetch + project mapping 解析為 Epic / Task / Story；container 為 `docs-manager/src/content/docs/specs/companies/{company}/{ticket}/` |
| Bug ticket / `source_kind=bug` | 透過 `refinement-bug-source-mode.md` 執行 reproduction / RCA / source PR / severity-impact sub-steps，container 仍為對應 company ticket source |
| `DP-NNN` | Locate exactly one `docs-manager/src/content/docs/specs/design-plans/DP-NNN-*` container；`index.md` 為 canonical primary doc，legacy `plan.md` 只作 fallback |
| direct DP plan/refinement path | 使用該 DP folder 作為 `source_container` |
| direct JIRA-backed artifact path | 使用該 ticket folder 作為 `source_container` |
| topic phrase | 呼叫 `scripts/create-design-plan.sh` 分配下一個 archive-aware `DP-NNN-{slug}` folder，建立完整 metadata `index.md`，設定 `status: DISCUSSION` |
| `SEEDED` DP | 若存在 `artifacts/research-report.md`，讀取並轉成 candidate Decisions |
| `LOCKED` / `IMPLEMENTED` source | 新 topic overwrite 必須 fail loud；只有使用者明確 resuming/reviewing 該 source 時才繼續 |

Source locator hard rules（適用所有 source type）：

- source ID 必須唯一 match 一個 container。
- Zero 或 multiple matches 必須 fail loud。
- 不可默默建立同號 replacement source。
- `LOCKED` / `IMPLEMENTED` source 不可被 new topic overwrite。方向改變時，開新 source 並
  加 see-also links。

Framework-owned DP source 若預期拆成多張 task PR 後走 `framework-release`，必須在
refinement 階段以 `scripts/resolve-handbook.sh --project polaris-framework` 取得 canonical
handbook payload。codebase exploration 前先讀 `index_path`、從 `narrative_paths` 取得
`changeset-convention.md` 與 `release-topology.md`，並呼叫
`scripts/validate-handbook-load-gate.sh` 建立 session/repo marker。該 changeset topic 是 repo
policy；first-touch gate 只作漏接或跨 repo backstop，不以 task-specific changeset prose 代替。
`release-topology.md` 只提供 release topology
planning guidance；不要把線性 PR stack 寫成 fake code dependency，也不要用 markdown prose
取代 `framework-release` lane 的結構化 release gate。

## T1. Create Or Update Source Plan

新 ticketless topic 必須使用單一建單入口，不可手動 `mkdir` 或手寫 minimal template：

```bash
bash scripts/create-design-plan.sh "<durable topic>"
```

`create-design-plan.sh` 會：

1. 掃描 active + archive parent `index.md` / `plan.md`，分配全域最大 DP number + 1。
2. 建立 `{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{topic-slug}/index.md`。
3. 寫入完整 metadata：`title`、`description`、`topic`、`created`、`status`、`priority`、`sidebar`。
4. 呼叫 `scripts/validate-dp-plan-authoring.sh`，讓語言、Starlight、metadata、sidebar、route-safe path 與
   DP number collision gate 一次通過。

若 command 失敗，必須修正 root cause 後重跑；不可改回手動建單。

JIRA-backed source 不需要 `create-design-plan.sh`；container 由 ticket key + project mapping 直接決定。
首次 refinement 寫入時若 container 不存在，由 `refinement` 依 spec-source-resolver 規範建立。

Source plan authority 規則（適用所有 source type）：

- 新 source 一律以 owning resolver / creation script 產出的 container 為準；不可搜尋
  sibling source 來推導 frontmatter 或章節模板。
- 既有 source 重跑 / 重整時，直接更新同一個 `index.md` / `refinement.md` / `refinement.json`
  container；不可刪掉後用別張 source 內容複製回填。
- 若 authoring shape 不清楚，回讀本 reference 與 validator 輸出；不要用「先找一張像的
  source」當預設流程。

`refinement` owns these primary doc sections:

- `## Goal`
- `## Background`
- `## Target State`
- `## Decision Policy`
- `## Migration Boundaries`
- `## Decisions`
- `## Blind Spots`
- `## Acceptance Criteria`
- `## Technical Approach` / `## 技術方案`

Framework contract source 在 handoff 前，plan 必須包含 target-state-first sections：

- `## Target State`：migration 後的 final source of truth、runtime ownership、handoff boundary、steady-state paths。
- `## Decision Policy`：選擇 direct migration 或 phased delivery 的規則。
- `## Migration Boundaries`：任何 temporary compatibility / fallback / bridge / mirror / dual-source mechanism，必須寫 owner、removal criteria、verification method、follow-up task。

如果 framework source 提出 phased compatibility 但缺少這些欄位，先停下來補完 design，再進
implementation 或 breakdown。Compatibility scaffolding 不可成為 steady state。

每個使用者確認的 design decision 都必須先更新 primary doc（DP container 為 `index.md`，legacy
container 可是 `plan.md`；JIRA-backed source 為對應 container 的 primary doc），再繼續
unrelated work。不可只把 confirmed decisions 留在 conversation memory。

每次建立或更新 primary doc 後，必須先跑 authoring wrapper，通過後才能回報給使用者：

```bash
bash scripts/validate-dp-plan-authoring.sh \
  {workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/index.md
```

JIRA-backed source 的對應 wrapper 由 spec-source-resolver / authoring-preflight 指定。若
gate 失敗，先修正自然語言、metadata、sidebar、route path 或 source number collision 後重跑。
primary doc 違反 wrapper 時，不可宣稱 source 已可 review。

Starlight `docsSchema()` 要求每個 docs markdown 都有 `title`。`refinement` 建立任何新的
`index.md` / legacy `plan.md` 或 `refinement.md` 時，必須寫入 stable `title` frontmatter；
不可依賴 docs-manager 在 build 時補 metadata。

## T2. Docs-Manager Preview

建立或編輯 source markdown 後，docs-manager 會直接從 `{workspace_root}/docs-manager/src/content/docs/specs/`
讀取 canonical source。必須先跑 T1/T3 的 language gate；未通過 workspace language policy
的新產生 prose 不可進入 review 或 downstream handoff。

正式 preview surface 是 docs-manager Starlight route。常用 route：

```text
/docs-manager/specs/design-plans/dp-nnn-topic/plan/
/docs-manager/specs/design-plans/dp-nnn-topic/refinement/
/docs-manager/specs/design-plans/dp-nnn-topic/tasks/t1/
/docs-manager/specs/companies/{company}/{ticket}/refinement/
```

Live review route 由 docs-manager canonical specs 直接提供；framework 只產出 markdown 與
route，不替使用者啟動或重啟 docs viewer。

Static/search verification（先由使用者啟動 preview viewer，再驗證該 port）：

```bash
bash scripts/polaris-toolchain.sh run docs.viewer.verify -- --ports <preview-port> --preview
```

這適用於 `index.md` / legacy `plan.md`、`refinement.md`，以及任何準備進 review 的 source
markdown artifact。

## T3. Refinement Markdown Output

所有 source 採 local-first refinement。Discussion output 寫入：

```text
{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.md
{workspace_root}/docs-manager/src/content/docs/specs/companies/{company}/{ticket}/refinement.md
```

寫入前先讀 `authoring-preflight.md`。所有 skill 自己新增的 prose 直接使用 root
`workspace-config.yaml` 的 `language` 起稿；不可先產英文 draft 再把 language gate 當翻譯器。

Preview 不再啟動獨立 markdown renderer；使用 docs-manager route。舊的 standalone preview helper
已 sunset，不能作為 handoff contract。

`refinement.md` 只應包含 downstream implementation information：

- scope
- technical approach
- acceptance criteria
- edge cases
- risks
- references

`refinement.md` 的 acceptance criteria 不可使用較弱模板；所有 source（JIRA Epic、DP、ticketless
topic）皆採用同一套 hardened AC 結構：

- `功能 AC`
- `非功能 AC`
- `負面 AC`
- `驗證方式`

若某一輪沒有相關非功能 AC，需明確寫 `N/A` 或原因；不可直接省略，避免 source 退化成只剩功能描述。

完整 decision history 保留在 primary doc（DP container 為 `index.md`，legacy fallback 為 `plan.md`；
JIRA-backed source 為對應 primary doc）。

Source container 的 markdown path classification：

- Docs page：`index.md` / legacy `plan.md`、`refinement.md`、`tasks/Tn/index.md`、
  `tasks/Vn/index.md`。需符合 Starlight authoring contract，含 `title` + `description`。
- D2 transport artifact：`artifacts/external-writes/**/*.md` 與
  `artifacts/research/**/*.md`。這些會從 docs collection 排除，但 producer 必須寫
  `artifact_type`、`source`、`created`；不要求 `title` / `description`。
- Existing sidecar：`jira-comments/`、`escalations/`、`refinement-inbox/`。這些也會從 docs
  collection 排除，但不套 D2 metadata，保留各自既有 schema。

Legacy DP `plan.md` 是唯讀相容 fallback。Active DP container 必須用 folder-native
`index.md`；若某個 active design-plan container 仍留著 `plan.md`，在 downstream handoff
前先跑 `scripts/migrate-legacy-dp-plan-to-index.sh --workspace <root> --execute`。已封存的
`design-plans/archive/**/plan.md` 除非帶 `--include-archive`，否則屬明確歷史 allowlist；
helper 在遷移時會保留 frontmatter 與 body。

D2 transport artifact 寫入後需跑：

```bash
bash scripts/validate-specs-collection-shape.sh <source_container>
```

每次建立或更新 `refinement.md` 後，必須先跑 workspace language gate，通過後才能 preview、
sidebar sync 或 downstream handoff：

```bash
bash scripts/validate-language-policy.sh \
  --blocking \
  --mode artifact \
  {workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.md
```

同一輪若同時改了 primary doc 與 `refinement.md`，用同一個 command 一起驗。若 gate 失敗，先
修正 artifact language，再開 preview 或繼續 refinement flow。

## T4. Artifact Output

準備 handoff 時，produce 或 update：

```text
{source_container}/refinement.md
{source_container}/refinement.json
```

`refinement.json` 的 validator gateway 見 `pipeline-handoff.md` § Artifact Schemas；完整
producer schema 見 `refinement-artifact.md`。本節只保留最小定位框架（DP 範例 — 其他 source
type 的 `source` 欄位請依 spec-source-resolver 規範填入）：

```json
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-NNN",
    "container": "{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}",
    "plan_path": "{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/index.md",
    "jira_key": null
  },
  "predecessor_audit": []
}
```

Artifact 必須保留足夠的 scope、AC、dependencies、edge cases、downstream hints，讓
`/auto-pass {source}` 不需要重做 refinement 就能 create work orders。

所有 source type 的 artifact contract 一致：

- `acceptance_criteria[]` 每條 AC 都要保留驗證方式。
- 新 producer 應為每條 AC 寫 `category`，值為 `functional`、`non_functional`、`negative`
  其中之一，避免 human-only markdown 分類在 JSON artifact 中流失。
- `negative: true/false` 可保留作 legacy compatibility，但不能取代 `category` 的分類語意。

`predecessor_audit` 是 refinement handoff 的必讀欄位；沒有 predecessor 時也必須明確寫
`[]`，不可省略。若 successor 吸收任何 predecessor scope，entry 至少要包含：

- `spec_id`
- `disposition`: `KEEP` / `PARTIAL_ABSORB` / `FULLY_SUPERSEDED`
- `rationale`
- `writeback.required`
- `writeback.summary`
- `writeback.expected_status`
- `writeback.checklist_attribution`

一致性規則：

- `KEEP`：保留 predecessor current lifecycle，不做 source writeback
- `PARTIAL_ABSORB`：必須寫回 predecessor disposition note / checklist attribution，但
  predecessor 仍保留 residual ownership
- `FULLY_SUPERSEDED`：必須寫回 predecessor disposition，且預期 terminal status 為 `SUPERSEDED`

## T5. LOCKED Handoff Gate

當使用者說「定版」、「開始做」、「可以執行」、「lock」或同義語：

1. 檢查 Goal、Decisions、Blind Spots、Acceptance Criteria、Technical Approach 是否足夠交給
   breakdown。
2. 確認 `refinement.md` 與 `refinement.json` 是 current；`refinement.json` 必須通過
   `scripts/refinement-handoff-gate.sh`。這是所有 refinement-owned source 的 LOCK / breakdown
   handoff 規則，不限 source type：Epic / Story / Task / ticketless DP / topic 同樣不得在
   缺 handoff artifact 時提示 breakdown。

   若本輪 decisions / dependencies / Background 已吸收 predecessor scope，`predecessor_audit`
   不得為空，且每筆 entry 都必須把 disposition 與 writeback 寫清楚；不可只留在 prose。

2b. **Breakdown-ready preflight（DP-262 T4，fail-stop）**：跑

    ```bash
    bash scripts/validate-refinement-lock-preflight.sh {source_container}/refinement.json
    ```

    這支 preflight 讀 `refinement.json` 的 `planned_tasks[]`（schema 見
    `refinement-artifact.md` § planned_tasks），對每筆合成一份 ephemeral placeholder
    task.md，再呼叫真正的 `scripts/validate-breakdown-ready.sh` 判斷該 planned task 的
    宣告 deliverable 是否可通過 breakdown readiness。它**不**自行重寫 specs-only /
    `task_shape` 判斷，只委派 validate-breakdown-ready（DP-262 AC7）。

    - exit 0：所有 planned task 在 LOCK 時就已是 breakdown-ready。
    - exit 2 + `POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED`：至少一筆 planned task 不
      ready（例如 `task_shape: implementation` 卻宣告 specs-only deliverable，DP-262
      AC-NEG3）。這是 **fail-stop**，不是 advisory：停下，修正 `planned_tasks[]` 的
      `task_shape` / `tracked_deliverable_hint`（或改設計），再重跑，不得 LOCK。
    - `refinement.json` 沒有 `planned_tasks[]`（pre-DP-262 source）時 preflight no-op
      PASS，零 migration shim（DP-262 AC8）。

    **Replace-existing source discipline（DP-417 T9，同支 preflight，fail-stop）**：
    當 `refinement.json` 帶 `replaces_existing`（本 source 替換既有機制）時，同一支
    preflight 在 task-derive loop 之前額外強制兩道 source-level gate（non-replacing
    source 無此欄位 → 嚴格 no-op）：

    - **枚舉 gate（AC9 / AC-NEG4）**：`replaces_existing.existing_sources` 必須非空，且每筆
      `evidence` 必須是 runtime/build-output（`runtime` / `build-output` / `cdn` /
      `inline`）。只用 `source-grep` discovery 或 `existing_sources` 為空 → exit 2 +
      `POLARIS_REFINEMENT_REPLACE_EXISTING_ENUMERATION`。停下，補上枚舉被替換物**所有**現存
      來源（含 build-time / CDN / inline 注入等源碼 grep 看不見的路徑）的 runtime/build-output
      證據，再重跑，不得 LOCK。
    - **反死代碼 port gate（AC11 / AC-NEG6）**：`replaces_existing.ported_symbols` 每筆必須
      攜帶 `usage_evidence`；`usage_count == 0`（全站零使用）者 `disposition` 必須是
      `removable`，否則 → exit 2 + `POLARIS_REFINEMENT_REPLACE_EXISTING_DEAD_PORT`。停下，
      補 usage 檢查、把死 symbol 標成可移除（不得原封 port 製造 new legacy），再重跑。

    schema shape 見 `refinement-artifact.md` § `replaces_existing`。
3. 將 primary doc frontmatter 改為：

   ```yaml
   status: LOCKED
   locked_at: YYYY-MM-DD
   ```

4. 跑 `scripts/validate-dp-plan-authoring.sh {source_container}/index.md`；若是 legacy
   container 則對 `plan.md` 跑同一個 wrapper。相關 artifact validator / handoff gate 任一
   失敗或缺 `refinement.json`，先停下來 produce/fix artifact。
5. 若需要 route/search review，跑 docs-manager dev 或 preview verification。
6. 告知使用者下一個 command（DP 範例；JIRA-backed source 帶 JIRA key）：

   ```text
   /auto-pass DP-NNN
   ```

Source 在此之後仍走正規施工鏈：`breakdown -> engineering -> (verify-AC when verification
artifact exists)`。`framework-release` 不是 planning/implementation 捷徑，只能消費
engineering 已建立的 workspace PR。

## LOCKED Scope Guard (DP-212)

primary doc 進入 `status: LOCKED` 後，**任何** refinement amendment 都受 LOCKED scope guard
管制（適用所有 source type）：

| Section / Field | LOCKED 後可改？ | 原因 |
|-----------------|------------------|------|
| `## Goal` | ❌ 不可 | LOCK 承諾的核心目標 |
| `## Background` | ❌ 不可 | 鎖定當下的事件脈絡 |
| `## Decisions` | ❌ 不可 | 鎖定的設計決策 |
| `## Scope` / `## Out of Scope` | ❌ 不可 | 鎖定的範圍邊界 |
| AC 增刪（`acceptance_criteria[].id` 集合變動） | ❌ 不可 | 鎖定的 AC 承諾範圍 |
| `acceptance_criteria[].id` | ❌ 不可 | per-AC-id 配對的 identity，rename 即 id 集合變動 |
| `acceptance_criteria[].text` | ❌ 不可 | AC 意圖權威，不得為遷就 implementation 改寫 |
| `acceptance_criteria[].category` | ❌ 不可 | AC 分類屬 LOCK 承諾 |
| `acceptance_criteria[].verification.method` | ❌ 不可 | 驗證方法不可變，防 amendment 弱化驗收 |
| `acceptance_criteria[].verification.detail` | ✅ 可 | 驗證執行細節屬 implementation detail，amendment 可調（DP-311 T5） |
| `## Technical Approach` | ✅ 可 | implementation detail，可隨 amendment 調 |
| `## Dependencies` | ✅ 可 | dependency 變動需 amendment 反映 |
| `## Open Questions` | ✅ 可 | 隨 dogfood 收斂 |
| `## Downstream Breakdown Hints` | ✅ 可 | 子單拆分細節可調 |
| `tasks/**/*.md` | ✅ 可 | task.md 細節 / Verify Command / Allowed Files 可 amendment |

實際 enforce 由 `scripts/validate-refinement-locked-scope.sh` 負責。canonical writer 在
mutation 前以現存 `refinement.json` 作 current authority、待寫 body 作 candidate
authority，先驗 candidate schema與 source identity，再對照上表。`goal` / `background` /
`decisions` / `scope` 整欄 deep-compare；`acceptance_criteria` 採 per-AC-id 配對 +
per-field 比對（DP-311 T5）——AC 增刪、id / text / category / `verification.method`
任一變更即 exit 2 並輸出 `POLARIS_LOCKED_SCOPE_VIOLATION` stderr；唯一開放欄位是
`verification.detail`。同筆 AC 同時改 `verification.detail` 與鎖定欄位時整筆 fail，
不因含合法 detail 變更而放行。

git-ref mode 只保留給兩端 blob 都可觀測的 tracked compatibility caller；base/head 任一
blob 不存在、JSON 無法解析、current/candidate 指向同檔或 identity 不一致時，必須以
`POLARIS_LOCKED_SCOPE_AUTHORITY_UNOBSERVABLE` exit 2。ignored／untracked source 一律走
writer 的 explicit-file mode，不得以空物件、candidate 自身或 rendered
`refinement.md` 代替 before authority。auto-pass 收到 exit 2 後必須升 terminal
`blocked_by_gate_failure`，由人類決定是否走完整 unlock + refinement 流程。

### 人工 Unlock 流程

LOCKED scope 真的需要改時，**不可** 透過 amendment 繞道，必須：

1. 把 primary doc `status` 從 `LOCKED` 改回 `DISCUSSION`、刪 `locked_at`、把 sidebar badge
   改回 `DISCUSSION / Pn`。
2. 跑完整 `/refinement {source}` 走 Phase 0/1/2 discovery 並更新 `refinement.md` / `refinement.json`。
3. 重跑 Step 7 所有 gate，確認 LOCK 條件後再重新 LOCK。
4. auto-pass 必須以新 ledger 重新啟動，舊 ledger 視為 stale。

## Appendix: DP Inherent Property

本附錄列出 DP-backed（ticketless）source 在上述 source-neutral 流程之外的 inherent
property — 這些是 DP 本質上與 JIRA-backed source 不同的點，不是流程歧異：

1. **Container path**：DP container 位於
   `docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/`；JIRA-backed source
   container 位於 `docs-manager/src/content/docs/specs/companies/{company}/{ticket}/`。
2. **No JIRA write**：ticketless DP source 不寫 JIRA comments、labels、descriptions、sub-tasks。
   若 DP 工作需要正式 cross-team document，route 到 `sasd-review` 或明確建立 JIRA ticket
   後再走 JIRA-backed source flow。
3. **DP number allocation**：DP-NNN 由 `scripts/create-design-plan.sh` 全域分配；JIRA key 由
   JIRA 系統分配。`refinement` 不負責 DP number assignment，也不負責 JIRA ticket creation。
4. **Source-state writer**：DP `status` 由 refinement / breakdown / framework-release 等
   skill 透過 primary doc frontmatter writer 統一管理；JIRA `status` 透過 JIRA transition
   API 管理，並依 company-specific transition map 進行。
5. **Closeout**：DP 完成後由 `scripts/mark-spec-implemented.sh` 等 closeout chain
   negotiate；JIRA-backed source 的 closeout 依 company JIRA convention。

這些 inherent property 只是 source type 的本質差異，不影響 refinement 主流程的 source-neutral
shape。所有 source type 共用同一條 refinement → breakdown → engineering → verify-AC 主鏈。
