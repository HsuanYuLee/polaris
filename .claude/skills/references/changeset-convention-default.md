# Changeset Convention — Polaris L3 Default

Polaris 提供的 changeset 兜底規範。當 repo **L1 config**（`.changeset/config.json`）未明訂語意設定，且 **L2 handbook**（`{company}/polaris-config/{project}/handbook/**`）無 changeset 慣例段時，`scripts/polaris-changeset.sh` 與 LLM 依此 spec 機械化產出 changeset 檔。

**消費者**：`scripts/polaris-changeset.sh new`（純機械產出）+ `engineer-delivery-flow.md § Step 6b 蒸發後的 deliverable 路徑`（changeset 由 task.md `deliverables.changeset` 宣告 → engineering Phase 3 自然產出）。

**Source**：DP-032 D24（`specs/design-plans/DP-032-engineering-deterministic-extraction/plan.md` § D24）。本檔等同 D24 § Decision 鎖定的 L3 spec 機讀化版本。

---

## 1. Fallback Chain

| 層級 | 來源 | 角色 |
|------|------|------|
| **L1 Repo config** | `.changeset/config.json`（packages glob、changelog plugin、access、baseBranch 等） | **package_scope SoT**（mono-repo packages 列表、commit policy 等機器可讀） |
| **L2 Repo handbook** | `{company}/polaris-config/{project}/handbook/changeset-convention.md`（或等同位置） | **語意 spec**（`ticket_prefix_handling` / 語言一致性 / bump level default 慣例） |
| **L3 Polaris default**（本檔） | `references/changeset-convention-default.md` | **兜底**（L2 未宣告時的最後基準） |

**規則衝突處理**：L1 是機器設定（`.changeset/config.json` schema），L2 / L3 是語意慣例 — 兩者**不衝突**（互補）。L2 有定義就用 L2；L2 無 → 用 L3 default。

`.changeset/config.json` 不存在 → 該 repo 不走 changeset → engineering 不主動產 changeset 檔。只有 `.changeset/` 空目錄不算啟用；偵測條件必須是 repo root 下存在 `.changeset/config.json`。

---

## 2. task.md 宣告契約（DP-033 scope）

breakdown / engineering 先偵測 repo `.changeset/config.json` 存在，確認該 repo 有啟用 Changesets 後，才啟動 changeset deliverable 流程。breakdown 偵測成立時 task.md frontmatter 注入 `deliverables.changeset` block：

```yaml
deliverables:
  changeset:
    package_scope: "@exampleco/web"          # L1 .changeset/config.json packages 推導
    bump_level_default: patch             # L2 handbook 宣告，無則 L3 default = patch
    filename_slug: kb2cw-3788-product-heading-mobile-layout
```

**Allowed Files** 自動把 `.changeset/{filename_slug}.md` 加入。

`.changeset/config.json` 不存在 → 不宣告 → engineering 不動 changeset；`polaris-changeset.sh` 與 `gate-changeset.sh` 也必須 no-op exit 0。

> 註：DP-033 完成前，breakdown 端的注入流程仍在演化；本檔規範**消費端**行為（script 與 LLM 該怎麼解析這些欄位），生產端 schema 鎖定屬 DP-033。

---

## 3. L3 Default 規範

### 3.1 檔名 Slug 規則

格式：`{ticket-kebab}-{short-desc-kebab}.md`

| 元件 | 規則 |
|------|------|
| `ticket-kebab` | task.md ticket 小寫 + 連字符（`TASK-3788` → `kb2cw-3788`） |
| `short-desc-kebab` | task.md title 去 ticket prefix 後 kebab-case；移除標點與 emoji；長度上限 60 char（截斷時保留完整單字） |
| 副檔名 | `.md` |

**範例**：

| Task title | filename_slug |
|------------|--------------|
| `[TASK-3788] 產品頁 BreadcrumbList 加首頁 entry` | `kb2cw-3788-product-heading-mobile-layout`*（短描述由 breakdown 決定，title 過長時可裁剪）* |
| `[EPIC-521] BreadcrumbList SEO 優化` | `gt-521-breadcrumblist-seo` |
| `chore: bump pnpm`（Admin、無 ticket） | `chore-bump-pnpm` |

中文 / 非 ASCII 字符的 slug：保留底層 unicode（changeset 支援），但建議 breakdown 階段轉拼音 / 英文短描述（避免 git 跨平台檔名問題）。

### 3.2 Frontmatter

```
---
"{package_scope}": {bump_level}
---
```

| 欄位 | L3 default | 說明 |
|------|-----------|------|
| `{package_scope}` | 從 task.md `deliverables.changeset.package_scope` 帶入 | 必須與 `.changeset/config.json` packages 對齊；mono-repo 多 package 情境見 § 5 |
| `{bump_level}` | `patch` | LLM 可在呼叫 script 時 `--bump minor/major` override |

不加其他 frontmatter 欄位（changeset CLI 預設 schema 不需要）。

### 3.3 Body — Description 100% 機械化

**規則**：description = task.md title（去 ticket prefix），純機械產出，**LLM 不寫**。

| 步驟 | 動作 |
|------|------|
| 1 | 讀 task.md 的 `# {ticket}: {title}` heading 或 frontmatter `title` |
| 2 | 依 L2 handbook `ticket_prefix_handling` 處理（L3 default = `strip`） |
| 3 | 寫入 changeset body（單行；無額外 markdown 結構） |

**`ticket_prefix_handling` 三種模式**：

| 模式 | 行為 | 範例 |
|------|------|------|
| `strip`（**L3 default**） | 移除 `[TICKET]` / `TICKET:` 前綴 | `[TASK-3788] 產品頁 BreadcrumbList 加首頁 entry` → `產品頁 BreadcrumbList 加首頁 entry` |
| `keep` | 保留原樣 | `[TASK-3788] 產品頁 BreadcrumbList 加首頁 entry` → `[TASK-3788] 產品頁 BreadcrumbList 加首頁 entry` |
| `transform` | 自定義（L2 須附帶 transform spec） | repo-specific |

**L3 default = `strip`** 的理由：ticket key 已存在 changelog 的 PR / commit metadata 與檔名 slug，body 重複沒意義；保持 changelog 讀者體驗乾淨。Repo 若 changelog 讀者需看 ticket → 走 L2 `keep`。

### 3.4 完整 L3 範例

**檔名**：`.changeset/kb2cw-3788-product-heading-mobile-layout.md`

```
---
"@exampleco/web": patch
---

產品頁 BreadcrumbList 加首頁 entry
```

---

## 4. Script 行為（`polaris-changeset.sh new`）

```
polaris-changeset.sh new --task-md {path} [--bump {patch|minor|major}]
```

| 步驟 | 行為 |
|------|------|
| 1 | 讀 `--task-md` 指定的 task.md → frontmatter `deliverables.changeset` block |
| 2 | 解析 `package_scope` / `bump_level_default` / `filename_slug` |
| 3 | `--bump` 未指定 → 用 `bump_level_default`（L3 default = `patch`） |
| 4 | 讀 task.md title → 套用 `ticket_prefix_handling`（L3 default = `strip`）→ description |
| 5 | 寫 `.changeset/{filename_slug}.md`（frontmatter + body） |
| 6 | **Idempotent**：同 slug 檔已存 → 靜默 skip + exit 0（rebase 後重跑不該噪音、不該重產）|

**LLM 唯一語意保留 = `--bump` 判定**：

| 情境 | LLM 判斷 |
|------|---------|
| 一般功能 / 修正 / 重構 | `patch`（依 default 不傳 `--bump`） |
| 加新功能 / 新 public API | `--bump minor` |
| 破壞性變更（API breaking） | `--bump major` |

**Description 不傳 `--description`**：本 spec 不開放 LLM override description（避免 BS-D24-1 重新引入語意負擔）；description 永遠 = task.md title（strip 後）。

---

## 5. Mono-repo 多 Package 處理

`.changeset/config.json` 的 packages glob 可能匹配多個 package（`packages/*`）：

| 情境 | 處理 |
|------|------|
| 單一 package match | 直接寫入該 package |
| 多 package + Allowed Files 在單一 package 子樹 | breakdown 自動推導唯一 `package_scope` |
| 多 package + Allowed Files 跨 package | breakdown 在 task.md 列 `package_scope` candidates list；engineering 實作完成後選最終 scope（或拆 task） |

> 跨 package changeset（一個檔案宣告多個 package）的 schema：
>
> ```
> ---
> "@scope/pkg-a": patch
> "@scope/pkg-b": minor
> ---
> ```
>
> L3 不主動鼓勵跨 package 單一 changeset；多 package 影響較複雜，建議拆 task / 拆 changeset。Repo 若有跨 package 慣例 → L2 handbook 明訂。

`polaris-changeset.sh check` 另支援既有手寫 multi-package changeset：當 task
未宣告單一 `package_scope`、Allowed Files 推導出多個 candidate package，且
`.changeset/` 內有同 ticket 的 changeset frontmatter 覆蓋全部 candidates 時，
gate 視為通過。這只適用於 `check`；`new` 仍 fail loud，避免 framework 自行替
跨 package task 選 scope。

---

## 6. Inherited Cleanup（`changeset-clean-inherited.sh`）

**獨立於本 convention** — 純機械 git state 衛生（rebase 副作用），不在 task 交付路徑：

| 步驟 | 行為 |
|------|------|
| 1 | `git diff origin/{base} --name-only -- .changeset/` 列檔 |
| 2 | Parse 每檔 body / 檔名 → 提取 ticket key pattern |
| 3 | 不符當前 task ticket → `git rm` |

**呼叫點**：`engineering-rebase.sh` 完成 rebase 後**自動**呼叫，不在 delivery flow step 中暴露。

**完全跟 new creation 分離** — cleanup 是 git 衛生，不是 task 交付物。

---

## 7. Rebase 後 Idempotent

| 動作 | 是否觸發 changeset 重產？ |
|------|------------------------|
| `engineering-rebase.sh`（cascade rebase） | **否**（task 目標不變 → task title 不變 → description 不變） |
| `polaris-changeset.sh new` 誤呼叫 | **否**（idempotent skip） |
| `changeset-clean-inherited.sh`（rebase 後置） | 是（移除 inherited 檔，本 task 檔不動） |

**Rationale**：rebase 動的是 commit history，task 交付目標不變 → changeset 描述穩定 → 檔案不該重產（避免 PR diff 雜訊、避免 LLM 在 revision 階段重寫 description）。

---

## 8. Admin Mode

- Admin 流程**無 task.md** → 無 `deliverables.changeset` 宣告 → engineering 不主動產
- Framework repo 若 CI 要求 changeset → 由 DP-backed `engineering` task.md 明確宣告；不再走 Admin PR skill。
- Admin 手動產 changeset 時可參考本 spec 格式（subject 用 commit-style headline、`{type}: {summary}`）

---

## 9. Cross-LLM Notes

- 本 spec 為純文字 / 機讀規則，所有 LLM（Claude Code / Codex / Cursor / Gemini CLI）共用
- 不依賴 MCP / IDE plugin；產出由 `polaris-changeset.sh` 直接寫檔（pure bash + cat heredoc）
- LLM 唯一介入 = `--bump` 判定（語意分析）；description 100% 機械化

---

## 10. Do / Don't

- Do: 先 probe L1 → L2 → L3，互補使用（L1 = 機器、L2/L3 = 語意）
- Do: description = task.md title（strip 後），LLM 不重寫
- Do: rebase 後依賴 idempotent skip，不主動重產
- Do: cleanup 走獨立 script（`changeset-clean-inherited.sh`），不混進 new creation
- Don't: LLM 改 description（破 BS-D24-1 消解）
- Don't: 把 inherited changeset 的清理塞回 delivery flow step
- Don't: changeset 跨 package 預設啟用（保持單 package、必要時拆 task）
- Don't: `.changeset/config.json` 不存在還主動產 changeset

---

## Source

- DP-032 plan.md § D24（`specs/design-plans/DP-032-engineering-deterministic-extraction/plan.md`）
- 配套 reference：`commit-convention-default.md`（D22）、`pr-body-builder.md`（D23）
- 配套 script：`scripts/polaris-changeset.sh`（new、idempotent；待實作）+ `scripts/changeset-clean-inherited.sh`（rebase 後置；待實作）
- 上層消費：`engineer-delivery-flow.md § Step 6b`（D24 後 Step 6b 蒸發；changeset 走 task.md `deliverables` 自然產出路徑）
