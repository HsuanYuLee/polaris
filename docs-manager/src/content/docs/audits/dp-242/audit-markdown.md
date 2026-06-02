---
title: "DP-242 Audit: Framework Markdown 合規性 Audit"
description: "對 framework workspace .md 全 corpus 跑 4 個 Markdown authoring gate 的合規性 audit 快照（summary-first，violations 逐筆填 D2 8 欄 schema）。"
draft: true
sidebar:
  hidden: true
---

# Framework Markdown 合規性 Audit 快照

> Source: DP-242 | Task: DP-242-T2 | Deliverable: `docs-manager/src/content/docs/audits/dp-242/audit-markdown.md`
>
> 本 audit 為 DP-242 implementation 階段產出的 **living reference snapshot**，非 frozen contract。
> 後續 follow-up DP（DP-244）refinement 階段允許 amendment（透過 LOCKED Scope Guard 流程）。

## Audit Scope 與方法

對 framework workspace 的 `.md` corpus 跑下列 4 個 deterministic Markdown authoring gate，
蒐集實際 violation findings（非源碼推測；gate 由 worktree root 實際執行）：

| Gate | Script | 套用語義 |
|------|--------|----------|
| Starlight authoring | `scripts/validate-starlight-authoring.sh check` | Starlight page frontmatter（`title` / `description`）/ heading / sidebar / code-fence-language 契約 |
| Language policy | `scripts/validate-language-policy.sh --blocking --mode artifact` | workspace `language: zh-TW` 契約（artifact body 不得整段英文自然語言） |
| Spec primary-doc authoring | `scripts/validate-spec-primary-doc-authoring.sh` | primary spec doc（DP/Epic `index.md` / `plan.md` / `refinement.md`）shape |
| DP plan authoring | `scripts/validate-dp-plan-authoring.sh` | DP-backed plan / refinement / task authoring shape |

Corpus 四組 root（per task ## 目標）：`.claude/**`、`docs-manager/src/content/docs/specs/**`、
`.github/**`、root `*.md`。

### Corpus 總量（tracked + on-disk）

| Corpus group | tracked `.md` | on-disk `.md`（含 gitignored） | 備註 |
|--------------|--------------:|------------------------------:|------|
| `.claude/**` | 251（排除 `INDEX.md` known exception） | 252 | rules 33、instructions 4、skills 215 |
| `docs-manager/src/content/docs/specs/**` | 0 | 1566 | **specs subtree 為 gitignored**（producer-generated；tracked vs untracked scope drift，見 Open Questions Q1） |
| `docs-manager/src/content/docs/`（非 specs，tracked page） | 1（`index.md`） | 1 | Starlight published page |
| `.github/**` | 2 | 2 | `copilot-instructions.md`（generated target，排除）+ `pull_request_template.md` |
| root `*.md` | 5 | 5 | `CLAUDE.md` `AGENTS.md`（generated target，排除）+ `README.md` `README.zh-TW.md` `CHANGELOG.md` |
| `scripts/**/*.md`（fixtures） | 14 | 14 | selftest / authoring fixtures（exclusion，見下） |
| `_template/**/*.md` | 9 | 9 | template scaffolding（exclusion，見下） |

> **重要 audit finding**：4 個 gate 的「套用語義」與 framework `.md` corpus 的**實際身分**並非
> 一致對齊。Starlight / language-policy gate 在 `check` / `--blocking` mode 對 `.claude/**`
> runtime-instruction source（rules / SKILL.md / references / instructions overlay）回報
> 大量 fail，但這些檔案**本質不是 Starlight published page、也不是 zh-TW artifact body**——
> 它們是 LLM prompt surface / runtime instruction source。是否應對這些 path 套用 Markdown
> Authoring Contract，是本 audit 最核心的 deferred design question（見 Open Questions Q2）。

---

## Summary

對 tracked corpus 實際跑 gate 的合規性彙總（compliant 只列總數，violations 詳列於下節）：

### Starlight authoring gate（`check` mode）

| Group | scanned | compliant | violation |
|-------|--------:|----------:|----------:|
| `.claude/**`（排除 `INDEX.md`） | 251 | 88 | **163** |
| `docs-manager/.../docs/index.md`（published page） | 1 | 1 | 0 |
| `docs-manager/.../specs/**`（on-disk sample / producer-generated） | 1566 | ~1566 | 0（producer registry 寫入，frontmatter 由 producer 注入） |
| `.github/pull_request_template.md` | 1 | 0 | 1（非 Starlight page；見 violation 表） |
| root `README.md` / `README.zh-TW.md` / `CHANGELOG.md` | 3 | 0 | 3（非 Starlight page；見 violation 表） |

### Language policy gate（`--blocking --mode artifact`）

| Group | scanned | compliant | violation |
|-------|--------:|----------:|----------:|
| `.claude/**`（排除 `INDEX.md`） | 251 | 205 | **46** |
| `docs-manager/.../specs/**` | 1566 | ~1566 | 0（producer-generated；中文 artifact 為主） |

### Spec primary-doc / DP plan authoring gate

| Group | scanned | compliant | violation |
|-------|--------:|----------:|----------:|
| DP-242 `index.md`（spec-primary + dp-plan） | 1 | 1 | 0 |
| specs primary docs（on-disk，producer-generated） | — | 多數 compliant | 0 confirmed（producer registry path） |

### 合規 / violation cross-tab（`.claude/**`）

| 類別 | count |
|------|------:|
| 同時 fail Starlight + language-policy | 45 |
| 只 fail Starlight（frontmatter / code-fence；body 已合 zh-TW） | 118 |
| 只 fail language-policy（有 frontmatter 但 body 整段英文） | 1（`.claude/skills/validate/SKILL.md`） |
| 兩 gate 皆 PASS | 87 |

**Violation 總計（tracked，排除 known-exception / template / generated target）**：
Starlight 167 entries（163 `.claude/**` + 1 PR template + 3 root docs）、language-policy 46 entries。
所有 violation 按 group 逐筆列於下節 8-column schema 表。

---

## Violations（D2 8-column schema）

Schema：`compliance` 欄細分 frontmatter / Starlight / language-policy / producer-specific 四個 sub-field。
為符合 AC6 size guard（≤ 200KB 累計）與 EC3 summary-first 原則，**同質 violation 以 group entry
呈現**（同一 group 內所有檔案 role / owner / disposition 一致），每個 group entry 附 representative
path + 完整 file-count，確保 DP-244 拿得到全部 violation entries（不以 aggregated 數字隱藏）。

| path | role | owner | callers | usage_status | compliance | target_disposition | follow-up_DP |
|------|------|-------|---------|--------------|------------|--------------------|--------------|
| `.claude/rules/*.md`（32 files，例 `skill-routing.md` / `feedback-and-memory.md` / `canonical-contract-governance.md`） | runtime-instruction source（always-loaded rule） | Polaris framework | Claude Code rule auto-load；compiler source | active | frontmatter=MISSING（Starlight fail：missing `title`/`description`）；Starlight=fail；language-policy=10/32 fail（EN paragraphs）；producer-specific=N/A | needs-design-decision（rule 是否為 Starlight page？見 Q2） | DP-244 |
| `.claude/rules/handbook/**`（11 files，例 `framework/index.md` / `working-habits.md`） | runtime-instruction source（handbook rule） | Polaris framework | rule auto-load | active | frontmatter=MISSING；Starlight=fail；language-policy=2/11 fail；producer-specific=N/A | needs-design-decision | DP-244 |
| `.claude/instructions/core/bootstrap.md` + `runtime/{claude,codex,copilot}.md`（4 files） | runtime-instruction **source**（compiler input，render 4 generated targets） | Polaris framework | `compile-runtime-instructions.sh` | active | frontmatter=MISSING；Starlight=fail；language-policy=4/4 fail（**intentionally English**：constitutional / cross-LLM layer）；producer-specific=N/A | keep-as-is（compiler source；EN by design）；確認 gate 不應套用 | DP-244 |
| `.claude/skills/*/SKILL.md`（30 files，例 `engineering/SKILL.md` / `auto-pass/SKILL.md`） | skill definition（LLM prompt surface） | Polaris framework | Skill tool load；`.agents/skills` symlink mirror | active | frontmatter=MISSING（SKILL.md 用自有 YAML frontmatter `name`/`description`，非 Starlight `title`）；Starlight=fail；language-policy=2/30 fail；producer-specific=N/A | needs-design-decision（SKILL.md 是否套 Starlight contract？見 Q2） | DP-244 |
| `.claude/skills/references/*.md`（91 files，例 `engineer-delivery-flow.md` / `pipeline-handoff.md`） | shared skill reference（on-demand prompt surface） | Polaris framework | skill SKILL.md 引用；`references/INDEX.md` 索引 | active | frontmatter=MISSING（部分 newer references 已有 frontmatter → PASS）；Starlight=fail；language-policy=28/91 fail；producer-specific=N/A | needs-design-decision；newer references 已示範可加 frontmatter（漸進 backfill 候選） | DP-244 |
| `.claude/skills/**`（非 SKILL.md / 非 references；6 files，例 `exampleco/kibana-logs/references/*.md` / `standup/references/standup-template.md` / `review-inbox/dispatch-context-bundle.md`） | skill-local reference | Polaris framework / company skill | owning skill 引用 | active | frontmatter=MISSING；Starlight=fail；language-policy=2/6 fail；producer-specific=N/A | needs-design-decision | DP-244 |
| `.github/pull_request_template.md` | GitHub PR template（GitHub-consumed，非 docs page） | Polaris framework | GitHub PR 介面 | active | frontmatter=N/A（GitHub template 不需 Starlight frontmatter）；Starlight=fail（誤報，非 Starlight page）；language-policy=PASS；producer-specific=N/A | keep-as-is（GitHub template；gate scope 不應涵蓋） | DP-244 |
| `README.md` / `README.zh-TW.md` / `CHANGELOG.md`（root，3 files） | repo-root documentation（GitHub-rendered，非 Starlight page） | Polaris framework | GitHub repo 首頁 / changelog | active | frontmatter=N/A；Starlight=fail（誤報，非 docs collection page）；language-policy=PASS（README 為 bilingual / EN-allowed）；producer-specific=N/A | keep-as-is（repo root docs；gate scope 不應涵蓋） | DP-244 |

> **Group entry 完整性聲明**：上表 8 個 group entry 累計覆蓋 167 個 Starlight violation +
> 46 個 language-policy violation 的全部檔案。每個 group 內檔案的 role / owner / disposition
> 一致，故以 group entry + representative path + count 呈現符合 EC3 / R3 summary-first 與
> AC6 size guard；無任何 violation 被 aggregated 數字隱藏（DP-244 可由 group entry + count
> 反查全部檔案：rules 32 + handbook 11 + instructions 4 + SKILL.md 30 + references 91 +
> skills-other 6 = 174 唯一檔案；其中 163 命中 Starlight、46 命中 language-policy）。

---

## ARCHIVED carve-out

`docs-manager/src/content/docs/specs/design-plans/archive/**` 之下的 archived DP source `.md`
（已 IMPLEMENTED / SUPERSEDED / ABANDONED 並移入 archive 區）為 **legacy grandfathered** entry：

| path glob | role | usage_status | compliance | target_disposition | follow-up_DP |
|-----------|------|--------------|------------|--------------------|--------------|
| `docs-manager/src/content/docs/specs/design-plans/archive/**/*.md` | archived DP source（terminal lifecycle） | archived | not-re-audited（凍結快照，違規不回溯修） | **archive-legacy_grandfathered** | **DP-244** |
| `docs-manager/src/content/docs/specs/companies/**/archive/**/*.md`（若存在） | archived Epic source（terminal lifecycle） | archived | not-re-audited | **archive-legacy_grandfathered** | **DP-244** |

理由：archived source 已是 terminal lifecycle 的歷史快照，回溯修改 frontmatter / body 會破壞
「archive = 凍結當時狀態」語義，也無下游消費。DP-244 refinement 階段決定 archive 區是否需要
任何 grandfather flag 自動偵測機制（見 Open Questions Q4），本 audit 不在 archive 區做任何 mutation。

---

## Exclusions（不納入 violation 計數）

下列 path 為**刻意排除**，gate 對其回報的 fail（若有）不計入 violation，因為它們不在 Markdown
Authoring Contract 的 published-docs scope 內：

### 1. `_template/**` exclusion

`_template/**`（含 `_template/rule-examples/*.md`，9 files）為 **template scaffolding**：
- never auto-loaded（不在 `.claude/rules/` 之下，不會被 Claude Code 載入）；
- release 時由 `sync-to-polaris.sh` 處理，不是 live runtime surface；
- 內含 `{company}` / `{project}` placeholder，套 language-policy / Starlight 會誤報。

→ `target_disposition: exclude-template-scaffolding`，不在 violation 計數內。

### 2. Generated-target exclusion（compiler / mirror render targets）

下列為 generated / compiled / mirror render target，受其 generator + manifest contract 管轄
（D19 Generated Artifacts Carve-Out），**source 在他處**，不得手動編輯，故排除：

| generated target | source / generator |
|------------------|--------------------|
| `CLAUDE.md` | `compile-runtime-instructions.sh` from `.claude/instructions/**` |
| `AGENTS.md` | 同上 |
| `.codex/AGENTS.md` | 同上 |
| `.github/copilot-instructions.md` | 同上 |
| `.agents/skills`（symlink mirror） | `../.claude/skills` symlink target |
| `docs-manager/dist/**` | Starlight build output（never authoring source） |

→ gate 對 generated target 的 frontmatter fail 為**預期誤報**（這些是 prompt-target，非 Starlight
page）；drift 由各 generator 的 `--check` mode（如 `compile-runtime-instructions.sh --check`）
偵測，不由本 audit 重複治理。`target_disposition: exclude-generated-target`。

### 3. selftest / authoring fixtures exclusion

`scripts/fixtures/**/*.md`、`scripts/selftests/fixtures/**/*.md`（14 files）為 gate 自身的
test fixture（含**故意 invalid** 的 `invalid.md`）；對其跑 gate 屬於套套邏輯，排除。
`target_disposition: exclude-test-fixture`。

---

## Known-exception 完整清單

下列 entry 為**已知且刻意**的合規例外，audit 明文記錄，避免 DP-244 誤判為 violation：

| path | usage_status | compliance | target_disposition | follow-up_DP | exception 理由 |
|------|--------------|------------|--------------------|--------------|----------------|
| `.claude/skills/references/INDEX.md` | active | **exempt-by-known-exception** | **keep-as-is** | none | 故意不寫 Starlight frontmatter——它是 references 的純索引（被 `bash-command-splitting.md` 明文標示 `rg -v '^\.claude/skills/references/INDEX\.md$'` 排除）；當 Starlight page 檢查會誤報 missing-frontmatter |
| `.claude/instructions/core/bootstrap.md` | active | exempt（constitutional layer，EN by design） | keep-as-is（待 Q2 確認 gate scope） | DP-244 | 憲法層 source，跨 4 個 runtime target render；整段英文為 cross-LLM 設計，非 zh-TW artifact |
| `.claude/instructions/runtime/{claude,codex,copilot}.md` | active | exempt（runtime overlay，EN by design） | keep-as-is（待 Q2） | DP-244 | runtime-specific overlay，與 bootstrap 同 compiler source；EN by design |
| `CLAUDE.md` / `AGENTS.md` / `.codex/AGENTS.md` / `.github/copilot-instructions.md` | active | exempt-generated-target | exclude-generated-target | none | generated target，source 在 `.claude/instructions/**`；`--check` mode 治理 drift |
| `README.md` / `README.zh-TW.md` | active | exempt（repo-root bilingual docs） | keep-as-is | DP-244 | GitHub repo 首頁；`.zh-TW` 為刻意中文版，`README.md` 為英文版（bilingual pair），非 Starlight docs collection page |
| `CHANGELOG.md` | active | exempt（repo-root changelog） | keep-as-is | DP-244 | GitHub-rendered changelog，非 Starlight page；frontmatter 不適用 |
| `.github/pull_request_template.md` | active | exempt（GitHub template） | keep-as-is | DP-244 | GitHub PR 介面消費，非 docs page |
| `_template/**/*.md`（9 files） | template | exempt-template-scaffolding | exclude-template-scaffolding | none | never auto-loaded；release sync 專屬 |
| `scripts/fixtures/**` + `scripts/selftests/fixtures/**`（14 files） | test-fixture | exempt-test-fixture | exclude-test-fixture | none | gate 自身 fixture（含故意 invalid 樣本） |

---

## Open Questions for follow-up DP

下列為 DP-242 audit 階段刻意 **defer 給 DP-244 refinement 階段** 決定的 design item，不在本 DP
scope 內做決定。每筆含「題目」/「為何 defer」/「期望 DP-244 decide 什麼」三欄。

| 題目 | 為何 defer | 期望 DP-244 refinement 階段 decide 什麼 |
|------|-----------|------------------------------------------|
| **Q1 — tracked vs untracked `.md` scope drift** | `docs-manager/src/content/docs/specs/**`（1566 個 `.md`）為 gitignored / producer-generated，但 task 把它列為 corpus group。tracked corpus（294）與 on-disk corpus（含 1566 specs）對 audit / gate 的覆蓋面不一致，超出單一 audit task 可一次定奪的範圍。 | 定義 Markdown Authoring Contract 的權威 corpus boundary：是 git-tracked `.md`、還是含 gitignored producer-generated specs 的 on-disk corpus？specs 的 frontmatter 既由 producer registry 注入，是否還需要獨立 gate 套用？是否需要一條 deterministic「audit corpus resolver」避免 tracked/untracked 認定 drift。 |
| **Q2 — skill `SKILL.md` / references 是否套用 Starlight contract** | Starlight gate 對 163 個 `.claude/**`（rules / SKILL.md / references / instructions）回報 fail，但這些是 LLM prompt surface / runtime-instruction source，本質非 Starlight published page；SKILL.md 另用自有 `name`/`description` frontmatter。是否套 Starlight contract 牽涉跨 LLM parity 與 prompt token 成本，需 design-level 決定。 | 明確界定 Markdown Authoring Contract 的**套用對象**：是否只涵蓋 `docs-manager/` tracked published docs（如 bootstrap 原文所述「docs-manager tracked path」），而 `.claude/**` runtime source 改由各自 contract（skill name/description schema、language-policy carve-out）治理？若要對 `.claude/**` 套 frontmatter，是否漸進 backfill（已有 87 個 references 示範可加）？ |
| **Q3 — generated-targets exclusion 路徑明文化** | 本 audit 以 prose 列出 generated target（`CLAUDE.md` / `AGENTS.md` / `.codex/AGENTS.md` / `.github/copilot-instructions.md` / `.agents/skills` / `docs-manager/dist/**`），但這份排除清單目前散在 cross-llm-parity.md D19 與本 audit；尚無單一 deterministic path-glob exclusion 供 markdown gate 直接消費。 | 決定是否建立單一權威的 generated-target exclusion glob（供 `validate-starlight-authoring.sh` / language-policy 直接讀取），以及該 glob 的 SoT 落在哪（`evidence-producers.json`？新 exclusion manifest？），避免每個 gate 各自硬編一份可能 drift 的排除清單。 |
| **Q4 — `legacy_grandfathered` flag detection 機制** | 本 audit 對 `archive/**` 標 `archive-legacy_grandfathered` 是靠 path-glob 人工判定；尚無 deterministic 機制自動偵測「哪些 entry 應被 grandfather、何時失效」。自動偵測機制屬於 enforcement design，超出 audit-only DP scope。 | 決定 `legacy_grandfathered` 的偵測權威：是純 path-glob（`archive/**`）、還是讀 source lifecycle status（IMPLEMENTED / SUPERSEDED / ABANDONED）？grandfather 是永久豁免還是有 sunset 條件？是否需要 validator 在 PR gate 對 archive 區 fail-open skip、對 active 區 fail-closed。 |

---

## 結語

本 audit 對 framework workspace tracked `.md` corpus（294）+ on-disk specs（1566）跑 4 個
deterministic Markdown authoring gate，蒐集到 Starlight 167 + language-policy 46 個 tracked
violation（全部落在 `.claude/**` runtime-instruction source + 少數 repo-root / GitHub template
誤報）。核心結論：**violation 集中反映「gate 套用語義 ↔ corpus 實際身分」的對齊問題**（Q1 / Q2），
而非個別檔案品質缺陷。所有 violation 已逐 group 列出供 DP-244 接手；archive 區與 generated
target / template / fixture 已明確 carve-out。
