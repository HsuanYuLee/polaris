---
name: visual-regression
description: >
  Visual regression guard using before/after screenshot comparison. Two modes: SIT (compare staging vs local dev)
  or Local (compare git-stashed base vs current changes). No long-lived baselines — captures fresh screenshots
  each run and deletes after comparison. Config-driven from workspace-config.yaml.
  Use when: "跑 visual regression", "檢查畫面", "頁面有沒有壞", "visual test", "screenshot test",
  "畫面測試", "截圖比對", "有沒有跑版", "畫面壞了嗎", "UI 有沒有問題", "check if pages look right",
  or when git-pr-workflow detects visual_regression enabled on the current domain.
---

# Visual Regression

Before/after screenshot comparison guard — no long-lived baselines. Each run captures two fresh sets of screenshots, compares them, then discards both. Config-driven from `workspace-config.yaml`.

**Position in quality chain:**
```
dev-quality-check → visual-regression → verify-completion → commit/PR
```

- `dev-quality-check`: "Is the new code quality OK?"
- `visual-regression`: "Are existing pages still visually intact?"
- `verify-completion`: "Does the new feature work correctly?"

**How the comparison works (Playwright's built-in diff engine):**
1. Run Playwright with `--update-snapshots` against the "before" source → creates temporary baselines in `{test_dir}/snapshots/`
2. Run Playwright normally against the "after" source → auto-compares against those baselines
3. Playwright generates diff images in `{test_dir}/test-results/` and an HTML report
4. After analysis: delete all snapshots and test-results — nothing is committed

---

## Step 0: Read Config and Check Prerequisites

### 0a. Identify the domain

Determine the active domain from:
1. Git branch → `projects[]` match → `visual_regression.domain` field in company workspace-config.yaml
2. User's explicit mention of a domain name
3. JIRA ticket context (when invoked from `git-pr-workflow`)

Read workspace config using `references/workspace-config-reader.md`. Find the matching `visual_regression.domains[]` entry in the company workspace-config.yaml.

If no domain can be determined, ask the user: "要對哪個 domain 跑 visual regression？"

### 0b. Check if visual regression is configured for this domain

If no matching entry in `visual_regression.domains[]` is found:

```
此 domain 尚未設定 visual regression。
如需啟用，在公司 workspace-config.yaml 的 visual_regression.domains[] 加入此 domain 的設定。
詳見 references/visual-regression-config.md。
```

Stop here. Do not proceed.

### 0c. Smart skip — check if changes affect visual output

Read `pages[].source_project` for each configured page. If ALL pages have a `source_project` defined:

1. Get changed files: `git -C {project_dir} diff --name-only {base_branch}...HEAD`
2. Extract the set of `source_project` values for pages that could be affected
3. If NO changed files belong to any of those source projects → skip:

```
Visual regression skipped — 變更的檔案不在任何頁面的 source_project 範圍內。
（此次變更不影響畫面，略過截圖比對。）
```

If `source_project` is absent on any page, always proceed (cannot determine scope safely).

**Clean working tree in Local mode**: if `git status` shows no changes and `git stash` would be a no-op, skip with:
```
Visual regression skipped — working tree is clean, nothing to compare.
```

### 0d. Check dependency consent

Read root `workspace-config.yaml` → `dependencies.playwright.status`:

| Status | Action |
|--------|--------|
| `consented` | Verify installed. If missing, auto-install |
| `declined` | Skip silently. Append to output: `Visual regression 已跳過（playwright 未安裝）` |
| `pending` or missing | Prompt per `references/dependency-consent.md` Phase 2 flow |

If `fixtures` block exists in domain config, apply same check for `mockoon-cli` (or configured fixture tool).

### 0e. Load config with inheritance

Merge two layers into an effective config:

```
root workspace-config.yaml → defaults.visual_regression.*
  ↓ (overridden by)
company workspace-config.yaml → visual_regression.domains[matching].*
```

For each field: use domain value if set, otherwise fall back to root default.

Key effective config fields to resolve:
- `threshold` (default: `0.02`)
- `full_page` (default: `true`)
- `browsers` (default: `["chromium"]`)
- `timeouts.server_startup` (default: `60000`)
- `timeouts.fixture_startup` (default: `30000`)
- `timeouts.screenshot` (default: `30000`)
- `server.sit_url`, `server.base_url`, `server.start_command`, `server.ready_signal`
- `fixtures.*` (entire block, if present)
- `pages[]`, `global_masks`, `locales`, `locale_strategy`

Test files location: `ai-config/{company}/visual-regression/{domain}/`

---

## Step 1: Determine Comparison Mode

**Mode decision logic:**

| Condition | Mode | Before source | After source |
|-----------|------|--------------|--------------|
| `server.sit_url` configured AND SIT passes health check | **SIT** | SIT/staging URL | Local dev server |
| `server.sit_url` configured BUT SIT unreachable | **Local** (auto fallback) | Local dev (stashed) | Local dev (current) |
| `server.sit_url` not configured | **Local** | Local dev (stashed) | Local dev (current) |
| User says "用 SIT 比" | **SIT** (forced) | SIT/staging URL | Local dev server |
| User says "跑 local mode" | **Local** (forced) | Local dev (stashed) | Local dev (current) |

**SIT health check:**
```bash
curl -s -o /dev/null -w "%{http_code}" {sit_url}
```
- HTTP 200 → SIT mode available
- Any other result → log warning, fall back to Local mode

Report the chosen mode to the user:
```
比對模式：SIT（before = {sit_url}, after = {base_url}）
```
or:
```
比對模式：Local（before = stash 前, after = 目前變更）
```

---

## Step 2: Environment Setup

### 2a. Verify Playwright is installed

```bash
npx playwright --version
```

If not installed and consent is `consented`:
```bash
pnpm add -D @playwright/test
npx playwright install chromium
```

Adapt package manager to the project (npm/yarn/pnpm).

### 2b. Start environment via polaris-env.sh

Use the shared one-click environment script to start Mockoon fixtures + dev server:

```bash
bash {workspace_root}/scripts/polaris-env.sh start {company} --vr
```

This handles:
- **Layer 2 (Fixtures)**: starts Mockoon proxy with deterministic API responses. Idempotent — skips already-running instances
- **Layer 3 (Dev server)**: starts the b2c/web project's dev server with `-C` path. Skips `requires` check in `--vr` profile (Mockoon replaces Docker dependencies)
- **Layer 4 (Verify)**: health-checks all started services

**Check the output** — if any layer fails, `polaris-env.sh` reports which service failed. Decide:

| Situation | Action |
|-----------|--------|
| All layers ✓ | Proceed to Step 3 |
| Fixtures failed, dev server ✓ | Warn: "截圖將使用真實 API 資料 — 若後端資料有異動，可能出現假陽性" → proceed |
| Dev server failed | Stop. Check log at `/tmp/polaris-env/{company}/{project}.log` |

**Proxy vs Mock mode:**
- VR tests use **proxy mode** (`--proxy enabled`) — fixtures served locally, unmatched routes fall through to SIT proxy
- **Pure mock mode** (`--proxy disabled`) is NOT recommended — SSR pages call dynamic endpoints that need live proxy fallback

### 2c. Cleanup plan

Record the cleanup command for Step 6:
```bash
bash {workspace_root}/scripts/polaris-env.sh stop {company}
```

This stops Mockoon + dev server + any Docker services started by polaris-env.

---

## Step 3: Capture "Before" Screenshots

Run Playwright with `--update-snapshots` to establish temporary baselines.

**SIT mode:**
```bash
VR_BASE_URL={sit_url} npx playwright test \
  --update-snapshots \
  -c ai-config/{company}/visual-regression/{domain}/playwright.config.ts
```

**Local mode (git stash flow):**

1. Stash current changes:
   ```bash
   git -C {project_dir} stash push -m "polaris-vr-{timestamp}"
   ```
   Record the stash ref for later restore.

2. Wait for dev server hot-reload. Poll health check every 2s (max 30s):
   ```bash
   curl -s -o /dev/null -w "%{http_code}" {server.base_url}
   ```
   If server not ready after 30s: warn user — suggest manually restarting dev server, abort.

3. Capture before screenshots:
   ```bash
   VR_BASE_URL={server.base_url} npx playwright test \
     --update-snapshots \
     -c ai-config/{company}/visual-regression/{domain}/playwright.config.ts
   ```

4. Restore stash:
   ```bash
   git -C {project_dir} stash pop
   ```

5. Wait for hot-reload again (same poll loop as step 2).

**Output:** Snapshot files written to `ai-config/{company}/visual-regression/{domain}/snapshots/`

---

## Step 4: Capture "After" Screenshots + Compare

Run Playwright normally — it auto-compares against the baselines from Step 3.

```bash
VR_BASE_URL={server.base_url} npx playwright test \
  -c ai-config/{company}/visual-regression/{domain}/playwright.config.ts
```

Playwright outputs:
- Exit code 0 → all screenshots match
- Exit code 1 → one or more diffs found
- Diff images: `ai-config/{company}/visual-regression/{domain}/test-results/`
- HTML report: `ai-config/{company}/visual-regression/{domain}/playwright-report/`

---

## Step 5: Analyze Results

### Parse exit code and output

| Playwright exit code | Meaning |
|---------------------|---------|
| 0 | All match → proceed to report |
| 1 | Diffs found → classify each |

### Strict mode (fixtures active)

**When Mockoon fixtures are running**, all API data is deterministic. Any visual diff is therefore caused by code changes, NOT data variation. In this mode:

- **Zero-diff is the only PASS** — any diff, regardless of size, is a FAIL
- Do NOT classify diffs as "data variation" or "known variance" — fixtures eliminate that category
- Do NOT accept higher thresholds for content-heavy pages — the content is fixed
- If diffs appear: they are either **intentional** (related code changed) or **regression** (unrelated code caused it). No third option

**When fixtures are NOT running** (fallback to live proxy): the classification below applies, but warn that results may include false positives from non-deterministic API data.

### Classify each diff

Only applies when fixtures are NOT active, or as secondary analysis when strict mode flags diffs:

For each page with a diff:

1. Get changed files: `git -C {project_dir} diff --name-only {base_branch}...HEAD`
2. Check if changed files relate to the page's `source_project`:
   - Files under the `source_project` repo → related
   - Global style or layout files → related to all pages
   - Files in a different project → unrelated

| Changed files relate to this page? | Classification |
|------------------------------------|---------------|
| Yes — source_project files, global styles, or layouts changed | **Intentional** — expected visual change |
| No — page has diff but no related code was changed | **Regression** — unexpected side effect |
| Diff > 50% | **Major change** — flag explicitly, don't classify |
| `source_project` not set on page | **Unknown** — report diff, cannot classify |

### Report format (zh-TW)

```
Visual Regression 結果（before/after 比對）

模式：SIT（before = {sit_url}, after = {server.base_url}）
Fixture server：{running | 未啟用}

✅ 無差異（N 個）:
  - homepage-zh-TW-1280: 一致
  - homepage-zh-TW-375: 一致
  - homepage-en-1280: 一致

⚠ 有差異（M 個）:
  - product-page-zh-TW-1280: diff 3.2% — 你改了 pages/product/（預期）
  - product-page-zh-TW-375: diff 2.9% — 同上（預期）
  - destination-page-zh-TW-1280: diff 1.5% — ⚠ 無相關變更（可能副作用）

🚨 重大差異（K 個）:
  - checkout-page-zh-TW-1280: diff 67% — 差異過大，請手動確認

Playwright HTML Report:
  npx playwright show-report ai-config/{company}/visual-regression/{domain}/playwright-report
```

**All pass:**
```
Visual regression passed ✅ — {N} 個頁面截圖一致，無畫面異常。
```

### 5b. Preserve snapshots for verification artifacts

If the VR run is part of a ticket verification flow (e.g., triggered by `verify-completion` or `work-on`), copy the "after" snapshots to a persistent location before cleanup deletes them:

```bash
ARTIFACT_DIR="/tmp/polaris-vr-artifacts/{ticket}-{timestamp}"
mkdir -p "$ARTIFACT_DIR"
cp -r ai-config/{company}/visual-regression/{domain}/snapshots/ "$ARTIFACT_DIR/"
```

These snapshots should be attached to the JIRA ticket or PR as verification evidence. The skill reports the artifact path:

```
VR snapshots saved to: {ARTIFACT_DIR}
  - desktop/Homepage-visual-regression/homepage.png
  - mobile/Homepage-visual-regression/homepage.png
  - ...
Attach these to the verification ticket or PR description.
```

If VR was run standalone (not as part of a ticket flow), skip this step — snapshots are ephemeral.

---

## Step 6: Cleanup

Always run cleanup regardless of test outcome — including on error. Snapshots are ephemeral — do not commit them.

**Cleanup is ordered by priority** (most important first, in case cleanup itself fails):

1. **Restore git state** — if Local mode stash was created but NOT yet popped:
   ```bash
   git -C {project_dir} stash pop
   ```

2. **Restore server state** — based on `vr_server_action` from Step 2c:
   | Action | Cleanup |
   |--------|---------|
   | `started` (fresh start) | `kill {vr_server_pid}` |
   | `took_over` | `kill {vr_server_pid}` → restart original: `nohup {original_cmd} &` |
   | `reused` | Do nothing — leave user's server untouched |

3. **Kill fixture server** (if started by this skill — track PID from Step 2b)

4. **Delete snapshots** (temporary baselines):
   ```bash
   rm -rf ai-config/{company}/visual-regression/{domain}/snapshots/
   ```

5. **Delete test results** (diff images):
   ```bash
   rm -rf ai-config/{company}/visual-regression/{domain}/test-results/
   ```

Note: `playwright-report/` is kept for the user to inspect. It is NOT committed.

**Error safety**: wrap cleanup in a try-finally equivalent — if VR crashes at any step, cleanup still runs. The git stash and server restore are the most critical (user's working state must not be lost).

---

## Integration: git-pr-workflow

When invoked as part of the PR quality chain (not user-initiated):

- Auto-select mode: SIT if `sit_url` configured and reachable, otherwise Local
- Skip the smart-skip check (git-pr-workflow already determined changes are significant)
- **All pass** → one-line confirmation, continue PR workflow
- **Intentional diffs only** → report diffs but do NOT block PR; note that visual changes are expected
- **Any regressions or major diffs** → block PR workflow, report findings, require user investigation before proceeding

Return format for git-pr-workflow:
```
visual-regression: {PASS | PASS_WITH_DIFFS | BLOCK}
{one-line summary}
```

---

## Edge Cases

| Situation | Handling |
|-----------|----------|
| Git stash conflicts (stash pop fails) | Abort. Report the conflict. Suggest switching to SIT mode if available |
| SIT unreachable (forced SIT mode by user) | Report error, ask whether to fall back to Local mode |
| Dev server doesn't hot-reload after stash | Warn after 30s poll. Suggest manually restarting dev server. Abort |
| Very high diff > 50% | Flag as "重大差異", do not classify as intentional or regression |
| Fixture server fails to start | Proceed without fixtures, warn about non-deterministic results |
| Clean working tree in Local mode | Skip (Step 0c already catches this — "nothing to compare") |
| Playwright not installed, consent = consented | Auto-install, then continue |
| Playwright not installed, consent = declined | Skip with note, do not install |
| No `pages[]` configured | Report config error, stop |
| `test_dir` doesn't exist | Create it: `mkdir -p ai-config/{company}/visual-regression/{domain}/` |
| Stash succeeds but stash pop fails after capture | Keep trying. If unrecoverable, report stash ref for manual restore |

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Page renders wrong data after recording fixtures | A dynamic endpoint (response varies by query params) was recorded as a static fixture | Remove that fixture route — let it proxy instead |
| Fixture server won't start ("data too recent") | CLI version older than environment files | Update the fixture server CLI to match |
| SSR pages hang indefinitely | A required service (Redis, DB) is not running — connection retries block the render | Start the service (see Step 2d) |
| Page 200 on SIT but 500 locally | Local dev's env vars point to an unreachable backend | Route all API base URLs through the fixture server proxy |
| First page load slow (60s+) on dev server | SSR cold start — Vite/Nitro compiling on first request | Warm up with a homepage request before running Playwright |
