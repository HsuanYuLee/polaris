# Quality Check Flow

工程師在 commit 前的自檢流程 — lint、test、coverage、risk 評分、輸出報告。

**消費者**：`engineer-delivery-flow.md § Step 2`（Developer 與 Admin 兩角色共用）。

本 reference **不是獨立的 skill 觸發詞** — 無 ad-hoc 入口，只被 engineer-delivery-flow 內部呼叫。工程師自檢是交付的一部分，不該單獨觸發。

## 原 dev-quality-check 的差異

| 原 dev-quality-check | 新 quality-check-flow |
|---------------------|----------------------|
| 獨立 skill，有觸發詞 | Reference，無觸發詞 |
| Step 6 Nuxt build smoke + nginx proxy | **刪除** — 改由 engineer-delivery-flow § Step 3 Behavioral Verify 處理（框架無關） |
| Step 8b VR trigger | **移走** — 在 engineer-delivery-flow § Step 3 後做條件觸發 |
| Step 9 寫 `/tmp/.quality-gate-passed-{BRANCH}` marker + pre-push hook | **刪除** — 合併到 evidence file + pre-PR hook |
| 跨 framework 硬編碼（nuxi prepare 等） | 泛化 — 只做 lint/test/coverage |

## Scripts

| Script | 用途 |
|--------|------|
| `{workspace_root}/scripts/detect-project-and-changes.sh` | 偵測專案類型 + 變更檔案 + 測試覆蓋狀態 |
| `{workspace_root}/scripts/pre-commit-quality.sh` | 執行 lint → typecheck → test，寫 quality evidence |
| `{workspace_root}/scripts/quality-gate.sh` | PreToolUse hook — 沒有 quality evidence 就擋 `git commit` |

### Deterministic Gate

`quality-gate.sh` 是 PreToolUse hook，在 `git commit` 前檢查 `/tmp/polaris-quality-{branch}.json` 是否存在且 all_passed。**這是確定性的** — LLM 無法繞過。

**呼叫順序**：
1. 本 reference 的 Step 0-5 執行品質檢查（行為層）
2. 檢查全部通過後，呼叫 `pre-commit-quality.sh --repo <path>` 寫入 evidence（確定性層）
3. `git commit` 時 `quality-gate.sh` hook 驗證 evidence 存在
4. evidence 不存在或有 FAIL → hook exit 2 擋下 commit

**Bypass**：`POLARIS_SKIP_QUALITY=1`（WIP commit）或 commit message 以 `wip:` 開頭。

## Step 0 — Detect Project + Changed Files + Test Coverage

```bash
bash {workspace_root}/scripts/detect-project-and-changes.sh --project-dir <repo>
```

輸出 JSON：

```json
{
  "project": "<name>",
  "test_framework": "vitest | jest | ...",
  "base_branch": "develop | main",
  "test_command": "...",
  "coverage_command": "...",
  "lint_command": "...",
  "changed_files": [...],
  "test_files": [{"source": "...", "test": "...", "exists": true}],
  "test_files_to_run": [...],
  "missing_tests": [...],
  "stats": {"source_files": N, "has_test": N, "missing_test": N}
}
```

Script 自動處理：
- 專案類型偵測（vitest.config / jest.config / gulpfile / composer.json）
- 變更檔案合併（staged + unstaged + branch diff 去重）
- 測試檔案比對（`.test.ts` / `.spec.ts` / `__tests__/`）
- 例外檔案剔除（`types.ts`、`constants.ts`、`*.d.ts`、`*.config.*`）

### 0-files Guardrail

若 `source_files: 0` 但 `git status --short` 顯示有變更：
- **不可直接通過**。手動列出變更檔案，對這些檔案跑 lint + test + coverage
- 常見原因：檔名在剔除清單但實際需要檢查；或 diff 源錯誤

### 缺少測試處理

根據 `missing_tests` 欄位：
1. 警告使用者，列出無對應測試的 source file
2. 詢問是否自動產生測試（invoke `unit-test` reference 的 TDD 模式）
3. 若使用者選擇不補 → 記錄原因納入 evidence file 的 `layer_a.notes`

---

## Step 1 — Run Related Tests

依偵測到的框架執行：

```bash
# Vitest
npx vitest run <test-files> --reporter=verbose

# Jest
npx jest <test-files> --verbose
```

**所有測試必須通過**。失敗時分析原因並修復，**不跳過**。

### Re-test-after-fix 鐵律

若為了修測試失敗或 lint 錯誤而改了 code，**所有測試和 lint 必須重跑**。上一輪結果無效。

適用情境：
- 測試失敗 → 改 code → 必須重跑 test
- Lint 錯 → 改 code → 必須重跑 lint
- Coverage 不足 → 補測試 → 必須重跑 coverage

絕不用舊結果放行 commit。

---

## Step 2 — Coverage Check（Mandatory）

### Pre-flight：確認 coverage 工具已安裝

**Vitest 專案**：

```bash
node -e "require.resolve('@vitest/coverage-v8')" 2>/dev/null
```

失敗（exit ≠ 0）→ 立即安裝：

```bash
VITEST_VER=$(node -p "require('vitest/package.json').version" 2>/dev/null || echo "")
pnpm -C <project-dir> add -D @vitest/coverage-v8@${VITEST_VER} --filter <package-name>
```

**Jest 專案**：coverage 內建，無需 pre-flight。

### 執行

```bash
# Vitest（Monorepo 特別注意：必須從 vitest.config 所在目錄執行）
cd <project>/apps/main && npx vitest run <test-files> \
  --coverage --coverage.include='<source-path>/**'

# Jest
npx jest <test-files> --coverage \
  --collectCoverageFrom='<source-path>/**/*.{ts,tsx,vue,js,jsx}'
```

**Monorepo pitfall**：不可用 `npx --prefix <project>` 從 workspace root 執行。Vite 會從 root 的 node_modules 解析，但 root 和子目錄可能有不同 vitest 版本，造成 module resolution 失敗。

### 預估 Codecov patch coverage

本地跑出 coverage 後，對照 main-core threshold（通常 60% — 依 repo `codecov.yml` 設定）預估會不會被 CI 擋。不足則先補測試。

---

## Step 3 — ESLint

```bash
npx eslint <changed-files> --no-fix
```

有錯時：
1. 嘗試自動修正：`npx eslint <changed-files> --fix`
2. 無法自動修正的 → 列具體錯誤 + 修正建議
3. **禁止使用 `eslint-disable` 繞過** — 理由是 lint 規則背後通常有 reviewable patterns（通常來自 review lessons），繞過等於埋地雷

---

## Step 4 — Verification Gate Pattern

每個驗證步驟（Step 1-3）都遵循：

1. **IDENTIFY** — 確認要跑什麼命令
2. **RUN** — 完整執行
3. **READ** — 仔細閱讀完整輸出（不是只看前幾行）
4. **VERIFY** — 確認輸出支持結論

**禁止**：
- 跑了命令但只看前幾行就說「通過」
- 「應該沒問題」但沒實際跑驗證

---

## Step 4b — Write Quality Evidence

所有品質檢查通過後（Step 1-4 無 FAIL），呼叫 `pre-commit-quality.sh` 寫入確定性 evidence：

```bash
bash {workspace_root}/scripts/pre-commit-quality.sh --repo <project-dir>
```

Script 自動偵測 lint / typecheck / test 指令並執行，全部通過時寫入 `/tmp/polaris-quality-{branch}.json`。

**注意**：若 Step 1-3 已經手動跑過 lint/test 並通過，`pre-commit-quality.sh` 會重跑一次 — 這是 by design，確保 evidence 反映最新狀態。

若 script 回報 FAIL（exit 1）→ 回到對應步驟修正，不可手動建 evidence 檔案。

---

## Step 5 — Risk Scoring（Advisory）

計算變更的風險分數 0-100。**此分數是 advisory**（提示工程師與使用者），**不 block PR**。理由：很多高風險變動（關鍵路徑的必要 bugfix）就是該出，block 只會推使用者繞過；低風險的爛 PR 也不會因為分數低變好。真正 block 的是 evidence file 裡的 FAIL。

### 計分訊號

| 訊號 | 權重 |
|------|------|
| 變更檔案數 | +2/file，上限 20 |
| 變更行數 | +1 / 50 lines，上限 10 |
| 關鍵路徑（路徑含 `checkout` / `payment` / `pay` / `order/create` / `auth` / `login` / `register` / `cart/submit`）| +20 |
| 測試覆蓋比 | `(1 − has_test/source_files) × 15`，全覆蓋 = 0 |
| 新增依賴（`package.json` `dependencies` 新增）| +10 |
| 設定檔變更（config、env、CI 相關）| +5 |
| 共用元件（變更檔案被 ≥ 5 個檔案 import）| +10 |

加總後 cap 在 0-100。

### 判讀門檻

| 分數 | 等級 | 處置 |
|------|------|------|
| 0-30 | 🟢 LOW | 繼續 |
| 31-60 | 🟡 MEDIUM | 在報告中顯示警告 + 列主要風險因子，繼續 |
| 61-100 | 🔴 HIGH | 列所有風險因子，**提示使用者**（不 block），由使用者決定是否加 reviewer / 拆 PR |

---

## Step 6 — Output Report

```
品質檢查結果（{base_dir}/{project}）
─ Framework: {vitest | jest | ...}
─ 變更檔案: N 個 source files
─ 測試覆蓋: M/N 檔有對應測試
  └─ 缺少測試: {列出，或 "無"}
─ 測試結果: X passed / Y failed
─ Coverage: {pct}% (main-core threshold: {pct}%, {PASS/FAIL})
─ ESLint: {通過 | N 個錯誤}
─ 風險評分: {score}/100 {🟢/🟡/🔴} {LOW/MEDIUM/HIGH}
─ 結論: {✅ 可進入 behavioral verify | ⚠️ 需修正後重跑}
```

**結論 ✅** → engineer-delivery-flow 進 Step 3
**結論 ⚠️** → 修正後從 Step 1 重跑

---

## 和其他 reference 的關係

- [engineer-delivery-flow.md](engineer-delivery-flow.md) — 本 reference 的唯一消費者（Step 2）
- `unit-test` skill — 補測試時 invoke 該 skill 的 TDD 指引

## 來源

從原 `.claude/skills/dev-quality-check/SKILL.md`（v3.2.0）轉型。2026-04-14 engineering 重構 v2 的 Phase 1 產出（見 memory `project_workon_redesign_v2.md`）。

原 skill 的 Step 6 Nuxt build smoke 段、Step 8b VR trigger、Step 9 gate marker 已移除或搬移（詳見本文件 § 原 dev-quality-check 的差異）。
