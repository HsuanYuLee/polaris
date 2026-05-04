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
| `DP-NNN` | Locate exactly one `docs-manager/src/content/docs/specs/design-plans/DP-NNN-*/plan.md` |
| direct DP plan/refinement path | 使用該 DP folder 作為 `source_container` |
| topic phrase | 分配下一個 `DP-NNN-{slug}` folder，建立 `plan.md`，設定 `status: DISCUSSION` |
| `SEEDED` DP | 若存在 `artifacts/research-report.md`，讀取並轉成 candidate Decisions |
| `LOCKED` / `IMPLEMENTED` DP | 新 topic overwrite 必須 fail loud；只有使用者明確 resuming/reviewing 該 DP 時才繼續 |

DP locator hard rules：

- `DP-NNN` 必須唯一 match 一個 folder。
- Zero 或 multiple matches 必須 fail loud。
- 不可默默建立同號 replacement DP。
- `LOCKED` / `IMPLEMENTED` DP 不可被 new topic overwrite。方向改變時，開新 DP 並加 see-also links。

## T1. Create Or Update DP Plan

新 topic：

1. 掃描 `{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-*`。
2. 分配既有最大 number + 1。
3. 建立 `{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{topic-slug}/plan.md`。
4. 寫入 frontmatter：
   ```yaml
   ---
   title: "DP-NNN: <durable topic>"
   topic: <durable topic>
   created: YYYY-MM-DD
   status: DISCUSSION
   ---
   ```
5. 加上初始 `## Goal`、`## Background`，若已知 open decisions 則先放 placeholders。

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

每個使用者確認的 design decision 都必須先更新 `plan.md`，再繼續 unrelated work。不可只把 confirmed decisions 留在 conversation memory。

每次建立或更新 `plan.md` 後，必須先跑 workspace language gate，通過後才能
sidebar sync 或回報給使用者：

```bash
bash scripts/validate-language-policy.sh \
  --blocking \
  --mode artifact \
  {workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/plan.md
```

若 gate 失敗，先修正自然語言內容並重跑。`plan.md` 違反 workspace language
時，不可宣稱 DP 已可 review。

Starlight `docsSchema()` 要求每個 docs markdown 都有 `title`。`refinement`
建立任何新的 `plan.md` 或 `refinement.md` 時，必須寫入 stable `title`
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

Live review：

```bash
bash scripts/polaris-toolchain.sh run docs.viewer.dev
```

Static/search verification：

```bash
bash scripts/polaris-toolchain.sh run docs.viewer.doctor
```

這適用於 `plan.md`、`refinement.md`，以及任何準備進 review 的 DP markdown artifact。

## T3. Refinement Markdown Output

Ticketless source 仍採 local-first refinement。Discussion output 寫入：

```text
{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.md
```

Preview 不再啟動獨立 markdown renderer；使用 T2 的 docs-manager route。`scripts/refinement-preview.py`
若仍存在，只能作為 legacy fallback 或 local debug helper，不能作為 handoff contract。

`refinement.md` 只應包含 downstream implementation information：

- scope
- technical approach
- acceptance criteria
- edge cases
- risks
- references

完整 decision history 保留在 `plan.md`。

每次建立或更新 `refinement.md` 後，必須先跑 workspace language gate，通過後才能
preview、sidebar sync 或 downstream handoff：

```bash
bash scripts/validate-language-policy.sh \
  --blocking \
  --mode artifact \
  {workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.md
```

同一輪若同時改了 `plan.md` 與 `refinement.md`，用同一個 command 一起驗。若 gate
失敗，先修正 artifact language，再開 preview 或繼續 refinement flow。

## T4. Artifact Output

準備 handoff 時，produce 或 update：

```text
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.md
docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/refinement.json
```

DP-backed `refinement.json` 必須包含：

```json
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-NNN",
    "container": "{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}",
    "plan_path": "{workspace_root}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-{slug}/plan.md",
    "jira_key": null
  }
}
```

Artifact 必須保留足夠的 scope、AC、dependencies、edge cases、downstream hints，讓 `breakdown DP-NNN` 不需要重做 refinement 就能 create work orders。

## T5. LOCKED Handoff Gate

當使用者說「定版」、「開始做」、「可以執行」、「lock」或同義語：

1. 檢查 Goal、Decisions、Blind Spots、Acceptance Criteria、Technical Approach 是否足夠交給 breakdown。
2. 確認 `refinement.md` 與 `refinement.json` 是 current；`refinement.json` 必須通過 `scripts/refinement-handoff-gate.sh`。
3. 將 DP frontmatter 改為：
   ```yaml
   status: LOCKED
   locked_at: YYYY-MM-DD
   ```
4. 跑相關 artifact validator / handoff gate。若失敗或缺 `refinement.json`，先停下來 produce/fix artifact。
5. 若需要 route/search review，跑 docs-manager dev 或 preview verification。
6. 告知使用者下一個 command：
   ```text
   breakdown DP-NNN
   ```

Ticketless source 不寫 JIRA comments、labels、descriptions、sub-tasks。若需要正式 cross-team document，route 到 `sasd-review` 或明確建立 JIRA ticket。
