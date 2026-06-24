# Changelog

## [3.76.33] - 2026-06-24

### Changed

- 3e10daa: revision-rebase-selftest.sh：固定 /tmp 路徑改唯一 WORK_DIR + case8 env -u 隔離（hermetic）

## [3.76.32] - 2026-06-24

### Changed

- d32221e: T-tier：selftest tier manifest（319 支，量 wall-clock + 解析 scope，speed × scope 兩軸標 tier）
- d32221e: T-sweep：branch sweep runner（跑 gate、hit-rate 報告、轉 /auto-pass、遷移 evidence）（D10）
- fc35753: T-friction：friction→DP intake 機械化（D11）
- c270e1c: T-precommit：pre-commit 快 lint slot 灌入（staged per-file lint）
- d32221e: T-affected：affected-runner（changed→closure，shared 升 full）+ pre-push wiring（解 :76 main 早退、補 feat/chore）
- 5dcc00e: T-backstop：DP-iteration/release full corpus 串接確認 + 慢 selftest 盤點
- 961c5d3: T-timer：staleness 計時器（clone session-switch-eval）+ workspace-config threshold
- d32221e: T-schema：task.md delivery/verification block 欄位 + derive writer（D1/D2）
- f429089: T-consumer：≥6 consumer 改讀 task.md block + teardown head-sha marker writer；窮舉 input shape；selftest + mechanism-registry 同步
- 33a7738: T-contract：canonical-contract-governance.md § Closeout Delivered-Head Authority amendment（D6 憲法層）
- 8189abb: T-rebase：cascade-rebase-chain.sh 簽章改 feat→main + re-verify 路由（D5，root bug #6）

## [3.76.31] - 2026-06-23

### Changed

- 9efa3b7: 收斂三處 live naive section parser 到 canonical parse-task-md.sh + 修 selftest 複本
- f997ff3: 新增 lint-naive-section-parse.sh（A 類 fail-closed）+ 接 framework PR gate + mechanism-registry annotation

## [3.76.30] - 2026-06-22

### Changed

- f202707: Prerequisite classifier 正確性 — 修 script-ownership-audit.py worktree SKIP_DIRS blank-out + skill_local 定義（own-owning-skill selftest = skill-owned）
- a86026d: 依真實角色正確歸類每支 root executable — single-skill script（含自身 selftest）移入 skill 目錄、gate→gates/、util→lib/、orphan review；callsite/manifest/catalog 同步
- ab1754c: .sh/.py 全面改寫成 canonical mature pattern — shellcheck-clean .sh、ruff-clean .py、檔首 Purpose
- fce6e63: validate-starlight-authoring.sh dir-walk 對齊 content.config.ts render 排除 glob（refinement-inbox/escalations/jira-comments/tests/、artifacts/external-writes/、artifacts/research/、\_ 前綴檔名，以及非 docs-manager content-collection root 的非 render 樹），使 check 只驗真正 render 的 Starlight page；explicit file 參數仍照驗。
- 39fd7e3: 攜帶性證明 + DP-242 supersede

## [3.76.29] - 2026-06-22

### Changed

- f80adff: PostToolUse tick hook（session-keyed）+ 刪死碼 + settings 註冊 + selftest
- 2419a8f: DP-291-T2：新增 UserPromptSubmit session-switch-eval hook、session_switch 設定區塊、settings 註冊與 hermetic selftest
- 2aa37e1: 薄轉述 rule + mechanism-registry runtime annotation + cross-llm parity

## [3.76.28] - 2026-06-22

### Changed

- d1e8bff: 修 Bug #1：engineering-branch-setup 確保 feat base 先於 cascade-rebase
- 9e004bc: 修 Bug #2：polaris-pr-create 的 gh pr create 注入 repo context（cwd-independent）
- 2574794: 修 Bug #3：cascade-rebase-chain conflict 路徑 abort + restore（維持 fail-loud）
- 7b39e48: 修 Bug #4 (hygiene)：framework-release-pr-lane corpus-count 不洩漏 SIGPIPE rc=141

## [3.76.27] - 2026-06-22

### Changed

- bbe2c98: Cluster A：closeout-selftest + folder-native 補 completion-gate marker（real-state fidelity）+ de-quarantine folder-native
- 8cd1eee: Cluster B：bundle-task-closeout + mixed-task-bundle 改由 parent-closeout V enumeration 驅動 V + de-quarantine mixed-task-bundle
- eb0bf9a: DP-319 finalize-precondition：engineering-bundle-pr-identity fixture 改用 tasks/pr-release finalized layout
- 7c76467: Hermeticity：closeout-chain-archive order-independence + release-stage-pr-release-gate env-leak 修正

## [3.76.26] - 2026-06-22

### Changed

- 097d05b: closeout authority hygiene：head 取自 immutable marker、邊界拒 V 單、aggregate 缺 head fail-closed
- be8f6ed: DP-303-T2：verify-AC 整合隔離——throwaway integration branch 契約 + boundary gate 偵測 task/\* delivery branch ref 位移即 fail-closed
- 2a8da3e: leak-scan scope 對齊 sync set：排除 gitignored runtime state
- 44a1110: bundle-PR canonical path + gate-evidence aggregate-aware，關閉 bundle escape-hatch（gate-pr-title 不在本 task，由 DP-319 交付）
- 9281ac7: DP seed collision check：report seed 經 allocator 取號或驗證未占用

## [3.76.25] - 2026-06-22

### Changed

- 55058ac: DP-319-T1：gate-changeset / gate-pr-title 以 pr-release lifecycle 位置作 release-stage exemption（含 multi-match all-members rule）
- 111463e: engineering-branch-setup --aggregate-release bundle 組裝前置 fail-closed（member 必須在 pr-release/）

## [3.76.24] - 2026-06-22

### Changed

- 83553e8: review-inbox-discovery-flow.md — newest-first 指引 + oldest/escaped-JSON pitfall + normalize 步驟說明
- 677600d: check-my-review-status.sh review 效力判定修正 + selftest
- da524cc: Slack MCP detailed escaped-JSON 確定性 normalize（共用 decoder）+ selftest

## [3.76.23] - 2026-06-22

### Changed

- 622396b: 為 stop hook 加入 per-session block 確認狀態與 baseline 新鮮度視窗過濾
- 589937f: release-cleanup-sweep baseline 與 stop-gate state retention sweep

## [3.76.22] - 2026-06-22

### Changed

- 99b27c2: portable manifest-freshness gate + push-time 雙路接入 + reconcile
- 2765daf: 新增 PostToolUse auto-regen hook 與 settings wiring，並補 registry annotation

## [3.76.21] - 2026-06-22

### Added

- ad0bd1e: auto-pass-runner Terminal Complete Sequence 對 implementation T task 對稱 advance + fail-closed confirm
  `scripts/auto-pass-runner.sh` 宣告 terminal=complete 前，除既有 V gate 外，對 required implementation（task_shape=implementation，含缺欄位 default）T work item 加入對稱處理：completion_gate marker PASS at head 但未落 pr-release → 經唯一 canonical writer `mark-spec-implemented.sh`（與 V advance 共用同一 assignment site）advance，再 fail-closed 重讀確認 pr-release/+IMPLEMENTED（重用 `close-parent-spec-if-complete.sh` 契約，無第二 classifier）。carve-out：audit/confirmation 走 DP-262 no-PR path、ABANDONED 留原位；fresh 與 resume-complete 共用同 hook。擴充 `auto-pass-terminal-v-advance-selftest.sh`（case11-16）與補 `mechanism-registry.md` 對稱 canary。

## [3.76.20] - 2026-06-22

### Changed

- 09b7596: gate-work-source feat-release lane：裸 $REPO_ROOT 改 worktree-aware resolve_specs_root（G4）
- 909f479: gate-evidence feat-aggregation evidence awareness：消除釋出 lane 手動 POLARIS_SKIP_EVIDENCE（G1）
- 3a3b03e: gate-evidence feat-aggregation：改讀每筆 pr-release task 自己的 frontmatter head_sha，並驗持久 per-task verify / completion_gate 證據（非 feat HEAD），解除 feat-model 自我釋出 self-block；selftest 改 real-state（marker 綁各 task 自己 head ≠ feat HEAD、completion-gate 不在、verify 在）。一併把 pre-existing-on-main、feat/DP-351 未觸及的 `post-memory-index-regenerate-hook-selftest.sh`（T4 hook-path Hot-count assertion drift）收進 aggregate-runner quarantine（DP-325 umbrella），解除 release aggregate gate 對非本 DP red 的誤擋（DP-351-T2 尾巴修正）

## [3.76.19] - 2026-06-18

### Changed

- a1d43b0: base_branch 畢業為 universal 欄位 + dp feat/{id} format gate
- cd47bc6: delivery-boundary required gate：dp source 進 breakdown 須有 feat/{id}

## [3.76.18] - 2026-06-18

### Changed

- 161ee3a: engineering-branch-setup.sh framework DP 路徑改 feat/DP-NNN 聚合
- 8043a77: 四條 release gate lifecycle 改 key off feat/DP-NNN，移除 bundle_branch_alias
- 5398a04: release tail 改 feat HEAD 壓版 + 單一 feat->main PR + 後 sync（含 bootstrap fallback）
- 3d32bc8: gate-work-source 補 feat/DP-NNN→main 釋出 PR work-source lane（補齊 AC5）

## [3.76.17] - 2026-06-17

### Changed

- a748548: genericize live ticket key in branch-identity selftest comment
  `scripts/selftests/validate-breakdown-ready-branch-identity-selftest.sh` 的 Case 3 註解引用了 live ticket key（template leak），改為 generic「real-world JIRA-Epic bug shape」描述，移除 template-facing 違規。純註解變更，selftest 行為不變、fixtures 維持 generic placeholder（EXCO-712 / exampleco-web）。
- a020ae2: Producer branch-identity 修正 + dual-source parity selftest
- 48d12d8: breakdown-ready branch-identity gate（複用 resolve-task-branch invariant）
- a4744dc: friction gap-assertion kind 強制 contract_evidence（writer + ledger validator 雙邊 fail-closed）+ selftest + reference
- 97e362f: follow_up_dp_seed 加 framework_gap + 條件式 contract_evidence（report validator fail-closed）+ selftest + reference
- fc7612d: B 類 canary（mechanism-registry）+ self-authored-prose Writer side evidence-binding prose

## [3.76.16] - 2026-06-17

### Changed

- 01245cb: bootstrap.md core 新增 Evidence-Before-Invention 原則 + recompile 4 runtime target
- c7a8d2f: mechanism-registry.md 新增 B-class post-task canary（semantic_only）

## [3.76.15] - 2026-06-16

### Changed

- a895bd4: C-b：selftest POLARIS\_\* env-leak hermeticity 修正 + detector（解 DP-301 release block）
- 1298156: C-a（keystone）：aggregate selftest runner + enrollment gate + 接入 PR/release lane + 窮舉 triage
- 3b15575: B：marker supersede 修正（成功 re-package 清舊 blocker marker）
- 6e6f57c: A：consumer 改讀權威欄位（derive modules[].action / audit manifest kind+owner_surface）+ selftest
- f78af24: D：marker source_artifact path-stale 修正（reader resolve-by-id + 全表面 detector）

## [3.76.14] - 2026-06-15

### Changed

- b25012e: 修 resolve-task-md.sh run*selftest fixture-based child invocation 的 POLARIS*\* env hermeticity

## [3.76.13] - 2026-06-15

### Changed

- 2cfc584: FD1：task_snapshot 綁 source canonical refinement_hash + staleness fail-closed gate
- 25cd2f5: FD4-2：run-verify-command 改 structured exit code、移除 stdout FAIL substring
- 6882f3a: FD6：gate-pr-title 在 aggregate-release 接受 bundle title
- 5e4ed79: FD3：engineering finalize 自動寫 completion_gate marker

## [3.76.12] - 2026-06-13

### Changed

- 0f0a530: runner / probe review-state extension：actionable signals 觸發 ROUTE_BACK_REVISION
- 53504e1: ledger schema + execution-flow + SKILL.md：engineering_revision_rounds counter 與 dispatch boundary 明文
- 452264e: orchestrator head rebind 接線：revision 後新 head probe 與 verify-AC refresh、gh fail-closed

## [3.76.11] - 2026-06-13

### Fixed

- 473a8ef: resolve-task-md-by-branch.sh clean-worktree specs overlay lookup：--scan-root 無 specs 時解析 git-common-dir source repo，不退 PWD，使 framework-release pr-lane governed-test gate 全綠

## [3.76.10] - 2026-06-13

### Changed

- ba75371: derive slugify 改 ASCII-only + 3-producer parity selftest
- 036e12e: 新增 branch-name ASCII validator 並接進 breakdown task-readiness
- 0420e2d: pre-push 兩層 enforcement reuse validator
- d0168dd: push refspec 構造 hardening + utf8-boundary-lint 擴及 branch-setup/pr-create
- aabaf16: mechanism-registry 登錄新機制 + selftest fallback 接線

## [3.76.9] - 2026-06-12

### Changed

- 19c2592: derive bridge level projection：canonical mapping 取代逐字複製
- 86a555c: lock-preflight parity：placeholder 帶真實 level 並 reuse 同一 projection

## [3.76.8] - 2026-06-12

### Changed

- 6ecf6e3: detect-closeout-drift 新增 V-task 驗收 read-only gate 與 selftest V-task 案例
- 9038545: mark-spec-implemented archive 容器 folder-native anchor 解析與 embedded selftest 案例

## [3.76.7] - 2026-06-12

### Changed

- c5daf9b: 新增單一 shared staleness helper + 改寫 canonical 定義
- af4b81a: check-pr-approval-status.sh 收斂到 helper、移除 pushed_at
- 93d06ac: check-my-review-status.sh APPROVED branch 收斂到 helper、移除 committer-date staleness

## [3.76.6] - 2026-06-12

### Changed

- 95f348e: auto-pass Terminal Complete Sequence：V task canonical terminal 推進 + fail-closed gate
- eaee6f3: ledger finalize：standalone helper + parent-flip callsite（LOCKED 階段 terminal_status=complete）
- 788220b: validate-auto-pass-report：report↔ledger terminal + verification↔head-bound marker 兩道 fail-closed cross-check
- e441ef5: framework-release-closeout：V task 自動列舉 / idempotent 確認
- a4fc6b8: locked-scope guard per-field 粒度：唯一開放 acceptance_criteria[].verification.detail
- 8da1b7a: derive + readiness 的 Verify Command executability fail-closed（共用 helper）
- 1d805c4: mark-spec-implemented bare-DP 遞迴 qualified key + Path 2 多 match fail-closed

## [3.76.5] - 2026-06-11

### Changed

- e555eb4: closeout 補 PR 關閉 + 改以 release evidence 觸發 cleanup
- a0cd28b: scan-template-leaks.sh 改 gitignore-aware 跳過 ignored 檔
- 6a55de1: install-copilot-hooks.sh pre-push delete/tags carve-out 鏡像
- b7bb6f6: 新增 idempotent release-cleanup sweep 清既有殘骸
- 50cf1a0: mechanism-registry 登錄 + selftest aggregate 接線

## [3.76.4] - 2026-06-11

### Changed

- 50bc9f9: 產 .claude/rules/handbook/code-documentation-conventions.md（workspace handbook 新檔）
- 3c84ce5: memory Hot-membership 單一 canonical 定義收斂：apply demotion 寫 hot_overflow_demoted per-file 訊號 + validate-memory-write 尊重訊號 + hermetic selftest

## [3.76.3] - 2026-06-11

### Changed

- 79486f9: 抽出 shared bundle-detection lib + F3：check-local-extension-completion 改 bundle-aware
- 6f64183: F2：framework-release-closeout 改 order-independent close-parent（V-task 排序無關）
- e30ca22: closeout-drift detector + evidence helpers + selftest（偵測 delivered/stranded drift）
- 434b7c4: detector surfacing 接線（mise + my-triage/standup）+ mechanism-registry 升級

## [3.76.2] - 2026-06-11

### Changed

- 167b3e1: gate-changeset.sh 補 release_bump carve-out（bundle release tail false-block 修正）
- 3bf7e95: 改寫 framework-release SKILL.md：bundle-release orchestration + 版本邊界 + gate-lane 指引 + selftest

## [3.76.1] - 2026-06-10

### Changed

- 1656c18: 修正 validate-task-md.sh docs-manager page-deliverable 分類判準 + selftest
- b2d5aca: working-habits.md 例外 (b) 加 skill-contracted notification carve-out + 判別 test

## [3.76.0] - 2026-06-10

### Changed

- b9b53dd: Keep a Changelog custom formatter + changeset/bump 慣例 reference
- 1efac9e: 建立 .changeset scaffolding + package.json 版本 SoT + config
- e120a95: 壓版本 wrapper（mise run release:version）+ VERSION mirror + selftest
- 34d9c96: release-readiness 整合進 ci-local + remote CI + selftest
- ec8b374: evidence-classifier 擴充壓版本 commit 分類 + selftest
- 605ed99: framework-release: 移除 release lane 的版本壓回（version bounce-back）。版本與
  CHANGELOG 改由 PR 內 changeset-driven 的 `mise run release:version` 壓制並隨被驗證的
  PR HEAD 進版，release lane（`framework-release-pr-lane.sh`）薄化為 lineage 驗證 +
  merge，不再跑 pre-merge version-bump gate，也不再 defer 一道 merge 後的 release-metadata
  壓版步驟。
- 8506652: sync-to-polaris 邊界（機制 sync 到 template，未消費 changeset 不洩漏）

## [3.75.158] - 2026-06-10

### Fixed — DP-302 release hygiene：CHANGELOG prose template leak 修正

v3.75.157 entry 的敘述文字本身含 live 公司 ticket prefix，被 `sync-to-polaris.sh` 的 template leak scan 擋下（CHANGELOG.md 也屬 template surface）。本版把該 entry 改寫成 generic placeholder 並完成發布；DP-302 的功能變更內容同 v3.75.156。

- **template leak 修正**：CHANGELOG release-hygiene 敘述改用 generic placeholder（live 公司 ticket prefix → `PROJ-700-style`），不再於文件 prose 內留 live ticket key。

## [3.75.157] - 2026-06-10

### Fixed — DP-302 release hygiene：derive selftest 註解 template leak 修正

v3.75.156（DP-302 bundle）在 `sync-to-polaris.sh` 的 template leak scan 被擋下：`scripts/selftests/derive-task-md-from-refinement-json-selftest.sh` case 22 註解使用 live 公司 ticket prefix 作為 applies=true 範例（test fixture 屬 template surface，禁止 live ticket prefix）。該版改為 generic placeholder；DP-302 的功能變更內容同 v3.75.156。

- **template leak 修正**：derive selftest 註解改用 `PROJ-700-style` generic placeholder，對齊該 test 自身的 fixture 資料。

## [3.75.156] - 2026-06-10

### Changed — DP-302 derive task.md 去 source.type 分支：identity/body/references 改 field-driven，per-task body schema 對 all source 適用

把 `derive-task-md-from-refinement-json.sh` 的 task.md 輸出收斂成 source.type-free：identity、verification body、references-by-container 改由 refinement.json 欄位驅動，JIRA 成為 optional side effect 而非 output 分支條件，確保 DP-backed 與 JIRA Epic-backed source 產出 identical 結構。

- **per-task body 欄位 schema（all source）**（DP-302-T1）：`validate-refinement-json.sh` 新增 per-task verification body 欄位 schema，對所有 source type 適用（不再 DP-only）；selftest 補對應覆蓋。
- **derive 去 source.type 分支 + body field-driven**（DP-302-T2）：`derive-task-md-from-refinement-json.sh` 移除 source.type 分支，body 與 references-by-container 改 field-driven；`applies=true` 的 behavior_contract 完整 render（source_of_truth / fixture_policy / flow / assertions），缺欄位 fail-loud。
- **refinement skill 為所有 source populate per-task body 欄位**（DP-302-T3）：`refinement/SKILL.md` + `references/refinement-artifact.md` 接線 behavior_contract 判定，為所有 source populate per-task body 欄位。
- **parity gate 補 render-body coverage**（DP-302-T4）：`validate-spec-source-parity.sh` 補 render-body coverage（field-driven DP-only literal proof）；selftest 補對應覆蓋。

## [3.75.155] - 2026-06-09

### Added — DP-300 session mid-task resume：active-thread anchor 從單 thread advisory 升 multi-thread fail-closed 機制

把跨-session resume 的 active-thread anchor 從「單 thread + advisory 提醒」缺口，收斂成 multi-thread fail-closed 機制：parked work 未刷新 anchor 即 block stop，且 anchor 可並存多條 thread 全列。

- **grounded 診斷落地 + registry 標註**（DP-300-T1）：DP 文件寫入 grounded 診斷（canonical path 命名 DP-290 active-thread 三件套、writer advisory-only 無 trigger / single-thread overwrite 兩根因、機制 vs path-flaw 判定）；`mechanism-registry.md` 新增 `active-thread-writer-trigger-gap` / `active-thread-single-thread-overwrite` 兩 canary，deterministic target 指向 T2/T3 selftest。
- **Stop gate 升 fail-closed**（DP-300-T2）：`stop-active-thread-reminder.sh` 從 advisory 升為 fail-closed Stop gate——偵測 incomplete work（TodoWrite in_progress 或 fallback：未 closeout boundary baseline）+ 本 session 未刷新 anchor → block stop + 提示刷新；明確 bypass / 無 parked work → exit 0。新增 selftest 涵蓋 block / 不擋 / bypass / false-positive 四態。
- **multi-thread anchor upsert + 全列 reader**（DP-300-T3）：`update-active-thread.sh` 改 per-thread-key upsert（寫第二條不 clobber 第一條、同 key idempotent、`--done`/`--remove`）；`session-start-thread-anchor.sh` reader 注入所有 active thread 下一步。既有單 thread selftest 回歸全綠。

## [3.75.154] - 2026-06-09

### Added — DP-299 prose-vs-gate 行為原則准入標準 + review-inbox discovery fail-closed probe

把「該不該再寫一條 prose 提醒」收斂成一條明文准入標準，並用 review-inbox discovery 的 fail-closed probe 作為「A 類 invariant 落成 gate」的 worked example，阻止 prose 治 prose 通膨。

- **prose-vs-gate 行為原則准入標準落地**（DP-299-T1）：`contract-design.md` Heuristic 1 新增准入標準——新增行為原則先分類 A 類（gateable invariant，必須做成 fail-closed gate，禁止 prose-only）或 B 類（無 tool-call 邊界的純態度/生成行為，唯一合法落地是 `mechanism-registry.md` canary entry，禁止新增 prose 規則規範態度）；附 carve-out 保護既有 rationale/background prose 不被機械刪除，並登記 `prose-vs-gate-admission` canary 吃自己狗糧。
- **review-inbox discovery fail-closed probe（worked example）**（DP-299-T2）：新增 `scripts/review-inbox-discovery-probe.sh` + selftest，把原本靠 prose「主來源不可用時應早報、不要靜默 fallback」的 A 類 invariant 落成實際 fail-closed gate。
- **discovery-flow 改 detailed 並串接 probe**（DP-299-T3）：`review-inbox-discovery-flow.md` 改為 detailed 一致化敘述，串接 fail-closed probe 作為 discovery 主來源不可用時的早報路徑。

## [3.75.153] - 2026-06-09

### Fixed — DP-298 business gate 讀 authoritative refinement.json 而非 derived refinement.md（DP-296 fix-forward）

把所有 business gate 的判斷來源從 derived `refinement.md` body 收斂到 authoritative `refinement.json`，解開 DP-295 的 locked-scope dead-lock，並把語言不變式前移到 write-time。

- **canonical 契約落地 + derived-md reader 盤點守門**（DP-298-T1）：`canonical-contract-governance.md` 新增明文條文「任何 business gate 不得讀 derived `refinement.md` body，對 `refinement.md` 唯一允許 idempotency/parity `--check`」；新增 regression lint `lint-no-business-gate-reads-derived-md.sh`，以 allowlist 區分 idempotency/parity/shape/existence reader（legitimate）與 business-read（violation）。
- **locked-scope guard 改只驗 JSON 權威欄位**（DP-298-T2）：`validate-refinement-locked-scope.sh` 移除讀 `refinement.md` `## Scope`/heading diff 的 business 分支，只保留 `LOCKED_JSON_FIELDS` JSON 比對，解開 DP-295「amend 非 LOCKED 欄位卻被 derived md 誤判 exit 2」的 dead-lock；LOCKED 保護不變。
- **語言不變式前移至 write-time**（DP-298-T3）：`validate-language-policy.sh` 新增 JSON field-aware mode，對 `refinement.json` human-facing prose 欄位（`tasks[].title`/`tasks[].scope`/`acceptance_criteria[].text`）逐欄位驗 config 語言，沿用既有 inline-code strip heuristic 避免誤擋技術術語。
- **交付/接收邊界綁定 prose 欄位語言**（DP-298-T4）：`validate-refinement-consumer-schema-binding.sh` 延伸 DP-296 schema-binding，把 prose 欄位語言合規納入交付/接收邊界檢查。

## [3.75.152] - 2026-06-09

### Fixed — DP-296 skill produce/consume canonical 契約綁定 + selftest callsite parity

把 refinement.json 的 task 描述從 legacy top-level `planned_tasks[]` 收斂成單一 canonical `tasks[]` schema（`task_shape` / `tracked_deliverable_hint` 為 first-class 欄位），收緊 validator、遷移所有消費端、新增 consumer schema-binding 守門 gate，並把 DP-294 fix-forward 的 selftest 對齊真實 callsite 形狀；四段 skill 互走契約一併文件化。版號治理機制本身的根本解法留待 DP-295。

- **遷移腳本與既有 active source 收編**（DP-296-T1）：新增 `migrate-refinement-planned-tasks-to-canonical.sh`（orphan fail-loud、idempotent），把 DP-296 自身與 7 個 LOCKED sibling（DP-242/272/274/280/281/282/289）的 active refinement.json 由 `planned_tasks[]` 折進 canonical `tasks[]`。
- **收緊 schema validator**（DP-296-T2）：`validate-refinement-json.sh` 對 top-level `planned_tasks[]` fail-close，接受 `tasks[].task_shape` / `tracked_deliverable_hint`。
- **消費端遷移**（DP-296-T3）：`derive-task-md-from-refinement-json.sh` 與 `validate-refinement-lock-preflight.sh` 改讀 canonical `tasks[]`，移除 `planned_tasks[]` 讀取。
- **consumer schema-binding gate**（DP-296-T4）：新增 `validate-refinement-consumer-schema-binding.sh`，消費端讀 schema 外欄位時 exit 非 0，接進 `check-framework-pr-gate.sh`。
- **DP-294 fix-forward callsite-real selftest**（DP-296-T5）：四主題（T1 真實 nested bundle、T2 live-ledger re-anchor、T6 hermetic session-lock、T7 LOCK-preflight title-language）各帶對齊真實 callsite 形狀的斷言與 negative counterpart。
- **四段 skill canonical 契約文件**（DP-296-T6）：refinement / breakdown / engineering / verify-AC 的 SKILL.md 與共用 `pipeline-handoff.md` 載明預設互走 canonical 契約 + standalone fallback LLM 契約。
- **research-dispatch-unit selftest fixture canonical 化**（DP-296-T7）：`validate-breakdown-ready-research-dispatch-unit-selftest.sh` 的 2 個 LOCK-time fixture 由 `planned_tasks[]` 改寫為 canonical `tasks[]`，research-lock case 正確 exit 2（`POLARIS_RESEARCH_UNIT_NO_IMPLEMENTATION`）。

## [3.75.151] - 2026-06-07

### Fixed — DP-294 framework deterministic-gate correctness follow-ups

把 DP-293 release 全程實證的 7 個 framework deterministic-gate 缺口收斂成「單一共用標準規格」（canonical shared spec），而非增開容許／豁免規格；每個缺口的解法都是一條涵蓋既有與新情境的 canonical contract / single writer path / deterministic classifier。

- **Theme 1 — 共用 delivery-branch worktree resolution**（DP-294-T1）：`resolve-task-worktree.sh` 把解析重新定義為「work-item 的 delivery branch worktree」，per-task task branch 與 bundle `bundle_branch_alias` 共用同一條 canonical 規則；bundle-delivered DP（含 V task）的 verify-AC dispatch 不再 false `blocked_by_missing_worktree`，per-task 解析行為不變。
- **Theme 2 — amendment 同步 in-flight ledger refinement_hash**（DP-294-T2）：in-session breakdown amendment 經 amendment writer 單一 writer path re-anchor auto-pass ledger 的 `refinement_hash`，resume runner source gate 不再對 amend 後 fresh marker false-stale；runner 維持 reader，不加 stale-but-ok 分支。
- **Theme 3 — 語言守則 selftest 斷言指向 SoT**（DP-294-T3）：`runtime-final-response-language-guard-selftest.sh` 斷言改指 runtime overlay 三檔（claude/codex/copilot），origin/main 不再長期假紅燈；closeout parity advisory 確認。
- **Theme 4 — metadata-only/release-bump commit deterministic 分類**（DP-294-T4）：純 VERSION/CHANGELOG/release-metadata commit 與 non-ticket framework T-task 由共用 deterministic classifier / completion-gate marker 判定 evidence，D15 pre-push gate 與 closeout consumer（`check-local-extension-completion.sh`）共用同一規則，移除對 `POLARIS_SKIP_EVIDENCE` carve-out 的依賴。
- **Theme 5 — refinement-inbox canonical producer**（DP-294-T5）：補 canonical producer token + 把 `write-producer-owned-artifact.sh` 納入 `evidence-producers.json` refinement-inbox writer_scripts，inbox emission 與其他 producer 同型（token-first lookup + atomic write + validator），amendment loop 可機械觸發。
- **Theme 6 — selftest session-lock hermeticity**（DP-294-T6）：`resolve-task-md.sh` 內嵌 selftest 改用 hermetic lock 路徑 + trap 清理，不再洩漏 live session lock 誤擋正常 work-order 解析。
- **Theme 7 — LOCK-preflight 任務標題語言守則**（DP-294-T7）：`validate-refinement-lock-preflight.sh` 合成 placeholder task.md 時帶入真實 `tasks[].title`，重用既有 `validate-task-md.sh` summary-language 判定（無第二套 classifier），English-only title 在 LOCK 即 fail-stop，不再逃逸到 breakdown。

## [3.75.150] - 2026-06-07

### Fixed — DP-293 framework deterministic release & closeout gate correctness

修正 DP-290 release 過程實證踩到的三類 framework deterministic-gate 正確性缺陷，讓 self-iteration 不再被自身壞 gate 擋住，也不讓 generated-artifact drift 與 incomplete delivery 漏過 gate。

- **Theme A — runtime-instruction parity 對 PR head tree 生效**（DP-293-T1）：`run-governed-script-tests.sh` release profile 把 `--head-ref` checkout 到隔離 tree，讓 `compile --check` 類 selftest 跑在 PR head 而非 selftest 自身 main checkout；移除 3 支 selftest 寫死的 BASH_SOURCE ROOT；`check-framework-pr-gate.sh` 新增 blocking W11 parity step（`compile-runtime-instructions --check` + `mechanism-parity --strict`）。
- **Theme B — closeout loop soft-block 容錯**（DP-293-T2）：`framework-release-closeout.sh` per-task loop 對 `close-parent-spec-if-complete.sh` rc==2（active verification tasks remain 類 intentional block）改為 soft-block continue 並 log parent + reason，非 2 exit 仍 fail loud；含 implementation + verification 的 bundle 可單次 invocation 收尾。
- **Theme C — verify-evidence skip 契約端到端對齊**（DP-293-T3）：`check-local-extension-completion.sh` consumer 端與 engineering producer 端對 `POLARIS_SKIP_EVIDENCE` skip 契約一致，消除 producer 跳過、consumer 硬要的互斥。
- **Theme D — refinement research producer**（DP-293-T4）：`scripts/lib/evidence-producers.json` 新增 refinement-owned research producer entry（glob `artifacts/research/*.md`）+ token `refinement:research-snapshot`，與 learning research 同型且 token 唯一。
- 4 支新 hermetic selftest（release-lane-head-ref-parity / framework-release-closeout-mixed-task-bundle / local-extension-verify-evidence-contract / refinement-research-producer）覆蓋 AC1-AC6 + AC-NEG1/2。

### Verified

DP-293-V1 verify-AC：9/9 PASS（AC1-AC6 + AC-NEG1/2/3）@ bundle head efd35ff，全於 PR head tree 重跑。Pre-existing Gap G（runtime-final-response-language-guard-selftest）為 origin/main 既有 FAIL、非 release governed suite、與 DP-293 無關，未計入。

## [3.75.149] - 2026-06-06

### Added — DP-290 deterministic cross-session handoff via SessionStart anchor hook

用 `SessionStart` startup hook 機械注入單一 canonical active-thread 錨點，讓跨-session handoff 從「靠 harness 隨機 recall memory + 使用者貼對 resume prompt」的機率性，收斂成 deterministic 注入。解決多次切 session 後 plan / next-action 遺失、舊計劃變殭屍的問題。

- **`scripts/update-active-thread.sh`**（DP-290-T1，single writer）：覆寫（不 append）維護 `.claude/active-thread.md` 錨點，idempotent，帶 `last-updated` 時戳，>10,000 字元時截斷尾段、保留「下一步」頭段並印提示（官方上限）。`.gitignore` 忽略錨點檔（session 狀態非 source）。
- **`.claude/hooks/session-start-thread-anchor.sh` + `.claude/settings.json`**（DP-290-T2）：SessionStart `startup` matcher fail-open hook，開場 `cat` 錨點 + branch + dirty filename 注入 context，**exit 0 永不 block**（缺檔印 fail-open 提示、非 git 目錄 / git status 失敗皆 exit 0）；只 cat + git status，不 dump env / secrets。
- **`.claude/hooks/stop-active-thread-reminder.sh` + `.claude/settings.json`**（DP-290-T3）：session-end Stop advisory 提醒更新錨點，exit 0 不 block；配套 selftest。
- **`.claude/rules/mechanism-registry.md`**（DP-290-T4）：Runtime Annotation Registry 新增 `session-start-thread-anchor`（claude-code-only + portable writer fallback）、`update-active-thread`、`stop-active-thread-reminder` 三條條目，通過 `validate-mechanism-runtime-annotations` + `mechanism-parity --strict`。
- **三支 hermetic selftest**（`update-active-thread-selftest` / `session-start-thread-anchor-selftest` / `stop-active-thread-reminder-selftest`）覆蓋 AC1-AC6 + AC-NEG1/2，registered 進 script manifest。

### Why

新 session 的自動載入面只有 `CLAUDE.md` / `MEMORY.md` Hot 索引 / harness 隨機 recall 的 memory / 使用者貼的 prompt；`user/` 計劃、checkpoints、resume prompt 都不在自動載入面，導致 handoff state 切多次必失。官方 docs 證實 `SessionStart startup` hook stdout 注入是唯一 deterministic 通道。DP-290 以 single-writer 錨點 + fail-open hook 把 handoff 收斂成 deterministic，對齊 `canonical-contract-governance.md` § No special writer paths 與 `contract-design.md` § Deterministic-First。

### Verified

DP-290-V1 verify-AC：8/8 PASS（AC1-AC6 + AC-NEG1/2），全 unit_test method。3 支 hermetic selftest 於 bundle head `46be4c0` 獨立重跑 rc=0；`.claude/settings.json` SessionStart matcher startup 由 jq assert 確認；AC-NEG1 no-env-dump 經 selftest grep + 原始碼比對（env pattern 僅在註解）；`validate-mechanism-runtime-annotations` PASS / `mechanism-parity --strict` IN SYNC / `check-script-manifest` PASS / `verify-cross-llm-parity` PARITY OK / `scan-template-leaks` 0 hits。Bundle 內含 T1-T4 per-task commits。

## [3.75.148] - 2026-06-05

### Fixed — DP-273 framework-release auto-pass delivery-lane hardening（multi-DP bundle / post-bundle closeout / version-race robustness）

修正 framework-release closeout 三道牆（Wall A/B/C）在 multi-DP bundle、no-branch task、refinement-session boundary 與 stale baseline 場景下的 false-positive，讓 bundle release 與 single-DP release 共用同一條 deterministic closeout 路徑且 idempotent。

- **`scripts/framework-release-closeout.sh` / `scripts/engineering-clean-worktree.sh`**（DP-273-T1，Wall A + Wall C，已於 #514 / T1 交付）：closeout 的 head-ancestry 斷言改 **bundle-aware**——偵測 `bundle_branch_alias` / Bundle Identity 時以 bundle release head（release diff ∩ Allowed Files）驗交付，取代 per-task-head ancestry；`engineering-clean-worktree.sh` 的 delivered-head-ancestry 同步套 bundle release head（copy-content 變體）。Wall C 對 `task_shape ∈ {confirmation, verify}` 且無 `task_branch` 的 task 不再 `die`，改以 content-delivered 語義（驗 deliverable 證據後）flip IMPLEMENTED 計入 parent completion，並辨識 **legacy no-branch `task_kind:V`** 舊式驗收子單慣例（evidence 在 → flip IMPLEMENTED；container 其餘已齊 → parent archive；evidence 缺 → fail-closed）。single-DP 非 bundle 維持原嚴格 per-task-head 路徑；重跑 idempotent。
- **`scripts/check-main-chain-compliance.sh` / `scripts/refinement-handoff-gate.sh` / `scripts/skill-workflow-boundary-gate.sh`**（DP-273-T2，Wall B，已於 #515 / T2 交付）：release-tail（closeout）context 跳過 `skill-workflow-boundary-gate --skill refinement --check`（該 boundary 只屬 live refinement→breakdown handoff，closeout 不應 re-validate refinement-session scope）；`skill-workflow-boundary-gate.sh` 加 defense-in-depth——refinement handoff gate PASS 後清理該 source 的 stale boundary baseline，避免後續 closeout 誤判 out-of-scope mutation。不放鬆 live handoff boundary。
- **`scripts/selftests/framework-release-closeout-bundle-task-closeout-selftest.sh` / `scripts/selftests/closeout-no-refinement-session-boundary-selftest.sh`**（DP-273-T1 / T2，AC1-AC7 + AC-NEG1-3 deterministic evidence）：兩支 hermetic selftest 覆蓋三道牆，含 **C-LEGV** case（no-branch legacy `task_kind:V`）驗 AC4；`mechanism-registry.md` 補 `framework-release-closeout-bundle-task-closeout` 與 `closeout-no-refinement-session-boundary` runtime annotation。

### Why

DP-191 形態的 bundle release（單顆 PR bundle 多 task，`tasks/pr-release/` pattern）與 DP-242/269 形態的 no-branch confirmation/verify task，在舊 closeout per-task-head ancestry 斷言下會 false-positive `die`，把合法 bundle / no-branch 交付擋在 release tail 之外；release-tail closeout 又誤跑 live refinement-session boundary check，對已收尾的 source 報假性 out-of-scope。DP-273 把三道牆收斂成 bundle-aware + content-delivered + closeout-context-aware 的 deterministic 判定，並以 hermetic selftest fail-closed 固定行為，對齊 `contract-design.md` § Deterministic-First 與 `canonical-contract-governance.md` § No special writer paths。

### Verified

DP-273-V1 verify-AC：11/11 PASS（AC1-AC7 + AC-NEG1-4）。AC4 走 `framework-release-closeout-bundle-task-closeout-selftest.sh` 的 C-LEGV case（no-branch legacy `task_kind:V`）；AC-NEG4 由 selftest 內 closeout 真路徑佐證、無 hand-assemble marker。兩支 hermetic selftest 全 case PASS（33/33 + 6/6）+ `check-script-manifest.sh --root . --quiet` PASS + template-leak scan 0 hits。Bundle 內容經 cherry-pick T1（`2093ea0`）/ T2（`3d14843`）commits 組成。

## [3.75.147] - 2026-06-04

### Added — DP-238 pipeline handoff contract slimming（refinement → breakdown → engineering → verify-AC）

清理 `refinement -> breakdown -> engineering -> verify-AC` 之間的冗餘 handoff contract：在不降低 pipeline 可靠性的前提下，讓每個 cross-skill 欄位都能回答 canonical authority、derived surface、防 drift validator 與 LLM role，並降低 LLM 在每段 handoff 前 reconcile 多份 prose / schema 的負擔。

- **`.claude/skills/references/pipeline-handoff.md`**（DP-238-T1，已於 #460 / T1 merge，本 bundle 不含 code diff）：新增 handoff atom matrix，盤點 `refinement.json` / T task.md / V\*.md / lifecycle marker / orchestration signal 的 owner / canonical source / derived surface / validator / LLM role；matrix 只保留 pointer，不再整份 copy schema。`scripts/selftests/pipeline-handoff-authority-selftest.sh` 新增 `atom-matrix-required-columns` / `atom-matrix-no-full-schema-copy` / `probe-ledger-atom-declared` cases。
- **`.claude/skills/{breakdown,engineering,refinement,verify-AC}/SKILL.md` / `.claude/skills/references/{INDEX,refinement-artifact,task-md-schema-verification}.md`**（DP-238-T2，AC2-AC4）：修正 consumer 邊界並收斂重複 schema reference。`refinement.json` 確立為需求 / AC machine source，`task.md` 為 `engineering` 唯一施工來源，V\*.md 確立為 execution envelope（非第二份 AC authority）；各 skill 主文只保留 routing / owning scope / fail-stop / pointer，duplicate schema prose 移除。selftest 新增 `engineering-consumer-boundary` / `v-envelope-boundary` / `duplicate-schema-scan` cases。
- **`scripts/selftests/pipeline-handoff-authority-selftest.sh`**（DP-238-T3，AC3 / AC5 / AC7）：新增 duplicate / drift 的 deterministic selftest 守則，覆蓋 duplicate schema table、consumer boundary、V\*.md drift、raw prose 補判斷與 derived-copy drift policy；新增 `probe-ledger-schema-parity` case，與 `verify-AC-deterministic-consumption-selftest.sh` 串接。
- **`scripts/{parse-task-md,resolve-task-branch,gate-pr-title,polaris-pr-create,check-delivery-completion,run-verify-command}.sh` / `scripts/gates/gate-pr-title.sh` / `scripts/manifest.json`**（DP-238-T4，AC5 / AC6）：補 Bug source product PR identity consumer 邊界——內部 task DAG identity 用 `work_item_id`（例 `PROJ-4190-T1`），產品 repo branch / PR title / JIRA transition 用真實 `jira_key`（例 `PROJ-4190`），消除 legacy `task_jira_key` alias 把 `T1` suffix 外溢到產品 PR title / branch 的 drift。selftest 新增 `identity-atom-split` / `bug-source-product-pr-identity` 與 negative cases（no-gate-removal / legacy-reader-compatibility / bug-source-product-pr-identity-negative）做 regression 鞏固，確認 slimming 未移除 gate、未破壞 legacy reader、未增加 runtime-specific 依賴。

### Why

pipeline 的可靠性設計方向正確，但交付面混在一起：`refinement-artifact.md` 仍暗示 `engineering` 可直讀 `acceptance_criteria[].verification` 與 `modules[].path`；同一批 AC / module 語意散落在 `refinement.json` / `task.md` / V\*.md prose；多個 skill 重複 `pipeline-handoff` / language / producer-env / boundary gate / schema 段落，維護成本高且讓 LLM 在每段 handoff 前吸收大量低階 contract。PROJ-4190 dogfood 進一步暴露 identity handoff 混亂。DP-238 把 cross-skill 欄位收斂成單一 canonical authority + derived surface + deterministic drift gate，對齊 `contract-design.md` § Deterministic-First 與 `canonical-contract-governance.md` § No special writer paths。

### Verified

DP-238-T2 / T3 / T4 各自 Layer B verify evidence exit 0（`pipeline-handoff-authority-selftest.sh` 全 case + `verify-AC-deterministic-consumption-selftest.sh` + `validate-refinement-json.sh` + `check-script-manifest.sh --root . --quiet` PASS）。Bundle 內容經 cherry-pick T2/T3/T4 commits 組成，tree 與已驗 T4 tip（`dbb41c4`）byte-identical。

## [3.75.146] - 2026-06-04

### Added — DP-274 delivery-unit completion-standard contract（D1）+ 研究單（D2）/ 轉發 theme 單（D3）定義與 D4 deterministic gate

- **`.claude/skills/references/delivery-unit-completion-standard.md`**（DP-274-T1，新檔，D1/D2/D3 canonical 契約）：新增 delivery unit 結案標準的 canonical reference。**D1**：delivery unit 必須具備 runtime-verifiable 結案標準（至少一條可機械執行的 AC + 合法 producer / sanctioned writer 路徑 + 至少一張 `task_shape: implementation` task），form / format proxy（只把 status 字串改成 `IMPLEMENTED`、只產 audit prose、全 `manual` AC）不算結案 → hollow completion。**D2**：研究單（全 audit task、無 implementation task、無 verifiable AC、不改 production contract）是 refinement-phase activity，收編進 implementation DP 的 refinement seed，不獨立成 delivery unit。**D3**：轉發 / theme 單（無自身 verifiable AC、deliverable 僅 dispatch 到其他 concrete DP）改寫成 north-star artifact（含 supersede 訊號：被 seed 的 concrete DP 全 IMPLEMENTED 即標 superseded），禁止成為 delivery DP。
- **`.claude/rules/canonical-contract-governance.md`**（DP-274-T1）：新增 § Delivery Unit Completion Standard routing pointer，把 D1/D2/D3 收進 canonical contract governance（對齊 Strong constraints first / Fail closed on missing inputs），並指明 D4 deterministic gate 負責機械 enforce。
- **`scripts/validate-breakdown-ready.sh` / `scripts/validate-refinement-lock-preflight.sh`**（DP-274-T2，D4 deterministic gate，AC2）：在 directory target 對 source 跑 delivery-unit shape gate，**banks on 既有 `task_shape` classifier**（不另寫第二套 classifier、不做 full rescan）：研究單 fail-stop exit 2 + `POLARIS_RESEARCH_UNIT_NO_IMPLEMENTATION`，轉發 / theme 單 exit 2 + `POLARIS_DISPATCH_THEME_UNIT_NO_IMPLEMENTATION`；含 ≥1 implementation task 的 mixed-task DP（DP-262 carve-out）PASS。`validate-refinement-lock-preflight.sh` 委派同一判定，LOCK 時就擋。`mechanism-registry.md` 新增 `research-dispatch-unit-gate` runtime annotation + canary entry。
- **`scripts/lib/evidence-producers.json` / `scripts/write-producer-owned-artifact.sh`**（DP-274-T3，D9 producer-env writer coverage，AC5）：refinement design-doc 的 sanctioned writer 補成 `refinement:primary-doc` producer token（綁 refinement 容器 index.md glob）；`write-producer-owned-artifact.sh` 新增 `artifact_kind=refinement_primary_doc` 分支——index.md 寫入後跑 primary-doc content gates（`validate-spec-primary-doc-authoring.sh` for DP-backed paths、`validate-starlight-authoring.sh` + `validate-language-policy.sh` for all paths），失敗 rollback。non-owning token 寫 container index.md 仍被 path-glob check 擋下，binding 不外溢到任意 .md。
- **`scripts/selftests/validate-breakdown-ready-research-dispatch-unit-selftest.sh` / `scripts/selftests/write-producer-owned-artifact-refinement-coverage-selftest.sh`**（DP-274-T2 / T3，AC2 / AC5 evidence）：2 支 selftest 覆蓋研究單 / 轉發單 fail-stop、mixed-task carve-out PASS、refinement design-doc sanctioned writer 路徑與 content gate rollback。
- **DP-274-T4 migration（plan 紀錄，非本 bundle code diff）**：DP-247 標記 SUPERSEDED + in-flight cleanup（4-dimension scope）；Multi-DP plan 以 durable DP-248-251 seed inline 記錄於 DP-247；DP-263 reclassify 成 north-star artifact；Plan B 完成定義對齊 D1 runtime-verifiable 標準。

### Why

過去研究 umbrella / 轉發 theme 單會被當成獨立 delivery unit 走主鏈並期待 `IMPLEMENTED` 終局，但它們沒有 runtime-verifiable 結案標準，只能靠 form proxy（status 字串、audit prose）宣告完成 → hollow completion，且 north-star 方向容器無 lifecycle 永久 stale。DP-274 把 delivery-unit 結案標準收斂成 canonical contract（D1），明文研究單（D2）/ 轉發 theme 單（D3）的正確收編路徑，並用 D4 deterministic gate（banks on 既有 task_shape classifier，無第二套）在 LOCK / breakdown 階段機械擋下，對齊 contract-design.md § Deterministic-First。同時補上 refinement design-doc 的 producer-env sanctioned writer 覆蓋（D9），消除「文件規範 sanctioned writer 但實際沒有 producer 路徑」的 hollow writer gap。

### Verified

驗收委派 DP-274-V1：9/9 AC PASS（AC1-AC6 + AC-NEG1-NEG3）。`bash scripts/selftests/validate-breakdown-ready-research-dispatch-unit-selftest.sh` PASS（研究單 / 轉發單 fail-stop + mixed-task carve-out PASS）；`bash scripts/selftests/write-producer-owned-artifact-refinement-coverage-selftest.sh` PASS（refinement design-doc sanctioned writer + content gate rollback）；`bash scripts/check-script-manifest.sh --root . --quiet` PASS；`bash scripts/compile-runtime-instructions.sh --check` PASS。

## [3.75.145] - 2026-06-04

### Added — DP-281 write-ac-verification.sh emit ac_verification verdict marker（canonical deterministic writer）

- **`scripts/write-ac-verification.sh`**（DP-281-T1，AC1–AC6 / AC-NEG1–NEG2）：擴充為 `ac_verification` verdict marker 的唯一 canonical deterministic writer。新增 `--source-id` / `--work-item-id` / `--head-sha` flag（D2）；source `scripts/lib/main-checkout.sh` 以 `resolve_main_checkout` 把 marker 錨定到 main checkout（D3），即使在 `git worktree` 內被 auto-pass 呼叫，marker 仍落 main checkout 的 `.polaris/evidence/ac-verification/{work_item}-{head}.json`，與 `auto-pass-runner` probe 路徑一致；只有 terminal verdict status（PASS / FAIL / MANUAL_REQUIRED / UNCERTAIN / BLOCKED_ENV）才 emit marker、`--status IN_PROGRESS` 只寫 frontmatter（D4）；marker payload 對齊 D5 schema（schema_version / marker_kind=ac_verification / writer=verify-AC / owning_skill=verify-AC / source_id / work_item_id / status / ac_counts / human_disposition / freshness / 正確 ISO8601 UTC `at` / summary），並帶 `ticket` / 頂層 `head_sha` 相容別名供既有 reader 使用；marker emit 失敗 fail-stop exit 1（D6）。pattern 對齊 `scripts/write-completion-gate-marker.sh`。
- **`.claude/skills/verify-AC/SKILL.md` / `scripts/lib/evidence-producers.json`**（AC5）：消除 documented≠implemented drift — registry notes 與 SKILL.md 敘述均更新為「write-ac-verification.sh 實際 emit ac_verification verdict marker（main-checkout 錨定、IN_PROGRESS 不 emit、純 Bash file I/O、fail-stop exit 1）」，並補新 flag 呼叫範例。
- **`scripts/check-local-extension-completion.sh`**：確認 `check_ac_verification_evidence` 與新 marker 相容（marker 頂層 `ticket` / `head_sha` 別名滿足既有 reader 期望，`writer=verify-AC` 已在 whitelist），加註 DP-281 compatibility 說明。
- **`scripts/selftests/write-ac-verification-selftest.sh`**：擴充涵蓋 AC1（marker D5 schema）、AC2（worktree→main-checkout 錨定）、AC3（實跑 `auto-pass-probe` verify-AC stage 得 status=PASS / next_action=report / terminal=complete）、AC4（IN_PROGRESS 不 emit）、AC5（registry + SKILL.md 文件對齊）、AC6（no-POLARIS-env script I/O）、AC-NEG1（缺 flag fail-stop）、AC-NEG2（marker 失敗 exit 1）。

### Why

`scripts/write-ac-verification.sh` 先前只寫 V\*.md frontmatter，registry 與 SKILL.md 卻宣稱它會產生 `ac_verification` marker（documented≠implemented）。auto-pass-runner verify-AC stage 依賴 `.polaris/evidence/ac-verification/{work_item}-{head}.json` marker 判定 terminal complete；缺 marker 會讓 verify-AC PASS 卻無法收斂。DP-281 把這支 writer 補成 marker 的唯一 sanctioned writer，並用 main-checkout 錨定解決 worktree（auto-pass 寫）與 main checkout（probe 讀）路徑不一致的 circular missing-marker 問題。

### Verified

`bash scripts/selftests/write-ac-verification-selftest.sh` PASS（AC1–AC6 + AC-NEG1–NEG2 全綠，含實跑 `auto-pass-probe` verify-AC stage assert status=PASS / next_action=report）；`bash scripts/check-script-manifest.sh --root . --quiet` PASS。驗收委派 DP-281-V1。

## [3.75.144] - 2026-06-03

### Added — DP-277 memory-hygiene topic-folder-aware index producers（apply / emit-index 收斂單一磁碟列舉 + apply chain 透明 gate）

- **`scripts/memory-hygiene-tiering.py`**（DP-277-T1，AC1–AC4 / AC-NEG1–NEG3）：新增 `discover_topic_folders()` 與 `enumerate_topic_folder()`，apply topic-index writer 與 `render_emit_index_block` 的 per-topic 段共用同一個「以磁碟列舉」來源，消除 apply 與 `--emit-index` 各自列舉造成的 MEMORY.md per-topic pointer drift。topic folder pointer 即使 warm set 為空仍保留（flat-empty 不再吃掉 pointer）、`archive/`（Cold 區）排除、缺 frontmatter 的檔 link text fallback 到檔名不 crash。
- **`scripts/validate-memory-hygiene-plan.sh`**（DP-277-T2，AC5 / AC6 / AC-NEG4）：改為透明 pipe gate — PASS 把驗證過的 plan JSON 原樣輸出到 stdout、verdict 寫 stderr；FAIL stdout 不輸出 plan 且 exit 非 0，讓 documented chain（`dry-run --json | validate | apply`）在 `set -o pipefail` 下 fail-closed。`.claude/skills/references/memory-hygiene-apply-flow.md` Preferred Command 改為單管 chain；修正 DP-213 後遺留的 stale `invalid_nested` fixture（`nested_frontmatter` 現為 warnings-only）並對齊兩個 coupled selftest 的 verdict→stderr 契約。

### Why

memory-hygiene 的 apply 與 `--emit-index` 兩條 index producer 原本各自列舉 topic 來源，造成 MEMORY.md per-topic pointer 與 `{topic}/index.md` 內容 drift；plan 驗證閘原本吃掉 stdout，使 documented apply chain 無法 fail-closed。DP-277 把兩條 producer 收斂到單一磁碟列舉 source of truth，並把 plan gate 改成透明 pipe，讓 chain 在 plan 不合法時確實中止、不污染 memory_dir。

### Verified

V1 verify-AC dogfood 12/12 PASS（AC1–AC6 + AC-NF1 / AC-NF2 + AC-NEG1–NEG4）：5 個 selftest（topic-folder-index / apply-chain / validate-plan / emit-index / tiering）exit 0、AC-NF1 diff 無新 PyPI import、AC-NF2 emit-index generated-block marker byte-equivalent 無變更。aggregate-release bundle PR #505（T1 + T2 content + V1 verify-report）。

## [3.75.143] - 2026-06-02

### Added — DP-242 DP-240 legacy backfill audit（scripts / markdown / cross-LLM hooks 分類盤點）

- **`docs-manager/src/content/docs/audits/dp-242/audit-scripts.md`**（DP-242-T1，AC1 / AC7）：擴展 `script-ownership-audit.{sh,py}` 掃描範圍至 `.py` / `.mjs` / `.ts`（per DP-240 D26 multi-language scope），對 `scripts/**`、`.claude/skills/**/scripts/**`、`.claude/hooks/**` 三組 root 分類盤點；每筆 entry 採 D2 8 欄 schema（path / role / owner / callers / usage_status / compliance / target_disposition / follow-up_DP），結尾含 per-extension 小計（.sh 533 / .py 25 / .mjs 12 / .ts 2 / Total 572）與 `## Open Questions for follow-up DP`（7 條，導向 DP-243）。
- **`docs-manager/src/content/docs/audits/dp-242/audit-markdown.md`**（DP-242-T2，AC2 / AC7）：framework markdown 合規性 audit，8 欄 schema（compliance 細分 frontmatter / Starlight / language-policy / producer-specific），含 ARCHIVED carve-out（`archive-legacy_grandfathered` → DP-244）、`_template/**` 與 generated-target exclusion、known-exception 清單，及 4 條 Open Questions（導向 DP-244）。
- **`docs-manager/src/content/docs/audits/dp-242/audit-hooks.md`**（DP-242-T3，AC3 / AC7）：cross-LLM hook parity audit，逐 hook 採 8 欄 schema + Claude / Codex / Copilot runtime 細分、18-row parity matrix、行為等價（behavior parity）語義宣告、每筆 intentional-gap rationale，及 4 條 Open Questions（導向 DP-245）。
- **DP-242 `index.md` `## Multi-DP Plan` + `## Audit Findings`**（DP-242-T4，confirmation no-PR）：確認 DP-243 / DP-244 / DP-245 / DP-246 四張 follow-up DP 規劃表（6 欄）與兩條 framework-gap finding（refinement-lock-preflight-gap / audit-only-dp-shape-gap）齊備；以 `task_shape: confirmation` completion-gate marker 無-PR 完成（DP-262 carve-out + DP-272 derive propagation 落地）。

### Why

DP-240 D26 把 multi-language hot path executable（`.sh` / `.py` / `.mjs` / `.ts`）納入 framework script governance scope，但既有 legacy script / markdown / cross-LLM hook 從未做過一次完整分類盤點。DP-242 以 audit-only DP 先盤點現況（classify），把實際 refactor 拆進 DP-243 / DP-244 / DP-245 / DP-246 follow-up（then refactor），避免一次大改 legacy 造成不可控 diff。

### Verified

V1 verify-AC 端對端 10/10 PASS（AC1–AC7 + AC-NEG1 / AC-NEG2 / AC-NEG3）：三份 audit schema / coverage / carve-out / Open Questions 完整、`index.md` 兩 section 齊備、4 份 tracked markdown frontmatter + language-policy + Starlight gate replay PASS、累計 < 200KB；implementation 未觸碰 production surface、未提前 seed follow-up container、未改 `.gitignore`。aggregate-release bundle PR（T1–T3 content + V1 verify-report）。

## [3.75.142] - 2026-06-02

### Added — DP-269 JIRA-Epic-backed source 與 auto-pass initial-create lane 對稱（T1–T5 bundle）

- **`scripts/derive-task-md-from-refinement-json.sh`**（DP-269-T1，AC1 / AC2 / AC5）：derive 依 `source.type` 分 dp / jira 兩 mode。jira mode 從 `refinement.json` 注入真實 `tasks[].jira_key` 作 task identity、`source.repo` 作 `Repo`、`source.base_branch` 作 `Base branch`、`JIRA key` cell 為真實 key；`jira_key=null` 或缺 `source.repo` / `source.base_branch` 時 fail-closed（無 N/A fallback）。dp mode 行為完全不變（N/A / polaris-framework / main / identity=DP-NNN-Tn），維持純 stdlib python3。
- **`scripts/validate-refinement-json.sh` + `.claude/skills/references/refinement-artifact.md` + `scripts/render-refinement-md.sh`**（DP-269-T2，AC4 / AC-NEG1 / AC-NEG2）：新增 jira-only schema 規則——`source.type=jira` required `source.repo` + `source.base_branch`、`tasks[].jira_key` 可 string|null；`source.type=dp` 出現任一 jira-only 欄位以 `POLARIS_REFINEMENT_JIRA_ONLY_FIELD` fail-closed（比照 DP-228 jira-only 禁令，鬆綁不外洩到 dp 分支）。
- **`scripts/breakdown-emit-blocker-marker.sh`（new）+ `scripts/lib/evidence-producers.json` + `scripts/auto-pass-runner.sh` + `scripts/auto-pass-probe.sh`**（DP-269-T3，AC3）：新增 emitter 落 `validation_fail` / `missing_v_task` durable marker 到 `.polaris/evidence/`（比照 task-snapshot emitter 繞過 `no-direct-evidence-write`）；runner / probe 把該 marker 映射成可讀的 `blocked_by_gate_failure`（非「marker missing」）。
- **`.claude/skills/refinement/SKILL.md`**（DP-269-T4）：Phase 1/2 populate `source.repo`（company context 目錄名）與 `source.base_branch`（`{company}/polaris-config/{project}/handbook/config.yaml`，無對應 entry 時 fail-stop）。
- **`.claude/skills/breakdown/SKILL.md`**（DP-269-T5）：initial-create 段落記載 jira mode；確認 source-parity gate 對 dp / jira 對稱。

### Why

某次對 JIRA-Epic-backed source 跑 `/auto-pass`（2026-06-01）在 breakdown 階段 fail-closed：derive script 對所有 source 硬寫 `JIRA key | N/A` / `Repo: polaris-framework` / `Base branch: main`，而 `validate-task-md.sh` 對 `source_type=jira` 拒絕 N/A key，導致 JIRA-Epic-backed source 連可對應真實 key 的 task 都無法 materialize（DP-only fast path）。DP-269 補上 derive jira mode + schema 欄位 + blocker-marker emitter，讓 JIRA-Epic-backed 與 DP-backed source 共用同一條 auto-pass initial-create lane（呼應 `canonical-contract-governance.md` § Source Parity）。

### Verified

V1 verify-AC PASS（AC1 / AC2 / AC3 / AC4 / AC5 / AC-NEG1 / AC-NEG2）；derive selftest（jira / dp parity）、`validate-refinement-json` selftest、`breakdown-emit-blocker-marker` selftest 全綠。bundle PR #495（T1–T5 共用 `bundle_branch_alias: task/DP-269-bundle`），經 DP-270 修好的 framework-release lane 發版。

## [3.75.141] - 2026-06-02

### Fixed — DP-272 derive task_shape propagation（補完 DP-262 T5 宣告但未實作的 gap）

- **`scripts/derive-task-md-from-refinement-json.sh`**（DP-272-T1，AC1 / AC2 / AC3 / AC-NEG1 / AC8）：derive 在 T-task frontmatter（`task_kind` 後）注入 `task_shape`。取值來源唯一 canonical 為 `refinement.json` `planned_tasks[].task_shape`，依 normalize 後的 short task_id join 取得；不新增 `tasks[].task_shape` 第二來源。只注入 T-task；V-task 永不注入（AC2）。Passthrough only：derive 不驗 enum，單一 classifier 仍是 `validate-task-md.sh`（DP-262 AC7）；缺 entry / 缺值時省略該行，reader default = `implementation`。
- **`scripts/selftests/derive-task-md-from-refinement-json-selftest.sh`**（DP-272-T1）：新增 case 8-12 涵蓋 AC1 / AC2 / AC3 / AC-NEG1 / AC8（propagation、V-task 不注入、缺值省略、zero-shim byte-identical）。
- **`.claude/rules/mechanism-registry.md`**（DP-272-T1）：Runtime Annotation Registry 新增 `derive-task-shape-propagation` row（kind=script、runtime=portable、fallback=derive selftest、governance_role=governance）。

### Why

DP-262-T5 在 `breakdown` SKILL.md 與 T-task schema 文件化了 `task_shape` 會由 breakdown 在 task packaging 階段傳遞，但 `derive-task-md-from-refinement-json.sh`（DP-backed task 的 task.md 生成器）從未實作該 propagation——documented contract ≠ implemented contract。結果 DP-backed source 走 derive 產生的 task.md 永遠缺 `task_shape` frontmatter，audit / confirmation task 仍被下游 gate（breakdown-ready、delivery-completion）當 implementation 處理。DP-272 補上 derive 端的 `planned_tasks[]` join，使 task_shape carve-out 在 DP-backed source 真正生效。

### Verified

V1 verify-AC 5/5 AC PASS（AC1 / AC2 / AC3 / AC-NEG1 / AC8）；derive selftest 全綠（含新增 propagation cases）+ `check-script-manifest.sh` PASS；fix diff 僅 3 檔。workspace PR #498。

## [3.75.140] - 2026-06-02

### Added — DP-270 framework-release lane single-DP bundle support

- **`scripts/resolve-task-md-by-branch.sh`**（DP-270-T1）：新增 frontmatter `bundle_branch_alias` 比對。給定 branch `B`，除既有「Task branch == B」比對外，額外回傳所有 frontmatter `bundle_branch_alias == B` 的 task.md（bundle 情境下 multi-match 為合法、非錯誤）。
- **`scripts/framework-release-pr-lane.sh`**（DP-270-T1）：當 resolved task.md 共用同一 `bundle_branch_alias` 時群組成單一 bundle PR——對 bundle branch 單次 `gh pr view`、逐一驗證 member lineage（接受 `pr_head == bundle_branch_alias`）、plan 單一 merge、version gate 對 bundle branch。非 bundle 的單票 per-task 路徑零行為變更。
- **`scripts/framework-release-pr-lane-selftest.sh`**（DP-270-T1）：擴充 selftest fixture 涵蓋 bundle 群組、單一 merge plan、per-task regression、fail-closed。
- 直接成果：解阻 DP-269 的 bundle PR（PR #495 為 T1–T5 bundle）走標準 release lane，未來所有單-DP bundle 共用同一條 lane，不需 maintainer-orchestrated 特例。

## [3.75.139] - 2026-06-02

### Added — DP-262 audit/confirmation-only task_shape 識別與 lifecycle carve-out

- **`scripts/validate-task-md.sh`**（DP-262-T1）：task.md frontmatter 新增 `task_shape` enum（`implementation` / `audit` / `confirmation`，預設 `implementation`），並提供 `--field task_shape` 解析，讓下游 gate 能讀取 task 形態。
- **`scripts/validate-breakdown-ready.sh`**（DP-262-T2）：對 `task_shape: audit` / `confirmation` 的 task 套用 breakdown-ready carve-out，audit/confirmation-only task 不再被誤判為缺 implementation 交付物（mechanism `audit-confirmation-task-kind-carve-out`）。
- **`scripts/validate-refinement-lock-preflight.sh`** + selftest（DP-262-T4）：新增 refinement LOCK-time breakdown-ready preflight，於 LOCK 前驗證 task_shape 分類與 breakdown-ready 狀態一致；`scripts/manifest.json` 新增對應 row。
- **`.claude/skills/breakdown/SKILL.md` + `.claude/skills/references/task-md-schema-task.md`**（DP-262-T5）：breakdown 在 task packaging 階段傳遞 `task_shape`，並於 T-task schema 文件化該欄位；`.claude/rules/mechanism-registry.md` 新增 `audit-confirmation-task-kind-carve-out` Runtime Annotation Registry row。

### Fixed — DP-262 auto-pass terminal required-PR set 對 audit/confirmation task 的排除

- **`scripts/check-delivery-completion.sh`**（DP-262-T3）：delivery completion 對 `task_shape: audit` / `confirmation` 套用 carve-out，auto-pass terminal 的 required-PR set 不再要求 audit/confirmation-only task 產出 implementation PR；新增 `check-delivery-completion-task-shape-selftest.sh`。

### Why

audit-only 與 confirmation-only task（例：純驗證、純確認既有行為）原本被 breakdown-ready 與 delivery-completion gate 一律當成 implementation task，缺 code PR 時被誤判為未完成。DP-262 以 task.md frontmatter `task_shape` enum 顯式標記 task 形態，讓 breakdown-ready preflight、delivery completion、auto-pass terminal required-PR set 對 audit/confirmation 形態 deterministic 地套用 carve-out，避免靠 LLM 自律判斷。

## [3.75.138] - 2026-06-01

### Fixed — DP-264 derive-task-md stacked task base-branch 推導 form-agnostic

- **`scripts/derive-task-md-from-refinement-json.sh`**（DP-264-T1，AC1 / AC2 / AC-NEG1）：stacked task 的 dependency base-branch 推導改為 form-agnostic。`task_by_id` lookup 改用 `full_work_item_id(entry.id)` 正規化 key，使 `refinement.json` `tasks[].id` 不論 short form（`T1`）或 full form（`DP-NNN-T1`）都能用 full dependency id 命中真實 entry，取得真實 title slug 推導出 `| Base branch | task/DP-NNN-T1-{title-slug} |`，不再退回 `task/DP-NNN-T1-dp-nnn-t1` slug-of-full-id fallback。複用既有 `short_work_item_id` / `full_work_item_id` helper，與 primary task lookup 的 dual-form 處理同源。
- **`scripts/selftests/derive-task-md-stacked-base-branch-selftest.sh`**（DP-264-T1，AC1 / AC2 / AC-NEG1）：新增 stacked base-branch derivation selftest，short-form-id fixture 斷言 base branch 解析到真實 T1 title slug（非 slug fallback）、full-form regression、foreign-prefix external dep 維持排除三類 case。
- **`.claude/rules/mechanism-registry.md`**（DP-264-T1，AC3）：Runtime Annotation Registry 新增 `derive-task-md-stacked-base-branch` selftest row（kind=script、runtime=portable、governance_role=governance）。

### Why

stacked task（task B depends on task A）需推導 task A 的 branch 作為 task B 的 base branch（render 進 task.md，由 `engineering-branch-setup` cascade-rebase 消費）。`refinement.json` 的 `tasks[].id` 由 `create-design-plan.sh` / refinement 產生時是 short form（`T1`），但 dependency lookup 用 full id（`DP-NNN-T1`）查以 short id 為 key 的 dict → miss → base-branch 退回 `dp-nnn-t1` fallback，永不等於真實 dependency branch，導致 stacked task 全部卡在 cascade-rebase 到不存在的 branch。此 bug 在 DP-262 首個含 stacked task 的 DP 才浮現（既有 DP 的 task 皆 base=main 未觸發）；既有 fullform selftest 因 fixture 用 full-form id 剛好命中、且未斷言 base_branch 輸出，缺口存活。

### Verified

V1 verify-AC 6/6 AC PASS（AC1-4 + NEG1-2）；新 selftest + 兩支 derive regression selftest + `validate-mechanism-runtime-annotations.sh` 全 PASS；fix diff 僅 3 檔，不含任何 `refinement.json`（DP-262 / DP-242 refinement_hash 不受影響）。workspace PR #487。

## [3.75.137] - 2026-06-01

### Added — DP-265 framework embedded-python union annotation Python 3.9 portability fix

- **`scripts/validate-memory-write.sh` / `scripts/validate-script-categorization.sh`**（DP-265-T1）：為兩支內嵌 Python validator 加上 `from __future__ import annotations`，讓 `X | None` union annotation 在 host Python 3.9 下不再 `TypeError: unsupported operand type(s) for |`（governed harness 以 `bash -lc` 選到 host python <3.10 時不再 crash）。
- **`scripts/selftests/python-union-annotation-py39-portability-selftest.sh`**（DP-265-T1）：新增 portability selftest，斷言內嵌 Python 使用 PEP 604 union 時必須帶 `from __future__ import annotations`。
- **`.claude/rules/mechanism-registry.md`**（DP-265-T1）：新增 `python-union-annotation-py39-portability` Runtime Annotation Registry row。

### Fixed — DP-267 governed-script-tests release gate stale full-source-completion-invariant selftest assertion

- **`scripts/selftests/auto-pass-full-source-completion-invariant-selftest.sh`**（DP-267-T1）：從 `required_sources` 陣列移除 stale 的 `scripts/compile-runtime-instructions.sh` 斷言。其餘 source 斷言、4 個 generated target 斷言、negative anchor、skill-routing、manifest 自我登錄、末尾 `--check` render-sync 全部保留不動；governed-script-tests release gate 達成 36/36 全綠。

### Why

DP-265 與 DP-267 為一組 stacked cross-DP fix：DP-267 的 governed-script-tests 36/36 需要 DP-265 的 py3.9 portability fix 先進 base（否則 host python <3.10 先 crash 遮蔽後段中止），而 DP-265 的 release gate 又需要 DP-267 的 stale 斷言移除。透過 stacked delivery（DP-267 base 疊在 DP-265 上）打破對稱死結，於同一個 merge train 一次釋出版本。

### Verified

DP-265 V1 verify-AC PASS、DP-267 V1 dogfood verify-AC 5/5 AC PASS（AC1/AC2/AC-NEG1/AC-NEG2/AC-NEG3），governed-script-tests 36/36 全綠不依賴 bypass env；workspace PR #488（DP-265）+ #489（DP-267），bundle release。

## [3.75.136] - 2026-05-29

### Added — DP-261 `check-runtime-cache-residue.sh` 改為 source-scoped filename matching

- **`scripts/check-runtime-cache-residue.sh`**（DP-261-T1）：從 workspace-wide residue 掃描改為 source-scoped filename matching，只 flag 屬於當前 source container 的 transient draft；不再讓並行 source container 的 residue 互擋 closeout chain。
- **`scripts/selftests/check-runtime-cache-residue-selftest.sh`**（DP-261-T1）：擴充 3 個 case，涵蓋 source-scoped filter 行為（自身 source residue 仍 flag、他 source residue 不再誤 flag、空 cache 維持 PASS）。
- **`scripts/lib/script-categorization-exception.txt`**（DP-261-T1 revision）：新增 `scripts/check-runtime-cache-residue.sh` 為 `refinement` owner 的 dynamic-invoke exception。原因：該 script 被 `scripts/refinement-handoff-gate.sh`（root-contract caller）靜態呼叫，但 `script-ownership-audit.sh` 的 consumer scan 只計 `.claude/skills/**/SKILL.md` reference，不偵測 cross-script callers，因此被誤分類為 `skill_local`。使用 DP-240 D26 設計的 designed bypass 機制，避免將真實的 root-contract dependency 誤遷移到 skill-local 目錄。

### Why

並行 source container（多張同時走 main-chain 的 DP / Epic）會在 runtime cache 留下 transient draft；舊版 residue 掃描為 workspace-wide，會把他 source 的合法 draft 視為當前 source 的 residue，導致 closeout chain 被無關 source 的 cache 擋住。DP-261 把 residue 判定改為 source-scoped filename matching，從根本解掉「並行 source 互擋 closeout」的 false positive，不需要每次 closeout 都手動清 cache。

### Verified

V1 verify-AC 9/9 AC PASS（含 source-scoped filter + selftest 3 case 擴充）；workspace PR #480。

## [3.75.135] - 2026-05-29

### Added — DP-260 refinement.json `tasks[].id` canonical-form contract + derive accepts short and full form

- **`scripts/derive-task-md-from-refinement-json.sh`**（DP-260-T1，AC1 / AC2 / AC3 / AC4 / AC-NEG1）：entry-match 改為先嘗試 full form（例：`DP-260-T1`），若無命中且 CLI 傳入的 source prefix 與 `source.id` 相同，再 fallback 比對 short tail（例：`T1`）。短/全形產出 byte-identical task.md；不合 canonical pattern 的 `--task-id` fail-stop 並提示 `DP-NNN-Tn`。
- **`scripts/validate-refinement-json.sh`**（DP-260-T1，AC5 / AC-NEG2 / AC-NEG3）：在 `tasks[]` schema 檢查補一條 id format gate；只接受 short form `T?[0-9]+[a-z]?` 或 full form `<SOURCE-PREFIX>-T?[0-9]+[a-z]?`，且 full form 的 source prefix 必須等於 `source.id`。違反時 exit 2 + `POLARIS_REFINEMENT_TASK_ID_INVALID:{reason}`。
- **新 selftest**：`scripts/selftests/derive-task-md-short-id-selftest.sh`（兩 fixture 比對 short vs full form 產出位元一致；V-mode 也涵蓋）、`scripts/selftests/validate-refinement-json-task-id-format-selftest.sh`（6 case：valid short / valid full / invalid foreign prefix / invalid free-form / invalid empty / invalid extra suffix）。
- **擴充 selftest**：`scripts/selftests/derive-task-md-from-refinement-json-selftest.sh` 新增 AC-NEG1 case，驗證短 form `--task-id T1` 必須 fail-stop 並含 `canonical pattern` hint。
- **`.claude/skills/references/refinement-artifact.md`** § Strong-Bound Machine Contract：說明 dual-form `tasks[].id` 契約、`POLARIS_REFINEMENT_TASK_ID_INVALID` marker 與 derive CLI 行為。

### Why

DP-242 與後續 refinement-owned source 在 LOCK 後跑 `/auto-pass {KEY}` 時，derive script 只接受 full form `<source>-Tn` 但 historic refinement.json 仍用 short form `Tn`，造成 main-chain 在 breakdown stage fail-stop。改 derive script 與 validator 對齊既有 `tasks[].dependencies[]` 同型支援 short / full form，DP-260 之後 short/full form refinement.json 都能直接被 main chain 消費，不需要逐張 DP 手動 retro-fit。

### Verified

Verify-AC 9/9 AC PASS（含 AC4 用真實 DP-252 refinement.json 跑 derive、AC-NEG2 對 7 張 sibling DP 跑 regression 確認 byte-diff=0）；report 路徑：`docs-manager/src/content/docs/specs/design-plans/DP-260-refinement-json-task-id-canonical-form-contract-derive-accepts-short-and-full-form/verification/V1/verify-report.md`。

## [3.75.134] - 2026-05-29

### Added — DP-240 framework workspace self-development handbook + constitutional skill-first amendment

- **憲法層**（`.claude/instructions/core/bootstrap.md`）新增 3 個 H2 section：`## Skill-First Routing`、`## Markdown Authoring Contract`、`## Tool Missing Discipline`。4 個 generated runtime target（`CLAUDE.md` / `AGENTS.md` / `.codex/AGENTS.md` / `.github/copilot-instructions.md`）同步含相同條文（DP-240-T1，AC1 / AC15 / AC16）。
- **bootstrap source alignment**（`scripts/compile-runtime-instructions.sh`）：`emit_core` 改為從 `.claude/instructions/core/bootstrap.md` 讀取作為 single source（取代原本 hardcoded heredoc），讓 bootstrap.md 成為憲法層真實 SoT（DP-240-T1）。
- **新增 framework self-development handbook**（`.claude/rules/handbook/framework/`，DP-240-T2）：index.md routing pointer + 6 個 topic 子檔（cross-llm-parity / script-governance / development-standards / dependency-management / configuration-surface / contract-design），由 `.claude/rules/workspace-self-development.md` route 進入（AC2 / AC12 / AC13 / AC17 / AC18）。
- **Universal handbook 補強**：`working-habits.md` 新增 Principal Agreement = GO Signal 條文（DP-240-T10，AC14）；新增 `.claude/rules/handbook/implementation-language-choice.md` 規範 sh / py / mjs 語言取捨 + 過度工程禁令（DP-240-T12，AC19，R7 amendment 對齊 sibling H1-first 慣例）。

### Added — multi-language script governance + validator gates（DP-240-T3 / T4 / T5 / T9）

- **`scripts/validate-script-header-comment.sh`**（T3，AC3 / AC7）：`.sh` / `.py` / `.mjs` / `.ts` 新增或修改時必須在前 20 行含 Purpose 註解；支援 `--mode diff` blocking + `--mode audit` legacy debt report。
- **`scripts/validate-script-categorization.sh`**（T4，AC4 / AC7）：依 callsite 分布判定 skill-only / framework-wide / hook / owning-DP 位置；支援 `--mode diff` blocking + `--mode audit`。
- **Aggregate wiring**（T5，AC8）：`mise run script-audit` + `scripts/command-catalog.json` runtime.script-audit.implementation + `scripts/framework-release-pr-lane.sh` + `scripts/check-framework-pr-gate.sh` 都消費同一 aggregate；`mechanism-registry.md` 補登 4 個 entry。
- **`scripts/validate-mise-dependency-change.sh`**（T9，AC11）：`mise.toml` diff 需要 PR body 引用 `DP-NNN`，模糊文字（`DP TBD` / `see Polaris DP`）不接受。
- **`scripts/audit-legacy-script-governance.sh`**（T7）：legacy script governance debt audit report producer，產出 artifact 列既有 100+ script 的 header / categorization / reuse / fail-stop missing 狀態。

### Added — gate authority for root scripts + handbook routing（DP-240-T6 / T8）

- **`scripts/gates/gate-pr-body-template.sh`**（T6，AC9）：新增 root `scripts/*.sh|*.py|*.mjs|*.ts` 的 PR body 必須含 `Script reuse justification` 段落；空白或模糊文字（「see existing X」「reuse later」）會被擋下。
- **`scripts/validate-framework-handbook-routing.sh`**（T8，AC10）：framework-owned path / product repo path / 混合命中三類由 deterministic gate 標示，避免 framework handbook 被 product repo path 誤用。

### Added — framework configuration surface governance（DP-240-T11）

- **`.claude/rules/handbook/framework/configuration-surface.md`**（D25，AC17）：`workspace-config.yaml` / `.claude/instructions/manifest.yaml` 與 `mise.toml` 同層治理；新增 / 修改視為 framework contract change，PR body 必須引用 owning DP。carve-out 明列 `<company>/polaris-config/**` / `_template/**`。

### Fixed — compile script duplicate emission

- **`scripts/compile-runtime-instructions.sh`**：移除 `emit_decision_priority_principle()` inline function 與 4 個 callsites。DP-259-T1 引入 inline function 時 emit_core 為 hardcoded heredoc，無 duplicate；DP-240-T1 把 emit_core 改成讀 bootstrap.md SoT（bootstrap.md 此時已含 DP-259 加入的 Decision Priority Principle section），inline function 變 redundant 產生 duplicate。本 release 將 inline function 移除，由 bootstrap.md 作 single source。

### Verification

- **V1 verify-AC PASS 21/21**（含 AC-NEG1 / AC-NEG2，HEAD `4c38913`）：4-target byte-equivalent diff、validator selftest、benchmark wall-clock < 1.2s、bootstrap source canary、aggregate wiring、framework handbook 結構斷言、handbook H1-first convention assert（AC19 經 R7 amendment 對齊 sibling 慣例），全部 PASS。verify-report.md 在 `verification/V1/`。
- **Bundle integration**：12 個 task PR（#455 #457 #461 #463 #464 #465 #466 #467 #470 #471 #472 #473）在 bundle branch 依 stack order merge（T1/T2/T9/T10/T12 root → T3/T5/T8/T11 layer 1 → T4/T6 layer 2 → T7 layer 3）。

## [3.75.133] - 2026-05-29

### Added — DP-259 decision priority constitution + local verification / self-authored prose handbook

- `.claude/instructions/core/bootstrap.md` 新增 `## Decision Priority Principle` H2 section（憲法層）：三原則排序（功能完整 > 易讀 > 效能/簡潔，逐項遞減）、trade-off 從尾項放棄且第 1 項絕不放棄、選項出現時優先依本原則直接決定且不得列契約已排除的選項。
- `scripts/compile-runtime-instructions.sh` 新增 `emit_decision_priority_principle()` heredoc 並 wire 進 `emit_claude` / `emit_agents` / `emit_codex` / `emit_copilot`，CLAUDE.md / AGENTS.md / .codex/AGENTS.md / .github/copilot-instructions.md 4 個 generated target 同步含同條文；`.codex/.generated/rules-manifest.txt` 與 `.github/.generated/copilot-rules-manifest.txt` sha 更新。
- 新增 `.claude/rules/handbook/local-verification-first.md`（universal handbook）：所有程式碼 push remote 前須盡可能 local 驗證完整；列出期望 local 驗證項目、Why、carve-out。
- 新增 `.claude/rules/handbook/self-authored-prose-is-not-contract.md`（universal handbook）：orchestrator self-authored prose 是 draft assertion 不是契約延伸；Writer 端寫入前過 `forbidden_actions` / `consent_excludes` / `dispatch_boundary` gate，Reader 端 resume session 對每個 enumerated option re-validate；針對 DP-240 5/29 resume incident 直接收斂。

## [3.75.132] - 2026-05-28

### Fixed — DP-258 auto-pass migration completion retrofit

- DP-258 retroactively ratifies bypassed-flow commits `8f33e23` and `92a0412` as
  auto-pass migration completion: probe loop counter dual-shape handling,
  refinement-inbox `consumed: true` filtering, derive `verify_command` priority,
  and full-form `depends_on` emission.
- Added focused selftests for those four behaviors so the already-landed script
  fixes are now covered by deterministic regression evidence instead of relying
  on the original dirty script path.

## [3.75.131] - 2026-05-28

### Fixed — DP-255 skill routing precision + framework script UTF-8 safety

- `.claude/rules/skill-routing.md`：`review-pr` trigger 改為主語 anchoring
  （主語省略或主語=self），`check-pr-approvals` trigger 補入常見催 review phrasing
  （請同仁/大家 review、找人 review、請\[人名\]幫我 review、催 PR）。Anti-Patterns
  新增「中文『請\[主語\]幫我 X』」主語盲點規則。
- `.claude/skills/review-pr/SKILL.md` 與 `.claude/skills/check-pr-approvals/SKILL.md`
  frontmatter description 同步反映上述 boundary。
- `.claude/skills/check-pr-approvals/scripts/rebase-pr-branch.sh` 與
  `scripts/polaris-viewer.sh` 修正 `$VAR<中文全形標點>` 寫法，改為
  `${VAR}<標點>`，消除 bash `set -u` 在 UTF-8 多 byte 邊界觸發 `unbound variable`
  crash 的根源。

### Added — DP-255 deterministic gate

- 新增 `scripts/lint-bash-variable-utf8-boundary.sh` + selftest，掃 `.claude/**/*.sh`
  與 `scripts/**/*.sh` 內 `$VAR<非 ASCII byte>` pattern，違反輸出
  `POLARIS_BASH_VAR_UTF8_BOUNDARY` token、exit 2。
- 新增 `scripts/selftests/skill-routing-subject-aware-selftest.sh` + utterance
  fixture（18 條 case 涵蓋 AC1 / AC2 / AC-NEG3）。
- `scripts/check-framework-pr-gate.sh` 加入 W7 lint gate；
  `.claude/rules/mechanism-registry.md` Runtime Annotation Registry 新增
  `bash-var-utf8-boundary-lint` 與 `skill-routing-subject-aware` 兩 row。

## [3.75.130] - 2026-05-28

### Changed — DP-253 auto-pass evidence preview publication contract

- 明確化 PR / JIRA 佐證發布對照表 contract，欄位固定包含情境、嵌入預覽、驗證結果、影片或原始檔連結。
- JIRA 圖片預覽要求使用 attachment filename wiki markup，例如 `!filename.png|thumbnail!`；影片維持 link + screenshot / thumbnail / GIF fallback，不宣稱 raw video inline 播放。
- 補齊 engineering、verify-AC、auto-pass 邊界文字：`auto-pass` complete 必須能看到 non-draft PR 與遠端可見 evidence marker / URL，但不成為 PR / JIRA evidence writer。

## [3.75.129] - 2026-05-28

### Fixed — DP-254 engineering completion gate review readiness

- `check-delivery-completion.sh` 現在把 GitHub shared PR state 的 `blocked_review`
  視為 post-delivery review readiness，不再阻擋 engineering closeout 到 Code Review。
- 保留 draft PR、head SHA mismatch、缺 evidence、缺 assignee、failing CI、stale base、
  merge conflict 與 unresolved review thread disposition 等 hard blockers。
- 更新 engineering delivery flow 與 deterministic hooks registry，讓跨 runtime 對
  engineering completion 與 review approval 的邊界一致。

## [3.75.128] - 2026-05-28

### Changed — DP-237 auto-pass prompt-surface slimming + runtime runner extraction

五項 task，打包為一個 aggregate bundle PR：

- **T1 — Runner 契約 + shadow fixture 對齊**：新增 `scripts/auto-pass-runner.sh`
  (352 行) 作為 deterministic aggregator，覆蓋 source / breakdown / engineering /
  verify-AC / blocked / resume / loop-cap / JIRA consent stage 的 next_action 推導；
  新增 `selftests/auto-pass-runner-selftest.sh` (382 行)、`auto-pass-runner-probe-parity-selftest.sh`
  (191 行)、`validate-auto-pass-report-selftest.sh` (242 行)；擴充 `auto-pass-probe-selftest.sh`
  覆蓋 machine-field 穩定性與 prose-decoy AC-NEG3 negative case。
- **T2 — 精簡 SKILL + reference 去重**：`.claude/skills/auto-pass/SKILL.md` 從 464 行
  trim 到 185 行 (-60%)，移除 ledger schema、report schema、consent enum、
  friction trigger table 等 implementation detail，改為 thin runner-first contract
  指向 `.claude/skills/references/auto-pass-*.md` canonical sources；新增
  `selftests/auto-pass-thin-skill-selftest.sh` 鎖定行數預算與 reference pointer 完整性。
- **T3 — Runner-first 執行流程切換**：更新 `auto-pass-execution-flow.md`、
  `auto-pass-proof-of-work.md`、`worktree-dispatch-paths.md` 與 SKILL.md 末段，
  把實際呼叫路徑改為 `scripts/auto-pass-runner.sh` 為 single entry point；
  runner-selftest 新增 172 行覆蓋執行流程 fixture。
- **T4 — Parity / negative selftest + docs health 收尾**：`auto-pass-thin-skill-selftest.sh`
  擴充至 185 行，新增 negative case 阻擋 runner script 內出現 mutation helper
  (sync-to-polaris / mark-spec-implemented / polaris-pr-create)，保持 runner 為
  pure aggregator；`references/INDEX.md` 加上 `scripts/auto-pass-runner.sh` 指引列
  (AC5) 讓 downstream agent 從 INDEX 即可定位 runner script。
- **T5 — Skill-size lint + mechanism-registry 登錄**：新增 `scripts/lint-skill-size.sh`
  (104 行) 作為 skill SKILL.md 行數預算 deterministic gate；新增 `selftests/lint-skill-size-selftest.sh`
  (195 行) 覆蓋 budget / fail / skip 邊界；`mechanism-registry.md` 登錄 `skill-size-policy`
  runtime annotation 與 graduation_milestone=M2，把預算強制納入 framework health check。

額外 bundle 修補：

- **DP-246 race-recovery carry-forward**：T2 trim 範圍涵蓋 DP-237 設計後才併入 SKILL.md
  的 DP-246 Counter Race-Recovery / Counter Increment Contract 段落。為避免 thin SKILL
  丟失這兩段 operational guidance，bundle commit `bdfd71a` 把它們補回到
  `references/auto-pass-execution-flow.md § Loop Caps` 之後作為 canonical doc 來源。

## [3.75.127] - 2026-05-28

### Fixed — DP-246 auto-pass finalize-tail framework hotfix bundle

四項 hotfix，打包為一個 aggregate bundle PR：

- **T1 — escalations producer registration**：補全 `scripts/lib/evidence-producers.json` 中
  缺漏的 escalations producer entry，並新增 `selftests/escalations-producer-registration-selftest.sh`
  確保 registry 完整性。同步更新 `mechanism-registry.md` 新增 `counter-idempotency` 與
  `counter-race-recovery` 兩條 runtime annotation。
- **T2 — auto-pass increment counter idempotency**：`scripts/auto-pass-increment-counter.sh`
  加入 idempotency guard，防止同一 `{dp_id}/{run_id}` 組合被多次計數；
  新增 `selftests/auto-pass-increment-counter-idempotency-selftest.sh`（224 行）覆蓋邊界情境。
- **T3 — counter race-recovery helper**：新增 `scripts/auto-pass-counter-race-recovery.sh`
  提供 orphan counter 偵測與清理機制；新增 `selftests/auto-pass-counter-race-recovery-selftest.sh`
  （348 行）全面覆蓋競態恢復情境。
- **T4 — polaris-pr-create.sh Bash 3.2 compatibility**：修正 macOS Bash 3.2 下 `readarray`
  不可用的問題，改用 `while read` 替代；新增 `selftests/polaris-pr-create-bash3-gh-args-selftest.sh`
  驗證 gh args 在 Bash 3.2 環境正確組合。

## [3.75.126] - 2026-05-27

### Fixed — DP-241 Slack URL boundary clarification

把 `.claude/rules/handbook/quality-standards.md` 第 8 點「Slack URL 後必須換行」精確化為
「Slack URL 邊界必須明確」：明寫單行 `\n` 不夠用、列出 blank line 與 `<URL>` 角括號兩種
有效做法，並附 percent-encode 範例（`2427%E4%BE%9D%E5%AE%98%E6%96%B9`）作為記憶錨點，避免
Slack auto-link parser 把後續中文吞進 URL。

## [3.75.125] - 2026-05-27

### Fixed — DP-235 full-source completion invariant

新增 runtime constitution、auto-pass 與 routing guard，明確禁止把單一 task、
blocker hotfix、PR、version tag 或 framework-release closeout 誤判為 DP / source
完整完成；並將 invariant 納入 generated runtime targets 與 selftest / manifest。

## [3.75.124] - 2026-05-27

### Fixed — DP-231 task_kind handoff fixed point

讓 `derive-task-md-from-refinement-json.sh` 對 T / V task.md frontmatter
deterministically 產出 `task_kind`，避免 framework-release closeout 的
local-extension completion gate 在缺 schema dispatcher key 時 fail-stop。

## [3.75.123] - 2026-05-27

### Fixed — DP-231 template-safe dependency examples

將 refinement artifact dependency contract 中的公司 ticket 範例改為 synthetic key，
避免 template leak gate 在 framework release tail 擋下 DP-231 handoff 修正。

## [3.75.122] - 2026-05-27

### Fixed — DP-231 auto-pass 主鏈 handoff 固定點

修正 refinement → breakdown → engineering handoff 的 deterministic gap：
`derive-task-md-from-refinement-json.sh` 會產出合法 V task schema 與 implementation
task list，`validate-refinement-json.sh` 會阻擋裸 DP/JIRA predecessor 混入
`tasks[].dependencies`，並補上 auto-pass / engineering worktree ownership contract
與 regression selftests。

## [3.75.121] - 2026-05-25

### Fixed — DP-233 ci-local 多行 husky hook mirror

修正 `ci-contract-discover.sh` 對 `.husky/pre-commit` 多行 shell block 的解析，
讓 ci-local mirror 以完整 hook body 執行並通過 `bash -n`；新增 discovery selftest，
並把 release metadata 納入 framework release gate。

## [3.75.120] - 2026-05-25

### Fixed — DP-230 template leak fixture cleanup

將 DP-230 leak-scan selftest 與註解中的公司實名範例改成 synthetic fixture，
讓 template sync 的 material leak gate 可以通過；本版延續 v3.75.119 的 DP-230
deterministic chain hardening aggregate release。

## [3.75.119] - 2026-05-25

### Changed — DP-230 deterministic chain hardening aggregate release

補齊 refinement → breakdown → engineering → verify-AC 主鏈的 deterministic guard：
新增 DP-230 umbrella regression entrypoint、強化 artifact writer / PR identity /
verify-AC evidence / runtime response language / skill workflow boundary 等 selftest
覆蓋，並修正 aggregate release PR identity 與 engineering branch setup 的相容路徑。

## [3.75.118] - 2026-05-24

### Changed — DP-229 refinement contract hardening

將 refinement handoff 升級為 strong-bound machine contract：新增 `refinement.json`
schema_version / tasks / adversarial_pass enforcement、derived `refinement.md` renderer 與
hand-edit detector、source resolver `source_kind` 通用化，並 sunset active `/bug-rca`
skill routing surface。

### Fixed — auto-pass-auto-friction selftest case 4 baseline regression

D27 source resolver `source_kind` 通用化（延伸自 v3.75.117 DP-228-T17 release tail v2）
後，非 DP key（例：`ZZ-9999`）由 resolver 回 `BLOCKED` 而非 `UNKNOWN`，
`scripts/selftests/auto-pass-auto-friction-selftest.sh` case 4
（auto-pass-probe UNKNOWN → deterministic_gap friction）在 v3.75.117 變成
11 passed / 1 failed 的 silent baseline regression（release tail v2 自己升版時跳過了
governed test gate）。本版改用 `engineering` stage 缺 `--head-sha` 的 deterministic
UNKNOWN 觸發路徑作 fixture，selftest 回到 12 passed / 0 failed。

## [3.75.117] - 2026-05-23

### Changed — DP-228 refinement flow parity + specs-bound write contract（aggregate release：T1–T17）

讓 Polaris 主鏈（`/auto-pass` + `refinement` + `breakdown` + `engineering` + `verify-AC`）的 refinement-owned source 抽象同時涵蓋 framework workspace 的 DP-backed source（`design-plans/DP-NNN-*/`）與產品 repo 的 JIRA Epic-backed source（`companies/{company}/{EPIC}/`），共用同一條 producer / probe / ledger / amendment / migration / validator / hook 路徑。新增 spec-source resolver、source parity gate 與 allowlist；補齊 producer-env consent、auto-pass probe / ledger / resume validator；交付 Epic 三支 migration script；rules / skills / references 全面 source-neutral；以及 release tail（manifest、VERSION、CHANGELOG）。

#### T1 — spec source resolver

- `scripts/spec-source-resolver.sh` + `scripts/selftests/spec-source-resolver-selftest.sh`：新增 deterministic resolver，從 `{KEY}` 或 `--source-container` 解析 DP-backed 或 JIRA Epic-backed source；輸出 `source_id`、`source_type`、`source_container`、`refinement_artifact` 等欄位，供其他 helper 共用。

#### T2 — hook producer-env consent

- `.claude/hooks/no-direct-evidence-write.sh`：補上 source-neutral evidence write contract，對 DP-backed 與 JIRA Epic-backed source path 同步 enforce token + glob + consent envelope。
- `scripts/selftests/validate-specs-bound-write-contract-selftest.sh`：補上 JIRA Epic source consent / negative case 覆蓋。

#### T3 — producer registry parity

- `scripts/lib/evidence-producers.json`：補齊 `companies/*/*/` source parity entries 與 D2 transport metadata 分流，使 ledger / resume / refinement-inbox writer 對 JIRA Epic-backed 與 DP-backed source 對稱。

#### T4 — spec primary doc authoring

- `scripts/validate-spec-primary-doc-authoring.sh` + `scripts/selftests/validate-spec-primary-doc-authoring-selftest.sh`：把 `validate-dp-plan-authoring.sh` 拆出 source-neutral primary doc authoring gate；原 DP-only validator 改為 thin wrapper 並指向新 gate。
- `scripts/validate-dp-plan-authoring.sh` + selftest：精簡為 DP-flavor adapter，呼叫新的 source-neutral gate。

#### T5 — spec source parity gate（framework PR）

- `scripts/validate-spec-source-parity.sh` + `scripts/selftests/validate-spec-source-parity-selftest.sh`：新增 framework PR gate，掃 producer registry 與 source-neutral surface（rules / skills / references），對 `design-plans/DP-*/` 與 `companies/*/*/` glob 強制對稱；exception 必須登記在 `scripts/lib/spec-source-parity-allowlist.txt`（`[registry]` / `[auto-pass-prose]`）。
- `scripts/check-framework-pr-gate.sh`：framework PR gate 流程整合 source parity 檢查。

#### T6 — auto-pass probe（source-neutral）

- `scripts/auto-pass-probe.sh` + `scripts/selftests/auto-pass-probe-selftest.sh`：probe 對 DP-backed 與 JIRA Epic-backed source 對稱判定 `source_state`、`refinement_artifact_present`、`task_md_present`，並輸出 source-neutral 欄位給 routing matrix。

#### T7 — auto-pass ledger validator（source-neutral）

- `scripts/validate-auto-pass-ledger.sh` + `scripts/selftests/validate-auto-pass-ledger-selftest.sh`：ledger contract 改為 source-neutral，validator 不再對 source type 做特殊豁免；JIRA Epic-backed source 的 `jira_status_transition` consent 以 additional 契約形式存在。

#### T8 — auto-pass resume report parity

- `scripts/validate-auto-pass-resume.sh` + `scripts/validate-auto-pass-report.sh` 與對應 selftest：resume / report contract 同步 source-neutral，對兩種 source type 套用同一條 `pause.kind` / `stage_events` 規約。

#### T9 — auto-pass + refinement SKILL.md source-neutral

- `.claude/skills/auto-pass/SKILL.md`、`.claude/skills/refinement/SKILL.md`、`.claude/skills/references/auto-pass-execution-flow.md`、`.claude/skills/references/auto-pass-ledger.md`：orchestrator + amendment + ledger 路徑改為 source-neutral，不再以 `DP-NNN` 為 source ID 唯一格式；route 同時接受 DP 與 JIRA Epic key。

#### T10 — producer skill SKILL.md source-neutral

- `.claude/skills/breakdown/SKILL.md`、`.claude/skills/bug-triage/SKILL.md`、`.claude/skills/learning/SKILL.md`、`.claude/skills/verify-AC/SKILL.md`：producer 走 source-neutral writer path；`learning` skill 補上 JIRA Epic-backed source 的 inbox / handoff 路徑。

#### T11 — Epic frontmatter migration

- `scripts/migrate-epic-frontmatter.sh` + `scripts/selftests/migrate-epic-frontmatter-selftest.sh`：把 legacy JIRA Epic 的 `docs-manager` page frontmatter 一次性遷移到 source-neutral 規約（`source_type` / `source_id` / `source_container` 對齊 DP-backed source）。

#### T12 — Epic refinement handoff migration

- `scripts/migrate-epic-refinement-handoff.sh` + selftest：遷移既有 Epic 的 refinement handoff artifact（`refinement.md` / `refinement.json` / `refinement-inbox/`）到 source-neutral container layout。

#### T13 — PM Epic mapping migration

- `scripts/migrate-pm-epic-mapping.sh` + selftest：遷移 PM ↔ Epic 對應表，補齊 Epic-backed source 在 producer registry / routing matrix 的對應條目。

#### T14 — refinement inbox record validator

- `scripts/validate-refinement-inbox-record.sh` + `scripts/selftests/validate-refinement-inbox-record-selftest.sh`：對 refinement-inbox record 套用 source-neutral schema check（`source_type` / `source_id` / `consumed_by_amendment` 欄位），對兩種 source type 對稱 enforce。

#### T15 — refinement source-mode reference rename

- `.claude/skills/references/refinement-dp-source-mode.md` → `.claude/skills/references/refinement-source-mode.md`：reference 改名為 source-neutral；同步更新 `.claude/skills/refinement/SKILL.md`、`.claude/skills/learning/SKILL.md`、`.claude/skills/references/INDEX.md`、`.claude/skills/references/refinement-research-container.md`、`.claude/hooks/pre-push-quality-gate.sh` 的引用。

#### T16 — rules / skill-routing source-neutral

- `.claude/rules/skill-routing.md`：full development workflow + source-state matrix 改為 source-neutral，trigger / route 同時涵蓋 `DP-NNN` 與 JIRA Epic key（如 `GT-NNN` / `KB2CW-NNN`）；`framework-release` 重述為 framework workspace 專屬 terminal tail。
- `.claude/rules/canonical-contract-governance.md`：新增 § Source Parity 段，宣告 DP-backed 與 JIRA Epic-backed source 共用同一抽象與 producer / ledger / validator / hooks / reference 對稱契約；保留 `framework-release` 為 framework workspace 專屬 terminal carve-out。
- `scripts/selftests/auto-pass-routing-selftest.sh`：補上 JIRA Epic-backed source 進入 main-chain 的路徑與 DP-only routing prose 退場 case。

#### T17 — release tail（bundle assembly + template-leak recurrence prevention）

- `scripts/manifest.json`：登記所有 DP-228 新 script / selftest（spec-source-resolver、validate-spec-primary-doc-authoring、validate-spec-source-parity、migrate-epic-frontmatter、migrate-epic-refinement-handoff、migrate-pm-epic-mapping、validate-refinement-inbox-record-selftest，與對應 selftest entries）。
- `scripts/lib/spec-source-parity-allowlist.txt`：新增 source parity gate 的 allowlist 來源檔。
- `VERSION` / `CHANGELOG.md`：release tail（本條目）。

##### Template-leak recurrence prevention（hotfix on T17）

- `scripts/gates/gate-template-leaks.sh`（新）：把 `scripts/scan-template-leaks.sh --source workspace --blocking` 包成 PR-time / push-time gate，讓 live company slug / JIRA prefix / Slack ID / internal URL 在 workspace PR 開出前就被攔下，不再只在 `sync-to-polaris.sh` post-merge 才檢查。
- `scripts/install-copilot-hooks.sh`：`.git/hooks/pre-push` 新增 `gate-template-leaks.sh` 呼叫（推遠端前 fail-stop）。
- `scripts/check-framework-pr-gate.sh`：framework PR gate aggregator 新增 W6 `template leaks (workspace)`，與既有 W1-W5 同列；selftest 同步補 W5 / W6 stub。
- `scripts/selftests/gate-template-leaks-selftest.sh`（新）：clean workspace exit 0、planted leak exit non-zero with BLOCKED marker；登記 `core` / `release` 兩個 governed test profile。
- `scripts/selftests/migrate-pm-epic-mapping-selftest.sh`、`auto-pass-probe-selftest.sh`、`spec-source-resolver-selftest.sh`、`validate-auto-pass-ledger-selftest.sh`、`validate-auto-pass-resume-selftest.sh`、`validate-refinement-inbox-record-selftest.sh`、`auto-pass-report-selftest.sh`、`auto-pass-routing-selftest.sh`、`spec-source-resolver.sh`：fixture 內的 live JIRA prefixes 與 live company slug 全部改為 generic placeholder（`EXAMPLE-NNN` / `EXB2C-NNN` / `exampleco`），符合 `rules/framework-iteration.md` § Template-Facing Examples Must Be Generic。
- `scripts/selftests/dp218-graduation-anchors-selftest.sh`：移除指向 company-scoped rule path 的 anchor check（17/17 portable anchors found；1 company-scoped 跳過）。
- Root cause：`scan-template-leaks.sh` 只在 `sync-to-polaris.sh` 內部被呼叫（post-merge），workspace PR / push 階段沒有 deterministic gate；前一版 release（v3.75.116 → v3.75.117）因此在 sync 時被 145 hit 擋下，需要 hard-reset main 並重發 PR。本 hotfix 把 leak scan 加到 push-time 與 PR-time，閉合 recurrence path。

覆蓋 AC1（spec source parity gate）、AC3（producer registry 對稱）、AC5（framework PR gate 整合）、AC7（spec primary doc authoring source-neutral）、AC9（auto-pass routing / ledger / resume / report source-neutral）、AC11–13（Epic migration scripts）、AC14（refinement inbox source-neutral）、AC15（refinement source-mode rename）、AC16（rules / routing source-neutral）、AC-NEG1-3（DP-only producer / prose / route fail-stop）、AC-NF1-2（allowlist + transitional carve-out 機制）。

## [3.75.116] - 2026-05-22

### Changed — DP-226 auto-pass producer trust + validator lifecycle awareness

讓 `/auto-pass` orchestrator 與 `breakdown` initial-create lane 用 deterministic producer writer 寫 ledger / resume JSON / 初始 task.md，不再依賴臨場 Bash heredoc workaround；並讓 `validate-task-md.sh` Verify Command static smoke 對齊 task `create` lifecycle，使 self-hosting create-script 引用通過驗證。對應 DP-225 friction_log[] 前 3 條結構性 gap。

- `.claude/hooks/no-direct-evidence-write.sh`：補上 auto-pass ledger / resume JSON protected globs，並新增 `POLARIS_PRODUCER` token 解析、token-first producer lookup、path glob enforce 與 stderr attribution log；缺 token / token 不命中 / path 不在 globs 時保留原 BLOCKED 行為。
- `.claude/hooks/pre-write-language-policy.sh`：把既有 producer bypass 收緊為 token enum + path glob 兩者都命中才允許跳過；不再容許 free-form token 對任意 specs path 形成 silent bypass。
- `scripts/lib/evidence-producers.json`：新增 `auto-pass`（ledger / resume JSON）與 `breakdown:initial-create`（`tasks/T*/index.md`、`tasks/V*/index.md`）producer entry 及對應 `producer_tokens[]`。
- `scripts/write-producer-owned-artifact.sh`：新增 deterministic writer，驗 token + path glob、支援 validator context args（`--source-container` / `--source-id` / `--ledger-path` / `--task-write-at`），temp file + atomic rename，validator fail 或缺 context 時 rollback 並 exit 2。
- `scripts/validate-task-md.sh § verify_command_static_smoke`：解析 `## 改動範圍` action=`create` paths 與 `## Allowed Files` 交集得到 create set；命中時 skip missing-script error，但仍解析 flag。
- `.claude/skills/auto-pass/SKILL.md`、`.claude/skills/breakdown/SKILL.md`：ledger / resume / initial-create task.md 寫入步驟改呼叫 `write-producer-owned-artifact.sh`，移除 DP-225 期間的 Bash heredoc workaround 描述。
- `scripts/selftests/no-direct-evidence-write-producer-token-selftest.sh`、`scripts/selftests/write-producer-owned-artifact-selftest.sh`、`scripts/selftests/validate-task-md-allowed-files-create-smoke-selftest.sh`：新增三條 selftest 覆蓋 AC1 / AC2 / AC3 / AC5 / AC-NEG1 / AC-NEG2 / AC-NEG3 / AC-NEG4 / AC-NEG5。

## [3.75.115] - 2026-05-22

### Changed — DP-192 engineering first-cut worktree overlay contract hardening

強化 engineering first-cut 的 worktree overlay 契約，避免實作流程因主 checkout dirty state、worktree 路徑漂移，或規格 / skill overlay 複製 workaround 而產生不可重現行為。

- `.claude/skills/references/engineering-first-cut-flow.md`：明確要求從 `engineering-branch-setup.sh` stdout 捕捉 `WORKTREE_PATH`，並用該 path 執行 implementation / tests / verify / delivery。
- `.claude/skills/references/workspace-overlay.md`：補上 main checkout dirty state 不應阻斷 worktree dispatch 的語意，並記錄 specs / skills / polaris-config 必須維持 main-checkout absolute-path overlay。
- `.claude/skills/references/worktree-dispatch-paths.md`：新增 first-cut dispatch path 契約，禁止把 docs specs 或 local overlay 複製進 task worktree。
- `scripts/check-engineering-first-cut-worktree-contract.sh`：新增 deterministic contract guard，檢查必備 handoff pattern 與 forbidden stash / copy workaround。
- `scripts/manifest.json`：登記新的 contract guard。

## [3.75.114] - 2026-05-21

### Added — DP-220 auto-pass automatic friction collection（5 個 deterministic trigger）

把 `/auto-pass` 過程中 5 個典型 friction signal 從「靠 orchestrator 口頭記得寫 helper」改成 deterministic 自動觸發。所有 trigger 都在 helper / hook / probe / counter 內就近呼叫 `append-auto-pass-friction.sh`，並透過 helper 內建 NOOP boundary（`AUTO_PASS_LEDGER_PATH` 未設或 ledger 不存在 → silent exit 0）保證同樣 scripts 也能在非 /auto-pass 流程安全執行。

5 個 trigger × kind 對應（refinement 原文 → helper enum）：

- `gate_failure` → `deterministic_gap`（`scripts/gate-hook-adapter.sh` 在 gate exit 2 後）
- `workaround_taken` → `env_bypass`（`.claude/hooks/pre-write-language-policy.sh` 在 `POLARIS_LANGUAGE_POLICY_BYPASS=1` 分支；`POLARIS_PRODUCER` 不觸發）
- `stage_retry` → `inner_skill_halt_bypass`（`scripts/auto-pass-increment-counter.sh` 在同 transition counter 1→2 時）
- `probe_unknown` → `deterministic_gap`（`scripts/auto-pass-probe.sh` 在 `status=UNKNOWN` 時）
- `context_pressure` → `other`（orchestrator 寫 `pause.kind=session_handoff` 前手動呼叫；唯一仍由 LLM 主導的 trigger）

DP-220 scope decision：沿用既有 helper enum 來 map refinement 原文的 5 個 kind，不擴充 enum。

#### Helper / Hook / Probe / Counter wiring

- `scripts/append-auto-pass-friction.sh`：新增 NOOP boundary — `ledger missing` 時 silent exit 0（`POLARIS_FRICTION_DEBUG=1` 才印 stderr），讓 deterministic triggers 在非 /auto-pass 流程不會 fail 主 workflow。
- `scripts/gate-hook-adapter.sh`：在 gate exit 2 + gate-failure ledger 寫入後，emit `kind=deterministic_gap` friction（`AUTO_PASS_LEDGER_PATH` set 時）。
- `.claude/hooks/pre-write-language-policy.sh`：在 `POLARIS_LANGUAGE_POLICY_BYPASS=1` 分支 emit `kind=env_bypass`。`POLARIS_PRODUCER` carve-out 維持原行為，不觸發 friction（producer 是正常 attribution，不是 workaround）。
- `scripts/auto-pass-probe.sh`：在 `emit(status="UNKNOWN", ...)` 時 emit `kind=deterministic_gap`，subprocess 呼叫 helper 並 timeout=2s 保護 probe 速度。
- `scripts/auto-pass-increment-counter.sh`（新）：deterministic counter writer，支援 `engineering_to_breakdown` / `breakdown_to_refinement_inbox` / `verify_ac_to_engineering` 三條 transition。counter 1→2 transition 時 emit `kind=inner_skill_halt_bypass`；後續 increments 由 counter 自身管理，cap enforce 仍由 `auto-pass-probe.sh ledger_terminal()` 負責。

#### Documentation

- `.claude/skills/auto-pass/SKILL.md`：新增 § Auto-Friction Triggers (DP-220)，列出 5 個 trigger 對應表 + counter writer 使用範例 + `context_pressure` 唯一 LLM-driven trigger 的呼叫順序（先 helper 再寫 pause）。
- `.claude/rules/mechanism-registry.md`：新增 4 個 runtime annotation rows（`auto-pass-friction-helper` / `auto-pass-friction-counter` / `auto-pass-friction-probe` / `auto-pass-friction-gate-adapter`），語言政策 hook 沿用既有 `pre-write-language-policy` row（已 claude-code-only + fallback `validate-language-policy.sh`）。

#### Selftest

- `scripts/selftests/auto-pass-auto-friction-selftest.sh`（新）：12 個 case 覆蓋 AC1-6 + AC-NF1-3 + AC-NEG1-3。實測 wall-clock 1s。
- `scripts/manifest.json`：登記 `auto-pass-auto-friction` selftest 進 governed test profiles `core` / `release`；新增 counter writer 與 selftest entry。

#### Behavioral impact

`/auto-pass` 跑下次 DP source 時，下列場景會自動寫入 `friction_log[]`，不再需要 orchestrator 記得呼叫 helper：

1. 任何 gate（`gate-hook-adapter.sh` 包裝過的）退出 code 2 — 自動寫 `deterministic_gap`。
2. 任何 Write/Edit/MultiEdit 觸發 `pre-write-language-policy.sh` 並設 `POLARIS_LANGUAGE_POLICY_BYPASS=1` — 自動寫 `env_bypass`。
3. 任何 `auto-pass-probe.sh` UNKNOWN（marker missing / invalid JSON / ledger stale）— 自動寫 `deterministic_gap`。
4. orchestrator 對同 transition 第二次呼叫 counter writer — 自動寫 `inner_skill_halt_bypass`（confirm 是 stage retry pattern）。

只有 `context_pressure`（pause session handoff 前的 friction 紀錄）仍須由 orchestrator 主動呼叫 helper；其他 4 條改成 deterministic 後，terminal report 的 `friction_log_summary` 不再因「orchestrator 忘記寫」而失真。

## [3.75.113] - 2026-05-21

### Fixed — DP-219 run-verify-command worktree blind fix

`scripts/run-verify-command.sh` 走 ancestor 找 repo 時永遠 land on main checkout 的 bug 修復。完成後 worktree 內跑 verify 不需手動傳 `--repo`，evidence head_sha 自動 bind worktree HEAD，後續 PR-create / completion gate 的 head_sha 比對不再 drift。

- `scripts/run-verify-command.sh`：新增 `--worktree <path>` 參數；`resolve_repo_path` 改成 preference chain：`--repo > --worktree > PWD-based worktree detection (git rev-parse --show-toplevel + worktree list) > legacy ancestor walk`。PWD-based detection 只在 toplevel basename 對得上 `REPO_NAME` 或當前 worktree 對應主 checkout basename 對得上 `REPO_NAME` 時才接受，避免 silent override 不相關 cwd。
- `scripts/selftests/run-verify-command-worktree-selftest.sh`（新）：9 個 case 覆蓋 AC1（worktree binding）、AC2（main-only 行為不變）、AC3（`--repo` 仍最高優先）、AC4（`--worktree` override 生效）、AC-NF1（wall-clock < 5s, 實測 3.6s）、AC-NF2（非 git fixture exit 1 + clear error）、AC-NEG1（PWD 不在 git 時 fallback ancestor walk）、AC-NEG2（`--worktree` 非 git path exit 1）、AC-NEG3（evidence file naming pattern 不變）。
- `.claude/skills/references/engineer-delivery-flow.md`：新增 § Verify Evidence Worktree Resolution 段落，記錄 preference order 與「不需手動 `--repo`」的效果。
- `scripts/manifest.json`：登記 `run-verify-command-worktree` selftest 進 governed test profiles `core` / `release`。

DP-218 release 時手動傳 `--repo <worktree-path>` 是這條 bug 的 workaround；本 DP 起 worktree 內 verify 不再需要手動 rebind。

## [3.75.112] - 2026-05-21

### Changed — DP-218 memory → framework graduation（18 條 prose feedback 一次 absorb）

把累積在 auto-memory Hot section 的 18 條 prose feedback memory 一次 graduate 進 framework canonical surface（rules / skills / references），同步刪除 absorbed memory 檔案、regenerate `MEMORY.md`，使規則 source of truth 從 memory 收斂到可被 deterministic gate 引用、cross-LLM 共用的 framework artifact。Hot section 從 30 條降到 2 條（只剩 DP-219 預定處理的 `feedback_run_verify_command_worktree_blind` 與 active project snapshot）。

Mapping（memory file → target framework anchor）：

| Memory file                                            | Target                                                | Anchor                                                          |
| ------------------------------------------------------ | ----------------------------------------------------- | --------------------------------------------------------------- |
| `feedback_no_checkpoint_as_work_order`                 | `.claude/rules/skill-routing.md`                      | § Checkpoint vs Work Order                                      |
| `feedback_framework_release_is_self_iteration`         | `.claude/rules/framework-iteration.md`                | § Self-Iteration Release Boundary                               |
| `feedback_auto_pass_must_not_stop_on_recoverable_halt` | `.claude/skills/auto-pass/SKILL.md`                   | Execution Loop § Recoverable HALT                               |
| `feedback_refinement_no_unsolicited_lock_prompt`       | `.claude/skills/refinement/SKILL.md`                  | § Unsolicited LOCK Prompt Forbidden                             |
| `feedback_pr_resolver_branch_fallback`                 | `.claude/skills/references/engineer-delivery-flow.md` | § Revision Mode — Explicit --pr                                 |
| `feedback_portable_gate_paths`                         | `.claude/skills/references/engineer-delivery-flow.md` | § Gate Invocation — Portable Paths                              |
| `feedback_aggregate_gate_file_lists`                   | `.claude/rules/bash-command-splitting.md`             | § Aggregate File Lists Need xargs                               |
| `feedback_polaris_scripts_require_workspace_root`      | `.claude/rules/bash-command-splitting.md`             | § Helper Script Invocation — Workspace Root                     |
| `feedback_template_examples_must_be_generic`           | `.claude/rules/framework-iteration.md`                | § Template-Facing Examples Must Be Generic                      |
| `feedback_refinement_contract_requires_dp_artifact`    | `.claude/skills/refinement/SKILL.md`                  | § Framework Contract Change Guard                               |
| `feedback_gate_preflight_fail_stop`                    | `.claude/rules/bash-command-splitting.md`             | § Gate Preflight Fail-Stop                                      |
| `feedback_skill_reference_relative_paths`              | `.claude/skills/references/INDEX.md`                  | § Path Resolution — Skill-Relative                              |
| `feedback_dp_completion_audit_must_verify_merged_pr`   | `.claude/rules/sub-agent-delegation.md`               | Delegation Patterns § DP completion audit                       |
| `feedback_learning_seed_contract_gap`                  | `.claude/skills/learning/SKILL.md`                    | External Mode § External Seed Contract — DP Container Authority |
| `feedback_refinement_no_overspilt_contract_tasks`      | `.claude/skills/breakdown/SKILL.md`                   | § Task Splitting Heuristic — Reviewable PR Boundary             |
| `feedback_apply_standards_not_ask_user`                | `.claude/rules/handbook/working-habits.md`            | § Strategist 互動風格 § Apply 標準                              |
| `feedback_company_subtask_close_via_pending`           | company-scoped JIRA conventions rule                  | (company-scoped, path varies per workspace)                     |
| `feedback_small_framework_gap_fix_now`                 | `.claude/rules/skill-routing.md`                      | § Framework Gap Immediate Routing                               |

- `scripts/selftests/dp218-graduation-anchors-selftest.sh`（新）：18 條 anchor grep check，AC1 / AC-NEG1 evidence；任一 anchor 缺失 exit 1。
- `scripts/manifest.json`：登記 `dp218-graduation-anchors` selftest（governed test profile `core` / `release`）。
- 18 個 memory 檔案 graduation PR 內刪除；`~/.claude/projects/-Users-hsuanyu-lee-work/memory/MEMORY.md` 透過 `scripts/memory-hygiene-tiering.py --emit-index` regenerate。

## [3.75.111] - 2026-05-21

### Changed — DP-217 writer-side deterministic guards 一次落地

- `.claude/hooks/pre-write-language-policy.sh`：新 PreToolUse hook，當 Write / Edit / MultiEdit 目標路徑落在 `.claude/skills/**`、`.claude/rules/**` 或 `docs-manager/src/content/docs/specs/**` 時呼叫 `scripts/validate-language-policy.sh --blocking --mode artifact`；違反 zh-TW policy 時 exit 2 阻擋寫入。`POLARIS_PRODUCER` 與 `POLARIS_LANGUAGE_POLICY_BYPASS=1` 是 escape hatch 且皆寫入 stderr 給 post-task reflection 稽核。
- `.claude/settings.json`：在 PreToolUse `Write` / `Edit` / `MultiEdit` matchers 註冊新 hook，與 `no-direct-evidence-write.sh`、`pre-memory-write.sh` 並列。
- `scripts/lib/evidence-producers.json`：新增 `refinement-md-writer`、`dp-index-status-writer`、`dp-task-status-writer` 3 條 producer entry，把 refinement.md / refinement.json、DP container index.md status flip、task.md status flip 的 canonical writer surface 寫進 producer registry。
- `scripts/manifest.json`：`script-manifest-schema` governed test profiles 從 `[core, release]` 擴到 `[core, runtime, delivery, full, release]`；登記 `pre-write-language-policy` 與 `gate-work-source-chore-followup` 兩個新 governed selftest；`scripts/gates/gate-pr-body-template.sh` selftest 欄位指向擴充後的 selftest。
- `scripts/gates/gate-pr-body-template.sh`：修 `set -u` 下 `body_headings[@]` 在 body 沒有任何 `## ` heading 時觸發 unbound variable 的 regression（DP-217 friction signal）；改用 `${body_headings[@]+"${body_headings[@]}"}` 安全展開。
- `scripts/gates/gate-work-source.sh`：加入 chore-followup lane —— `chore/DP-NNN-<slug>` branch 在 parent DP 有 IMPLEMENTED `tasks/pr-release/T*.md` 時放行 release-tail manifest / housekeeping fixes，不需要另寫 task.md；non-DP `chore/*` 與缺 IMPLEMENTED parent 的 case 仍 fail-stop。
- `.claude/skills/references/v-task-md-schema.md`：新增 V task quick-lookup reference，含 V vs T 對照表、V task skeleton、producer 常踩錯誤、validator 引用，解決 DP-212 V1 寫錯 V schema 的 friction signal。
- `.claude/skills/references/task-md-schema.md`：補 V vs T Boundary 段落，把 producer 導到 `v-task-md-schema.md`；同步把舊段英文敘述改寫為 zh-TW，符合 workspace language policy。
- `.claude/rules/mechanism-registry.md`：Runtime Annotation Registry 新增 `pre-write-language-policy` 列；修正 `specs-collection-shape-write-gate` 既有的 `claude-code` → `claude-code-only` runtime enum，並指明對應 fallback validator。
- `scripts/selftests/pre-write-language-policy-selftest.sh`：新 selftest，覆蓋 scope 內英文 block / zh-TW pass / out-of-scope no-op / 非 Write 工具 no-op / `POLARIS_LANGUAGE_POLICY_BYPASS` bypass / `POLARIS_PRODUCER` bypass / wall-clock 500ms budget 7 個案例。
- `scripts/selftests/gate-pr-body-template-selftest.sh`：擴充 11 個案例，覆蓋 DP-217 regression（body 無任何 `## ` heading 時 gate 不得 emit `unbound variable` 訊息）。
- `scripts/selftests/gate-work-source-chore-followup-selftest.sh`：新 selftest，覆蓋 chore-followup PASS（active + archived container）、no-IMPLEMENTED task、missing container、非 DP chore/\* 五個案例。

## [3.75.110] - 2026-05-21

### Changed — DP-212 auto-pass refinement-inbox auto-resume + LOCKED scope guard

- `scripts/validate-auto-pass-ledger.sh`：`paused_for_refinement` 從 terminal enum 移除（DP-212 D1），改為 non-terminal `pause.kind`；legacy ledger 若仍帶 `terminal_status=paused_for_refinement`，validator 顯示 `PAUSED_FOR_REFINEMENT_LEGACY_TERMINAL` 並指向 migration note。`loop_counters.breakdown_to_refinement_inbox > 3` 必須 promote 到 `terminal_status=loop_cap_reached`，validator 主動把關。
- `scripts/auto-pass-probe.sh`：`refinement-inbox/` 出現與 verify-AC `spec_issue` 不再回 terminal `paused_for_refinement`，改為 `ROUTE_BACK_AMEND` + action=`refinement_amendment`，由 orchestrator 自動 loop 而非中斷。
- `.claude/skills/auto-pass/SKILL.md`：Dispatch Boundary 加 `refinement`（amendment mode）；execution loop 文件補 amendment counter 行為；scope guard 違規時改 `blocked_by_gate_failure` + follow-up DP seed。
- `.claude/skills/refinement/SKILL.md`：Mode Routing 新增 _auto-pass driven amendment_ 列；amendment 不發問、不重做 Phase 0/1/2 discovery，只消費 `refinement-inbox/` 並在 LOCKED scope guard 限制內更新 refinement artifact。
- `.claude/skills/references/refinement-return-inbox.md`：補 `consumed_by_amendment` schema (`amender` / `amendment_commit_sha` / `amendment_round` / `rejected_by_scope_guard` / `scope_violation_detail`)。
- `.claude/skills/references/refinement-dp-source-mode.md`：新增 § LOCKED Scope Guard，逐 section 標註 LOCKED 後可否變動 + 人工 unlock 流程。
- `.claude/skills/references/auto-pass-ledger.md`：terminal enum 更新；non-terminal pause kind 補 amendment loop fields；probe mapping 表標 `ROUTE_BACK_AMEND`。
- `.claude/rules/skill-routing.md`：補 amendment loop policy；說明使用者不需主動 `/refinement DP-NNN` 消化 inbox，由 auto-pass 控制；只有 LOCKED scope guard 觸發時才需要人工決定 unlock。
- `scripts/validate-refinement-locked-scope.sh`（新）：amendment commit diff 對照 LOCKED section 白名單；違反 Goal / Background / Decisions / Scope / Out of Scope / Acceptance Criteria 或 JSON `goal` / `background` / `decisions` / `scope` / `acceptance_criteria` 時 exit 2 + `POLARIS_LOCKED_SCOPE_VIOLATION` stderr。
- 新增 `scripts/selftests/auto-pass-amendment-loop-selftest.sh`（6 cases：non-terminal pause、legacy terminal、counter > cap、cap promotion、mismatch、cap edge）。
- 新增 `scripts/selftests/refinement-locked-scope-selftest.sh`（4 cases：legitimate amendment / Goal body 違規 / JSON AC 違規 / Decisions heading rename 違規）。
- `scripts/manifest.json` 註冊新 validator + 兩個新 selftest；governed test profile `core` / `release` 收錄。

## [3.75.109] - 2026-05-21

### Added — DP-214 auto-pass friction-log artifact 契約

- `scripts/validate-auto-pass-ledger.sh`：新增 optional `friction_log[]` schema check，包含 `friction_kind` 8 值 enum (`inner_skill_halt_bypass`、`manual_artifact_patch`、`deterministic_gap`、`env_bypass`、`validator_contract_conflict`、`missing_helper_script`、`language_drift_repair`、`other`) 與 `stage` 6 值 enum (`source`、`breakdown`、`engineering`、`verify-AC`、`framework-release`、`post-task`)；summary > 280 chars 印 stderr WARNING 但不變更 exit code（AC-NEG3）。
- `scripts/validate-auto-pass-report.sh`：從 `ledger_path` 重新聚合 ledger `friction_log[]` 為 `friction_log_summary`（`total` / `by_stage` / `by_kind`）；report 若帶 snapshot 必須與 ledger 聚合完全一致，否則 fail；validator-owned 不可手寫。
- `scripts/append-auto-pass-friction.sh`（新）：atomic append helper，含 enum 驗證、>280 chars WARNING、不截斷契約 (AC-NEG3)。
- `scripts/selftests/auto-pass-friction-log-selftest.sh`（新）：覆蓋 helper round-trip、enum rejection、soft-limit warning、ledger validator schema check、report validator 聚合一致性、mismatched summary fail。
- `.claude/skills/references/auto-pass-ledger.md`、`auto-pass-report.md`、`auto-pass/SKILL.md`、`post-task-reflection-checkpoint.md` 同步補 friction_log[] schema、寫入時機、消費契約與 follow_up_dp_seed 提示。
- 提供下一輪 refinement / sprint planning 的權威 signal source：deterministic gap、繞道、手動補位都不再只能口頭交代。

## [3.75.108] - 2026-05-21

### Changed — DP-216 scan-template-leaks selftest-slug recognition

- `scripts/scan-template-leaks.sh`：`framework_context_labels()` 加兩道 skip——(1) path-based: `scripts/selftests/**/*-selftest.sh` 一律不參與 framework-dp-active-path 偵測；(2) placeholder DP slug enum (`DP-999`/`DP-NNN`/`DP-XXX`/`DP-000`) 在任何 scripts/ path 都 skip。避免 sync-to-polaris 因 selftest fixture 內的 fake `docs-manager/.../DP-999/` 路徑而 false-positive blocking（DP-213 release 第一次跑就踩到）。
- DP-213 release tail 由本 fix 直接解鎖；後續 framework selftest 引用 placeholder 不再需要 ad-hoc workaround。

## [3.75.107] - 2026-05-21

### Changed — DP-213 memory tiering algorithm hardening

- `scripts/memory-hygiene-tiering.py` 加 `apply_hot_capacity_ceiling()` 後處理：當 Hot candidate 數量 > `MEMORY_HOT_CAPACITY` (default 15) 時，依 `pinned > trigger_count desc > recency > mtime desc > filename asc` ranking 自動把尾段 entries 降到 Warm，reason 標 `overflowed-hot-capacity`；pinned + graduated_to 永遠不被擠出。
- `scripts/validate-memory-hygiene-plan.sh` 將 `nested_frontmatter` 從 `issues` 移到 `warnings`：apply 內部 `normalize_memory_file()` 是唯一 enforcement path，canonical chain `dry-run --json | validate | apply` 在 nested_frontmatter 存在時無需 `POLARIS_MEMORY_HYGIENE_APPLY=1` bypass。
- 新增兩個 selftest：`scripts/selftests/memory-hygiene-capacity-ceiling-selftest.sh`（fixture 28 entries 驗 Hot=15、pinned 全留、graduated_to 全 Cold、migration log 含 overflowed-hot-capacity）與 `scripts/selftests/memory-hygiene-validator-nested-frontmatter-selftest.sh`（fixture plan json + memory dir 驗 chain 不需 env bypass）。
- 文件契約同步：`.claude/skills/memory-hygiene/SKILL.md`、`.claude/skills/references/memory-tiering-contract.md`、`.claude/rules/feedback-and-memory.md` 補 Hot 硬上限 15 與 nested_frontmatter normalize 是 apply 唯一 enforcement path 的描述。

## [3.75.106] - 2026-05-21

### Changed — DP-207 round 8 amendment (T2a + T6 + V1/V2)

- 完成 DP-207 round 8 self-dogfood：T2a (PR #389) 將 `ac-required-by-surface.yaml` 重新搬到 tracked reference，T6 (PR #390) 把 `framework-release` SKILL.md 搬入 workspace 並加 maintainer-only scope。
- 將 `scripts/command-catalog.json` 中 `maintainer.framework-release` 的 `implementation` 由 user-level 路徑改為 workspace 內 `.claude/skills/framework-release/SKILL.md`，配合 T6 workspace move。
- 修補 V1 / V2 verify steps：所有 deterministic check 統一以 `mise exec -C` 包裝，並把 V2 multi-source aggregation 拆成 dp207 / dp191 兩個單 source 呼叫，配合 round 8 refinement amendment。
- 紀錄 auto-pass v1 contract limitation：`paused_for_refinement` terminal 後須由使用者重新觸發 `/auto-pass`；DP-212 將追蹤 refinement-inbox auto-resume 與 LOCKED scope guard 的 deterministic 化。

## [3.75.105] - 2026-05-20

### Added — DP-207 auto-pass canonical DP orchestration gates

- 新增 locked DP source gate、auto-pass ledger / resume / report contract、proof-of-work marker validation 與 terminal closeout discipline，讓 auto-pass 以 deterministic artifacts 串接 breakdown、engineering、verify-AC。
- 補齊 refinement AC coverage、changed_files scope、baseline snapshot refresh、Codex specs-bound parity、refinement artifact parity 與 dogfood evidence audit gates。
- 新增 `scripts/audit-dogfood-evidence.sh` 與 selftest，讓 DP-207 self-dogfood deterministic-gap evidence 必須 schema 合法且可要求 consumed mapping。
- 強化 framework release lane，支援 DP-backed explicit DAG task PR merge，並加入 release metadata defer mode，讓 framework-release 可先合併 implementation PR set，再以 release metadata lane 補 `VERSION` / `CHANGELOG.md`。
- 補上 `scripts/validate-memory-write.sh` manifest row，修復 release preflight script manifest drift。

## [3.75.104] - 2026-05-20

### Added — DP-191 round 3 memory write enforcement hard gate

- 新增 `scripts/validate-memory-write.sh` CLI：對單一 memory file 做 frontmatter contract check（required fields、`pinned_reason`、topic folder 存在性、`created` ISO date、Hot soft-limit > 15、`MEMORY.md` 直寫），exit 2 + 結構化 stderr（current N、soft limit、最舊 3 候選 + 推薦命令）。
- 新增 `.claude/hooks/pre-memory-write.sh`（PreToolUse Write/Edit/MultiEdit）攔截 memory write candidate，從 hook JSON 重建內容後呼叫 validator；`POLARIS_MEMORY_DIR` 覆寫、`POLARIS_MEMORY_HYGIENE_APPLY=1` apply chain bypass、同檔案連 3 次 fail 後 surface escalation banner。
- 新增 `.claude/hooks/post-memory-index-regenerate.sh`（PostToolUse）合法寫入後以 producer env 呼叫 `memory-hygiene-tiering.py --emit-index` 重生 `MEMORY.md` generated block；regenerate 失敗時 surface 修復指令但不阻擋寫入。
- 擴充 `scripts/memory-hygiene-tiering.py --emit-index [--dry-run]`：generated block 由 HTML comment 包夾，annotation byte-equal preserve；legacy footer 視為 suffix annotation；Hot 依 `last_triggered` desc + 無欄位墊底；registered as `memory_index` producer in `scripts/lib/evidence-producers.json`。
- `.claude/rules/feedback-and-memory.md` Memory Write Hard Gate (Round 3) 段落與 `.claude/skills/references/memory-tiering-contract.md` Hot Soft-Limit Hard Gate / Generated MEMORY.md Index / Hook Ownership 三段同步登錄契約。
- `.claude/rules/mechanism-registry.md` Runtime Annotation Registry 新增 `pre-memory-write` / `post-memory-index-regenerate` 兩列 portable hook。
- 三套 selftest：`validate-memory-write-selftest.sh` / `pre-memory-write-hook-selftest.sh` / `post-memory-index-regenerate-hook-selftest.sh` 覆蓋必要欄位、`pinned_reason`、topic folder、Hot soft-limit、`MEMORY.md` 直寫、bypass、Write/Edit/MultiEdit JSON 重建、`POLARIS_MEMORY_DIR` override、escalation banner、regenerate marker、失敗 surface。

## [3.75.103] - 2026-05-19

### Added — DP-198 auto-pass orchestrator skill

- 新增 `auto-pass` locked/current DP-backed main-chain orchestrator，串接 breakdown、engineering 與 verify-AC，終點收斂為 workspace PR ready、verification current 與 durable report。
- 補齊 auto-pass ledger、execution loop、proof-of-work probe 與 terminal report contract，並以自測覆蓋 source resolver、ledger validator、probe matrix、pause taxonomy 與 report schema。
- 同步 skill catalog、公開 workflow 文件、中文觸發詞與 release metadata，並明確將 framework merge / sync / tag / GitHub release / closeout 保留給 framework-release。

## [3.75.102] - 2026-05-19

### Added — DP-201 auto-pass proof-of-work artifact contract

- 新增 proof-of-work marker producer whitelist gate，讓 `.polaris/evidence/` marker 必須符合 `scripts/lib/evidence-producers.json` 的 owning skill / writer / path contract。
- 將 direct-write hook、pre-push gate 與 generated git hooks 接上 producer whitelist，阻擋 generic writer 或 auto-pass 自行補證據。
- 將 DP-032 verify evidence writer whitelist 收斂到 producer SoT，並補 proof marker、direct-write、main-chain compliance regression selftest。

## [3.75.101] - 2026-05-19

### Fixed — DP-203 canonical command surface and gate fidelity convergence

- 收斂 framework public task canonical command surface，讓 active rules / skills / command catalog 統一使用 `mise run <task>`。
- 修正 dependency governance gates 的 Bash 3.2 no-arg strict-mode safety，並補齊 command catalog、script dependency 與 PR create selftests。
- 結清 DP-202 follow-up inventory disposition 債務，明文化 D7 readiness-probe tool token policy，並移除 onboard doctor 對第三方 `yaml` package 的依賴。

## [3.75.100] - 2026-05-19

### Added — DP-191 memory hygiene stale snapshot and lifecycle contract

- 強化 `memory-hygiene-tiering.py` 的 Hot/Warm/Cold 分類，補上 fresh-write grace、stale snapshot、graduated feedback、nested frontmatter 與 missing `created` backfill 的 dry-run / apply / decay-scan 行為。
- 重寫 memory hygiene plan validator，讓 legacy plan 與新增欄位共用同一個 JSON contract，並阻擋 nested frontmatter 等不可套用狀態。
- 補齊 memory tiering contract 與 feedback memory rule，明確 live memory 與 local mirror 的治理邊界。

## [3.75.99] - 2026-05-19

### Documentation — DP-204 jira-worklog dual-stream invocation contract

- 補上 `jira-worklog` SKILL.md Step 3「Execute (after user confirms)」code block 的雙流呼叫範例（`2>/tmp/worklog-stderr-{YYYYMM}.txt` + `1>/tmp/worklog-stdout-{YYYYMM}.json`）。
- 加入禁用 `2>&1 | tail -N` 或單一管線的警告段落，避免 summary 被截斷後使用者被迫重跑 worklog batch script。
- Step 4 補 cross-reference 指向 Step 3 範例的 stderr / stdout 檔案路徑。

## [3.75.98] - 2026-05-19

### Added — DP-202 root toolchain and public task convergence

- 新增 Polaris root public task inventory，將 bootstrap、doctor、release preflight、PR creation、spec closeout、script audit、docs health、verify 與 cross-runtime sync 收斂到 `mise` task surface。
- 新增 root dependency governance gates，覆蓋 tool direct-call、JS package graph、Python third-party dependency 與 runtime asset readiness。
- 更新 README、AGENTS、onboard skill 與 cross-runtime parity checks，統一 Claude / Codex 使用的 public task command surface。
- 收斂 direct-call inventory baseline，建立 AC10 release-day observation clock。

## [3.75.97] - 2026-05-18

### Fixed — template-safe specs validator fixtures

- 將 DP-197 新增 specs validator / migration selftest fixture genericize，避免 template sync leak check 將公司範例字串視為 material leak。
- 補 release closeout selftest specs fixture metadata，讓正式 release lane 符合 docs-manager collection contract。

## [3.75.96] - 2026-05-18

### Added — framework PR gate aggregator coverage and phased reference policy

- 將 framework PR gate aggregator 補上 reference line-count policy，並以 selftest 覆蓋 W1-W4 pass/fail dispatch。
- 新增 `lint-reference-line-count.sh --report` JSON contract 與 phased oversized reference allowlist，讓大型 reference 以顯式政策追蹤而非調高 DP-188 硬限制。
- 將 rule retention scan 納入 phased oversized reference report，並新增 DP-196 diff-scope guard，確認 DP-188 archive、hook/rule 與 runtime dependency 邊界未被擴張。

## [3.75.95] - 2026-05-18

### Fixed — specs collection producer contract

- 將 specs D2 transport artifacts 從 docs collection 排除，避免 external writes / research markdown 因缺 Starlight metadata 破壞 docs-manager。
- 新增 specs collection shape validator、migration tool、archive gate 與 pre-push selector，明確區分 docs page、D2 transport artifact 與既有 sidecar schema。
- 更新 refinement / authoring references，讓 producer contract、migration fallback 與 release gate 共用同一套路徑分類。

## [3.75.94] - 2026-05-18

### Added — deterministic tool attribution and runtime handoff

- 新增 Required Tools schema / parser validation，讓 ticket-scoped tools 由 task.md handoff，而不是升進 root `mise.toml`。
- 新增 tool attribution / resolution libraries，統一 root mise、system、delivery 與 ticket-scoped tool 的 ownership、install authority、runtime profile 與 `POLARIS_TOOL_*` error tokens。
- 將 bootstrap、doctor、toolchain、framework release lane、close-parent lifecycle 與 script dependency governance 接上 resolver / direct-call inventory gates。
- 補 release closeout 檢查的 generated runtime manifest 與 governed test runner 空 changed-file 路徑，讓 post-merge preflight 可重入。

## [3.75.93] - 2026-05-18

### Added — canonical framework workflow release hardening

- 新增 framework-release preflight、PR provenance evidence、verify-AC release disposition、gate failure ledger 與 closeout 證據檢查，避免 generic publisher 或手動 release tail 事後追認。
- 強化 engineering readiness / completion gates，讓 planner-owned baseline snapshot、verify evidence、PR body/template/language 與 release eligibility 在 task lifecycle 前被檢查。
- 補 runtime dependency guard 與 ignored-specs resolver，讓 mise / managed tools / gh 缺件與 worktree canonical specs overlay 都以 deterministic fail-stop 處理。

## [3.75.92] - 2026-05-17

### Added — cross-LLM deterministic governance hardening

- 新增 framework PR-time gate、mechanism runtime annotation validator、script-candidate graduation audit、learning seed contract gate 與 Codex portable smoke gate。
- 拆分 task schema / engineering delivery flow 大型 references，並加入 reference line-count lint。
- 將 Plugin Workflow Quarantine 收斂到單一 reference，補 rule / memory retention scanners 與 framework-experience trigger criteria。

## [3.75.91] - 2026-05-16

### Added — main-chain authoring contract completeness

- 補齊 refinement / breakdown / engineering / verify-AC 的 artifact authoring preflight pointer，明確先讀 `pipeline-handoff.md` gateway 再讀 artifact-specific schema。
- 強化 refinement JSON、V\*.md、behavior contract、return inbox 與 escalation sidecar 的 producer guidance。
- 明確 root-level task dispatch `type:` 與 nested domain `type` fields 的邊界。
- 新增 Completion Envelope advisory validator 與 selftest，並在 sub-agent role reference 標明 blocking 使用邊界。

## [3.75.90] - 2026-05-16

### Changed — main-chain skill prose consolidation

- 收斂 refinement / breakdown / engineering / verify-AC 的 Codex child-agent fallback 與 Post-Task Reflection 重複 prose。
- 將 Codex runtime adapter fallback 規則集中到 `sub-agent-roles.md` 的 Runtime Adapter Contract / Fallback Behavior。
- 合併 breakdown DP intake 的 `DISCUSSION` / missing `refinement.json` fail-stop wording，並移除新 task producer path 中的 legacy direct task fallback prose。

## [3.75.89] - 2026-05-16

### Added — runtime cache direct migration gate

- 將 external write transport cache 直接收斂到 `.polaris/runtime/external-writes/`，不保留 `.codex/external-writes/` 舊路徑。
- 新增 runtime cache residue checker 與 selftest，阻擋 `.polaris/runtime/external-writes/`、`.codex/external-writes/`、`.codex/tmp/` 在 refinement handoff 前殘留。
- 更新 refinement / external-write / authoring references，要求 durable drafts 回到 owning source container。

## [3.75.88] - 2026-05-16

### Fixed — validator no-rg fallback and direct-source scan boundary

- 讓 model-tier policy validator 在 PATH 不含 `rg` 時仍能執行 profile 與 raw model policy checks。
- 讓 docs-manager direct-source validator 不再依賴 `rg`，並把 custom loader 掃描限縮在 active source-like files，避免 archive specs prose 誤判。
- 補 no-`rg` regression selftest 與 patch release metadata，明確以 DP-185 記錄本次修正。

## [3.75.87] - 2026-05-15

### Added — governed script test contract

- 將 governed script test metadata 納入 `scripts/manifest.json`，以 profile mapping + changed-file mapping 選跑已登錄 selftests。
- 新增 deterministic script selftest helper、DP-183 bootstrap / doctor / dependency governance 首批 governed tests，以及 no-VSCode PATH missing `rg` regression fixture。
- 讓 framework release preflight 執行 selected governed script suite，避免 release 時才發現未納管 script dependency 或 PATH 偶然性。
- 更新 breakdown / engineering guidance，要求高風險 deterministic script 行為變更描述 test contract，並保留 text-only / trivial change 例外。

## [3.75.86] - 2026-05-15

### Fixed — runtime instruction source sync

- 將 DP-183 root bootstrap / doctor onboarding note 移入 runtime instruction compiler，避免 generated `AGENTS.md` 被重新產生時遺失新使用者初始化路徑。
- 同步 root `AGENTS.md` 與 Codex compatibility target，讓 agent-facing runtime notes 都指向 `polaris-bootstrap` / `polaris-doctor`。

## [3.75.85] - 2026-05-15

### Added — root runtime toolchain management

- 新增 Polaris root `mise.toml` 與 toolchain manifest profiles，將 `rg`、`jq`、Node、pnpm、Python、Playwright browser cache 與 Mockoon runtime 納入明確治理。
- 新增 `polaris-bootstrap` / `polaris-doctor` 流程，支援 workspace-shared runtime cache、no-VSCode PATH doctor 檢查，以及 fail-loud repair hints。
- 更新 onboarding 與 quick-start 文件，讓新使用者先走 bootstrap / doctor，再進 agent-facing onboard；root `pnpm` 保留為 thin alias 而非 runtime manager。
- 新增 script dependency governance，阻擋未納管的 shell / Python / Node 第三方工具與 package 依賴。

## [3.75.84] - 2026-05-15

### Fixed — template package allowlist sync

- 讓 `sync-to-polaris.sh` 同步 workspace `.gitignore`，確保 template allowlist 會追蹤 root package metadata。
- 補完 DP-179 package metadata release closure：template release 後需能以 git 追蹤 `package.json`、`pnpm-workspace.yaml`、`pnpm-lock.yaml`。

## [3.75.83] - 2026-05-15

### Fixed — template root package sync

- 讓 `sync-to-polaris.sh` 同步 root `package.json`、`pnpm-workspace.yaml`、`pnpm-lock.yaml`，避免 workspace root command governance 未進入 template release。
- 更新 workspace/template `.gitignore` allowlist，讓 root package metadata 不再需要 force-add 才能追蹤。

## [3.75.82] - 2026-05-15

### Added — root script command governance

- 新增 root `package.json` / `pnpm-workspace.yaml` / `pnpm-lock.yaml`，以 pnpm 10.10.0 提供常用 framework command alias，且不在 root 宣告第三方依賴。
- 新增 `scripts/command-catalog.json` 與人讀 command catalog，將 viewer、toolchain、script check 與 maintainer-only 指令分層管理。
- 補上 command catalog 與 root package governance validators/selftests，並讓 script manifest gate 串接 catalog validation 與 `sunset_ready` 證據 guard。

## [3.75.81] - 2026-05-15

### Fixed — Codex child-agent model dispatch

- 新增 Codex project-scoped `polaris-*` child-agent profiles，讓 Polaris semantic model class 可映射到 Codex 子代理。
- 將 `breakdown`、`engineering`、`verify-AC` 的 sub-agent dispatch contract 收斂到 semantic model class + Completion Envelope。
- 補強 model-tier validator 與 selftest，確保 Codex adapter profiles、fallback `inherit` 與跨 LLM policy 維持一致。

## [3.75.80] - 2026-05-15

### Fixed — script manifest release preflight

- 補上 DP-177 新增 root scripts 的 manifest rows，讓 release preflight 可驗證 root script coverage。

## [3.75.79] - 2026-05-15

### Changed — fresh engineering worktree enforcement

- 讓 first-cut branch setup 遇到 clean stale worktree 時先清理再建立 fresh worktree，不再回傳既有 path。
- 新增 revision fresh worktree setup helper，從 PR branch/head 建立一次性 detached worktree，dirty/unsafe 舊 worktree 會阻擋。
- 讓 behavior baseline temp worktree 改走 managed temp path 與 cleanup helper，驗證完成即清。

## [3.75.78] - 2026-05-15

### Added — engineering worktree cleanup hardening

- 新增 `engineering-worktree-cleanup.sh` dry-run/apply helper，分類並清理 clean registered worktree。
- 阻擋 dirty、main checkout、unregistered、source unknown、live-process 等 unsafe worktree，避免任務完成時誤宣稱已清空。
- 讓 `engineering-clean-worktree.sh` 與 release-completed blocker 對齊 cleanup helper remediation。

## [3.75.77] - 2026-05-15

### Changed — docs viewer lifecycle ownership

- 移除 docs-manager viewer 的 framework auto-reload / auto-restart 入口，保留使用者明確啟動、停止與 status 查詢。
- 將 docs runtime verification 改成只驗證已由使用者啟動的 viewer，並新增 `docs.viewer.verify` capability 讓 runtime command 維持 toolchain boundary。
- 更新 refinement / spec source / framework iteration references 與 docs-manager quick start，明確定義 framework 只更新文件與 route metadata。

## [3.75.76] - 2026-05-15

### Fixed — runtime verification config hardening

- 讓 `ci-local-generate.sh` 在 test-only patch 沒有 instrumented coverage lines 時維持 SKIP/PASS，不再被 empty-coverage safety net 誤判為 missing source coverage。
- 讓 `start-test-env.sh` 從 effective project config 讀取 `liveness_delay_seconds` / `liveness_timeout_seconds`，支援 Nuxt dev SSR 首次編譯較慢的 runtime verification。
- 讓 `handbook-config-validator.sh` 驗證 runtime liveness window 欄位型別，並以 selftest 覆蓋 coverage gate 與 env primitive 行為。

## [3.75.75] - 2026-05-15

### Fixed — verify-AC evidence publication and full workflow routing

- 讓 evidence upload bundle 直接產出 Jira publisher 可消費的 `links.json` 與 `publication-manifest.json`，圖片與影片證據可進入 attachment publication dry-run / apply 流程。
- 強化 verify-AC evidence reference，要求有 media evidence 時以 bundle manifest 呼叫 Jira publisher，並將 publication status 寫回 report。
- 補強 skill routing 對「完整流程 / 建 DP / DP -> PR -> 升版 / framework-release」的 hard rule，明確固定 `refinement -> breakdown -> engineering -> verify-AC`，`framework-release` 僅作 terminal tail。

## [3.75.74] - 2026-05-15

### Changed — spec lifecycle reconciler authority

- 讓 `reconcile-spec-lifecycle.mjs` 支援 `--apply`、path source、terminal archive apply 與 parent status/sidebar 寫回。
- 讓 parent closeout 改走 canonical parent file reconciler，避免 parent/task key collision，並把 DP/company parent resolver 收斂為 `index.md` 優先。
- 對 active task frontmatter status 加上 mandatory enum guard，並補 direct `IMPLEMENTED` edit hard-fail selftest。

## [3.75.73] - 2026-05-15

### Fixed — start-command untracked runtime cleanup

- 讓 `start-command.sh` 在啟動前清掉同 cwd tree、佔用 local `health_check` / `base_url` port、但未被本 project PID file 追蹤的 stale runtime。
- 加入 loopback、cwd、其他 project PID ownership guard，避免誤殺 Docker、VPN、SSH tunnel 或仍被 dependency project 追蹤的 listener。
- 補上 same-cwd stale listener 與 foreign-cwd negative selftest，確保 T8f 類型的 stale Nuxt dev lock 能被 framework cleanup，而不是 product workaround。

## [3.75.72] - 2026-05-15

### Fixed — start-command process group cleanup

- 讓 `start-command.sh` 重啟同 project runtime 前先清掉舊 process group，避免 durable launcher 下的 child dev server、port listener 或 Nuxt dev lock 殘留。
- 保留無法取得 process group 時的 single PID cleanup fallback，並避免誤殺目前 runner process group。
- 補上 child server restart regression selftest，確保第二次 official gate 不會被上一輪 runtime 殘留阻擋。

## [3.75.71] - 2026-05-15

### Fixed — start-command durable runtime launcher

- 讓 `start-command.sh` 以 detached process group 啟動 long-running runtime，避免呼叫端 shell 或 command substitution 結束時帶走 dev server。
- 保留 `ready_signal`、PID/log JSON 與 one-shot `completed` 語意，讓既有 D11 env primitive contract 不變。
- 補上 process group regression selftest，確保 runtime launcher 不再只依賴短窗 health-check。

## [3.75.70] - 2026-05-15

### Fixed — start-test-env runtime liveness

- 讓 `start-test-env.sh` 在 health check 通過後增加 runtime liveness finalizer，確認 tracked PID 與 health endpoint 在短穩定窗後仍有效。
- 保留 one-shot `start_command` 的 `completed` 語意，避免對 setup-only command 強制要求 PID 存活。
- 補上短命 runtime regression selftest，避免 dev server 已死亡時仍輸出 runtime PASS 前提。

## [3.75.69] - 2026-05-15

### Fixed — behavior contract artifact isolation

- 讓 `run-behavior-contract.sh` 每次執行前重建 deterministic artifact directory，避免失敗 run 誤讀舊的 `behavior-state.json` 或 screenshot。
- 在 PASS / FAIL behavior evidence artifact 中保留 `stdout.txt` / `stderr.txt`，並於 evidence JSON 記錄 durable file path 與 hash。
- 補上 stale artifact regression selftest，確保新失敗 run 不會繼承舊 PASS assertion coverage。

## [3.75.68] - 2026-05-15

### Fixed — polaris-env exact repo resolution

- 修正 `polaris-env.sh` 的 project dir resolver，改以 canonical `owner/repo` slug exact match 判斷 caller worktree，避免 workspace repo remote 前綴誤判為 product repo。
- 保留 DP-165 的 Docker dependency readiness 與 matching product worktree 行為，並補上 workspace-shadow repo regression selftest。
- 避免 `polaris-env.sh start <company> --project <app>` 在 workspace root 執行裸 dev command，讓 runtime behavior gate 能用文件指定入口啟動。

## [3.75.67] - 2026-05-15

### Added — Jira-first delivery evidence publication

- 新增 `publish-delivery-evidence.sh --mode jira-comment`，讓有 Jira key 的 delivery evidence 可以先上傳 Jira attachment，再於 PR 留 `polaris-jira-evidence:v1` marker。
- 將 delivery evidence manifest 轉成 Jira publisher 可驗證的 publication manifest / links manifest，沿用 existing safety gate 與 Jira uploader。
- 新增 publisher selftest，覆蓋 Jira marker、mock uploader、missing Jira key、uploader failure 與既有 GitHub comment mode。

## [3.75.66] - 2026-05-15

### Fixed — delivery evidence/report producer hardening

- 放寬 generic `run-behavior-contract.sh` evidence publication 判定，PASS behavior evidence 有 screenshot 或 video 任一媒體即可進入 PR-visible publication flow。
- 保留 legacy Playwright behavior recorder 的 video requirement，避免 video-specific recorder contract 被隱性改寬。
- 讓 `write-task-verify-report.sh` 直接產生 zh-TW report prose，並以 behavior contract selftest 覆蓋 language gate。

## [3.75.65] - 2026-05-15

### Fixed — polaris-env Docker dependency readiness

- 修正 `polaris-env.sh` 的 Docker proxy dependency startup readiness，改以 port-level readiness 啟動下游 app，避免 Docker route health 依賴尚未啟動的 app 時形成 deadlock。
- 保留 final `verify/status` 的 route health 嚴格檢查，app-backed Docker route 不健康時仍會 fail loud。
- 讓 `polaris-env.sh` 從 matching repo worktree 執行時使用目前 worktree 作為 app dev server project dir，避免 task runtime verify 跑到 canonical checkout。
- 新增 `polaris-env-selftest.sh`，覆蓋 app 啟動前 Docker route 502、app launch、worktree project dir resolution、與 final route health PASS。

## [3.75.64] - 2026-05-15

### Changed — workflow ownership cleanup

- 新增 stacked delivery sibling Epic lens，讓 refinement / breakdown 在 `TXa -> TXb -> TXc` 類長鏈交付進入 task write 前，先要求拆 sibling Epic 或留下明確 override。
- 補齊 lifecycle reconciler foundation 與 status dashboard projection selftests，讓 PLANNED task、execution stage 與既有 closeout/archive helper 行為可被同一組 gate 驗證。
- 收斂 dirty worktree ownership：把臨時草稿移回 source container，補上 DP-164 承接未歸屬 helper 變更，並強化 local CI Codecov test-only patch reason 與 main-chain compliance selftest。

## [3.75.63] - 2026-05-14

### Fixed — plugin workflow authority quarantine

- Made workspace skill routing declare OpenAI-curated and marketplace plugin skills as adapter surfaces rather than Polaris workflow authority.
- Clarified that GitHub plugin helpers may assist `engineering` review-thread reads but cannot override R6 review-thread reply and resolve obligations.
- Added canary coverage so source rules, engineering revision references, and AGENTS generated targets must keep the plugin workflow quarantine contract in sync.

## [3.75.62] - 2026-05-14

### Fixed — Codex PR assignee gate

- Made `polaris-pr-create.sh` verify remote GitHub issue assignee metadata after auto-assign, so successful `gh pr edit` alone is not treated as delivery-ready.
- Made shared PR readiness classify missing required assignees as `needs_code_changes` instead of `wait_ci`, `review_required`, or `mergeable_ready`.
- Added selftest coverage for empty remote assignees and documented the Codex / non-Claude PR gate boundary.

## [3.75.61] - 2026-05-14

### Fixed — status dashboard behavior contract tolerance

- Made the status dashboard tolerate unknown behavior contract and visual regression enum values as item blockers instead of throwing a full-page 500.
- Added raw-value fallback labels for unknown verification summary values.
- Covered unknown behavior contract metadata in the status dashboard selftest.

## [3.75.60] - 2026-05-14

### Fixed — outdated review thread closeout

- Made `engineering` revision closeout reply to and resolve outdated-but-unresolved review threads instead of treating active non-outdated threads as the whole review surface.
- Made the review-thread disposition gate require explicit disposition for every unresolved thread, including GitHub-outdated conversations that still show unresolved in the PR UI.
- Added PR state snapshot fields for total and outdated unresolved thread counts so closeout reports cannot hide stale unresolved conversations behind `active_unresolved_threads=0`.

## [3.75.59] - 2026-05-14

### Fixed — framework release route guard

- Blocked Polaris framework release and PR intents from falling through to generic GitHub publish routes.
- Added release lane task lineage validation so source-less or generic branch PRs cannot enter framework release.
- Covered legal task-backed PRs and generic publish branch rejection in the release lane selftest.

## [3.75.58] - 2026-05-14

### Added — delivery contract convergence dogfood

- Added a template-safe synthetic convergence selftest for the delivery metadata, verify report, behavior coverage, changeset scope, and PR readiness gates.
- Added sanitized fixture validation so dogfood evidence cannot introduce company or product identifiers into the template surface.
- Released the final DP-154 verification slice for parent closeout.

## [3.75.57] - 2026-05-14

### Changed — scope and PR readiness diagnostics

- Made breakdown readiness fail when a declared changeset deliverable is outside `Allowed Files`.
- Made parent closeout sync completed child status into the Work Orders table before terminal parent closeout.
- Added spec-boundary selftest coverage and separated pending CI from unknown mergeability in PR readiness snapshots.

## [3.75.56] - 2026-05-14

### Changed — behavior assertion coverage contract

- Made behavior contract evidence emit structured `assertion_results` for declared task assertions, including `NOT_COVERED` and `MANUAL_REQUIRED` states.
- Made the evidence gate validate assertion result coverage for behavior tasks instead of relying on flow prose.
- Made task verify reports show behavior assertion coverage so uncovered or manual assertions are not presented as automated PASS.

## [3.75.55] - 2026-05-14

### Fixed — PR delivery metadata automation

- Made `polaris-pr-create.sh` automatically write task `deliverable` metadata and generate the current-head task verify report after PR creation.
- Made `finalize-engineering-delivery.sh` generate a missing task-bound verify report before running the completion gate.
- Added PR creation and finalize selftests covering implicit task resolution, deliverable idempotency, and automatic verify report generation.

## [3.75.54] - 2026-05-14

### Fixed — behavior evidence and delivery closeout hardening

- Made behavior contract evidence fail when structured runtime health reports empty body, missing Nuxt root, or failed HTTP status, and defaulted product evidence namespaces to `Task JIRA key`.
- Added behavior contract selftests for canonical ticket identity, explicit ticket override, DP fallback, and unhealthy baseline/compare evidence.
- Made DP number allocation and uniqueness checks include folder-native `index.md` design plans.
- Made DP verification task closeout support `DP-NNN-Vn` folder-native tasks and added zh-TW task summary validation before PR title generation.
- Updated cross-LLM parity fixtures so release preflight remains compatible with the stricter task summary language gate.

## [3.75.53] - 2026-05-14

### Changed — PR body template preflight

- 強化 `engineering` mandatory contract，要求撰寫 PR title/body 前先讀 `pr-body-builder.md` 並解析 repo PR template。
- 新增 PR body producer preflight，讓第一版 PR body draft 就從 L1 repo template skeleton 起稿，不再等 `gate-pr-body-template.sh` 或 completion gate 擋下才重寫。
- 將 PR body template shape 納入共用 `authoring-preflight.md`，並補強 first-cut 與 revision delivery flow 的 PR body overlay 規則。

## [3.75.52] - 2026-05-14

### Changed — authoring preflight language policy

- 新增共用 authoring preflight reference，讓 skill 在產生 preview、handoff、external write body、specs markdown、refinement artifact 或 task.md 前先讀 workspace language、Starlight 與 task readiness 規則。
- 強化 `refinement` 與 `breakdown` 的 mandatory contract，要求直接使用 root `workspace-config.yaml` 的 `language` 起稿，不可把 language gate 當送出前翻譯器。
- 更新 runtime instruction 產生器並重產 Claude、Codex、Agent 與 Copilot bootstrap，讓所有 runtime 入口都會在產文前載入 authoring preflight 與 workspace language policy。

## [3.75.51] - 2026-05-13

### Fixed — template leak cleanup

- Removed company-specific ticket wording from the local artifact placement changelog history.
- Replaced a company-specific Mockoon fixture filename in the visual snapshot selftest with a template-safe example domain.

## [3.75.50] - 2026-05-13

### Changed — local artifact placement policy

- Documented `user/tools/` as an ignored user-local workspace surface for personal utilities.
- Clarified company-local helper placement under `{company}/polaris-config/tools/` instead of framework `scripts/`.
- Added external write closeout rules so durable drafts return to the owning source container and `.codex/external-writes/` remains transport-only.

## [3.75.49] - 2026-05-13

### Fixed — work-source and evidence runner hardening

- Added explicit `--task-md` forwarding to PR creation wrappers so source and evidence gates can validate overlay or external task artifacts.
- Made behavior contract evidence use a flow-provided canonical `behavior-state.json` hash when available.
- Hardened visual snapshot fixture path parsing for Markdown-quoted paths and Mockoon API fixture directories.

## [3.75.48] - 2026-05-13

### Fixed — status board task deliverable rollup

- Made docs-manager status board task summaries include terminal `tasks/pr-release/*` work orders so implemented closeout tasks count as done.
- Added deliverable-aware task projection so active tasks with PR metadata show in the review lane instead of staying unknown.
- Added stale metadata signals for malformed deliverables and local evidence drift, with representative selftest coverage.

## [3.75.47] - 2026-05-13

### Fixed — template-safe Nuxt/Vitest DEBUG hygiene

- Generalized the Nuxt/Vitest Test Command DEBUG hygiene guard so it can ship through the framework template without company-specific strings.
- Kept the clean-env handoff rule while making the validator fixture and release notes template-safe.

## [3.75.46] - 2026-05-13

### Fixed — Nuxt/Vitest test command DEBUG hygiene

- Made the app-level Vitest command source clear inherited `DEBUG` before task packaging consumes it.
- Added a breakdown readiness guard so Nuxt/Vitest app Test Commands cannot be handed to engineering without `env -u DEBUG`.
- Documented the Test Command clean-env requirement so future tasks do not push product runtimeConfig workarounds for framework/env issues.

## [3.75.45] - 2026-05-13

### Added — status board projection rollup

- Added docs-manager status update projection fields so the status board can show derived phase, next owner, next action, validation waits, latest update links, evidence links, and stale signals without writing lifecycle status.
- Extended status dashboard task summaries to include both T-task and V-task files in flat and folder-native shapes.
- Covered status update schema validation, invalid phase handling, missing evidence, waiting-window stale signals, and projection links in docs-manager selftests.

## [3.75.44] - 2026-05-13

### Fixed — local runner DEBUG env sanitization

- Made generated `ci-local.sh` clear inherited `DEBUG` by default so caller shell debug settings do not change product test startup behavior.
- Added explicit `CI_LOCAL_DEBUG` and `POLARIS_VERIFY_DEBUG` opt-ins for commands that intentionally need debug logging.
- Made `run-verify-command.sh` clear inherited `DEBUG` by default and covered the regression in selftests.

## [3.75.43] - 2026-05-13

### Fixed — docs-manager company bug navigation

- Made docs-manager show company specs before design plans in the sidebar so active company work is discoverable without scrolling through the framework backlog.
- Added a company-level `bugs` sidebar group derived from Bug issue metadata.
- Split the status dashboard into company Bugs, company specs, and design plans.
- Aligned the Starlight content loader with sidebar-hidden internal folders so local escalation and refinement inbox artifacts do not block docs builds.
- Extended the docs-manager runtime verifier wait window so preview builds with large local specs can complete before the health check times out.
- Updated docs-manager verifier contracts for the Starlight-native glob loader and company-first sidebar order.
- Made `polaris-viewer.sh` pass the resolved specs overlay to Astro so linked scratch worktrees can preview ignored local specs.
- Covered company overview, bug grouping, and status dashboard grouping in docs-manager selftests.

## [3.75.42] - 2026-05-12

### Fixed — PR review label governance

- Added project-level `delivery.pr_review_label` config for required PR review labels.
- Made PR creation apply the configured review label after auto-assignment.
- Made delivery completion block required-label PRs when the configured review label is missing.
- Documented the config contract and covered create/completion regressions in selftests.

## [3.75.41] - 2026-05-12

### Fixed — completion PR readiness gate

- Made the Developer completion gate fail-closed when required PR assignee metadata is missing or unreadable.
- Made the Polaris PR create wrapper assign the created PR to `workspace-config.yaml` `user.github_username` when assignee policy is enabled.
- Added completion-time shared PR lineage checks so stale or non-clean PR mergeability cannot be reported as ready.
- Covered missing-assignee, PR auto-assign, and behind-branch regressions in selftests.

## [3.75.40] - 2026-05-12

### Fixed — ci-local Codecov branch coverage parity

- Made generated `ci-local.sh` prefer each flag's `coverage-final.json` over lcov when available, so local patch coverage accounts for partial branch coverage like Codecov.
- Recorded the coverage source in ci-local evidence and added a regression selftest for flag-specific V8 coverage reports.

## [3.75.39] - 2026-05-12

### Fixed — template leak cleanup

- Removed company-specific ticket wording from the v3.75.38 changelog entry so framework release sync can pass template leak checks.
- Replaced a company-specific remote URL in the task metadata validator selftest fixture with a generic `example.invalid` URL.

## [3.75.38] - 2026-05-12

### Fixed — PR gate parity hardening

- Made `codex-guarded-gh-pr-create.sh` delegate to `polaris-pr-create.sh`, so Codex PR fallback uses the complete PR gate set instead of a partial preflight followed by bare `gh pr create`.
- Added `--dry-run` support to `polaris-pr-create.sh` for full-gate parity selftests without creating a PR.
- Extended cross-LLM parity checks to fail if the Codex PR fallback directly executes bare `gh pr create`, and kept the fixture specs local-only.
- Corrected the deterministic hooks registry to describe the active portable gate / wrapper contract instead of removed Claude PreToolUse shims.
- Hardened breakdown readiness checks for moment/dayjs migration packaging gaps.

## [3.75.37] - 2026-05-12

### Fixed — mockoon-required behavior contract gate

- Hardened `verification.behavior_contract.fixture_policy: mockoon_required` so task validation rejects missing `flow_script` and remote live runtime targets before engineering delivery.
- Made the behavior runner fail early when a mockoon-required task has no executable flow script contract.
- Exposed behavior contract fields through `parse-task-md.sh` and covered the validator / runner regressions in selftests.
- Documented that breakdown must not package a READY task with a clean-base-red repo-wide Test Command as the only hard test gate.

## [3.75.36] - 2026-05-10

### Changed — skill-local script ownership cleanup

- Added a deterministic script ownership audit to classify root scripts by owner, active consumers, local leakage signals, and relocation recommendation.
- Moved the `pr-pickup` intake resolver into the owning skill, updated its selftest and callsites, and removed the root script entry from the manifest.
- Removed the stale shared `get-pr-status` helper path from PR approval/converge references, and made the memory decay hook use runtime-local memory configuration instead of a hardcoded workstation path.

## [3.75.35] - 2026-05-10

### Fixed — development chain reference wiring

- Wired `infra-first-decision.md` into refinement preview and breakdown split strategy so infra prerequisite decisions use AC verification methods.
- Wired `pr-state-contract.md` and `ci-local-env-blocker.md` into engineering authority surfaces, and removed the engineering revision preference for legacy `get-pr-status` readiness inference.
- Replaced stale task packaging examples that pointed at removed status dashboard files, trimmed stale L2 numbering in the core development-chain skills, and removed orphan shared references with no active consumers.

## [3.75.34] - 2026-05-10

### Changed — scripts root topology reduction

- 移動第一批 non-hot-path root selftests 到 `scripts/selftests/`，降低 `scripts/` root entrypoint noise。
- 移動 manual maintainer support tools 到 `scripts/support/`，保留可呼叫性但退出 root hot path。
- 移除已通過 sunset posture 的 legacy scanners：`dedup-scan.py`、`dedup-scan-sections.py`、`refinement-preview.py`。
- 更新 `scripts/manifest.json` 反映 relocation/removal decision。

## [3.75.33] - 2026-05-10

### Fixed — template sync coverage for script manifest

- 修正 `sync-to-polaris.sh` 的 scripts sync/prune scope，納入 Python scripts 與 `scripts/manifest.json`。
- 確保 DP-142 script manifest governance 同步到 Polaris template repo 時不會缺少 manifest target。

## [3.75.32] - 2026-05-10

### Added — scripts topology manifest governance

- 新增 `scripts/manifest.json`，記錄 Polaris scripts 的 kind、runner、owner surface、selftest disposition、lifecycle posture 與 relocation decision。
- 新增 `check-script-manifest.sh` 與 selftest，阻擋 root script 未登錄、manifest target/selftest 遺失、enum drift 與 `sunset_ready` 缺少 removal authority。
- 將 script manifest checker 接入 framework release PR lane preflight，並登錄為 deterministic mechanism contract。

## [3.75.31] - 2026-05-10

### Added — Polaris cleanup sunset inventory

- 新增 `check-sunset-candidates.sh` 與 selftest，為 reference / script / skill cleanup 產出 deterministic sunset ledger。
- 將 cleanup sunset inventory 納入 deterministic mechanism registry，要求移除前先有 replacement authority 與 active consumer evidence。
- 新增 `check-sunset-broken-refs.sh` 與 selftest，讓 cleanup removal 後可檢查 active callsite、reference index 與 runtime instruction graph 是否破壞。

### Removed — one-off cleanup and migration helpers

- 移除無 active consumer 的 one-off helpers：`backfill-behavior-contracts.sh`、`cleanup-duplicate-starlight-title.sh`、`dp033-migrate-tasks.sh`、`infer-starlight-descriptions.sh`、`migrate-design-plan-number.sh` 與對應 selftests。
- 移除 deterministic registry 的空 `Script Candidates` placeholder，避免已升級完成的候選區塊持續留在 hot path。

## [3.75.30] - 2026-05-10

### Fixed — pr-release tasks in main-chain compliance

- 修正 `check-main-chain-compliance.sh` 的 terminal-state 判斷，讓已移到 `tasks/pr-release/T*/index.md` 的 implementation tasks 仍被視為主鏈 T task。
- 新增 selftest 覆蓋「T*.md 已 release、V*.md 仍 active」的 dogfood closeout 狀態，避免 terminal closeout 前誤報沒有 implementation tasks。

## [3.75.29] - 2026-05-10

### Fixed — active V closeout blocker sequencing

- 修正 parent closeout 的 V*.md blocker 時機：仍有 active T*.md implementation task 時只做 NOOP，不會提前 hard block。
- 保留 terminal parent closeout 的嚴格語意：所有 T*.md 已 release 後，active 或 non-PASS V*.md 仍會阻擋 parent closeout/archive。

## [3.75.28] - 2026-05-10

### Added — strict main development chain mechanical enforcement

- 新增 DP/Epic 共用 refinement source template contract，並加入 company/project additive template resolver 與 drift gate。
- 新增 `refinement -> breakdown -> engineering -> verify-AC` 主鏈的 deterministic flow-gap 與 main-chain compliance gates。
- 強化 parent closeout 語意，active 或 non-PASS 的 V\*.md dogfood verification 會阻擋 DP closeout/archive。

## [3.75.27] - 2026-05-09

### Fixed — verify-AC V-mode lifecycle gate closure

- Added `write-ac-verification.sh` with selftests so verify-AC can update V\*.md `ac_verification` metadata through a deterministic writer instead of hand-written frontmatter.
- Hardened `check-verification-passed.sh` so V-mode PASS is accepted only after the V\*.md schema validator passes.
- Restored refinement handoff selftest coverage for required `predecessor_audit` data and made DP intake references include the breakdown readiness gate.

## [3.75.26] - 2026-05-09

### Fixed — gate-controlled workflow phase-1 deterministic governance hardening

- Added shared `verification_passed`, `release_eligible`, and `release_completed` stage gates plus release-surface resolution so engineering and framework-release consume the same deterministic delivery authority.
- Demoted shared skills, coordination flows, and reporting surfaces so they only produce or repair artifacts and no longer self-authorize workflow transitions or release completion.
- Added shared company routing, PR pickup intake, docs-sync completion, and memory-hygiene plan validators with matching selftests and consumer alignment across scripts, rules, and references.

## [3.75.25] - 2026-05-08

### Reverted — unintended DP-137 main checkout dirty diagnostics

- Removed `scripts/main-checkout-dirty-report.sh` and `scripts/main-checkout-dirty-report-selftest.sh` from the tracked framework surface.
- Restored `scripts/framework-release-closeout.sh` and `scripts/framework-release-closeout-selftest.sh` to the `v3.75.23` baseline, removing the unintended main-checkout classification integration while keeping the DP-136 stale-repo diagnostics.

## [3.75.24] - 2026-05-08

### Added — deterministic main checkout dirty classification

- Added `scripts/main-checkout-dirty-report.sh` plus selftests to classify main checkout divergence, local-only dirty files, and upstream-overlap dirty files without mutating the working tree.

### Changed — release closeout points to main-checkout hygiene report

- Extended `framework-release-closeout.sh` stale repo diagnostics to embed the maintainer main-checkout classification report.
- Hardened `framework-release-closeout-selftest.sh` with origin-backed stale repo coverage for dirty classification guidance.

## [3.75.23] - 2026-05-08

### Fixed — framework delivery chain false negatives after DP-135

- Serialized `create-design-plan.sh` number allocation so concurrent DP creation no longer races into duplicate DP ids.
- Moved Codex fallback PR-create parity coverage onto a fixture-owned work source, removing detached caller branch dependence from cross-LLM parity and docs-health preflight.
- Improved framework release closeout stale-repo diagnostics so maintainers can distinguish wrong repo selection from artifact failures.

## [3.75.22] - 2026-05-08

### Fixed — canonical workspace-config visibility in clean worktrees

- Added a shared `workspace-config` root resolver plus overlay kind so clean worktrees and detached checkouts can resolve the canonical root config without manual copy workarounds.
- Updated language-policy, task-resolution, and env bootstrap consumers to use the shared root resolver, keeping worktree config visibility aligned across validation and runtime helpers.
- Expanded resolver and language gate selftests with linked-worktree fixtures so clean-worktree regressions fail deterministically before release.

## [3.75.20] - 2026-05-08

## [3.75.21] - 2026-05-08

### Fixed — DP regular delivery chain and sample-only breakdown fail-stop

- Declared that DP-backed framework work follows the same `refinement -> breakdown -> engineering` delivery chain as Epic work, with `framework-release` limited to the post-PR maintainer tail.
- Made `create-design-plan.sh` plus refinement references the explicit template authority for DP authoring so sibling-DP browsing is no longer a default template path.
- Hardened DP breakdown packaging and `validate-breakdown-ready.sh` so sample/spec-only tasks under `docs-manager/src/content/docs/specs/**` are rejected from engineering handoff.

### Added — cross-LLM constitutional governance contract

- Elevated Polaris governance posture into shared bootstrap instructions so all runtime targets inherit strong-constraint, canonical-shape, no-special-path, and fail-closed principles.
- Added a universal canonical contract governance rule that defines one canonical shape, one writer path, and deterministic enforcement as the framework default.
- Synced public maintainer-facing docs in English and Traditional Chinese so the operating model exposes the same governance posture outside internal rules.

## [3.75.19] - 2026-05-07

### Fixed — refinement convergence sample-task template leak

- Updated `verify-refinement-convergence.sh` to discover a representative company sample task dynamically instead of hard-coding a company/ticket path into the template release surface.
- Expanded the verifier selftest to cover automatic sample discovery so the convergence gate keeps working without workspace-specific defaults.

## [3.75.18] - 2026-05-07

### Fixed — legacy refinement artifact convergence wash

- Added deterministic refinement migration tooling that inventories canonical non-archive `refinement.json` artifacts, separates safe empty-audit backfills from manual predecessor review, and selftests the backfill lane.
- Added a convergence verifier that cross-checks the backfill classifier against the canonical scan summary while asserting representative sample task status metadata and docs-manager direct-source contract health.
- Washed the active canonical refinement backlog to the current predecessor-audit contract, including explicit predecessor dispositions for reviewed overlap lanes and a fully green canonical workspace scan.

## [3.75.17] - 2026-05-07

### Fixed — PR governance state contract and refinement AC parity

- Added a shared PR governance contract with deterministic work-source resolution, state snapshots, and action classification so mutable, reviewer, and reporting lanes use the same readiness vocabulary.
- Updated engineering revision, PR pickup, review, and approval flows to consume shared mergeability, base-freshness, and unsupported-mutation signals instead of lane-local heuristics.
- Enforced framework-governed readiness metadata with a deterministic PR assignee gate and hardened release/validation behavior for refinement artifact scanning.
- Unified Epic-backed and DP-backed refinement AC contracts so ticketless design plans start with the same hardened functional, non-functional, and negative AC structure plus explicit verification guidance.

## [3.75.16] - 2026-05-07

### Fixed — runtime readiness and visual snapshot bootstrap hardening

- Updated env bootstrap scripts so long-running background services survive orchestrator exit and docker-tagged runtime health distinguishes root/origin port fallback from route-level HTTP readiness.
- Expanded env selftest coverage for sticky-service durability and docker root URL readiness fallback to keep dependency bootstrap semantics deterministic.
- Hardened visual snapshot capture with retryable body reads when page navigation resets the Playwright execution context.

## [3.75.15] - 2026-05-07

### Fixed — canonical specs overlay visibility in clean worktrees

- Updated the shared specs-root resolver so explicit worktree or clean checkout paths fall back to the authoritative main-checkout specs overlay when the local checkout lacks ignored specs content.
- Updated `gate-work-source.sh` to consume the shared specs-root contract instead of hard-coding a repo-local specs path, keeping work-source lookup aligned with clean-worktree overlay semantics.
- Expanded source-gate and framework-release lane selftests to cover clean worktree task lookup against main-checkout-only folder-native task sources.

## [3.75.14] - 2026-05-07

### Fixed — folder-native branch reverse-lookup parity

- Updated `resolve-task-md-by-branch.sh` so branch reverse-lookup now scans folder-native `tasks/T*/index.md` and `tasks/pr-release/T*/index.md` sources alongside legacy `T*.md` task files.
- Expanded helper selftest coverage for folder-native product tasks, folder-native DP tasks, folder-native `pr-release` tasks, and mixed legacy-plus-folder-native duplicate bindings while preserving archive and shadow-copy prune behavior.

## [3.75.13] - 2026-05-07

### Fixed — superseded terminal consumer integration

- Updated `archive-spec.sh` and the shared spec-source resolver contract so `SUPERSEDED` is treated as a completed-class terminal archive candidate instead of lingering in active-only semantics.
- Updated docs-manager status inference so superseded parent specs are recognized as a known lifecycle state but filtered out of the active dashboard surface.

## [3.75.12] - 2026-05-07

### Fixed — refinement predecessor audit handoff contract

- Added required `predecessor_audit` schema to `refinement.json`, including deterministic dispositions and writeback expectations for `KEEP`, `PARTIAL_ABSORB`, and `FULLY_SUPERSEDED`.
- Updated the refinement DP source-mode reference so successor specs must carry predecessor audit/writeback data before lock or breakdown handoff.
- Hardened the refinement handoff gate messaging so missing or invalid predecessor audit data blocks downstream planning.

## [3.75.11] - 2026-05-07

### Fixed — parent spec supersession metadata contract

- Added `SUPERSEDED` to Design Plan lifecycle metadata and sidebar sync so parent specs can declare a completed-class terminal supersession state without overloading `IMPLEMENTED`.
- Added `supersession` frontmatter validation covering `state`, `successor_ids`, `last_event_at`, and `residual_open`, including stricter requirements when status is `SUPERSEDED`.
- Documented the frontmatter/body split for supersession summary versus human-readable historical log in the Starlight authoring contract.

## [3.75.9] - 2026-05-06

### Fixed — version-bump release gate escalation

- Added a blocking `release-preflight` mode to `check-version-bump-reminder.sh` so framework release lanes fail-stop when framework files changed without a `VERSION` bump.
- Wired `framework-release-pr-lane.sh` to run that gate against the terminal task branch before merge execution.
- Added selftest coverage for blocked, bumped, and explicit-override release preflight cases, and documented that framework release can no longer silently treat this signal as advisory-only.

## [3.75.10] - 2026-05-06

### Fixed — release gate parity manifest repair

- Added the regenerated runtime instruction manifests required by the `framework-iteration.md` rule update so cross-LLM parity stays in sync with the `version-bump` release gate escalation.
- Corrected the changelog ordering around the `3.75.9` release record.

## [3.75.8] - 2026-05-06

### Fixed — markdown-link parent closeout release repair

- Issued the versioned release for the `close-parent-spec-if-complete.sh` markdown-link checklist closeout hotfix that was previously merged without a version bump.
- Covers `./tasks/Tn/` markdown-link task ref parsing and deterministic rewrite to `./tasks/pr-release/Tn/`.
- Includes regression selftest coverage for the DP-119 failure shape where parent closeout treated markdown-link checklist items as unchecked non-task work.

## [3.75.7] - 2026-05-06

### Fixed — review-inbox review status invocation

- Updated `check-my-review-status.sh` to support both positional and `--my-user` / `--org` invocation forms.
- Added regression coverage for the DP-113 pilot failure where discovery treated `--my-user` as the literal reviewer name.
- Documented that raw diff debug output must be redirected to artifacts instead of main-session stdout/stderr.

## [3.75.6] - 2026-05-06

### Fixed — docs-manager sidebar refresh

- Added a docs-manager dev watcher that restarts Astro when public specs markdown or folder structure changes so Starlight manual sidebar state is recalculated.
- Kept hidden evidence and artifact folders out of sidebar refresh triggers to avoid noisy restarts during evidence publication.
- Added regression coverage for sidebar refresh trigger classification.

## [3.75.5] - 2026-05-06

### Added — review-inbox context budget contract

- Added a shared Context Budget Contract reference with review-inbox as the first concrete instance.
- Added review-inbox telemetry, main-session diff budget helpers, failure-only CI rollup guidance, and already-reviewed skip coverage.
- Added evidence-gated `--auto-adapter` runtime planning so `constrained_code_reviewer` cannot enable without dual-run quality evidence.

## [3.75.4] - 2026-05-06

### Fixed — task-bound verify report completion gate

- Added a deterministic task verify report writer that collects local verification evidence into task-folder `verify-report.md` artifacts.
- Updated the delivery completion gate to require a task-bound verify report matching the ticket and deliverable head SHA.
- Hardened verify command handling so stdout `FAIL` markers cannot be reported as passing evidence when a command exits 0.

## [3.75.3] - 2026-05-06

### Fixed — refinement source handoff coverage

- 明確規範 refinement-owned DP / Epic / Story / Task sources 在 breakdown 或 DP LOCK 前必須具備 current `refinement.md` 與 `refinement.json`。
- 文件化 Bug 的 source-specific 例外：Bug 使用已確認的 `bug-triage` RCA handoff，不要求 refinement artifacts。
- 在 breakdown shared fail-stop 補上 source-specific planning handoff 要求。

## [3.75.2] - 2026-05-06

### Fixed — no-source no-PR gate

- 新增 Polaris PR creation source gate，要求 Polaris-governed repo 在建立 PR 前必須解析到合法 `task.md`。
- 阻擋 source-less PR、`--draft` PR，以及用 `--skip-gates` 跳過 source gate 的嘗試。
- 更新 engineering / PR body references，明確禁止 generic publisher 旁路 Polaris PR creation。

## [3.75.1] - 2026-05-06

### Fixed — review thread completion gate

- Updated the delivery completion gate to require explicit disposition evidence for unresolved current PR review threads.
- Added completion-gate regression coverage for missing and satisfied review-thread disposition manifests.
- Documented that PR-visible verify-report markers are accepted evidence publication proof and that active review threads must be dispositioned before completion.

## [3.75.0] - 2026-05-06

### Fixed — behavior contract completion gate

- Updated the delivery completion gate to pass the resolved task.md into the evidence gate so behavior contract requirements cannot be skipped for workspace-backed tasks.
- Added completion-gate regression coverage for missing behavior contract evidence.
- Hardened task.md validation so product migration, replacement, and removal tasks cannot set behavior contracts to non-applicable without an explicit planner override.

## [3.74.99] - 2026-05-06

### Fixed — template sync generated evidence exclusion

- Updated template sync to exclude docs-manager generated public evidence mirrors from Polaris template releases.
- Ensures local board video mirrors remain runtime artifacts instead of tracked template assets.

## [3.74.98] - 2026-05-06

### Fixed — template-safe sidebar structure selftest

- Reworked the docs-manager sidebar structure selftest to generate generic temporary specs instead of using company-specific fixture keys.
- Keeps folder-native sidebar regression coverage releaseable to the Polaris template without leaking workspace sample identifiers.

## [3.74.97] - 2026-05-06

### Added — folder-native docs-manager sidebar polish

- Updated docs-manager sidebar rendering so folder-native spec containers consistently expose overview/index children while lifecycle and legacy evidence folders stay hidden.
- Added migration and sidebar selftest helpers for folder-native task docs and legacy spec folders.
- Added localized sidebar status badges and sidebar spacing overrides for long work item labels.

## [3.74.96] - 2026-05-06

### Added — completion gate publication markers

- Updated the delivery completion gate to accept PR-visible verify report and Jira evidence markers in addition to the legacy evidence publication marker.
- Added publication manifest validation to the verification evidence gate for static mirror freshness and Jira attachment write-back.
- Added a rollout guard for new legacy `tasks/Tn.md` / `tasks/Vn.md` writes while preserving legacy readers during migration.

## [3.74.95] - 2026-05-06

### Fixed — folder-native parent closeout

- Updated parent closeout to support folder-native `index.md` parents and `tasks/pr-release/Tn/index.md` siblings.
- Added regression coverage so active folder-native siblings prevent parent closeout.
- Updated design-plan status, sidebar sync, and archive helpers to accept folder-native design plan `index.md` anchors.

## [3.74.94] - 2026-05-06

### Fixed — folder-native framework release closeout

- Fixed framework release closeout so folder-native task paths such as `tasks/T7/index.md` resolve to `tasks/pr-release/T7/index.md` after implementation marking.
- Added selftest coverage for folder-native task closeout.

## [3.74.93] - 2026-05-06

### Added — Jira evidence publisher safety gate

- Added a dry-run-first Jira evidence publisher that uploads required publishable artifacts and writes attachment URLs back to publication manifests and verify reports.
- Added deterministic evidence publication safety classification for required artifacts, missing sources, unsupported file types, and secret-bearing JSON/SVG files.
- Documented the remote publication contract for Jira evidence bundles.

## [3.74.92] - 2026-05-06

### Fixed — folder-native release closeout

- Updated spec closeout marking so folder-native task containers such as `tasks/T6/index.md` move to `tasks/pr-release/T6/index.md` with implemented status.

## [3.74.91] - 2026-05-06

### Fixed — folder-native sidebar groups

- Updated docs-manager sidebar generation so folder-native `index.md` routes appear as child overview links instead of invalid Starlight group links.

## [3.74.90] - 2026-05-06

### Fixed — template-safe evidence selftests

- Replaced company-specific evidence selftest fixture keys with generic placeholders so `.mjs` script companions can be released to the template.

## [3.74.89] - 2026-05-06

### Fixed — template sync script companions

- Updated template sync to include recursive `scripts/**/*.mjs` companions alongside shell wrappers.
- Added sync selftest coverage for `.mjs` companion copy and stale `.mjs` pruning.

## [3.74.88] - 2026-05-06

### Added — spec container migration helper

- Added a dry-run-first migration helper for moving legacy DP, company spec, and task files into folder-native `index.md` layouts.
- Added collision, active/archive, relative link rewrite, and legacy evidence bundle cleanup guards.
- Documented the folder-native migration lifecycle in the shared spec source resolver reference.

## [3.74.87] - 2026-05-06

### Added — folder-native producer defaults

- Updated new Design Plan creation to write folder-native `index.md` containers while keeping legacy `plan.md` readers documented.
- Updated breakdown and refinement references so new DP-backed tasks use `tasks/Tn/index.md` / `tasks/Vn/index.md` by default.
- Added selftest coverage for folder-native DP creation, sidebar metadata, and duplicate number avoidance across active and archive containers.

## [3.74.86] - 2026-05-06

### Added — static evidence distributor

- Added a deterministic static evidence distributor that classifies verification files into `assets/**`, writes `links.json`, and mirrors videos to a scoped public evidence path.
- Added a verify report generator that consumes deterministic links and produces Starlight-valid `verify-report.md` pages with inline screenshots and linked videos.
- Extended evidence upload bundle metadata and documentation so local board reports can consume upload bundles without LLM path or file-type decisions.

## [3.74.85] - 2026-05-06

### Added — folder-native dashboard discovery

- Added docs-manager status dashboard support for folder-native `index.md` containers and `Tn/index.md` tasks.
- Added dashboard columns for human-readable verification strategy, latest verify report, and publication state.
- Updated sidebar route handling so folder-native `index.md` pages resolve to the container route.

## [3.74.84] - 2026-05-06

### Fixed — breakdown scope trace readiness

- Added Scope Trace Matrix readiness checks for breakdown-produced work orders.
- Readiness gate now verifies owning files are covered by Allowed Files and catches UI/dashboard/API tasks without render/API surfaces.
- Updated breakdown and task schema references for scope trace packaging and folder-native readiness scans.

## [3.74.83] - 2026-05-06

### Added — folder-native task resolver foundation

- Added dual-read support for folder-native task containers such as `tasks/T1/index.md` and `tasks/V1/index.md`.
- Updated task resolver, dependency validator, task validator, and artifact gate dispatch to handle legacy and folder-native task paths.
- Added task resolver/parser/dependency selftest wrapper scripts for work orders that call selftests directly.

## [3.74.82] - 2026-05-06

### Fixed — DP-backed verification pseudo identity

- Extended DP-backed task identity validation to accept verification work items such as `DP-110-V1`.
- Updated task parsing and resolver selftests so direct and from-input lookup support `DP-NNN-Vn` identities.
- Documented DP-backed `Tn` / `Vn` pseudo identities in the task.md schema reference.

## [3.74.81] - 2026-05-05

### Added — behavior contract runner

- Added a deterministic behavior contract runner for baseline / compare evidence from task.md `verification.behavior_contract`.
- Added behavior evidence checks to the portable evidence gate, including current-head compare evidence and baseline evidence for parity / hybrid tasks.
- Extended PR evidence publication and upload bundles to include behavior contract screenshots, videos, and JSON evidence.

## [3.74.80] - 2026-05-05

### Added — evidence upload bundle contract

- Added a deterministic evidence upload bundle helper for collecting local VR, Playwright, verify, and ci-local artifacts into spec `artifacts/` folders.
- Fixed engineering and verify-AC delivery references to produce PR/Jira upload bundles when local visual or behavior evidence needs manual publication.
- Added upload bundle README/manifest output and selftest coverage for duplicate screenshot names, Playwright videos, and supporting evidence JSON.

## [3.74.79] - 2026-05-05

### Fixed — GitHub REST rate limit hardening

- Added a shared REST-backed GitHub helper with bounded rate-limit retry for PR metadata, current-branch PR lookup, and CI check status reads.
- Updated framework gates, revision rebase, release lane, review, and check-pr helpers to prefer REST reads over GraphQL-heavy `gh pr ... --json` commands.
- Updated workflow references so future PR status checks use the REST-backed helper path by default.

## [3.74.78] - 2026-05-05

### Fixed — template sync bytecode hygiene

- `sync-to-polaris.sh` now removes Python `__pycache__` directories and `.pyc` / `.pyo` files after directory copies.
- Prevented local verification bytecode from leaking into the Polaris template release artifact.

## [3.74.77] - 2026-05-05

### Fixed — topic-only review-inbox clustering

- Slack PR extraction now records a deterministic `root_topic_key` when a multi-PR root message has no umbrella ticket but does have a topic signal.
- Review candidate annotation now clusters by `root_ticket_key`, then `root_topic_key`, then per-PR ticket key, fixing topic-only cross-repo false splits.
- Review packets and runtime plans now carry `root_topic_key` metadata for cluster diagnostics.

## [3.74.76] - 2026-05-05

### Fixed — workspace language authoring default

- Runtime bootstraps now tell Claude, Codex, generic agents, and Copilot to draft user-facing prose directly in the configured workspace language.
- Workspace language policy now defines `language` as the default authoring language, not only a final validation gate.
- Language gate failures now point producers back to prompt/template authoring instead of treating last-mile translation as the normal path.

## [3.74.75] - 2026-05-05

### Fixed — delivery evidence completion gate

- Completion gate now re-validates the remote GitHub PR body with the workspace language policy, so PR body edits after creation cannot bypass zh-TW enforcement.
- Added `publish-delivery-evidence.sh` to publish PR-visible evidence manifests and require publication when local VR or Playwright behavior artifacts exist.
- Playwright behavior evidence now requires a video reference before delivery completion can pass.

## [3.74.74] - 2026-05-05

### Fixed — aggregate framework release lane

- 新增 aggregate release PR base 顯式驗證，讓 framework stacked release 可以對 `main` 開 PR，不需要繞過 PR base gate。
- 新增 revision rebase aggregate mode，讓 release PR 保持 base 為 `main`，同時保留 head-bound evidence。
- 放寬 framework release cleanup：final workspace commit 已包含 task HEAD 且 worktree clean 時，可清掉舊 task worktree。

## [3.74.73] - 2026-05-05

### Added — bootstrap token budget health

- Added `measure-bootstrap-tokens.sh` for shared Polaris bootstrap budget measurement with source scope and confidence labels.
- Reduced default bootstrap cost through memory Hot hygiene, mechanism registry disclosure, and a rules progressive-disclosure slice.
- Added skill description reporting, routing canary coverage, adapter source inventory, and advisory bootstrap budget health validation.

## [3.74.72] - 2026-05-05

### Fixed — review-inbox lean runtime dispatch plan

- Added a deterministic review-inbox runtime plan that forbids general-purpose per-PR review sub-agents by default.
- Review packets now carry ticket/root-ticket/thread metadata plus a runtime adapter policy.
- Clustered review runs now have an explicit lead-before-siblings execution plan so sibling-diff mode can consume lead summaries.

## [3.74.71] - 2026-05-05

### Fixed — template leak-safe review-inbox examples

- Replaced company-specific review-inbox selftest examples with neutral placeholders so framework template sync can pass the blocking leak scanner.

## [3.74.70] - 2026-05-05

### Fixed — native visual regression evidence lane

- 新增 task.md `verification.visual_regression` parser / validator support，並要求 VR task 使用 runtime verification environment。
- 新增 `run-visual-snapshot.sh` native runner，支援 record / baseline / compare、fixture-backed replay 與 Layer C evidence。
- Engineering 與 verify-AC 現在共用 native VR runner contract；legacy `visual-regression` skill 已降為 standalone transitional guard。

## [3.74.69] - 2026-05-05

### Fixed — review-inbox sister PR clustering

- Slack PR extraction now records a `root_ticket_key` from the root message before the first PR URL.
- Review candidate annotation now clusters by `(thread_ts, root_ticket_key)` when available, so umbrella review requests group sister PRs whose individual ticket keys differ.
- Added selftests covering the DEMO-493 / APP-3853 multi-PR pattern observed in DP-094 dogfood.

## [3.74.68] - 2026-05-05

### Fixed — review-inbox Phase 3 clustering

- Added deterministic review candidate annotation for sister PR clusters and semantic model tier hints.
- Dispatch prompts now include cluster lead/sibling roles and sibling-diff escalation instructions.
- Review-inbox docs now require cluster leads to run before siblings and escalate uncertain sibling reviews to `standard_coding`.

## [3.74.67] - 2026-05-05

### Fixed — review-inbox Phase 2 token controls

- Review-inbox dispatch prompts now require changed-file-first diff sampling and cap large diff reads to targeted hunks.
- Existing inline comments are fetched as metadata-only dedup keys instead of full comment bodies.
- Slack discovery docs now require concise MCP reads, and the Slack Web API fallback accepts ISO `--oldest` values.

## [3.74.66] - 2026-05-05

### Fixed — review-inbox dispatch token overhead

- 新增 review-inbox inline dispatch context bundle，避免 batch review sub-agent 重複讀完整 review reference stack。
- 新增 deterministic project handbook resolver，只把 Polaris project handbook 內實際存在的 markdown path 注入 prompt。
- 新增 bundle / resolver / prompt dry-run selftest，防止 prompt 回退到 full reference read 或 repo guideline sweep。

## [3.74.65] - 2026-05-05

### Fixed — archive-aware Design Plan authoring

- 新增 DP authoring wrapper、active+archive DP number allocator、uniqueness gate、
  create command 與 migration script，避免 refinement 新建 DP 時重用 archive 號碼。
- 已將既有 DP-087、DP-088、DP-092、DP-095、DP-097 撞號 container 重新編號；
  現在下一個新 DP 會配置為 DP-104。
- 新增 docs-manager status live body-link check，啟動 viewer 後確認
  `/docs-manager/status/` body 內 internal links 不回 404。

## [3.74.64] - 2026-05-05

### Fixed — unique Epic task resolver input

- `resolve-task-md.sh --from-input` now resolves exact Epic task inputs when
  they produce a single candidate, such as `EPIC-478 T7`.
- Bare Epic keys still fail loud because they do not identify one engineering
  work order.
- Added resolver selftest coverage for the unique-candidate path while keeping
  ambiguous series inputs blocked.

## [3.74.63] - 2026-05-05

### Fixed — tracked specs leak guard

- 新增 `gate-no-tracked-specs.sh` 與 selftest，禁止
  `docs-manager/src/content/docs/specs/**` 被 `git add -f` 納入 workspace PR。
- 將 gate 接進 PR create、guarded commit、pre-commit 與 pre-push hook。
- 從 workspace git index 移除既有 tracked specs，維持 specs 為 local-only
  canonical source。

## [3.74.62] - 2026-05-05

### Fixed — release closeout archive target

- `close-parent-spec-if-complete.sh` 在 terminal parent archive 時改用已解析的
  parent `plan.md` path，而不是重新用 `DP-NNN` key 查找。
- 補上同號 active DP selftest，避免 release closeout 因歷史 DP 編號重複而中斷。
- 完成 DP-095 release closeout，將 active DP-095 spec 從 tracked surface 移除。

## [3.74.61] - 2026-05-05

### Fixed — awaiting re-review PR state routing

- 新增 `pr-review-state-classifier.sh` 與 selftest，將 `CHANGES_REQUESTED`
  但 CI green、無 active unresolved actionable review threads 的 PR 分類為
  `AWAITING_RE_REVIEW`。
- 更新 converge / check-pr-approvals routing，避免已修完的 PR 再被導回
  `engineering` 修 code；此狀態改走 reviewer re-review handoff。
- 在 mechanism registry 登記 PR review state routing contract，讓
  `reviewDecision` 不再單獨決定 code-fix 路由。

## [3.74.60] - 2026-05-05

### Fixed — PR review thread disposition gate

- 新增 `pr-review-thread-disposition-gate.sh` 與 selftest，revision / rebase /
  stack rewrite 既有 open PR 前必須對 unresolved、not-outdated review threads
  記錄 `fixed` / `reply_only` / `not_actionable` / `deferred_with_reason`。
- 將 gate 接進 engineering delivery flow，明確規定 approval / `reviewDecision`
  不能取代 thread-aware review disposition。
- 在 mechanism registry 新增 `pr-review-thread-disposition-required` canary，
  防止 inline review comments 在 stack rebuild 時被漏修或漏回覆。

## [3.74.59] - 2026-05-05

### Fixed — T3 stack replay and CI-local parity guards

- 新增 repo-level `ci-local-overrides.json` support，讓已證實的遠端 CI false-positive
  以 `repo_override:*` skip 寫進 generated `ci-local.sh` 與 evidence，而不是要求
  feature branch 修 unrelated type baseline debt。
- `run-verify-command.sh` 支援 task.md 明確宣告的 `## Verify Fallback Command`：
  primary verify 仍必跑，fallback evidence 會記錄 primary/fallback exit 與 hash。
- 新增 `stack-replay-manifest-check.sh`，要求手動重建 stacked PR 時留下
  included/excluded commit ledger，避免 commit 取捨只靠 LLM 口頭推斷。

## [3.74.58] - 2026-05-05

### Changed — skill resource ownership audit

- 將 skill progressive disclosure policy 補齊為 skill-private / shared reference
  與 script ownership 分流規則，避免瘦身後形成 shared reference maze。
- 新增 `skill-resource-ownership-audit.sh` 與 selftest，輸出 consumer、suggested
  owner、`candidate_rehome` / `keep_shared` / `needs_manual_review` 分類。
- 完成第一個 pilot rehome：將 docs-sync editorial guideline 搬到
  `docs-sync/references/`，並更新 shared reference index 與 docs-sync flow 引用。

## [3.74.57] - 2026-05-05

### Fixed — public onboarding toolchain contract

- 補齊 README、quick start、Codex quick start 與 PM setup checklist 的 Polaris
  runtime toolchain 前置需求，明確列出 Node >= 20、pnpm、Python 3、Playwright、
  Mockoon 與 docs viewer。
- 新增 `scripts/validate-public-onboarding-contract.sh`，從 `polaris-toolchain.yaml`
  檢查 public onboarding docs 是否包含 `polaris-toolchain.sh doctor --required`
  與必要 runtime capability。
- 將 public onboarding contract validator 接進 `readme-lint.py`，讓版本升級與
  README lint gate 能 deterministic 擋下 toolchain prerequisite drift。

## [3.74.56] - 2026-05-05

### Changed — README hub structure

- 重整 README / README.zh-TW 為 OSS-style hub：保留 product identity、
  workflow entry points、quick start、repo layout、docs links、security 與致謝。
- 移除頂層 README 內重複的長篇三支柱、PM workflow、架構與多公司細節，改導向
  既有 workflow guide、PM setup、Codex quick start 與中文觸發詞文件。
- 依 learning external mode 補上 Kubernetes、Vite、VS Code、Home Assistant
  README pattern 參考，並把 hub-README pattern 寫入 cross-session learnings。

## [3.74.55] - 2026-05-05

### Changed — onboarding-first Polaris setup

- 將新人導入主入口從 `init` 轉為 `onboard`，保留 `init` 作為 deprecated alias。
- 新增 `onboard repair` readiness model 與 `scripts/onboard-doctor.sh`，覆蓋 root config、
  company config、runtime toolchain、Codex parity、MCP readiness 與 post-setup 機制檢查。
- 更新 README、Quick Start、Codex Quick Start 與 PM setup checklist，讓 public onboarding
  docs 只導向 `onboard` 路徑。
- 補齊 root / company onboarding templates 與 completion dashboard contract，讓 first-run、
  add company、repair existing workspace 使用同一套完成標準。

## [3.74.54] - 2026-05-05

### Fixed — revision rebase enforcement

- `revision-rebase.sh` 成功後會寫 current HEAD 綁定的 R0 evidence 到 `/tmp` 與
  `.polaris/evidence/revision-rebase/`。
- 新增 `gate-revision-rebase.sh`，existing PR branch 在 `git push` 前必須有對應的
  revision rebase evidence；first-cut 尚未開 PR 的 branch 不受影響。
- 將新 gate 接到 Codex/Claude fallback pre-push、generated git pre-push hook 與
  cross-LLM parity selftest，避免 revision mode 漏跑 rebase/cascade 後仍能推送。

## [3.74.53] - 2026-05-05

### Fixed — repo handbook source-of-truth drift

- 將 engineering / learning / review lesson references 裡的 repo handbook 路徑統一到
  `{company}/polaris-config/{project}/handbook/`，避免 agent 誤讀已淘汰的
  repo-local `.claude/rules/handbook/` overlay。
- 新增 `validate-handbook-path-contract.sh`，並接到 cross-LLM parity preflight，讓
  framework health check 能 deterministic 擋下 stale repo handbook path。
- 更新 runtime instruction manifest scope policy，讓 generated runtime targets 跟
  polaris-config handbook SoT 對齊。

## [3.74.52] - 2026-05-05

### Changed — learning progressive disclosure

- 將 `learning/SKILL.md` 精簡為 orchestration contract，只保留 mode routing、
  fail-stop boundary 與 reference loading rules。
- 將 External、Queue、Setup、PR、Batch mode 程序搬到 dedicated learning
  references，並登記到 shared references index。

### Changed — breakdown progressive disclosure

- 將 `breakdown/SKILL.md` 精簡為 source routing 與 gate contract，涵蓋 Bug、
  JIRA planning、DP intake、escalation intake、scope challenge 路徑。
- 將 breakdown mode procedures、task packaging、branch / validator rules 搬到
  dedicated references，並登記到 shared references index。

### Changed — engineering progressive disclosure

- 將 `engineering/SKILL.md` 精簡為 authoritative task.md resolution、mode routing、
  mandatory gate、scope ownership boundary 的施工 contract。
- 將 first-cut、revision、local extension、scope escalation、entry resolution 程序搬到
  dedicated engineering references，並沿用 `engineer-delivery-flow.md` 作為 delivery
  backbone。

### Changed — refinement progressive disclosure

- 將 `refinement/SKILL.md` 精簡為 Architect boundary、source routing、complexity tier、
  handoff gates 的 contract。
- 將 batch readiness、Phase 0 discovery、Phase 1 elaboration、Phase 2 decision 程序搬到
  dedicated refinement references，並沿用既有 DP source / artifact / return inbox
  references。

### Changed — init progressive disclosure

- 將 `init/SKILL.md` 精簡為 workspace initialization contract，只保留 setup boundary、
  reference loading、write rules、output rules 與 completion gate。
- 將 smartSelect / audit、core setup、runtime contract、visual regression setup、post-setup
  程序搬到 dedicated init references，並登記到 shared references index。

### Changed — visual-regression progressive disclosure

- 將 `visual-regression/SKILL.md` 精簡為 domain-level screenshot comparison contract，
  保留 skip boundary、reference loading、hard rules、completion return contract。
- 將 preflight、capture、analysis/JIRA reporting、fixture lifecycle、hard-won VR principles
  搬到 dedicated visual-regression references，並登記到 shared references index。

### Changed — review-inbox progressive disclosure

- 將 `review-inbox/SKILL.md` 精簡為 multi-PR discovery 與 batch review orchestration
  contract，保留 source routing、sub-agent boundary、Slack write gate、completion summary。
- 將 Label / Slack / Thread discovery、batch review fan-out、Slack reporting 流程搬到
  dedicated review-inbox references，並登記到 shared references index。

### Changed — review-pr progressive disclosure

- 將 `review-pr/SKILL.md` 精簡為單一 PR reviewer contract，保留 routing boundary、
  standards loading、sub-agent analysis、external write gate、severity boundary。
- 將 entry/fetch、analysis/dedup、submit/notification、re-review learning 流程搬到
  dedicated review-pr references，並登記到 shared references index。

### Changed — docs-sync progressive disclosure

- 將 `docs-sync/SKILL.md` 精簡為 documentation sync contract，保留 source-of-truth、
  reference loading、source mapping、write rules、completion report。
- 將 scope detection、English / zh-TW update flow、verification flow 搬到 dedicated
  docs-sync references，並登記到 shared references index。

### Changed — standup progressive disclosure

- 將 `standup/SKILL.md` 精簡為 daily standup / EOD reporting contract，保留 auto-triage、
  data source、Confluence write gate、completion summary。
- 將 data collection、planning/TDT/BOS、format/publish 流程搬到 dedicated standup
  references，並補上 `standup-template.md` 作為固定輸出格式 source。

### Changed — bug-triage progressive disclosure

- 將 `bug-triage/SKILL.md` 精簡為 Bug diagnosis contract，保留 diagnosis-only boundary、
  AC-FAIL routing、RD confirmation hard stop、JIRA language gate、handoff summary。
- 將 entry routing、AC-FAIL scoped investigation、root cause analysis、confirmation/handoff
  流程搬到 dedicated bug-triage references，並登記到 shared references index。

### Changed — sasd-review progressive disclosure

- 將 `sasd-review/SKILL.md` 精簡為 design-first SA/SD contract，保留 source routing、
  exploration boundary、template requirements、external publish gate、completion summary。
- 將 entry/exploration、SA/SD document template、publish/scope calibration 流程搬到
  dedicated sasd-review references，並登記到 shared references index。

### Changed — verify-AC progressive disclosure

- 將 `verify-AC/SKILL.md` 精簡為 Epic AC QA contract，保留 stateless full re-run、
  observed-vs-expected boundary、disposition gate、external write/Starlight gates。
- 將 entry expansion、step execution、reporting/transition、FAIL disposition、learning lifecycle
  流程搬到 dedicated verify-AC references，並登記到 shared references index。

### Changed — intake-triage progressive disclosure

- 將 `intake-triage/SKILL.md` 精簡為 batch intake prioritization contract，保留 source
  routing、scoring boundary、external write gate、completion summary。
- 將 input parsing/fetch、scoring/verdict、writeback/Slack summary 流程搬到 dedicated
  intake-triage references，並登記到 shared references index。

### Changed — converge progressive disclosure

- 將 `converge/SKILL.md` 精簡為 batch convergence orchestration contract，保留 scan
  scope、confirmation gate、downstream routing、external write / artifact gates。
- 將 assigned work scan、gap classification、execution safety、before/after reporting 流程搬到
  dedicated converge references，並登記到 shared references index。

### Changed — checkpoint progressive disclosure

- 將 `checkpoint/SKILL.md` 精簡為 save/resume/list mode router 與 session continuity
  contract，保留 carry-forward mandatory gate 與 branch safety boundary。
- 將 save timeline write、cross-session carry-forward validator、resume/list query 流程搬到
  dedicated checkpoint references，並登記到 shared references index。

### Changed — my-triage progressive disclosure

- 將 `my-triage/SKILL.md` 精簡為個人 dashboard / zero-input router contract，保留
  cross-session resume、read-only boundary、triage state write、sub-agent envelope。
- 將 resume scan、JIRA/GitHub dashboard、`.daily-triage.json` standup handoff 流程搬到
  dedicated my-triage references，並登記到 shared references index。

### Changed — unit-test progressive disclosure

- 將 `unit-test/SKILL.md` 精簡為 project-aware testing / TDD contract，保留 framework
  detection、TDD discipline、anti-regression hard rules、completion evidence。
- 將 framework detection/TDD cycle、Jest/Vitest/Vue patterns、coverage strategy 搬到
  dedicated unit-test references，並登記到 shared references index。

### Changed — memory-hygiene progressive disclosure

- 將 `memory-hygiene/SKILL.md` 精簡為 scan/dry-run/apply mode router 與 memory tiering
  contract，保留 apply confirmation gate、path resolution boundary、routine-memory rule。
- 將 scan/dry-run report 與 apply migration safety 流程搬到 dedicated memory-hygiene
  references，移除 user-specific absolute path，並登記到 shared references index。

### Changed — validate progressive disclosure

- 將 `validate/SKILL.md` 精簡為 framework health check mode router，保留 read-only
  boundary、FAIL/WARN semantics、static-vs-conversation mechanism boundary。
- 將 isolation checks、mechanism smoke tests、report formatting 搬到 dedicated validate
  references，並登記到 shared references index。

## [3.74.51] - 2026-05-05

### Added — skill progressive disclosure audit

- Added a deterministic advisory scanner for Polaris `SKILL.md` progressive
  disclosure health, with selftest coverage for thresholds, stdout,
  Markdown output, and read-only behavior.
- Added the skill progressive disclosure placement policy reference so future
  slimming work has a shared `SKILL.md` / reference / script boundary.

### Changed — verify-AC progressive disclosure

- Moved verify-AC environment preparation details into a dedicated reference
  while keeping the skill entrypoint focused on routing, boundaries, and
  fail-stop behavior.
- Registered the new verify-AC environment preparation reference in the shared
  references index.

## [3.74.50] - 2026-05-05

### Added — docs-manager status i18n

- Added docs-manager runtime i18n helpers that read `workspace-config.yaml`
  language and support English plus `zh-TW` with English fallback.
- Wired Status Dashboard labels, status/stage/task summaries, and Starlight
  root locale to the configured workspace language.

### Fixed — status dashboard layout

- Restored the Status Dashboard to Starlight native content width and kept wide
  status tables scrolling inside the table shell instead of overlapping the
  right table of contents.

## [3.74.49] - 2026-05-05

### Added — template leak guard

- Added `scan-template-leaks.sh` with selftest coverage for deterministic
  workspace/template leak scans over the sync surface.
- Added blocking leak-check integration to `sync-to-polaris.sh`, with
  `--leak-warn-only` retained for explicit compatibility runs.

### Changed — portable examples

- Replaced company-specific tickets, orgs, domains, repo names, package scopes,
  paths, and lesson metadata in shared framework docs, skills, hooks, scripts,
  and fixtures with neutral examples.
- Renamed shared handbook fixtures from company-specific names to ExampleCo
  fixtures so template paths stay portable.

## [3.74.48] - 2026-05-05

### Added — runtime toolchain ownership

- Added a root `polaris-toolchain.yaml` manifest and runner for install,
  doctor, and command dispatch across docs viewer, Mockoon, and Playwright
  capabilities.
- Added a dedicated `tools/polaris-toolchain` Node package to own Mockoon and
  Playwright dependencies instead of leaving tool consumers to infer installs.
- Added manifest, runner, consumer, Mockoon, Playwright, docs-manager status,
  and nav sync validation coverage.

### Changed — skill and docs-manager tool entrypoints

- Updated `/init`, refinement, visual-regression, verify-AC, and shared
  references to route tool-backed workflows through the manifest-defined
  runner.
- Surfaced toolchain health and navigation sync status in docs-manager Quick
  Start and Status Dashboard runtime views.
- Moved docs-manager and legacy Mockoon/E2E dependency ownership to pnpm-backed
  runtime packages.

## [3.74.47] - 2026-05-04

### Added — docs-manager status dashboard

- Added a read-only docs-manager Status Dashboard route at `/docs-manager/status/`.
- Added build-time status inference for active design plans and company specs,
  including archive pruning, task summaries, unknown status handling, and
  blocker reporting.
- Added Status Dashboard entry points in the docs-manager sidebar, Quick Start,
  and README.

### Fixed — engineering gate cleanliness

- Made `check-scope.sh` include committed, staged, unstaged, and untracked files
  when matching changed paths against task Allowed Files.
- Made `run-verify-command.sh` refuse dirty worktrees before writing
  HEAD-bound verification evidence.
- Added regression coverage for untracked scope checks and dirty verify
  refusal.

## [3.74.46] - 2026-05-04

### Added — skill mechanization gates

- Added `polaris-external-write-gate.sh` with selftest coverage for external
  write body preflight before JIRA, Slack, Confluence, or GitHub writes.
- Added `validate-skill-contracts.sh` with selftest coverage for SKILL.md
  contract drift reporting across Completion Envelope, language gate,
  Starlight authoring, Post-Task Reflection, and legacy path patterns.
- Documented the external write gate reference and wired the skill contract
  linter into the validate skill as a report-first health check.

## [3.74.45] - 2026-05-04

### Added — breakdown readiness gate

- Added `validate-breakdown-ready.sh` with selftest coverage for task handoff
  readiness before engineering consumes breakdown output.
- Required breakdown-generated tasks to include a Gate Closure Matrix covering
  scope, test, verify, and ci-local pass conditions with owner decisions.
- Documented machine-matchable Allowed Files and readiness validation in the
  breakdown skill, task schema, pipeline handoff, and mechanism registry.
- Fixed `validate-language-policy.sh --workspace-root .` so relative workspace
  roots do not hang PR language gates.

## [3.74.44] - 2026-05-04

### Fixed — release closeout archive timing

- Made `finalize-engineering-delivery.sh` run parent closeout from the
  workspace root after implementation worktree cleanup, avoiding missing-script
  failures when the worktree has already been removed.
- Made `framework-release-closeout.sh` defer terminal DP archive until the last
  task in a stacked release, so earlier closeout steps cannot invalidate later
  task paths.
- Added release closeout selftest coverage for already-implemented stacked
  `tasks/pr-release` inputs.

## [3.74.43] - 2026-05-04

### Changed — handbook config machine source contract

- Added deterministic handbook config reader / validator fixtures for project
  runtime machine fields and migration conflict detection.
- Wired `start-test-env.sh` to resolve runtime config from project handbook
  config first, with explicit workspace-config fallback and conflict failure.
- Documented the handbook machine-source boundary in delivery and mechanism
  registries, and refreshed docs-health route assertions for archived DP tasks.
- Aligned docs-health direct-source canaries with both DP-035 active repair
  and post-closeout badge states used by the release flow.

## [3.74.42] - 2026-05-04

### Fixed — revision rebase stacked base drift

- Made `revision-rebase.sh` run GitHub PR operations from the target repo
  working directory instead of passing a filesystem path to `gh -R`.
- When an existing PR base moves from a downstream branch back to the resolved
  task base, `revision-rebase.sh` now transplants only the PR branch's own
  commits with `rebase --onto` before syncing the PR base field.
- Made `check-scope.sh` read changed file paths with `core.quotePath=false` so
  non-ASCII changeset filenames still match the delivery metadata exemption.

## [3.74.41] - 2026-05-04

### Fixed — polaris-config migration closure

- Made company workspace directories local-only and removed previously tracked
  `exampleco/` framework workspace context from version control.
- Removed steady-state runtime dependence on the transitional
  `polaris-sync.sh` script; handbook and generated-script flows now operate
  directly on workspace-owned `polaris-config`.
- Added a DP-079 migration closure gate for active-runtime scans, ignored
  company config policy, repo-local overlay cleanup, and legacy `ci-local`
  fallback blockers.
- Added post-implementation flow gap audit guidance so implementation closeout
  checks for semantic bypasses before release.

## [3.74.40] - 2026-05-03

### Changed — runtime instruction source unification

- Added a shared runtime instruction compiler for Claude, Codex, and Copilot
  targets, keeping generated instructions thin and parity-checked.
- Renamed the Polaris-owned company config root to `polaris-config` and removed
  steady-state legacy config-root references from runtime targets, skills, and
  scans.
- Moved generated script and handbook contracts toward workspace-owned
  `polaris-config` paths while keeping product repo AI config repo-owned.

## [3.74.39] - 2026-05-03

### Fixed — Codex generated target lifecycle

- Made cross-LLM parity materialize the ignored `.codex` generated rule target
  before checking drift, so fresh checkouts no longer require LLM judgment to
  run `transpile-rules-to-codex.sh` manually.
- Kept `transpile-rules-to-codex.sh --check` as a pure no-write drift check.

## [3.74.38] - 2026-05-03

### Fixed — framework task overlay closeout

- Made Developer completion prefer the main checkout specs overlay when a
  framework implementation worktree has a stale copied task.md, so lifecycle
  metadata is read from the canonical source.
- Changed `finalize-engineering-delivery.sh` to switch back to the workspace
  root before removing the implementation worktree, avoiding deleted-cwd
  closeout noise.

## [3.74.37] - 2026-05-03

### Fixed — release evidence and specs overlay

- Mirrored `run-verify-command.sh` evidence into `.polaris/evidence/verify/`
  so framework release closeout no longer depends on volatile `/tmp` files.
- Let evidence gates read the durable mirror when `/tmp` evidence is absent,
  while preserving the same head-sha-bound schema checks.
- Let docs-manager sidebar and direct-source verification use a read-only main
  checkout specs overlay when implementation worktrees do not contain ignored
  specs.

## [3.74.36] - 2026-05-03

### Changed — semantic code change flow gate

- Added a framework decision that semantic code / rule / skill / script behavior
  changes must be captured in a DP-backed work order and implemented through
  `engineering`, rather than patched directly from the main session.
- Clarified that confirmed decisions are still captured immediately, while
  behavior-changing implementation moves through task scope, worktree isolation,
  verification, PR, and release metadata.
- Added a mechanism-registry canary for direct semantic patches that bypass the
  delivery flow.

## [3.74.35] - 2026-05-03

### Changed — target-state legacy cleanup

- Removed legacy skill routing and docs references so framework work routes
  through the current `engineering`, `breakdown`, `converge`, and `verify-AC`
  contracts.
- Removed the legacy `polaris-write-evidence.sh` writer and ticket-only
  verification evidence fallback; gates now require head-sha-bound evidence
  written by `run-verify-command.sh`.
- Added a personal handbook rule to prefer direct target-state migration over
  retaining compatibility scaffolding, with explicit removal criteria required
  for any short-lived migration aid.
- Updated zh-TW quick start MCP guidance and regenerated Copilot runtime
  instructions from the rule source.

## [3.74.34] - 2026-05-02

### Changed — framework backlog convergence closeout

- Closed the DP-075 active Design Plan sweep by archiving parking/dependent
  design seeds and leaving only active discussion / re-refinement candidates.
- Added the refinement research container contract and learning import wiring
  so future refinement work can track research snapshots inside the source
  container.
- Added the workspace overlay resolver and docs-manager release cleanup so
  framework work can distinguish tracked implementation files from local specs
  and generated runtime output.
- Slimmed `check-pr-approvals` by moving low-frequency reporting, Slack, label,
  and remediation guidance into a lazy-loaded reference.

## [3.74.33] - 2026-05-02

### Fixed — docs-manager unified spec sidebar routing

- Unified Design Plan and company spec sidebar generation so both namespaces use
  the same folder traversal and badge derivation logic.
- Fixed company Epic folder labels collapsing to `refinement` while preserving
  per-file refinement labels.
- Added regression coverage for company and Design Plan task routes, including
  `tasks/pr-release/`, plus lifecycle badge canaries for both namespaces.

## [3.74.32] - 2026-05-02

### Fixed — terminal parent archive closeout

- Added explicit terminal parent archive mode to `close-parent-spec-if-complete.sh`
  so DP-backed framework closeout can archive a parent DP at the same moment it
  becomes `IMPLEMENTED`.
- Reordered `framework-release-closeout.sh` so task worktree / branch cleanup
  happens before parent archive moves the DP container.
- Added delayed-terminal archive regression coverage for the DP-040 failure
  shape: non-task checklist blocks initial closeout, then later parent closeout
  archives the terminal DP.

## [3.74.31] - 2026-05-02

### Changed — framework engineering flow

- Sunset `git-pr-workflow` as an active Admin PR skill. Framework repo changes
  now route through DP-backed `refinement` -> `breakdown` -> `engineering`.
- Removed active docs and routing references that sent framework/docs PR work to
  `git-pr-workflow`, including README skill lists, workflow guide diagrams, and
  Copilot routing instructions.
- Added `framework-release-pr-lane.sh` plus selftest to preflight stacked
  framework workspace PRs before `framework-release` syncs workspace main to
  the Polaris template repo.

## [3.74.30] - 2026-05-02

### Changed — spec sidebar metadata single entrypoint

- 移除 `sync-dp-sidebar-metadata.sh` 與對應 selftest，不保留 DP-only
  compatibility wrapper。
- 文件與 validator repair hint 全部改用共用
  `sync-spec-sidebar-metadata.sh`，讓 DP 與一般工單 parent 使用同一個
  lifecycle sidebar metadata 入口。

## [3.74.29] - 2026-05-02

### Fixed — spec closeout sidebar refresh

- 新增共用 `sync-spec-sidebar-metadata.sh`，讓 Design Plan 與 company spec
  parent 都能在 lifecycle status 改變後同步 Starlight sidebar badge。
- `mark-spec-implemented.sh`、`codex-mark-design-plan-implemented.sh` 與
  `archive-spec.sh` 現在會在 closeout / archive path 自動同步 parent
  sidebar metadata，避免 `status` 與 `sidebar.badge` drift。
- `archive-spec.sh` 在真實 workspace archive 後會重啟已存在的 8080
  docs-manager viewer，讓 startup-time sidebar config 重新計算。

## [3.74.28] - 2026-05-02

### Fixed — task gate contract hardening

- `check-scope.sh` 支援 `VERSION` 這類 root exact filename，並保留自然語言
  Allowed Files bullet skip 行為。
- `validate-task-md.sh` 補上 docs-manager `/docs-manager/` runtime target
  contract、repo-local script unsupported flag smoke，以及簡單 `rg` regex
  parse smoke。
- PR title gate 會在 expected title 與 `zh-TW` workspace language policy
  不相容時 fail-stop，避免 title gate / language gate 互相拉扯。
- 更新 task schema 與 breakdown guidance，讓後續 task generation 直接產生
  gate-safe summary、runtime target、Verify Command。

## [3.74.27] - 2026-05-02

### Fixed — docs-manager runtime smoke stability

- 將 docs-manager runtime verifier 的 active DP smoke 改成動態讀取 sidebar
  內現存的 DP folder / route，避免 release closeout archive DP 後 health check
  綁定已歸檔的 DP。

## [3.74.26] - 2026-05-02

### Fixed — docs-manager runtime lifecycle ownership

- 新增 `polaris-viewer.sh --detach`、`--status`、`--stop`，讓使用者看的
  docs-manager preview 可以獨立於 shell lifetime 持續存在。
- 更新 docs-manager runtime verification，只 cleanup verifier 自己啟動的
  ephemeral server，並保留被 reuse 的 persistent preview server。
- 在 docs-manager maintenance guide 補上 persistent preview 與 verification
  runtime 的 lifecycle 差異。

## [3.74.25] - 2026-05-02

### Changed — docs-manager folder-native refinement preview

- Reworked docs-manager specs sidebar generation into a folder tree that keeps
  DP, company ticket, task, and pr-release markdown routes visible.
- Moved DP lifecycle / priority badges onto DP folder nodes while preserving
  existing page routes.
- Updated refinement preview workflow documentation so docs-manager Starlight
  routes are the official review surface and `refinement-preview.py` is only a
  legacy fallback helper.
- Expanded docs-manager runtime verification to cover folder badges, nested
  routes, company refinement pages, and preview search base-path behavior.

## [3.74.24] - 2026-05-02

### Changed — README brand logo placement

- Moved the Polaris logo into the root English and zh-TW README files as the
  project brand mark, while keeping the docs-manager README focused on
  maintenance notes.

## [3.74.23] - 2026-05-02

### Fixed — Polaris template sync allowlist

- Updated `sync-to-polaris.sh` to maintain the template `.gitignore`
  allowlist for docs-manager, GitHub config, and Codex compatibility files so
  copied framework assets are actually tracked and published in the template
  repository.

## [3.74.22] - 2026-05-02

### Changed — docs-manager branding and quick links

- Added the Polaris logo asset to docs-manager and wired it into the Starlight
  site title plus docs-manager README.
- Replaced the scaffold quick start copy with stable docs-manager entry points
  that link to concrete rendered spec pages instead of folder-only routes.

## [3.74.21] - 2026-05-02

### Changed — docs-manager viewer availability convention

- Added a framework-level convention to keep the user's default docs-manager
  viewer available at `http://127.0.0.1:8080/docs-manager/` during specs,
  docs-manager, and release work.
- Documented that preview/search verification should use a separate port when
  possible, and that any necessary stop of port 8080 must be followed by
  restarting the dev viewer before handoff.

## [3.74.20] - 2026-05-02

### Fixed — DP-044 flavor disposition gate

- `validate-breakdown-escalation-intake.sh` now requires `--disposition` and
  validates `accepted flavor: X` / `re-classified to Y: reason` against the
  engineering sidecar flavor before breakdown lands task.md, JIRA, or sidecar
  state writes.
- Updated breakdown scope-escalation instructions and the mechanism registry to
  make the flavor disposition check deterministic.
- Closed DP-044's remaining P0 blind spots and marked the design plan
  `IMPLEMENTED`, then archived it out of the active Design Plan list.

## [3.74.19] - 2026-05-02

### Changed — docs-manager container sidebar

- Replaced raw Starlight `specs` autogeneration with a generated manual sidebar
  that links Design Plan and company ticket containers directly to their primary
  document instead of rendering an extra folder-only collapse level.
- Added deterministic Design Plan sidebar metadata sync and validation scripts,
  including lifecycle / priority badge support for autogenerated Starlight links.
- Documented the specs sidebar and DP metadata authoring rules.

## [3.74.18] - 2026-05-02

### Fixed — pre-push hook quality marker drift

- Reinstalled the local generated pre-push hook and updated the Claude/Codex
  fallback pre-push gate to delegate to the current `gate-ci-local`, evidence,
  and changeset gates instead of the retired `/tmp/.quality-gate-passed-*`
  marker advisory.
- Added `install-copilot-hooks-selftest.sh` to prevent generated or fallback
  pre-push gates from regressing to the old quality marker warning.

## [3.74.17] - 2026-05-02

### Fixed — framework release closeout archive idempotency

- `framework-release-closeout.sh` now accepts already archived DP task paths
  under `tasks/pr-release/` without resolving the task ID through the active
  specs tree.
- Added self-test coverage for archived DP release closeout so post-release
  metadata writes, parent closeout, and worktree cleanup remain idempotent.

## [3.74.16] - 2026-05-02

### Changed — Starlight specs authoring contract

- Added a shared Starlight authoring contract for specs Markdown, requiring
  `title` and `description` frontmatter and avoiding duplicate H1 page titles.
- Added duplicate-title cleanup, legacy description inference, and Starlight
  authoring validator scripts with self-test fixtures.
- Removed the docs-manager duplicate-title remark transition plugin now that
  source specs are converted and validated directly.

## [3.74.15] - 2026-05-01

### Changed — framework docs health preflight

- Documented Codex as a supported agent runtime instead of a compatibility
  layer, including the symlink-based skill repair flow.
- Updated README and workflow docs to reflect the current `engineering` /
  `git-pr-workflow` boundary and shared delivery flow.
- Clarified that `docs-sync` can delegate semantic drift review to the
  maintainer-local docs health audit when available.

## [3.74.14] - 2026-05-01

### Fixed — docs-manager duplicate page titles

- Added a docs-manager remark plugin that removes a markdown H1 when it matches
  the Starlight `title` frontmatter, preventing duplicate page titles.
- Extended docs-manager runtime verification to fail on duplicate H1 titles.

## [3.74.13] - 2026-05-01

### Changed — Starlight-native docs-manager specs root

- `docs-manager` now uses the official Starlight `docsLoader()` / `docsSchema()`
  flow with canonical specs stored under `docs-manager/src/content/docs/specs/`.
- Specs lifecycle scripts now resolve the canonical root through shared helpers
  instead of hard-coding `specs/` or `docs-manager/specs`.
- Autogenerated sidebar subgroups now stay collapsed by default, keeping large
  archived DP trees from expanding the full navigation.

## [3.74.12] - 2026-05-01

### Changed — framework DP closeout archive

- `framework-release-closeout.sh` now archives a DP container automatically once
  the parent DP reaches terminal status after release closeout.
- Lifecycle docs now treat docs-manager as a direct canonical specs reader:
  framework DP closeout moves files; no viewer sync step is required.

## [3.74.11] - 2026-05-01

### Fixed — docs-manager template sync flow

- `sync-to-polaris.sh` now includes the framework `docs-manager/` app when
  publishing the template, while excluding generated runtime output and mirror
  content.
- `sync-from-polaris.sh` now restores `docs-manager/` into instances and
  removes the retired `docs-viewer/` app during framework sync.

## [3.74.10] - 2026-05-01

### Fixed — task branch contract

- `engineering-branch-setup.sh` now resolves first-cut branches from the
  task.md `Task branch` contract before falling back to deterministic slugging.
- Added `resolve-task-branch.sh` with explicit branch validation and self-test
  coverage for legacy fallback, invalid refs, and wrong task prefixes.

## [3.74.9] - 2026-05-01

### Changed — docs-manager direct-source closeout

- Removed the legacy specs sidebar generator and sync hook entrypoints from the
  steady-state docs flow.
- Documented docs-manager as the direct reader of canonical `{workspace_root}/specs/`
  content for dev, preview, search, and archive routes.
- Kept release validation centered on `verify-docs-manager-runtime.sh` and
  `archive-spec-selftest.sh`.

## [3.74.8] - 2026-05-01

### Changed — PR readiness completion gate

- Completion gate now reads deliverable PR remote metadata/body before task closeout and blocks draft, non-open, stale-head, or invalid-template PRs.
- PR body template gate now supports remote PR body sources while reusing the existing heading parser.
- Engineering docs, PR body builder guidance, and mechanism registries now define `polaris-pr-create.sh` plus completion-time PR readiness as the cross-runtime delivery contract.

## [3.74.7] - 2026-05-01

### Changed — refinement target-state planning contract

- `refinement` framework contract proposals now require a target state before
  implementation, including source of truth, runtime ownership, handoff
  boundaries, and steady-state paths.
- DP source mode now documents target-state-first sections for framework DPs:
  `Target State`, `Decision Policy`, and `Migration Boundaries`.
- Phased compatibility in framework DPs must specify owner, removal criteria,
  verification method, and follow-up task before breakdown or implementation.

## [3.74.6] - 2026-05-01

### Changed — framework target-state planning policy

- Added a target-state-first framework planning rule: plans must define the
  clean target architecture before splitting delivery phases.
- Clarified that phased compatibility is allowed only as a temporary delivery
  tool with an owner, removal criteria, verification method, and follow-up task.
- Added a mechanism-registry canary for fallback / mirror / dual-source plans
  that drift into steady-state compatibility instead of completing the design.
- Fixed the scope-header gate so universal `rules/handbook/` files are not
  misclassified as company-scoped rule files.

## [3.74.5] - 2026-05-01

### Fixed — DP-061 docs viewer release metadata

- `polaris-viewer.sh` and the docs-viewer runtime verifier now preserve
  non-default viewer origins and emit browser-based runtime evidence for local
  verification.
- `run-verify-command.sh` now keeps bootstrap commands in the Layer B evidence
  stream so verification setup is auditable.
- `generate-specs-sidebar.sh` now emits Starlight-compatible navigation
  metadata for specs sidebar rendering.

### Fixed — framework version bump reminder coverage

- `check-version-bump-reminder.sh` now detects framework distribution/tooling
  files such as scripts, hooks, docs, docs-viewer assets, templates, and
  generated agent guidance, instead of only rules and skills.
- `engineering` and `git-pr-workflow` keep version reminders portable: they
  surface `VERSION` / `CHANGELOG.md` decisions while leaving local release
  tails in local policy and local skills.

## [3.74.4] - 2026-04-30

### Fixed — ci-local changeset policy mirror

- `ci-contract-discover.sh` no longer falls back to an `other` category; CI
  setup/delivery/policy commands are classified explicitly.
- `ci-local-generate.sh` now converts Woodpecker changeset policy jobs into a
  local deterministic `.changeset/*.md` + JIRA ticket check instead of dropping
  them from the local mirror.
- Added self-test coverage for missing changeset failures, valid changeset
  passes, and avoiding unsafe replay of CI-only `apk` / `gh auth` / `gh pr`
  fragments.

## [3.74.3] - 2026-04-30

### Fixed — docs-viewer local origin contract

- `docs-viewer` local `site` origin is now driven by
  `POLARIS_DOCS_VIEWER_SITE`, while keeping a safe 8080 fallback.
- `polaris-viewer.sh` now exports the resolved origin, opens the same origin,
  and verifies an occupied port is an actual Polaris Specs viewer before
  reusing it.
- Added `verify-docs-viewer-runtime.sh` to check 8080 and non-8080 ports with
  browser navigation for sidebar and pagination origin stability.

## [3.74.2] - 2026-04-30

### Fixed — breakdown language preview policy

- `breakdown` now reads root `workspace-config.yaml language` as part of
  workspace config intake.
- Added conversation-level language policy for Step 8 and DP D4 confirmation
  previews, so planning output follows the configured language before artifact
  writes happen.
- Kept the existing `task.md` / `V*.md` deterministic artifact language gate as
  the downstream handoff guard.

## [3.74.1] - 2026-04-30

### Fixed — multi-package changeset gate

- `parse-task-md.sh` now exposes `deliverables.changeset.*` fields so
  changeset package scope metadata can be consumed mechanically.
- `polaris-changeset.sh check` now accepts an existing ticket changeset that
  covers every discovered package for a multi-package task, instead of
  blocking valid hand-authored multi-package changesets.
- Extended parser and changeset self-tests to cover the new completion gate
  path.

## [3.74.0] - 2026-04-30

### Changed — Starlight specs viewer and archive lifecycle

- 將 docs-viewer 由 docsify sidebar 改為 Starlight / Astro app，直接 mirror
  workspace `specs/` tree，支援 nested collapse、search 與 clean routes。
- 新增 `archive-spec.sh --sweep --dry-run` / `--sweep --apply`，用 parent
  status 機械判斷 `IMPLEMENTED` / `ABANDONED` specs，並在 duplicate archive
  destination 時 fail loud。
- 將 resolver、closeout、viewer sync hook 與相關 skill references 改為 root
  `specs/companies/{company}` namespace，active lookup 預設排除 archive。
- 這是 viewer route breaking change：舊 docsify `#/specs/...` route 不再是正式
  viewer contract；新 route 跟隨 Starlight generated content path。

## [3.73.66] - 2026-04-30

### Added — framework release closeout automation

- 新增 `framework-release-closeout.sh` 與 selftest，讓 framework release 後可批次
  closeout DP-backed tasks：寫入 `extension_deliverable`、跑 local-extension
  completion gate、標記 task implemented、關閉 parent DP、清理 implementation
  worktree。
- 支援 stacked task release，task list 必須明確傳入，避免從 branch name 猜測並
  誤清其他 DP。
- 更新 engineering / delivery flow / mechanism registry，將 post-PR
  `framework-release` endpoint 指向 deterministic closeout helper。

## [3.73.65] - 2026-04-30

### Added — cross-LLM model tier policy

- 新增 central `model-tier-policy.md`，用 `small_fast`、`realtime_fast`、
  `standard_coding`、`frontier_reasoning`、`inherit` 統一跨 LLM model
  selection。
- 將 sub-agent references、mechanism registry 與相關 skills 的 inline
  `haiku` / `sonnet` wording 改為 semantic model classes，避免 workflow
  prose 綁死 provider-specific model name。
- 新增 `validate-model-tier-policy.sh` 與 selftest，檢查 raw provider model
  policy drift 以及 `.agents/skills` mirror mode。
- 補 Codex / Claude runtime adapter examples，明確分離 model class 與
  `model_reasoning_effort` / runtime effort。

## [3.73.64] - 2026-04-30

### Fixed — DP refinement JSON handoff

- `validate-refinement-json.sh` 支援 DP-backed `refinement.json`：
  `epic: null`、`source.type=dp`、`plan_path` 與 `jira_key: null`。
- `refinement-handoff-gate-selftest.sh` 補上 DP-backed artifact case，避免
  ticketless refinement handoff 再被 JIRA-only schema 誤擋。
- 收緊 refinement / breakdown handoff 規則：新 DP 缺 `refinement.json` 時不得
  直接 minimal intake，必須回 refinement 補 artifact 並通過 handoff gate。

## [3.73.63] - 2026-04-30

### Fixed — refinement DP language gate

- 在 `refinement-dp-source-mode.md` 補上 DP-backed `plan.md` / `refinement.md`
  create/update 後的 blocking language gate。
- 明確要求 sidebar sync、local preview、user-facing review 與 downstream handoff
  前都必須先通過 `validate-language-policy.sh --blocking --mode artifact`。
- 在 mechanism registry 新增 `refinement-dp-language-gate` canary，防止
  ticketless refinement 再次繞過 workspace 語言設定。

## [3.73.62] - 2026-04-30

### Added — language policy registry parity

- 在 deterministic hooks registry 登記 `workspace-language-policy-gate`，包含 PR、
  commit、artifact gate、自測與 exception policy。
- 在 mechanism registry 補上 language policy gate 的 health-check canary 與
  deterministic contract pointer。
- 更新 docs-sync 與 README / workflow docs，明確記錄 bilingual docs mode 與
  workspace language policy gate 的關係。

## [3.73.61] - 2026-04-30

### Added — external write language gates

- 補上 `bug-rca` 與 `standup` 的 blocking temp artifact language gate，
  覆蓋 JIRA RCA comment 與 standup / EOD Confluence write path。
- 更新 bug-triage、sasd-review、intake-triage、review-inbox、check-pr-approvals、
  jira-worklog、learning、sprint-planning 的 external write 接入點，統一引用
  `workspace-language-policy.md`。
- 在共用 language policy reference 記錄 external write rollout status 與 MCP
  runtime interception 的剩餘風險。

## [3.73.60] - 2026-04-30

### Added — shared workspace language policy reference

- 新增 `workspace-language-policy.md`，集中定義 downstream-facing artifact、
  GitHub、JIRA、Slack、Confluence、commit message 與 release prose 的語言 gate 規則。
- 更新 refinement、breakdown、engineering、verify-AC、review-pr、docs-sync 等核心
  skills，讓各自的 write path 引用同一份 language policy reference。
- 保留 docs-sync 的 bilingual source / translation mode，避免 English source docs 被
  zh-TW-only artifact gate 誤擋。

## [3.73.59] - 2026-04-30

### Added — commit message language gate

- 新增 `gate-commit-language.sh`，在 git commit 前檢查 commit subject/body 的
  自然語言內容。
- 串接到 `codex-guarded-git-commit.sh` 與 `codex-guarded-bash.sh`，讓 `git commit -m`
  與 `git commit -F` 的可攔截 path 都會先跑語言 gate。
- 補上 PR author language、PR description fallback、workspace language fallback、
  conventional commit structural token 排除的 self-test。

## [3.73.58] - 2026-04-30

### Added — GitHub PR language gate

- 新增 `gate-pr-language.sh`，在 GitHub write path 送出 generated prose 前檢查
  PR title、body、comment 與 review text。
- 串接到 `polaris-pr-create.sh`、Codex PR create fallback、guarded Bash execution，
  以及 PR create/edit/comment/review hook path。
- 補上 self-test，覆蓋 zh-TW PR metadata、英文 title/body blocking，以及英文
  template headings 搭配 zh-TW prose 的合法情境。

## [3.73.57] - 2026-04-30

### Changed — refinement DP source progressive disclosure

- Moved low-frequency ticketless DP source-mode details from `refinement`
  into `refinement-dp-source-mode.md`.
- Kept source routing, DP hard rules, ownership boundaries, and `LOCKED`
  handoff checks in the primary `refinement` skill body.
- Indexed the new reference so DP/topic refinement loads detailed procedures
  only when needed.

## [3.73.56] - 2026-04-30

### Changed — mechanism registry audit reduction

- Reduced the mechanism registry priority audit to semantic judgment checks.
- Added deterministic contract pointers for script-backed artifact, delivery,
  handoff, session, and safety gates.
- Fixed DP-backed stacked task base resolution after local-extension upstream
  tasks move to `tasks/pr-release/`.

## [3.73.55] - 2026-04-30

### Fixed — workspace language inheritance

- Updated `validate-language-policy.sh` to inherit the nearest non-empty
  `language:` from parent workspace configs instead of stopping at a company
  config that does not override language.
- Added `--selftest` and self-test coverage for inherited root language,
  `language_unset`, bilingual mode, and code-heavy artifacts.

## [3.73.54] - 2026-04-30

### Fixed — ci-local coverage path mismatch false positive

- Kept Codecov patch gates passing when lcov coverage data exists under a
  fuzzy-matched path, avoiding false `coverage_path_mismatch` failures for
  prefix-stripped or suffix-matched coverage files.
- Added self-test coverage for both fuzzy path match with coverage data and
  true path mismatch without coverage data.

## [3.73.53] - 2026-04-30

### Added — parent spec closeout flow

- Added `close-parent-spec-if-complete.sh` to close parent Epic / DP specs only
  after all sibling tasks are implemented under `tasks/pr-release/`.
- Wired parent closeout into `finalize-engineering-delivery.sh` so completed
  Epic task sets can automatically update docs-viewer done state.
- Added parity coverage for the parent closeout helper and documented the
  helper-only boundary in `engineering`.

## [3.73.52] - 2026-04-30

### Changed — artifact language gate wiring

- Wired `validate-language-policy.sh` into refinement and breakdown as blocking
  gates before downstream artifacts are handed off.
- Documented language policy entry points for engineering, verify-AC, review-pr,
  and docs-sync, including advisory rollout and bilingual documentation modes.

## [3.73.51] - 2026-04-30

### Added — workspace language policy gate

- Added `validate-language-policy.sh` to enforce workspace artifact language
  policy from `workspace-config.yaml`.
- Added blocking/advisory modes plus bilingual document modes for rollout and
  README source/translation pairs.
- Added conservative paragraph detection that ignores code blocks, inline code,
  URLs, paths, CLI flags, branch names, ticket keys, and schema-style tokens.

### Changed — framework release PR boundary

- Clarified that `framework-release` is a post-workspace-PR release tail:
  engineering still owns implementation, gates, and workspace PR creation.
- Updated local extension contracts so `extension_deliverable` can supplement a
  real workspace PR deliverable for template sync / release evidence, while
  still forbidding fake PR URLs.

## [3.73.50] - 2026-04-30

### Fixed — external branch-chain anchors

- Updated branch-chain schema guidance so external dependency branches start
  the cascade chain instead of being placed after `develop`.
- Added `cascade-rebase-chain.sh` protection that treats task branches without
  a matching work order in the current task set as external anchors and skips
  rebase/push ownership.
- Documented external branch anchor examples for breakdown and branch creation
  so product tasks can base on another team's unmerged branch without taking
  ownership of it.

## [3.73.49] - 2026-04-29

### Fixed — source-aware task resolver lifecycle

- Updated task resolution to prefer canonical `jira_key` parsing while keeping
  legacy `> JIRA:` lookup as fallback.
- Added DP pseudo-task resolution coverage for released task files under
  `tasks/pr-release/`.
- Updated lifecycle helpers and engineering handoff references to use
  `work_item_id` for task identity and reserve `jira_key` for JIRA side effects.

## [3.73.48] - 2026-04-29

### Added — canonical task identity

- Added source-neutral task identity parsing with `source_type`, `source_id`,
  `work_item_id`, and nullable `jira_key` fields.
- Updated task.md validation to accept canonical DP-backed metadata with
  `JIRA: N/A` while preserving legacy `Task JIRA key` compatibility.
- Updated task schema and pipeline handoff references so DP pseudo-task IDs are
  treated as task identities rather than real JIRA keys.

## [3.73.47] - 2026-04-29

### Fixed — local extension worktree cleanup

- Updated `engineering-clean-worktree.sh` to accept
  `extension_deliverable.task_head_sha` as the delivered task head for
  local-extension workflows while preserving the existing PR deliverable path.
- Added self-test coverage for cleaning a local-extension implementation
  worktree that has no PR deliverable metadata.

## [3.73.46] - 2026-04-29

### Fixed — framework release clean-source gate

- Added a clean-source gate to `sync-to-polaris.sh --push` so release sync
  fails before template copy when the workspace source has dirty tracked
  changes.
- Added a selftest covering dirty tracked fail-fast, clean source pass,
  untracked scratch files, dry-run behavior, and non-push sync behavior.
- Updated local extension completion so repos without a declared `ci-local.sh`
  can record `ci_local: N/A` while still requiring Layer B verify evidence.

## [3.73.45] - 2026-04-29

### Added — local extension release completion

- Added `extension_deliverable` lifecycle metadata for local delivery
  extensions so DP-backed framework tasks can record real release evidence
  without fake PR URLs.
- Added local extension completion helpers that validate release metadata,
  task-head freshness, and Layer A/B evidence before task lifecycle closeout.
- Updated engineering and delivery references so portable workflows expose only
  the generic `local_extension` boundary while maintainer release details stay
  in local policy.

## [3.73.44] - 2026-04-29

### Added — refinement return inbox contract

- Added a breakdown-owned `refinement-inbox/*.md` contract so refinement
  consumes planner decisions instead of reading engineering escalation sidecars.
- Added `validate-refinement-inbox-record.sh` and wired refinement inbox
  validation into pipeline artifact gates.
- Added a refinement contract-change guard so framework workflow and handoff
  changes require an explicit proposal/confirmation path before editing skills,
  rules, hooks, or validators.

## [3.73.43] - 2026-04-29

### Fixed — template sync correction

- Re-synced the Polaris template from a clean workspace HEAD so the template
  release contains only the v3.73.42 ci-local stale mirror/cache fix and not
  unrelated local working-tree changes.

## [3.73.42] - 2026-04-29

### Fixed — ci-local stale mirror cache

- Generated `ci-local.sh` now fail-stops when source CI declarations changed
  after generation instead of warning and continuing with a stale mirror.
- Added a mirror hash to ci-local evidence and PASS cache validation so
  regenerated mirrors cannot reuse stale PASS evidence from an older CI mirror.
- Added self-test coverage for stale mirror blocking and stale cache rejection.

## [3.73.41] - 2026-04-29

### Added — product CI config read-only boundary

- Recorded the engineering decision that product-ticket delivery must treat
  repo CI declarations as read-only repo-owner policy.
- Added the boundary to the engineering authority rules, delivery flow Step 2,
  and mechanism registry canary so future CI/local-parity issues fail-stop
  instead of being fixed by modifying product repo CI settings.

## [3.73.40] - 2026-04-29

### Fixed — ci-local Codecov path parity

- Updated generated `ci-local` Codecov patch checks to fail when LCOV `SF:`
  paths only match changed files through fuzzy prefix stripping or suffix
  fallback, preventing false local passes when remote Codecov cannot map
  coverage paths to repo-relative diff paths.
- Added self-test coverage for LCOV path mismatch detection.

## [3.73.39] - 2026-04-29

### Fixed — template sync correction

- Re-synced the Polaris template from a clean workspace HEAD so the template
  release does not include unrelated local `ci-local` working-tree changes.
- Keeps v3.73.38's refinement DP docs-viewer sidebar sync change as the
  intended framework behavior.

## [3.73.38] - 2026-04-29

### Fixed — refinement DP viewer sync

- Updated the `refinement` ticketless DP flow to explicitly sync the
  docs-viewer sidebar after creating or updating DP markdown, covering
  non-Claude hook paths where new DPs otherwise would not appear at
  `http://localhost:4000/docs-viewer`.

## [3.73.37] - 2026-04-29

### Added — refinement breakdown handoff gate

- Added `refinement-handoff-gate.sh` to block `refinement` from handing off to
  `breakdown` unless the same spec container has a valid `refinement.json`.
- Added self-test coverage for missing, valid, and invalid refinement artifacts.
- Updated the refinement skill and mechanism registries so "ready for
  breakdown" now deterministically triggers the artifact handoff gate.

## [3.73.36] - 2026-04-29

### Added — engineering delivery finalizer

- Added `finalize-engineering-delivery.sh` to bind completion gate success to
  task lifecycle closeout, preventing delivered PRs from staying in active
  `tasks/` after the local gates pass.
- Updated engineering delivery flow to use the finalizer for both first-cut PRs
  and revision pushes before user-facing completion.

## [3.73.35] - 2026-04-29

### Fixed — completion gate task resolution

- Fixed `check-delivery-completion.sh` so completion freshness can resolve
  task.md files stored under the company workspace `specs/` root when `--repo`
  points at a product repo sibling.

## [3.73.34] - 2026-04-29

### Changed — local delivery extension boundary

- Changed the DP-backed direct-release design from a portable `engineering`
  maintainer lane into a generic local delivery extension boundary.
- Kept high-privilege maintainer release details in local-only policy / skills,
  while preserving engineering gates and forbidding fake PR deliverables.

## [3.73.33] - 2026-04-29

### Changed — DP-backed framework release lane

- Documented the `engineering` maintainer-release lane for DP-backed framework
  work orders that hand off to `framework-release` instead of opening product
  PRs or writing fake PR deliverables.

### Removed — design-plan skill

- Removed the deprecated `design-plan` skill after ticketless DP ownership moved
  to `refinement` and DP-backed work-order packing moved to `breakdown`.
- Routed legacy `design-plan DP-NNN` and `/design-plan DP-NNN` prompts directly
  to `refinement DP-NNN`; DP folders remain the ticketless source container.

## [3.73.32] - 2026-04-29

### Added — ci-local environment blocker classification

- Added a stdlib-only `ci-local` environment classifier for dependency install
  failures caused by DNS, timeout, TLS/proxy, auth, or private-network access.
- Generated `ci-local.sh` now records `BLOCKED_ENV` evidence for dependency
  infrastructure blockers, stops downstream checks after bootstrap blockers,
  and keeps the status blocking instead of treating it as implementation PASS.
- `ci-local-run.sh` now retries `BLOCKED_ENV` once in the same context and then
  emits a runtime-neutral `RETRY_WITH_ESCALATION` payload for Codex, Claude, or
  human-shell adapters.

## [3.73.31] - 2026-04-29

### Changed — design-plan shim cleanup

- Reduced `design-plan` to a compatibility shim for legacy `/design-plan DP-NNN`
  prompts; new non-ticket design discussions now route to `refinement`
  ticketless mode.
- Updated skill routing, learning handoff copy, README, Chinese trigger docs,
  and design-decision mechanisms so `refinement` owns DP research and decision
  capture while `breakdown` owns DP-backed work-order packing.

## [3.73.30] - 2026-04-29

### Added — ticketless DP pipeline source model

- Added a shared spec source resolver reference for JIRA, DP, topic, and
  artifact-path inputs, including DP locator rules and section ownership.
- Extended refinement with ticketless / DP source mode so non-ticket design
  discussions can produce DP-backed `refinement.md` and `refinement.json`
  artifacts without writing to JIRA.
- Extended breakdown with DP intake so locked design plans can be packed into
  DP-backed `tasks/T*.md` work orders, and turned design-plan into a
  compatibility shim for the refinement-led pipeline.

## [3.73.29] - 2026-04-29

### Added — DP-backed framework work orders

- Added DP-backed task resolution so framework design plans can produce
  engineering-consumable work orders under
  `specs/design-plans/DP-NNN-*/tasks/T*.md`.
- Extended branch reverse lookup, task validation, completion freshness, and
  lifecycle move-first helpers to support `DP-NNN-Tn` pseudo task identities.
- Documented the shared task.md schema for DP tasks and product tasks, and
  added the framework repo PR template copied from `exampleco-b2c-web`.

## [3.73.28] - 2026-04-28

### Fixed — runtime env startup and coverage evidence

- Routed runtime verification env startup through the actual checkout/worktree
  path and kept dependency cwd inference anchored at the company base.
- Treated docker-tagged dependencies as healthy when their declared health-check
  port is listening, and allowed one-shot start commands that exit 0 to count as
  completed startup.
- Refined the ci-local empty-coverage safety net so matched files with lcov data
  are not mistaken for missing coverage output when patch lines are not
  instrumented.

## [3.73.27] - 2026-04-28

### Fixed — template release hygiene

- Corrected the Polaris template sync after v3.73.26 so unrelated local script
  edits are not included in the published template release.

## [3.73.26] - 2026-04-28

### Fixed — engineering duplicate branch guard

- Made `engineering-branch-setup.sh` fail before creating refs when the same
  task already has a local branch, remote branch, or stale engineering worktree.
- Kept exact local branch retries resumable while blocking remote-only task
  branches that would otherwise fork a second first-cut from the base branch.
- Documented the duplicate work guard in the engineering skill so agents must
  resume, enter revision, or clean stale state instead of opening another branch.

## [3.73.25] - 2026-04-28

### Fixed — engineering worktree cleanup

- Added `engineering-clean-worktree.sh`, a guarded cleanup helper that removes
  delivered implementation worktrees only when they are registered, under
  `.worktrees/`, clean, and aligned with `deliverable.head_sha`.
- Updated engineering delivery Step 8.6 to call the helper instead of relying on
  manual `git worktree remove` path memory.
- Made the helper add `.worktrees/` to the main checkout exclude file so
  product worktree folders do not keep polluting `git status`.

## [3.73.24] - 2026-04-28

### Fixed — ci-local stacked PR coverage base

- Made generated `ci-local.sh` compute Codecov patch coverage against the
  resolved PR base branch instead of defaulting to `develop`/`main`.
- Added event/base/source/ref context to ci-local evidence cache keys so the
  same head SHA cannot reuse a PASS result from the wrong PR base.
- Routed `ci-local-run.sh` and CI gates through task.md base resolution, keeping
  hook fallback behavior aligned with engineering's stacked-branch workflow.

## [3.73.23] - 2026-04-28

### Fixed — engineering handbook and Codecov blockers

- Required engineering to read the company handbook index and all linked child
  documents before repo handbook consumption in first-cut, revision, and batch
  dispatch paths.
- Added a mechanism canary that treats incomplete company/repo handbook loading
  as drift for implementation agents.
- Made failed `codecov/patch` checks explicit CI blockers in engineering
  revision mode, even when Codecov also shows author activation or member
  visibility messages.

## [3.73.22] - 2026-04-28

### Fixed — task.md test command guidance

- Replaced invalid `pnpm -C apps/main vitest run` task.md examples with
  `pnpm --dir apps/main exec vitest run`, matching pnpm's executable invocation
  semantics for monorepo app directories.
- Clarified that task.md `## Test Command` is project-specific output from
  workspace config or repo guidance, not a fixed schema value.
- Updated the task parser self-test fixture so future checks no longer encode
  the invalid command form.

## [3.73.21] - 2026-04-28

### Changed — PR body language policy

- Required PR body prose to follow the root `workspace-config.yaml` `language`
  value before falling back to the user's language.
- Clarified that code identifiers, commands, file paths, package names, and
  official product terms keep their original spelling while explanatory prose
  follows the configured language.

## [3.73.20] - 2026-04-28

### Fixed — PR body template enforcement

- Added `gate-pr-body-template.sh` to block PR creation when a repo PR template
  exists but the supplied PR body does not preserve its `##` headings.
- Wired the gate into `polaris-pr-create.sh`, alongside existing base,
  evidence, CI, title, and changeset gates.
- Updated engineering PR body guidance to prefer `--body-file`, preventing
  shell quoting from escaping Markdown inline code/backticks.

## [3.73.19] - 2026-04-28

### Fixed — revision inline reply enforcement

- Updated engineering revision mode to collect GitHub review thread state in
  addition to flat pull request comments, so unresolved, non-outdated inline
  threads are handled explicitly.
- Required every fixed code-drift root inline comment to receive an inline
  reply through GitHub's review comment reply endpoint.
- Added a hard inline reply verification gate before completion: pushed commits
  or PR summary comments no longer count as replying to fixed inline feedback.

## [3.73.18] - 2026-04-28

### Fixed — revision-mode changeset gate hardening

- For products using repository-level changesets, added a workflow hardening note:
  PR checks from Codecov about activation/permission visibility must not be treated
  as an unblock reason by itself; PR quality decisions must rely on actual CI
  pass/fail results.

## [3.73.17] - 2026-04-28

### Fixed — legacy hook wrapper retirement

- Removed retired Claude Code L1 hook wrappers for carry-forward fallback,
  command-splitting checks, consecutive-read tracking, and file reread tracking.
- Updated active deterministic hook registries and Copilot/Codex references so
  current wiring no longer points at retired hook files.
- Kept reusable compatibility scripts available for manual/Copilot diagnostics
  and relaxed build-level verify preparation when repo prep primitives are
  absent.

## [3.73.16] - 2026-04-28

### Changed — engineering task-only work orders

- Removed engineering's legacy `specs/{TICKET}/plan.md` fallback; work orders
  must now be `specs/{EPIC}/tasks/T*.md` or `tasks/pr-release/T*.md`.
- Made PR revision rebase fail loud when no task.md maps to the branch instead
  of falling back to the PR base branch.
- Updated the engineering skill and resolver self-test to enforce task-only
  resolution for JIRA keys, PR URLs, and current-branch entry.
- Fixed `sync-to-polaris.sh` so releases can run from a clean framework
  worktree with no company directories.

## [3.73.15] - 2026-04-28

### Changed — task lifecycle folder naming

- Renamed completed task work-order storage from `tasks/complete/` to
  `tasks/pr-release/`, reflecting that engineering completion means a PR has
  been opened and the work is waiting for release.
- Updated engineering, breakdown, verify-AC, task schema references, resolver
  helpers, parser fallback, artifact gates, and task validators to use the new
  `pr-release/` lifecycle folder.
- Kept active task validation strict while preserving reader fallback for
  downstream dependency resolution across released-to-PR tasks.

## [3.73.14] - 2026-04-28

### Fixed — engineering delivery metadata gates

- Added deterministic Developer PR title and task changeset gates to PR
  creation and completion checks, so title naming and changeset deliverables are
  validated before engineering reports completion.
- Made changeset handling activate only when a repo has
  `.changeset/config.json`; repos without Changesets now skip creation and
  checks instead of being inferred from an incidental directory.
- Added repo-specific Developer PR title templates under
  `projects[].delivery.pr_title.developer` in company workspace config, with
  `[{TICKET}] {summary}` as the fallback.
- Improved changeset derivation for monorepos by supporting explicit `--repo`,
  check-only mode, private package tagging, and Allowed Files based package
  narrowing.
- Treated generated `.changeset/*.md` files as engineering delivery metadata in
  scope checks and applied Codecov global ignores to discovered flag gates.

## [3.73.13] - 2026-04-28

### Changed — worktree cleanup lifecycle

- Clarified that implementation worktrees are removed after PR creation or PR
  branch push once evidence and deliverables are recorded; PR revisions must
  recreate a fresh worktree from the current PR branch/head.
- Added an explicit engineering delivery cleanup step and required
  verification-only worktrees to be removed immediately after results, logs, or
  evidence are captured.

## [3.73.12] - 2026-04-28

### Added — run-verify worktree backlog item

- Added a Polaris backlog item for `run-verify-command.sh` resolving sibling
  worktree tasks back to the main checkout, which can produce evidence for the
  wrong HEAD and block completion gates.

## [3.73.11] - 2026-04-28

### Fixed — ci-local CI-like timezone

- Generated `ci-local.sh` now executes mirrored CI commands with `CI=true`
  and `TZ=UTC` by default, matching common CI container behavior instead of
  inheriting the developer machine timezone.
- Added `CI_LOCAL_CI` and `CI_LOCAL_TZ` overrides for repos that intentionally
  need a different local mirror environment.
- Recorded the effective command environment in ci-local evidence and added
  selftest coverage for the generated UTC runner.

## [3.73.10] - 2026-04-28

### Fixed — ci-local Woodpecker branch conditions

- `ci-contract-discover.sh` now preserves Woodpecker `when.event`,
  `when.branch`, `when.ref`, and `when.status` metadata for discovered checks.
- Generated `ci-local.sh` evaluates runtime context (`event`, base branch,
  source branch, and ref) before running each check, recording excluded checks
  as `SKIP` evidence instead of over-enforcing jobs that online CI would not
  select.
- Added selftest coverage for `when.branch: [develop, rc]` so feature-branch
  PR bases skip those checks while develop-targeted runs still execute them.

## [3.73.9] - 2026-04-27

### Added — branch chain cascade rebase

- Added task.md `Branch chain` support so breakdown records the full rebase
  path, such as `develop -> feat/EPIC-478-... -> task/KB2CW-...`.
- Added `resolve-branch-chain.sh` and `cascade-rebase-chain.sh` so engineering
  can deterministically rebase the chain from upstream to downstream before
  first-cut branch setup or revision work.
- Updated `engineering-branch-setup.sh`, `revision-rebase.sh`, task.md parsing,
  and branch references so PR base still comes from `Base branch` via
  `resolve-task-base.sh`, while `Branch chain` only controls rebase order.

## [3.73.8] - 2026-04-27

### Changed — engineering local completion authority

- Clarified that `engineering` completion is governed by local LLM gates and
  mechanical evidence gates: `ci-local.sh`, `run-verify-command.sh`, VR when
  triggered, evidence AND gate, and completion gate.
- Remote repo CI in queued / pending / running state no longer blocks
  user-facing completion. A remote check only becomes a revision signal after it
  has completed and clearly failed.
- Removed `framework-release` from the shared Polaris framework skill catalog.
  Release orchestration remains an operator-local skill under the agent home,
  not a template-facing workflow shipped to downstream workspaces.

## [3.73.7] - 2026-04-27

### Fixed — `resolve-task-base.sh` complete/ fallback

- `find_task_md_by_jira` now searches `tasks/T*.md` first then
  `tasks/complete/T*.md`, completing the DP-033 D8 fallback so revision-rebase
  works after `mark-spec-implemented.sh` move-first archives an upstream task.
- Without this, any downstream task whose `depends_on` points to a completed
  upstream errored out with `cannot find upstream task.md for JIRA key …`,
  blocking `revision-rebase.sh` and `engineering` revision mode for stacked
  Epics (e.g. EPIC-478 T3b/T3c/T3d once T3a was archived).
- Added selftest case 9 covering the upstream-in-complete/ path; full suite
  now 9/9 green.

## [3.73.6] - 2026-04-27

### Added — framework release skill

- Added `framework-release` as a shared Polaris skill so release requests route
  through the full workspace commit, push, template sync, tag, GitHub release,
  account restoration, and final verification chain.
- Synced the new skill into the Claude-side source layout and documented it in
  README customization guidance and Chinese trigger references.
- Updated public skill counts from 26 to 27 and verified Claude/Codex skill
  parity through the repo-level `.agents/skills` symlink.

## [3.73.5] - 2026-04-27

### Fixed — engineering lifecycle write-back boundary

- Clarified that `engineering` may not directly edit `task.md`, and may never
  alter planner-owned fields such as `Allowed Files`, estimates, test commands,
  verify commands, test environment, or `depends_on`.
- Preserved required delivery lifecycle write-back by allowing only approved
  helper scripts to update execution-owned metadata: `write-deliverable.sh` for
  `deliverable.*`, `mark-spec-implemented.sh` for `status: IMPLEMENTED`, and
  transition helpers for `jira_transition_log[]`.
- Tightened the DP-044 escalation halt rule so once engineering enters the
  sidecar handoff path, it performs no delivery lifecycle write-back, push, or
  PR creation.

## [3.73.4] - 2026-04-27

### Fixed — worktree gitignored framework artifact resolution

- Updated `engineering` so worktree sessions resolve the repo main checkout
  before reading the repo handbook, instead of assuming
  `{worktree}/.claude/rules/handbook/` exists.
- Clarified that Local CI mirror execution in worktrees must go through
  `scripts/ci-local-run.sh --repo <worktree>`, which dispatches to the
  canonical main-checkout `.claude/scripts/ci-local.sh`.
- Extended `worktree-dispatch-paths.md` to include repo handbooks and
  canonical `ci-local.sh` as gitignored main-checkout artifacts.

## [3.73.3] - 2026-04-27

### Fixed — breakdown escalation intake closure gate

- Added `scripts/validate-breakdown-escalation-intake.sh`, a breakdown-side hard
  gate that validates planner decisions before task.md edits, JIRA writes, or
  `processed: true` sidecar marking.
- Blocks routing a scope-escalation sidecar back to engineering when the
  sidecar's `Closure Forecast` says the proposed fix is insufficient and the
  breakdown decision does not explicitly handle residual baseline/env decisions.
- Updated `breakdown` E4 so scope-escalation intake must pass the new gate
  before landing any planner-owned changes.

## [3.73.2] - 2026-04-27

### Fixed — DP-044 gate-closure escalation

- Reframed engineering scope escalation around mandatory gate closure instead of
  first out-of-scope files. Engineering sidecars must now state pass condition,
  baseline/actual measurements, explained deltas, proposed fixes, residual
  blockers, closure forecast, and the full set of planner decisions required to
  make the failed gate pass.
- Updated `engineering` to challenge necessary-but-insufficient scope approvals:
  if approving only one candidate fix still leaves the gate failing, the sidecar
  must say so before routing to breakdown.
- Updated `breakdown` intake to consume gate-closure sections and handle all
  required planner decisions in one preview; it may not return a work order to
  engineering when the closure forecast still says the gate will fail.
- Strengthened `validate-escalation-sidecar.sh` so old first-file sidecars fail
  schema validation unless they include `Gate Closure`, `Current Measurement`,
  `Explained Delta`, `Proposed Fixes`, `Residual Blockers`,
  `Closure Forecast`, and `Required Planner Decisions`.
- Updated `escalation-flavor-guide.md` and `mechanism-registry.md` with the new
  gate-closure canary.

## [3.73.1] - 2026-04-27

### Changed — breakdown CI gate scope triage

- Added a breakdown-only CI gate scope triage note to the scope-escalation
  intake path: CI failures are blockers; breakdown decides ownership of the
  fix, not whether CI can be ignored.
- Clarified that small mechanical gate unblocks with no independent delivery or
  acceptance value should be re-classified as `plan-defect` and folded into the
  original task.md Allowed Files instead of creating a new task.

## [3.73.0] - 2026-04-27

### Added — Engineering scope-escalation handoff (DP-044)

Closes the longstanding pipeline gap where `engineering` discovers mid-task that
the planned scope is wrong but has no deterministic way to return to planning.
Without this, scope blockers ended either as ad-hoc "edit task.md and continue"
(silent scope expansion) or unstructured user-mediated handoff.

- **Sidecar evidence** — engineering halts when a mechanical gate fails on files
  outside `Allowed Files` AND the fix would alter planner-owned fields. Writes
  evidence to `specs/{EPIC}/escalations/T{n}-{count}.md` (D2, D7); never edits
  `task.md` from inside engineering.
- **Flavor classification** (D4) — engineering proposes `plan-defect`,
  `scope-drift`, or `env-drift` as a hint; breakdown re-classifies if evidence
  contradicts and must log `accepted flavor: X` or `re-classified to Y: reason`.
- **Lineage cap = 2** (D5) — third escalation routes to `refinement`, not
  another `breakdown` cycle. Validator blocks `escalation_count > 2`.
- **Breakdown intake path** — new top-level path in `skills/breakdown/SKILL.md`
  consumes the sidecar, reuses Planning Path's user-confirmation gate, marks
  sidecar `processed: true` post-confirm.
- **Engineering halt step** — new sub-section in `skills/engineering/SKILL.md`
  under "## 開發中 Scope 追加"; reuses `scripts/snapshot-scrub.py` for evidence.
- **Validator** — `scripts/validate-escalation-sidecar.sh` checks frontmatter
  (flavor enum, count ∈ {1,2}), 20KB body cap, lineage cap; `--self-test` mode
  for local validation.
- **Flavor decision tree** — `skills/references/escalation-flavor-guide.md`
  with worked examples (incl. EPIC-478 T3a / KkStorage.ts as `env-drift` case).
- **Mechanism registry** — 3 new entries (`engineering-escalation-sidecar-only`
  Critical, `escalation-count-cap` High, `breakdown-escalation-intake` Medium).

Design plan: `specs/design-plans/DP-044-engineering-scope-escalation-handoff/plan.md`
(status `IMPLEMENTING` pending dogfood).

## [3.72.2] - 2026-04-27

### Changed — mechanism-registry.md slimmed (~−18% bytes)

`rules/mechanism-registry.md` is loaded into every conversation via the auto rule
loader, so its size translates directly into token cost on every turn. This pass
removes redirect cruft and compresses the longest Rule cells without dropping
any canary signals.

- **Removed** 6 "Common Rationalizations" stub sections (each was 3 lines that
  only said "See `mechanism-rationalizations.md` § X"). Replaced with a single
  top-of-file pointer in § How to Use.
- **Removed** 4 "已畢業至 deterministic" callout blockquotes — the graduated
  mechanisms are documented in `deterministic-hooks-registry.md`; the inline
  callouts were duplicate notes.
- **Compressed** the Deterministic Quality Hooks section header (7 lines → 3),
  Pipeline Artifact Schema intro (lines 88/98–100 boilerplate consolidated),
  and Priority Audit Order tail (#9–12 collapsed to one line).
- **Compressed** ~14 verbose Rule cells (200–700 chars each) down to their
  essence. Largest reductions: `engineering-consume-depends-on` (~700 → ~250),
  `spec-status-mark-on-done` (~450 → ~200), `tdd-bypass-no-assertion-weakening`
  (~400 → ~200), `breakdown-step14-no-checkout`, `revision-r5-mandatory`,
  `cross-session-warm-folder-scan`. Implementation details (writer assignments,
  helper script paths, DP source pointers) moved to `(source: ...)` headers or
  the corresponding source files. Canary Signal column untouched — post-task
  audit observability is unchanged.

Net: 294 → 249 lines (−15%), 42754 → 35208 bytes (−18%).

## [3.72.1] - 2026-04-27

### Fixed — ci-local.sh now cross-worktree (DP-043 follow-up)

DP-043 v3.72.0 relocated `ci-local.sh` to `<repo>/.claude/scripts/` but kept a
"per-checkout materialized" model. From inside a `git worktree`, the generated
script would either be missing (triggering regeneration on every engineering
run) or — if invoked from main checkout — operate on the wrong branch because
`git rev-parse --show-toplevel` resolves to the script's physical location, not
the target worktree. Net effect: every worktree-based `/engineering` run
re-generated `ci-local.sh`, defeating the cache and confusing evidence files.

The fix consolidates the cross-worktree resolution into a single helper and
adds `--repo` support to the generated script, so the same canonical
`ci-local.sh` (in main checkout) serves every worktree of the same repo.

- **New — `scripts/lib/main-checkout.sh`**: shared `resolve_main_checkout`
  helper. Single source of truth for "given a path inside a worktree, return
  the main checkout". Three places that previously duplicated the
  `git rev-parse --git-common-dir` logic (`polaris-jira-transition.sh`,
  `resolve-task-md.sh`, `resolve-task-md-by-branch.sh`) now source this helper.
- **`scripts/lib/ci-local-path.sh`** — added `ci_local_canonical_path` helper
  (builds on `resolve_main_checkout`).
- **`scripts/ci-local-generate.sh`** — generated script accepts `--repo <path>`
  flag. When provided, the script operates on `<path>` instead of its physical
  location's toplevel. Legacy auto-detect retained as fallback.
- **New — `scripts/ci-local-run.sh`**: wrapper that resolves canonical script
  path + invokes with `--repo $PWD`. This is what `engineer-delivery-flow`
  Step 2 now calls — keeps the doc instruction simple.
- **`.claude/hooks/ci-local-gate.sh`** — uses canonical resolution via
  `resolve_main_checkout`, invokes the canonical script with `--repo
<target>`. Worktree-local script path retained as legacy fallback.
- **`skills/references/engineer-delivery-flow.md`** — Step 2 now uses
  `${POLARIS_ROOT}/scripts/ci-local-run.sh`. Existence invariant updated to
  mention "main checkout" canonical script (shared across worktrees).
- **`.claude/rules/sub-agent-delegation.md`** — gitignored framework artifacts
  policy now includes `.claude/scripts/ci-local.sh` alongside
  `specs/{EPIC}/` and `.claude/skills/`.
- **`scripts/ci-local-generate-selftest.sh`** — added Test 7 (4 assertions on
  `--repo` flag): generator exit, `--help` mentions `--repo`, `--repo`
  invocation produces evidence with target repo's HEAD SHA, bad `--repo`
  exits 2.

**Result**: LLM running `/engineering` Step 2 from a worktree automatically
hits the main-checkout canonical script + operates on `--repo <worktree>`.
Zero regeneration, zero behavioral burden on the LLM.

**Edge case**: feature branch modifying CI config → canonical script becomes
stale relative to that branch. Generated script's existing staleness advisory
warns (does not block); explicit regeneration via `ci-local-generate.sh
--repo <worktree>` updates the canonical when needed. Rare in practice.

**Selftest**: 59/59 + 21/21 PASS (`ci-local-generate-selftest.sh` and
`verification-evidence-gate-selftest.sh`).

**Plan**: `specs/design-plans/DP-043-ci-local-relocation/plan.md` § Follow-up.

## [3.72.0] - 2026-04-27

### Breaking — ci-local.sh relocated to `.claude/scripts/`

`ci-local.sh` (the framework-generated Local CI Mirror) now lives at
`<repo>/.claude/scripts/ci-local.sh` instead of `<repo>/scripts/ci-local.sh`.
The old path is no longer read or written by any framework script. Existing
files at the old path are inert orphans — `rm` them by hand. Nobody was
consuming the old mechanism in production yet, so this is a clean cut without
a migration window.

- **`<repo>/scripts/` was a repo source tree path** that risked accidental
  commits — the file was untracked but never declared in `.gitignore`. The new
  `<repo>/.claude/scripts/` location follows the same "framework auxiliary
  artifact under `.claude/`" convention as the auto-generated handbook
  (`.claude/rules/handbook/`).
- **No `.gitignore` changes** in any product repo. `ci-local-generate.sh` now
  writes a per-clone `.git/info/exclude` entry when generating the file
  (same mechanism as `ai_files_mode: "local"`). Top principle: don't affect the
  product repo's tracked state.
- **New file — `scripts/lib/ci-local-path.sh`**: single source of truth for
  the path. Exposes `CI_LOCAL_RELATIVE_PATH` constant and
  `ci_local_path_for_repo <repo_root>` helper. Generator, gate
  (`scripts/gates/gate-ci-local.sh`), hook (`.claude/hooks/ci-local-gate.sh`),
  and `verification-evidence-gate.sh` all source this — no other place
  hardcodes the path.
- **Generator updates**: default `--out` resolves through the helper; the
  generated `ci-local.sh`'s `REPO_ROOT` detection now uses
  `git rev-parse --show-toplevel` (with a `../..` fallback) instead of the
  position-bound `cd .. && pwd`. The generated script no longer breaks if
  relocated again.
- **References updated**: `engineer-delivery-flow.md`, `tdd-loop.md`,
  `mechanism-rationalizations.md`, `deterministic-hooks-registry.md`,
  `engineering/SKILL.md`, `transpile-to-copilot.sh`, and the regenerated
  `.github/copilot-instructions.md`. `grep -rn "scripts/ci-local\.sh"` no
  longer matches the old path in tracked source.
- **Selftests**: `ci-local-generate-selftest.sh` 54/54 PASS,
  `verification-evidence-gate-selftest.sh` 21/21 PASS. Dogfood against
  `exampleco-b2c-web` confirmed: new file landed under `.claude/scripts/`,
  `.git/info/exclude` entry written, `git status` clean, old file removed.

Canonical record: `specs/design-plans/DP-043-ci-local-relocation/plan.md`.

## [3.71.2] - 2026-04-27

### Change — entry resolution made harder to bypass in engineering

This patch closes the failure mode where an agent successfully resolved the
authoritative work order, then overrode it with an ad-hoc manual search over
`specs/**/tasks`, producing a false "work order not found" conclusion.

- **`scripts/resolve-task-md.sh` now supports authoritative session locks**:
  `--write-lock` records the resolved work order in `/tmp/polaris-work-order-lock-*.json`,
  and `--clear-lock` explicitly discards that authority when needed.
- **New Claude Code Bash guard — `.claude/hooks/no-manual-work-order-search.sh`**:
  once a fresh resolver lock exists, ad-hoc `find` / `rg` / `grep` / `fd`
  searches over `specs/**/tasks` / `plan.md` are blocked so a human-crafted
  fallback cannot silently override the resolver result.
- **Engineering skill wiring**: `.claude/skills/engineering/SKILL.md` now
  requires `resolve-task-md.sh --write-lock ...` for Entry Resolution and states
  that resolver success is authoritative until the lock is explicitly cleared.

## [3.71.1] - 2026-04-27

### Change — engineering D1/D7/D16 follow-up hardening

This patch does not close DP-032, but it makes `engineering` materially more
usable than the prior revision by landing the missing consumer-side primitives
that the rewritten skill now depends on.

- **New script — `scripts/resolve-task-md.sh`**: implements DP-032 D1 entry
  resolution as a real resolver instead of prose. Supports direct work-order
  path, JIRA key, PR URL / number, `--current`, and `--from-input`, with
  workspace-aware lookup across nested `*/specs/*/tasks/*.md`,
  `tasks/complete/`, and legacy `specs/{TICKET}/plan.md`.
- **Engineering skill wiring**: `.claude/skills/engineering/SKILL.md` now
  points its entry-resolution contract at `resolve-task-md.sh`, adds an
  explicit `Authority Boundary` section, and rewires first-cut resolution to a
  script-first flow instead of hand-rolled grep / gh lookup logic.
- **New reference — `.claude/skills/references/tdd-loop.md`**: lands the D7
  consumer-side TDD reference so engineering no longer depends on `unit-test`
  skill frontmatter for its default red-green-refactor loop. The `unit-test`
  skill itself is not sunset yet; this is partial D7 progress, not full close.
- **New hook — `.claude/hooks/no-direct-evidence-write.sh`**: lands the D16
  direct-write block for evidence JSON files and registers it in
  `.claude/settings.json` `PreToolUse` for `Write` / `Edit`. The pattern set
  covers verify, ci-local, and VR evidence paths.
- **Branch reverse-lookup fix**: `scripts/resolve-task-md-by-branch.sh` was
  fixed so the new resolver's branch-based paths no longer fail on valid task
  branches.

## [3.71.0] - 2026-04-27

### Add — completion gate + deterministic dependency hydration for engineering delivery

Engineering already hard-gated commit / push / PR via portable scripts, but an
agent could still claim "done" before touching those exits. This release adds a
completion-time hard gate so user-facing completion reports now reuse the same
delivery evidence invariants as git/PR actions.

- **New script — `scripts/check-delivery-completion.sh`**: a completion-time
  gate that reuses portable delivery checks before any "done / deliverable /
  complete" report. It always runs Layer A via `scripts/gates/gate-ci-local.sh`
  when repo root contains `scripts/ci-local.sh`, and for Developer flows also
  runs Layer B via `scripts/gates/gate-evidence.sh`. No new bypass env var was
  introduced.
- **Existence invariant promoted to explicit rule**: `.claude/skills/engineering/SKILL.md`
  and `.claude/skills/references/engineer-delivery-flow.md` now state that repo
  root `scripts/ci-local.sh` means "required" regardless of git tracking state
  (`tracked` / `untracked` / generated all count). The decision is file-existence
  based, not git-status based.
- **New delivery-flow step — Step 8.5 Completion Gate**: the shared
  `engineer-delivery-flow.md` backbone now inserts a pre-report hard gate after
  JIRA/IMPLEMENTED bookkeeping and before any user-facing completion report.
  This complements Step 7a Evidence AND Gate: Step 7a means "cannot open PR";
  Step 8.5 means "cannot mouth-complete".
- **Engineering skill wiring**: `engineering/SKILL.md` now requires
  `check-delivery-completion.sh` before writing completion output, both in
  first-cut and revision-mode descriptions.
- **New script — `scripts/env/install-project-deps.sh`**: resolves the project
  from `--task-md` / `--project`, prefers
  `workspace-config.yaml -> projects[].dev_environment.install_command`, and
  falls back to lockfile / manifest detection (`pnpm-lock.yaml` → `pnpm install
--frozen-lockfile`, `package-lock.json` → `npm ci`, `requirements.txt` →
  `python3 -m pip install -r ...`, etc.). It emits JSON evidence and fails
  loudly on real install failures.
- **Runtime orchestrator wiring**: `scripts/start-test-env.sh` now chains
  `ensure-dependencies → install-project-deps → start-command → health-check →
[fixtures-start]`, so runtime verification in a fresh worktree hydrates the
  project before boot.
- **Engineering contract update**: `engineering/SKILL.md` now requires
  `install-project-deps.sh` before any test / build / dev-server command in a
  worktree or fresh checkout. "Install deps first" is no longer an LLM memory
  heuristic.
- **Workspace config schema**: `projects[].dev_environment.install_command` is
  now documented in the config reader and seeded in ExampleCo workspace examples for
  pnpm repos.

## [3.70.1] - 2026-04-27

### Change — framework handbook moved under rules/

- Relocated the framework handbook into `.claude/rules/` so shared framework
  guidance follows the same source-of-truth layout as the rest of the rule
  stack.

## [3.70.0] - 2026-04-27

### Add — Codex skill source-of-truth hardening

Shared skill authoring now uses a single source-of-truth layout: `.claude/skills/`
is primary and `.agents/skills` is required to be a symlink to it. This removes
copy-mirror drift between Claude- and Codex-facing skill paths and promotes the
constraint into framework rules, parity checks, and sync flows.

- **New L1 rule** — `.claude/rules/cross-llm-skill-source-of-truth.md` defines
  `.claude/skills/` as the only authoring surface for shared skills, requires
  `.agents/skills -> ../.claude/skills`, and documents Windows / `core.symlinks=false`
  recovery steps.
- **New guard** — `scripts/check-skills-mirror-mode.sh` validates symlink mode and
  is enforced first by `scripts/verify-cross-llm-parity.sh`.
- **Doctor / parity updates** — `scripts/polaris-codex-doctor.sh` now follows symlinks
  when counting skill dirs; `scripts/mechanism-parity.sh` understands symlink mode and
  warns when a copied mirror is used as degraded fallback.
- **Sync flow updates** — `scripts/sync-to-polaris.sh` now syncs the `.agents/skills`
  symlink and `.codex/` generated outputs; `scripts/sync-from-polaris.sh` rebuilds the
  symlink mirror via `sync-skills-cross-runtime.sh --to-agents --link` before parity checks.
- **Codex fallback gate fix** — `scripts/codex-mark-design-plan-implemented.sh` now
  builds a structurally valid synthetic Write payload for the checklist gate before
  rewriting frontmatter on disk.
- **Docs** — `docs/codex-quick-start.md` and `docs/codex-quick-start.zh-TW.md` now
  document symlink mode as the recommended Codex setup and link Windows/platform notes.

## [3.65.0] - 2026-04-26

### Add — `scripts/revision-rebase.sh`: deterministic engineering revision R0

Backlog Roadmap item #3 closed. The four inline bash steps that opened
`engineering/SKILL.md § Revision Mode R0` (locate task.md → resolve base →
fetch + rebase → PR base sync) are extracted into a single deterministic
script that engineering revision-mode now calls as its first step. Removes
the "AI must remember to do this" failure mode that surfaced in the
TASK-2863 revision session.

- **`scripts/revision-rebase.sh`** — pure deterministic R0 automation.
  Defaults derive from cwd via `git rev-parse --show-toplevel` +
  `resolve-task-md-by-branch.sh --current` + `gh pr view --json
number,baseRefName`; all overridable via `--repo` / `--task-md` / `--pr`.
  Internally chains: resolve task.md → `resolve-task-base.sh` → `git
fetch origin` → `git rebase origin/<RESOLVED_BASE>` → PR base sync via
  `gh pr edit --base` (only when `pr.baseRefName ≠ RESOLVED_BASE`). Emits
  JSON evidence on stdout (`task_md` / `resolved_base` / `rebase_status` /
  `pr_base_synced` / `legacy_fallback` / `writer` / `at`). Exit
  contract: 0 = clean rebase + PR base aligned; 1 = conflict / fetch
  failure / PR base edit blocked (leaves git in rebase-in-progress with
  explicit abort advisory — does NOT auto-abort, since R0 spec is
  "stop, report, manual handle"); 2 = usage error. **No bypass env
  var**.

- **Legacy PR fallback** — if no task.md is found for the current
  branch, the script falls back to `gh pr view --json baseRefName` for
  the rebase target but **skips** the PR base sync step (no
  source-of-truth to compare against). `legacy_fallback: true` in the
  evidence + stderr advisory.

- **`scripts/revision-rebase-selftest.sh`** — 52/52 PASS. Each case
  builds an isolated tmp repo + bare origin to prevent state bleed,
  uses fake `gh` binary (FAKE_GH_PR_VIEW + FAKE_GH_LOG env vars) to
  stub `gh pr view --json` and capture `gh pr edit` invocations.

- **`engineering/SKILL.md § R0`** — replaced 24 lines of inline bash
  with a single `${CLAUDE_PROJECT_DIR}/scripts/revision-rebase.sh` call.
  Preserves the `pr-base-gate.sh` hook note and adds explicit legacy
  fallback semantics. `.agents/` mirror synced.

- **`.claude/polaris-backlog.md` item #3** marked `[x]` per the
  `繼續 polaris` standing-trigger contract.

## [3.64.0] - 2026-04-26

### Add — Cross-session warm-folder scan deterministic backup

Closes Roadmap to Done item #2 (`polaris-backlog.md`) — the cross-session
continuity rule in `CLAUDE.md` is now backed by a deterministic
UserPromptSubmit hook that surfaces memory matches across **all tiers**
(Hot flat root + Warm `{topic}/` folders + Cold `archive/`) when the user
types `繼續 X` / `continue X`.

- **`.claude/hooks/cross-session-warm-scan.sh`** (new) — UserPromptSubmit
  hook. Detects the trigger pattern, extracts up to 3 keywords (JIRA
  keys + alphanumeric tokens ≥ 3 chars, stop-word filtered), strips
  leading verb particles (`繼續做 TASK-3711` → `TASK-3711`), and
  recursively `find -iname '*{kw}*.md'` against the memory directory.
  Dash-normalized matching handles JIRA keys vs filename convention
  (`EPIC-478` matches `project_gt478_*.md`). Top-level `MEMORY.md` index
  is excluded from results (it's a pointer, not content). Caps at 3
  keywords × 8 files each to avoid noise on rich prompts. Memory dir
  path overridable via `POLARIS_MEMORY_DIR` for selftests. Memory dir
  absent → silent skip. Stdout injected as advisory; never blocks.

- **`scripts/cross-session-warm-scan-selftest.sh`** (new) — 23
  assertions covering zero-input forms (silent), keyword extraction,
  dash normalization across both JIRA-key and filename variants, multi-
  keyword caps, stop-word filtering, malformed JSON handling, fallback
  `prompt` field, `archive/` Cold tier surfacing, and missing-memory-dir
  silent skip. All 23 PASS.

- **`CLAUDE.md` § Cross-Session Continuity** — step 1 expanded into 3
  ordered steps: (1) MEMORY.md Hot index, (2) explicit Warm topic
  folder scan with `Read {topic}/index.md`, (3) recursive
  `find {memory_dir} -type f -iname '*{keyword}*.md'`. Explicitly
  rejects `ls memory/ | grep` as the only search method. Mentions the
  hook output as authoritative when injected. Plan vs memory 分工 line
  added (plan = decisions, memory = session handoff — both must be
  read).

- **`rules/mechanism-registry.md`** — new canary
  `cross-session-warm-folder-scan` (Medium drift) under § Cross-Session
  Continuity, pointing to the hook as deterministic backup.

- **`skills/references/deterministic-hooks-registry.md`** — hook
  registered with full enforcement spec (UserPromptSubmit advisory
  posture, dash normalization rules, override env var, selftest path).

- **`~/.claude/settings.json`** — UserPromptSubmit event added with
  `*` matcher pointing at the new hook script.

**Trigger fix:** the `繼續\b` regex previously failed to match
`繼續做 TASK-3711` because Python's ASCII word-boundary `\b` requires
`\w` on one side and Chinese chars are non-word — replaced with
`繼續\s*` plus a leading-verb stripper. Verified by selftest case [9].

**Why a UserPromptSubmit hook (not SessionStart):** the backlog wording
said "SessionStart hook" but SessionStart fires before any prompt is
visible — it can't extract the keyword. UserPromptSubmit is the
semantically correct event; the spirit (deterministic find on `繼續 X`)
is preserved.

## [3.63.0] - 2026-04-26

### Change — DP-032 D21: Self-Review moves to Phase 3 exit gate

The Pre-PR Self-Review Loop (originally engineer-delivery-flow Step 4) is
relocated to **Step 1.3** — the exit gate of Phase 3 (LLM implementation
段). Phase 3 = TDD → /simplify → Self-Review (iterable, fail-cheap);
Phase 4 Step 1.5 onward = mechanical verify 段 (linear fail-stop). Self-Review
blocking never crosses the segment boundary.

- **Reviewer baseline = handbook-first**：handbook + repo CLAUDE.md +
  `{repo}/.claude/rules/**` is the **primary compliance baseline**;
  task.md `## 改動範圍` / `## 估點理由` is **context only**;
  task.md `Allowed Files` / `verification.*` / `depends_on` are **not
  read** (handled by D20 Scope Gate / D15 verify evidence / D14 artifact
  gate). Eliminates the task.md rubber-stamp risk where a workaround
  passes review just because it stays inside `Allowed Files`.

- **Iteration**：`passed: false` → return to **Phase 3** (LLM may freely
  edit tests / impl / re-run /simplify), not just back to /simplify;
  Phase 3 exit condition forces TDD → /simplify → Self-Review re-run.
  **Hard cap 3 rounds**, beyond which the flow halts for user
  intervention. **NO bypass** flag (consistent with D11 / D12 / D14 /
  D15 / D16 / D20 — LLM cannot decide to skip a gate).

- **Evidence**：Self-Review writes **no** evidence file and is **not**
  part of the Layer A+B+C AND gate. Self-Review is a semantic
  checkpoint, not a CI-class gate. Detail artifact still records
  Self-Review output for traceability.

- **Revision mode R5 does NOT re-run Phase 3** (incl. Self-Review). R5
  only re-runs Layer A+B+C mechanical evidence — the self-review verdict
  reached in first-cut is not re-litigated when fixing PR review
  comments.

- **Critic role spec**（`references/sub-agent-roles.md § Critic`）：
  When-to-use updated to "engineering Phase 3 exit gate (replaces
  pre-PR Step 4); revision mode R5 does NOT call this agent". Review
  scope upgraded to handbook-first hard spec table. Return format adds
  `blocking[].rule` field pointing to specific handbook path /
  rule section so Phase 3 has an unambiguous fix target.

- **engineering/SKILL.md** Step 3 delivery flow updated: list now
  includes Step 1.3 Self-Review explicitly; Phase 3 exit condition
  documented as "test 綠 + simplified + Self-Review passed"; revision
  mode R5 carve-out documented inline.

- **Step 4 placeholder kept** in engineer-delivery-flow.md to avoid
  breaking downstream references (D19 / D20 / Phase 4 walkthrough refer
  to Step 5/6/7/8 by number).

DP-032 D1 (Phase 0 collapse) is **not** in this release — it requires a
new `scripts/resolve-task-md.sh` (with `--from-input` mode) which is
deferred to a follow-up wave.

## [3.62.0] - 2026-04-26

### Add — DP-032 Wave β: deterministic verify execution + changeset primitives

Three new scripts plus one hook extension graduate the engineering delivery
flow's verify / changeset legs into deterministic primitives. All four
ship with comprehensive selftests (115 assertions total, all green).

- **`scripts/run-verify-command.sh`** (D15) — atomic verify execution
  bound to `head_sha`. Reads `## Verify Command` and Test Environment Level
  from task.md via `parse-task-md.sh`, dispatches to the correct env-prep
  ladder (static / build / runtime → `start-test-env.sh`), executes the
  fenced shell, captures exit + stdout hash + best-effort URL→status
  pairs, and writes evidence to
  `/tmp/polaris-verified-{ticket}-{head_sha}.json` with a `writer` field.
  Exit 0 only when the command exits 0 **and** the evidence file lands
  with a parseable schema. No bypass env var. First-cut and revision R5
  share this script — no separate revision path. Selftest:
  `run-verify-command-selftest.sh` (34/34).

- **`scripts/verification-evidence-gate.sh`** extended (D15 hook side) —
  the gate now prefers the new head_sha-bound filename
  (`polaris-verified-{TICKET}-{head_sha}.json`) and falls back to the
  legacy filename only if the new one is absent. New evidence files are
  validated against a relaxed schema (`ticket` / `head_sha` / `writer` /
  `exit_code` / `at` required) and exempted from the legacy 4-hour stale
  check (head_sha binding already guarantees freshness). The `writer`
  field must be one of `run-verify-command.sh` / `polaris-write-evidence.sh`
  (D16 cross-LLM whitelist). Legacy callers continue to work unchanged.
  Selftest: `verification-evidence-gate-selftest.sh` (21/21).

- **`scripts/polaris-changeset.sh new`** (D24) — mechanical changeset
  generator. Reads task.md via `parse-task-md.sh`; if the
  `deliverables.changeset` block is present (DP-033 future scope) it is
  used directly, otherwise the script derives `package_scope` from
  `.changeset/config.json` (single-package ⇒ use it; multi-package ⇒
  fail-loud requesting an explicit declaration), `filename_slug` from
  `{ticket}-kebab + {short-desc}-kebab` (≤60 chars, word-boundary truncate),
  and applies the L3 default `strip` to remove `[TICKET]` / `TICKET:`
  prefixes from the body. `--bump` defaults to `patch`. Idempotent: same
  slug already on disk ⇒ silent skip + exit 0 (rebase-safe). Description
  cannot be overridden by flag — body is always the stripped task title.
  Selftest: `polaris-changeset-selftest.sh` (30/30).

- **`scripts/changeset-clean-inherited.sh`** (D24) — pure git-state
  hygiene for cascade-rebased branches. Diffs `.changeset/*.md` against
  `origin/{base}`, extracts the ticket key from each filename slug, and
  `git rm`s any changeset whose ticket ≠ `--current-ticket`. Files whose
  ticket cannot be extracted are left alone (conservative). Designed to
  be invoked by `engineering-rebase.sh` post-rebase — completely
  separated from `polaris-changeset.sh new`. Selftest:
  `changeset-clean-inherited-selftest.sh` (30/30).

DP-033 has not yet added the `deliverables.changeset` block to the task.md
schema. Wave β scripts work today via derivation fallback; once DP-033
declares the block, `polaris-changeset.sh` will prefer the declared values
without code changes. The D16 PreToolUse `no-direct-evidence-write.sh`
hook is intentionally deferred to a follow-up wave.

Wave γ wiring (call-site updates in `engineer-delivery-flow.md` /
`engineering/SKILL.md` / `verify-AC/SKILL.md`) is also deferred — these
primitives are ready to be wired when the delivery-flow rewrite begins.

DP-032 plan.md Implementation Checklist:

- A class `run-verify-command.sh` ✅ landed
- A class `polaris-changeset.sh` ✅ landed
- A class `changeset-clean-inherited.sh` ✅ landed
- B class `verification-evidence-gate.sh` D15 portion ✅ landed
  (D12 portion already landed in v3.58.0)

## [3.61.1] - 2026-04-26

### Fix — three deterministic hooks that physically blocked legitimate work

Three PreToolUse hooks were producing false-positive blocks during routine
framework work. All three have the same root cause: the hook reasoned about
the **wrong slice of state** — body text instead of frontmatter, on-disk file
instead of proposed write content. Fixed without adding bypass flags.

- `scripts/design-plan-checklist-gate.sh`: stopped using naive substring
  match on `"status: IMPLEMENTED"` in `new_content`. The hook now simulates
  the post-edit content (Write: `tool_input.content`; Edit: on-disk content
  with `old_string` → `new_string` applied) and parses YAML frontmatter to
  detect a real `status:` transition to `IMPLEMENTED`. Plan bodies that
  discuss lifecycle, archive rules, or contain self-referential checklist
  items no longer trip the gate. Backlog #2 / #171.

- `scripts/pipeline-artifact-gate.sh`: PreToolUse on `Write` fired before
  the file existed on disk; validator was given a non-existent path and
  returned exit 2, blocking every new `task.md` / `refinement.json`. The
  hook now extracts `tool_input.content` for `Write`, base64-stages it to a
  tmp probe whose basename mirrors the target (so filename-keyed dispatch
  for `T*.md` / `V*.md` / `*.json` still routes correctly), and runs the
  validator against the probe. `Edit` on a missing file remains a no-op
  (Edit's `new_string` is a diff fragment, not a full file). Backlog #3.

- `.claude/hooks/checkpoint-carry-forward-fallback.sh`: probe staging was
  gated on `! -f "$file_path"`, which meant `Write` overwrites of existing
  checkpoint memories handed the validator the **stale on-disk content**,
  not the user's proposed new content. The check then compared old
  pending against old pending and HARD_STOP'd. Hook now stages a tmp probe
  whenever `tool_name == Write` (regardless of whether the target exists);
  Edit still uses on-disk because Edit's `new_string` is a fragment.
  Backlog #4.

Each fix was verified end-to-end with stdin JSON dispatch:

- design-plan gate: body-only mention of `status: IMPLEMENTED` → allow;
  frontmatter transition with unchecked items → block; frontmatter
  transition with all checked → allow.
- pipeline gate: `Write` of a new `T1.md` with garbage content → validator
  runs against tmp probe and blocks; non-pipeline path → allow; `Edit` on
  missing file → allow.
- checkpoint gate: `Write` overwrite on existing project memory → validator
  receives `/tmp/carry-forward-probe.*`, not the on-disk path.

Pure deterministic-layer fixes — no behavioral rule changes, no skill
edits, no LLM-side workarounds. Hooks now match their original design intent.

## [3.61.0] - 2026-04-26

### Feat — DP-033 Phase B: V{n}.md verification schema dual-path

Closes the dual-schema lifecycle started in DP-033 Phase A. Phase B adds the
verification side (V{n}.md) so an Epic now has a fully symmetric pair:

- T{n}.md = implementation task (engineering, `deliverable` + PR)
- V{n}.md = verification task (verify-AC, `ac_verification` + AC results)

**Symmetry principle**: verification is also engineering. All shared
infrastructure stays as one canonical implementation — `parse-task-md.sh` /
`mark-spec-implemented.sh` / `pipeline-artifact-gate.sh` / D6 `complete/` /
D7 atomic-write contract / `jira_transition_log[]` are reused by T and V.
Phase B adds **only** what the verification side genuinely needs:

- `task-md-schema.md` § 4 Verification Schema (B1 + B2 + B5):
  full V{n}.md schema mirroring § 3 — required sections inventory,
  Operational Context cells (V version drops `Test sub-tasks` / `AC 驗收單` /
  `Task branch`, adds `Implementation tasks`), `## 驗收項目`, `## 驗收步驟`,
  `## Test Environment` reuses T mode rules, `ac_verification` writer
  contract symmetric to D7 `deliverable` (atomic + verify + retry-3 +
  fail-stop), `ac_verification_log[]` loose list-of-maps (same 精神 as
  `jira_transition_log[]`)
- `scripts/validate-task-md.sh` (B3): filename-dispatched dual-path
  validator. T mode unchanged (zero-regression dogfood: 7 pass / 9 fail /
  5 hard-fail same as Phase A baseline). V mode adds `## 驗收項目` /
  `## 驗收步驟` / Operational Context V cells / `ac_verification` schema
  (status enum / ISO 8601 last_run_at / count sum invariant /
  human_disposition conditional) / `ac_verification_log[]` loose check.
- `scripts/validate-task-md-deps.sh` (B4): filename pattern extended from
  `T*.md` to `[TV]*.md`. Same DAG / linear / fixture / D6 same-key
  invariants now apply across T+V. New cross-type direction check:
  V→T pass / V→V pass / T→V fail (DP-033 D4 § 5.3). Synthetic dogfood
  confirmed both sides fire correctly; existing exampleco/specs scan: 3 pass /
  0 fail (no regression).
- `.claude/hooks/pipeline-artifact-gate.sh`: V\*.md branch now also runs
  `validate-task-md-deps.sh` (Phase A had a TODO comment; Phase B activates).
- `breakdown/SKILL.md` Step D (B6): V{n}.md naming spec written into the
  skill (sequential V1, sub-split V1a/V1b, symmetric to T). **Producer
  cutover (`{V-KEY}.md` → `V{n}.md`) deferred to DP-039** — verify-AC
  consumer rewrite + existing `{V-KEY}.md` migration script must land in
  the same atomic switch to avoid a producer/consumer drift window.
  Step 6 now carries a segmented-AC advisory: when breakdown detects two
  disjoint AC groups + two disjoint task groups, it suggests splitting the
  Epic (PM-level decision; validator only hard-fails T→V invariant).

**Plan checklist gate**: A1-A12 (Phase A) + B1-B7 (Phase B) = 19/19
checked; `design-plan-checklist-gate.sh` no longer blocks
`status: IMPLEMENTED` flip on `specs/design-plans/DP-033-task-md-lifecycle-closure/plan.md`.

**Handoff to DP-039**: § Implementation Notes lists the verify-AC consumer
rewrite, breakdown producer cutover, and existing `{V-KEY}.md` migration
script as the atomic switch DP-039 owns. DP-033 Phase B defines the target
schema + validator + breakdown spec; DP-039 lands the producer/consumer
cutover and the migration.

## [3.60.0] - 2026-04-26

### Feat — DP-032 Wave γ: deterministic engine wiring complete

Lands the four prose-rewiring batches that connect already-shipped DP-032
deterministic engines into the SKILL.md / reference callsites that drive
engineering / verify-AC / engineer-delivery-flow. No new primitives — pure
wiring of D11 / D8 / D22 / D25 into consumers.

**Batch 1 — JIRA transition (D25)**

- `verify-AC/SKILL.md` § 7 + Do/Don't and `engineer-delivery-flow.md` § Step 8
  now dispatch to `polaris-jira-transition.sh <ticket> <slug>` instead of
  ad-hoc `transitionJiraIssue` MCP calls or hand-rolled wiki lookups.

**Batch 2 — parse-task-md (D8)**

- 13 prose callsites switched from grep-the-section-and-pray to
  `scripts/parse-task-md.sh --field <key>`: `engineer-delivery-flow.md` (5
  callsites incl. § 3a Repo, § 3d Verify Command + Legacy fallback, § 5.5
  Allowed Files, Inputs row note, behavioral verify forward-compat note);
  `engineering/SKILL.md` (5 callsites: location-detection note, Test Command,
  Test Environment, pre-work rebase Base branch, R1 revision context rebuild);
  `verify-AC/SKILL.md` (2 callsites: Step 3c env_bootstrap_command + Step 3d
  fixtures). Parser uses flat alias names (`level`, `repo`, `fixtures`, etc.),
  not dotted paths — corrected from earlier inventory.

**Batch 3 — env primitives (D11)**

- 3 callsites switch to `scripts/start-test-env.sh --task-md <path>
[--with-fixtures]` (D11 L3 orchestrator that chains
  ensure-dependencies → start-command → health-check → fixtures-start):
  `engineer-delivery-flow.md` § 3b (orchestrator becomes primary, polaris-env.sh
  retained as fallback for Admin / no-task.md / handbook-driven repos);
  `engineering/SKILL.md` runtime branch in Phase 2 Test Environment (line
  215 cluster) — explicitly forbids hand-rolled `docker compose up` /
  `pnpm dev` / `mockoon-runner.sh start`; `verify-AC/SKILL.md` § Step 3c
  collapses prior 3c/3d (env start + fixture start) into one orchestrator
  call.

**Batch 4 — commit convention (D22) + H-class scan**

- `engineer-delivery-flow.md` § Step 6a Commit drops the `git ai-commit --ci`
  assumption; new prose explicitly traverses the L1 → L2 → L3 fallback chain
  defined in `references/commit-convention-default.md` (repo commitlint
  config / handbook commit section / Polaris L3 default).
- H-class scan results (DP-032 plan § H bulk migration list):
  `transitionJiraIssue` = 0 residuals in framework skills (cleaned by batch
  1); `git ai-commit` = only intentional self-mentions inside
  `commit-convention-default.md` itself, which explicitly excludes user-level
  tools from spec scope.

**Inventory corrections vs the original Wave γ checkpoint memory**

- `start-dev/` skill does not exist in framework `.claude/skills/` (only in
  exampleco fork; out of scope).
- `bug-triage/SKILL.md` has no transition pattern — no rewiring needed.
- `engineering/SKILL.md` shares the JIRA transition with delivery-flow §
  Step 8 (single source of truth, no separate engineering callsite).
- `run-test.sh` / `run-verify-command.sh` not yet shipped (D10 / D15 are
  Wave β / δ scope) — Wave γ does not touch them.

**`.agents/` mirror discipline**

- Every batch manually `cp`s only the files it touched; no
  `sync-skills-cross-runtime.sh --to-agents` bulk runs (those would commit
  unrelated long-stale drift). Net result: all rewired prose lands
  identically in `.agents/` mirror for Codex / Cursor / Gemini CLI runtimes.

**DP-032 plan.md**

- Wave γ rows in Implementation Checklist ticked; plan retains LOCKED
  status until Wave δ (run-test / run-verify-command) closes.

## [3.59.0] - 2026-04-26

### Feat — DP-033 Phase A: task.md schema closure + lifecycle gates

Lands the implementation half of DP-033 (Phase A). Phase B (verification
schema V{n}.md + verify-AC write-back) remains as future work; the design
plan stays at `status: DISCUSSION` until Phase B closes.

**Spec consolidation**

- New `skills/references/task-md-schema.md` (538 lines) — single
  authoritative reference for task.md schemas across the pipeline. All
  producers / consumers / validators / hooks now derive from this file.
  Filename pattern is the only type signal: `T{n}[suffix].md` =
  implementation, `V{n}[suffix].md` = verification (Phase B placeholder).
  Frontmatter `type` field deliberately omitted (D2: ground truth is
  filename, redundant `type` would silently rot on rename).

**Validator → enforcer (D5 four-tier)**

- `scripts/validate-task-md.sh` upgraded from minimum validator to full
  enforcer:
  - Hard required (exit 1 on missing/empty): title regex, JIRA + Repo
    metadata, `## Operational Context` (with cells), `## 改動範圍`,
    `## Allowed Files` (upgraded from Soft per D5; no grace, no
    warn-only), `## 估點理由`, `## Test Command`, `## Test Environment`,
    `## Verify Command` when Level≠static
  - Soft required (warn only): `## 目標`,
    `## 測試計畫（code-level）`, header `Epic:` cell
  - Lifecycle-conditional (skip when absent, validate schema when
    present): frontmatter `deliverable.{pr_url, pr_state, head_sha}` and
    `jira_transition_log[]` (loose list-of-maps, freeform keys)
  - Optional (no check): `## Verification Handoff`
- New § 5.5 hard invariant (exit 2): frontmatter `status: IMPLEMENTED`
  outside `tasks/complete/` is a HARD FAIL. Pairs with the move-first
  writer below.

**`tasks/complete/` convention + reader fallback (D6 + D8)**

- `scripts/mark-spec-implemented.sh` refactored to **move-first** for
  task.md: `mv tasks/T.md → tasks/complete/T.md` first, then update
  frontmatter `status: IMPLEMENTED` in the complete/ location only. The
  active `tasks/` directory therefore never contains a transient
  IMPLEMENTED state. Idempotent for already-moved files; same-key
  conflicts with different content exit 2 (no clobber). Epic-anchor
  flow (refinement.md / plan.md in-place) preserved unchanged.
- `scripts/parse-task-md.sh` and `scripts/validate-task-md-deps.sh` add
  unified active → complete fallback when looking up a task key.
  `depends_on` chains stay intact across the boundary (T5 depending on
  completed T1 no longer false-fails).
- `scripts/resolve-task-md-by-branch.sh` covers both
  `tasks/` and `tasks/complete/`.
- `validate-task-md-deps.sh` adds the same-key uniqueness invariant
  (active + complete duplicate → exit 2) — surfaces D6 move-first
  failures as silent-corruption signals.

**Lifecycle write-back (D7)**

- New `scripts/write-deliverable.sh` — atomic frontmatter writer for
  the `deliverable` block. Writes via Python → temp file → POSIX `mv`,
  with 3-attempt exponential backoff. On permanent failure: HARD STOP
  with the spec-required "task is in inconsistent state — PR created
  but task.md not updated. Manual recovery required." message. No
  /tmp fallback. Verifies post-write by re-reading the file.
- Validator does **not** block writes (lifecycle-conditional means
  optional during breakdown), but enforces schema strictly when the
  block is present (`pr_url` regex, `pr_state` enum, `head_sha` hex).
- `jira_transition_log[]` schema deliberately loose: list-of-maps,
  `time` recommended (ISO 8601) but not enforced, other keys freeform
  per company-specific JIRA conventions.

**Pipeline gate dispatch (A4)**

- `scripts/pipeline-artifact-gate.sh` now dispatches by filename:
  `tasks/T*.md` → implementation validator + deps validator;
  `tasks/V*.md` → implementation validator (Phase B placeholder, full
  V-schema dispatch deferred); `tasks/complete/*.md` → exit 0 (D6 skip
  rule, checked first).

**Breakdown gate (A3)**

- `breakdown` Path A Step 14.5 now runs `validate-task-md.sh` per file
  - `validate-task-md-deps.sh` over the produced batch. Any non-zero
    exit blocks progression to JIRA sub-task creation / branch creation.

**Migration tooling (A7)**

- New `scripts/dp033-migrate-tasks.sh` — one-shot inventory and
  migration script. Dry-run (default for review): inventory all
  `specs/*/tasks/T*.md`, classify (move-to-complete / backfill-active /
  unchanged / fail-loud), report counts. Apply mode mutates files;
  fail-loud halts on Operational Context Hard cells that cannot be
  fabricated (Task JIRA key / Base branch / Task branch). Backfill
  TODO marker convention (`TODO(DP-033-migration):`) for grep-driven
  follow-up.
- Live workspace dry-run: 16 T\*.md files (5 to move, 2 to backfill, 9
  unchanged, 0 fail). Apply is owned by the human, not run automatically.

**Dogfood (A10 + A11)**

- A10 schema dogfood against EPIC-478: 0 false positives. All 7 findings
  are true positives that A7 migration apply will resolve cleanly.
- A11 synthetic end-to-end (10 steps in `/tmp` exercising A2 + A3 + A4
  - A5 + A6 + A8 + § 5.5 + same-key uniqueness): 10/10 PASS.

**SKILL / reference touch-ups**

- `engineering/SKILL.md` Step 7c language updated to call
  `write-deliverable.sh` and halt the delivery flow on its failure
  (no silent fallback). Step 8a calls `mark-spec-implemented.sh` as
  the only authoritative complete-mover.
- `verify-AC/SKILL.md` annotated with one-line reader-fallback note.
  Full Verify-AC consumer refactor is deferred to DP-039.
- `engineer-delivery-flow.md` Step 7c / Step 8a / reader paths aligned
  with the new contracts.
- `breakdown/SKILL.md` adds Step 14.5 validator gate + top-of-skill
  reference to `task-md-schema.md` as the authoritative spec.

**Out of scope (deferred to follow-ups)**

- Phase B (V{n}.md verification schema + verify-AC write-back) — same
  DP, future Implementation Checklist B1-B7
- DP-039 `/verify-AC refactor` — consumer-side rewrite plus migration
  of existing `KB2CW-XXXX.md` verification files to `V{n}.md`
- Backlog: `scripts/design-plan-checklist-gate.sh` substring match
  false positive (separately committed earlier this session) —
  unrelated framework hygiene

## [3.58.0] - 2026-04-25

### Feat — DP-032 D12-c: per-repo `ci-local.sh` replaces framework-level CI mirror (BREAKING)

Closes the migration to per-repo, framework-agnostic Local CI Mirror. The
framework no longer assumes how a repo runs its CI (codecov / specific lint
tools / typecheck stack); each repo's `scripts/ci-local.sh` (generated by
`scripts/ci-local-generate.sh` from the repo's own CI config — Woodpecker /
GitHub Actions / GitLab CI / husky / `.pre-commit-config.yaml` /
`package.json` scripts) is the only Step 2 path. The framework keeps a thin
PreToolUse hook (`ci-local-gate.sh`) that reads evidence and sync-runs
`ci-local.sh` on cache miss.

**BREAKING CHANGES**

- `scripts/ci-contract-run.sh` removed (responsibilities absorbed by
  per-repo `ci-local.sh`; codecov logic, empty-coverage invariant, and any
  framework-specific prep are now repo-local concerns)
- `scripts/quality-gate.sh` removed (PreToolUse coverage moved to
  `.claude/hooks/ci-local-gate.sh`)
- `scripts/pre-commit-quality.sh` removed (per-repo `ci-local.sh` is the
  single quality entry point)
- `.claude/skills/references/quality-check-flow.md` removed (content
  inlined into `engineer-delivery-flow.md` § Step 2)
- Bypass: `POLARIS_SKIP_CI_LOCAL=1` only (emergency). **No** `wip:`
  commit-message skip / **no** main-develop branch skip / **no**
  deprecation shim — D12-c is a single breaking cut, not a phased migration

**New**

- `.claude/hooks/ci-local-gate.sh` PreToolUse hook intercepts
  `git commit` / `git push` (task/_ / fix/_ only) / `gh pr create`. Reads
  `/tmp/polaris-ci-local-{branch_slug}-{head_sha}.json` for cache hit; on
  miss/FAIL syncs runs `bash {repo}/scripts/ci-local.sh` and blocks on
  exit ≠ 0 with tail of log
- Registered in `.claude/settings.json` PreToolUse chain three times
  (matching `Bash(git commit*)` / `Bash(git push*)` / `Bash(gh pr create*)`)

**Changed**

- `scripts/verification-evidence-gate.sh` slimmed to **Dimension A only**
  (runtime/build verify evidence at `/tmp/polaris-verified-{TICKET}.json`).
  Dimension B (patch coverage / lint / typecheck) handed off entirely to
  the new `ci-local-required` deterministic hook
- `.claude/skills/references/engineer-delivery-flow.md` § Step 2 rewritten
  as **Local CI Mirror** (single section, replaces prior § 2 Quality
  Check + § 2a CI Contract Parity split). Vocabulary "CI Contract Parity"
  retired everywhere; "Local CI Mirror" / `ci-local.sh` is canonical
- `.claude/skills/references/deterministic-hooks-registry.md` — added
  `ci-local-required` row, removed `quality-evidence-required` and
  `ci-contract-framework-prep` rows, renamed
  `ci-contract-empty-coverage-net` → `ci-local-empty-coverage-net` with
  script path pointing into per-repo `ci-local.sh`
- `.claude/skills/engineering/SKILL.md` — all "CI Contract Parity (§ 2a,
  Dimension B)" / "ci-contract-run.sh" references swapped to "Local CI
  Mirror (Step 2, `ci-local.sh`)"; revision-mode R5 wording updated to
  point at `ci-local-gate.sh` PreToolUse blocking instead of
  `verification-evidence-gate.sh`'s former Dimension B clause
- `scripts/codex-guarded-git-commit.sh` and
  `scripts/codex-guarded-gh-pr-create.sh` — internal hook chain switched
  from `quality-gate.sh` / `ci-contract-run.sh` invocation to
  `.claude/hooks/ci-local-gate.sh` adapter call. `codex-guarded-git-push.sh`
  is unchanged (uses `pre-push-quality-gate.sh`, marker-based, no coupling)
- `_template/rule-examples/pr-and-review.md`, `docs/workflow-guide.md`,
  `docs/workflow-guide.zh-TW.md`, `references/feature-branch-pr-gate.md`,
  `references/sub-agent-roles.md`, `references/tdd-smart-judgment.md`,
  `references/epic-verification-workflow.md`,
  `references/visual-regression/SKILL.md`,
  `references/mechanism-rationalizations.md`,
  `references/commit-convention-default.md`,
  `references/shared-defaults.md`, `references/INDEX.md` — vocabulary
  scrubbed to canonical "Local CI Mirror / `ci-local.sh`"
- `.claude/polaris-backlog.md` — pre-commit-quality.sh full-repo-scan
  follow-up entry struck through (superseded by D12-c)

**Status**: DP-032 D12-c IMPLEMENTED. The scrub plus the structural
changes (3 scripts + 1 reference deleted, 1 PreToolUse hook added,
`verification-evidence-gate.sh` halved) are intentionally one breaking
release. Migration: regenerate each repo's `ci-local.sh` via
`scripts/ci-local-generate.sh` after pulling this version; no other
caller-side changes needed (generated script is self-contained).

## [3.57.2] - 2026-04-25

### Fix — ci-local-generate two latent bugs surfaced by Polaris dog-food

D12-b's `ci-local-generate.sh` shipped working for b2c-web pilot (which only
exercises husky + GitHub Actions paths) but two bugs blocked Polaris from
dog-fooding its own generator. Both fixed before D12-c; selftest extended
from 50 to 54 assertions to cover the new paths.

**Bug 1 — `.pre-commit-config.yaml` hooks emitted hook id as bare command**
(`scripts/ci-contract-discover.sh` `discover_pre_commit_config`):

`command = entry_cmd_str or hook_id` fell back to the hook id whenever
`entry` was absent. For community hooks (e.g., `id: shellcheck` /
`id: ruff-check` from upstream pre-commit repos), the YAML legitimately
omits `entry` because pre-commit fetches the implementation from the hook's
own repo. The generator then wrote literal `shellcheck` / `ruff-check`
lines into `ci-local.sh` — which fail at runtime (no such binary, or wrong
invocation). Even hooks with explicit `entry` plus default
`pass_filenames: true` were broken because the entry alone (e.g.,
`python3 -m py_compile`) needs file args appended by pre-commit.

Fix: when `entry` is absent, OR present but `pass_filenames` is not
explicitly `false`, delegate to `pre-commit run <hook-id> --all-files`.
Only `entry` + `pass_filenames: false` (truly self-contained local hooks
like `python3 scripts/readme-lint.py`) keeps the direct entry path.

**Bug 2 — embedded f-string with backslash-escaped dict key (Python <3.12 SyntaxError)**
(`scripts/ci-local-generate.sh` final aggregation block):

The generator emitted `print(f"... {summary[\"failed_checks\"]} ...")` into
the heredoc that becomes `ci-local.sh`. Python <3.12 forbids backslashes
inside the expression part of an f-string — pre-PEP-701 this is a
`SyntaxError`. The generator's own host (Python 3.14 here) tolerated it,
masking the bug; downstream environments on 3.11 / 3.10 would crash at
parse time. Switched to single-quoted dict keys
(`summary['failed_checks']`) — works on all Python 3.7+.

**Selftest extension (Test 4)**: fixture rewritten to cover three paths:
community hook (no entry), entry hook with default `pass_filenames` (still
delegated), local hook with explicit `pass_filenames: false` (direct entry).
New regression guards (`grep -Fx`) verify that bare hook ids never appear
as standalone command lines. 54 assertions, all passing.

## [3.57.1] - 2026-04-25

### Fix — sync-to-polaris.sh recursive scripts/ glob

Single-level `scripts/*.sh` glob in `sync-to-polaris.sh` Step 5 missed the
`scripts/env/` subfolder, leaving the v3.57.0 template release without the
six DP-032 D11 env primitives (`_lib.sh`, `health-check.sh`,
`fixtures-start.sh`, `start-command.sh`, `ensure-dependencies.sh`,
`selftest.sh`).

Replaced with `find scripts -name "*.sh" -type f` while preserving relative
paths under scripts/. Also excludes `node_modules/` and `e2e-results/`
trees. Header comment updated to `scripts/**/*.sh (recursive)`.

Discovered immediately after v3.57.0 sync — env/ files exist in workspace
repo but not in the public template. This release pushes them.

## [3.57.0] - 2026-04-25

### Feat — DP-032 Wave α: deterministic extraction infrastructure

Land the foundational scripts and reference docs for the engineering-deterministic-extraction plan. No breaking changes; legacy `ci-contract-run.sh` and `quality-gate.sh` remain in place — D12-c (next release) will retire them.

**D11 — env primitives + L3 orchestrator**:

- `scripts/env/_lib.sh` (workspace-config router→company resolver, yaml→json, dotted-path field extract, fail-loud helper)
- `scripts/env/health-check.sh` / `fixtures-start.sh` / `start-command.sh` / `ensure-dependencies.sh` (4 L2 primitives)
- `scripts/env/selftest.sh` (25 assertions)
- `scripts/start-test-env.sh` (L3 orchestrator: ensure-deps → start-command → health-check → [fixtures-start])
- Callsite rewiring deferred to Wave γ

**D8 — task.md central parser**:

- `scripts/parse-task-md.sh` (bash + python3 inline parser)
- Two output modes: full JSON envelope or `--field <key>` flat alias
- N/A sentinel normalized to null; resolves base via `resolve-task-base.sh` with soft-fail
- Selftest passes; smoke-tested against EPIC-478 T1/T3b/T3d
- Callsite rewiring deferred to Wave γ

**D25 — JIRA transition unified entry**:

- `scripts/polaris-jira-transition.sh` (cross-LLM REST API; bash 3.2 compatible)
- Built-in default slug→name map (in_development / code_review / done / waiting_qa / qa_pass / blocked)
- Aggressive soft-fail (per D25 reframe: JIRA transition is a nice-to-have display layer; task.md is authoritative)
- Smoke-tested on TASK-3711
- Callsite rewiring (engineering / verify-AC / bug-triage / start-dev) deferred to Wave γ

**D12-b — tool-agnostic CI mirror generator**:

- `scripts/ci-local-generate.sh` produces per-repo `{repo}/scripts/ci-local.sh`
- Reuses `ci-contract-discover.sh` to parse 4 of 5 CI providers (Woodpecker / GitHub Actions / GitLab CI + .husky/ + .pre-commit-config.yaml + package.json scripts; CircleCI deferred)
- Strict filtering: install/lint/typecheck/test/coverage categories only, `local_executable=true`, no `$CI_*` env dep
- `scripts/ci-local-generate-selftest.sh` (50 assertions across 6 fixtures)

**D22 + D24 — L3 default convention specs**:

- `references/commit-convention-default.md` (L3 fallback for commit messages: type enum, `{TICKET}` derivation, multi-commit, revision rules)
- `references/changeset-convention-default.md` (L3 fallback for changesets: filename slug, `{package}: patch` default, description = stripped task title, `ticket_prefix_handling=strip`)

**A0 — Polaris CI baseline (dog-food)**:

- `.github/workflows/ci.yml` (lint + selftest jobs)
- `.pre-commit-config.yaml` (mirrors workflow for local pre-commit framework)
- shellcheck `--severity=error` gate (0 errors today; warning + info + style cleanup deferred — separate session via "cleanup polaris shellcheck warnings" trigger)
- ruff check (5 files auto-fixed in this release; 0 issues today)

### Fix — TASK-3900 interim (subsumed by D12-c)

`ci-contract-run.sh` Nuxt prepare auto-detect + empty-coverage safety net. Both additions document the bug to fix in D12-c (full `ci-contract-run.sh` deletion, ci-local.sh take over).

## [3.56.0] - 2026-04-24

### Feat — DP-031: Revision Push Evidence Gate

Revision mode 只做 `git push`（不經 `gh pr create`），完全繞過 DP-029 建立的 evidence gate — 修 CI fail 的 revision 反而是最需要 CI 模擬的場景，卻是唯一沒被攔的路徑。

**D1 — L1 hook: `verification-evidence-gate.sh` 擴展攔截 `git push`**:

- 新增 `git push` 攔截（條件：`task/*` / `fix/*` branch + repo 有 codecov config + 非 `--delete`/`--tags`）
- `wip/*`、`feat/*`、framework repo、tag push 不攔
- `.claude/settings.json` 新增 `Bash(git push*)` hook entry

**D2 — L2 skill embed: engineering SKILL.md R5 明確列出 `ci-contract-run.sh`**:

- Revision R5 重跑完整驗收時，Step 2a（ci-contract-run.sh）標示為必跑步驟
- 警告區塊說明 revision mode 是最需要 CI 模擬的場景

**D2b — mechanism-registry.md 更新**:

- `verification-evidence-required`：補充 `git push` 攔截描述 + DP-031 條件
- `revision-r5-mandatory`：補充 DP-031 deterministic backup 說明

**Origin**: TASK-3900 session — PR #2206 revision 補測試，ci-contract-run.sh 未執行，git push 成功，evidence 完全不存在。

## [3.55.1] - 2026-04-24

### Fix — review-pr Step 4d severity calibration: language/library behavior claims require verification

Review-inbox session (web-design-system PR #667) 中 sub-agent 以「`DS_IMPORT_RE` 缺 `s` flag 因 `[^}]+` 無法跨行匹配」為由送出 must-fix + REQUEST_CHANGES，事實上 JS character class `[^}]+` 不受 `dotAll` 影響、本來就可跨行 — must-fix 判斷為誤，雖 reply 撤回但 REQUEST_CHANGES 仍在 GitHub 擋 merge。

**Updated — `.claude/skills/review-pr/SKILL.md § 4d Severity Calibration 注意事項`**:

- 新增一列：語言 / 函式庫行為推論（regex、array 方法、framework 預設值等） → 未驗證前最多 should-fix，驗證（Node REPL / MDN / 官方文件）後才可升 must-fix；附上 `[^}]+` dotAll 誤判為標準案例
- 核心原則段落補「語言/函式庫特性若未當場驗證，同樣最多 should-fix」

**Not graduated to deterministic**: 無法自動化偵測 review comment 中語言特性的事實錯誤（需要執行 runtime 驗證才能判斷）。這條與既有 `runtime-claims-need-runtime-evidence` canary 同屬 behavioral 層，但覆蓋 sub-agent 對外送出的 must-fix 判斷，不只是 Strategist 的內部結論採納。

## [3.55.0] - 2026-04-24

### Feat — DP-030 Phase 3: finalization (mechanism-registry audit + CLAUDE.md landed case study)

DP-030 收尾不碰 hook / script，只收 doc：

**Audited — `mechanism-registry.md`**:

- 確認 6 條強下放 canary（`no-cd-in-bash`、`no-independent-cmd-chaining`、`cross-session-carry-forward`、`max-five-consecutive-reads`、`no-file-reread`、`version-bump-reminder`）只剩 § Deterministic Quality Hooks 的 row，原 behavioral 分類僅存 block quote cross-reference
- 確認 2 條 partial-graduation canary（`post-task-feedback-reflection`、`feedback-trigger-count-update`）按 path B 設計保留 behavioral row + deterministic signal-capture row + annotation block quote
- 確認 6 條 Non-candidate canary（`skill-first-invoke`、`delegate-exploration`、`api-docs-before-replace`、`runtime-claims-need-runtime-evidence`、`design-plan-*`、`blind-spot-scan`）仍是 L3 residual 核心
- Priority Audit Order：items 1-8 是 live behavioral 重點；items 9-12 為 graduation trail / deterministic hook 低優先級提醒 — 此次無需再調整

**Updated — `CLAUDE.md § Deterministic Enforcement Principle`**:

- 在 Workaround accumulation signal 段落後加「Landed case study — DP-030」簡述：2026-04-24 v3.54.0 系統性下放 6 條 canary（全下放）+ 2 條（partial graduation），歸納 pattern 為「同一支 script 供 hook 和 SKILL embed 共用」、「exit 2 hard-stop vs exit 1 retry-able」、「behavioral 只保留不可簡化的語意判斷」。指向 `specs/design-plans/DP-030-llm-to-script-migration/plan.md` 作 canonical record

**Plan status flip**:

- `specs/design-plans/DP-030-llm-to-script-migration/plan.md`：status `LOCKED` → `IMPLEMENTED`、新增 `implemented_at: 2026-04-24`、Locked 下補 `## Implemented` 段落列 v3.51.0 ~ v3.55.0 五個版本 shipped 內容（plan.md 本身 gitignored，僅在主 checkout 維護）
- 所有 Implementation Checklist 8 項與 Blind Spots #3/#4 皆標為 checked；跨 LLM 驗證（BS#3）交棒給 DP-027 Phase 1E C19/C20；memory-hygiene L2 embed 因 Stop advisory 已覆蓋主要 drift signal 改列 backlog follow-up

**Also — `.claude/polaris-backlog.md`**:

- 補上 Phase 2C 親歷的 `.claude/hooks/checkpoint-carry-forward-fallback.sh` 既存檔 Write overwrite probe bug 條目（line 124 `! -f "$file_path"` 條件誤用 on-disk 舊內容當 probe），列入 framework follow-up，不阻擋 DP-030 收尾

**Why now**: Phase 2C 實作落地後，Phase 3 完成 canonical 文件與引用，讓未來 workspace / skill 作者在看 `CLAUDE.md § Deterministic Enforcement Principle` 時就能找到實戰參考，而不是從 backlog 考古。

## [3.54.0] - 2026-04-24

### Feat — DP-030 Phase 2C: L2 canary batch (path B advisory)

承接 Phase 2B（v3.53.0）L1-only batch，Phase 2C 把 `rules/mechanism-registry.md` 最後三條本質「部分語意」的 behavioral canary 下放到 advisory 組合（L1 Stop hook / PostToolUse signal capture + L2 skill embed）。行為寫入責任仍保留給 LLM — hook 只攔截訊號並在 Stop 時 surface 給 Strategist，從不 block；這是 Explorer sub-agent BS#1/BS#2 的 path B 折衷（硬下放會稀釋 DP-030 招牌，完全保留又違反確定性原則）。

**Added — `version-bump-reminder` → L2 + L1 advisory (full graduation)**:

- `scripts/check-version-bump-reminder.sh` — 接 `--mode post-commit|post-pr` + `--base`；post-commit 讀 `git log -1 --name-only HEAD`，post-pr 讀 `${base}..HEAD`；偵測 `rules/` / `.claude/skills/` 改動且無同 commit `VERSION` bump 時 stdout 提醒。Exit 0 恆成立
- `.claude/hooks/version-bump-reminder.sh` — 重寫為 delegate-only wrapper，從 stdin JSON 取 command 呼叫 validator（原本 inline logic 約 50 行壓到 34 行）
- `.claude/skills/engineering/SKILL.md` Step 9、`.claude/skills/git-pr-workflow/SKILL.md` Step 3 — L2 embed post-PR tail，呼叫同一支 `scripts/check-version-bump-reminder.sh --mode post-pr`

**Added — `feedback-trigger-count-update` → L1-only signal capture + Stop advisory**:

- `.claude/hooks/feedback-read-logger.sh` — PostToolUse on Read，比對 `memory/(topic/)?feedback[_-]*.md` pattern，match 時 dedup append 到 `/tmp/polaris-session-feedback-reads.txt`
- `scripts/check-feedback-trigger-count.sh` — 讀 state file，對每個 path 檢查 frontmatter `last_triggered` 是否 == today；stale entry 於 stdout 列出。接 `--clear` 選項（Stop hook 不用，保留狀態以便後續訊號）
- `.claude/hooks/feedback-trigger-advisory.sh` — Stop hook，honor `stop_hook_active` 防遞迴，呼叫 validator
- 不嵌任何 SKILL.md — 信號時機在 Read 發生時，不適合 skill flow 綁定。純訊號捕獲 + Stop advisory

**Added — `post-task-feedback-reflection` → L2 (4 skills) + L1 Stop advisory**:

- `scripts/check-feedback-signals.sh` — 合成兩種自糾正信號：(1) `/tmp/polaris-test-sequence.json`（test-sequence-tracker 餵料）、(2) `/tmp/polaris-cmd-self-correct.txt` sentinel（預留，目前無 writer）。Session start epoch 從 `/tmp/polaris-session-calls.txt` mtime 推估；掃 `memory/` 下本 session 內新建的 `feedback*.md` 檔。若「自糾正信號 > 0 且 無新 feedback 檔」才 stdout 提醒
- `.claude/hooks/feedback-reflection-stop.sh` — Stop hook，呼叫 validator with `--skill stop`
- L2 embed（tail 收尾）：`.claude/skills/engineering/SKILL.md` Step 10、`.claude/skills/git-pr-workflow/SKILL.md` Step 4、`.claude/skills/verify-AC/SKILL.md` § 11、`.claude/skills/breakdown/SKILL.md` § 17、`.claude/skills/refinement/SKILL.md` Step 8
- SKILL.md 注入點一致：skill flow 結束前呼叫 `check-feedback-signals.sh --skill <name>`，解讀 stdout，依 `rules/feedback-and-memory.md` 三層分類決定寫 feedback / handbook / 忽略

**Updated — settings.json**:

- PostToolUse Read：新增 `feedback-read-logger.sh` entry
- Stop：新增 `feedback-trigger-advisory.sh` + `feedback-reflection-stop.sh` entries（並列 `stop-todo-check.sh`，advisory-only hooks 不走 `decision: block`）

**Updated — L2 embedding registry**:

- `.claude/skills/references/l2-embedding-registry.md` — 加 7 行（B3 × 2 + B1 × 1 + B2 × 4）；preamble 新增「Multi-skill canary」慣例說明：同 canary 嵌多 skill 時每組合佔一 row，canary 欄允許重複
- Validator 本地 run 12/12 ✅

**Updated — mechanism-registry (partial / full graduation)**:

- § Framework Iteration — 移除 `version-bump-reminder` row，加 graduation 註記指向 § Deterministic Quality Hooks
- § Feedback & Memory — `post-task-feedback-reflection` + `feedback-trigger-count-update` 兩 row **保留**（behavioral write 仍由 LLM 負責），後面加 block quote 說明 DP-030 Phase 2C 加掛 deterministic advisory signal-capture
- § Deterministic Quality Hooks — 新增 3 row（version-bump-reminder / feedback-trigger-count-update / post-task-feedback-reflection）
- Priority Audit Order — item 6 調整描述（post-task-feedback-reflection graduated 為 signal-capture，audit priority 降低）；item 10/11 加 graduation 註記

**Path B rationale**:

- B1/B2 本質 semantic — user correction 的分類（framework / company handbook / repo handbook）、self-correct 的判斷（真錯誤 vs. 正常 iteration）無法純由 script 決定
- 硬下放為 blocking 會：(a) false positive 干擾正常 flow，(b) 稀釋 DP-030「deterministic 只下放可腳本化」的招牌
- Path B 折衷：deterministic 層抓訊號 + 在 Stop / skill tail surface，behavioral write 仍 LLM 決定。Stop hook 不 block（advisory）保持 session 流暢，但遺漏訊號變可觀察

**Known risks / follow-up**:

- Advisory 不擋 drift — 1–2 週觀察期後若遺漏率高考慮升級為 blocking（屆時需補 `POLARIS_SKIP_*` env bypass）
- `scripts/check-feedback-signals.sh` self-correct 訊號單一來源（目前只接 test-sequence-tracker）；預留 `POLARIS_CMD_SELFCORRECT` sentinel 待後續 PostToolUse 偵測「同指令不同參數 rerun」pattern 自動寫入
- Session start epoch 用 `stat -f %B` APFS 可能回 0，fallback 走 `/tmp/polaris-session-calls.txt` mtime；偏保守（可能多發 advisory），但不會漏
- engineering Setup-Only 特例在 Step 9/10 會 silent exit 0（無 commit），dogfood 時若反覆 surface 再加 bypass 說明
- 跨 LLM dogfood（BS#3）未在本 PR 執行，建議挑 engineering Step 9 在 Cursor / Codex session 實測 exit 0 + stdout surface 行為

**Impact**:

- Behavioral audit list 減 1 條完全（version-bump-reminder），2 條改為 partial graduation（保留 row + 加 block quote，audit priority 降低）
- DP-030 Phase 2 完成：Phase 2A meta-linter 基建（v3.52.0）+ Phase 2B L1-only × 3（v3.53.0）+ Phase 2C L2 advisory × 3（本版本）= 6 條 canary 下放 + 1 條 meta-linter validator
- 累計 deterministic 執行層：10 條 L1 hooks + 6 條 L2 embed（分屬 4 skill）+ scripts 共 9 支
- Bash 層 behavioral canary 歸零（Phase 2B 完成），Feedback 層保留 2 條 partial graduated

**Bypass**:

- Advisory hooks 不擋，暫無 env bypass；失誤時從 settings.json 移除對應 entry
- 若 B1/B2 未來升級為 blocking → 加 `POLARIS_SKIP_FEEDBACK_REFLECTION=1` / `POLARIS_SKIP_VERSION_BUMP_REMINDER=1`

Next: Phase 2C 觀察 1–2 週後（或 Phase 3 mechanism-registry 最終 audit）決定是否再硬化；剩餘 behavioral canary 歸類為純 semantic（api-docs-before-replace、delegate-exploration、blind-spot-scan 等），保留 L3。

## [3.53.0] - 2026-04-24

### Feat — DP-030 Phase 2B: L1-only canary batch migration

承接 Phase 2A（v3.52.0）meta-linter 基礎建設，Phase 2B 把三條純 tool-use 層級的 behavioral canary 下放到 L1 deterministic hooks。這些 canary 不依附任何 skill flow，直接由 PreToolUse / PostToolUse hook 觸發對應 `scripts/check-*.sh`；違反時 block（exit 2）或 advisory（stdout 警告）。

**Added — `no-independent-cmd-chaining` → L1 hook (hard block)**:

- `scripts/check-no-independent-cmd-chaining.sh` — python3 `shlex.split(posix=True)` 逐 token 掃描 `&&` 作為 top-level 運算子；引號內的 `&&` (e.g., `git commit -m "a && b"`) 仍合法通過。PreToolUse 語意：exit 2 HARD_STOP，stderr 附替代做法（多個並行 Bash tool call）
- `.claude/hooks/no-independent-cmd-chaining.sh` — PreToolUse wrapper，從 stdin JSON 解析 `tool_input.command` 轉呼叫 validator
- `.claude/settings.json` — PreToolUse Bash 註冊（skill-agnostic primary）

**Added — `max-five-consecutive-reads` → L1 hook (advisory)**:

- `scripts/check-consecutive-reads.sh` — 狀態檔 `/tmp/polaris-consecutive-reads.txt` 累計 Read/Grep；當 `Bash|Edit|Write|Agent|NotebookEdit|Glob` 等「產生結論」的 tool 觸發就 reset；超過 5 連發時 stdout 發 advisory 建議 delegate Explorer
- `.claude/hooks/consecutive-reads-monitor.sh` — PostToolUse wrapper（broad matcher 觀察全部 state-relevant tools）
- `.claude/settings.json` — PostToolUse `Bash|Edit|Write|Read|Grep|Glob|Agent|NotebookEdit` 註冊

**Added — `no-file-reread` → L1 hook (advisory)**:

- `scripts/check-no-file-reread.sh` — 狀態檔 `/tmp/polaris-file-reads.txt` 每 path 獨立計數；偵測 file mtime，若檔案被修改則 counter 重置為 1；超過 2 次同 path 讀取時 stdout 警告並建議從 milestone summary 引用
- `.claude/hooks/no-file-reread-monitor.sh` — PostToolUse wrapper 解析 `tool_input.file_path`
- `.claude/settings.json` — PostToolUse Read 註冊

**Fixed — `scripts/validate-l2-embedding.sh` escaped-pipe parsing**:

- Registry 中 L1 Matcher 欄位含 `Bash\|Edit\|...` 這類 markdown-escaped 的 pipe，原 `IFS='|' read` 會在第一個 pipe 就錯切 column。改為先 `sed 's/\\|/\x1e/g'` 保護再 split、split 完再還原。`cross-session-carry-forward` row 先前是靠巧合（'Edit' 剛好在 fallback hook 出現）才 pass，Phase 2B 擴表後問題暴露，順手修
- 抽出 `trim_restore()` helper 統一處理 whitespace trim + placeholder 還原

**Updated — L2 embedding registry**:

- `.claude/skills/references/l2-embedding-registry.md` — 新增三條 L1-only entry；validator 本地 run 5/5 ✅

**Removed from behavioral mechanism-registry (D5 直切 no shadow)**:

- `.claude/rules/mechanism-registry.md` § Context Management — 移除 `max-five-consecutive-reads`、`no-file-reread` canary rows；加 graduation 註記
- `.claude/rules/mechanism-registry.md` § Bash Execution — 整個 table 移除（唯一 canary `no-independent-cmd-chaining` 下放完畢），改為 graduation 註記
- 三條改列 § Deterministic Quality Hooks 表格（Enforcement + Script 欄位）
- § Priority Audit Order item 9 同步更新

**Framework gap noted (not fixed in this release)**:

- `scripts/context-pressure-monitor.sh` 存在但 `.claude/settings.json` 未註冊對應 hook — plan.md 原本「`max-five-consecutive-reads` 與 context-pressure-monitor 整併」的整併方向改為「先獨立運作」以保持本 PR scope；整併工作留待 context-pressure-monitor 被正式註冊後再做

**Impact**:

- Behavioral audit list 減 3 條（High + High + Medium），Bash 層 behavioral canary 歸零
- 與 Phase 1 POC `no-cd-in-bash` 風格一致：同一支 `scripts/check-*.sh` 可被 hook 與（未來）其他 LLM 直接呼叫
- 整體 deterministic 執行層累計：7 條 L1 hooks + 1 條 L2 embed + ~3 其他 hooks，behavioral layer 持續瘦身

**Bypass**: L1 hook 失誤攔截時可暫時從 `.claude/settings.json` 移除對應 hook entry；無專用 env var（advisory 兩條本來就不擋），`no-independent-cmd-chaining` 擋到時建議 rewrite 成多個 Bash tool call。

Next: DP-030 Phase 2C — L2 canary batch（`feedback-trigger-count-update` / `post-task-feedback-reflection` / `version-bump-reminder`），改動 SKILL.md 並在 DP-027 dogfood context 驗證跨 LLM 一致行為。

## [3.52.0] - 2026-04-24

### Feat — DP-030 Phase 2A: L2 embedding meta-linter infrastructure

承接 Phase 1 POC（v3.51.0），建立 DP-030 Phase 2 系統性下放的**監督層**：meta-linter registry 記錄「哪個 canary 對應哪支 script / 嵌在哪個 skill / 哪個 hook fallback」，validator 比對實際檔案抓斷連，避免 Phase 2B/2C 批次下放時漏嵌被忽略。（plan.md BS#8）

**Added — L2 embedding registry**:

- `.claude/skills/references/l2-embedding-registry.md` — machine-parseable markdown table（`<!-- registry:start -->` / `<!-- registry:end -->` 包起）記錄每個已下放 canary 的 9 欄位資訊：Canary ID / Script / Layer（L2+L1 / L1-only / L2-only）/ L2 Skill anchor / L2 Expected Grep / L1 Hook / L1 Event / L1 Matcher / L1 Expected Grep。Phase 1 POC 兩條 entry（`cross-session-carry-forward`、`no-cd-in-bash`）為 seed

**Added — Meta-linter validator**:

- `scripts/validate-l2-embedding.sh` — 讀 registry 表格，逐 row 驗：
  - Script 檔案存在
  - L2 Skill 檔案存在 + 內含指定 anchor（Step 標題字串） + L2 Expected Grep 字串
  - L1 Hook 檔案存在 + 內含 L1 Expected Grep 字串
  - L1 Hook basename 有註冊到 `.claude/settings.json`
  - Layer 宣告與實際填寫欄位一致（L2+L1 必須兩者都填；L1-only 不能有 L2 Skill；L2-only 不能有 L1 Hook）
  - Exit 0 = 全 pass；exit 1 = 至少一 row fail；exit 2 = registry 檔不存在 / 表格 marker 缺

**Added — `/validate` Mechanisms mode check #11**:

- `.claude/skills/validate/SKILL.md` — Mechanisms mode checks 表擴到 11 項，新增「L2 embedding integrity」項，直接呼叫 validator + 將 per-entry error surface 給使用者

**Follow-up (Phase 2B/2C, pending)**:

- Phase 2B — L1-only canary batch（`no-independent-cmd-chaining`、`max-five-consecutive-reads`、`no-file-reread`）
- Phase 2C — L2 canary batch（`feedback-trigger-count-update`、`post-task-feedback-reflection`、`version-bump-reminder`）

## [3.51.0] - 2026-04-24

### Feat — DP-030 Phase 1 POC: LLM judgment → deterministic script migration

第一批「機械式 canary」下放到 deterministic 執行層，對齊 CLAUDE.md § Deterministic Enforcement Principle（「能用確定性驗證的，不要靠 AI 自律」）。本次兩個示範 canary：L1 hook only (`no-cd-in-bash`) + L2 skill-embedded primary + L1 fallback (`cross-session-carry-forward`)。

**Added — L2 script conventions reference**:

- `.claude/skills/references/l2-script-conventions.md` — 規範 L2 script 的 exit code 語意（0/PASS, 1/RECOVERABLE_FAIL, 2/HARD_STOP）、retry budget（3 輪）、呼叫模板；讓其他 LLM（Cursor / Codex / Copilot / Gemini）藉由 SKILL.md embedded script call 取得跨 LLM 一致行為（DP-030 D2/D3/D4）

**Added — POC canary #1 `no-cd-in-bash` → L1 hook only**:

- `scripts/check-no-cd-in-bash.sh` — regex-based validator，偵測 bash command 開頭或 chain 分隔符（`&&` / `||` / `;` / `|` / `` ` `` / `$(`）後的 `cd ` token，block with exit 2 + stderr 說明替代方案（`git -C` / `pnpm -C` / `gh --repo` / 絕對路徑）
- `.claude/hooks/no-cd-in-bash.sh` — PreToolUse wrapper，從 stdin JSON 解析 `tool_input.command` 轉呼叫 validator
- `.claude/settings.json` — PreToolUse Bash 註冊（skill-agnostic primary，不綁特定 skill）

**Added — POC canary #2 `cross-session-carry-forward` → L2 primary + L1 fallback**:

- `scripts/check-carry-forward.sh` — python3 核心 heuristic：抓 new checkpoint 的 `topic` identifier → 找 memory_dir 內同 topic 最近一筆 prior project memory → 抽 prior 的 pending items → 檢查 new checkpoint 是否用 `(a) done / (b) carry-forward / (c) dropped` disposition marker 或 next-steps section 的關鍵詞覆蓋每項。Missing → exit 2 HARD_STOP + stderr missing list（`l2-script-conventions` D4 規則：retry 只會誘發偽造，禁止）
- `.claude/skills/checkpoint/SKILL.md` — 新增 Step 2.5「L2 Deterministic Check」，embedded script call + exit code handling + rationale
- `.claude/hooks/checkpoint-carry-forward-fallback.sh` — PreToolUse on Write/Edit fallback，當 user bypass checkpoint skill 直接寫 memory file 時攔截；過濾非 memory path / 非 `type: project` memory 以避免吵
- `.claude/settings.json` — PreToolUse（無 matcher 限定，由 hook 內部過濾 path）

**Removed from behavioral mechanism-registry (D5 直切 no shadow)**:

- `.claude/rules/mechanism-registry.md` § Bash Execution — 移除 `no-cd-in-bash` canary row
- `.claude/rules/mechanism-registry.md` § Feedback & Memory — 移除 `cross-session-carry-forward` canary row
- 兩者改列於 § Deterministic Quality Hooks 表格（Enforcement + Script 欄位）
- § Priority Audit Order item 5 和 item 9 同步更新，deterministic graduation 註記加在原區塊下

**Fixed — `quality-gate.sh` framework repo 偵測**（DP-030 D6 warm-up）:

- `scripts/quality-gate.sh` line 70 — `[[ "$repo_root" == "$HOME/work" ]]` → `[[ -n "$repo_root" && -f "$repo_root/VERSION" ]]`。原條件在 worktree 環境（e.g., `.worktrees/framework-*`）失敗，導致 framework repo 的 worktree commit 被誤攔 quality evidence；改偵測 VERSION 檔存在更 robust

**Impact**:

- Behavioral audit list 減 2 條（High + Critical 各一），post-task scan 更聚焦
- L2 script + SKILL.md embed 為後續 Phase 2 系統性下放（`post-task-feedback-reflection` / `version-bump-reminder` 等 6+ canary）奠基
- Cross-LLM 一致性：SKILL.md 文字化 script call + exit code handling，Cursor / Codex 走 skill flow 也會觸發同一支 check

**Bypass**: L1 hook 若誤擋可用 `POLARIS_SKIP_ARTIFACT_GATE=1` 以外的個別 env var 跳過（Phase 2 視需要加）— 目前建議觸發時讀 stderr 決定是否 rewrite command；L2 HARD_STOP 不提供 bypass（對齊 D4 設計意圖）。

Next: DP-030 Phase 2 系統性下放 candidate 表其餘 canary（見 `specs/design-plans/DP-030-llm-to-script-migration/plan.md` Implementation Checklist）。

## [3.50.0] - 2026-04-24

### Break — DP-029 Phase C Quick-Win: coverage-gate 下架、Dimension A/B 釐清

Phase C 以 **Quick-Win 原則**（D12）收尾：8 個 sub-topic 中做 3 項、其餘 5 項 deliberate closure。patch coverage 自此歸 repo 責任，框架不維持獨立 Dimension A coverage gate。難解部分（LLM judgment → script migration）承接到 DP-030 另案。

**Removed — framework-level coverage gate 整組下架（D6 revision v2 / D11）**:

- `.claude/hooks/coverage-gate.sh` — push-time PreToolUse hook 刪除
- `scripts/write-coverage-evidence.sh` — evidence writer 刪除
- `.claude/settings.json` — `git push*` 第二個 hook 註冊移除
- `scripts/ci-contract-run.sh` — `--write-coverage-evidence` flag + 對應 Python 區塊整組移除（不再寫 `/tmp/polaris-coverage-*.json`）
- `scripts/codex-guarded-gh-pr-create.sh` / `scripts/pre-commit-quality.sh` — caller 移除 `--write-coverage-evidence` 參數
- `.claude/rules/mechanism-registry.md` — `coverage-evidence-required`（Deterministic Quality Hooks 表）+ `codecov-patch-gate`（Quality Gates 表）canary 整組移除；Priority Audit Order line 12 同步更新
- `POLARIS_SKIP_COVERAGE=1` env var 作廢（無對應 gate 可 skip）

**Rationale**: Dimension A Framework Baseline 剩下 **TDD / Verify Command / VR（conditional）** 三層，bug 早期偵測已足夠。Patch coverage 抓的是「改 prod 沒補 test」，這是 TDD 紀律後驗、不是 bug 防線。配合使用者「快速迭代、快做快修」哲學，不在框架層累積補救性 gate。repo 有配 `codecov.yml` → 由 Dimension B（`ci-contract-run.sh` Phase B patch gate 模擬）接手；repo 沒配 → 不主動追加。

**Added — D8 revision canary `tdd-bypass-no-assertion-weakening`**:

- `.claude/rules/mechanism-registry.md` Quality Gates 表新增 canary：gate fail → 禁止放寬 assertion / `.skip()` / `as any` / `@ts-ignore` 繞過，必須回實作階段修 root cause
- 定位從原訂的 `ci-equivalent-no-patch-to-pass`（綁 coverage gate）改為通用 gate-fail 後的 TDD 紀律檢查，涵蓋 build / lint / typecheck / test / functional-verify / CI-equivalent 全部 gate

**Changed — engineer-delivery-flow Step 2a Dimension A/B 文件化**:

- `.claude/skills/references/engineer-delivery-flow.md` § Step 2a 從「Coverage Gate Check（硬門檻）」改為「CI Contract Parity」
- 明文分離 Dimension A（framework baseline）vs Dimension B（repo CI-equivalent），說明 `ci-contract-run.sh` 如何 owner-based 執行（有配就跑、沒配就跳過）
- 移除 `POLARIS_SKIP_COVERAGE` bypass 說明，改為 `POLARIS_SKIP_CI_CONTRACT=1`
- `.claude/skills/engineering/SKILL.md` § 工程規範 / § 交付流程 coverage-gate 引用同步更新為 CI Contract Parity

**Closed — Phase C 其餘 5 項 deliberate closure (D12)**:

- Advisory section（「repo CI 未配置的常見 check」）→ out of scope（D11 後框架不主動追加）
- workspace-config `ci_equivalent` overrides schema → deferred（無實際需求）
- Evidence 持久化 `/tmp → specs/{EPIC}/verification/` → deferred（ephemeral 模式沒抱怨）
- Monorepo advanced（path filter per job / per-package context）→ deferred（Phase B 已解當前痛點）
- Matrix / conditional / reusable → deferred（無真實 repo 受阻）

`specs/design-plans/DP-029-engineering-ci-equivalent-coverage/plan.md` 狀態：LOCKED → **IMPLEMENTED**（2026-04-24）。

**DP-030 seeded**: LLM judgment → script migration — mechanism-registry 裡「可腳本化但仍 behavioral canary」的系統性下放 hook layer，對應使用者主張「LLM 判斷力留給有價值的事，機械式檢查該腳本化」。

## [3.49.1] - 2026-04-24

### Fix — BSD sed/grep/awk `\s` incompatibility on macOS

Closes a latent portability bug discovered during the DP-028 v3.48.0 commit session: macOS default BSD `sed` / `grep -E` / `awk` do not expand `\s` (GNU extension). Patterns silently matched nothing, causing the most visible symptom where `quality-gate.sh` could not extract `repo_dir` from `git -C <path>` commands, fell back to `cwd`, and misidentified the branch when Claude Code's Bash tool CWD diverged from the commit target repo (→ `BLOCKED: No quality evidence for branch 'task/XXX'` false positive).

**Changed** — 22 occurrences across 12 files, `\s` → `[[:space:]]` and `\S` → `[^[:space:]]` (Python heredoc blocks preserved since `re` module supports `\s`):

- `scripts/quality-gate.sh` (L31 grep, L42 grep, L43 sed — root cause of the false-block symptom)
- `scripts/verification-evidence-gate.sh` (L28, L128)
- `scripts/dev-server-guard.sh` (L34, L36)
- `scripts/pr-create-guard.sh` (L19)
- `scripts/check-scope-headers.sh` (L46)
- `scripts/validate-task-md.sh` (L143, L144 — awk `/^\s*$/`, also BSD-incompatible)
- `scripts/test-sequence-tracker.sh` (L27)
- `scripts/safety-gate.sh` (L53-63 — 10 dangerous-pattern regexes)
- `scripts/generate-specs-sidebar.sh` (L200)
- `.claude/hooks/coverage-gate.sh` (L69)
- `.claude/hooks/version-docs-lint-gate.sh` (L30, L31)
- `.claude/hooks/version-bump-reminder.sh` (L21, also fixed `\S` → `[^[:space:]]`)

**Dogfood** — macOS BSD sed now correctly extracts paths:

```bash
echo 'git -C /Users/hsuanyu.lee/work commit -m "test"' | \
  sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^ ]+).*/\1/p'
# → /Users/hsuanyu.lee/work   (previously: empty string)
```

**Files**

- 12 shell scripts / hooks (see list above)
- `.claude/polaris-backlog.md` — TODO entry flipped `[ ]` → `[x]` with fix note
- `VERSION` — 3.49.1
- `CHANGELOG.md` — this entry

## [3.49.0] - 2026-04-24

### DP-029 Phase A + Phase B — CI-Equivalent Coverage: Hook Detection + Codecov Patch Gate Simulation

Closes the gap where `ci-contract-run.sh` marks a local run PASS while Codecov's `patch` status fails on the same commit. Root cause on PR #2206 (`exampleco-b2c-web`): discover only scanned the first `patch` status per flag and ignored `threshold`; runner treated `target: auto` as auto-pass; `choose_base_branch` hardcoded `develop/main/master` so task branches with upstream task bases computed diff against the wrong ref; and the monorepo lcov file paths (relative to package root) did not reconcile with git diff paths (relative to repo root).

**Added (Phase A — hook-layer detection, rough)**

- `scripts/ci-contract-discover.sh`: three new dev-hook scanners feeding a new top-level `dev_hooks[]` field in the contract output:
  - `.husky/*` — reads every file under `.husky/`, strips boilerplate (`echo`, shebang, husky self-source lines), categorises the remaining commands via the existing `categorize_command`.
  - `.pre-commit-config.yaml` / `.pre-commit-hooks.yaml` — parses `repos[].hooks[]` and records hook entries with the `entry` or `id` as command and the first `stages` value as `hook_type` (fallback `pre-commit`).
  - `package.json` — scans root plus `apps/*/package.json` and `packages/*/package.json` for legacy `husky.hooks` and `lint-staged` fields; emits a marker entry for standalone `.lintstagedrc.{js,cjs,mjs,json,yaml}` files.
- `scripts/ci-contract-run.sh`: new `--include-hooks` CLI flag; currently a pass-through (runner does not execute dev hooks — deferred to Phase C), value surfaces as `report.contract.include_hooks`.

**Added (Phase B — codecov patch gate simulation)**

- `scripts/ci-contract-discover.sh`: schema bumped to `schema_version: 2`. New `codecov_flag_gates[]` field replaces the old `codecov_patch_gates[]` (break change per DP-029 D9 — no fallback). Each entry records `flag`, `include_paths`, `exclude_paths`, and a full `statuses[]` list preserving per-status `type` (patch / project), `target_raw` (original string, e.g. `"60%"` or `"auto"`), `target_percent` (parsed float, null when auto), `threshold_percent` (parsed float, null when absent), and `is_auto` (true when target is literal `auto`). Flags without `statuses` are still listed (empty list) for report-only configurations.
- `scripts/ci-contract-run.sh`: new `--base-branch <name>` CLI flag lets callers override the `develop → main → master` fallback when the effective base is an upstream task branch. Value surfaces as `report.contract.base_branch`.
- `scripts/ci-contract-run.sh`: new per-status patch gate loop. Each flag's statuses are evaluated individually:
  - `type: patch` + explicit numeric target → `effective_target = target_percent - (threshold_percent or 0)`; PASS when `coverage_percent >= effective_target`, FAIL otherwise.
  - `type: patch` + `is_auto: true` → SKIP with `reason: patch_auto_target_not_supported_locally` (auto requires base-commit coverage, out of scope for Phase B).
  - `type: project` → SKIP with `reason: project_gate_not_implemented` (deferred to Phase C).
  - Flag with empty statuses → SKIP with `reason: flag_has_no_statuses`.
  - `total_lines == 0` (no instrumented patch lines) → SKIP with `reason: no_instrumented_patch_lines`.
- `scripts/ci-contract-run.sh`: monorepo path reconciliation in `compute_flag_coverage`. When direct `lcov_map.get(f)` misses, the runner now strips each flag `include_path` prefix (e.g. `apps/main/`) before retrying, and falls back to a bidirectional suffix match. Fixes a Phase B bug surfaced during real b2c-web dogfood where SF paths relative to `apps/main/` (e.g. `SF:app.vue`) did not match git diff paths relative to repo root (e.g. `apps/main/app.vue`).
- Evidence schema: previous `patch_gates` array replaced by `flag_results[]`. Each entry includes `flag`, `status_type`, `target_raw`, `target_percent`, `threshold_percent`, `effective_target_percent`, `is_auto`, `status` (PASS/FAIL/SKIP/PLANNED), `reason` (when SKIP), `covered_lines`, `total_lines`, `coverage_percent`, and `matched_files[]`. Any `flag_results[*].status == "FAIL"` drives `report.status = "FAIL"` and exit 1. SKIP does not count as FAIL. `summary.flag_gate_failures` mirrors the FAIL count.

**Dogfood**

- Synthetic FAIL scenario (`/tmp/dp029-synthetic`, 3/3 new lines uncovered): coverage 0% < effective_target 60%, `flag_results[0].status: FAIL`, `summary.flag_gate_failures: 1`, exit 1. ✅
- Synthetic PASS scenario (same repo, fully covered): coverage 100%, `flag_results[0].status: PASS`, overall PASS, exit 0. ✅
- Synthetic `target: auto` scenario: `flag_results[0].status: SKIP`, `reason: patch_auto_target_not_supported_locally`, overall PASS, exit 0. ✅
- `.pre-commit-config.yaml` synthetic dogfood: 2 hook entries (`trailing-whitespace`, `check-yaml`), `hook_type: pre-commit`. ✅
- Real b2c-web dogfood (branch `task/TASK-3468-lodash-cdn-unify` against develop): 5 `dev_hooks` entries (husky pre-commit w/ `pnpm exec lint-staged` → `lint`, commit-msg commitlint, post-merge `pnpm install` → `install`, `.lintstagedrc.mjs` marker), schema v2 flag gates correct (`main-core` project auto+threshold 1% + patch 60%, `multiples` report-only), monorepo prefix strip resolved — `main-core` patch coverage 20.67% (43 / 208 changed lines), which in non-dry-run mode drives exit 1 via deterministic `if coverage < effective_target` branch.

**Scope boundaries (explicit)**

- Phase A is intentionally rough — "可用即可" per DP-029 D9. False positives acceptable; no runner execution of dev hooks yet.
- Phase B acceptance target is PR #2206's class of failure (absolute-numeric patch target + monorepo paths). `target: auto` patch and all `type: project` gates are SKIP with explicit reasons; their full simulation is Phase C.
- `scripts/coverage-gate.sh`, `scripts/write-coverage-evidence.sh`, `pre-commit-quality.sh`, and `verification-evidence-gate.sh` are callers — their migration to the new `flag_results` schema lives in Phase C.

**Files**

- `scripts/ci-contract-discover.sh` — new scanners + schema v2
- `scripts/ci-contract-run.sh` — per-status patch gate + `--base-branch` + `--include-hooks` + monorepo prefix fix
- `specs/design-plans/DP-029-engineering-ci-equivalent-coverage/plan.md` — Phase A+B checklist ticked, Delivery Log added, Phase C remains open (`status: LOCKED` kept deliberately)
- `VERSION` — 3.49.0
- `CHANGELOG.md` — this entry

## [3.48.0] - 2026-04-23

### DP-028 — `depends_on` Branch Binding

Closes the gap where multi-task Epics let engineering open PRs against stale or wrong base branches when upstream tasks weren't yet merged. Enforcement is deterministic (script + hook), not behavioral.

**Added**

- New script `scripts/resolve-task-base.sh` — reads task.md's `Base branch`, traces `depends_on` chain, checks `git merge-base --is-ancestor` to determine whether the upstream is already merged into develop, and returns the correct base dynamically.
- New script `scripts/resolve-task-md-by-branch.sh` — maps a git branch name back to its task.md via the `Task branch` field; supports `--current` and handles worktree roots (prefers outermost `workspace-config.yaml`, then `git rev-parse --git-common-dir`).
- New PreToolUse hook `.claude/hooks/pr-base-gate.sh` — extracts `--base X` from `gh pr create` / `gh pr edit` commands, compares with `resolve-task-base.sh` output, and blocks on mismatch (exit 2). Fail-open on resolver failure. Bypass: `POLARIS_SKIP_PR_BASE_GATE=1`.

**Changed**

- `scripts/validate-task-md.sh`: added cross-field rule — when `Depends on` is non-empty, `Base branch` must start with `task/` (snapshot points at the task branch until upstream merges).
- `scripts/validate-task-md-deps.sh`: added is-linear-dag check — a task may depend on at most one predecessor. Multi-dependency rejected to keep the dispatch chain unambiguous.
- `breakdown` Step 14: rewritten to produce DAG-topological ordering (Kahn's algorithm), snapshot `Base branch` at breakdown time, and emit chain-depth advisory. Pre-check rejects multi-dependency graphs.
- `engineering` SKILL.md § R0 Pre-Revision Rebase + PR Base Sync: engineering revision mode now rebases onto `resolve-task-base.sh` output (not PR `baseRefName`) and syncs PR base via `gh pr edit --base` when it drifts. The hook blocks mismatched edits.
- `references/engineer-delivery-flow.md`: Base Branch Resolution table now lists four consumption points including § R0 step 4 PR base sync.
- `references/pipeline-handoff.md`: added `Dependency Binding (DP-028)` section documenting the three-layer consumption model (Snapshot / Resolve / Gate) and cross-field rule.
- `rules/mechanism-registry.md`: added `engineering-consume-depends-on` (High) and `depends-on-linear-chain` (Medium); updated `breakdown-step14-no-checkout` canary to cover DAG topological ordering.

**Dogfood**

- EPIC-478 T3b/T3c/T3d PRs (#2206, #2205, #2207) had stale `feat/EPIC-478-cwv-js-bundle` base because T3a (TASK-3711) hadn't merged. Mechanism detected, engineering revision mode R0 applied `gh pr edit --base task/TASK-3711-dayjs-infra-util` to all three, hook validated each edit. Three PRs now stacked correctly against the predecessor task branch.

## [3.47.0] - 2026-04-23

### Worktree Dispatch Paths for Cross-LLM Compat

**Added**

- New reference `skills/references/worktree-dispatch-paths.md` — canonical path map for worktree sub-agents accessing gitignored framework artifacts (`specs/`, `.claude/skills/`). Includes a copy-paste dispatch block and rationale. Indexed under Sub-agent & Exploration in `references/INDEX.md`.
- Backlog entries for related worktree friction surfaced during TASK-3711: Verify Command hardcoded main-checkout paths, and `pre-commit-quality.sh` full-repo vs scoped-to-changed scanning.

**Changed**

- `rules/sub-agent-delegation.md`: worktree path translation split into two bullets — tracked source code stays inside the worktree; gitignored framework artifacts (`specs/`, `.claude/skills/`) are read from and written to the main checkout via absolute paths.
- `engineering`, `breakdown`, `verify-AC`, `refinement`, `bug-triage`, `sasd-review` SKILL.md: inlined a ≤ 6-line path-rule block at each skill's sub-agent dispatch site so Codex and other LLMs that don't auto-load `rules/` can follow the rule verbatim.
- `framework-iteration-procedures.md`: added Step 0 "One commit for everything" to the post-version-bump chain to prevent partial commits that omit `VERSION`/`CHANGELOG.md`.

**Fixed**

- `bug-triage` Step 2-AF artifact path was relative (`specs/{EPIC}/artifacts/...`), corrected to absolute (`{company_base_dir}/specs/{EPIC}/artifacts/...`) so sub-agents running in worktrees can locate it.

## [3.46.0] - 2026-04-22

### Pipeline Handoff + Skill Workflow Upgrades

**Added**

- New handoff evidence reference: `skills/references/handoff-artifact.md` (and `.agents` mirror), defining Summary/Raw Evidence schema, 20KB cap, secret scrub contract, and on-demand consumer behavior.
- New `memory-hygiene` skill (in `.agents`) for manual Hot/Warm/Cold memory tiering operations.
- Stop-hook backup for session summary capture: `.claude/hooks/session-summary-stop.sh`.

**Changed**

- Updated multiple core skills and mirrors (`engineering`, `bug-triage`, `breakdown`, `verify-AC`, `learning`, `design-plan`, `my-triage`, `checkpoint`) to align pipeline boundaries, handoff artifacts, and resume/triage behavior.
- Expanded `pipeline-handoff.md` with artifact schema and cross-file validation expectations.
- Strengthened engineering quality guidance with explicit coverage-gate integration in `engineer-delivery-flow.md` and `tdd-smart-judgment.md`.
- Updated timeline behavior (`scripts/polaris-timeline.sh`) to support `session_summary` dedup via `--session-id`.

**Fixed**

- Improved PreCompact session-summary hook to consume stdin session metadata and emit dedup-ready command output (`.claude/hooks/session-summary-precompact.sh`).
- Corrected script path references in checkpoint workflows to use `scripts/polaris-timeline.sh` directly.

## [3.45.0] - 2026-04-22

### Codex Compatibility Fixes (from workspace PR #5)

**Fixed**

- `codex-mcp-setup` SKILL.md frontmatter: quoted `description` field to fix YAML parsing in Codex (both `.claude/` and `.agents/` mirrors).
- `sync-skills-cross-runtime.sh`: replaced `rsync` dependency with `cp -R` for broader compatibility; simplified dry-run output.

**Added**

- `polaris-codex-doctor.sh`: expanded from 4 to 5 checks — added `.agents/skills` path validation, SKILL.md frontmatter YAML parsing (via PyYAML), and Codex MCP hints (`~/.codex/config.toml` inspection).
- `sync-codex-mcp.sh`: added troubleshooting hints at script completion for login and optional connector removal.
- `docs/codex-quick-start.md` + `zh-TW`: added Troubleshooting section covering `invalid YAML` and `MCP startup incomplete` scenarios.

## [3.44.0] - 2026-04-22

### Sidebar Sync Hook Fix + DP-010 Closure

**Fixed**

- `docs-viewer-sync-hook.sh`: `CLAUDE_TOOL_INPUT` is empty in PostToolUse Edit hooks — added `find`-based fallback to scan recently modified specs files (10-second window), bypassing both missing env var and gitignored `specs/` directory.

**Changed**

- DP-010 (CWV/SEO Epic Full Classification) plan status → IMPLEMENTED. All 4 rounds complete; EPIC-542 "[SEO] Product Heading 整理" Epic created with Relates links from EPIC-488/489/490.

## [3.43.0] - 2026-04-22

### Worktree Isolation — All Code Changes

**Changed**

- Worktree isolation rule upgraded from "branch switching only" to **all code changes** — no "stay on current branch" exception, including framework repo itself.
- Mechanism `branch-switch-requires-worktree` renamed to `all-code-changes-require-worktree`, drift escalated to **Critical**.
- Exceptions narrowed to: read-only operations, JIRA/Slack/Confluence, and memory/todo/plan file edits.

## [3.42.0] - 2026-04-22

### Framework Sync Alignment

**Changed**

- Cross-runtime skills mirror synced (`.claude/skills` → `.agents/skills`) to keep Codex runtime artifacts aligned with latest framework updates.
- Synced framework changes into Polaris template via `scripts/sync-to-polaris.sh` (local template updated, no auto-push).

## [3.41.0] - 2026-04-22

### DP-025 — Pipeline Artifact Schema Enforcement

延續 DP-023 的 runtime slice 成果，把 validator + PreToolUse hook + exit-code gate 模式擴張到 Polaris pipeline 全鏈 artifact（refinement → breakdown → engineering）。Producer 寫完 artifact 當下即 fail-fast，不等 consumer 在下游炸掉。

**使用者裁示**：強約束、立即上線、上線後掃補。無 warning-tier、無分階段 rollout。

**Added**

- `scripts/validate-refinement-json.sh` — 新 validator：檢查 `specs/*/refinement.json` 必填欄位（`epic` / `version` / `created_at` / `modules[]` with `path`+`action` / `acceptance_criteria[]` with `id`+`text`+`verification{method,detail}` / `dependencies[]` / `edge_cases[]`）。支援 `--scan {workspace_root}` 盤點模式。Hard-fail on any missing required field
- `scripts/validate-task-md-deps.sh` — 新 validator：跨檔案檢查 `specs/{EPIC}/tasks/` 目錄。驗證 `depends_on` 指向同目錄既有 task.md（broken ref）+ DAG 無 cycle（DFS coloring）+ `## Test Environment` `Fixtures:` path 在檔案系統存在（解析順序：Epic dir → company base dir → workspace root）。支援 `--scan` 模式
- `scripts/pipeline-artifact-gate.sh` — PreToolUse dispatcher（runtime-agnostic）。從 `CLAUDE_TOOL_INPUT` / 命令列 / stdin 擷取 file path，依 path pattern 分派到對應 validator：
  - `*/specs/*/refinement.json` → `validate-refinement-json.sh`
  - `*/specs/*/tasks/T*.md` → `validate-task-md.sh` + `validate-task-md-deps.sh`
  - Validator exit ≠ 0 → hook exit 2 blocks Edit/Write
  - Bypass: `POLARIS_SKIP_ARTIFACT_GATE=1`
- `.claude/hooks/pipeline-artifact-gate.sh` — Claude hook wrapper（跟隨 `specs-sidebar-sync.sh` 的 thin wrapper 模式）
- `skills/references/pipeline-handoff.md` § Artifact Schemas — 新增 authoritative schema 章節（Atom 層 single source of truth）。列出 refinement.json / task.md / cross-file / fixture 各 artifact 的必填欄位與驗證規則；validator script 從此文件派生
- `rules/mechanism-registry.md` § Pipeline Artifact Schema — 新增 canary 區塊：`refinement-schema-compliance`、`task-md-full-schema`、`task-md-deps-closure`、`fixture-path-existence`。Drift: High. Enforcement: Deterministic (hook + exit code)
- `/tmp/dp025-scan-report.md` — 上線後 baseline 盤點報告

**Changed**

- `scripts/validate-task-md.sh` — 擴充 DP-025 非 runtime 檢查：
  - `## Operational Context` 必須含 JIRA key（pattern `[A-Z][A-Z0-9]+-[0-9]+`）
  - `## 目標` / `## 改動範圍` / `## 估點理由` 必須非空（至少 1 行實質內容，跳過 blockquote 註解）
  - `## Test Command` / `## Verify Command` 必須內含 fenced code block
  - 新增 `--scan {workspace_root}` 盤點模式，過濾 `.worktrees` / `node_modules` / `archive`
  - DP-023 runtime 規則原封不動保留
- `.claude/settings.json` — PreToolUse Edit|Write matcher 新增 `pipeline-artifact-gate.sh` hook（與 `design-plan-checklist-gate.sh` 並列）
- `specs/design-plans/DP-025-pipeline-artifact-schema-enforcement/plan.md` — Implementation Checklist 勾選實作完成項目；status 保持 LOCKED（盤點後回補由使用者驅動，checklist 仍有 `[ ]`）

**Scan results (2026-04-22 baseline)**

| Artifact        | Scanned | Pass | Fail |
| --------------- | ------- | ---- | ---- |
| refinement.json | 2       | 2    | 0    |
| task.md         | 13      | 13   | 0    |
| task.md deps    | 3 Epics | 3    | 0    |

All existing exampleco artifacts 通過新 schema — 無需回補。未來 artifact 若違反 schema 會在 Edit/Write 當下被 hook 攔截。

## [3.40.0] - 2026-04-22

### DP-024 P4 pilot — Pipeline handoff evidence artifact (bug-triage → engineering)

承接 v3.39.0 P3，本版啟動 DP-024 P4 pipeline handoff evidence 層。Skill 交接現在可以把支撐結論的原始 tool return（grep 結果、error trace、endpoint response）封裝成 scrubbed + capped artifact，下游 skill 預設信任結論、only on-demand 讀。

P4 pilot 範圍：bug-triage → engineering 單一 handoff。其餘 4 個 handoff 點（breakdown→engineering、engineering→verify-AC、verify-AC FAIL→bug-triage、refinement→breakdown）等 pilot 驗證後再擴散。

**Added**

- `skills/references/handoff-artifact.md` — artifact 格式規範
  - Frontmatter schema（`skill` / `ticket` / `scope` / `timestamp` / `truncated` / `scrubbed`）
  - `## Summary` (≤ 500 字決策摘要) + `## Raw Evidence` (原始 tool return)
  - 20KB 硬上限：head 13KB + `[truncated, N bytes omitted]` marker + tail 6KB
  - Per-skill 「結論不自明」判定（bug-triage: Full Path + AC-FAIL 寫、Fast Path 跳過）
  - On-demand 讀 dispatch prompt 注入模板
- `scripts/snapshot-scrub.py` — 在寫入前 scrub secrets + 20KB cap + frontmatter flag 更新
  - 10+ 種 secret pattern（GitHub PAT/OAuth、OpenAI、Anthropic、Slack、AWS、Bearer、Basic auth、URL token params、labelled secrets）
  - `--file PATH` 原地改寫；`--stdin` 讀 stdin 寫 stdout
  - Smoke test：10/10 patterns 全部 redact、30KB 輸入 → 19KB head+tail+marker

**Changed**

- `skills/bug-triage/SKILL.md` v2.1.0 → v2.2.0
  - Step 3 Full Path Explorer dispatch：artifact 檔名從 `bug-triage-{ts}.md` 改為 `bug-triage-root-cause-{TICKET}-{ts}.md`，明確要求 Summary/Raw Evidence 格式 + 寫入後跑 scrub
  - Step 2-AF.2 AC-FAIL Explorer dispatch：同步換命名為 `bug-triage-ac-fail-{BUG_KEY}-{ts}.md` + scrub
  - Step 5c Handoff + Step 2-AF.4 AC-FAIL handoff：Items 表新增「Evidence artifact」列，讓 engineering 看得到路徑
- `skills/engineering/SKILL.md` v5.0.0 → v5.1.0
  - Phase 2b sub-agent dispatch prompt 新增「## Handoff Artifact (on-demand)」段落，明示預設不讀、只在 task.md ambiguous / 需驗證 claim / 懷疑結論 stale 時打開
- `skills/references/pipeline-handoff.md`：新增 `## Evidence Artifact（Handoff 層的證據載體）`區塊 + 相關 references 清單連到 handoff-artifact.md
- `skills/references/INDEX.md`：JIRA Operations 表格新增 handoff-artifact.md 條目
- `specs/design-plans/DP-024-memory-system-enhancement/plan.md`：新增 D5 decision（P4 pilot 切 bug-triage→engineering、per-skill 判定）、更新 Implementation Checklist 勾選 P4 基礎建設

**Known issue / Follow-up**

- Pilot 尚未跑過真實 bug-triage → engineering 流程驗證端到端。下次 Bug ticket 出現時觀察：artifact 實際寫入、scrub 正常、engineering 正確 on-demand 讀（或正確忽略）
- 擴散到 engineering→verify-AC、verify-AC FAIL→bug-triage 等另 4 個 handoff 點，待 pilot 驗證後再做
- BS#7 規則文件 vs 實作一致性掃描仍是 P4 Implementation Checklist 最後一項

## [3.39.0] - 2026-04-22

### DP-024 P3 — Semantic query for cross-session learnings (D2)

承接 v3.38.0 P2，本版把 D2 向量查詢層補上。`polaris-learnings.sh query` 現支援 `--semantic "text"` 語意搜尋，資料源仍是人為 curated JSONL（no auto-capture, no AI 壓縮），只新增索引層。

**Added**

- `scripts/polaris-embed.py` — Python CLI（在 polaris venv 跑）
  - `embed --text TEXT` 輸出單筆向量 JSON
  - `build-index --learnings FILE --output FILE [--force]` 建/更新 embeddings；按 `text_hash` + `embedding_model` + `embedding_version` 判定需重算的 entry
  - `query --learnings FILE --embeddings FILE --query TEXT [--top N] [--min-confidence M] [--min-similarity F] [--company C]` 回傳 top-N entries（附 `similarity` 與 `effective_confidence`）
  - Model mismatch fail-fast：index 記錄的 model 與查詢 model 不一致直接 exit 3 建議 reindex
  - Company hard-skip：entry `company` 不為空且 != `POLARIS_COMPANY` → 跳過
- `scripts/polaris-embed-setup.sh` — 建立 `~/.polaris/venv`（python3.13）+ 裝 fastembed，idempotent
- `scripts/polaris-learnings.sh` 擴充
  - `reindex [--force] [--model M] [--version V]` 呼叫 embed.py 建/更新索引
  - `query --semantic "text" [--min-similarity F]` 走向量；未附 `--semantic` 維持原信心衰減模式
  - 新增 env：`POLARIS_VENV`、`POLARIS_EMBED_MODEL`（default `sentence-transformers/all-MiniLM-L6-v2`）、`POLARIS_EMBED_VERSION`
- `.claude/skills/references/cross-session-learnings.md § Semantic Query (DP-024 P3)` — setup / 儲存 schema / model versioning / company hard-skip / 依賴說明

**Storage**

`~/.polaris/projects/{slug}/embeddings.json`：

```json
{
  "version": 1,
  "entries": {
    "{key}::{type}": {
      "embedding_model": "sentence-transformers/all-MiniLM-L6-v2",
      "embedding_version": "1",
      "text_hash": "sha256:abcd...",
      "vector": [384 floats]
    }
  }
}
```

**Blind spots resolved**

- BS#2 (embedding model 版本綁定)：每筆記 model+version+text_hash；reindex 漸進重算；query mismatch fail-fast
- BS#4 (multi-company isolation)：query 回傳前套 `POLARIS_COMPANY` hard-skip（與既有 memory 規則一致）

**Dependencies**

- Python 3.13（via Homebrew `python@3.13`）
- `fastembed`（pip install 會帶 onnxruntime + numpy，~120MB）
- 模型首次使用自動下載（`all-MiniLM-L6-v2` ~90MB，cache 在 `~/.cache/huggingface/`）
- 後續 embed ~10ms/query

**Verified behaviors**

- Reindex 建 4 筆原有 learnings → 384 dim 向量落地
- 語意搜尋 "verification agent should not modify files" → 正確命中 `verification-read-only-principle` (similarity 0.54)，其他 entry 遠低於此
- Force reindex 對於 content 未變動但 schema 變動的 entry 全量重算
- Company hard-skip：加一筆 `company: exampleco` 測試，`POLARIS_COMPANY=exampleco` 可見、`POLARIS_COMPANY=other` 隱藏 ✓
- Model mismatch 警報：`POLARIS_EMBED_MODEL=BAAI/bge-small-en-v1.5` 走 query 直接 fail 並建議 reindex ✓

**Known gaps（P3 follow-up）**

- 多語 learnings（zh-TW/English 混合）的 semantic quality 用 `all-MiniLM-L6-v2` 僅驗證 key 命中，完整多語品質待實際使用累積後評估（e.g. 是否換 `paraphrase-multilingual-MiniLM-L12-v2`）
- Strategist preamble injection 尚未整合 semantic 查詢（目前仍走 `query --top 5 --min-confidence 3`）
- P4 D3 pipeline handoff evidence 尚未啟動

## [3.38.0] - 2026-04-22

### DP-024 P2 — PreCompact session summary hook (D4 minimum loop)

承接 v3.37.0 的 P1 bootstrap，把 D4 session summary 寫入路徑的主要觸發點（PreCompact）接好。壓縮前 Claude Code 觸發 hook → hook 注入 prompt 要求 Strategist 寫一行 `session_summary` 到 `polaris-timeline`，下一個 session 可查。

**Added**

- `.claude/hooks/session-summary-precompact.sh` — PreCompact hook
  - Exit 0（永不阻擋壓縮），stdout 注入 prompt
  - Hook 預先從 `git` 和 `polaris-timeline.sh query --since 4h` 推算 `branches` / `tickets` / `skills` / `commits` metadata，組成可直接貼到 shell 的 `polaris-timeline.sh append --event session_summary` 指令範本
  - Strategist 只填 `--text` 一行敘述，metadata 都由 hook 帶好
- `.claude/settings.json` — 新增 `PreCompact` slot 註冊該 hook，`matcher: "auto"`（與現有 `PostCompact` / `post-compact-context-restore` 對稱）
- `mechanism-registry.md § Deterministic Quality Hooks` 新增 `session-summary-precompact` 條目

**Design note**

Hook 不直接寫 timeline — 原因在 D4.5：Strategist 寫 `text`（session 敘述），hook 補 metadata。讓 text 反映實際做了什麼，不是 hook 猜的。v1 不做 dedup（同 session 多次 PreCompact 會有多筆 summary），follow-up 再處理。

**Pairs with**

- `PostCompact` `post-compact-context-restore.sh`（v3.x 前已存在）：壓縮前寫 summary → 壓縮後重建 context 指向最後一筆 summary，形成「壓縮前寫 / 壓縮後讀」的對稱閉環

**Known gaps（P2 follow-up，非 blocker）**

- Stop hook 補位路徑（短 session 從不壓縮的情境）尚未實作
- Dedup（同 `session_id` 多次觸發只保留最後一筆）尚未實作
- `checkpoint` skill 擴充（寫 memory 時同步 append session_summary）尚未實作
- PreCompact hook v1 還沒跑過真實壓縮驗證 — 等實際觸發 auto-compact 時觀察端到端行為

## [3.37.0] - 2026-04-22

### DP-024 P1 — Memory system bootstrap (polaris-learnings + polaris-timeline)

把 rules/skills 大量引用卻不存在的兩個 script 實作出來，補齊 `polaris-learnings.sh` 與 `polaris-timeline.sh` 的骨架，並對齊幽靈 reference。純 POSIX bash + `jq`，無 Python 依賴；向量查詢（P3）與 session summary 自動化（P2）留待後續 phase。

**Added**

- `scripts/polaris-learnings.sh` — JSONL 策劃知識庫
  - Subcommands：`add` / `query` / `confirm` / `list`
  - `add` 用 `key+type` dedup merge，衝突時取 max(confidence)，`last_confirmed` 更新為今天
  - `query` 支援 `--top` / `--min-confidence` / `--company` / `--type` / `--tag`，套 confidence decay（每 30 天 -1）+ multi-company hard-skip
  - `confirm --key K [--type T] [--boost N]` 重置 decay，可選增信心
  - `list` 輸出所有條目 + effective_confidence
- `scripts/polaris-timeline.sh` — append-only JSONL 事件日誌
  - Subcommands：`append` / `query` / `checkpoints`
  - `append` 支援標準欄位（event/skill/ticket/branch/pr_url/outcome/duration/note/company/text）+ 任意 `--field key=jsonvalue` 讓 D4 session_summary 塞 tickets/skills/branches 陣列
  - `query --since today|Nh|YYYY-MM-DD` 解析多種時間表示；`--event` / `--last` 過濾
  - 時戳統一寫 UTC `Z`，reader 容忍 legacy `+0800` / `+08:00`（現有 `~/.polaris/projects/work/timeline.jsonl` 9 筆舊資料無損讀取）

**Changed**

- `.claude/skills/references/session-timeline.md` — schema 範例時戳改為 UTC `Z`（`2026-04-02T06:30:00Z`），`ts` 欄位描述標明「ISO 8601 UTC with Z suffix」
- `.claude/skills/checkpoint/SKILL.md` — 修正 3 處錯誤路徑 `{base_dir}/.claude/skills/references/scripts/polaris-timeline.sh` → `{base_dir}/scripts/polaris-timeline.sh`
- `.claude/skills/refinement/SKILL.md` — 移除 `polaris-learnings.sh query --project {project}` 的不存在 flag，改用 `POLARIS_WORKSPACE_ROOT={workspace_root} polaris-learnings.sh query --top 5 --min-confidence 3`
- `.claude/skills/verify-AC/SKILL.md` — `add` 呼叫原本用的 `--note` / `--ticket` / `--type verify-ac-gap` 不符 v1 CLI，改為 `--key "verify-ac-gap-<AC_KEY>-<step_slug>" --type pitfall --tag verify-ac-gap --content "..." --metadata '{...}'`
- `.claude/designs/problem-analysis-protocol/design.md` — 同樣移除 `--project {project}` flag（gitignored，本地修改）

**Rationale**

rules/skills 過去大量引用 `polaris-learnings.sh` 和 `polaris-timeline.sh`（抄寫在 CLAUDE.md、feedback-and-memory.md、mechanism-registry.md、learning/refinement/verify-AC SKILL.md 等多處），但實作從未存在。DP-024 LOCKED 2026-04-22 後，P1 Bootstrap 先把骨架立起來，讓 `~/.polaris/projects/$SLUG/` 目錄真的有 script 寫入、其他 skill 可 actually 呼叫。P1 範圍刻意不含向量查詢、session summary 自動化、pipeline handoff evidence — 這些在 P2/P3/P4 分別實作。

**Known gaps**

- `.agents/` mirror 仍有同樣的 CLI drift（`--project` flag、錯誤路徑），需下次 `polaris-sync.sh` 同步 `.claude/` → `.agents/`
- `decay-scan` subcommand 未實作（`query`/`list` 已套 decay，先替代）
- D4 session_summary dedup（同 session_id 多次觸發只留最後一筆）P1 未做，P2 設計時決定

## [3.36.0] - 2026-04-21

### Dynamic CI contract parity gate (cross-repo)

把「本地品質檢查」從固定 lint/test 指令擴充為動態 CI contract：先讀 repo 的 CI YAML，再依策略在 local 做同構驗證，提前攔截 PR 才會看到的 patch coverage 失敗。

**Added**

- `scripts/ci-contract-discover.sh`
  - 自動偵測 CI provider（Woodpecker / GitHub Actions / GitLab CI）
  - 正規化輸出 checks contract（install/lint/typecheck/test/coverage）
  - 解析 `codecov.yml` 的 patch gate（flag、target、include/exclude）
- `scripts/ci-contract-run.sh`
  - 執行本地可重現的 contract commands（跳過 upload/token 步驟）
  - 依 codecov patch gate 計算 patch coverage 並做 hard gate
  - 支援 `--dry-run`（只列執行計畫不實跑）
  - 可寫入 `/tmp/polaris-coverage-{branch}.json` evidence

**Changed**

- `scripts/pre-commit-quality.sh`
  - 新增 `CI contract parity` 步驟，結果寫入 quality evidence 的 `results.ci_contract`
  - `all_passed` 現在包含 `ci_contract`（FAIL 直接擋下 quality gate）
- `scripts/codex-guarded-gh-pr-create.sh`
  - 在 PR create gate 前自動執行 `ci-contract-run.sh`（dry-run / real-run 分流）
- `scripts/verification-evidence-gate.sh`
  - repo 含 Codecov patch gate 時，PR 前強制檢查 coverage evidence（PASS + <4h）
- `skills/references/quality-check-flow.md`
  - 新增 `CI Contract Parity` 為 mandatory step，並記錄 `--dry-run` 用法
- `skills/review-inbox/SKILL.md`
  - Scan freshness 硬性規定：snapshot 超過 60 秒必須重跑 Step 1

**Fixed**

- EPIC-478 task title numbering drift:
  - `exampleco/specs/EPIC-478/tasks/T8b.md`: `T9` → `T8b`
  - `exampleco/specs/EPIC-478/tasks/T9.md`: `T10` → `T9`

## [3.35.0] - 2026-04-21

### Runtime contract hardening end-to-end (DP-023)

把「公司 runtime 啟動入口」從慣例升級為可執行契約，並在 `init → breakdown/engineering → validator → PR gate` 全鏈 enforce，避免 runtime 任務被 static 檢查誤判通過。

**Added**

- New design plan: `specs/design-plans/DP-023-runtime-entry-contract/plan.md`（LOCKED）
- `scripts/validate-task-md.sh` 新增 runtime deterministic checks:
  - `## Verify Command` 必填
  - `Level=runtime` 必須有 live endpoint URL
  - Verify URL host 必須與 `Runtime verify target` host 對齊
- `scripts/polaris-write-evidence.sh` 新增 `runtime_contract` evidence metadata（支援 `--task-md` 自動抽取）
- `scripts/verification-evidence-gate.sh` 新增 runtime contract gate（`level=runtime` 時強制 target/verify host 對齊）

**Changed**

- `init`（`.agents` / `.claude`）Step 9a 明確定義 runtime entry contract（runtime project 不可 skip，且設定必須可被 `scripts/polaris-env.sh start <company> --project <repo>` 消費）
- `pipeline-handoff`（`.agents` / `.claude`）明確 Target-first：`health_check` 僅 readiness、`Runtime verify target` 才是行為驗證目標
- `breakdown` / `engineering`（`.claude`）補齊與 `.agents` 一致的 runtime consistency hard-gate 語意
- `mechanism-registry` / `mechanism-rationalizations` / `engineer-delivery-flow` 更新 evidence 與 gate 契約描述

**Validation**

- Contract samples passed: runtime+live endpoint（PASS）、runtime+grep-only（FAIL）、static+grep-only（PASS）
- PR gate samples passed: missing runtime_contract（BLOCK）、runtime host mismatch（BLOCK）、合法 runtime_contract（ALLOW）
- Active runtime tasks scan: `exampleco/specs/**/tasks/*.md` 中 `Level=runtime` 檔案皆通過新版 validator

## [3.34.0] - 2026-04-21

### Runtime env handoff becomes framework-level contract (breaking)

`task.md` 的 runtime 驗證資訊從「隱含於公司知識」升級為 framework 契約，避免 engineering 對 `health_check` / 驗證 URL / 起環境指令產生歧義（例如 local domain 與 localhost 混用情境）。

**Breaking**

- `scripts/validate-task-md.sh` 現在強制 `## Test Environment` 必須包含：
  - `Runtime verify target`
  - `Env bootstrap command`
- 當 `Level=runtime` 時，上述兩欄不可為 `N/A`
- 當 `Level=static|build` 時，上述兩欄必須為 `N/A`

**Changed**

- `skills/references/pipeline-handoff.md`（`.claude` / `.agents`）task.md schema 新增：
  - `Runtime verify target`
  - `Env bootstrap command`
- `skills/breakdown/SKILL.md`（`.claude` / `.agents`）Step 14.5 補充：
  - runtime URL 可為 localhost 或 local domain（不預設視為遠端）
  - runtime 優先引用 workspace/company 的標準啟環境腳本（framework 泛化）
- `skills/breakdown/SKILL.md` metadata version：`2.2.0` → `3.0.0`

**Why**

- `dev_environment.health_check` 只代表 ready probe，不一定是 smoke 驗證入口
- `Runtime verify target` 與 `Env bootstrap command` 顯式化後，engineering 可 deterministic 地起環境與驗證，不依賴公司 tacit knowledge

## [3.33.0] - 2026-04-21

### Branch switching = worktree — universal framework default

多工並行是 Polaris 預設前提：使用者主 checkout 隨時可能有平行 WIP（編輯中、dev server 跑著、另一 session 在用）。先前 worktree 規則只收斂 engineering batch mode / revision / planning skills Tier 2+ 等窄路徑，逐個 skill 補規則會漏。本版將「任何會改變主 checkout HEAD/branch/working tree 的操作都須用 worktree」提升為 framework-level universal default。

**Added**

- `rules/sub-agent-delegation.md` § Operational Rules 新增「Branch switching = worktree (universal default)」bullet — 適用 Strategist、所有 skill、所有 sub-agent；列出例外（read-only 檢視、純 JIRA/Confluence/Slack、當前主 checkout 分支的編輯）+ worktree 命名慣例
- `rules/mechanism-registry.md` 新增 canary `branch-switch-requires-worktree` (High drift) — 任何 `git checkout` / `git switch` / `git pull` 在主 checkout path 執行都觸發
- Memory `feedback_branch_switch_requires_worktree.md` (pinned) 記錄決策背景與 canary signal

**Changed**

- `rules/sub-agent-delegation.md` 移除舊的「Worktree isolation for batch implementation」窄規則（已被通則吸收）；「Worktree for operations requiring isolation」bullet 重寫為通則的具體應用清單
- `rules/mechanism-registry.md` 舊 canary `worktree-for-batch-impl` 標註為 `branch-switch-requires-worktree` 的具體子案例

**Why**：避免「planning skill 要 worktree、engineering 第一次實作不用、Strategist 主 session 順手切分支沒規則可管」這種逐例外補洞的累積。Universal default + specific reinforcement 比散落在各 skill 的規則好維護。

## [3.32.0] - 2026-04-21

### task.md `## Test Environment` section — pointer mode for dev env handoff

EPIC-478 實作期間發現 engineering sub-agent 讀 task.md 後不知道如何起測試環境（T3 需 `pnpm build` 產 `.output/`，T2 需 curl live dev.exampleco.com）。breakdown 只把 workspace-config 的 `test_command` 抽到 task.md，沒寫 dev server / docker / mockoon 啟動指引，pipeline handoff 契約缺這一段。

**Added**

- `skills/references/pipeline-handoff.md` task.md schema 新增 `## Test Environment` 區塊：
  - `Level: {static | build | runtime}` — 告訴 engineering 本 task Verify Command 需要的環境層級
  - `Dev env config` — 指向 `workspace-config.yaml` → `projects[{repo}].dev_environment`（pointer 模式，不複製細節）
  - `Fixtures` — mockoon fixture path 或 `N/A`
- `skills/breakdown/SKILL.md` Step 14.5 新增 Test Environment 填寫規則，含 Level 決策流程表（依 Verify Command 特徵判斷）
- `scripts/validate-task-md.sh` 新增 `## Test Environment` 為必要區塊，並驗證 Level 值合法性
- `skills/engineering/SKILL.md` sub-agent prompt 新增 Level-based 環境準備流程（static → skip / build → `pnpm build` / runtime → 依 `dev_environment.requires` + `start_command` + 選配 mockoon）
- `rules/mechanism-registry.md` 新增兩條 canary：
  - `task-md-test-env-section` (High) — task.md 必須含 Test Environment 區塊
  - `engineering-reads-test-env` (High) — engineering 必須依 Level 起環境

**Changed**

- EPIC-478 T1-T9 task.md 全數補上 `## Test Environment` 區塊（T1 runtime + fixtures, T2/T6/T7 runtime, T3/T4/T5 build, T8a/T8b/T9 static）

**Why pointer mode**：dev_environment 細節（`start_command`、`requires`、`health_check`、`is_monorepo`）已在 workspace-config，單一來源。複製進 task.md 會 stale — workspace-config 改了沒人同步。engineering sub-agent 依 Level 自行讀 workspace-config。

**Deterministic enforcement**：`validate-task-md.sh` 硬性擋缺漏（exit 1），不靠 AI 自律。符合 `CLAUDE.md § Deterministic Enforcement Principle`。

## [3.31.0] - 2026-04-21

### /learning 知識落地鏈路 (DP-019)

兩條主軸：Track 1 新增 /learning → /design-plan seeding handoff 讓 rich research 不再只存在對話裡；Track 2 把 version-bump backlog scan 從 aspirational 變 deterministic（warn-only v1）。

**Added**

- `.claude/skills/design-plan/SKILL.md` (v1.2.0):

  - 新增 `SEEDED` 作為 plan frontmatter `status` 合法值（原有：DISCUSSION / LOCKED / IMPLEMENTED / ABANDONED）
  - Phase 1 新增 Mode B（DP-NNN argument trigger）：`/design-plan DP-019` 讀 `artifacts/research-report.md` 產初版 Goal / Background / D1 候選
  - Mode B fail loud if report missing（BS#16 — 不 silent fallback）
  - Mode B status-based 分支：SEEDED/DISCUSSION/ABANDONED 可 consume；LOCKED/IMPLEMENTED 強制新開 DP（BS#19）
  - Report → plan mapping 規則（BS#3'）：Goal → Goal；Matrix+Compile → Background summary+link；每個 Recommendation → D{N} 候選（Context=Why, Decision=What, Rationale=How+Landing；Effort/Priority 不帶進 plan）
  - Integration table 新增 `/learning` 列

- `.claude/skills/learning/SKILL.md`:

  - Step 5 改為主動呈現三路徑（DP / backlog / learnings-only），支援混選（D10 — 不做自動分類樹，由使用者判斷）
  - 新增 "design-plan seeding" sub-flow（D12）：建 DP folder + artifacts/ + research-report.md（固定 structure：Goal / Comparison Matrix / Knowledge Compile Results / Recommendations）+ stub plan.md (status: SEEDED) + 告知 DP 編號，**不** auto-invoke /design-plan
  - Quick-path gate（BS#15）：depth tier == Quick 時禁走 DP 路線
  - Fuzzy slug pre-check against existing DPs，status-based 分支（BS#5/#19）
  - Inline DP-NNN allocation（BS#2 — 不抽 script）
  - DP route 下 skip polaris-backlog entry，照寫 learnings（D4）

- `.claude/hooks/version-docs-lint-gate.sh`:

  - VERSION staged 時新增 backlog scan（D11 + BS#20 warn-only v1）
  - 列出所有 open `[ ]` 項目 + age（days since `(YYYY-MM-DD)` creation date）
  - 標記 age > 14d 且無 park tag（`[next-epic]`/`[platform]`）的項目
  - Warn-only：不 block commit（觀察期再決定是否升級 block-mode）
  - Bypass: `POLARIS_SKIP_BACKLOG_SCAN=1`

- `scripts/generate-specs-sidebar.sh`:
  - SEEDED 狀態 → 🌱 badge（BS#21）

**Design Notes**

- DP-019 本身經過 scope 擴大：從「單點 handoff」升級成「/learning 知識落地完整鏈路」，涵蓋 Track 1（大 gap → /design-plan → 實作）和 Track 2（小 gap → backlog → version bump 帶走）
- D2 原提議 /learning direct-write 進 plan.md，被 D9 取代為 research-report.md artifact 模式（separation of concerns）
- D9 原提議 /learning 自動 invoke /design-plan，被 D12 取代為 seeding 模式（使用者用 `/design-plan DP-NNN` 顯式消費），解決 Quick-path report 殘缺、silent fallback、多 recommendation fan-out 等 blind spots
- Track 2 依 Explorer 證據（`specs/design-plans/DP-019-.../artifacts/backlog-close-pattern.md`）：68% done entries 在 VERSION bump 時被帶走、median time-to-close = 0 天、7 個 open 項目無真正 rot。結論：不加新 actor，強化既有 trigger 即可

**Deferred**

- BS#13 closure-intent convention 具體格式（`Backlog-closes:` PR desc / commit trailer / 同 commit 同做）
- BS#14 monthly standup fallback 命運（enforce 或刪殭屍）
- 兩者待 D11 hook 觀察期後依 friction 決定

## [3.30.0] - 2026-04-20

### Knowledge Compilation Protocol (DP-018) + docs-viewer done-link active color

Added a framework-level canonical reference for knowledge compilation semantics (Atom vs Derived boundary + backwrite policy + parallel naming lock), wired it into learning/reference discovery, and introduced two behavioral canaries for auditability. Also fixed docs-viewer sidebar styling so completed entries remain green when selected (active state).

**Added**

- `.claude/skills/references/knowledge-compilation-protocol.md` (and `.agents/` mirror) — canonical framework policy:
  - Atom vs Derived contract
  - Backwrite requirements when editing derived artifacts first
  - Parallel naming lock protocol (pre-locked slots before fan-out)
  - Mapping and compliance IDs

**Changed**

- `.claude/rules/mechanism-registry.md` — new Knowledge Compilation section:
  - `knowledge-source-of-truth-boundary` (High drift)
  - `parallel-doc-naming-lock` (Medium drift)
- `.claude/skills/references/INDEX.md` (and `.agents/` mirror) — indexed `knowledge-compilation-protocol.md` as canonical entry
- `.claude/skills/learning/SKILL.md` (and `.agents/` mirror):
  - added “Knowledge compilation” extraction category
  - synthesis wording now normalizes compile/source-of-truth findings to canonical terms (Atom layer / Derived layer / Naming Lock)
- `docs-viewer/index.html` — completed sidebar entries (`.done`) keep green color in active state (`.done a.active`), avoiding docsify default blue override

**Notes**

- DP-018 design-plan file lives under `specs/design-plans/` and remains local-only per workspace `.gitignore` convention; release includes the implemented framework policy/docs changes.

---

## [3.29.0] - 2026-04-20

### Absorb `/next` into `/my-triage` (DP-017)

`/next` skill removed. The "zero-input what should I do" scenario — its original intent — turned out to be already covered by `/my-triage` (assigned work + Bug priority + PR progress). `/next`'s own Level 4 fallback admitted this by deferring to `/my-triage`. Rather than maintain two skills with overlapping scope and fragile PR/JIRA state auto-routing (Level 0-3), zero-input triggers now land directly on `/my-triage` with a new Step 0 Resume scan that covers cross-session recovery (branch-ticket context, MEMORY.md Hot signals, recent checkpoints, `wip/*` branches).

**Changed**

- `.claude/skills/my-triage/SKILL.md` — v1.1.0 → v1.2.0: description + triggers extended with zero-input tokens (下一步、繼續、然後呢、what's next、接下來、推進手上的事情); new Step 0 Resume scan (branch-ticket priority → MEMORY.md Hot scan → checkpoints 7d → `wip/*` branches); new Group 0 「🔄 上次未完成」 ordered ahead of Bug group.
- `.claude/rules/skill-routing.md` — removed `/next` routing row; `my-triage` trigger row extended with zero-input tokens and disambiguation note (`when no ticket key / topic keyword follows`); new sub-section under Core Rule: "Zero-input Triggers in Active Skill Session" (triggers do not auto-route when an active skill session is in progress).
- `CLAUDE.md` — § Cross-Session Continuity opening clause added: trigger requires topic keyword (e.g., 「繼續 DP-015」); bare 「繼續」 / 「下一步」 → `/my-triage`.
- `.claude/skills/engineering/SKILL.md`, `.claude/skills/references/epic-verification-workflow.md` (and `.agents/` mirrors) — `/next` references replaced with `/my-triage`.
- `docs/workflow-guide.md` — removed `NX` Mermaid node + 5 edges; expanded `MT` node to cover auto-route duties.
- `.claude/polaris-backlog.md` — historical item annotated with absorption note.

**Removed**

- `.claude/skills/next/` — folder deleted. Four blind spots from DP-017 plan each have corresponding mitigation in the changes above.

**Rationale**

Original `/next` design as "quick entry point when the user doesn't know what to do next" drifted over time as sibling skills matured — `/check-pr-approvals` took PR inspection, `/my-triage` ranked all assigned work, Cross-Session Continuity rules handled explicit "繼續 X". What remained for `/next` was a shrinking middle ground that its own Level 4 deferred to `/my-triage`. Consolidating the last unique niche (cross-session resume without topic keyword) into `/my-triage` Step 0 collapses "what should I work on?" into a single skill and eliminates fragile auto-routing across PR/JIRA state combinations.

---

## [3.28.0] - 2026-04-20

### Memory Hot/Warm/Cold tiering (DP-015 Part B B8–B14 + B16)

Complete the memory tiering system designed in `DP-015-polaris-context-efficiency`. Before this change, `memory/` was a flat pile of 92 files with no decay: `MEMORY.md` was drifting toward the 200-line truncation risk and every conversation loaded every entry. Now entries live in three tiers — Hot (loaded every session), Warm (per-topic folder, pulled on demand), Cold (`archive/`, never auto-loaded) — with a session-start advisory and a manual `/memory-hygiene` skill for pruning.

**Added**

- `scripts/memory-hygiene-tiering.py` — three modes: `dry-run` (classify without moving + markdown or JSON output), `apply` (execute a plan from stdin JSON, move files, rewrite `MEMORY.md`, create topic `index.md` files, write `.migration-log.md`), `decay-scan` (advisory, lists candidates without moving). Classification: `pinned` OR `last_triggered >= today-30d` OR `trigger_count >= 5` -> Hot; `last_triggered >= today-90d` -> Warm (grouped by `topic`); else Cold.
- `.claude/hooks/memory-decay-scan.sh` — SessionStart hook that runs `decay-scan` once per day (stamped at `/tmp/polaris-memory-decay-scan-YYYY-MM-DD`). Advisory output only, never blocks session start.
- `.claude/skills/memory-hygiene/SKILL.md` — manual `/memory-hygiene` skill with three modes (scan / dry-run / apply). Used when the SessionStart advisory fires, `MEMORY.md` Hot grows past the 15-entry soft limit, or for periodic cleanup.

**Changed**

- `.claude/rules/feedback-and-memory.md` — new `§ Memory Tiering (Hot / Warm / Cold)` section: tier table, write discipline (check topic folder first, otherwise flat), frontmatter fields (`pinned: bool`, `topic: string`), decay & migration flow, boundary with `polaris-learnings.sh`.

**User-level** (not in this repo, done manually)

- `~/.claude/CLAUDE.md` — new `# Memory Tiering Rules` section (three rules per D7.5: topic-folder routing, <= 15 Hot soft limit, pinned/topic frontmatter).
- `~/.claude/settings.json` — register `SessionStart` hook pointing at `.claude/hooks/memory-decay-scan.sh`.
- `MEMORY.md` — header tiering-overview block (soft limit note + format spec + frontmatter fields).

**Status**

- B15 (fresh-session end-to-end validation) deferred to next new session — V1–V4 (script, hook script, dry-run, header) verified in-place; V6–V8 (real SessionStart fire, skill trigger, Hot <= 15 apply run) require a new session.

---

## [3.27.0] - 2026-04-20

### Task-level done marking on PR creation (and setup-only exception)

Extend v3.26.x Epic/Bug done marker down to individual tasks. Previously `mark-spec-implemented.sh` only resolved `specs/{TICKET}/refinement.md` / `plan.md`; now it also resolves `specs/{EPIC}/tasks/T*.md` by matching the `> JIRA: KEY` header. Engineering now auto-calls the helper after PR creation (new **Step 8a**), so task-level specs get marked done the moment their PR lands. Also documents the setup-only task path (no code to commit — e.g., TASK-3821 Mockoon fixture setup — transitions directly to Done).

**Changed**

- `scripts/mark-spec-implemented.sh` — two-path resolution: Epic-anchor first, Task-anchor (by `> JIRA: KEY` header grep across `specs/*/tasks/T*.md`) fallback. Same idempotent behavior. Error message lists both search paths.
- `scripts/generate-specs-sidebar.sh` — reads each task.md's own `status:` frontmatter. Task's own status overrides parent inheritance. Task entries get the same `✅` / `❌` badge as Epic entries.
- `.claude/skills/references/engineer-delivery-flow.md` — new **Step 8a** (Developer only): call `mark-spec-implemented.sh {TICKET}` after Step 8 JIRA transition. Admin mode skips.
- `.claude/skills/engineering/SKILL.md` — documents the setup-only task path (no code → skip delivery flow → JIRA transition + helper call + branch cleanup). Rare exception, not the common path.
- `.claude/rules/mechanism-registry.md` — `spec-status-mark-on-done` rule extended to cover Task-level anchors and engineering writers (Step 8a + setup-only exception).

**Rationale**

Discovered during TASK-3821 (EPIC-478 T1 — Mockoon fixtures) execution. The task transitioned directly to JIRA Done (no PR because all deliverables were gitignored), but T1.md remained at full opacity in docs-viewer — sidebar showed incomplete state while the task was already done. Follow-up analysis also revealed that normal task flows (PR → merged) were not marking task.md either, because the v3.26.x helper only handled Epic-level anchors. v3.27.0 closes both gaps.

## [3.26.1] - 2026-04-20

### Task entries inherit parent done status

Follow-up on v3.26.0 DP-014: when the parent Epic/Bug is `IMPLEMENTED` or `ABANDONED`, task entries under it (`tasks/*.md`) now also render with `<span class="done">` in the sidebar. Previously the parent was greyed but the tasks underneath were not, making completed Epic subtrees look half-done.

**Changed**

- `scripts/generate-specs-sidebar.sh` — tasks inherit parent ticket's done state. No change to writer contract (task-level `status:` frontmatter still out of scope for DP-014).

## [3.26.0] - 2026-04-20

### Epic/Bug Done Marker in docs-viewer

DP-014 — mirror the DP pattern: completed Epic/Bug/task spec entries in the docs-viewer sidebar are now greyed out + ✅ when marked `status: IMPLEMENTED`. Previously only Design Plans had this; Epic/Bug entries looked identical whether done or untouched.

**Added**

- `scripts/mark-spec-implemented.sh` — idempotent helper to set `status: IMPLEMENTED` / `ABANDONED` / `LOCKED` / `DISCUSSION` in `{company}/specs/{TICKET}/refinement.md` (or `plan.md`) frontmatter. Creates frontmatter if absent; only rewrites the status line if present.

**Changed**

- `scripts/generate-specs-sidebar.sh` — detects `status` frontmatter on `refinement.md` / `plan.md` and wraps Epic/Bug entries in `<span class="done">` when `IMPLEMENTED` or `ABANDONED`. Also made `extract_frontmatter_field` tolerate missing fields (prevents `set -e` abort when anchor files have no frontmatter).
- `.claude/skills/verify-AC/SKILL.md` — Step 7 (Epic mode, all AC PASS) now calls `mark-spec-implemented.sh {EPIC_KEY}` after notifying the user that the Epic is mergeable.
- `.claude/skills/check-pr-approvals/SKILL.md` — new Step 10.1: when Step 10 detects a MERGED PR, extract the ticket key and call `mark-spec-implemented.sh {TICKET}` for Bug / ad-hoc task specs. Epic IMPLEMENTED marking stays with verify-AC.

**Mechanism**

- New canary `spec-status-mark-on-done` (Medium drift) in `.claude/rules/mechanism-registry.md` under Delivery Flow Contract.

**Design Plan**

- `specs/design-plans/DP-014-epic-bug-done-marker/plan.md` — design decisions, writer responsibilities, out-of-scope items (Epic aggregation, JIRA sync).

**Out of scope**

- Engineering (PR open) does NOT mark IMPLEMENTED — PR open ≠ merged. Marking happens at merge detection (`check-pr-approvals`) or AC pass (`verify-AC`). Manual override via direct frontmatter edit remains supported.

## [3.25.0] - 2026-04-20

### Codecov Patch Gate — Deterministic Enforcement

TASK-3847 retrospective — a framework-produced PR failed CI because new source lines had no test coverage. Lesson pushed into a deterministic layer (hook + skill gates) rather than behavioral memory.

- **New hook** `.claude/hooks/coverage-gate.sh` (PreToolUse, `git push*`): detects repos with Codecov patch gate (`codecov.yml` `type: patch` or workflow referencing `codecov/patch`), blocks push unless `/tmp/polaris-coverage-{branch-slug}.json` exists with status=PASS, fresh (<4h), and branch match. Bypass via `POLARIS_SKIP_COVERAGE=1` or `wip:` commit prefix.
- **New script** `scripts/write-coverage-evidence.sh`: writes the evidence JSON (`{branch, status, timestamp, note, patch_files[]}`) for skills to record PASS/FAIL
- **`engineering/SKILL.md`**: surfaces coverage gate awareness in TDD section + automated flow
- **`references/engineer-delivery-flow.md`**: new § Step 2a Coverage Gate Check (detection signals, required steps, evidence writer invocation, bypass)
- **`references/tdd-smart-judgment.md`**: § 0 precondition — repo with patch gate overrides the judgment table (all source file changes require tests)
- **`rules/mechanism-registry.md`**: Quality Gates section gains `codecov-patch-gate` canary (Critical); Deterministic Quality Hooks section gains `coverage-evidence-required` entry

### Settings

- `.claude/settings.json`: registers `coverage-gate.sh` as second PreToolUse hook on `Bash(git push*)`

## [3.24.0] - 2026-04-20

### Pipeline Unification — bug-triage produces refinement artifacts (DP-013)

Unified the pipeline so all ticket types (Bug, Epic, Story, Task) share the same Layer 2-4 flow. bug-triage now produces `refinement.md` + `refinement.json` (same schema as refinement skill), enabling breakdown to consume a single artifact format regardless of ticket type.

- **bug-triage SKILL.md** (v2.2.0): Step 5 expanded — after RD confirmation, produces `specs/{BUG_KEY}/refinement.md` + `refinement.json` alongside JIRA comment
- **breakdown SKILL.md**: Bug Path B1 now checks `refinement.json` first (same early-exit as Planning Path); JIRA comment parsing is fallback for legacy bugs. Added `fix/{BUG_KEY}-{slug}` branch pattern for Bug tickets
- **pipeline-handoff.md**: Rewritten pipeline overview as 4-layer unified architecture (Layer 1 varies by ticket type, Layer 2-4 identical)
- **refinement-artifact.md**: `epic` field description updated to "ticket key (Epic, Story, Task, or Bug)"
- **workspace-config.yaml**: Added `fix` branch pattern to `git.branch_patterns`

## [3.23.0] - 2026-04-17

### review-inbox Slack Fallback Hardening

Improved review-inbox reliability when Slack MCP is unavailable by adding a deterministic CLI fallback path.

- Added `scripts/slack-webapi.sh` for Slack Web API fallback (`read-channel`, `read-thread`, `send-message`)
- Updated `review-inbox/SKILL.md` to explicitly route Slack/Thread modes through MCP first, then fallback CLI
- Extended `scripts/extract-pr-urls.py` to parse both MCP-formatted output and Slack Web API `messages[]` JSON

### Cross-LLM Parity Script Reliability

Fixed parity verification edge cases that could produce false drift in Codex bootstrap flows.

- `scripts/mechanism-parity.sh`: guard empty-array loops under `set -u`
- `scripts/mechanism-parity.sh`: follow symlinked `.agents/skills` with `find -L`
- Re-verified with `scripts/verify-cross-llm-parity.sh` (`CROSS-LLM PARITY OK`)

## [3.22.0] - 2026-04-17

### Claude/Codex Compatibility Gates (DP-012 P1-P3)

Completed DP-012 rollout for deterministic gate parity between Claude and Codex.

**Codex fallback wrappers added**:

- `scripts/gate-hook-adapter.sh` to execute Claude-style gate scripts with synthetic hook JSON
- `scripts/codex-guarded-git-commit.sh` (`quality-evidence-required`, `version-docs-lint-gate`)
- `scripts/codex-guarded-gh-pr-create.sh` (`verification-evidence-required`)
- `scripts/codex-guarded-git-push.sh` (`pre-push-quality-gate`)
- `scripts/codex-guarded-bash.sh` (`safety-gate`)
- `scripts/codex-mark-design-plan-implemented.sh` (`design-plan-checklist-gate`)

**Parity verification strengthened**:

- `scripts/verify-cross-llm-parity.sh` now checks fallback wiring + smoke tests for P0/P0.5/P1 wrappers

### Docs Viewer Sidebar Sync Hardening

Resolved the mismatch where design plan status could be updated via Bash wrapper without triggering Claude `PostToolUse(Edit/Write)` sidebar sync.

- `codex-mark-design-plan-implemented.sh` now invokes `scripts/docs-viewer-sync-hook.sh` after successful status transition
- Ensures `docs-viewer/_sidebar.md` reflects `IMPLEMENTED` plans immediately in Codex wrapper flow

## [3.21.0] - 2026-04-17

### review-inbox Context Optimization

Three changes to reduce review-inbox's main session context consumption:

**Step 5 notification sub-agent delegation**:

- Slack notification logic (GitHub→Slack user mapping + thread replies) moved entirely to a sub-agent
- Main session no longer runs the 4-step lookup chain per author or assembles mrkdwn messages
- Applies to both Label mode (channel summary) and Slack/Thread mode (per-thread replies)

**SKILL.md slimdown** (397 → 273 lines, −31%):

- Format templates (JSON schema, review_status table, Slack mrkdwn, conversation summary) extracted to `references/review-inbox-templates.md`
- SKILL.md retains flow logic only; sub-agents read templates from reference file

**Review dispatch prompt scripting** (`scripts/build-review-prompt.sh`):

- Generates per-PR prompt files from candidates JSON, eliminating manual prompt assembly in main session
- Outputs manifest JSON for Strategist to iterate and dispatch sub-agents
- Step 4 now: run script → read manifest → parallel dispatch (each sub-agent reads its prompt file)

## [3.20.0] - 2026-04-17

### Deterministic Context & Completion Hooks

Three new mechanisms inspired by Boris Cherny's Claude Code tips, pushing behavioral rules into deterministic enforcement:

**PostCompact hook** (`.claude/hooks/post-compact-context-restore.sh`):

- Fires after auto-compaction, re-injects branch, ticket, modified file count, stash count
- Prompts Strategist to confirm company context — replaces behavioral-only `post-compression-company-context`
- Registered in settings.json as PostCompact hook (auto trigger only)

**Stop hook** (`.claude/hooks/stop-todo-check.sh`):

- On substantial sessions (10+ tool calls), blocks Claude from stopping until todo review is confirmed
- Prevents premature completion — the #1 quality drift in long sessions
- Checks `stop_hook_active` to prevent infinite loops

**Auto-compact window** (`CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`):

- Added to `~/.claude/settings.json` env block
- Triggers compaction at 400k tokens, before reasoning quality degrades (300-400k range)
- Complements `context-pressure-monitor.sh` (tool-call count) with token-level precision

**Mechanism registry + context-monitoring.md** updated with all three new entries.

## [3.19.0] - 2026-04-17

### Revision Mode — Behavioral Verification Hard Gate

Rebase-only revision (no review comments to fix) was silently skipping R5 behavioral verification. Now R5 is mandatory for ALL revision paths.

**Engineering SKILL.md:**

- New § R2d Empty-Signal Route: when review signals are empty (QA-reported, rebase-only), skip R3-R4 but still run R5
- R5 title updated to "硬門檻 — 所有 revision path 必經", explicit that rebase-only must verify

**Mechanism Registry:**

- New `revision-r5-mandatory` (Critical): canary detects `git push` in revision mode without behavioral verification

### Specs Sidebar — Universal Auto-Sync

Previously only design-plan triggered sidebar regeneration. Now all skills writing to `specs/` (bug-triage, breakdown, refinement) auto-trigger via broadened hook pattern.

**specs-sidebar-sync.sh:** Pattern `*/specs/*/*.md` covers plan.md, refinement.md, and any spec file
**generate-specs-sidebar.sh:** Detects `plan.md` in company epic dirs (standalone bug/ticket specs no longer skipped); title dedup strips ticket key prefix
**docs-viewer/index.html:** Sidebar overflow scroll fix + docsify-sidebar-collapse plugin for collapsible epic sections

## [3.18.0] - 2026-04-17

### Pre-Work Rebase — Mandatory Before Development/Revision

Rebase moved from delivery-time (Step 5) to pre-development/pre-revision, so conflicts surface before coding starts — not after.

**Engineering SKILL.md:**

- New § 4.5 Pre-Development Rebase (first-cut): rebase after branch checkout, before TDD
- New § R0 Pre-Revision Rebase (revision mode): rebase before reading work order
- Batch sub-agent prompt: new § 1.5 mirrors the same gate

**cascade-rebase.md → Pre-Work Rebase (renamed):**

- Generalized from "feature branch only" to all branch types (task→feature, feature→develop, task→develop)
- Added "why before development" rationale and feature PR edge case

**engineer-delivery-flow.md:**

- Step 5 downgraded to "Final Re-Sync" — skips when base hasn't moved since pre-work rebase

**mechanism-registry.md:**

- New `pre-work-rebase` entry (High drift): canary = Edit/Write on source files without prior `git rebase`

## [3.17.0] - 2026-04-17

### Remove Graduation Mechanism — Direct Rule Write

Replaced the `trigger_count >= 3` graduation pipeline with immediate direct rule write. Confirmed corrections are now promoted to rules immediately, not after 3 triggers.

**Core behavior change:**

- `feedback-and-memory.md` item 2: "referenced >= 3 times → graduation" → "confirmed correct → direct rule write"
- `mechanism-registry.md`: deleted `graduation-at-three-triggers` canary row + Priority Audit #10 reference
- `framework-iteration.md`: updated framework-experience signals table + constraints
- `trigger_count` field retained as usage frequency tracker, no longer a promotion gate

**References rewritten (7 files):**

- `feedback-memory-procedures.md`: "Standard Graduation" → "Direct Rule Write", manual trigger updated
- `cross-session-learnings.md`: "Graduation Pipeline" → "Promotion Pipeline", schema fields `graduated` → `promoted`
- `post-task-reflection-checkpoint.md`: "Graduation Check" → "Rule Promotion Check"
- `INDEX.md`: 2 description updates
- `quality-check-flow.md`, `epic-verification-workflow.md`: terminology updates

**Skills updated (5 files):**

- `validate/SKILL.md`: removed `(should graduate)` flag from check 6
- `sprint-planning/SKILL.md`: deleted Pre-Step graduation scan (12 lines)
- `standup/SKILL.md`: deleted Post-Step graduation scan (12 lines)
- `learning/SKILL.md`: 3 graduation references updated
- `review-pr/SKILL.md`: classification table updated

**Script:** `polaris-learnings.sh` — `graduate` subcommand renamed to `promote` (backward compat alias kept)

**Other:** CLAUDE.md, README.md (Pillar 2 rewrite), `_template/rule-examples/`, `exampleco/docs/rd-workflow.md` (removed phantom `review-lessons-graduation` node)

## [3.16.0] - 2026-04-17

### DP-009 Close: Deterministic Checklist Gate + D3 Detail Path Propagation

**design-plan-checklist-gate (new deterministic hook)**

- `scripts/design-plan-checklist-gate.sh`: PreToolUse hook on Edit/Write — blocks `status: IMPLEMENTED` when plan has unchecked `[ ]` items in Implementation Checklist
- Registered in `settings.json` PreToolUse, `mechanism-registry.md` upgraded from behavioral to deterministic
- Root cause: Strategist skipped checklist check when closing DP-009 — behavioral rule failed, now enforced by hook

**D3 Detail path propagation (gap fix)**

- 13 SKILL.md files updated with Completion Envelope Detail path instructions in sub-agent dispatch prompts
- Root cause: v3.14.0 deferred this item claiming "Reference Discovery auto pull-in" — but sub-agents don't read INDEX.md; dispatch prompts are the only delivery mechanism

## [3.15.0] - 2026-04-17

### DP-009: Context Consumption Optimization (D2 — Rules Slimming)

Rules auto-load reduced from 1,520 → 879 lines (−641, 42%). Procedure and reference content moved to `skills/references/` (loaded on-demand via INDEX.md triggers).

**Whole file moves:**

- `library-change-protocol.md` → `skills/references/library-change-protocol.md` (rules/ stub: 7 lines)

**Split extractions:**

- `framework-iteration.md`: procedures → `skills/references/framework-iteration-procedures.md` (119→57 lines)
- `feedback-and-memory.md`: graduation, hygiene, carry-forward, dedup, backlog, frontmatter, injection scan → `skills/references/feedback-memory-procedures.md` (328→103 lines)
- `sub-agent-delegation.md`: model tiers, T1/T2/T3, scoring, isolation, restore, fan-in, safety hooks → `skills/references/sub-agent-reference.md` (188→21 lines)
- `mechanism-registry.md`: all Common Rationalizations + Deterministic Hooks detail → `skills/references/mechanism-rationalizations.md` (338→272 lines)

**Reference integrity:**

- INDEX.md: 5 new entries with triggers
- 4 SKILL.md broken path fixes (learning, converge, design-plan, post-task-reflection-checkpoint)
- mechanism-registry source path updated for library-change-protocol

## [3.14.0] - 2026-04-17

### DP-009: Context Consumption Optimization (D1, D3, D4)

Structural improvements to reduce per-session context consumption. D2 (rules slimming) deferred to a separate session.

**D1: hooks override prevention**

- `/validate` Mechanisms mode check 10: scans `settings.local.json` for `hooks` key → warn
- `polaris-sync.sh` deploy: post-sync check warns if deployed `settings.local.json` contains `hooks`
- New rule in `CLAUDE.md` Additional Rules: `settings.local.json` must not define `hooks` key
- `mechanism-registry.md`: new `no-hooks-in-local-settings` canary; updated `version-docs-lint-gate` description (now in `settings.json`)

**D3: sub-agent structured return**

- `sub-agent-roles.md` Completion Envelope: new `Detail` line + Summary ≤ 3 sentences + "Summary vs Detail Separation" section with write path rules (Epic/DP/tmp) and verified flag
- `epic-folder-structure.md`: new `artifacts/` subdirectory for sub-agent detail files
- Exploration Pattern dispatch prompt updated to reference Envelope format
- `mechanism-registry.md`: `subagent-completion-envelope` canary upgraded to High with Detail check

**D4: skill-completion session split + checkpoint todo-diff**

- `context-monitoring.md` § 5a-bis: skill completion as natural session split point (decision table + override rules)
- New `scripts/checkpoint-todo-diff.sh`: fuzzy-matches todo items against checkpoint content, exit 1 on missing items
- `post-task-reflection-checkpoint.md` Step 5: todo-diff as hard gate before session split notification
- `mechanism-registry.md`: new `skill-completion-split` + `checkpoint-todo-completeness` canaries

## [3.13.0] - 2026-04-17

### DP-006: verify-AC Fixture/Environment Gap

Closes the fixture gap that caused EPIC-521 AC verification to return all UNCERTAIN — verify-AC couldn't start fixture servers because breakdown didn't produce verification task.md files.

- **breakdown SKILL.md** Step 10D: verification tickets now generate `task.md` with `fixture_required`, `fixture_path`, `fixture_start_command`, `test_urls`, `env_start_command`
- **verify-AC SKILL.md** Step 3: restructured into 3a–3d sub-steps — read task.md → fallback auto-detect `specs/{EPIC}/tests/mockoon/` → start dev server → start fixture server
- **engineer-delivery-flow.md** Step 3b+: new fixture existence advisory check (warning when `fixture_required: true` but mockoon dir empty)
- **pipeline-handoff.md**: updated verify-AC contract — now reads task.md for fixture config + JIRA description for verification steps

## [3.12.0] - 2026-04-17

### DP-007: User Config Isolation + Docs Viewer Hot Reload

Fixes user-specific data leakage when sharing the framework with teammates. Colleague discovered hardcoded GitHub username (`daniel-lee-kk`) in company handbook leaking to all framework users.

**User config isolation (DP-007)**

- Removed hardcoded `developer account daniel-lee-kk` from `rules/exampleco/handbook/index.md`
- Added `user:` section to `workspace-config.yaml` — config-first, fallback `gh api user`
- Updated `workspace-config.yaml.example` with user section template
- Updated `skills/references/shared-defaults.md` — GitHub username lookup now reads config first
- New `scripts/scan-user-data-leak.sh` — detects hardcoded user data in `rules/`
- Integrated scan into `validate` skill (Isolation mode check #5)
- Added Content Constraints section to `skills/references/repo-handbook.md` — no user-specific data in handbooks
- Deferred: `/init` graceful fallback when `gh api` unavailable (backlog Medium)

**Docs viewer improvements**

- New PostToolUse hook `specs-sidebar-sync.sh` — auto-regenerates sidebar when specs files are written/edited
- Hot reload for docs-viewer — 1s polling on `_sidebar.md` Last-Modified, pauses when tab hidden

## [3.11.0] - 2026-04-16

### MCP Transport Migration + Codex Compatibility

Migrates baseline MCP servers (Atlassian, Slack) from legacy stdio (`npx @anthropic-ai/claude-code-mcp-*`) to streamable HTTP connectors, and adds Codex mirror instructions.

**sync-codex-mcp.sh**

- Baseline servers now use `add_streamable_server` with official connector URLs
- Added transport type/URL detection — automatically replaces servers with wrong transport
- `existing_transport_type()` / `existing_streamable_url()` helpers for introspection
- Google Calendar example URL updated to `gcal.mcp.claude.com`

**Documentation**

- README + README.zh-TW: MCP setup rewritten with Claude Code `/mcp` connector flow + Codex mirror commands
- Legacy stdio npx setup marked as deprecated

## [3.10.0] - 2026-04-16

### DP-005: Engineering Test Command + Handbook Injection

Closes two quality gaps discovered in EPIC-521/TASK-3788: (1) engineering sub-agents used generic `npx vitest run` instead of project-specific test commands, (2) sub-agent dispatch prompts omitted handbook injection, causing coding conventions to be ignored.

**Test Command pipeline (new)**

- `pipeline-handoff.md` — task.md schema gains `## Test Command` section (between 測試計畫 and Verify Command)
- `breakdown/SKILL.md` — Step 14.5 fills Test Command from `workspace-config.yaml` → `projects[].dev_environment.test_command`
- `workspace-config-reader.md` — documents new `test_command` config field
- `validate-task-md.sh` — enforces `## Test Command` as required section
- `engineering/SKILL.md` — sub-agent must use task.md's Test Command; environment failure = hard stop

**Handbook injection (fix)**

- `engineering/SKILL.md` — removed "handbook 自動載入" lie; added explicit handbook injection block for batch + first-cut modes
- `breakdown/SKILL.md` — corrected "handbook 自動載入" to accurate wording
- `design-plan/SKILL.md` — Phase 4b sub-agent prompt adds handbook reading instruction; Phase 5 adds sidebar regeneration step
- `converge/SKILL.md` — Phase 3 execution sub-agents gain handbook pre-read for code-modifying skills

**Mechanism canaries (new)**

- `mechanism-registry.md` — `handbook-injection-in-subagent` (High), `test-command-in-task-md` (High), `test-env-hard-gate` (Critical)

## [3.9.1] - 2026-04-16

### Specs Viewer: Home link

- `generate-specs-sidebar.sh` — add Home link at top of sidebar for navigation back to landing page

## [3.9.0] - 2026-04-16

### Polaris Specs Viewer

Docsify-based browser for design plans, Epic refinements, and task work orders. One command (`scripts/polaris-viewer.sh`) generates a navigation sidebar and opens a local web viewer.

- `scripts/generate-specs-sidebar.sh` — scans `specs/design-plans/` and `{company}/specs/` to build sidebar with status badges (💬/🔒/✅/❌), deduplicates title prefixes, skips empty epics
- `scripts/polaris-viewer.sh` — launcher: generate sidebar → start HTTP server → open browser
- `docs-viewer/` — docsify SPA with home page; `_sidebar.md` is generated (gitignored)
- `.gitignore` — whitelist `docs-viewer/`, exclude generated sidebar

## [3.8.1] - 2026-04-16

### Design plan checklist completeness gate

design-plan Phase 5 now runs `grep -c '- [ ]'` before allowing status → IMPLEMENTED. If any unchecked items remain, the transition is blocked until each is confirmed done or dropped. Fixes the "last item forgot to tick" pattern discovered in DP-003 (commit/sync completed but checklist not updated because attention had moved to session memory).

- `skills/design-plan/SKILL.md` — Phase 5 gains a deterministic grep gate as Step 1, before status change

## [3.8.0] - 2026-04-16

### Epic-centric specs folder (unified artifact structure)

All Epic artifacts now live under `specs/{EPIC}/` — mockoon fixtures, VR baselines, verification evidence, lighthouse reports, refinement artifacts, and task work orders. Previously, mockoon fixtures lived in `ai-config/{company}/mockoon-environments/{epic}/` separate from refinement data. This migration unifies everything so an Epic folder is self-contained: one folder to share, archive, or delete at Epic completion.

**Design decisions (DP-003):**

- D1: proxy-config.yaml stays at company level (`{company_base_dir}/mockoon-config/`) — cross-epic shared config
- D2: VR baselines become permanent per-epic (`specs/{EPIC}/tests/vr/baseline/`) — specs folder is gitignored, no size concern
- D3: verify-AC evidence gets local copy (`specs/{EPIC}/verification/{TICKET}/{timestamp}/`) before JIRA upload

**Changes:**

- `skills/references/epic-folder-structure.md` — **new** reference defining the complete folder schema, path resolution, artifact lifecycle, and bootstrap rules
- `skills/references/INDEX.md` — new § Epic Folder Structure section
- `skills/references/visual-regression-config.md` — directory structure split into tooling (domain-level) and data (per-epic); fixtures schema updated (`runner` + `shared_config_dir` replace `environments_dir` + `active_epic` + hardcoded `start_command`)
- `skills/references/api-contract-guard.md` — contract-check invocation updated to new path
- `skills/references/epic-verification-workflow.md` — fixture folder paths + cleanup flow updated
- `skills/visual-regression/SKILL.md` — fixture lifecycle section rewritten for `specs/{EPIC}/tests/mockoon/`; bootstrap, runner integration, and Phase 3 commit flow updated
- `skills/verify-AC/SKILL.md` — Step 5 split into 5a (local evidence copy) + 5b (JIRA upload)
- `skills/engineering/SKILL.md` — Phase 1.5 contract-check path updated
- `skills/breakdown/SKILL.md` — references-to-load table gains `epic-folder-structure.md`
- `exampleco/workspace-config.yaml` — fixtures block: removed `environments_dir`, `active_epic`, hardcoded `start_command`; added `runner`, `shared_config_dir`
- `_template/workspace-config.yaml` — new `visual_regression` section with updated schema example
- `exampleco/ai-config/exampleco/visual-regression/record-fixtures.sh` — MOCKOON_DIR parameterized (env var or argument), no longer hardcoded
- `rules/mechanism-registry.md` — new canary `epic-folder-structure-compliance` (Medium)
- `polaris-backlog.md` — closed "Epic-centric specs folder" item

**Data migration (exampleco):**

- `exampleco/ai-config/exampleco/mockoon-environments/EPIC-478/` → `exampleco/specs/EPIC-478/tests/mockoon/`
- `exampleco/ai-config/exampleco/mockoon-environments/EPIC-483/` → `exampleco/specs/EPIC-483/tests/mockoon/`
- `exampleco/ai-config/exampleco/mockoon-environments/proxy-config.yaml` → `exampleco/mockoon-config/proxy-config.yaml`
- `exampleco/ai-config/exampleco/mockoon-environments/demo.json` → `exampleco/mockoon-config/demo.json`

## [3.7.0] - 2026-04-16

### Infra-first decision framework (AC-verification-driven)

When breakdown decomposes an Epic, deciding whether to insert 1–2 "infra prerequisite" subtasks (Mockoon fixtures, VR baseline, stable data seed) before feature subtasks was previously done by Strategist improvisation — with two failure modes. (1) Over-engineering: simple Epics got infra prereq inserted because `visual_regression` config existed, even when AC were all `unit_test`. (2) Under-engineering: complex Epics shipped without fixtures and verify-AC hit backend API drift. Pattern had been applied intuitively across EPIC-483 / EPIC-478 / EPIC-521; this version lifts it into an explicit, shared reference.

The decision tree is fully AC-driven. Q1: does any AC use `lighthouse` / `playwright` / `curl`? Q2: any `modules[].api_change`? + exception list (i18n / docs / static-config / research / Epic-is-infra / existing-infra-covers). Output is a structured `decision_trace[]` auditable by the new mechanism-registry canary.

- `skills/references/infra-first-decision.md` — **new** shared reference (Why / Inputs / Classification / Decision tree / Exceptions / Output / Graceful degrade / Tier Guidance / Canary / Edge cases). Mirrors `planning-worktree-isolation.md` structure.
- `skills/references/refinement-artifact.md` (schema `version: 1.0 → 1.1`):
  - `modules[]` gains optional `api_change: "none" | "additive" | "breaking"` (defaults to `"none"` when absent; backward-compat safe)
  - New downstream rows: breakdown Step 5.5 + refinement Step 5 preview consumers
  - New § `modules[].api_change` documenting the signal
- `skills/references/INDEX.md` — new row for `infra-first-decision.md` under § Estimation & Planning
- `skills/references/pipeline-handoff.md` — breakdown → engineering Pre-conditions now reference infra-first-decision.md with graceful-degrade note
- `skills/breakdown/SKILL.md` (v2.5.0 → v2.6.0):
  - **New Step 5.5 Infra-first 決策** (Planning Path only) — reads refinement.json, outputs infra_subtasks + ordering_rule + decision_trace
  - Step 6 old "API-first 排序規則 + 穩定測資單 (Fixture Recording Task)" (bound to `visual_regression` config) replaced with "消費 Step 5.5 輸出" section; old logic becomes documented fallback path
- `skills/refinement/SKILL.md` (v4.1.1 → v4.2.0):
  - Step 5 § 子單結構 template now includes an infra-first summary line generated from the same decision tree (identical source, rendered during refinement preview)
  - Step 5b prose updated to explain preview/breakdown consistency contract
- `rules/mechanism-registry.md`:
  - New canary **`breakdown-infra-first-applied`** (Medium drift) — detects Planning Path breakdown missing infra-first decision trace, or ordering violating decision tree, or refinement preview missing the summary line
- `polaris-backlog.md`:
  - Closed: **breakdown：infra-first 決策框架（AC-verification-driven）**

## [3.6.0] - 2026-04-16

### Breakdown Step 14 — no main-checkout mutation during branch creation

Step 14 previously ran `git checkout develop` + `git pull` + `git checkout -b feat/...` directly on the user's main checkout. If the user had WIP, checkout would fail or corrupt staging. Discovered as a scoped-out note during v3.4.0 worktree isolation work.

The solution turned out to be simpler than the worktree approach proposed in the backlog: **don't switch checkout at all.** `git branch <name> <start>` (without `-b`) creates the ref without touching the working tree. Then `git push -u origin <name>` uploads it. Main checkout's HEAD / branch / working tree never change.

- `skills/breakdown/SKILL.md` (v2.4.0 → v2.5.0):
  - Step 14 absolute rule: forbid `git checkout` / `git pull` / `git stash` on main checkout
  - 14b: replaced `checkout develop + pull + checkout -b + push` with `fetch origin develop + git branch feat/... origin/develop + push`
  - 14c: same pattern for task branches (`git branch task/X feat/Y`)
  - Added "為什麼不用 `checkout -b`？" + canary signal (git status on main checkout must not change during Step 14)
  - Updated the Worktree Isolation section's footnote (previously said branch creation would touch main checkout)
- `rules/mechanism-registry.md`:
  - New canary **`breakdown-step14-no-checkout`** (High drift) — detects `git checkout` / `git pull` on main checkout path during breakdown Step 14, or changes to main checkout HEAD/branch/working tree after Step 14
- `polaris-backlog.md`:
  - Closed: **breakdown Step 14 main-checkout mutation**

## [3.5.0] - 2026-04-16

### Breakdown Step 3a — AC drift detection vs refinement artifact

When refinement v2+ reshapes AC structure (e.g., `AC#1/2/3-5` → `AC1-14`), any existing subtasks still referencing the old AC numbers silently go stale. Downstream consumers (engineering, verify-AC) then read the wrong AC IDs. EPIC-478 breakdown caught this only because the Strategist manually cross-referenced `refinement.json` with each subtask description. Automating this in Step 3 closes the gap.

- `skills/breakdown/SKILL.md` (v2.3.0 → v2.4.0):
  - Step 3: added detection item 4 — AC 引用對齊（當 `refinement.json` 存在且有既有子單時）
  - New § **3a AC 引用漂移偵測與調和** — trigger conditions, detection flow (regex extract + normalize + compare), 4-option reconcile decision (SUPERSEDE / UPDATE / RECREATE / KEEP), user-facing presentation format, sub-agent dispatch boundary (static comparison stays in main session, batch editJiraIssue uses haiku sub-agent)
  - `jira-subtask-creation.md § Retiring Obsolete Subtasks` (already exists) is the SUPERSEDE implementation reference
- `skills/references/refinement-artifact.md`:
  - New row in downstream table: `breakdown (Step 3a — AC drift)` consumes `acceptance_criteria[].id`
  - New § **AC ID 格式約定** documenting the stable anchor contract: `AC1/AC2/...`, `AC-NEG1/...`, `AC2.1/...`; subtask descriptions must use `ACn` or `AC#n` (normalized for drift comparison); warning that refinement v2+ AC restructuring must co-process existing subtasks
- `polaris-backlog.md`:
  - Closed: **breakdown Step 3 偵測既有子單 AC 編號漂移**

### Backlog hygiene — split conjoined items, add Step 14 mutation guard

- `polaris-backlog.md`:
  - Split one malformed `- [ ]` entry that had two `**Why:**` blocks into separate items: **infra-first decision framework** and **Epic-centric specs folder structure**
  - Added **Breakdown Step 14 main-checkout mutation** entry (scoped-out note from v3.4.0 worktree isolation session): Step 14 feature/task branch creation directly mutates main checkout (`git checkout develop` + `git pull`), which conflicts with user WIP. Three solution options documented (pre-check clean state / worktree-add-B pattern / move branch creation to engineering)

## [3.4.0] - 2026-04-16

### Planning skill worktree isolation — generalized to all four planning skills

Refinement v4.1.0 introduced Worktree Isolation for Tier 2+ runtime verification (avoiding main-checkout mutation during `pnpm install` / build / dev server operations). The same drift risk applies to `breakdown` (runtime sanity-check during estimation), `bug-triage` (AC-FAIL Path investigates a feature branch; bug reproduction requires a running env), and `sasd-review` (technical feasibility probes). Generalizing this prevents planning skills from silently corrupting user WIP.

- `skills/references/planning-worktree-isolation.md` (**new**):
  - Shared reference consolidating the worktree isolation protocol — why, absolute rules, execution flow, canary signal, sub-agent dispatch, exceptions
  - Tier Guidance table per skill: when the worktree requirement activates
- `skills/refinement/SKILL.md` (v4.1.0 → v4.1.1):
  - Replaced ~70 lines of inline Worktree Isolation content with a 10-line skill-specific header + link to the shared reference
- `skills/breakdown/SKILL.md` (v2.2.0 → v2.3.0):
  - New § **Worktree Isolation (條件性)** — triggers for estimation sanity-check, infra-first decision verification, Scope Challenge runtime checks
  - Note clarifying Step 14 feature-branch creation is a separate concern (skill's intended output, not runtime verification)
- `skills/bug-triage/SKILL.md` (v2.1.0 → v2.2.0):
  - New § **Worktree Isolation (條件性)** — mandatory for AC-FAIL Path (feature-branch investigation), manual bug reproduction, cross-branch behavior comparison
  - AC-FAIL Path sub-agents must use `isolation: "worktree"` to prevent feature-branch state from leaking into main checkout
- `skills/sasd-review/SKILL.md` (v1.0.0 → v1.1.0):
  - New § **Pre-step (conditional): Worktree Isolation** — triggers for feasibility verification (runtime API/module behavior), dev scope quantification via build, A/B alternative comparison
- `skills/references/INDEX.md`:
  - New entry under **Estimation & Planning** pointing to `planning-worktree-isolation.md`
- `rules/mechanism-registry.md`:
  - New canary **`planning-skill-worktree-isolation`** (High drift) under § Delegation — detects `pnpm install` / build / dev server in main checkout path before any `worktree add`
- `polaris-backlog.md`:
  - Closed: **Generalize worktree isolation to breakdown / sasd-review / bug-triage**

## [3.3.0] - 2026-04-16

### Breakdown pipeline — split subtasks + SUPERSEDED pattern

Addresses two gaps surfaced by EPIC-478 breakdown (11 implementation subtasks, 1 of which was split; 3 obsolete verification subtasks needing retirement).

- `scripts/validate-task-md.sh`:
  - Header regex relaxed `^# T[0-9]+:` → `^# T[0-9]+[a-z]*:` to allow split subtask headers (T8a, T8b)
  - Rationale: preserving parent T-number + alpha suffix avoids renumbering siblings and breaking downstream task.md references
- `skills/references/pipeline-handoff.md`:
  - § task.md Schema: added **Header numbering** note documenting sequential + suffix convention and validator regex
- `skills/references/jira-subtask-creation.md`:
  - New § **Retiring Obsolete Subtasks** — `[SUPERSEDED]` summary prefix + SP=0 + comment pattern for workflows without direct Open → Cancel transition
  - Applies to any company workflow lacking Cancelled/Rejected transition from initial state
- `polaris-backlog.md`:
  - Added **Breakdown: AC drift detection vs refinement artifact** (High) — Step 3 should flag mismatched AC numbering between existing subtasks and refinement.json

## [3.2.0] - 2026-04-16

### Library change protocol — reviewer-suggested upgrade pause

Addresses drift in `engineering` revision mode where sub-agents default to closing PRs by silently deferring reviewer-suggested library upgrades ("defer to next sprint", "current version doesn't support this"). Reviewer upgrade suggestions are often load-bearing signals — silently dismissing them loses legitimate improvement paths and burns reviewer trust.

- `rules/library-change-protocol.md`:
  - New § **Reviewer-Suggested Upgrades in Revision Mode** — pause and escalate to user before deciding
  - Forbidden defaults: unilateral deferral, "T3 so deferred" auto-response, "reply-only no code change"
  - Correct flow: sub-agent stops → main agent asks user → user decides Y (upgrade protocol) or N (reply with reason)
  - Scope: any library/framework/module upgrade suggestion in PR review, not just Nuxt modules
  - New Common Rationalization row added
- `rules/mechanism-registry.md`:
  - New canary **`lib-reviewer-upgrade-pause`** (High drift) — detects "deferred to next sprint" replies without user consultation

## [3.1.0] - 2026-04-16

### Refinement skill — Worktree Isolation

- `refinement` skill bumped `4.0.0 → 4.1.0`:
  - Added **§ Worktree Isolation** section with absolute-rule framing and canary signal
  - Tier 2+ refinement must create `refinement/{EPIC_KEY}` worktree from `origin/{base_branch}` before any codebase/runtime work
  - **No mutation of user's main checkout**: forbids `git checkout`, `git stash`, `git pull` in main workspace
  - Canary signal: before any git command, self-check "will this change the main checkout's HEAD/branch/working tree?"
  - Prerequisites section updated to call out worktree requirement

### Backlog — Planning pipeline evolution

Three High-priority framework items added to `polaris-backlog.md`:

- **Generalize worktree isolation** to `breakdown` / `sasd-review` / `bug-triage` (same pattern, Tier 2+ runtime work)
- **`specs/{EPIC}/` as Epic single source of truth** — consolidate refinement artifacts, task.md, Lighthouse reports, Mockoon fixtures, verification evidence into one folder. Affects mockoon workspace-config path, breakdown task.md location, verify-AC evidence placement
- **`breakdown` infra-first decision framework** — AC-verification-driven decision tree: if hardest AC requires runtime state (Mockoon fixtures / VR baseline / specific data) → infra subtask first; else feature-first. API changes: breaking → API-first-then-fixtures; additive → parallel

### Framework experience

- Real-session drift discovered and corrected: first draft of Worktree Isolation only said "build worktree" without forbidding main-checkout mutation — Strategist still executed stash→checkout→pull sequence before running build. v4.1.0 second pass adds absolute rules + canary signal to prevent misinterpretation

## [3.0.4] - 2026-04-15

### Docs alignment after Codex parity rollout

- Updated skill count references from **25 → 26** in:
  - `README.md`
  - `README.zh-TW.md`
  - `docs/quick-start-zh.md`
- Added `codex-mcp-setup` to `docs/chinese-triggers.md` so trigger catalog matches the actual skill inventory.
- Re-ran docs lint and confirmed no drift:
  - `Docs lint: OK (26 skills, all documented)`

## [3.0.3] - 2026-04-15

### Codex bootstrap + cross-LLM parity hardening

- Added `scripts/sync-codex-mcp.sh`:
  - Syncs baseline Codex MCP servers (`claude_ai_Atlassian`, `claude_ai_Slack`)
  - Supports `--dry-run` / `--apply` and optional `--login`
  - Skips OAuth login automatically for `stdio` transport servers
- Added `codex-mcp-setup` skill (Claude + Codex mirrored layouts):
  - Standardized Codex setup flow (MCP sync + skills link + parity + doctor)
- Added `scripts/transpile-rules-to-codex.sh`:
  - Source of truth: `.claude/rules/**/*.md`
  - Generates `.codex/AGENTS.md` + `.codex/.generated/rules-manifest.txt`
  - Supports `--check` drift validation for CI
- Added `scripts/verify-cross-llm-parity.sh`:
  - Runs `mechanism-parity.sh --strict` + `transpile-rules-to-codex.sh --check`
  - Provides a single CI-friendly cross-LLM parity gate

### Init / upgrade workflow integration

- `init` skill now includes **Step 13.6 Codex Bootstrap** (skippable):
  - Runs skills sync, Codex MCP sync, rules transpile, cross-LLM parity verification, and Codex doctor
  - Keeps init non-blocking on Codex bootstrap failures (warn + continue)
- `init` Step 14 "Done" summary now reports Codex bootstrap status:
  - `✓ enabled` / `— skipped` / `⚠ partial`
- `scripts/sync-from-polaris.sh` upgrade flow now runs post-upgrade:
  - `scripts/transpile-rules-to-codex.sh`
  - `scripts/verify-cross-llm-parity.sh`

### Docs

- Updated Codex quick-start (EN + zh-TW):
  - Documented MCP baseline sync, rules transpile, and cross-LLM parity check
  - Declared `.claude/**` as SSOT and `.agents/**`, `.codex/**` as generated outputs
- Updated README upgrade section (EN + zh-TW) to reflect post-upgrade Codex parity checks

## [3.0.2] - 2026-04-15

### Codex compatibility — skills path sync bridge

- Added `scripts/sync-skills-cross-runtime.sh` to sync skills between:
  - `.claude/skills` (Claude layout)
  - `.agents/skills` (Codex layout)
- Supports:
  - `--to-agents` / `--to-claude` / `--both`
  - `--link` mode (`.agents/skills -> .claude/skills` symlink)
- Added `.agents/skills` whitelist in `.gitignore` so repo-scoped Codex skills can be version-controlled.
- Updated Codex quick-start docs with explicit skill sync step:
  - `docs/codex-quick-start.md`
  - `docs/codex-quick-start.zh-TW.md`

### Maintainer-only skill boundary hardening

- `scripts/sync-to-skills.sh` now skips skills marked with `scope: maintainer-only` in SKILL frontmatter.
- This aligns vendoring behavior with `sync-to-polaris.sh` and prevents framework-internal maintenance skills from being exported to external/team skills repos.

## [3.0.1] - 2026-04-15

### `design-plan` skill — 新增 Sub-agent Handoff 模式（v1.1.0）

Phase 4 實作階段新增雙模式選擇：

- **4a. Main-agent 模式**：小 scope（Checklist ≤ 3 項、單檔案）走 Strategist 直接執行
- **4b. Sub-agent Handoff 模式**：大 scope 走「dispatch sub-agents 消費 plan.md 作為 work order」的 pattern，類比 `breakdown → task.md → engineering`

**Sub-agent Handoff 要點**：

- Dispatch prompt 只傳 plan file **路徑**（sub-agent 自己讀），不 copy plan 內容
- Phases 依賴關係決定平行 vs 順序；多 sub-agent 寫同檔時用 worktree isolation
- Main agent 只做 orchestration + fan-in validate + 統一 tick off Checklist
- Sub-agent 偏離 plan 必須 STOP + 回報，不擅自決策

**Dogfood 驗證**：DP-002 重構（engineering revision mode + pr-pickup + fix-pr-review 移除）透過此模式執行——5 個 phases 全部 DONE、零 user 修正。

## [3.0.0] - 2026-04-15

### ⚠ Breaking — `fix-pr-review` skill 移除

`fix-pr-review` 整個 skill 已刪除。「修 PR」這件事回歸施工標準：**回讀施工圖（task.md / plan.md）→ 比對 review signals → 重跑完整驗收**，不再是 symptom-driven 的逐 comment patch。

### engineering 擴充為 first-cut + revision 雙模式（v4.0.0 → v5.0.0）

`engineering` 新增 **revision mode**（D1 六步流程），成為所有 PR code 修正的唯一入口：

1. 讀施工圖
2. 比對 review signals vs 原計劃
3. Classify：`code drift` / `plan gap` / `spec issue`
4. 執行修正（依 classification）
5. 重跑 engineer-delivery-flow（quality + behavioral verify + AC check）
6. 回覆 reviewer + lesson 萃取

**嚴格性規則**：

- **Plan gap / spec issue → 硬擋退回上游**（breakdown / refinement），不就地補 plan（避免便宜行事繞過品質關卡）
- **Legacy PR 無施工圖 → 硬擋**（要求先跑 `/breakdown {TICKET}` 補 plan，或用 `--bypass` 旗標並警告）
- **Review comments 不分級**：所有 comment（typo 或邏輯漏洞）一律走完整 revision flow，不做 triage

Mode detection 發生在 engineering Step 0：PR 已開 → revision；否則 → first-cut（原有流程保留不變）。

### 新 skill：`pr-pickup` — Slack 協作層

填補 fix-pr-review 原本的 Slack 協作價值，但**只做溝通傳遞，不做 code 修正**：

- **Intake**：從 Slack 訊息擷取 PR URL + thread context
- **Dispatch**：同步 Skill tool 呼叫 engineering revision mode
- **Broadcast**：完工後回 Slack thread（✅ 完成 / ⛔ 退回 / ⚠️ 失敗）

觸發：`pr-pickup`、`pickup`、Slack URL + PR intent。

### Learning Pipeline — `plan-gap` + `review-lesson` 標籤

新增兩類 lesson 標籤，對應不同 handbook 目標：

- `plan-gap`（engineering R3a plan gap 退回時寫入）→ 畢業成 refinement / breakdown 的 checklist 條目
- `review-lesson`（engineering R6 code drift 修完時寫入）→ 畢業成 repo handbook

**閾值**：N=3（同 feedback memory graduation）。自動掃描整合進 standup（post-step）和 sprint-planning（pre-step）。

**CLI 擴充**：`polaris-learnings.sh` 新增 `--tag` / `--metadata` 旗標 + `graduate <tag>` subcommand。

### Design Plan Skill 檔案位置遷移（DP-001 superseded）

原本 `.claude/design-plans/{topic}.md`（committed）改為 `specs/design-plans/DP-NNN-{slug}/plan.md`（gitignored）：

- Plan 檔是個人工作空間的思考紀錄，畢業成 rule/reference 才進 framework git
- 比照 `{company}/specs/{TICKET}/` 架構，framework 層有對應的 spec folder
- 非 ticket 用 `DP-NNN` 三位數流水號 + kebab-case slug
- 每個 plan 是 folder（容納 draft / diagram 子檔）

### 規則 + 文件更新

- `rules/skill-routing.md`：移除 fix-pr-review，新增 engineering revision mode 路由 + pr-pickup 路由
- `rules/mechanism-registry.md`：Common Rationalizations 更新指向 engineering revision mode
- `rules/*/mechanism-registry.md` canaries：保留 deterministic 機制規則，移除 skill-specific 殘跡
- `references/engineer-delivery-flow.md` Step 7：加 revision mode 行為（push to existing PR）
- `references/cross-session-learnings.md`：新增 Pipeline Learning Tags + Graduation Pipeline section
- `references/shared-defaults.md`：pr-pickup 列入 config consumers
- `standup` / `sprint-planning` SKILL：加 learning queue 掃描步驟
- 25+ 其他 references / skills 的 fix-pr-review 引用清除（bug-triage / review-pr / converge / next / learning / INDEX 等）
- 雙語 docs 同步：README / workflow-guide / chinese-triggers（EN + zh-TW），mermaid diagram 更新
- `.claude/settings.local.json` 移除 fix-pr-review 相關 permission

### Dogfood

DP-002 全程走 design-plan 流程產出（LOCKED → 5 個 phase 平行 / 順序 dispatch sub-agents 消費 plan.md 作為 work order）。

## [2.17.0] - 2026-04-15

### Design Plan skill — non-ticket architecture discussions

新增 `design-plan` skill，填補 breakdown/refinement/sasd-review 之間的 gap：**非 ticket 設計討論的持久化落地機制**。

- **新 skill**：`.claude/skills/design-plan/SKILL.md`
- **檔案位置**：`.claude/design-plans/{topic}.md`（committed to git，類似 ADR）
- **Status 流轉**：DISCUSSION → LOCKED → IMPLEMENTED / ABANDONED
- **觸發**：使用者說「想討論」「怎麼設計」「重構」「重新設計」「要怎麼改」等，或多輪架構討論自動回溯建檔
- **決策即寫檔**：每個確認的決策，下一個 tool call 必須更新 plan file
- **實作時讀 plan**：implementation 階段必須讀 plan file，不依賴對話記憶
- **Checklist-based done**：Implementation Checklist 全打勾才能宣告完成

**Dogfood**：本 skill 的實作本身經過 design-plan 流程產出，plan file 一起 commit 作為決策紀錄（`.claude/design-plans/design-plan-skill.md`）。

### 規則更新

- `rules/skill-routing.md`：新增 design-plan routing 條目
- `rules/context-monitoring.md § 5b Defer = Immediate Capture`：加「design decision → plan file」case + check-pr-approvals v2.10→v2.16 掉棒事件說明
- `rules/feedback-and-memory.md § Memory Hygiene Checks`：新增第 9 項 stale design-plan 掃描（DISCUSSION > 30 天 / LOCKED > 14 天未實作）
- `rules/mechanism-registry.md § Strategist Behavior`：新增 4 個 canaries（`design-plan-creation` / `design-plan-decision-capture` / `design-plan-reference-at-impl` Critical；`design-plan-checklist-done` High）+ Common Rationalizations + Priority Audit Order 1a

### 為什麼這個 skill 存在

check-pr-approvals v2.10.0 重設計時，早期決策「check-pr-approvals 發現問題 PR 轉 JIRA 狀態」在後續討論中被「engineering 零改動」覆蓋，實作時掉棒，v2.16.0 才補回。這次事件暴露了「非 ticket 設計討論」缺乏 landing point，設計決策只存在對話記憶中，容易被後續 phrasing 覆蓋。design-plan 把決策從記憶轉成檔案，讓實作有確定性的 spec 可讀。

## [2.16.0] - 2026-04-15

### check-pr-approvals: JIRA status revert for 🔧 PRs

補上 v2.10.0 遺漏的 JIRA 狀態回轉邏輯。

- **Step 5 新增**：對 🔧 分類 PR，若 JIRA 狀態為 `CODE REVIEW`，轉回 `IN DEVELOPMENT` 並留 comment 記錄原因
- **理由**：engineering 的路由表中 `CODE REVIEW` 狀態會導向「修 review comments 嗎？」引導至 fix-pr-review。為了讓「做 KB2CW-XXXX」直接命中 engineering 的「IN DEV + 有 branch」路徑，check-pr-approvals 必須主動回轉狀態
- **Step 9 回報**：列出哪些 ticket 已回轉狀態
- **Do**：新增規則「🔧 PR 若 JIRA 狀態為 CODE REVIEW，必須轉回 IN DEVELOPMENT」

## [2.15.0] - 2026-04-15

### 清除 v2.12.0 文件殘留 + maintainer-only 感知 lint

v2.13 的 docs-sync 只修了 phantom 引用和 skill count，但遺漏了其他殘留：

- **Skill Orchestration 圖修復**：移除 `DS` (docs-sync) 節點、移除 self-loop edges（`RP/FPR/CPA → self`）、移除 `DS` class 分類。連通性說明改為「lesson extraction 直接寫 handbook，不需中繼節點」
- **chinese-triggers.md**：移除 docs-sync 行；`learning` 描述的 review-lessons 改為 handbook
- **workflow-guide Learning Modes 表**：「write to review-lessons」改為「write to repo handbook」
- **readme-lint.py**：動態讀取 SKILL.md 的 `scope: maintainer-only`，自動從 doc-mention 檢查排除。與 sync-to-polaris.sh 同一機制
- **Skill count**：25 → 24（扣除 maintainer-only 的 docs-sync）

## [2.14.0] - 2026-04-15

### sync-to-polaris: maintainer-only skill exclusion

- **`scope: maintainer-only`**：SKILL.md frontmatter 新增此欄位的 skill 不會 sync 到 template repo
- **`docs-sync` 從 template 移除**：framework 文件維護是個人行為，不應暴露給所有使用者
- **通用機制**：任何 skill 加 `scope: maintainer-only` 即自動排除，不需改 sync 腳本

## [2.13.0] - 2026-04-15

### docs-sync fix + version-docs-lint-gate hook

v2.12.0 刪除 `review-lessons-graduation` 後漏跑 post-version-bump chain，導致 14 處文件殘留引用。

- **文件修復**：skill count 26→25（9 處）、phantom skill 引用（6 處）、mermaid 圖節點+邊
- **確定性拘束**：新增 `version-docs-lint-gate.sh` — VERSION staged 時自動跑 `readme-lint.py`，lint fail 則 block commit
- **Local-only 設計**：hook 註冊在 `settings.local.json`（gitignored），腳本在 repo 但不自動生效，避免暴露個人行為到 template
- **Handbook 條目**：`working-habits.md` § 框架維護，記錄 bump 後必跑 docs-sync 的個人習慣
- **Mechanism registry**：新增 `version-docs-lint-gate` + 更新 `docs-sync-on-version-bump` 加註確定性備援

## [2.11.0] - 2026-04-15

### standup local markdown backup

Standup 確認後自動存本地 markdown 檔案，作為 Confluence 推送前的備份。

- **路徑結構**：`{base_dir}/standups/{YYYY}/{MM}/{YYYYMMDD}.md`（年/月兩層，檔名帶完整日期）
- **執行順序**：Step 10a 存本地 → Step 10b 推 Confluence（local first, 離線也有紀錄）
- **自動建目錄**：`mkdir -p` 建立不存在的年/月目錄
- **覆寫設計**：同日重跑直接覆寫

## [2.10.0] - 2026-04-15

### check-pr-approvals v2.0.0 — detect + report only

check-pr-approvals 從「偵測 + 自動修正 + 催 review」瘦身為「偵測 + 報告 + 催 review」。

- **移除所有自動修正邏輯**：CI 修正、rebase conflict 解衝突、review comment 修正（原委派 fix-pr-review）全部移除
- **三分類報告**：🟢 可催 review / 🔧 需先修正（附 ticket key）/ ✅ 已達標
- **修正走 engineering**：問題 PR 由使用者主動「做 KB2CW-XXXX」觸發 engineering 完整流程（TDD + behavioral verify），確保功能不被改壞
- **冪等設計**：每次執行重新掃描當前狀態，不等修正完成、不輪詢遠端 CI
- **移除 review lessons 萃取**：lesson 萃取應在 engineering 修正時自然產生，不在掃描時回溯
- **Backlog**：review-lessons buffer 廢除排入 Medium backlog

淨減 124 行（78 insertions, 202 deletions）。四個 bundled scripts 不動，engineering 不動。

## [2.9.0] - 2026-04-14

### docs-sync restructure — deterministic lint + git-diff scoping

文件同步從「全量掃描 + 手動修」重構為「確定性偵測 + 差異驅動修復」。

- **`readme-lint.py` 擴充為 docs-lint** — 新增 5 項確定性檢查：
  - Phantom skill 偵測（doc 引用不存在的 SKILL.md）
  - chinese-triggers 表格 ↔ catalog 比對
  - Mermaid diagram node ↔ catalog 比對
  - `KNOWN_NON_SKILLS` 白名單降低 false positive
  - 原有 skill count + undocumented skill 檢查保留
- **`docs-sync` SKILL.md v3.0.0** — 新增 Step 0（git diff + completeness scoring）：
  - Step 0a: 跑 `readme-lint.py` 確定性檢查
  - Step 0b: `git diff` 找出上次同步後變更的 SKILL.md
  - Step 0c: 借 `/learning` baseline→classify 模式分類變更深度
  - Step 0d: 借 `/refinement` N/M 維度對每個 skill 打 4 維覆蓋分數
  - 無變更 + lint 通過 → 直接跳到驗證，不跑全量掃描
- **Post-version-bump chain 調整** — docs-lint 先跑（確定性），有問題才觸發 docs-sync（AI）
- **文件全面更新** — 修正 7 個 doc 檔案：
  - `work-on` → `engineering`（全部文件）
  - 移除 phantom skills（`jira-worklog` 公司層、`skill-creator` Claude 官方）
  - 新增 `check-pr-approvals`、`my-triage`、`next`、`sasd-review` 到各 doc

## [2.8.0] - 2026-04-14

### Pipeline Persona — Architect / Packer / Engineer

三層 pipeline 的角色收斂，每個 skill 有明確的身份宣言和「不做」邊界。

- **refinement** — Architect persona：把模糊需求變成可執行藍圖，不拆單、不估點
- **breakdown** — Packer persona：接過藍圖拆工單、估價、排班，不做技術探索
  - Step 4 新增 `refinement.json` early-exit：有 artifact 時跳過 Explore sub-agent，直接消費
- **engineering** — Engineer persona（v2.6.0 已有）
- `pipeline-handoff.md` Role Boundaries 表加 persona 標籤

## [2.7.0] - 2026-04-14

### Context Pressure Monitor — deterministic session degradation prevention

長 session 中 Strategist 靠自律計算 tool calls 不可靠（v1.71.0 事件），改用 PostToolUse hook 確定性注入警告。

- **`scripts/context-pressure-monitor.sh`** — 計數 Bash/Edit/Write/Read/Grep/Glob/Agent calls，三級警告：
  - 20 calls → advisory（wrap up current phase）
  - 25 calls → urgent（save state, delegate）
  - 35 calls → critical（checkpoint mode NOW）
- 註冊進 `~/.claude/settings.json` PostToolUse hooks
- `mechanism-registry.md` 新增 `context-pressure-monitor` entry
- `context-monitoring.md` §5 從 "Future enhancement" 升級為 "Deterministic mechanism"

**設計原則**：與 `test-sequence-tracker.sh` 同模式 — stdout injection（advisory），不 block。

## [2.6.0] - 2026-04-14

### Engineering Mindset — Deterministic Quality Gates & Skill Rename

`work-on` 更名為 `engineering`，搭配三層確定性強化，確保 AI 工程師不再跳過品質檢查。

#### 確定性品質 Gate（P0）

- **`scripts/pre-commit-quality.sh`** — 自動偵測 lint/typecheck/test 並執行，全過寫 quality evidence
- **`scripts/quality-gate.sh`** — PreToolUse hook，`git commit` 前檢查 evidence，沒有就 exit 2 擋下
- Coverage advisory — 列出缺少 test 的 source files（non-blocking）
- 整合進 `quality-check-flow.md` Step 4b + `mechanism-registry.md`

#### Scope Lock（P1）

- `pipeline-handoff.md` task.md schema 新增 `## Allowed Files` section
- `engineer-delivery-flow.md` 新增 Step 5.5 Scope Check（advisory + risk signal）
- `sub-agent-delegation.md` self-regulation scoring：計畫外檔案 +10% → +15%

#### Skill Rename: work-on → engineering

- 目錄 `skills/work-on/` → `skills/engineering/`
- SKILL.md 開頭加工程師 persona 宣言
- 全框架 ~30 個檔案 cross-reference 更新
- Routing table 保留 `做`/`work on` trigger，skill name 改為 `engineering`

**設計原則**：能用確定性驗證的，不靠 AI 自律。Hook exit code > 行為規則。

## [2.5.0] - 2026-04-14

### Library Change Protocol — Investigation & Workaround Standards

從 EPIC-521 TASK-3789（nuxt-schema-org tagPosition）的 debug session 萃取兩條準則，加入 `library-change-protocol.md`：

- **Config Not Working — Systematic Elimination**：config 不生效時，先列出所有注入點再依序排除；驗證結果矛盾以失敗為準
- **Workaround Documentation Standard**：繞過官方 API 時，code comment 必須包含完整決策鏈（目標 → 試了什麼 → 為什麼選此方案 → 移除條件）

**觸發背景**：T2 修復過程在 5 個注入點之間來回測試，浪費 4 次 dev server 重啟。

## [2.4.0] - 2026-04-14

### review-inbox Thread Mode

review-inbox 新增第三種 PR 發現模式：給一個 Slack 討論串 URL，從該 thread 提取 PR URL 並走標準 review pipeline。填補 channel 全掃（太廣）和單一 PR review（太窄）之間的缺口。

- **extract-pr-urls.py** — 新增 `--thread-ts` flag，Thread 模式跳過 per-message 解析，直接撈全文 PR URL
- **SKILL.md** — Step 0 Thread 偵測、Step 1 Thread pipeline（主 session 直接跑，不需 sub-agent）、Step 5 Thread reply
- **skill-routing.md** — routing table 新增 Slack thread URL + review intent 觸發

**使用方式**：`review <slack_thread_url>`

## [2.3.0] - 2026-04-14

### Verify Command — Developer Self-Test Gate

breakdown（Tech Lead）為每張 task.md 寫一個可執行的 smoke test 指令，work-on（Engineer）實作完後必須原封不動執行。FAIL 直接擋 PR，消除「sub-agent 聲稱 pass 但沒真跑」的結構性弱點。

- **pipeline-handoff.md** — task.md schema 新增 `## Verify Command` section
- **breakdown SKILL.md** — Step 14.5 新增 Verify Command 撰寫指南（範例、原則、N/A 情境）
- **engineer-delivery-flow.md** — Step 3d 改為 Verify Command hard gate；舊 `## 行為驗證` 降級為 legacy fallback
- **mechanism-registry.md** — 新增 `verify-command-immutable-execute` (Critical)

**角色分工**：
| 角色 | Skill | 驗證職責 |
|------|-------|---------|
| Tech Lead | breakdown | 寫 verify command（what to check） |
| Engineer | work-on | 執行 verify command（self-test） |
| QA | verify-AC | 跑完整 AC 驗收（business-level） |

**觸發背景**：EPIC-521 PR #2126 JSON-LD head position 實作未生效，sub-agent 未跑 runtime 驗證即開 PR。

## [2.2.0] - 2026-04-14

### Review Skill Architecture — Discovery / Engine Split

review-inbox 升級為三層 sub-agent 架構（Slack scan → per-PR review → 彙整），review-pr 砍掉批次模式純化為 single-PR review engine。

- **review-inbox v2.1.0** — Slack 模式 Step 1 委派 sub-agent（MCP + extract-pr-urls.py pipeline），原始訊息不進主 session context；Step 4 每個 PR 由獨立平行 sub-agent 執行 review-pr 流程
- **review-pr v2.0.0** — 移除 Step 0 批次模式（multi-PR dispatch、batch Slack notification），批次調度由 review-inbox 負責
- **extract-pr-urls.py** — 支援新 MCP 輸出格式（`=== Message from ...` headers + `Message TS`），保留 legacy fallback；thread_ts 從秒級近似提升為微秒精度

**職責分工**：
| 職責 | 負責者 |
|------|--------|
| PR 發現（Slack / Label 掃描） | review-inbox |
| 批次調度（平行 sub-agent） | review-inbox Step 4 |
| 單 PR review（diff → 審查 → 提交） | review-pr |
| 批次 Slack 通知 | review-inbox Step 5 |
| 單 PR Slack 通知 | review-pr Step 7 |

## [2.1.0] - 2026-04-14

### Phase 4 — Delivery Flow Polish

v2.0.0 follow-up：補齊 contract、VR 整合、pr-convention 降級、delivery canaries。

- **Delivery Contract** — `engineer-delivery-flow.md` 頂部加 Preconditions / Postconditions / 不做的事
- **VR Step 3.5** — Behavioral Verify 後、Pre-PR Review 前條件觸發 `visual-regression`（Local mode），結果寫入 evidence file
- **Deleted skill: `pr-convention`** — PR template 偵測、body 組裝、AC Coverage、母單 PR、Bug RCA 偵測邏輯移到新 reference `pr-body-builder.md`，消除獨立 skill 的路由歧義
- **New reference: `pr-body-builder.md`** — engineer-delivery-flow Step 7 消費
- **Delivery Contract canaries** — mechanism-registry 新增 5 條 delivery-flow 專屬 canary（step-order、single-backbone、vr-trigger、pr-body、evidence-completeness）
- **Sweep** — 更新 INDEX.md、git-pr-workflow、bug-rca、mechanism-registry 中所有 pr-convention 引用

## [2.0.0] - 2026-04-14

### BREAKING — Engineer Delivery Flow Redesign

execution backbone 從分散的 skill 統一到共用 reference，work-on 和 git-pr-workflow 共用同一份交付流程。

- **New references**
  - `engineer-delivery-flow.md` — 共用交付 backbone：Simplify → Quality Check → Behavioral Verify (Layer A+B) → Pre-PR Review → Rebase → Commit → PR → JIRA transition
  - `quality-check-flow.md` — lint / test / coverage / risk scoring 自檢流程（原 dev-quality-check 內容）
- **Restructured skills**
  - `work-on` v4.0.0 — Developer 主入口，TDD 開發後委託 engineer-delivery-flow (Role: Developer)。刪除 Phase 2.5 Sanity Gate（吸收進 delivery-flow Step 3）
  - `git-pr-workflow` v4.0.0 — 瘦身為 Admin 入口（~440→~90 行），加 `tier: meta` + `admin_only: true`，委託 engineer-delivery-flow (Role: Admin)
- **Deleted skills**
  - `verify-completion/` — 行為驗證段 → engineer-delivery-flow Step 3；AC 驗證段 → verify-AC（已獨立）
  - `dev-quality-check/` — 內容 → quality-check-flow.md；`detect-project-and-changes.sh` → 搬到 `scripts/`
- **Skill routing**
  - 新增 § Admin-Only Skill Guard：git-pr-workflow 在產品 repo 引導走 work-on
- **Reference sweep** — 16 files 更新 verify-completion / dev-quality-check 引用
- **Evidence gate 合併** — 刪除 `/tmp/.quality-gate-passed-{BRANCH}` + pre-push hook marker，保留 `/tmp/polaris-verified-{TICKET}.json` + pre-PR hook 為唯一 gate

## [1.110.0] - 2026-04-14

- **Handbook as Coding Standard — review skills now read and enforce repo handbook**
  - `review-pr` Step 3: reads `handbook/index.md` + sub-files as primary review standard (full compliance, not checklist)
  - `review-pr` Step 6.5: review findings write directly to handbook (Standard-First), replacing review-lessons buffer
  - `fix-pr-review` Step 5: upfront handbook read for global context before per-comment fixes
  - `fix-pr-review` Step 7b: upgraded to Standard-First Calibration (conflict → pause → ask user → update handbook or reply reviewer)
  - `repo-handbook.md` § 3c: reframed from "review context" to "coding standard" — three roles (work-on, review-pr, fix-pr-review) all comply holistically
  - `INDEX.md`: added `review-pr` to repo-handbook triggers
- **review-lessons buffer deprecated** for repos with handbook — new patterns go directly to handbook via Standard-First flow
  - `review-lessons-graduation` skill retained only for legacy repos without handbook

## [1.109.0] - 2026-04-13

- **jira-worklog moved to company layer** (`skills/exampleco/jira-worklog/`)
  - Decision: worklog compliance is company-driven behavior, not universal developer need
  - Removed from framework `skill-routing.md` — no company-specific info in framework files
- **jira-worklog-batch.py — deterministic script replaces AI orchestration**
  - JIRA fetch, changelog parsing, allocation, delete/write all handled by Python script
  - AI only handles Google Calendar MCP (OAuth) → passes meeting hours JSON to script
  - Token consumption: ~100k → ~3k per monthly run
  - Fixed JIRA API migration: `/rest/api/3/search` → `/rest/api/3/search/jql` (cursor-based pagination)
- **Standup decoupled from worklog** — removed Post-Standup: Daily Worklog section
  - Monthly reminder stays in personal handbook (`working-habits.md`)

## [1.108.0] - 2026-04-13

- **jira-worklog v3.0 — monthly compliance model**
  - Redesign: `8h = meetings + 1h lunch + ticket work`, meeting hours from Google Calendar are core
  - Primary trigger changed from daily standup post-step to monthly batch
  - Phase 2 monthly reconciliation fills gap days, ensures monthly total ≈ expected
  - Monthly reminder added to personal handbook (last 5 workdays of month)
- **Skill catalog consolidation: 44 → 32 (-27%)**
  - Deleted: `end-of-day`, `example`, `start-dev`, `wt-parallel`
  - Merged: `which-company` → `use-company`, `validate-isolation` + `validate-mechanisms` → `validate`, `worklog-report` → `jira-worklog`, `epic-status` → `converge`, `unit-test-review` → `unit-test`, `systematic-debugging` → `bug-triage`
  - Downgraded: `exampleco/docs-sync`, `exampleco/sasd-review` (removed as skills)
  - `docs-sync` marked `scope: maintainer-only`
- **New mechanism: `defer-immediate-capture`**
  - When deferring work ("等 X 再處理 Y"), capture in todo/memory immediately
  - Added to `context-monitoring.md` §5b and `mechanism-registry.md`

## [1.107.0] - 2026-04-13

- **Skill catalog consolidation: 33 → 30 skills (cumulative 44 → 30, -32%)**
  - `scope-challenge` → `breakdown`: Quality Challenge inlined as Step 7.5; standalone Scope Challenge Mode added (SC1-SC5)
  - `tdd` → `unit-test`: TDD Mode §1.5 with Red-Green-Refactor cycle, cycle log, and anti-patterns
  - `jira-branch-checkout` → `references/branch-creation.md` + `scripts/create-branch.sh`: skill wrapper removed, script promoted to shared location
  - Updated 11 referencing files (INDEX, sub-agent-roles, work-on, git-pr-workflow, pr-convention, fix-pr-review, verify-completion, decision-audit-trail, refinement-artifact, confidence-labeling, tdd-smart-judgment)
  - Net -272 lines (19 files changed)

## [1.106.0] - 2026-04-13

- **Breakdown v2.0.0 — Universal Planning Skill (Phase 2 of 3-Layer Redesign)**
  - Rename `epic-breakdown` → `breakdown`: now handles Bug / Story / Task / Epic uniformly
  - New Bug Path (B1-B4): reads `[ROOT_CAUSE]` from bug-triage → estimates → simple (1-2pt) direct handoff or complex (3+pt) subtask split
  - Story/Task absorbed from `jira-estimation` Step 8: codebase exploration → subtask split → estimation → Quality Challenge
  - Epic path preserved within unified Planning Path (Steps 4-16)
  - Delete `jira-estimation` — estimation logic fully internalized into breakdown
  - Updated 22 reference files: routing, registry, skills, references
  - Net -402 lines across 24 files (consolidation)
  - Three-layer architecture now fully implemented: bug-triage/refinement → breakdown → work-on

## [1.105.0] - 2026-04-13

- **docs-sync: fix-bug → bug-triage rename across all documentation**
  - Reflects v1.104.0 3-layer architecture redesign in 12 bilingual doc files
  - Skill count corrected 43→42 in README.md, README.zh-TW.md, quick-start-zh.md
  - Mermaid diagrams updated: Bug path now shows `bug-triage` → `epic-breakdown` → `work-on` (3-layer)
  - Bug Fix prose sections rewritten for diagnosis-only model (workflow-guide EN/zh-TW, rd-workflow)
  - Template rule-examples updated (skill-routing, scenario-playbooks, pr-and-review)
  - chinese-triggers.md version bumped to v1.104.0, trigger keywords updated

## [1.104.0] - 2026-04-13

- **Skill Architecture Redesign — 3-Layer Separation (Phase 1)**
  - Three-layer model: Understanding (bug-triage / refinement) → Planning (breakdown) → Execution (work-on)
  - New: `bug-triage` v2.0.0 — pure diagnostic skill (root cause analysis → RD confirmation → enriched JIRA ticket)
  - Rewrite: `work-on` v3.0.0 — execution-only orchestrator, slimmed 56% (657→290 lines), Plan Existence Gate replaces Readiness Gate + AC Gate
  - Delete: `fix-bug` — replaced by bug-triage (Layer 1) + work-on (Layer 3)
  - Downgrade: `jira-estimation` v2.0.0 — library skill, callers updated to bug-triage + breakdown
  - Updated: `skill-routing.md`, `mechanism-registry.md`, and 12+ reference files cleaned of fix-bug references
  - Phase 2 planned: breakdown expansion as universal planner (Bug + Story/Task + Epic branches)

## [1.103.0] - 2026-04-12

- **Framework Handbook — User-Facing Working Preferences**
  - `.claude/handbook/` — new layer for user working habits and quality standards (not AI behavioral rules)
  - `working-habits.md` — session management, Strategist interaction style, decision patterns
  - `quality-standards.md` — output format (JIRA links, Slack URL formatting), verification standards
  - Migrated 6 feedback memories into handbook (session-split-direct, session-split-proactive, strategist-pushback, slack-url-linebreak, jira-ticket-clickable-link, session-split-include-trigger)
  - `CLAUDE.md` § Framework Handbook — periodic review flow (stay / upgrade to rules / downgrade to company handbook)
- **Refinement SKILL.md — Two Post-Validation Improvements**
  - Step 2b: Production Runtime Verification — curl/dev-server verification required when codebase analysis involves runtime behavior (source code ≠ runtime)
  - Step 5b: Output format constraint — refinement.md only contains implementation-ready information, no historical context or derivation process
  - Design path changed from `.claude/designs/` to `{company_base_dir}/designs/{EPIC_KEY}/` (ticket workspace model)
  - Modules table includes `Repo` column for cross-repo traceability

## [1.102.0] - 2026-04-12

- **Refinement v2 — Codebase-Backed Technical Validation**
  - `refinement/SKILL.md` v3.1.0 → v4.0.0: Phase 1 redesigned from checklist filling to 7-step technical verification
  - Complexity Tier (1/2/3): Tier 2 as floor — codebase exploration + AC hardening by default
  - AC Hardening: functional + non-functional + negative AC with verification method per criterion
  - Local-First Workflow: multi-round refinement via local markdown + browser preview, JIRA write-back only on finalization
  - `scripts/refinement-preview.py` — zero-dependency local preview server (Python stdlib + marked.js CDN, 3s auto-refresh)
  - `references/refinement-artifact.md` — structured JSON artifact schema for downstream skill consumption (breakdown, estimation, work-on)
  - `references/confidence-labeling.md` — shared confidence labeling reference (HIGH/MEDIUM/LOW/NOT_RESEARCHED)
  - Phase 2 enhanced with optional multi-role analysis (RD/QA/Arch lenses) for Tier 3
  - `references/INDEX.md` updated with new references + refinement added to explore-pattern triggers

## [1.101.0] - 2026-04-12

- **Dedup Scan + README Lint + Editorial Guideline**
  - `scripts/dedup-scan.py` — file-level bigram Jaccard overlap scanner for rules/ and references/
  - `scripts/dedup-scan-sections.py` — section-level containment scanner (finds embedded duplicates)
  - Resolved 3 true duplications: mechanism-registry § Library Rationalizations → ref to library-change-protocol.md; epic-verification-structure § Assignee → ref to jira-subtask-creation.md; epic-verification-structure § 三層驗證 → ref to epic-verification-workflow.md
  - `library-change-protocol.md` — enriched Common Rationalizations with `(docs, issues, config)` detail
  - `scripts/readme-lint.py` — skill count check + undocumented-skill cross-reference + `--fix` auto-correct + `--verbose` mode
  - `docs/quick-start-zh.md` — auto-fixed 3 stale skill counts (33/41 → 43)
  - `skills/references/docs-editorial-guideline.md` — new reference: writing style for public docs (conclusion-first, show don't tell, structured vs editorial split)
  - `rules/framework-iteration.md` — added readme-lint as Step 2 in post-version-bump chain
  - `polaris-backlog.md` — closed: "Rules/skills dedup scan", "README.md lint-on-bump"

## [1.100.0] - 2026-04-12

- **Backlog Clearance + Learning Refactor + Dedup**
  - `skills/references/review-lesson-extraction.md` — new shared reference: sub-agent prompt, dedup logic, write format, graduation check (extracted from learning SKILL.md PR/Batch modes, 1060→947 lines)
  - `skills/references/INDEX.md` — added review-lesson-extraction.md entry
  - `skills/learning/SKILL.md` — PR mode Steps P2-P4 and Batch mode Steps B5-B7 now reference the shared file instead of duplicating
  - `CLAUDE.md` — removed Context Recovery section (deduped into context-monitoring.md §4), 195→182 lines
  - `rules/context-monitoring.md` — enriched §4 Compression Awareness with artifact/timeline checks from CLAUDE.md
  - `polaris-backlog.md` — closed: skill-script-extraction (already done), learning refactor, CLAUDE.md refactor; merged: PostToolUse hooks ×2→1, isolation ×2→1; added: rules/skills dedup scan, README.md lint-on-bump

## [1.99.0] - 2026-04-12

- **Library Change Protocol + Blind Spot Scan + Key Libraries**
  - `rules/library-change-protocol.md` — universal protocol for replacing, upgrading, or removing dependencies: three-layer exhaustion check (docs → issues → config), four-question impact assessment, upgrade-specific checks (changelog, migration guide, peer deps, lock file diff), runtime vs build-time distinction, decision tier matrix
  - `CLAUDE.md` — added Blind Spot Scan as Strategist Responsibility #6: pre-execution self-check (invert, edge cases, silent failure) before presenting plans or decisions
  - `mechanism-registry.md` — registered 6 new mechanisms: `lib-exhaust-before-replace` (Critical), `lib-replace-is-t3`, `lib-config-registration-check`, `lib-lock-file-diff`, `lib-key-libraries-binding`, `blind-spot-scan`
  - b2c-web handbook — added Key Libraries section (Nuxt 3, Vue 3, Pinia, @nuxtjs/i18n, nuxt-schema-org, @nuxtjs/device, nuxt-vitalizer, Turborepo, Vitest)
  - member-ci handbook — added Key Libraries section (CodeIgniter 2, GuzzleHttp, Vue 2, Vuex 3, Vue Router 3, Webpack 5, Optimizely, Adyen)
  - `polaris-backlog.md` — added CLAUDE.md length refactor as Low priority item

## [1.98.0] - 2026-04-12

- **member-ci Handbook v0 + Company Handbook Enrichment**
  - Generated `exampleco-member-ci/.claude/rules/handbook/` — index.md (architecture overview) + 6 sub-files (api-design, php-conventions, security, vue-conventions, logging, testing)
  - Graduated 4 existing rules files + 11 review-lessons files into handbook sub-files, deleted originals
  - Key corrections from user Q&A: CodeIgniter 2.1.4 (not 3), pure PHP → Vue 2 history, device routing via CloudFront + UA, internal API design principle (不對外揭露 service)
  - `rules/exampleco/handbook/cross-repo-dependencies.md` — enriched with web-api ↔ member-ci, member-ci ↔ mobile-member-ci (legacy), member-ci ↔ docker dependencies, internal API design principle

## [1.97.0] - 2026-04-12

- **Review-Lessons Buffer Deprecation + Handbook Direct Write**
  - `repo-handbook.md` — 有 handbook 的 repo，PR review findings 直接寫入 handbook 子文件，不經 review-lessons/ buffer
  - `repo-handbook.md` — Ingest channel table 更新：PR review lesson → PR review finding (direct write)
  - `repo-handbook.md` — Review Lessons → Handbook 流程圖更新為 Direct Write 三層分類
  - First real-world validation: b2c-web 14 review-lessons files graduated (70+ patterns), review-lessons/ directory deleted

## [1.96.0] - 2026-04-12

- **Handbook Lifecycle — Full Implementation (Generate→Ingest→Query→Lint)**
  - `explore-pattern.md` — Handbook-First 探索協議：Explorer subagent 先讀 handbook 再做 codebase scan，只探索 gap，減少冗餘 Read
  - `explore-pattern.md` — Handbook Observations 回傳欄位（Used / Gaps / Stale），Strategist 收到後自動回寫 handbook
  - `explore-pattern.md` — Handbook 回寫規則：Gap → 寫入 repo/company handbook（`confidence: generated`）、Stale → 直接修正或加 stale-hint
  - `explore-pattern.md` — Conflict resolution 優先級：user correction > PR lesson > Explorer 回寫
  - `repo-handbook.md` — Step 4 重組為三管道 ingest channel（user correction / PR lesson / Explorer 回寫），lifecycle diagram 更新
  - `repo-handbook.md` — Step 5 Handbook Lint 三粒度保鮮機制：Lazy lint（讀到時驗）、Event-driven lint（git diff → stale-hint）、Batch lint（sprint planning / monthly standup）
  - `mechanism-registry.md` — 新增 Handbook Lifecycle section（5 個 canary signal）
  - `INDEX.md` — explore-pattern 描述更新

## [1.95.0] - 2026-04-11

- **AI Files Local-Mode Automation**
  - `workspace-config.yaml` — 新增 `ai_files_mode` 欄位（`local` / `committed`），公司層級控制 AI 檔案可見性
  - `polaris-sync.sh` — deploy 後自動設定 `.git/info/exclude` + `skip-worktree`（檢查 .gitignore 避免重複、只對 tracked files 設 skip-worktree、冪等）
  - `polaris-sync.sh --scan` — 新 mode，一次掃描所有 workspace repos 並修復缺漏的 git-hide 設定
  - 修正 `get_projects()` parser：只取 `projects:` block，不會誤撈 `visual_regression` 等 nested names
  - 首次 scan 修復 web-design-system（3 tracked files 缺 skip-worktree）和 exampleco-web-docker（缺 exclude entry）

## [1.94.0] - 2026-04-11

- **Handbook Knowledge Injection — Two-Layer Strategy**
  - `sub-agent-roles.md` — Company handbook = Strategist 選擇性摘錄；Repo handbook = sub-agent 自己全讀（效果等同 auto-loaded rules）
  - `repo-handbook.md` — 修正「auto-loaded by Claude Code」的錯誤描述。在 workspace setup 下 repo handbook 不會自動載入，需透過 dispatch prompt 指示 sub-agent 自己讀
  - 設計原則：company-level 放 workspace（永遠相關，自動載入）；repo-level 留在 repo（按需注入，避免 context 膨脹）

## [1.93.0] - 2026-04-11

- **Company Handbook — Three-Layer Knowledge Architecture**
  - **New concept**: Handbook 分三層 — Framework（個人工作風格）→ Company（跨 repo 知識）→ Repo（單一 repo 架構）。受 Karpathy 知識庫系統啟發：探索效率來自「起點更高」（compiled knowledge），不是「步驟更聰明」
  - **ExampleCo company handbook** (`rules/exampleco/handbook/`): index.md + 4 子文件（cross-repo-dependencies, development-workflow, tools-and-channels, testing-and-verification）
  - **Three-layer classification** (`repo-handbook.md` Step 3b): Q1「換 workspace 還適用？」→ Q2「換 repo 還適用？」— 三個問題，每個 3 秒可分類
  - **Company context injection** (`sub-agent-roles.md`): dispatch sub-agent 到子 repo 時，Strategist 注入 company handbook 的 Cross-Repo Dependencies 段落
  - **feedback-and-memory.md** item 1 改為三層分類邏輯
  - **12 筆 memory 遷移至 company handbook** 後刪除，MEMORY.md 瘦身

## [1.92.0] - 2026-04-11

- **Backlog Context Format — 每個項目附帶 Why / Without it / Source**
  - `polaris-backlog.md` — 新增 § Item Format 格式規範，所有現有項目補上 context block（動機、後果、來源）
  - `feedback-and-memory.md` — backlog entry format 從一行模板升級為帶 context block 的多行格式
  - AI Files Management 3 個子項合併為一個群組項目
  - 目標：「繼續 Polaris」時讀 backlog 即可判斷優先序，不需翻 memory 重建前因後果

## [1.91.0] - 2026-04-11

- **Handbook as Review Standard — Review Comment ↔ Handbook Cross-Reference**
  - `fix-pr-review` Step 7b 新增：修正前比對 review comment 與 handbook，衝突 → 暫停 → escalate（修 code + 更新 handbook，或回覆 reviewer 說明慣例）
  - `review-lessons-graduation` 畢業路由三分流：repo-specific → `handbook/*.md` 子文件（優先）、跨 repo 通用 → `rules/*.md`、framework → workspace `rules/*.md`
  - `repo-handbook.md` Step 3c 新增：Handbook as Review Standard — review-pr / fix-pr-review / graduation 三者統一以 handbook 為 primary context
  - Reviewer 的意見反過來驗證 handbook：衝突是 handbook 品質的校正信號，每次解決後知識庫更準確

## [1.90.0] - 2026-04-11

- **Handbook v1 — Correction-Driven Update + Nested Structure**
  - **Correction-Driven Update** (`repo-handbook.md` Step 3b) — user 糾正 repo-specific 知識時，暫停工作 → 更新 handbook（不建 feedback memory）→ 基於新理解繼續。判斷捷徑：「換一個 workspace 還適用嗎？」No → handbook，Yes → feedback
  - **Nested handbook structure** (Step 3a) — 主文件 100-300 行（架構全景），子文件 `handbook/*.md` ≤50 行（code style、testing、API conventions），全部在 `.claude/rules/` 自動載入
  - **Step 1 補強** — handbook 生成第一步改為「先讀 README.md」，README 是 Overview 和 Cross-Repo 段落的 primary source
  - **feedback-and-memory.md** — item 1 加入 handbook vs feedback 分類邏輯：repo-specific → handbook，framework → feedback
  - **mechanism-registry.md** — 新增 `correction-driven-handbook-update` (Critical) + `repo-knowledge-to-handbook-not-feedback` (High) canary
  - **首批 handbook 產出**：exampleco-b2c-web（主文件 + 3 子文件：local-dev, testing, cwv-benchmark）、exampleco-web-docker（主文件）
  - **Feedback → Handbook 遷移**：7 筆 exampleco repo-specific feedback memory 遷移至 handbook 子文件並刪除

## [1.89.0] - 2026-04-11

- **Repo Handbook — AI 的新人 onboarding 文件**
  - `skills/references/repo-handbook.md` — 完整設計：repo 類型辨識（10 種 primary type + 6 種 secondary trait）、按類型生成 handbook 結構、user Q&A 校正流程、stale detection 維護機制
  - `/init` — 最後新增 optional step：老手可在初始化時直接為已設定的 repo 建立 handbook
  - `work-on` — Phase 0.5 Handbook Check：首次 work-on 自動觸發 handbook 生成；sub-agent prompt 加入「先讀 handbook 再探索」指示
  - `git-pr-workflow` + `fix-pr-review` — post-step：PR 建好/修完後自動 diff 改動 vs handbook，更新 stale 段落
  - Handbook 存在 `{repo}/.claude/handbook.md`（gitignored），類比人類的架構文件：README 是給外部人看的，CLAUDE.md 是員工守則，handbook 是系統架構文件

## [1.88.0] - 2026-04-11

- **Learning Compile & Lint — 知識複利機制** (inspired by Karpathy's LLM Knowledge Base)
  - **Step 1.5 增強**: Baseline scan 新增查詢 `polaris-learnings.sh` 既有知識，讓每次學習從已知出發而非從零開始
  - **Step 4b Compile (新增)**: 新學到的知識與既有 learnings 碰撞 — 明確標注 confirm（增強信心）/ contradict（發現矛盾）/ extend（擴展深度）/ new（全新知識）。自動 confirm/boost 已驗證的 learnings
  - **Step 6 Lint (新增)**: 學習完成後分析知識盲點 — adjacent unknowns、stale knowledge、unresolved contradictions、depth gaps。產出 1-3 個建議下一步學什麼，並自動回寫 learnings 到 cross-session knowledge base
  - External flow 從 `Ingest → Extract → Save` 進化為 `Ingest → Extract → Compile → Save → Lint`，知識從此能滾雪球

## [1.87.0] - 2026-04-10

- **EPIC-521 拘束機制 — 行為規則推到確定性層**
  - `scripts/verification-evidence-gate.sh` (PreToolUse) — ticket branch 上 `gh pr create` 必須有 `/tmp/polaris-verified-{TICKET}.json` evidence file（valid JSON、< 4h、ticket match、non-empty results）。無 evidence = exit 2 物理攔截。Bypass: `POLARIS_SKIP_EVIDENCE=1`（非 ticket PR）
  - `scripts/test-sequence-tracker.sh` (PostToolUse on Bash|Edit|Write) — 追蹤 test-fail → production-file-edit → test-pass 序列，偵測到時注入警告：「你改了 production code 讓測試過，確認這是正確修法？」
  - `scripts/polaris-write-evidence.sh` — evidence file writer，供 verify-completion / fix-bug 呼叫
  - `api-docs-before-replace` mechanism (Critical) — 模組行為不符預期時，必須查官方 API 文件再行動。Compiled source ≠ API truth。替換是 T3 決策需使用者確認
  - mechanism-registry: 新增 Deterministic Quality Hooks section + Priority Audit Order #12
  - settings.json: 註冊兩支新 hooks

## [1.86.0] - 2026-04-10

- **`runtime-claims-need-runtime-evidence` mechanism (High)** — Sub-agent source code analysis about runtime behavior must be verified with actual execution (curl, test, dev server) before adoption. Source: nuxt-schema-org JSON-LD position was incorrectly concluded as `<head>` from code reading; actual production output is in `<body>`
- **Backlog cleanup addendum** — closed Session-split checkpoint gate (covered by `checkpoint-mode-at-25`)

## [1.85.0] - 2026-04-10

- **API Contract Guard** — Detects schema drift between Mockoon fixtures and live API responses. Prevents stale fixtures from masking real API contract changes (false negatives). Three drift categories: breaking (type change, field removal → blocks task), additive (new field → auto-update), value-only (same schema → no action)
  - `scripts/contract-check.sh` — schema diff engine (Python, zero deps). Parses Mockoon environment files, hits live API via proxyHost, recursive JSON schema comparison. Exit codes: 0=clean, 1=breaking, 2=unreachable
  - `skills/references/api-contract-guard.md` — design doc with drift classification, skill integration pattern, fixture update flow
  - Pre-steps added to 4 skills: `visual-regression` (Step 2.5), `fix-bug` (Step 4.4), `work-on` (Phase 1.5), `verify-completion` (Pre-flight)
- **Backlog cleanup** — closed 36 items (23 Medium no-pain/premature + 13 Low brainstorm-era). 11 items remain

## [1.84.0] - 2026-04-10

- **fix-pr-review configurable mode** — Step 0.5 now reads `skill_defaults.fix-pr-review.mode` from `workspace-config.yaml` (default: `auto`). Users set their preferred mode in config; per-invocation keywords (`互動`/`auto`) still override

## [1.83.0] - 2026-04-10

- **Backlog Hygiene mechanism** — Post-version-bump chain 新增 Step 2：掃描 `polaris-backlog.md` 的 stale items。每個 `[ ]` item 帶 `(YYYY-MM-DD)` 日期 tag，可選 `[platform]`/`[next-epic]` 豁免 tag。無 tag > 60 天 → 建議關閉，有 tag > 90 天 → 確認是否仍有效。Fallback：每月首次 `/standup` 觸發
- **Backlog 大掃除** — 移除 ~75 個完成項，34 個 open items 按主題重新分組，全部標記日期 + 豁免 tag。檔案從 362 行縮到 137 行
- **`backlog-staleness-scan` mechanism (Medium)** — 新增 mechanism-registry canary，追蹤版本升級和月度 standup 是否觸發 backlog 掃描

## [1.82.0] - 2026-04-10

- **fix-bug Step 4.5 Hard Gate** — AC Local Verification 升級為 Hard Gate：每個 Local 驗證項必須有 PASS/SKIP/FAIL disposition + 證據（test output、curl response、截圖），不允許「unit test 過了就跳過行為驗證」。來源：TASK-3783 hotfix 中跳過了起 dev server 的語系切換驗證，只靠 unit test 就發 PR
- **`local-verification-hard-gate` mechanism (Critical)** — 新增 mechanism-registry canary：fix-bug Step 4.5 的 Local 驗證項如果包含行為驗證（需起 server），不可只用 unit test 替代

## [1.81.1] - 2026-04-10

- **Reference Discovery INDEX.md tracked** — `skills/references/INDEX.md` now committed to the repo (was untracked). Reference Discovery section added to CLAUDE.md as a supplement to v1.80.0

## [1.81.0] - 2026-04-10

- **sync-to-polaris auto-genericize** — Before committing to the template repo, automatically applies each company's `genericize-map.sed` + `genericize-jira.sed` to all `.md` files. Company-specific references (JIRA keys, domains, Slack IDs, org names) are replaced with generic placeholders before the template is committed. The post-commit leak check now serves as verification — surviving patterns indicate missing sed rules, not a manual cleanup task. Converts the 18-hit leak warning (v1.79.0) from "remind to fix" to "auto-fixed"

## [1.80.0] - 2026-04-09

- **Version bump reminder PostToolUse hook** — Deterministic enforcement for the Critical `version-bump-reminder` mechanism. `hooks/version-bump-reminder.sh` fires after every `git commit`, checks committed files for `skills/` or `rules/` paths, injects a reminder if found. Skips VERSION bump commits to avoid loops. Wired into `settings.json` PostToolUse
- **Reference Discovery mechanism (Critical)** — New `reference-index-scan` canary in mechanism-registry: before any skill execution, read `skills/references/INDEX.md` and pull trigger-matched references. Added to CLAUDE.md § Reference Discovery as a skill execution prerequisite. Common Rationalizations table included
- **Write Isolation Model documentation** — `sub-agent-delegation.md` gains § Write Isolation Model: three tiers (Shared / Worktree / Cross-repo) with selection guide, inspired by LangGraph's per-task write buffer pattern
- **Backlog hygiene** — closed "Standup 口頭同步條列化" (already implemented), closed "Version bump hook" (done this version), closed "Write isolation model 文件化" (done this version)

## [1.79.0] - 2026-04-09

- **jira-worklog v2.0 — Daily quota allocation** — 8h per workday split among In Development tickets by story point weight. Smart filtering excludes non-logged ticket types. Batch curl for multi-day backfill. Standup auto-log integration
- **Story Points dynamic discovery (cross-cutting)** — `jira-story-points.md` rewritten as authoritative reference with mandatory Step 0 field ID discovery. All 7 skills using Story Points (converge, epic-status, intake-triage, jira-worklog, my-triage, jira-subtask-creation, work-on) updated to use `<storyPointsFieldId>` placeholder — hardcoded `customfield_10016` strictly forbidden
- **epic-verification-structure.md rewrite** — Verification tickets default 0pt (not 1pt), lifecycle flow with PASS/FAIL comment templates, Epic close criteria, implementation task description split into code-level test plan vs business-level AC sections, test sub-tasks as JIRA 子任務 issueType (not Task)
- **PR review conventions (L1 rule)** — New universal `pr-and-review.md`: inline comments mandatory (no findings in review body), review language follows PR description language. exampleco-scoped placeholder added
- **check-pr-approvals** — PR links must be clickable markdown format
- **jira-subtask-creation** — Step 0 query existing sub-tasks before creating, assignee param fix
- **version-bump-reminder canary (Critical)** — Added to mechanism-registry after discovering 6 consecutive sessions modified `skills/` without triggering version bump reminder. Common Rationalizations table added. Backlog item for deterministic PostToolUse hook

## [1.78.0] - 2026-04-08

- **sasd-review v1.0.0 — Design-First Gate** — 從 exampleco 專屬提升為框架級 skill。在寫任何程式碼前產出 SA/SD 設計文件：需求分析 → 歧義收集 → 2-3 方案比較 → 確認後產出（含 Dev Scope、System Flow、Task List with Estimates）。移除 exampleco 專有術語（BFF、PC/M），保留通用工程紀律
- **jira-quality.md — L1 通用 JIRA 規則** — 從 exampleco jira-conventions 提升 7 條通用規則：缺資訊主動問不猜、PM 範例 ≠ 實作規格、外部連結需取回內容、建完 issue 附連結、拆單含驗證場景、批次建子單、attachment 先刪再傳。exampleco jira-conventions 瘦身為僅保留專案 key 結構和 VR template 格式
- **清理 exampleco 重複 skills** — 刪除 ai-config 中 6 個重複的 skill 副本（exampleco-dev-quality-check、exampleco-git-pr-workflow、exampleco-unit-test、exampleco-dev-guide 及對應的 non-prefix stale copies），Polaris 已有更新版本
- **skill-routing.md** — 新增 sasd-review 路由條目

## [1.77.0] - 2026-04-08

- **pr-convention v1.3.0 — Template-aware PR body** — Step 1 偵測專案 PR template 檔案（5 路徑優先順序），Step 4b 以 template section 結構為骨架填入內容。Mapping table 涵蓋常見 section（Description, Changed, Screenshots, Checklist, Breaking Changes 等），不認識的 section 保留 heading 並用 HTML comment hint 生成內容。無 template 則 fallback 到預設格式。AC Coverage 在 template 未定義時自動注入
- **git-pr-workflow Step 7** — 改為引用 pr-convention 的 template 偵測與 mapping 邏輯，避免重複定義

## [1.76.0] - 2026-04-07

- **fix-bug Step 4.5 AC Local Verification** — 開發完成後、發 PR 前，根據 ticket 的 [VERIFICATION] Local 項目逐一驗證（unit test / Playwright 截圖 / 手動確認），結果更新回 JIRA。Post-deploy 項目標記「待 SIT 驗證」不阻擋 PR
- **fix-bug VR Gate（條件觸發）** — 改動涉及前端可見代碼（pages/components/layouts/_.vue/_.scss）且有 VR 設定時，自動觸發 visual regression 檢查
- **jira-estimation VERIFICATION 兩層模板** — Bug 的預計驗證方式分 Local（PR 前，RD 負責）和 Post-deploy（SIT/Prod，驗證子任務追蹤）兩層，JIRA comment 模板同步更新

## [1.75.0] - 2026-04-07

- **jira-estimation Bug VERIFICATION section** — Bug ticket 的 [ROOT_CAUSE] + [SOLUTION] 模板新增 `[VERIFICATION]` 段，列出預計驗證方式（重現步驟、邊界場景、數據確認），比照 Task 的 AC 概念
- **pr-create-guard.sh env bypass** — 新增 `POLARIS_PR_WORKFLOW=1` 環境變數讓 git-pr-workflow skill 合法放行 `gh pr create`。修正 hook 無法區分「隨手開 PR」與「skill 品質檢查後開 PR」的設計缺口
- **git-pr-workflow v3.4.0 Step 7** — 加上 `POLARIS_PR_WORKFLOW=1` 環境變數說明

## [1.74.0] - 2026-04-07

- **VR Principles P1-P7** — 將 6 個 session 累積的 hard-won rules 集中寫入 SKILL.md（走 nginx proxy、CSR waitForSelector、mobile UA、proxy/replay mode 差異、首次截圖 quality gate、workers:1、JIRA wiki markup）。P1/P3 泛化為框架層原則，exampleco 細節以 blockquote 附註
- **VR Phase 2 mandatory checkpoint** — replay mode 切換後強制跑 VR pass + 人工截圖確認，才能進 Phase 3 commit fixtures。防止 proxy fallback 隱藏缺失 fixture
- **VR JIRA report template** — 新增 `references/vr-jira-report-template.md`，定義 wiki markup 表格穿插截圖格式、all-pass / mixed results 模板、attachment 命名慣例。Step 5c 引用此 template
- **checklist-before-done 機制** — 宣告任務完成前必須回查 session 起始清單，逐項確認 done/carry-forward/dropped。加入 context-monitoring §5b + mechanism-registry（High drift）
- **JIRA 附件先刪再傳規則** — 加入 `rules/exampleco/jira-conventions.md`，適用所有 JIRA attachment 操作
- **ai-config version control** — `.gitignore` whitelist VR test files（pages.spec.ts, playwright.config.ts）+ proxy-config.yaml。Fixture JSON 維持 local only。新公司只需加 `!{company}/`
- **visual-regression-config.md** — 新增 Playwright config 必設項目（workers:1, mobile UA）

## [1.73.0] - 2026-04-06

- **Per-Epic Fixture Isolation** — fixture 管理從 root-level 遷移到 per-epic 子目錄（`mockoon-environments/EPIC-483/`）。每個 Epic 獨立一套完整 fixture，新 Epic 從上一個 copy + 重錄有變動的 route。刪除 root-level 12 個 legacy JSON 檔案
- **mockoon-runner.sh `--epic` 參數** — `mockoon-runner.sh start <dir> --epic EPIC-483` 從子目錄載入 fixture。Root-level loading 標記 deprecated
- **VR SKILL.md 三個 feedback 寫入** — (1) Mockoon CLI proxy 不自動錄 fixture，需手動 curl (2) 首次截圖品質閘門：zero-diff ≠ 正確，需人工確認 (3) JIRA attachment 同名覆蓋陷阱：wiki markup 綁 attachment ID 不是檔名
- **VR SKILL.md Fixture Lifecycle section** — 文件化 per-epic 目錄結構、bootstrap 流程、runner 整合、設計決策（為何不做 base + overlay）
- **EPIC-483 fixture 合併** — 從 root 補齊 11 條 route（mkt 1、svcb2c 2、hotel_product 4、product 4），EPIC-483 現為完整獨立集合（12 檔、47 routes）
- **Gzip header 全清** — 最後一個殘留（EPIC-483/recommend `content-encoding: gzip`）已移除。來源：Mockoon proxy 錄製時抓了真實 server 的壓縮 header 但存了已解壓的 body

## [1.72.0] - 2026-04-06

- **Cross-Session Carry-Forward Check** — 寫 next-session memory 前必須 diff 前一份 checkpoint 的 pending items。每個 item 必須標記為 (a) done / (b) carry-forward / (c) dropped，不允許靜默丟棄。根因：v1.71 session 掉了 JIRA VR 報告，因為 4/6 session 寫新 memory 時沒回頭檢查 4/5 checkpoint 的未完成項
- **Checkpoint Mode at 25 Tool Calls** — tool call > 25 且有 pending work 時，主動進入存檔模式：寫 checkpoint memory + diff 前一份 checkpoint + 建議開新 session。防止 context 耗盡導致跨 session 狀態遺失
- **mechanism-registry 新增** — `cross-session-carry-forward` (Critical) + `checkpoint-mode-at-25` (High)，加入 Priority Audit Order #5 和 #6a

## [1.71.0] - 2026-04-06

- **VR 確定性修復：fixture gzip header 根因** — Mockoon fixture 的 `Content-Encoding: gzip` header 搭配 plain JSON body 導致 Mockoon crash（嘗試解壓非壓縮資料）。這同時是 proxy mode 崩潰和 Product page SSR hang 的根因。移除 14 個 response 的 gzip header 後，8/8 zero-diff、Product page 首次正常渲染
- **polaris-env.sh env override 恢復** — `--vr`/`--e2e` 自動從 `proxy-config.yaml` 讀 `env_override` 注入 dev server 啟動指令。v1.70.0 移除後發現仍需要（Mockoon fixture 需要 env override 才能攔截 API calls）
- **VR SKILL.md：Record → Compare 兩階段流程** — 新增 Fixture Recording Workflow section，文件化 fixture 錄製（proxy mode）→ 驗證（replay mode）→ commit 的完整生命週期
- **JIRA VR 報告補發** — EPIC-483 VR 通過 comment（8/8 zero-diff + 確定性措施 + 修復紀錄），修正上次 session 遺漏
- **proxy-config.yaml 公司層** — 從 EPIC-483/ Epic 目錄 copy 到 `mockoon-environments/`，成為公司共用 config

## [1.70.0] - 2026-04-05

- **VR 架構修正：走 Docker nginx，不走 localhost** — VR base_url 從 `localhost:3001` 改回 `dev.exampleco.com`（Docker nginx）。之前因 Docker compose v2 壞掉繞過 nginx，導致整個架構歪掉（Product page "SSR hang"、Search page "不在 b2c-web" 都是偽問題）。現在回到正確路徑：Playwright → Docker nginx → b2c-web / member-ci / mobile-member-ci
- **移除 Search page** — `exampleco.com/zh-tw/search/?keyword=tokyo` production 回 404，頁面不存在。從 spec 和 workspace-config 移除
- **Product page 解除 skip** — 走 Docker nginx 後 SSR 應能正常 render，之前的 "hang" 可能是 localhost 直打造成的
- **移除 polaris-env.sh env override 自動注入** — 不再需要 Mockoon 取代 nginx，b2c-web 通過 Docker 網路呼叫 member-ci
- **feedback memory** — 記錄 workaround 累積導致架構歪掉的完整路徑，`no-workaround-accumulation` 教科書案例

## [1.69.0] - 2026-04-05

- **VR JIRA 圖文報告** — Step 5b 擴充為三步（收集 artifacts → `jira-upload-attachment.sh` 批次上傳 → 解析 URL）。Step 5c 改為 wiki markup 圖文穿插報告（每頁一 section，PASS 附截圖，FAIL 附 diff 圖，SKIP 附原因）。MCP markdown mode 不支援 attachment 引用，改用 REST API v2 + wiki markup
- **jira-upload-attachment.sh** — 共用腳本，curl + JIRA REST API 批次上傳 attachment，自動從 `.env.secrets` 讀取 credentials。所有需要 JIRA 附件的 skill 可共用
- **Fixture 一致性驗證** — `proxy-config.yaml` 新增 `migration_pairs` schema，`record-fixtures.sh` Step 6 自動比對新舊 endpoint 的 JSON key structure。支援 `key_structure` 和 `exact` 兩種比對模式，endpoint 遷移場景（如 i18n member-ci → api-lang）自動抓不一致
- **polaris-env.sh env override 自動注入** — `--vr`/`--e2e` profile 下自動掃描 `environments_dir/*/proxy-config.yaml`，讀取所有 `env_override` 值 prepend 到 dev server 啟動指令。不再需要手動設定 `.env.local`
- **Product page SSR hang 重分類** — 確認 fixture 已齊（`fetch_product/10000` + `fetch_packages_data`），hang 是 SSR code 層級 bug（API 全回但 render 不完成）。Backlog 從 "fixture 補全" 更新為 "SSR debug runbook"
- **Search page 不在 b2c-web** — 確認 `/search/` 由外部服務處理，local dev 無法載入。SIT mode 可覆蓋

## [1.68.0] - 2026-04-05

- **VR domain-level testing principle** — VR tests domains, not repos. Skip reasons changed from "not in this repo" to actionable TODOs (missing fixtures, SSR investigation needed). Feedback memory recorded for cross-session enforcement
- **VR SKILL.md Step 5c: JIRA update required** — VR results (pass/fail/skip with reasons) must be written to JIRA verification ticket after every run. Structured comment template added
- **VR backlog: 5 coverage completeness items** — Product page fixture gap, Search Results fixture, dual-endpoint consistency validation, JIRA auto-update AC, polaris-env.sh env override automation

## [1.67.0] - 2026-04-05

- **Design doc persistence in work-on** — `work-on` now writes a per-ticket design doc to `.claude/designs/{TICKET-KEY}.md` at two points: batch Phase 1 Step 1e (after user confirms analysis) and single-ticket Step 5g (after AC Gate). Design docs capture technical approach, test plan, sub-tasks, and decisions. Phase 2 sub-agents now read the design doc file instead of receiving inline analysis text, reducing prompt size and enabling cross-session resume via file read. `.claude/designs/` added to `.gitignore`
- **CLAUDE.md updated** — `.claude/designs/` listed in Framework Files section and product repo `.gitignore` recommendation

## [1.66.0] - 2026-04-05

- **CSO audit: 17 skill descriptions rewritten to trigger-only** — Discovered via Superpowers learning that SKILL.md descriptions containing workflow summaries cause the agent to shortcut (follow description instead of reading full body). Audited all 42 skills: 9 HIGH, 8 MEDIUM flagged. All 17 descriptions rewritten to contain ONLY trigger conditions, never workflow steps. Average reduction from 6-14 lines to 1 line per description
- **Rationalization tables for top 3 high-drift mechanisms** — Added "Common Rationalizations" sections to mechanism-registry.md for `skill-first-invoke` (7 entries), `delegate-exploration` (4 entries), and `fix-through-not-revert` + debugging/verification (7 entries). All entries sourced from real observed violations (EPIC-483 sessions, VR env failures), not hypothetical. Pattern inspired by Superpowers' prompt engineering approach
- **Superpowers learning → 2 backlog items** — Critic two-stage review split (spec-compliance + code-quality), skill-creator baseline failure recording (RED-GREEN-REFACTOR for skills)

## [1.65.0] - 2026-04-05

- **Fan-in validation for parallel sub-agents** — new "Fan-In Validation" section in `sub-agent-delegation.md`. When dispatching multiple parallel sub-agents, the Strategist now validates all completion envelopes before synthesis: Status must be present, Artifacts must be non-empty for DONE status, and missing/BLOCKED/PARTIAL agents are handled explicitly. Prevents silent partial failures from corrupting synthesis results
- **Return vs Save separation in completion envelope** — `sub-agent-roles.md` Completion Envelope gains a new convention: `User Summary` (concise result for display) vs `Checkpoint State` (full context for cross-session resume). Solves the common failure mode where memory files are either too terse or too verbose for session continuation
- **LangGraph learning → 4 backlog items** — Deep exploration of langchain-ai/langgraph produced actionable insights: per-skill retry policy (`polaris-retry.sh`), session-level cache (`polaris-cache.sh`), write isolation model documentation, and structured memory namespace. All tracked in backlog Medium with source attribution

## [1.64.0] - 2026-04-05

- **Chinese developer guide sections** — quick-start-zh.md expanded from quick-start-only to complete developer guide: architecture (three-layer rules, directory structure, workflow orchestration, scheduled agents), multi-company setup (isolation mechanism, diagnostics), customization (safe-to-edit vs framework internals), and upgrading (sync-from-polaris.sh). Chinese-speaking colleagues no longer need to reference the English README

## [1.63.0] - 2026-04-05

- **sync-to-polaris post-sync leak check** — new `leak_check()` function in `sync-to-polaris.sh` that runs between commit and push. Extracts company-specific patterns from all `workspace-config.yaml` files (JIRA ticket keys as `KEY-\d+`, domain names, Slack channel IDs, GitHub orgs) and greps the polaris template. Warns on matches but does not block push. First scan found 71 hits to genericize over time
- **VR strict judgment backlog cleanup** — merged two duplicate entries, confirmed VR SKILL.md already has "Strict mode (fixtures active)" section with zero-diff-only pass criteria

## [1.62.0] - 2026-04-05

- **Mockoon fixture per-Epic lifecycle** — epic-verification-workflow.md gains Fixture Lifecycle section: record at Epic start, re-record after cross-repo API task, develop on stable fixtures, delete on release. exampleco playwright-testing.md gains full Mockoon integration doc (architecture, recording workflow, parallel Epic isolation design). Backlog item updated from "pending" to "design complete"
- **epic-breakdown API-first ordering + fixture recording task** — when Epic involves cross-repo API changes, API task must be ordered first. Additionally, epic-breakdown now auto-generates a "穩定測資" (fixture recording) task (1pt) for Epics with `visual_regression` config. Ordering: API task → fixture recording → frontend tasks. This makes fixture recording a visible, trackable JIRA ticket instead of hidden skill logic

## [1.61.0] - 2026-04-05

- **fix-pr-review Step 3b rebase hygiene expansion** — Step 3b renamed to "Post-Rebase 衛生檢查" and split into 3b-1 (full scan of inherited non-PR files: changesets, pre.json, CHANGELOG, package.json version bumps) + 3b-2 (changeset self-check). Previously only cleaned `.changeset/` files, now uses `git checkout origin/{baseRefName}` to restore all inherited files to base state before push. Source: PR #2088 lesson where rebase brought in unrelated CHANGELOG and version bumps

## [1.60.0] - 2026-04-05

- **Epic verification Playwright-first update** — epic-verification-workflow.md updated with `browser` (Playwright) as the preferred verification type over curl. Verification examples use `{BASE_URL}` variable (company-layer defines the actual URL). Added EPIC-483 Lessons Learned section: browser-first rationale, URL format conventions (locale lowercase, urlName not area code), SIT→localhost test data sourcing. Graduation checklist: Epic #1 complete, awaiting Epic #2 to graduate into skill integration
- **exampleco playwright-testing reference** (company-layer, gitignored) — defines dev.exampleco.com as BASE_URL, Docker routing map (b2c-web / member-ci / mobile-member-ci), auth via test account + storageState, A/B mock via route intercept, URL conventions

## [1.59.0] - 2026-04-04

- **Deterministic post-task reflection checkpoint** — 33 write skills now have a mandatory `## Post-Task Reflection (required)` final step in their SKILL.md, pointing to shared reference `skills/references/post-task-reflection-checkpoint.md`. Covers behavioral feedback scan, technical learning check, mechanism audit (top 5 canaries), and graduation check. 12 read-only skills excluded. Root cause: two EPIC-483 sessions produced 12+ violations with zero feedback because the Strategist was always "still fixing" and the task-completion trigger never fired. This is 方案 C from the backlog — the lowest-cost deterministic enforcement that makes reflection impossible to skip

## [1.57.0] - 2026-04-04

- **polaris-env.sh Docker health check fix** — Docker services (Layer 1) now use port-listening check instead of HTTP 200 (nginx returns 404 on `/` but services are up). Requires check for Docker dependencies also uses port-based verification. Fixed `docker compose` → `docker-compose` for Colima compatibility. Added stabilization wait before Layer 4 verification
- **JIRA attachment upload via REST API** — validated curl-based upload to JIRA tickets using API token stored in `{company}/.env.secrets`. Enables VR screenshots to be attached to verification tickets. Token setup uses IDE file editing (not terminal `read -s` which fails in Claude Code's non-interactive shell)

## [1.56.0] - 2026-04-04

- **Deterministic Enforcement Principle** — new framework-level design philosophy in CLAUDE.md: "能用確定性驗證的，不要靠 AI 自律". When behavioral drift is discovered, the fix must push checks into deterministic layers (scripts, hooks, exit codes), not add another behavioral rule. Includes workaround accumulation signal: ≥2 workarounds for the same feature → STOP and check design
- **polaris-env.sh design fix** — `--vr` profile now starts Layer 1 (Docker) like all other profiles. Previous design incorrectly assumed Mockoon replaces Docker; Docker is infrastructure, Mockoon supplements it. Removed `ensure_redis()` (Redis lives in Docker compose). Restored `requires` check for all profiles
- **polaris-env.sh hard gate** — Layer 4 verification is now profile-aware and exits non-zero when required services fail health check. Prevents downstream tools from running in a broken environment
- **VR strict mode** — SKILL.md Step 5: when Mockoon fixtures are active, zero-diff is the only PASS. No "known variance" or "data variation" classification allowed
- **Decision drift mechanisms** — 4 new canaries in mechanism-registry: `no-workaround-accumulation` (Critical), `design-implementation-reconciliation` (High), `env-hard-gate` (High), `no-bandaid-as-feature` (High). Workaround accumulation is now #1 in Priority Audit Order
- **Backlog: skill checkpoint gate + clean-room test** — medium-term items for extending deterministic enforcement to skill execution and new script validation

## [1.55.0] - 2026-04-04

- **Project→Backlog pipeline fix** — `type: project` memories with action items (待實施/下一步/需要解決) now trigger FRAMEWORK_GAP classification and flow into `polaris-backlog.md` at write time. Previously only `type: feedback` memories were classified, causing project-level improvements to become dead letters. Batch scan during memory hygiene also extended to cover project memories
- **`project-backlog-classification` mechanism** — new High-drift canary in mechanism-registry: project memory containing action items without corresponding backlog entry. Catches the gap that let VR improvements sit unactioned for a full day
- **VR reliability trio in backlog** — three items added: Mockoon fixture determinism (fix false positives), polaris-env.sh hardening (Redis/port/pnpm auto), VR strict judgment (zero-diff only when fixtures active)

## [1.54.0] - 2026-04-04

- **/next v1.1.0 — cross-session recovery** — Level -1 added before todo/git/JIRA checks: scans MEMORY.md for in-progress project memories, `.claude/checkpoints/` for recent checkpoints, and `wip/*` branches. Enables "推進手上的事情" to resume both ticket-based work and memory-based work (e.g., framework improvements, design discussions). Universal improvement — all users benefit, not just framework maintainers

## [1.53.0] - 2026-04-04

- **Epic three-layer verification reference doc** — `references/epic-verification-workflow.md`: Task test plans (PR gate records), per-AC verification tickets (Playwright E2E), Feature integration tests. Includes graduation criteria (2 Epic cycles), size threshold (>8pt → per-AC split), environment tagging (feature/stage/both), and skill integration map. Draft status — validate before graduating to skill changes
- **ExampleCo JIRA conventions rule** — `.claude/rules/exampleco/jira-conventions.md`: sub-tasks in KB2CW project (Task + parent link), ticket creation guidelines, happy flow verification requirement. First L2 company rule for exampleco

## [1.52.0] - 2026-04-04

- **VR conditional trigger in quality gate** — `dev-quality-check` Step 8b: auto-detect frontend-visible changes (pages/, components/, layouts/, _.vue, _.css) and recommend VR when `visual_regression` is configured. Also triggers for member-ci and design-system changes that affect b2c rendering. Informational, not blocking
- **Epic verification backlog** — three-layer verification structure designed: Task test plans (PR gate records), per-AC verification tickets (Playwright E2E), Feature branch integration tests. Auto-rebase pre-step, auto-generated verification tickets, and feature integration testing planned for upcoming versions

## [1.51.0] - 2026-04-04

- **One-click environment — polaris-env.sh** — new `scripts/polaris-env.sh` with start/stop/status commands and three profiles: `--full` (Docker + dev servers), `--vr` (Mockoon + standalone dev server, skips Docker requires), `--e2e` (all layers). 4-layer architecture: infra → fixtures → dev servers → health verification. Idempotent (skips already-running services), PID tracking in `/tmp/polaris-env/`. VR SKILL.md Step 2 refactored from ~120 lines inline management to a single `polaris-env.sh --vr` call
- **Polaris naming update** — "About the name" section updated to reflect the original North Star concept (guiding users further than they imagined) rather than the interim Zhang Liang reference

## [1.50.0] - 2026-04-04

- **Session Start — Fast Check protocol** — every conversation begins with a lightweight WIP detection (`git status` + `stash list` + branch check). If uncommitted changes exist, reports to user and offers: continue WIP or branch-switch. Topic switches use `wip/{topic}` branches instead of stash (explicit, trackable, survives across sessions). Two new mechanism-registry canaries: `session-start-fast-check` and `wip-branch-before-topic-switch` — source: commit 混到 prevention

## [1.49.0] - 2026-04-04

- **Security hardening — skill-sanitizer + safety-gate expansion** — New `scripts/skill-sanitizer.py`: 5-layer pre-LLM security scanner (credentials, prompt injection/exfil/tamper, suspicious bash, context pollution, trust abuse) with code block context awareness and Unicode normalization. 15 built-in test vectors, `scan-memory` mode for memory file integrity checks. `safety-gate.sh` expanded from 5 to 11 patterns (added reverse shell ×3, pipe-to-shell ×2, crontab). Learning skill Step 1.1 pre-scans external repo SKILL.md files before exploration. Memory integrity guard in `feedback-and-memory.md`. Security section in mechanism-registry (3 canaries). README Security section with zero-telemetry policy. Inspired by [skill-sanitizer](https://github.com/cyberxuan-XBX/skill-sanitizer) — source: gstack telemetry incident response

## [1.48.0] - 2026-04-03

- **/init re-init mode** — existing users can run `/init` → "Re-init" to add only new sections (Step 9a Dev Environment, Step 9b Visual Regression) without re-running the full wizard. Scans existing config for missing fields and only runs the gaps. Recommended upgrade path from pre-v1.46.0
- **/init Step 9b-4 server config resolution** — critical fix from second simulation: when a project depends on an infrastructure repo (Docker stack), VR config now correctly inherits the infra repo's `start_command` and `base_url` instead of the app's standalone dev server. Presents A/B choice to user. Accuracy improved from ~30% to ~80% in simulation
- **/init Phase 3.5 locale expansion** — after confirming pages, asks whether to test additional locales beyond the primary

## [1.47.0] - 2026-04-03

- **/init Step 9a+9b friction fixes** — validated via worktree simulation against real exampleco repos. Seven fixes: (1) cross-repo dependency detection scans Docker volume mounts and .env cross-references to surface prerequisites (2) SIT URL always asks user — `.env` contains dev URLs not SIT, auto-detection was wrong (3) production domain requires explicit user input — code only has dev/template URLs (4) dynamic routes prompt user for example IDs/slugs (5) missing `.env.example` warning when start script references `.env.local` (6) monorepo multi-app selection instead of assuming which app is primary (7) locale codes read from i18n config for correct case

## [1.46.0] - 2026-04-03

- **visual-regression before/after rewrite** — SKILL.md completely rewritten from baseline model to before/after comparison. Two modes: SIT (staging vs local dev) and Local (git stash before/after). Leverages Playwright's built-in `--update-snapshots` for temporary baselines — no files committed. Server startup uses health-check-first strategy (reuse running server, only start if needed)
- **Lib layering** — Playwright dependency moved from per-domain `package.json` to company VR level (`ai-config/{company}/visual-regression/package.json`), all domains share one installation. Domain directories contain only test files
- **Config cleanup** — removed obsolete `baseline_env` and `snapshot_dir` defaults from root workspace-config.yaml. VR config reference updated with before/after mode description, fixture server value proposition, and new directory structure
- **/init Step 9a + 9b** — new sections: Dev Environment (AI-detects start commands from docker-compose/package.json/Makefile/README, smartSelect presentation) and Visual Regression (domain mapping, key page discovery, SIT URL, test file generation). Populates `projects[].dev_environment` and `visual_regression.domains[]` in company config
- **workspace-config-reader** — added `dev_environment.*` and domain-level VR field index, removed stale project-level VR fields
- **skill-routing** — visual-regression triggers added to routing table
- **Mockoon fixture value** — feedback memory recording why fixture server matters (backend API changes during development cause false positives in screenshot comparison)

## [1.45.0] - 2026-04-03

- **intake-triage generalized** — promoted from exampleco-specific (`skills/exampleco/`) to shared skill (`skills/intake-triage/`). Domain lens now config-driven: reads `intake_triage.lenses` from workspace-config.yaml with built-in defaults as fallback. Author changed to Polaris. Skill count 39→40
- **docs-sync** — READMEs (EN+zh-TW) skill count updated, chinese-triggers.md entry added, workflow-guide mermaid diagrams updated with intake-triage node

## [1.44.0] - 2026-04-03

- **intake-triage skill** — new exampleco-specific skill for batch ticket prioritization from PM. Analyzes tickets across 5 dimensions (Readiness, Effort, Impact, Dependencies, Duplicate Risk) with theme-aware domain lenses (SEO/CWV/a11y/generic). Produces a prioritized verdict table (Do First/Do Soon/Do Later/Skip/Hard Block) with Do First capped at 3, writes JIRA labels + analysis comments, and sends PM-facing Slack summary in non-technical language. Epic + subtask auto-convergence: when both appear in a batch, Epic becomes a summary header while subtasks are individually scored. Tested on 44 real tickets. Execution Queue deferred to Phase B (backlog) with 4 explicit trigger conditions
- **skill-routing update** — intake-triage added to routing table, "排優先" trigger disambiguated from my-triage (requires multiple ticket keys)

## [1.43.0] - 2026-04-03

- **Hotfix auto-ticket creation** — two-layer mechanism for hotfix scenarios where no JIRA ticket exists: (1) Strategist pre-processing route: fix intent + Slack URL + no JIRA key → read Slack thread → auto-create Bug ticket → route to `fix-bug` with new ticket key (2) git-pr-workflow Step 6.0 safety net: if changeset step detects no JIRA key in branch/commits → auto-create ticket, update PR title and changeset. Prevents CI failures from missing JIRA key in changeset/PR title. Mechanism registry entry `hotfix-auto-ticket` added for post-task audit

## [1.42.0] - 2026-04-03

- **Language preference** — `/init` Step 0a now asks the user's preferred language (zh-TW, en, ja, etc.) and writes it to root `workspace-config.yaml`. The Strategist reads this field at conversation start and responds in that language. Template config updated with a NOTE clarifying that `language` belongs in root config, not company config

## [1.41.0] - 2026-04-03

- **Learning from tvytlx/ai-agent-deep-dive** — deep-dive into reverse-engineered Claude Code architecture specs (16 docs). Three actionable items applied: (1) `verify-completion` verification sub-agents now default to read-only — cannot modify project files to make verification pass (verifier ≠ fixer), with explicit exception for auto-fix items (2) `sub-agent-delegation.md` adds worktree path translation rule — dispatch prompts must declare the worktree working directory to prevent sub-agents from reading/writing the wrong workspace (3) `e2e-verify.spec.ts` adds adversarial probe mode (`E2E_ADVERSARIAL=1`) with 4 boundary tests: nonexistent product, invalid locale, missing ID, nonexistent category — checks no 5xx, no uncaught JS, non-blank page. Three items deferred to backlog: compact auto-checkpoint, per-agent isolation config, read-only isolation mode

## [1.40.0] - 2026-04-03

- **Sub-agent role system rewrite** — `sub-agent-roles.md` restructured from 11-role registry to dispatch patterns reference. Audit found only 4/11 roles were correctly cited by skills — generic roles (Explorer, Implementer, Analyst, Validator, Scribe) removed as named roles, replaced with copy-paste prompt patterns. Three specialized protocols retained with canonical definitions: QA Challenger/Resolver (multi-round challenge loop), Architect Challenger (estimation review), Critic (pre-PR review with JSON return). Mandatory standards (Completion Envelope, Model Tier Selection, Context Isolation) elevated to top of file. Converge routing table fixed: removed role name labels, replaced with dispatch pattern descriptions, corrected VERIFICATION_PENDING (was mislabeled QA Challenger → now Verification) and REVIEW_STUCK (was mislabeled Scribe/haiku → now sonnet). Based on cross-framework research (OpenAI Swarm, CrewAI, LangGraph, Claude Agent SDK, AutoGen, gstack, GSD) — no production framework uses a dynamic role registry; all define roles inline per-dispatch

## [1.39.0] - 2026-04-03

- **Mockoon CLI runner** — new `scripts/mockoon/` module with `mockoon-runner.sh` supporting start/stop/status, proxy mode (passthrough to SIT) and mock mode (canned responses for E2E). Reads environment JSON files from any directory (framework-agnostic, company provides the data)
- **Unified dependency installer** — `scripts/install-deps.sh` installs all framework tools (Playwright, Mockoon CLI, Chromium browser) with `--check` mode for status reporting. Called by `/init` Step 13.5 and usable after `sync-from-polaris.sh` upgrades
- **E2E Mockoon pre-flight** — `e2e-verify.sh` now detects Mockoon proxy status before running tests, warns when using live backend (results may vary vs stable fixtures)
- **`/init` Step 13.5** — auto-installs framework dependencies during workspace setup

## [1.38.0] - 2026-04-03

- **E2E browser verification via Playwright** — new `scripts/e2e/` module (framework-level, not installed in product repos) with Playwright config, generic page health check spec, and wrapper shell script. Checks 6 dimensions: HTTP status, blank page, hydration errors, uncaught JS errors, critical elements, error page indicators. Supports page type inference from git diff (product/category/destination/home). `verify-completion` v1.6.0 adds Step 1.7 "E2E Browser Verification" — runs through `https://dev.exampleco.com` (Docker nginx proxy), gracefully skips if dev server is not running, blocks on hydration/JS/render failures. Screenshots saved for reports

## [1.37.0] - 2026-04-03

- **`converge` skill v1.0.0** — batch convergence orchestrator that scans all assigned work, classifies 14 gap types (NO_ESTIMATE → MERGE_CONFLICT), proposes a 4-layer prioritized plan (quick wins → implementation → planning → waiting), and auto-routes to 10 downstream skills after user confirmation. Absorbs epic-status as Epic-only alias. 4-phase design: scan → propose → execute → rescan with before/after report
- **`settings.local.json.example` rewrite** — both project-level and user-level examples now include `_doc` blocks explaining the 3-layer permission model, pattern syntax, and recommended split between user-level vs project-level settings. Copied to `_template/` for `/init` reference
- **Pre-commit scope header validation** — `scripts/check-scope-headers.sh` validates that company rule files under `.claude/rules/{company}/` include a `Scope:` header. Supports `--staged` mode for git pre-commit hook and full-scan mode. Wired into `.git/hooks/pre-commit`
- **Cross-session knowledge system validated** — first real usage of `polaris-learnings.sh` (add + query) and `polaris-timeline.sh` (append + query), confirming both scripts work end-to-end with `~/.polaris/projects/work/` storage

## [1.36.0] - 2026-04-02

- **Cross-session knowledge system (Wave 2)** — new `~/.polaris/projects/$SLUG/` infrastructure for persistent cross-session data. Three components: (1) **learnings.jsonl** — typed knowledge entries (pattern/pitfall/preference/architecture/tool) with confidence 1-10, time-based decay (1pt/30d), key+type dedup on write, and preamble injection of top 5 entries at conversation start. Shell script `polaris-learnings.sh` handles add/query/confirm/list with jq (2) **timeline.jsonl** — append-only session event log (10 event types: skill_invoked, pr_opened, commit, checkpoint, etc.) for accurate standup reports and session recovery. Shell script `polaris-timeline.sh` handles append/query/checkpoints with --since filtering (today/Nh/Nd/date) (3) **`/checkpoint` skill** — save/resume/list session state. Captures branch, ticket, todo, recent timeline into a checkpoint event; resume parses and restores context. Integration: `feedback-and-memory.md` item 7 (learning write on non-obvious technical insights), `CLAUDE.md` preamble injection + context recovery step 4, `mechanism-registry.md` 3 new mechanisms, `skill-routing.md` checkpoint route

## [1.35.1] - 2026-04-02

- **fix-pr-review changeset self-check** — fixed timing gap where Step 3b removed inherited changesets but Step 6g only created a new one when changeset-bot warned (bot checked pre-cleanup state, so no warning was issued). Two fixes: (1) Step 3b now self-checks after cleanup — if no changeset with the PR's ticket key remains, creates one immediately (2) Step 6g detection changed from bot-warning-only to diff-scan-first (check `git diff` for missing changeset) with bot warning as fallback

## [1.35.0] - 2026-04-02

- **Learning v3.0 — discovery-first exploration** — fundamental shift from gap-directed to discovery-first approach. Step 1.5 gap pre-scan renamed to "Baseline Scan" — still runs but no longer filters exploration. Steps 2-3 research phase explores broadly without preconceptions, using novelty and unknown signals to drive selective deep-dives instead of known gaps. Deep mode Round 2 dispatches Researchers by "what's different" and "what concept we don't have" rather than lens list gaps. Round 3 compares findings against baseline with 4-type classification: confirms (known gap), new (unknown unknown), refines (our approach but more mature), skip (not applicable). Step 4 synthesis matrix highlights new discoveries first. Works for both framework and product project targets — same principle, different comparison anchors

## [1.34.0] - 2026-04-02

- **Shared references + review-lessons pipeline** — (1) New `references/github-slack-user-mapping.md` — 4-step lookup chain (context match → search username → gh API real name → plaintext fallback), replaces inline logic in review-inbox, review-pr, fix-pr-review (2) New `references/slack-message-format.md` — URL linebreak rule, mrkdwn vs GitHub MD differences, message length limits (3) `standup` adds post-standup review-lessons graduation gate — counts entries across repos, suggests graduation when >= 15 (4) `next` Level 4 adds review-lessons check when no active work context

## [1.33.0] - 2026-04-02

- **Quality pipeline hardening (5 fixes from feedback graduation)** — (1) `feature-branch-pr-gate` now runs `dev-quality-check` before creating feature PR — catches broken merges before CI (2) `dev-quality-check` adds coverage tool pre-flight check (`require.resolve`) instead of reactive error-driven install (3) `git-pr-workflow` Step 6.5 re-runs changeset hygiene after rebase; `fix-pr-review` adds proactive Step 3b changeset cleanup after rebase (not just reactive to changeset-bot) (4) Cascade rebase logic extracted to shared `references/cascade-rebase.md` with documented edge cases and fallback; `git-pr-workflow` and `fix-pr-review` now reference instead of inline (5) `work-on` batch mode validates sub-agent results include PR URL — flags completions without PR as incomplete

## [1.32.0] - 2026-04-02

- **Comprehensive rebase coverage across PR lifecycle** — three gaps closed: (1) `git-pr-workflow` v3.4.0 adds **Step 6.5 Rebase to Latest Base** — explicit rebase after commit/changeset and before opening PR, with cascade rebase for feature branch workflows and automatic conflict handling (2) `feature-branch-pr-gate` adds **Sibling Cascade Rebase** — when any task PR merges, all remaining open sibling task PRs are automatically rebased onto the updated feature branch, keeping diffs clean for reviewers (3) `feature-branch-pr-gate` adds **Feature Branch Rebase** — before creating the feature→develop PR, rebase the feature branch onto latest develop to ensure a clean diff. Together with existing coverage in `check-pr-approvals` (batch rebase) and `fix-pr-review` (pre-fix rebase), all PR states now have automatic rebase handling

## [1.31.1] - 2026-04-02

- **Auto-release on sync** — `sync-to-polaris.sh` now creates a GitHub Release (with CHANGELOG notes) automatically when pushing a new tag. Backfilled 27 missing releases (v1.11.0–v1.31.0) from CHANGELOG entries

## [1.31.0] - 2026-04-02

- **Learning v2.0 — gap-driven deep exploration with dual target** — External mode rewritten with three core improvements: (1) **Gap pre-scan** (Step 1.5) — scans backlog, mechanism-registry, and feedback memories before exploring, so research is directed at known problems (2) **Depth tiers** — Quick/Standard/Deep with auto-escalation for repos with `.claude/` directories; Deep mode uses 3-round multi-agent exploration (structure → targeted deep-dive → cross-reference) (3) **Dual target** — learnings can land in framework (`rules/`, `skills/`, `polaris-backlog.md`) OR product projects (project code, project rules, project CLAUDE.md), with target-specific gap sources and extraction categories. New triggers: "深入學", "deep dive", "像 gstack 那樣學"

## [1.30.0] - 2026-04-02

- **Sub-agent safety & resilience from gstack learning** — three new mechanisms in `sub-agent-delegation.md`: (1) **Safety hooks** — `scripts/safety-gate.sh` PreToolUse hook blocks Edit/Write outside allowed dirs + dangerous Bash patterns (rm -rf, force-push main, DROP TABLE). Configurable via `POLARIS_SAFE_DIRS` env var (2) **Self-regulation scoring** — sub-agents accumulate risk score per modification (+5-15% per event), hard-stop at >35% and report back to Strategist (3) **Pipeline restore points** — `git stash` before implementation in long-running skills (work-on, fix-bug, git-pr-workflow), auto-restore on failure or self-regulation stop

## [1.29.1] - 2026-04-02

- **Quality enforcement from gstack learning** — three mechanisms landed: (1) Re-test-after-fix rule in `git-pr-workflow` Step 3 — stale test results after code fix are invalid, must re-run (2) Verification Iron Rule in `verify-completion` — no completion claims without fresh verification + 5 named anti-rationalization patterns as canaries (3) Decision Classification framework in `sub-agent-delegation` — T1 mechanical / T2 taste / T3 user-challenge with escalation bias toward T2. All three registered in `mechanism-registry.md` Quality Gates section

## [1.29.0] - 2026-04-02

- **Standup unified entry point (v2.0)** — `/standup` is now the single entry point for all end-of-day and standup workflows. New Step 0 auto-triage guard checks `.daily-triage.json` freshness and runs `/my-triage` automatically when stale or missing. All end-of-day triggers ("下班", "收工", "EOD", "wrap up", etc.) now route to standup. `/end-of-day` deprecated to a redirect stub. Routing table consolidated from two rows to one

## [1.28.1] - 2026-04-02

- **Quick-fix batch: 4 backlog items** — `/init` Step 1 ASCII company name validation (reject CJK directory names). `wt-parallel` priority flipped to prefer builtin `isolation: "worktree"` over `wt` CLI. MEMORY.md integrity check added to memory hygiene rules. Scheduled agents / remote triggers documented in README architecture section (EN + zh-TW)

## [1.28.0] - 2026-04-02

- **`/init` v3.1 — 7 gap fixes from live validation** — JIRA smartSelect adds Description column + ticket prefix verification to prevent key confusion (GROW vs GT). Confluence Step 4 now uses CQL auto-detection for SA/SD folders, Standup/Release parent pages, and prompts for additional spaces. Projects Step 7 adds local repo reverse scan (cross-references `gh repo list` with `{base_dir}/` directories, surfaces `[local only]` repos). New Step 10a offers to clone missing repos after config write. Step 10 ensures `default_company` goes to root config only. Step 14 lists all deferred empty fields with fill-in guidance

## [1.27.0] - 2026-04-01

- **Cascade rebase for feature branch workflows** — `rebase-pr-branch.sh` now detects when a task PR's base is a feature branch (not develop/main/master), automatically rebases the feature branch onto its upstream first, then rebases the task branch. Eliminates diff bloat where task PRs show 40+ unrelated files from develop. Requires `ORG` env var. Updated in `check-pr-approvals` Step 2 and `fix-pr-review` Step 3
- **Changeset cleanup for inherited changesets** — `fix-pr-review` Step 6g-2 and `git-pr-workflow` Step 6 now scan for changesets that don't belong to the current PR's ticket key (inherited from dependency branches) and remove them. Ensures each PR has exactly one changeset matching its own ticket

## [1.26.0] - 2026-03-31

- **`learning` Batch mode (5th mode)** — new `/batch learn` flow that scans a repo's merged-PR history, skips already-extracted PRs (Layer 1 dedup by Source URL), batch-extracts review-lessons from the rest, and auto-triggers graduation with Step 2.5 semantic grouping. Triggers: "掃 review", "batch learn", "批次學習", "掃歷史 PR", "補齊 review lessons". Defaults to 3 months, cap 30 PRs/repo
- **Skill routing: batch learn** — learning skill description updated to include Batch mode triggers, no separate route needed (internal mode detection handles it)

## [1.25.1] - 2026-03-31

- **Review-lessons semantic grouping (Step 2.5)** — `review-lessons-graduation` now runs a semantic similarity pass before classification. Entries describing the same underlying coding pattern (even with different wording across PRs) are merged, combining their Source PRs. This unblocks graduation for patterns that were previously stuck at Source=1 per entry despite being validated by multiple PRs
- **Skill routing Anti-Pattern #5** — graduated feedback: fixing PR review comments must use `fix-pr-review` skill, not manual edits. Manual fixes skip comment replies, quality checks, and lesson extraction, breaking the learning pipeline
- **Backlog: review-lessons pipeline gaps** — 4 structural improvements tracked: semantic consolidation (done), periodic graduation trigger outside review skills, retroactive extraction for manually-fixed PRs, cross-pipeline dedup (review-lessons ↔ feedback memories)

## [1.25.0] - 2026-03-31

- **`my-epics` → `my-triage` rename + scope expansion** — skill now scans Epics, Bugs, and orphan Tasks/Stories (no parent). Bug group always displayed first in dashboard. JQL expanded with `issuetype` filter + `parent` post-filter. Step 5+6 merged to prevent triage state write being skipped on conversation interruption
- **`.epic-triage.json` → `.daily-triage.json`** — triage state file renamed, JSON schema updated (`epics` → `items`, added `type` field per item). Standup skill references updated accordingly
- **`/end-of-day` orchestrator skill** — new skill chains `/my-triage` → `/standup` in sequence. Triggers: "下班", "收工", "準備明天的工作", "EOD". Ensures triage state exists before standup TDT generation
- **Routing table updated** — `my-epics` → `my-triage`, added `end-of-day` route

## [1.24.0] - 2026-03-31

- **`get-pr-status.sh` shared script** — new `references/scripts/get-pr-status.sh` provides comprehensive single-PR status checking: CI status, review counts (deduplicated per reviewer), thread-based unresolved inline comment detection, mergeable state, and optional stale approval detection (`--include-stale`). Replaces inline `gh api` calls with consistent thread-aware comment analysis
- **`epic-status` v1.4.0** — Step 4 now delegates per-child-ticket PR status to `get-pr-status.sh` instead of inline `gh pr list` + `gh api .../comments`. Gains thread-based unresolved detection (previously only counted total comments) and reviewer deduplication
- **Backlog cleanup** — closed 2 invalid High items (`review-pr` Slack notification path was misdirected, changeset check belongs in project rules not generic skill). Split `get-pr-status.sh` Phase 2 migration into separate tracked item

## [1.23.1] - 2026-03-31

- **Workflow-guide mermaid diagrams updated** — removed deleted `sasd-review` from both diagrams; added `next`, `my-epics`, `epic-status`, `docs-sync`, `worklog-report` to Skill Orchestration diagram with proper edges (next→orchestrators, epic-status→gap routing, standup↔my-epics). Both EN and zh-TW files synced
- **docs-sync now covers mermaid diagrams** — Step 1 scans mermaid node IDs against skill catalog to detect drift; Step 2c includes explicit mermaid diagram update guidance (nodes, edges, class assignments, connectivity check prose)

## [1.23.0] - 2026-03-31

- **`/my-epics` triage skill** — new skill for personal Epic backlog triage. Queries JIRA for all assigned active Epics, validates actual status (catches board/status desync), sorts by priority + created date, checks GitHub PR progress for In Development items, and outputs a prioritized dashboard. Writes `.epic-triage.json` state file for standup integration
- **Standup TDT triage integration** — standup's TDT section now reads `.epic-triage.json` when available, sorting today's tasks by triage rank and showing progress traffic lights (🟢 ahead / ⚪ normal / 🔴 stuck) by comparing triage-time progress vs current state

## [1.22.2] - 2026-03-31

- **`/next` auto-continuation skill** — zero-input context router that reads todo list, git branch, git status, JIRA ticket state, and GitHub PR status to auto-determine the correct next action. 4-level decision tree (todo → git branch → JIRA status → PR status) with direct routing to existing skills. Trigger: "下一步", "next", "繼續", "continue"
- **work-on trigger cleanup** — removed "下一步" and "繼續" from work-on triggers (now handled by `/next`), added key distinction note

## [1.22.1] - 2026-03-31

- **`check-feature-pr.sh` shared script** — new `references/scripts/check-feature-pr.sh` consolidates feature PR status checking (task PR merge count, feature PR existence, review/CI/conflict status) into a single script. `feature-branch-pr-gate.md` Steps 2-4 and `epic-status` Step 3b now delegate to this script instead of inline gh commands
- **`references/scripts/` directory** — established shared scripts directory for cross-skill deterministic logic

## [1.22.0] - 2026-03-31

- **Skill logic consolidation** — extracted 7 shared reference docs from duplicated logic across 12 skills: `slack-pr-input.md` (Slack URL → PR URL parsing), `pr-input-resolver.md` (PR URL/number + local path resolution), `jira-story-points.md` (Story Points field ID query + write-back verification), `jira-subtask-creation.md` (batch create + estimate loop), `stale-approval-detection.md` (stale approval rule), `tdd-smart-judgment.md` (TDD file-level decision), `confluence-page-update.md` (search → version check → append flow)
- **Inline deduplication** — `feature-branch-pr-gate.md` inline copies in check-pr-approvals and git-pr-workflow replaced with reference pointers. sub-agent-roles Critic spec in git-pr-workflow annotated with cross-reference
- **epic-status v1.1.0** — Phase 1 now scans feature PR review/CI status (Step 3b) and detects unresolved inline comments (Step 4a-2, catches Copilot review and COMMENTED-state reviews). Phase 2 auto-routes gaps without user confirmation
- **Cleanup** — removed deprecated `exampleco/ai-env.sh` (replaced by polaris-sync.sh)

## [1.21.0] - 2026-03-31

- **`epic-status` skill** — new skill for Epic progress tracking and gap closing. Phase 1 scans all child tickets' JIRA + GitHub status (branch/PR/CI/review) into a status matrix with completion percentages. Phase 2 routes gaps to existing skills (work-on, fix-pr-review, check-pr-approvals, verify-completion) with user confirmation
- **Feature Branch PR Gate** — new cross-cutting mechanism (`references/feature-branch-pr-gate.md`) that auto-creates feature branch → develop PRs when all task PRs are merged. Integrated into `epic-status`, `git-pr-workflow`, and `check-pr-approvals` — "discover it's ready, create it" philosophy instead of manual tracking
- **Slack channel routing** — epic-status and other skills now read `slack.channels.pr_review` for team-facing messages (review requests, PR updates) vs `slack.channels.ai_notifications` for self-only notifications. Prevents misdirected review requests
- **Skill routing update** — added epic-status triggers ("epic 進度", "離 merge 還多遠", "還差什麼", "補全")

## [1.20.0] - 2026-03-31

- **Sub-agent Completion Envelope** — all sub-agent roles now require a standard 3-line return header (`Status / Artifacts / Summary`) so orchestrators can programmatically determine success/failure without parsing prose. Added to `sub-agent-roles.md` and tracked in mechanism registry
- **Complexity Tier routing** — new section in `skill-routing.md` defines Fast / Standard / Full tiers based on task size. Prevents small tasks from incurring full-workflow overhead and large tasks from skipping planning
- **Goal-Backward Verification** — new Step 1.6 in `verify-completion` checks 4 layers (Exists → Substantive → Wired → Flowing) before running detailed test items. Catches "all tasks done but goal not met" situations like created-but-never-imported components
- **Runtime Context Awareness** — new §5 in `context-monitoring.md` with proactive 20-tool-call checkpoint and interim mitigation for context rot in long sessions. Hook-based runtime monitoring tracked in backlog
- **Mechanism registry updates** — added `subagent-completion-envelope` (Medium) and `proactive-context-check-at-20` (Medium) canary signals
- **Backlog: 3 future items** — context monitor PostToolUse hook, `/next` auto-continuation skill, wave-based parallel execution for large epics

> Inspired by [gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done) — context engineering patterns, goal-backward verification, and scale laddering concepts adapted for Polaris

## [1.19.0] - 2026-03-31

- **Bilingual docs (zh-TW)** — full Traditional Chinese README (`README.zh-TW.md`), workflow guide, and PM setup checklist. All docs have `English | 中文` language switcher at top
- **Daily learning scanner → Slack delivery** — scanner now sends article recommendations to Slack instead of committing to git. Eliminates git history pollution from transient queue data
- **Learning Setup mode** — new `/learning setup` (or `設定學習`) configures the daily scanner: auto-detects tech stack and repos from workspace config, asks for Slack channel and custom topics, assembles and creates RemoteTrigger. `/init` Step 13 delegates to this mode
- **`daily-learning-scan-spec.md` cleaned** — now a pure framework template (no instance-specific tech stack, repos, or channel IDs). All instance data lives in the trigger prompt, assembled by Setup mode
- **`docs-sync` skill** — generic version that detects skill/workflow changes and updates all bilingual documentation files (README, workflow-guide, chinese-triggers, quick-start). Replaces the old company-specific Confluence sync
- **Sync script updates** — `sync-to-polaris.sh` now syncs `docs/` directory and `README.zh-TW.md` to the template repo

## [1.18.0] - 2026-03-30

- **Three Pillars documentation rewrite** — restructured README and docs around three narrative pillars: Development Assistance (輔助開發), Self-Learning (自我學習), and Daily Operations (日常紀錄). Replaces the old skill-category table and moves self-evolution into Pillar 2 as the framework differentiator
- **Quick Start simplification** — merged 4 setup steps into 3, added post-`/init` folder structure example so new users see what they'll get before starting. Based on real user feedback about unclear workspace concept
- **Chinese docs sync** — `quick-start-zh.md` mirrors the three-pillar structure and simplified setup flow
- **Pillar tags in chinese-triggers.md** — each skill category header now shows which pillar it belongs to

## [1.17.0] - 2026-03-30

- **`/init` Step 13: Daily Learning Scanner** — new opt-in step at end of init wizard. Explains article selection logic (tech stack from Step 7 + AI/Agent news + architecture), lets user customize preferences (add topics, adjust volume), and auto-creates RemoteTrigger schedule if accepted. Users who decline can enable later via `/schedule`

## [1.16.0] - 2026-03-30

- **Feedback pre-write dedup** — before creating a feedback memory, scan existing entries for semantic overlap; merge if found (incrementing `trigger_count`) instead of creating duplicates. Post-merge check triggers graduation immediately if `trigger_count >= 3`
- **Dual-layer review-lesson dedup** — `review-pr` and `fix-pr-review` lesson extraction now checks both existing review-lessons AND main `rules/*.md` before writing, matching the dedup quality of `learning/PR` mode
- **Framework-level lesson tagging** — lesson extraction tags entries with `[framework]` when the pattern is about skill design, delegation, rules mechanisms, or memory management (not project coding patterns)
- **Review-lessons-graduation framework routing** — new § 3.5 routes `[framework]`-tagged lessons to workspace `rules/` instead of project `rules/`, closing the gap where framework-level learnings from code review had no path to framework rules
- **Mechanism registry** — added `feedback-pre-write-dedup` (High) to enforce dedup before feedback creation

## [1.15.0] - 2026-03-30

- **Framework Self-Iteration rule** — new `rules/framework-iteration.md` formalizing three iteration cadences (Micro/Meso/Macro), repositioning Challenger Audit as a milestone-only self-check (pre-release, not daily), and adding Framework Experience collection for positive signals
- **Framework Experience collection** — new `type: framework-experience` memory type captures what works (not just pain points): validated skill flows, successful graduations, cross-company pattern reuse. At most 1 per task, no graduation — observations, not corrections
- **Validated Pattern Promotion** — when >= 3 framework-experience memories describe the same pattern, surface as a candidate for rule rationale during organize-memory
- **Version Bump Reminder** — post-task reflection now reminds the user to consider a version bump when `rules/` or `skills/` files were modified
- **Mechanism registry expanded** — added `challenger-milestone-only` (High) and `framework-exp-once-per-task` (Low) to prevent Challenger overuse and memory pollution

## [1.14.0] - 2026-03-30

- **Challenger personas for daily workflows** — two new must-respond challenger sub-agents that review quality before user confirmation:
  - **🏛️ Architect Challenger** — challenges estimation results (complexity gaps, blind spots, scope misses) in `jira-estimation` Step 8.4a
  - **🔍 QA Challenger** — challenges test plans (missing negative cases, regression risks, boundary conditions) in `work-on` Step 5f
- **Must-respond protocol** — challenger findings are not advisory; every ⚠️ must be explicitly accepted or rejected (with reason) before proceeding
- Persona definitions added to `skills/references/sub-agent-roles.md`

## [1.13.0] - 2026-03-30

- **`/validate-mechanisms` skill** — Layer 3 of mechanism protection: periodic smoke test scanning 9 static canary signals (scope headers, bash patterns, routing table completeness, memory isolation, feedback frontmatter, hardcoded paths, ghost references)
- **Chinese trigger reference** — new `docs/chinese-triggers.md` with all skills grouped by category, Chinese/English trigger phrases, and disambiguation guides
- **L3 project CLAUDE.md template** — new `_template/project-claude-md.example` showing what belongs at project level (tech stack, conventions, testing, dev commands)
- **Default company config** — `default_company` field in workspace-config.yaml for single-client fallback; integrated into `use-company` skill and `multi-company-isolation` rule
- **Routing table updated** — added `validate-mechanisms` and `validate-isolation` to skill-routing.md

## [1.12.0] - 2026-03-30

- **Developer Workflow Guide** — new `docs/workflow-guide.md` extracted from company-specific RD workflow into a generic framework reference. Covers: ticket lifecycle (mermaid), AC closure gates, skill orchestration graph, Feature/Bug/Hotfix paths, code review pipeline, and continuous learning
- **README: Workflow orchestration section** — added link to workflow guide under "How it works"
- **sync-to-polaris.sh** — automated instance → template sync with `--push` flag (GitHub account switch for dual-account setups)

## [1.11.0] - 2026-03-30

**Drift Audit & Mechanism Registry** — stability pass after rapid v1.7–v1.10 iteration

- **Mechanism Registry** — new `rules/mechanism-registry.md` with 20 behavioral mechanisms, canary signals, and drift-risk ratings; post-task audit section added to `feedback-and-memory.md` for automatic compliance checks
- **Drift Audit fixes (Critical)** — removed phantom `dev-guide` skill references (4 files), fixed CLAUDE.md routing path (`rules/{company}/` → `rules/`), fixed graduation table paths in feedback-and-memory.md, added missing `name:` to use-company frontmatter
- **Skill genericization pass 2** — replaced `~/work/` hardcodes with `{base_dir}` across 16 skill files (65 occurrences); removed company-specific refs (b2c-web, member-ci, GT-XXX, TICKET-14407) from 5 generic skills
- **Memory hygiene** — added `company: exampleco` tag to 19 company-scoped memories; deleted 3 redundant/graduated memories; fixed stale content in 4 memories (Commander→Strategist, wrong paths)
- **CLAUDE.md Cross-Project Rules** — separated universal rules from company-specific rules set up via `/init`
- **sub-agent-delegation.md** — removed hardcoded "(Opus)" model assumption

## [1.10.0] - 2026-03-30

- **Skill description trim** — top 6 bloated skills (learning, refinement, review-inbox, fix-pr-review, work-on, check-pr-approvals) reduced from avg ~1300 to ~400 chars, saving ~4k tokens per conversation
- **fix-pr-review routing fix** — added colloquial Chinese triggers: "修 PR", "PR 有 review", "處理 review" so natural-language requests route correctly
- **exampleco workspace-config** — added `bug_value`/`maintain_value` aliases under `requirement_source` for generic skill compatibility

## [1.9.2] - 2026-03-30

- **Hook matcher simplified** — uses Claude Code's `if: "Bash(git push*)"` field instead of firing on every Bash call + grep short-circuit; removes outdated "no command-level matchers" comment
- **PM Setup Checklist** — new `docs/pm-setup-checklist.md` with zero-terminal-commands handoff: what PMs need, what to ask their developer, daily commands, troubleshooting

## [1.9.1] - 2026-03-30

Challenger audit v1.9.0 quick-fixes (6-persona, 16 🔴 / 37 🟡 / 18 🟢):

- **Removed leaked company name** from `.gitignore` — `exampleco/` replaced with generic comment
- **Chinese guide link at README top** — visible in first 5 lines, not buried in Quick Start
- **Multi-company in "Who is this for"** — freelancers/multi-client listed as a target audience
- **`/commands` note moved to Step 3** — before `/init`, not after Step 4
- **Post-/init validation step** — "try `work on PROJ-123` to verify setup" added to Quick Start
- **PM section: removed PR tracking** — dev-only operation removed from PM workflow
- **PM section: Max plan requirement** — cost callout added at top of PM workflow
- **PM section: troubleshooting tip** — "check MCP connections" one-liner added
- **YDY/TDT/BOS expanded** — acronym explained on first use in both README and Chinese guide
- **Refinement description clarified** — "Polaris reads codebase for you" note for PM users
- **Chinese guide end note** — links to English README for developer content
- **`/validate-isolation` in README** — linked in multi-company diagnostics list and post-setup guidance
- **Same-prefix resolution** — documented in multi-company-isolation.md routing rules
- **Company recovery prompt** — specific prompt format for post-compression company re-confirmation
- **13 new backlog items** from v1.9.0 audit findings (skill genericization, hook matcher, PM setup, etc.)

## [1.9.0] - 2026-03-30

- **Chinese Quick Start guide** — full `docs/quick-start-zh.md` covering prerequisites, setup steps, skill examples, and PM workflow in 中文; linked from README Quick Start section
- **PM & Scrum workflow narrative** — new README section mapping the complete sprint lifecycle to Polaris commands: sprint planning → standup → refinement → breakdown → worklog report, with bilingual trigger phrases and expected outputs

## [1.8.0] - 2026-03-30

- **Memory isolation enforcement** — hard-skip rule for mismatched `company:` field (skip silently, no cross-contamination), new hygiene check #6 for untagged company-specific memories, MEMORY.md index now supports `[company]` prefix for visual scanning
- **Company context persistence** — active company context now survives context compression: saved in milestone summaries, restored from todo list, explicit re-confirmation after compression events
- **`/validate-isolation` diagnostic skill** — scans L2 rules for missing scope headers, memory files for missing `company:` fields, cross-company directive conflicts, and MEMORY.md index format issues; outputs structured report with ✅/🟡/🔴 severity
- **Cross-reference in multi-company-isolation.md** — `/validate-isolation` now documented as the recommended diagnostic tool

## [1.7.0] - 2026-03-30

- **Memory company isolation** — memories now support `company:` frontmatter field to prevent cross-company rule bleed
- **`/init` scaffolds L2 rules** — new companies automatically get `.claude/rules/{company}/` with scoped copies of rule templates
- **`/use-company` skill** — explicitly set active company context for a conversation, complementing `/which-company` diagnostics
- **`/init` repo path flexibility** — no longer assumes `~/work/` as base dir; uses actual workspace root path
- **README bilingual integration** — Quick Start examples now show English/中文 side-by-side instead of separate blocks
- **CJK branch naming guard** — empty or invalid translations from CJK titles fall back to ticket key only (`task/PROJ-123`)
- **SA/SD Chinese alias update** — added 「寫 SA」「出 SA/SD」triggers, deprioritized misleading 「實作評估」
- **Stale backlog cleanup** — `review-pr` hardcoded paths already resolved in earlier genericization; item closed

## [1.6.0] - 2026-03-30

- **Excluded `polaris-backlog.md` from template** — framework backlog is maintainer-only, no longer confuses new users
- **Added "What not to touch" guide** in README — clarifies which files are framework internals vs. safe to customize
- **Added "Upgrading" section** in README — documents `sync-from-polaris.sh` for pulling framework updates
- **Moved Zhang Liang inspiration** to "About the name" section — frees hero section for practical info
- **Added Claude Code plan/tier note** — specifies that sub-agent features need Max plan or API access
- **Added clone path guidance** — warns against `~/work` default to avoid conflicts
- **Pre-push hook first-time bypass** — first push skips the quality gate with an informational message instead of blocking
- **CHANGELOG rewritten** — user-facing release notes style, concise per-version summaries
- **Sync script fixed** — L2 rules now sync from `_template/rule-examples/` (v1.5.0+ path)
- **Removed obsolete skills** (`auto-improve`, `check-pr-approvals`, `dev-guide`)
- **Removed `ONBOARDING.md`** — was already absorbed into README in v1.1.0

## [1.5.0] - 2026-03-30

- Added "What is Claude Code?" explainer for users new to the tool
- Added MCP install instructions with concrete `claude mcp add` example
- Added PM/Scrum workflow showcase (`standup`, `sprint-planning`)
- Added "Start here" role-based table pointing each role to their first command
- Added full bilingual skill routing (English + 中文)
- Moved rule examples from `.claude/rules/_example/` to `_template/rule-examples/` — no longer auto-loaded

## [1.4.0] - 2026-03-30

- Added multi-company isolation with scoped rules and `/which-company` diagnostic
- Added "Who is this for?" section and tiered prerequisites (Everyone / Dev / Optional)
- Added Chinese Quick Start examples (「做 PROJ-123」「修 bug」「估點」)
- Workspace config (`workspace-config.yaml`) is now gitignored — copy from template

## [1.3.0] - 2026-03-30

- All skills and rules genericized — no company-specific hardcodes remain
- L2 example rules translated to English
- Template ready for public distribution

## [1.2.0] - 2026-03-30

- Skill routing rewritten English-first with Chinese aliases
- Company-specific JIRA field IDs, URLs, and credentials removed from rules
- 12 skill trigger phrases updated

## [1.1.0] - 2026-03-30

- README rewritten: clear positioning, prerequisites, Quick Start walkthrough
- ONBOARDING.md absorbed into README (single entry point)
- MCP server dependencies documented

## [1.0.0] - 2026-03-30

- Identity established: Polaris, inspired by Zhang Liang (張良)
- Persona: Commander to Strategist — "listen first, then orchestrate"

## [0.9.0] - 2026-03-29

- `/init` v3: smartSelect interaction, AI repo detection, audit trail
- `learning` skill: external resource attribution
- Added VERSION file, CHANGELOG, and improvement backlog

## [0.8.0] - 2026-03-29

- Bidirectional sync scripts (`sync-from-upstream.sh`, `sync-from-polaris.sh`)
- Context monitoring and feedback auto-evolution rules
- CLAUDE.md genericized — company content moved to `rules/{company}/`

## [0.7.0] - 2026-03-29

- Two-layer config (root + company `workspace-config.yaml`)
- `/init` wizard v2 for interactive company setup
- All skills migrated to config-driven resolution

## [0.6.0] - 2026-03-28

- Template repo extracted from working instance
- Genericize pipeline (sed scripts strip company references)

## [0.5.0] - 2026-03-28

- Three-layer architecture (Workspace / Company / Project)
- Config consolidation into `workspace-config.yaml`

## [Pre-0.5]

Skills, rules, and references developed organically during daily usage in a production engineering team. No formal versioning.
