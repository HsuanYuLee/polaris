---
name: visual-regression
description: >
  Visual regression guard using before/after screenshot comparison. Two modes: SIT (compare staging vs local dev)
  or Local (compare git-stashed base vs current changes). No long-lived baselines — captures fresh screenshots
  each run and deletes after comparison. Config-driven from workspace-config.yaml.
  Use when: "跑 visual regression", "檢查畫面", "頁面有沒有壞", "visual test", "screenshot test",
  "畫面測試", "截圖比對", "有沒有跑版", "畫面壞了嗎", "UI 有沒有問題", "check if pages look right",
  or when engineering detects visual_regression enabled on the current domain.
---

# Visual Regression

Before/after screenshot comparison guard — no long-lived baselines. Each run captures two fresh sets of screenshots, compares them, then discards both. Config-driven from `workspace-config.yaml`.

Project config is read from the workspace-owned Polaris tree (`{company}/polaris-config/...`). Visual regression does not require repo root `CLAUDE.md` / `AGENTS.md` native injection and does not write repo-owned adapter config.

**Position in quality chain:**
```
engineer-delivery-flow Step 2 (ci-local.sh) → visual-regression (Step 3.5) → engineer-delivery-flow Step 3 → commit/PR
```

- `engineer-delivery-flow Step 2`: "Is the new code quality OK?" (Local CI Mirror — `ci-local.sh`)
- `visual-regression`: "Are existing pages still visually intact?"
- `engineer-delivery-flow Step 3`: "Does the new feature work correctly?"

**How the comparison works (Playwright's built-in diff engine):**
1. Run Playwright with `--update-snapshots` against the "before" source → creates temporary baselines in `{test_dir}/snapshots/`
2. Run Playwright normally against the "after" source → auto-compares against those baselines
3. Playwright generates diff images in `{test_dir}/test-results/` and an HTML report
4. After analysis: delete all snapshots and test-results — nothing is committed

---

## Core Principle: Domain-Level Testing

VR 的測試單位是 **domain**（如 `www.example.com`），不是 repo。

- 頁面清單由 URL path 定義，不以「這頁不在本 repo」為 skip 理由
- 如果某頁在 local dev 無法載入（由其他 service 服務），VR 仍應嘗試；SIT mode 可完整覆蓋
- VR 報 diff 時只報「哪一頁有問題」，不負責定位 repo — fix sub-agent 拿到 failing page 後自行查 routing / service map
- 合法的 skip 理由：fixture 尚未建立、SSR 已知 hang（待修）、環境依賴缺失（待補）

---

## VR Principles (Hard-Won Rules)

These principles were established through debugging sessions. Violating any of them causes non-deterministic results or missed regressions.

### P1. Always go through the production-equivalent proxy

Never bypass the reverse proxy by hitting dev server ports directly (e.g., `localhost:3001`). The proxy (nginx, Caddy, etc.) routes domain paths to the correct upstream services. Direct port access only tests one service's routes and misses cross-service routing. If the proxy is broken, fix the proxy — don't route around it.

> **Example**: Docker nginx on `dev.example.com` routes to web-app, member-api, mobile-api. See `polaris-env.sh` Layer 1.

### P2. Wait for CSR content with `waitForSelector`, never `waitForTimeout`

CSR-rendered content renders AFTER `networkidle` — framework hydration triggers client-side fetches. `waitForTimeout(3000)` is a guess that fails under CPU contention. Instead, wait for a DOM element that only exists when the data has rendered. Define a `waitForCSRContent()` helper that calls `page.locator(selector).waitFor()` for each CSR section.

### P3. Mobile requires User-Agent if the site uses UA-based SSR detection

If the site uses server-side UA detection (e.g., `@nuxtjs/device`, `mobile-detect`) to render different layouts, setting viewport to 375px alone is NOT sufficient — SSR still returns desktop layout. Playwright mobile projects must set a mobile `userAgent` string. Check the site's SSR detection method before creating the mobile project config.

### P4. Proxy mode hides missing fixtures — replay mode exposes them

In proxy mode (`--record`), unmatched requests fall through to SIT → pages render correctly → missing fixtures go unnoticed. After switching to replay mode (`--proxy disabled`), those endpoints return 404 → CSR sections show skeleton/grey. **Always run a full VR pass + human screenshot review after switching to replay mode.**

### P5. First-run quality gate — zero-diff ≠ correct screenshots

Two identical runs of broken screenshots produce zero-diff. The first VR run after fixture setup or changes must be human-reviewed before publishing to JIRA. Known failure modes: all-grey product cards (missing fixture), desktop layout on mobile viewport (missing UA).

### P6. Tests must run sequentially (`workers: 1`)

Parallel Playwright tests overload the shared Mockoon + dev server. 8 tests hitting the same ports causes timeouts, incomplete responses, and memory pressure. Always `workers: 1`.

### P7. JIRA reports use wiki markup via REST API v2

MCP `addCommentToJiraIssue` with `contentFormat: "markdown"` cannot embed attachment images. Use `POST /rest/api/2/issue/{key}/comment` with wiki markup body. Image syntax: `!filename.png|thumbnail!` inside table cells for side-by-side desktop/mobile comparison. See `references/vr-jira-report-template.md` for templates.

---

## Step 0: Read Config and Check Prerequisites

### 0a. Identify the domain

Determine the active domain from:
1. Git branch → `projects[]` match → `visual_regression.domain` field in company workspace-config.yaml
2. User's explicit mention of a domain name
3. JIRA ticket or DP task context (when invoked from `engineering`)

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

If `fixtures` block exists in domain config, verify the `fixtures.mockoon` capability through `scripts/polaris-toolchain.sh`.

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

Test files location: `polaris-config/{company}/visual-regression/{domain}/`

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
bash {workspace_root}/scripts/polaris-toolchain.sh run browser.playwright.doctor
```

If not installed and consent is `consented`:
```bash
bash {workspace_root}/scripts/polaris-toolchain.sh install --required
```

Do not install Playwright into the product repo. Polaris owns the browser runner through `tools/polaris-toolchain`.

### 2b. Start environment via polaris-env.sh

Use the shared one-click environment script to start Docker + dev server:

```bash
bash {workspace_root}/scripts/polaris-env.sh start {company} --vr
```

This handles:
- **Layer 1 (Docker)**: starts acme-web-docker (nginx + member-ci + mobile-member-ci). Nginx proxies all domain routes to the correct backend
- **Layer 3 (Dev server)**: starts b2c-web standalone — Docker nginx proxies to it for b2c routes
- **Layer 4 (Verify)**: health-checks all started services

**Architecture: Playwright → Docker nginx (dev.example.com) → upstream repos**

```
Playwright → dev.example.com (Docker nginx)
                ├── /zh-TW/*           → acme-web-app (localhost:3001)
                ├── /api/internal/*    → acme-member-api (Docker)
                └── /mobile/*          → acme-mobile-api (Docker)
```

All routes that exist in production are testable through nginx. Do NOT bypass nginx by hitting `localhost:3001` directly — that only tests b2c-web routes and misses member-ci/mobile-member-ci.

**Check the output** — if any layer fails, `polaris-env.sh` reports which service failed. Decide:

| Situation | Action |
|-----------|--------|
| All layers ✓ | Proceed to Step 3 |
| Docker failed | Stop. Fix Docker first — all routes depend on nginx |
| Dev server failed | Stop. Check log at `/tmp/polaris-env/{company}/{project}.log` |

### 2c. Cleanup plan

Record the cleanup command for Step 6:
```bash
bash {workspace_root}/scripts/polaris-env.sh stop {company}
```

This stops Mockoon + dev server + any Docker services started by polaris-env.

---

## Step 2.5: API Contract Check (if fixtures active)

If Mockoon fixtures are running (Layer 2 of polaris-env), run the contract check before capturing screenshots. See `references/api-contract-guard.md`.

```bash
# Mockoon fixtures path: specs/{EPIC}/tests/mockoon/ (see references/epic-folder-structure.md)
scripts/contract-check.sh --env-dir {company_specs_dir}/{EPIC}/tests/mockoon
```

| Exit code | Action |
|-----------|--------|
| 0 | No drift → proceed to Step 3 |
| 1 (breaking) | Display drift report. Ask user: "API contract 有 breaking change，要先更新 fixture 再跑 VR，還是忽略？" |
| 2 (env not reachable) | Warn, proceed without check |

If user chooses to update fixtures → switch to `--record` mode, re-capture, then restart from Step 3.

---

## Step 3: Capture "Before" Screenshots

Run Playwright with `--update-snapshots` to establish temporary baselines.

**SIT mode:**
```bash
VR_BASE_URL={sit_url} bash {workspace_root}/scripts/polaris-toolchain.sh run browser.playwright.verify -- \
  --update-snapshots \
  -c polaris-config/{company}/visual-regression/{domain}/playwright.config.ts
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
   VR_BASE_URL={server.base_url} bash {workspace_root}/scripts/polaris-toolchain.sh run browser.playwright.verify -- \
     --update-snapshots \
     -c polaris-config/{company}/visual-regression/{domain}/playwright.config.ts
   ```

4. Restore stash:
   ```bash
   git -C {project_dir} stash pop
   ```

5. Wait for hot-reload again (same poll loop as step 2).

**Output:** Snapshot files written to `polaris-config/{company}/visual-regression/{domain}/snapshots/`

---

## Step 4: Capture "After" Screenshots + Compare

Run Playwright normally — it auto-compares against the baselines from Step 3.

```bash
VR_BASE_URL={server.base_url} bash {workspace_root}/scripts/polaris-toolchain.sh run browser.playwright.verify -- \
  -c polaris-config/{company}/visual-regression/{domain}/playwright.config.ts
```

Playwright outputs:
- Exit code 0 → all screenshots match
- Exit code 1 → one or more diffs found
- Diff images: `polaris-config/{company}/visual-regression/{domain}/test-results/`
- HTML report: `polaris-config/{company}/visual-regression/{domain}/playwright-report/`

---

## Step 5: Analyze Results

### First-run quality gate

**Zero-diff ≠ correct screenshots.** The first time VR runs after fixture setup or fixture changes, screenshots must be manually reviewed by the user before publishing results. Zero-diff only proves "two runs produced the same output" — if the baseline itself is wrong (missing content, wrong viewport, fixture gaps), the comparison passes with garbage.

Known failure modes caught by this gate:
- Homepage product area all grey (fixture missing routes → skeleton fallback renders identically both times)
- Mobile shows desktop layout (UA not set → "wrong" version is consistent → zero-diff)

**Checkpoint:** after the first VR run with new/changed fixtures, show screenshots to the user and ask: "截圖內容正確嗎？" Do NOT auto-publish the JIRA report until confirmed.

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
  bash {workspace_root}/scripts/polaris-toolchain.sh run browser.playwright.verify -- show-report polaris-config/{company}/visual-regression/{domain}/playwright-report
```

**All pass:**
```
Visual regression passed ✅ — {N} 個頁面截圖一致，無畫面異常。
```

### 5b. Collect and upload artifacts to JIRA

If the VR run is part of a ticket verification flow (e.g., triggered by `engineering` or `engineer-delivery-flow Step 3`), collect screenshots and upload them to the JIRA ticket **before** cleanup deletes them.

**Step 5b-1: Collect artifacts to a temp directory**

```bash
ARTIFACT_DIR="/tmp/polaris-vr-artifacts/{ticket}-{timestamp}"
mkdir -p "$ARTIFACT_DIR"
# Copy "after" snapshots (the final state)
cp -r polaris-config/{company}/visual-regression/{domain}/snapshots/ "$ARTIFACT_DIR/snapshots/"
# Copy diff images if any (Playwright generates these for failures)
cp -r polaris-config/{company}/visual-regression/{domain}/test-results/ "$ARTIFACT_DIR/diffs/" 2>/dev/null || true
```

**Step 5b-2: Upload all artifacts to JIRA**

**⚠ JIRA attachment 同名覆蓋陷阱：** JIRA wiki markup `!filename.png|thumbnail!` binds to the attachment ID at comment creation time, not by filename lookup. If you upload a new file with the same name, old comments still point to the old attachment ID. Deleting the old attachment breaks all comments that reference it.

**Safe re-upload flow:** delete old attachment first → upload new file → re-post the comment. Or use versioned filenames (`homepage-desktop-v2.png`), but this accumulates garbage.

Use the shared upload script to attach screenshots and diff images:

```bash
# Collect all PNG files
FILES=$(find "$ARTIFACT_DIR" -name "*.png" -type f)
if [ -n "$FILES" ]; then
  bash {workspace_root}/scripts/jira-upload-attachment.sh {ticket} $FILES
fi
```

The script outputs JSON per file with `filename`, `id`, and `url` fields. **Capture these URLs** — they are needed for the inline report in Step 5c.

**Step 5b-3: Parse upload results**

Store the mapping of `filename → attachment URL` for use in the JIRA comment. The `url` field from the upload response is the direct content URL that can be embedded in JIRA comments.

If VR was run standalone (not as part of a ticket flow), skip upload — snapshots are ephemeral.

### 5c. Write JIRA report with inline screenshots (required)

Regardless of pass or fail, VR results **must** be written to the JIRA verification ticket as a **rich report with inline screenshots**. Plain text tables are insufficient — reviewers need to see the actual screenshots to judge visual quality.

**Template reference:** use `references/vr-jira-report-template.md` for the full template catalog (all-pass, mixed results, attachment naming conventions, and posting rules). The inline example below is the minimal format — refer to the template for edge cases.

**Report format — interleaved text and images:**

The comment uses JIRA wiki markup (not markdown) for inline image embedding:

```
h2. VR 結果 — {comparison_type} ({date})

*結論：{N}/{total} PASS, {diff_summary}*

h3. 測試條件
* Baseline: {baseline_description}
* Comparison: {comparison_description}
* Fixtures: {fixture_state}

----

h3. ✅ Homepage — PASS (zero-diff)
||Desktop||Mobile||
|!homepage-desktop.png|thumbnail!|!homepage-mobile.png|thumbnail!|

h3. ⚠ Product Page — FAIL (diff 3.2%)
||Desktop — Diff||
|!product-page-desktop-diff.png|thumbnail!|
*變更區域：* footer 高度差異，cache key 遺漏 query params

h3. ⏭ Search Results — SKIP
*原因：* fixture 尚未建立，需攔截 search API calls 並錄製

----

h3. 判定
{final_verdict — PASS / PASS_WITH_DIFFS / BLOCK}
```

**Key rules for the report:**

1. **每頁一個 section** — 用 `h3.` 分隔，包含結果 emoji + 頁面名 + 結論
2. **PASS pages**: 附 "after" 截圖（desktop + mobile 並排），一行確認無差異
3. **FAIL pages**: 附 **diff 圖**（Playwright 生成的紅色差異圖）+ before/after 對比。描述差異區域和可能原因
4. **SKIP pages**: 說明原因和解除條件（何時能啟用）
5. **圖片用 wiki markup**: `!filename.png|thumbnail!` 讓 JIRA 顯示可點擊的縮圖
6. **先上傳再寫 comment**: Step 5b 必須完成（圖片已在 JIRA attachments），comment 才能引用檔名

**When screenshots are not available** (standalone run, upload failed):

Fall back to text-only format with the summary table:

```
|| Page || Desktop || Mobile ||
| Homepage | ✅ pass | ✅ pass |
| Product | ⚠ diff 3.2% | ⚠ diff 2.9% |
```

Add a note: "截圖未上傳 — 請透過 toolchain 開 Playwright HTML report：`bash scripts/polaris-toolchain.sh run browser.playwright.verify -- show-report ...`"

**Posting method — REST API v2 with wiki markup (NOT MCP markdown)**:

MCP `addCommentToJiraIssue` with `contentFormat: "markdown"` does NOT support `![](filename.png)` for referencing JIRA attachments — images render as broken blob URLs. Instead, post via JIRA REST API v2 which natively supports wiki markup:

```bash
source {company}/.env.secrets
curl -s -X POST \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  "https://{site}.atlassian.net/rest/api/2/issue/{ticket}/comment" \
  -d '{"body": "{wiki_markup_content}"}'
```

Wiki markup image syntax: `!filename.png|thumbnail!` — JIRA auto-resolves filenames from the ticket's attachments. Use in tables for side-by-side comparison:

```
|| || Desktop || Mobile ||
| *Master baseline* | !before-homepage-desktop.png|thumbnail! | !before-homepage-mobile.png|thumbnail! |
| *After* | !after-homepage-desktop.png|thumbnail! | !after-homepage-mobile.png|thumbnail! |
| *Diff* | !diff-homepage-desktop.png|thumbnail! | !diff-homepage-mobile.png|thumbnail! |
```

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
   rm -rf polaris-config/{company}/visual-regression/{domain}/snapshots/
   ```

5. **Delete test results** (diff images):
   ```bash
   rm -rf polaris-config/{company}/visual-regression/{domain}/test-results/
   ```

Note: `playwright-report/` is kept for the user to inspect. It is NOT committed.

**Error safety**: wrap cleanup in a try-finally equivalent — if VR crashes at any step, cleanup still runs. The git stash and server restore are the most critical (user's working state must not be lost).

---

## Integration: engineering

When invoked as part of the PR quality chain (not user-initiated):

- Auto-select mode: SIT if `sit_url` configured and reachable, otherwise Local
- Skip the smart-skip check (engineering already determined changes are significant)
- **All pass** → one-line confirmation, continue PR workflow
- **Intentional diffs only** → report diffs but do NOT block PR; note that visual changes are expected
- **Any regressions or major diffs** → block PR workflow, report findings, require user investigation before proceeding

Return format for engineering:
```
visual-regression: {PASS | PASS_WITH_DIFFS | BLOCK}
{one-line summary}
```

---

## Fixture Recording Workflow (Record → Compare)

When fixtures need to be created or updated (new domain setup, new API endpoints, stale data), use the two-phase Record → Compare flow. This is **not** a comparison mode — it's a fixture lifecycle operation that produces deterministic baselines for future VR runs.

### When to use

| Trigger | Action |
|---------|--------|
| First VR setup for a domain | Record all configured proxy routes |
| New API endpoint added to `proxy-config.yaml` | Re-record to capture the new route |
| Fixture data is stale (API response format changed) | Re-record affected routes |
| User says "重錄 fixture", "re-record", "更新 fixture" | Run this workflow |

### Phase 1: Record (proxy mode)

Start the environment with `--record` flag — Mockoon runs as a **proxy**, forwarding requests to real backends and saving responses as fixtures:

```bash
bash {workspace_root}/scripts/polaris-env.sh start {company} --vr --record
```

Then capture baseline screenshots (these validate that proxy mode produces correct pages):

```bash
VR_BASE_URL={server.base_url} bash {workspace_root}/scripts/polaris-toolchain.sh run browser.playwright.verify -- \
  --update-snapshots \
  -c polaris-config/{company}/visual-regression/{domain}/playwright.config.ts
```

**⚠ Mockoon CLI proxy mode does NOT auto-record fixtures.** `--proxy enabled` only forwards unmatched requests to real backends — it does NOT save responses back to the environment JSON file. To add new fixtures:

1. Start in proxy mode (`polaris-env.sh start {company} --vr --record`)
2. Manually `curl` each endpoint you want to capture
3. Copy the response into the Mockoon environment JSON as a new route
4. Long-term: automate via Node.js recording proxy or Mockoon admin API (backlog)

Review the Mockoon environment file after adding routes. Check for:
- **Unwanted dynamic data** (timestamps, session tokens) that would cause non-determinism
- **`Content-Encoding: gzip` on plain JSON bodies** — proxy recording captures real server headers, but Mockoon stores the decompressed body. The header/body mismatch causes Node.js `undici` to fail decompression → SSR API calls 500. **Always remove `Content-Encoding: gzip` from recorded fixtures**
- **Large responses** (> 1MB) — consider whether they need to be recorded or can be excluded

Stop the environment:
```bash
bash {workspace_root}/scripts/polaris-env.sh stop {company}
```

### Phase 2: Compare (replay mode)

Restart without `--record` — Mockoon replays saved fixtures:

```bash
bash {workspace_root}/scripts/polaris-env.sh start {company} --vr
```

Run Playwright normally (compares against Phase 1 baselines):

```bash
VR_BASE_URL={server.base_url} bash {workspace_root}/scripts/polaris-toolchain.sh run browser.playwright.verify -- \
  -c polaris-config/{company}/visual-regression/{domain}/playwright.config.ts
```

**Expected result: zero-diff.** Proxy-recorded data replayed through the same code should produce identical screenshots. If diffs appear:

| Symptom | Likely cause |
|---------|-------------|
| Data-dependent diff (numbers, text changed) | A dynamic endpoint was not captured by proxy — add it to `proxy-config.yaml` |
| Layout shift | CSS depends on response timing — add `waitForPageReady` delay |
| Missing content (grey skeleton, empty sections) | CSR endpoint missing from fixtures — proxy mode hid the gap (fallback to SIT), replay mode exposed it. Add the missing route (see P4) |
| Fixture response gzipped | Remove `Content-Encoding: gzip` header from fixture JSON |
| Completely blank page | SSR hang — fixture server not responding on expected port; check `health_ports` |

**⚠ Mandatory checkpoint after replay-mode switch:**

1. Run full VR pass (all pages, desktop + mobile)
2. **Human screenshot review** — open each snapshot and confirm content is correct (not skeleton, not wrong layout). This is not optional — see P4 and P5
3. Only after human confirmation: proceed to Phase 3

This checkpoint catches the #1 failure mode in fixture setup: proxy mode silently falls through to SIT for unrecorded endpoints, producing correct-looking screenshots. Replay mode returns 404 for those same endpoints, but without a human review, zero-diff between two broken runs looks like "pass."

### Phase 3: Commit fixtures

After zero-diff is confirmed, fixtures stay in the **per-epic directory** — that is the source of truth:

1. Verify all routes are in `specs/{epic}/tests/mockoon/` (see `references/epic-folder-structure.md`)
2. Update shared `{company_base_dir}/mockoon-config/proxy-config.yaml` if new routes or env overrides were added
3. Fixtures are **not committed to the product repo** — they live in `specs/` (gitignored)

### Relationship to comparison modes

The Record → Compare workflow is orthogonal to the SIT / Local comparison modes:

- **SIT mode** answers: "Does my local code look the same as staging?"
- **Local mode** answers: "Did my code changes break any pages?"
- **Record → Compare** answers: "Are my fixtures correct and deterministic?"

After fixtures are validated via Record → Compare, normal VR runs (SIT or Local mode) use replay mode automatically (`polaris-env.sh start {company} --vr` without `--record`).

---

## Fixture Lifecycle: Per-Epic Isolation

Fixtures are organized **per-epic** under `specs/{EPIC}/tests/mockoon/`. Each epic has a complete, independent set of Mockoon environment JSON files. See `references/epic-folder-structure.md` for the full folder schema.

### Directory structure

```
specs/{EPIC}/tests/mockoon/          ← Epic fixtures (source of truth)
├── dev.example.com.json
├── api-lang.sit.example.com.json
├── recommend.sit.example.com.json
└── ...

{company_base_dir}/mockoon-config/   ← Shared cross-epic config
├── proxy-config.yaml
└── demo.json (optional)
```

No root-level `*.json` files — the epic mockoon directory IS the environments directory.

### Bootstrap a new epic

When starting a new epic that needs VR:

1. Copy the previous epic's fixtures as a starting point:
   ```bash
   cp -r specs/{prev-epic}/tests/mockoon/ specs/{new-epic}/tests/mockoon/
   ```
2. Review which routes are relevant — remove stale routes for APIs no longer tested
3. Re-record any routes where the API response format has changed (see Record → Compare workflow)
4. No workspace-config update needed — path is derived from the Epic key at runtime

### Why per-epic (not shared base + overlay)

- **Determinism** — each epic is a complete snapshot; no merge layer, no inheritance bugs
- **Independence** — epic A's fixture changes can't break epic B's tests
- **Simplicity** — `scripts/polaris-toolchain.sh run fixtures.mockoon.start -- specs/{EPIC}/tests/mockoon/` loads exactly what's in that directory, nothing else
- **Storage is cheap** — a full fixture set is ~1.5MB; recording time is the real cost, and bootstrap from previous epic eliminates most of it

### Runner integration

`fixtures.mockoon.start` accepts a directory containing `*.json` files:

```bash
# Load directly from the epic mockoon directory
bash scripts/polaris-toolchain.sh run fixtures.mockoon.start -- {company_specs_dir}/PROJ-100/tests/mockoon
```

The workspace-config `fixtures.runner` specifies the runner script path. The Epic-specific mockoon directory is resolved at runtime from the active Epic context — no hardcoded `--epic` flag or `environments_dir` needed.

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
| `test_dir` doesn't exist | Create it: `mkdir -p polaris-config/{company}/visual-regression/{domain}/` |
| Stash succeeds but stash pop fails after capture | Keep trying. If unrecoverable, report stash ref for manual restore |

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Page renders wrong data after recording fixtures | A dynamic endpoint (response varies by query params) was recorded as a static fixture | Remove that fixture route — let it proxy instead |
| Fixture server won't start ("data too recent") | CLI version older than environment files | Update the fixture server CLI to match |
| SSR pages hang indefinitely | A required service (Redis, DB) is not running — connection retries block the render | Start the service (see Step 2d) |
| Page 200 on SIT but 500 locally | Local dev's env vars point to an unreachable backend | Route all API base URLs through the fixture server proxy |
| First page load slow (60s+) on dev server | SSR cold start — Vite/Nitro compiling on first request | Warm up with a homepage request before running Playwright |
