# Refinement DP Source Mode

`refinement` ticketless / DP-backed source handling 的 progressive-disclosure reference。

當 `refinement` 將 source 解析為以下類型時使用：

- `dp`：既有 `DP-NNN` design-plan container
- `topic`：必須成為 DP container 的新 ticketless topic
- `artifact_path`：`docs-manager/src/content/docs/specs/design-plans/DP-NNN-*` 底下的 path

核心邊界：`refinement` owns design record 與 artifact output；DP-backed work 不寫 JIRA。

## T0. Resolve Source

透過 `spec-source-resolver.md` resolve source。

| Input | Action |
|-------|--------|
| `DP-NNN` | Locate exactly one `docs-manager/src/content/docs/specs/design-plans/DP-NNN-*` container；`index.md` 為 canonical primary doc，legacy `plan.md` 只作 fallback |
| direct DP plan/refinement path | 使用該 DP folder 作為 `source_container` |
| topic phrase | 呼叫 `scripts/create-design-plan.sh` 分配下一個 archive-aware `DP-NNN-{slug}` folder，建立完整 metadata `index.md`，設定 `status: DISCUSSION` |
| `SEEDED` DP | 若存在 `artifacts/research-report.md`，讀取並轉成 candidate Decisions |
| `LOCKED` / `IMPLEMENTED` DP | 新 topic overwrite 必須 fail loud；只有使用者明確 resuming/reviewing 該 DP 時才繼續 |

DP locator hard rules：

- `DP-NNN` 必須唯一 match 一個 folder。
- Zero 或 multiple matches 必須 fail loud。
- 不可默默建立同號 replacement DP。
- `LOCKED` / `IMPLEMENTED` DP 不可被 new topic overwrite。方向改變時，開新 DP 並加 see-also links。

## T1. Create Or Update DP Plan

新 topic 必須使用單一建單入口，不可手動 `mkdir` 或手寫 minimal template：

```bash
bash scripts/create-design-plan.sh "<durable topic>"
```

`create-design-plan.sh` 會：

1. 掃描 active + archive parent `index.md` / `plan.md`，分配全域最大 DP number + 1。
2. 建立 `{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{topic-slug}/index.md`。
3. 寫入完整 DP metadata：`title`、`description`、`topic`、`created`、`status`、`priority`、`sidebar`。
4. 呼叫 `scripts/validate-dp-plan-authoring.sh`，讓語言、Starlight、DP metadata、sidebar、route-safe path 與 DP number collision gate 一次通過。

若 command 失敗，必須修正 root cause 後重跑；不可改回手動建單。

DP template authority 規則：

- 新 DP 一律以 `create-design-plan.sh` 產出的 container 為準；不可搜尋 sibling DP 來推導
  frontmatter 或章節模板。
- 既有 DP 重跑 / 重整時，直接更新同一個 `index.md` / `refinement.md` / `refinement.json`
  container；不可刪掉後用別張 DP 內容複製回填。
- 若 authoring shape 不清楚，回讀本 reference 與 validator 輸出；不要用「先找一張像的
  DP」當預設流程。

`refinement` owns these DP sections:

- `## Goal`
- `## Background`
- `## Target State`
- `## Decision Policy`
- `## Migration Boundaries`
- `## Decisions`
- `## Blind Spots`
- `## Acceptance Criteria`
- `## Technical Approach` / `## 技術方案`

Framework contract DPs 在 handoff 前，plan 必須包含 target-state-first sections：

- `## Target State`：migration 後的 final source of truth、runtime ownership、handoff boundary、steady-state paths。
- `## Decision Policy`：選擇 direct migration 或 phased delivery 的規則。
- `## Migration Boundaries`：任何 temporary compatibility / fallback / bridge / mirror / dual-source mechanism，必須寫 owner、removal criteria、verification method、follow-up task。

如果 framework DP 提出 phased compatibility 但缺少這些欄位，先停下來補完 design，再進 implementation 或 breakdown。Compatibility scaffolding 不可成為 steady state。

每個使用者確認的 design decision 都必須先更新 primary DP doc（新 container 為 `index.md`，legacy
container 可是 `plan.md`），再繼續 unrelated work。不可只把 confirmed decisions 留在
conversation memory。

每次建立或更新 primary DP doc 後，必須先跑 DP authoring wrapper，通過後才能回報給使用者：

```bash
bash scripts/validate-dp-plan-authoring.sh \
  {workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/index.md
```

若 gate 失敗，先修正自然語言、metadata、sidebar、route path 或 DP number collision 後重跑。primary
DP doc 違反 wrapper 時，不可宣稱 DP 已可 review。

Starlight `docsSchema()` 要求每個 docs markdown 都有 `title`。`refinement`
建立任何新的 `index.md` / legacy `plan.md` 或 `refinement.md` 時，必須寫入 stable `title`
frontmatter；不可依賴 docs-manager 在 build 時補 metadata。

## T2. Docs-Manager Preview

建立或編輯 DP markdown 後，docs-manager 會直接從 `{workspace_root}/docs-manager/src/content/docs/specs/`
讀取 canonical source。必須先跑 T1/T3 的 language gate；未通過 workspace
language policy 的新產生 prose 不可進入 review 或 downstream handoff。

正式 preview surface 是 docs-manager Starlight route。DP-backed source 的常用 route：

```text
/docs-manager/specs/design-plans/dp-nnn-topic/plan/
/docs-manager/specs/design-plans/dp-nnn-topic/refinement/
/docs-manager/specs/design-plans/dp-nnn-topic/tasks/t1/
```

JIRA-backed source 同樣使用 company specs route：

```text
/docs-manager/specs/companies/{company}/{ticket}/refinement/
```

Live review route 由 docs-manager canonical specs 直接提供；framework 只產出
markdown 與 route，不替使用者啟動或重啟 docs viewer。

Static/search verification（先由使用者啟動 preview viewer，再驗證該 port）：

```bash
bash scripts/polaris-toolchain.sh run docs.viewer.verify -- --ports <preview-port> --preview
```

這適用於 `index.md` / legacy `plan.md`、`refinement.md`，以及任何準備進 review 的 DP
markdown artifact。

## T3. Refinement Markdown Output

Ticketless source 仍採 local-first refinement。Discussion output 寫入：

```text
{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.md
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

DP-backed `refinement.md` 的 acceptance criteria 不可使用較弱模板；必須沿用與
Epic-backed refinement 相同的 hardened AC 結構：

- `功能 AC`
- `非功能 AC`
- `負面 AC`
- `驗證方式`

若某一輪沒有相關非功能 AC，需明確寫 `N/A` 或原因；不可直接省略，避免 ticketless source
退化成只剩功能描述。

完整 decision history 保留在 primary DP doc（新 container 為 `index.md`，legacy fallback
為 `plan.md`）。

每次建立或更新 `refinement.md` 後，必須先跑 workspace language gate，通過後才能
preview、sidebar sync 或 downstream handoff：

```bash
bash scripts/validate-language-policy.sh \
  --blocking \
  --mode artifact \
  {workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.md
```

同一輪若同時改了 primary DP doc 與 `refinement.md`，用同一個 command 一起驗。若 gate
失敗，先修正 artifact language，再開 preview 或繼續 refinement flow。

## T4. Artifact Output

準備 handoff 時，produce 或 update：

```text
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.md
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.json
```

DP-backed `refinement.json` 的 validator gateway 見 `pipeline-handoff.md` § Artifact
Schemas；完整 producer schema 見 `refinement-artifact.md`。本節只保留最小定位框架：

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

Artifact 必須保留足夠的 scope、AC、dependencies、edge cases、downstream hints，讓 `breakdown DP-NNN` 不需要重做 refinement 就能 create work orders。

DP / Epic 的 artifact contract 一致：

- `acceptance_criteria[]` 每條 AC 都要保留驗證方式。
- 新 producer 應為每條 AC 寫 `category`，值為 `functional`、`non_functional`、`negative`
  其中之一，避免 human-only markdown 分類在 JSON artifact 中流失。
- `negative: true/false` 可保留作 legacy compatibility，但不能取代 `category` 的分類語意。

`predecessor_audit` 是 refinement handoff 的必讀欄位；沒有 predecessor 時也必須明確寫 `[]`，不可省略。若 successor 吸收任何 predecessor scope，entry 至少要包含：

- `spec_id`
- `disposition`: `KEEP` / `PARTIAL_ABSORB` / `FULLY_SUPERSEDED`
- `rationale`
- `writeback.required`
- `writeback.summary`
- `writeback.expected_status`
- `writeback.checklist_attribution`

一致性規則：

- `KEEP`：保留 predecessor current lifecycle，不做 source writeback
- `PARTIAL_ABSORB`：必須寫回 predecessor disposition note / checklist attribution，但 predecessor 仍保留 residual ownership
- `FULLY_SUPERSEDED`：必須寫回 predecessor disposition，且預期 terminal status 為 `SUPERSEDED`

## T5. LOCKED Handoff Gate

當使用者說「定版」、「開始做」、「可以執行」、「lock」或同義語：

1. 檢查 Goal、Decisions、Blind Spots、Acceptance Criteria、Technical Approach 是否足夠交給 breakdown。
2. 確認 `refinement.md` 與 `refinement.json` 是 current；`refinement.json` 必須通過 `scripts/refinement-handoff-gate.sh`。
   這不是 DP-only 規則，而是所有 refinement-owned source 的 LOCK / breakdown handoff
   規則。DP 只是其中一種 source；Epic / Story / Task / ticketless topic 同樣不得在缺
   handoff artifact 時提示 breakdown。
   若本輪 decisions / dependencies / Background 已吸收 predecessor scope，`predecessor_audit`
   不得為空，且每筆 entry 都必須把 disposition 與 writeback 寫清楚；不可只留在 prose。
3. 將 DP frontmatter 改為：
   ```yaml
   status: LOCKED
   locked_at: YYYY-MM-DD
   ```
4. 跑 `scripts/validate-dp-plan-authoring.sh {source_container}/index.md`；若是 legacy
   container 則對 `plan.md` 跑同一個 wrapper。相關 artifact validator / handoff gate 任一失敗或缺
   `refinement.json`，先停下來 produce/fix artifact。
5. 若需要 route/search review，跑 docs-manager dev 或 preview verification。
6. 告知使用者下一個 command：
   ```text
   breakdown DP-NNN
   ```

DP-backed source 在此之後仍走正規施工鏈：`breakdown -> engineering -> (verify-AC when
verification artifact exists)`。`framework-release` 不是 planning/implementation 捷徑，
只能消費 engineering 已建立的 workspace PR。

Ticketless source 不寫 JIRA comments、labels、descriptions、sub-tasks。若需要正式 cross-team document，route 到 `sasd-review` 或明確建立 JIRA ticket。
