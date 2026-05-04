# Epic Folder Structure

每個 Epic 的所有 artifacts 統一收在 `{company_specs_dir}/{EPIC_KEY}/` 下，讓 Epic 結案時一個 folder 帶走。

## Folder Schema

```
docs-manager/src/content/docs/specs/companies/{company}/{EPIC_KEY}/
├── refinement.md              # 多輪迭代紀錄（人讀）
├── refinement.json            # 定版 artifact（機器讀，schema: refinement-artifact.md）
├── breakdown.md               # breakdown summary（optional）
├── tasks/
│   ├── T1.md                  # work order per sub-task（schema: pipeline-handoff.md）
│   ├── T2.md
│   └── ...
├── tests/
│   ├── lighthouse/
│   │   ├── baseline-YYYY-MM-DD/   # Lighthouse JSON reports
│   │   └── direction-eval-YYYY-MM-DD/
│   ├── mockoon/                   # Mockoon environment JSONs（從 fixtures recording 或 bootstrap）
│   │   ├── dev.exampleco.com.json
│   │   ├── api-*.json
│   │   └── ...
│   └── vr/
│       └── baseline/              # VR baseline screenshots（永久，per-epic 快照）
│           ├── homepage-zh-tw-1280.png
│           └── ...
├── artifacts/                     # sub-agent detail files（exploration reports, analysis, intermediate output）
│   └── explorer-2026-04-17T0830.md
└── verification/                  # verify-AC evidence（上傳 JIRA 前的本地留底）
    └── {TICKET_KEY}/
        └── {timestamp}/
            ├── screenshot-1.png
            └── ...
```

完成或放棄後可 archive，路徑固定為：

```
docs-manager/src/content/docs/specs/companies/{company}/archive/{EPIC_KEY}/
```

Archive 是整個 container 的 move，不是 copy；active namespace 與 archive namespace 不可同時保留同一張單。只有 parent container 已標 `IMPLEMENTED` 或 `ABANDONED` 時，才可執行 `scripts/archive-spec.sh {EPIC_KEY}`。Archive 後 docs-manager 會直接讀取 `docs-manager/src/content/docs/specs/companies/{company}/archive/{EPIC_KEY}/` canonical folder tree；resolver / engineering 預設不再把它當 active work。

## Path Resolution

所有 skill 讀寫 Epic artifact 時，路徑一律經由以下公式推導：

```
{company_specs_dir}/{EPIC_KEY}/{artifact_subpath}
```

- `{company_specs_dir}`：`{workspace_root}/docs-manager/src/content/docs/specs/companies/{company}`
- `{EPIC_KEY}`：從 JIRA ticket、git branch（`feat/{EPIC}-*`）、或 command-line `--epic` 推導
- `{artifact_subpath}`：本 reference 定義

**禁止** hardcode framework config roots 或其他非 `specs/` 的路徑作為 Epic artifact 存放位置。

## Artifact Lifecycle

| Artifact | 寫入 Skill | 讀取 Skill | 生命週期 |
|----------|-----------|-----------|---------|
| `refinement.md` | refinement | breakdown, engineering | Epic 存續期 |
| `refinement.json` | refinement | breakdown, engineering | Epic 存續期 |
| `tasks/T*.md` | breakdown | engineering | Epic 存續期 |
| `tests/lighthouse/` | engineering, manual | refinement, breakdown | Epic 存續期 |
| `tests/mockoon/` | record-fixtures.sh, manual | visual-regression, `fixtures.mockoon` capability | Epic 存續期 |
| `tests/vr/baseline/` | visual-regression (record) | visual-regression (compare) | Epic 存續期 |
| `verification/` | verify-AC | verify-AC (re-run), human review | Epic 存續期 |

Framework DP release closeout 會在 parent DP 變成 `IMPLEMENTED` 後自動執行 archive
move；docs-manager 直接讀 canonical `specs/`，因此不需要額外 viewer sync。

Product Epic / Bug / Task closeout 後若不再需要留在 active sidebar，執行 archive helper：

```bash
scripts/archive-spec.sh {EPIC_KEY}
```

產品 specs 的 archive 刻意不是自動化 closeout 的一部分；執行者需確認該
Epic / Bug / Task container 已完成或已放棄，且短期不需要作為 active work 入口。

需要批次整理既有完成或放棄 specs 時，先產 dry-run report，再 apply：

```bash
scripts/archive-spec.sh --sweep --dry-run
scripts/archive-spec.sh --sweep --apply
```

Sweep 規則：

- company container 優先讀 `refinement.md` frontmatter `status`，沒有時讀 `plan.md`
- `IMPLEMENTED` / `ABANDONED` 會搬到 archive
- `SEEDED` / `DISCUSSION` / `LOCKED` / missing status 只會保留在 active namespace
- destination 已存在時 fail loud，避免 active/archive duplicate
- sweep 後 docs-manager 會直接讀 canonical specs；需要 review 時執行 `scripts/polaris-toolchain.sh run docs.viewer.dev`，需要 static/search 驗證時執行 `scripts/polaris-toolchain.sh run docs.viewer.doctor`

## Bootstrap（新 Epic）

新 Epic 建立 specs folder 時，可以從前一 Epic copy 特定 artifacts 作為起點：

1. **Mockoon fixtures**：`cp -r specs/{PREV_EPIC}/tests/mockoon/ specs/{NEW_EPIC}/tests/mockoon/`
   - 當前 Epic 的 API 通常與前一 Epic 大致相同
   - Copy 後再 record 新的 fixture 覆蓋差異
2. **VR baseline**：`cp -r specs/{PREV_EPIC}/tests/vr/baseline/ specs/{NEW_EPIC}/tests/vr/baseline/`
   - 前一 Epic 的 baseline 是新 Epic 的 "before" 快照

Bootstrap 不是自動的 — skill 在 Step 0 檢查 `tests/mockoon/` 或 `tests/vr/baseline/` 是否為空，若空則提示 bootstrap。

## Mockoon Path 解析

遷移前，workspace-config 用 `fixtures.environments_dir` + `fixtures.active_epic` 拼接 mockoon 路徑。

遷移後，mockoon 路徑由 Epic folder 直接決定：

```
# 舊（deprecated）
scripts/polaris-toolchain.sh run fixtures.mockoon.start -- {environments_dir} --epic {epic_key}

# 新
scripts/polaris-toolchain.sh run fixtures.mockoon.start -- {company_specs_dir}/{EPIC_KEY}/tests/mockoon
```

`workspace-config.yaml` 的 `fixtures` block 只保留工具層設定（ports、ready_signal），不再包含路徑或 Epic key。

## 公司共用 Mockoon Config

跨 Epic 共用的設定檔（proxy-config.yaml、demo.json 等）不隨 per-epic folder，存在公司層：

```
{company_base_dir}/mockoon-config/
├── proxy-config.yaml     # API routing overrides（跨 Epic 共用）
└── demo.json             # 示範環境（optional）
```

## 與其他 Reference 的關係

| Reference | 關係 |
|-----------|------|
| `refinement-artifact.md` | 定義 `refinement.json` schema |
| `pipeline-handoff.md` | 定義 `tasks/T*.md` schema |
| `visual-regression-config.md` | 定義 VR config（domain-level tooling，與 per-epic baseline 分離） |
| `api-contract-guard.md` | 定義 mockoon fixture schema drift detection |
| `epic-verification-structure.md` | 定義 verify-AC 驗收架構 |
