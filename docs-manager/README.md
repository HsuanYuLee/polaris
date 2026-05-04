# Polaris Docs Manager

Polaris Docs Manager 是 Starlight / Astro 文件 app，用來管理與瀏覽 workspace 的 canonical specs 文件樹。

## Maintenance Sources

- Starlight official docs: https://starlight.astro.build/
- Starlight GitHub repo: https://github.com/withastro/starlight
- Astro docs: https://docs.astro.build/

調整 docs-manager routing、sidebar 行為、content collections 或 build commands 時，優先參考上述官方來源。

## Commands

```bash
npm install
npm run dev -- --host 127.0.0.1 --port 8080
npm run build
npm run preview -- --host 127.0.0.1 --port 8080
```

docs-manager 服務路徑固定在 `/docs-manager/`。

Status Dashboard 位於 `/docs-manager/status/`，用 build-time filesystem scan 呈現 active design plans 與 company specs 的狀態。這個頁面只讀 `docs-manager/src/content/docs/specs`，不呼叫 JIRA / GitHub / Slack，也不會改寫 lifecycle status；真正的狀態轉移仍由 Polaris skills 與 scripts 執行。

日常從 workspace root 使用 wrapper：

```bash
bash scripts/polaris-viewer.sh --detach --mode dev --port 8080 --no-open
bash scripts/polaris-viewer.sh --status --port 8080
bash scripts/polaris-viewer.sh --stop --port 8080
bash scripts/polaris-viewer.sh --detach --preview --port 3334 --no-open
```

`polaris-viewer.sh --detach` 是日常 persistent preview 入口，適合保留 `http://127.0.0.1:8080/docs-manager/` 給使用者持續瀏覽。`--status` 用來確認目前 port 的 URL / PID / log，`--stop` 只會停止可辨識的 docs-manager，不會關掉未知服務。

dev mode 會啟動 Astro dev server，適合快速看內容與 hot reload。Starlight 預設 Search 使用 Pagefind，因此 search input 與結果只會在 production build 後出現；驗 Search 行為時請使用 preview mode。

Framework work 應盡量保留使用者預設 viewer：
`http://127.0.0.1:8080/docs-manager/`。做 preview/search verification 時優先使用
`3334` 這類其他 port。若 deterministic check 必須停掉 8080，交回控制權前要用 `bash scripts/polaris-viewer.sh --detach --mode dev --port 8080 --no-open` 重啟 dev viewer。

## Specs Content

docs-manager 的 canonical document source 是 `docs-manager/src/content/docs/specs` tree：

```text
{workspace_root}/docs-manager/src/content/docs/specs/
```

Starlight content collection 使用官方 `docsLoader()` / `docsSchema()` 讀取 canonical markdown。local dev 不需要先產生中間資料夾，也不需要同步步驟。

所有 specs markdown 都必須遵守 shared authoring contract：`../.claude/skills/references/starlight-authoring-contract.md`。最低要求是 `title` 與 `description` frontmatter；body 不應產生與 page title 相同的 duplicate H1。新增 DP、refinement 或 task 文件時，producer 必須直接把合格 metadata 與 Markdown 寫進 source file。

Sidebar 使用 Starlight 官方 manual sidebar config，由 `sidebar.mjs` 從 canonical specs tree 產生 folder tree。Design Plan folder、company ticket folder、`tasks/`、`pr-release/` 等資料夾都保留可展開節點；folder 內的 markdown 會保留各自 Starlight route，non-markdown artifact 不進 sidebar。

Design Plan folder node 的 lifecycle / priority badge 來自該 folder 的 `plan.md` frontmatter：`status`、`priority`、`sidebar.badge`。Badge 必須顯示在 DP folder node；`plan.md` page node 的 badge 不能取代 folder badge。

Refinement preview 的正式入口也是 docs-manager。`refinement` skill 寫入 `{source_container}/refinement.md` 後，直接用下列 route review：

```text
/docs-manager/specs/design-plans/dp-nnn-topic/refinement/
/docs-manager/specs/companies/{company}/{ticket}/refinement/
```

Live review:

```bash
bash ../scripts/polaris-viewer.sh --detach --mode dev --port 8080 --no-open
bash ../scripts/polaris-viewer.sh --reload --mode dev --port 8080
bash ../scripts/polaris-viewer.sh --status --port 8080
```

新增、搬移或歸檔 spec folder 後，使用 `--reload` 重新載入 dev viewer。Markdown 內容更新通常會由 dev server hot reload；sidebar folder tree 由 `sidebar.mjs` 在 Astro config 載入時產生，folder 結構變更需要 reload 才會穩定反映。

Static/search verification:

```bash
bash ../scripts/verify-docs-manager-runtime.sh --preview
```

Runtime verification 會檢查 folder node、DP folder badge、nested markdown route、company ticket refinement route，以及 preview search result 是否維持在 `/docs-manager/` base path。`verify-docs-manager-runtime.sh` 的 verification runtime 是 ephemeral：script 自己啟動的 server 預設會 cleanup；若 reuse 既有 persistent preview，驗證後不會停止該 server。需要保留 verifier 自己啟動的測試 server 時可加 `--keep-server`，並用 `polaris-viewer.sh --stop --port <port>` 清掉。

Authoring verification:

```bash
bash ../scripts/validate-starlight-authoring.sh check src/content/docs/specs/path/to/file.md
bash ../scripts/validate-starlight-authoring.sh legacy-report src/content/docs/specs
```

Spec sidebar metadata:

```bash
bash ../scripts/sync-spec-sidebar-metadata.sh --apply src/content/docs/specs
bash ../scripts/validate-dp-metadata.sh src/content/docs/specs/design-plans
```

DP `plan.md` 必須包含 lifecycle `status`、work `priority` 與 Starlight `sidebar` metadata；company spec parent 也必須讓 `sidebar.badge` 對齊 lifecycle `status`。Sync script 會把 DP 的 `SEED` 正規化成 `SEEDED`，依 status 推導缺漏的 priority，並寫入 sidebar metadata。

Archive folders 是同一個 canonical tree 的一部分。當 specs 移到 `docs-manager/src/content/docs/specs/design-plans/archive/` 或 `docs-manager/src/content/docs/specs/companies/{company}/archive/` 時，docs-manager 會在下一次 dev refresh 或 build 直接讀到新 route。

`docs-manager/src/content/docs/specs` 是 local-only source content。`docs-manager/dist` 是 generated static output，不可當 source 使用，也不可作為 migration input。
