# verify-AC Environment Preparation

此 reference 是 `verify-AC/SKILL.md` Step 3 的延後載入細節。只有在 AC
驗證需要 local dev server、fixture server、或 worktree sub-agent 執行時讀取。

## Step 3a. 讀驗收單 task.md

**Worktree dispatch — 主 checkout 絕對路徑**

Sub-agent 在 worktree 執行；`specs/` 與 `.claude/skills/` 是 gitignored
（worktree 無此檔）。dispatch prompt 須以主 checkout 絕對路徑讀寫：

- task.md: `{company_specs_dir}/{EPIC}/tasks/T{n}.md`
- artifacts / verification: `{company_specs_dir}/{EPIC}/artifacts/`、`.../verification/`

完整 path map 見 `worktree-dispatch-paths.md`。

查找驗收單對應的 task.md：

```text
{company_specs_dir}/{EPIC_KEY}/tasks/{AC_TICKET_KEY}.md
```

若存在，讀取 fixture 設定；若不存在，fallback：

```text
{company_specs_dir}/{EPIC_KEY}/tasks/pr-release/{AC_TICKET_KEY}.md
```

兩者皆無時，進入 Step 3b。

## Step 3b. Fixture 自動偵測 fallback

若無 task.md，自動偵測：

```text
specs/{EPIC_KEY}/tests/mockoon/
```

判斷方式：

- 目錄內有 `.json` 檔案 → 視為 `fixture_required: true`，使用 conventional path。
- 沒有 `.json` 檔案 → 視為不需 fixture，只起 dev server。

Fallback 到舊路徑只在該 repo 尚未被 task.md schema 涵蓋時使用；sub-agent return
中要標註 fallback 原因。

## Step 3c. 啟動環境（含 Fixture）

跑 D11 L3 orchestrator，一支命令包住 dependencies、start-command、health-check、
fixtures-start 全鏈：

```bash
bash {polaris_root}/scripts/start-test-env.sh --task-md {task_md_path} [--with-fixtures]
```

加 `--with-fixtures` 的條件：

- Step 3a 解出 `fixture_required: true`。
- 或 Step 3b fallback 偵測到 `specs/{EPIC_KEY}/tests/mockoon/` 有 `.json`。

Orchestrator 行為：

- 自行讀 task.md 的 `## Test Environment` `Fixtures:` 欄抽路徑。
- `Fixtures: N/A` 但需要 fixture 時，報錯 exit 1；sub-agent 可 fallback 到 conventional path，改用 `--fixtures-dir <path>` 重跑。
- 自抽 project name（從 `test_environment.dev_env_config`），讀 workspace-config 推 dependencies / start_command / health_check URL。
- 每步輸出 JSON 證據（`primitive: start-test-env`）。

結果處理：

- exit 0 → 繼續 `verify-AC/SKILL.md` Step 4，dev server + fixture server 都已 ready。
- exit 非 0 → 本張驗證 block，addComment「環境啟動失敗：第 {step} 步」；`step` 從 stderr 或最後一行 JSON 讀，不標 PASS/FAIL，標 **UNCERTAIN**。

不要再分別呼叫 `polaris-env.sh` + direct Mockoon runner；orchestrator 已包住
D11 L2 primitives。需要 Mockoon capability 時使用：

```bash
scripts/polaris-toolchain.sh run fixtures.mockoon.start -- <fixtures_dir>
```

## Step 3d. Native VR preparation

若 AC step 是 visual AC，且 task.md 宣告 `verification.visual_regression`：

1. 確認 `scripts/run-visual-snapshot.sh` 存在且可執行。
2. 確認 `## Test Environment` `Level=runtime`，且 `Runtime verify target` 可連線。
3. 若 task 使用 fixture-backed VR，先確認 fixture manifest 已 review；未 review 時本輪標 `MANUAL_REQUIRED`，不要繼續判 PASS。
4. 建立 local verification folder：

```text
{company_specs_dir}/{EPIC_KEY}/verification/{run_id}/vr/
```

`run_id` 使用本輪 verify-AC timestamp 或 AC ticket key + timestamp。後續 `run-visual-snapshot.sh`
的 `--output-dir` 指到此資料夾，讓 screenshots / diff artifact 和 report 使用同一份 local path。
