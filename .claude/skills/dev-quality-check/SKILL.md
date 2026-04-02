---
name: dev-quality-check
description: >
  Development quality gate: verifies test coverage, runs related tests, and checks code quality
  for changed files. Auto-detects project context (test framework, coverage config, base branch).
  Use when: (1) user finishes writing code and wants to verify quality,
  (2) user says "check tests", "run tests", "quality check", "coverage check", "品質檢查",
  "測試檢查", "跑測試", (3) before committing code (auto-invoked by git-pr-workflow),
  (4) user asks "is my code ready to commit", (5) user says "verify", "validate", "確認品質".
metadata:
  author: Polaris
  version: 3.2.0
---

# dev-quality-check

開發階段品質把關。在寫完程式後、commit 前執行，確保變更有足夠的測試覆蓋與品質。

## Scripts

本 skill 包含 shell script 處理確定性邏輯（專案偵測、變更檔案、測試覆蓋檢查）：

| Script | 用途 | Input | Output |
|--------|------|-------|--------|
| `scripts/detect-project-and-changes.sh` | 偵測專案類型 + 變更檔案 + 測試覆蓋狀態 | `[--project-dir <path>]` | JSON object |

Script 路徑相對於本 SKILL.md 所在目錄。執行前確認有 `+x` 權限。

## 0. Project Detection + Changed Files + Test Coverage

用 bundled script 一次完成專案偵測、變更檔案收集、測試覆蓋檢查：

```bash
SKILL_DIR="$(dirname "$(readlink -f "$0")")"  # 或直接用 skill 的絕對路徑
"$SKILL_DIR/scripts/detect-project-and-changes.sh" --project-dir {base_dir}/<repo>
```

**輸出 JSON 格式**：

```json
{
  "project": "<detected-project-name>",
  "test_framework": "vitest",
  "base_branch": "develop",
  "test_command": "cd apps/main && npx vitest run",
  "coverage_command": "cd apps/main && npx vitest run --coverage",
  "lint_command": "npx eslint",
  "change_source": "branch_diff",
  "changed_files": ["src/components/Foo.vue", "src/utils/bar.ts"],
  "test_files": [
    {"source": "src/utils/bar.ts", "test": "src/utils/__tests__/bar.test.ts", "exists": true},
    {"source": "src/components/Foo.vue", "test": "", "exists": false}
  ],
  "test_files_to_run": ["src/utils/__tests__/bar.test.ts"],
  "missing_tests": ["src/components/Foo.vue"],
  "stats": {"source_files": 2, "has_test": 1, "missing_test": 1, "test_files_to_run": 1}
}
```

Script 自動處理：

- **專案偵測**：vitest.config / jest.config / gulpfile 等判斷 → 決定 framework + base branch + 指令
- **變更檔案**：合併 staged + unstaged + branch diff 三個來源再去重 → 過濾掉測試/mock/型別/設定/barrel
- **測試覆蓋**：每個 source file 搜尋對應 `.test.ts` / `.spec.ts`（含 `__tests__/` 目錄）
- **例外跳過**：`types.ts`、`constants.ts`、`*.d.ts`、`index.ts`、`*.config.*` 不要求測試

> 如果偵測到有專案層級的 `dev-quality-check` local override（在專案的 `.claude/skills/` 下），提醒使用者應從該專案目錄執行以套用專案專屬的品質規則。

### 缺少測試時的處理

根據 `missing_tests` 欄位：
1. **警告使用者**，列出缺少測試的檔案
2. **詢問是否要自動產生測試**
3. 若使用者選擇不補測試，記錄原因供 PR description 使用

### 0-files Guardrail

如果 script 回傳 `source_files: 0`，**不可直接跳過品質檢查**。必須交叉驗證：

1. 跑 `git status --short` 確認工作目錄是否真的沒有變更
2. 如果有 unstaged/staged 變更但 script 未偵測到 → 手動列出變更檔案，對這些檔案跑 lint + 測試 + coverage
3. **禁止在有未 commit 的變更時宣告「0 files，可以 commit」**

## 3. Run Related Tests

根據偵測到的測試框架執行：

**Jest 專案：**
```bash
npx jest <test-files> --verbose
```

**Vitest 專案：**
```bash
npx vitest run <test-files> --reporter=verbose
```

- 所有測試**必須通過**才能繼續
- 如果測試失敗，分析失敗原因並嘗試修復，不要跳過

## 4. Coverage Check (Mandatory)

Coverage 是品質檢查的必要步驟，不可跳過。

### Pre-flight：確認 coverage 工具已安裝

在執行 coverage 之前，先主動檢查工具是否存在，不要等跑掛才裝：

**Vitest 專案：**
```bash
# 檢查 @vitest/coverage-v8 是否已安裝
node -e "require.resolve('@vitest/coverage-v8')" 2>/dev/null
```

若上述指令失敗（exit code !== 0），立即安裝：
```bash
VITEST_VER=$(node -p "require('vitest/package.json').version" 2>/dev/null || echo "")
pnpm -C <project-dir> add -D @vitest/coverage-v8@${VITEST_VER} --filter <package-name>
```

**Jest 專案**：Jest coverage 內建，無需 pre-flight。

### 自動安裝（fallback）

如果 pre-flight 通過但執行時仍出現 `Failed to load url @vitest/coverage-v8` 或類似的 module not found 錯誤，自動安裝後重跑：

**Vitest 專案 — 自動安裝 coverage-v8：**
```bash
# 1. 偵測 vitest 版本
VITEST_VER=$(node -p "require('vitest/package.json').version" 2>/dev/null || echo "")

# 2. 安裝到正確的 workspace（Monorepo 需裝在對應 package filter）
pnpm -C <project-dir> add -D @vitest/coverage-v8@${VITEST_VER} --filter <package-name>  # e.g. --filter @your-org/app-main
# 或 workspace root: pnpm -C <project-dir> add -Dw @vitest/coverage-v8@${VITEST_VER}

# 3. 重跑 coverage
```

**Jest 專案**：Jest coverage 通常內建，若缺少則安裝 `jest` 本身即可。

**Monorepo 注意事項**：Monorepo 專案（如 `<project>`）的 `vitest.config.ts` 在 `apps/main/`，coverage provider 的 module resolution 只在該目錄下有效。必須從 `apps/main/` 目錄執行 coverage 指令：
```bash
cd <project-dir>/apps/main && npx vitest run <test-files> --coverage --coverage.include='<source-path>/**'
```
**不可用 `npx --prefix <project-dir>` 從 workspace root 執行**——Vite 會從 root 的 node_modules 解析 coverage-v8，但 root 和子目錄可能有不同版本的 vitest，導致 module resolution 失敗。

**其他 Vitest 專案：**
```bash
npx vitest run <test-files> --coverage --coverage.include='<source-path>/**'
```

**Jest 專案：**
```bash
npx jest <test-files> --coverage --collectCoverageFrom='<source-path>/**/*.{ts,tsx,vue,js,jsx}'
```

## 5. ESLint Check

```bash
npx eslint <changed-files> --no-fix
```

如果有 ESLint 錯誤：
- 嘗試自動修正：`npx eslint <changed-files> --fix`
- 無法自動修正的，列出具體錯誤並提供修正建議
- **禁止使用 eslint-disable 繞過**

## 6. Build Smoke Test（Nuxt 專案）

Lint 和 test 在 Vitest/Node 環境跑，不會觸發 Nuxt runtime 的 module scanning。但 Nuxt dev/build 會掃描 `server/api/`、`plugins/` 等目錄，載入所有檔案。如果有 test-only 檔案（import vitest）被放在這些目錄且未被 `nitro.ignore` 排除，lint + test 全過但 dev server 啟動就 crash。

**觸發條件**：專案偵測為 Nuxt（有 `nuxt.config.ts`）時才執行。非 Nuxt 專案跳過。

### 6a. nuxi prepare（快速驗證 module resolution）

```bash
# nuxi prepare 比 nuxi build 快很多（只做 module resolution + .nuxt/ 生成，不做完整 build）
<project>/node_modules/.bin/nuxi prepare <project-dir> 2>&1
```

| 結果 | 動作 |
|------|------|
| exit 0 | ✅ 通過，繼續 6b |
| exit non-0 | ❌ 分析 stderr 輸出，常見問題：test 檔案被 Nitro 載入（建議檢查 `nitro.ignore`）、missing module、env var 未設定。修正後重跑 |

### 6b. Dev Server Smoke Test（完整 runtime 驗證）

`nuxi prepare` 只驗 module resolution，不啟動 runtime。有些問題只在 dev server 實際啟動時才會爆（如 worker init 階段的 dynamic import 失敗）。啟動 dev server 並**透過 `{config: infra.docker_project}` 的 nginx proxy 打真實頁面**確認 HTTP 200。

**標準 dev 環境架構（Nuxt 專案）：**
```
curl → {config: infra.dev_host}:80 → nginx (Docker) → host.docker.internal:{port} → Nuxt dev server
```

```bash
# 1. 安裝依賴
pnpm -C <project> install

# 2. 啟動 dev server（背景）
<project>/node_modules/.bin/nuxi dev <project> --dotenv .env.local &

# 3. 透過 nginx proxy 等待 server ready（最多 90 秒）
for i in $(seq 1 18); do
  http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://{config: infra.dev_host}/<default-locale>" --max-time 10 2>/dev/null)
  [ "$http_code" = "200" ] && echo "✅ Dev server smoke test passed" && break
  sleep 5
done

# 4. 關閉 dev server
kill %1 2>/dev/null
```

**Server 可達性判定：**

| 結果 | 動作 |
|------|------|
| HTTP 200 within 90s | ✅ 進入 content check |
| 503 持續 90s | ❌ nginx 連不到 Nuxt upstream — 檢查 Nuxt 是否在正確 port（`<project>: {port}`）、`{config: infra.docker_project}` 是否在跑、server log |
| 000 (connection refused) | ❌ nginx 未啟動 — 確認 `{config: infra.docker_project}` 容器是否在執行 |

**Content Sanity Check（HTTP 200 後）：**

HTTP 200 ≠ 頁面正常。取得 HTML 後檢查：
- **i18n key leak**：`grep -oE '[a-z]+(_[a-z0-9]+){2,}'` 計算 raw key 數量，> 10 個 = ⚠️ 翻譯可能沒載入（檢查 `.env.local` 的 i18n base URL 環境變數是否指向可達的 endpoint）
- **SSR payload**：確認 HTML 有 `__NUXT__`，沒有 = SSR 失敗
- **`<title>`**：應包含有意義的文字，不是 i18n key

i18n key leak 在 quality check 階段為 **WARNING**（不 block commit，可能是 dev 環境限制），但會記錄在報告中提醒 RD 確認。SSR 失敗為 **FAIL**。

> 如果專案沒有 `.env.local`，去掉 `--dotenv`。`<default-locale>` 用專案預設語系路徑（如 `zh-tw`）。**必須透過 `{config: infra.dev_host}` 打**，不能直接打 `localhost:3001`，才能驗證完整的 proxy 鏈路。

## 7. Verification Gate

每個驗證步驟都必須遵循：

1. **IDENTIFY** — 確認要跑什麼指令
2. **RUN** — 完整執行指令
3. **READ** — 仔細閱讀完整輸出
4. **VERIFY** — 確認輸出支持結論

**禁止：**
- 跑了指令但只看前幾行就說「通過了」
- 說「應該沒問題」但沒有實際跑驗證

## 7. Risk Scoring

在所有驗證步驟完成後，計算變更的風險分數（0-100）。

**計分訊號：**

| 訊號 | 權重 | 計算方式 |
|------|------|----------|
| 變更檔案數 | +2/file | 每個變更檔案 +2，上限 20 |
| 變更行數 | +1/50 lines | 每 50 行 +1，上限 10 |
| 關鍵路徑 | +20 | 觸及 checkout、payment、auth、order 相關路徑 |
| 測試覆蓋比 | +0~15 | `(1 - has_test/source_files) * 15`，全覆蓋 = 0 |
| 新增依賴 | +10 | package.json 有新增 dependencies |
| 設定檔變更 | +5 | 修改 config、env、CI 相關檔案 |
| 共用元件 | +10 | 變更的元件被 ≥5 個檔案 import |

計算方式：加總所有訊號分數，cap 在 0-100。

**判讀關鍵路徑**：檔案路徑包含以下關鍵字視為 critical —
`checkout`, `payment`, `pay`, `order/create`, `auth`, `login`, `register`, `cart/submit`

**判讀共用元件**：對每個變更檔案，grep codebase 計算被 import 的次數，≥5 次視為共用。

**門檻與動作：**

| 分數 | 等級 | 動作 |
|------|------|------|
| 0-30 | 🟢 LOW | 正常繼續 |
| 31-60 | 🟡 MEDIUM | 顯示警告，列出主要風險因子，繼續 |
| 61-100 | 🔴 HIGH | 列出所有風險因子，**需使用者明確確認**才繼續 |

HIGH 風險時的提示：

> ⚠️ 風險分數 {score}/100（HIGH）
> 主要風險因子：{列出 top 3 訊號}
> 確認要繼續發 PR 嗎？（y/n）

## 8. Output Report

```
品質檢查結果：
- 專案：{project-name}（{test-framework}）
- 變更檔案：N 個 source files
- 測試覆蓋：M/N 個檔案有對應測試
- 缺少測試：列出缺少的檔案（若有）
- 測試結果：X passed / Y failed
- ESLint：通過 / N 個錯誤
- 風險評分：{score}/100 {🟢/🟡/🔴} {LOW/MEDIUM/HIGH}
- 結論：✅ 可以 commit / ⚠️ 需修正後再 commit / 🔴 高風險，需確認
```

## 9. Quality Gate Marker

品質檢查是 pre-push hook 的前置條件。通過品質檢查後寫入 marker file，讓 `.claude/hooks/pre-push-quality-gate.sh` 知道可以放行 `git push`。沒有這個 marker，push 會被擋下來。

**結論為「✅ 可以 commit」時**（包含使用者確認高風險後繼續的情況）：

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) quality-check passed" > "/tmp/.quality-gate-passed-${BRANCH}"
```

**結論為「⚠️ 需修正」時**：不寫 marker。修正後重跑品質檢查，通過後自然會寫入。

**結論為「🔴 高風險」時**：等使用者明確確認（Step 7 的 y/n）後才寫 marker。使用者選擇不繼續則不寫。

## Do / Don't

- Do: 在寫完功能後立即執行
- Do: 對缺少測試的檔案提供具體建議
- Do: 修正 ESLint 錯誤時從根本解決
- Don't: 對純型別檔案要求測試
- Don't: 測試失敗時直接跳過
- Don't: 使用 eslint-disable 繞過
- Don't: script 回傳 0 files 時直接宣告通過 — 必須用 `git status` 交叉驗證
- Don't: 只跑 lint + type check 就說「可以 commit」— coverage check 是必要步驟
- Do: Nuxt 專案跑 `nuxi prepare` smoke test — lint/test 在 Node 環境跑，不會觸發 Nitro module scanning，只有 build smoke test 能抓到 runtime import 問題（如 test 檔案被 Nitro 載入）
