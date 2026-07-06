---
name: auto-pass
description: >
  Canonical main-chain orchestrator for locked/current refinement-owned sources
  (DP-backed or JIRA Epic-backed). It routes a source through breakdown,
  engineering, and verify-AC without taking over their mutation authority.
  Trigger: "auto-pass {KEY}", "快速通關 {KEY}", "完整流程 {KEY}" when the source
  is LOCKED and artifacts are current. `{KEY}` 可以是 `DP-NNN` 或 JIRA Epic key。
metadata:
  author: Polaris
  version: 0.3.0
---

# Auto-pass

`auto-pass` 是 locked/current refinement-owned source 的主鏈 orchestrator。runner-first
contract：本 SKILL 只負責 dispatch boundary 與 terminal contract；所有 schema、execution
loop、friction、report 細節都 pointer 到 canonical references；runtime 行為由
`scripts/auto-pass-runner.sh` 與其呼叫的 deterministic validators 決定。

`auto-pass` 不改 code、不寫 task.md、不建 generic GitHub PR、不判 AC PASS/FAIL，也不執行
merge / release / deploy / production write。

## Source Gate

`auto-pass` 接受 `spec-source-resolver.md` 解析出的唯一 refinement-owned source（DP-backed
落在 `design-plans/DP-NNN-*/`，JIRA Epic-backed 落在 `companies/{company}/{EPIC}/`）。
runner / probe 共同確認：唯一 container、`index.md` `status=LOCKED`、`refinement.md` /
`refinement.json` current、ledger `source.refinement_hash` 對齊。任何一項不符回 upstream
owning skill；兩種 source type 共用同一條 gate，無特殊豁免。JIRA Epic-backed source 首次
dispatch 必須先取得 JIRA status sync consent；prompt、marker、TTL fallback 以
`.claude/skills/references/auto-pass-ledger.md` § JIRA Status Consent 為準。

## Ledger Contract (pointer)

ledger 路徑：`{source_container}/artifacts/auto-pass/YYYYMMDD-HHMMSS-ledger.json`。schema、
consent enum、`consent_excludes`、terminal enum、resume 欄位、JIRA status consent schema、
friction log schema 皆以 `.claude/skills/references/auto-pass-ledger.md` 為 canonical
source，由 `scripts/validate-auto-pass-ledger.sh` enforce。durable write 一律走
`scripts/write-producer-owned-artifact.sh`（token / path / atomic-rename / validator
rollback 細節以 writer 與 `scripts/lib/evidence-producers.json` 為準）。啟動 `auto-pass`
代表使用者同意本 source 內的重新評估、重新拆分與 task repair；該同意只能透過 ledger
artifact 傳給下游，不可用 conversation memory 代替。

## Runner Command

`scripts/auto-pass-runner.sh` 是主鏈 deterministic next-action authority。orchestrator
**只**依 runner JSON（`schema_version=1`，含 `stage`、`status`、`terminal_status`、
`next_action`、`next_skill`、`next_work_item_id`、`evidence_path`）決定下一步，不讀 inner
skill 自然語言 final answer 補判斷。

```bash
# Source gate
bash scripts/auto-pass-runner.sh --source-id {SOURCE_ID} --stage source

# Stage probe
bash scripts/auto-pass-runner.sh \
  --source-id {SOURCE_ID} \
  --stage breakdown|engineering|verify-AC \
  --work-item-id {SOURCE_ID}-T1 \
  [--head-sha {sha}] [--ledger /abs/path/to/ledger.json]
```

`status=UNKNOWN` 或 missing marker 一律 terminal `blocked_by_gate_failure`。runner 與
`scripts/auto-pass-probe.sh` 的 parity 由
`scripts/selftests/auto-pass-runner-probe-parity-selftest.sh` 守住。

## Dispatch Boundary

`auto-pass` 只 dispatch 以下 owning skills：

1. `breakdown` — 產生或修正本 source 的 work orders。
2. `engineering` — 依 authoritative task.md 施工、驗證並建立 non-draft workspace PR。
   涵蓋兩種 mode：**first-cut**（completion-gate marker 尚未 PASS 的初次施工）與
   **revision**（completion-gate marker PASS 後，open PR 的 shared classifier 回
   `needs_code_changes` actionable review signals，runner emit `ROUTE_BACK_REVISION`）。
   兩種 mode 都由同一個 `engineering` skill 契約承載；revision 的 R6 comment reply 是
   `engineering` skill-contracted write（非 auto-pass `consent_excludes`）。review-revision
   loop 的 trigger 範圍、head rebind、`engineering_revision_rounds` counter / cap 與 fail-closed
   行為以 `.claude/skills/references/auto-pass-execution-flow.md` § Review-Revision Loop 為準。
3. `verify-AC` — 驗收 V work order 並產生 current verification disposition。
4. `refinement`（amendment mode only）— `{source_container}/refinement-inbox/*.md` 出現或
   verify-AC 回 `spec_issue` 時，consume inbox、把 implementation detail 微調寫回
   refinement artifact，counter +=1 後 loop 回 breakdown。Amendment 不重做 Phase 0/1/2
   discovery、不改 LOCKED scope（由 `validate-refinement-locked-scope.sh` 把關）。

inner skill mandatory gates 保持原樣。Planner-owned gap、scope escalation、AC spec issue、
consent 外 external write、blocked conflict、unknown probe 都必須回 owning skill 或明確
pause / blocked。
當 product-flow engineering 發現需要 framework-owned diff 才能繼續時，`auto-pass` 不把該
diff 吸收到產品 PR；必須讓 engineering 產出 DP-backed framework workstream seed/handoff
或更新既有 DP-backed framework source，再回主鏈。產品 PR 內的 framework-owned diff 是
`blocked_by_gate_failure`，不是可人工略過的 convenience patch。

dispatch envelope 必帶：

- `AUTO_PASS_LEDGER_PATH=/abs/path/to/ledger.json`（breakdown / engineering / verify-AC）。
- `worktree_resolution`（engineering / verify-AC 任務階段），由
  `scripts/resolve-task-worktree.sh --source-id ... --work-item-id ... --format json`
  解析。envelope schema、`FOUND` / `NONE` / `AMBIGUOUS` 行為與下列邊界以
  `.claude/skills/references/auto-pass-execution-flow.md` § Dispatch Envelope Worktree
  Resolution 為準：
  - engineering first-cut pre-setup 時 `NONE` 是正常初始狀態，orchestrator dispatch
    `engineering`，由 `engineering-branch-setup.sh` 建 fresh branch/worktree。
  - post-setup / resume / verify-AC 階段若仍 `NONE`，terminal `blocked_by_missing_worktree`。

## Execution Loop (pointer)

orchestrator 採 **runner-first** 模型：每個 stage transition 只讀 runner JSON 作為
next-action authority，不再重跑 probe / ledger parse / filesystem walk。stage 順序、
internal probe wrapping、recoverable HALT continue、loop cap、pause / terminal fixed-point、
closeout chain 以 `.claude/skills/references/auto-pass-execution-flow.md` 為 canonical
source。簡述：`next_action=dispatch` → 下一階段；`terminal` → 寫 report 進 closeout；
`refinement_amendment` → amendment loop；`blocked` → terminal blocked。Recoverable HALT 必須繼續 dispatch，
並自動 loop dispatch；只有 session pressure 才能寫 `pause.kind=session_handoff`。
`next_action=resume`（active `session_handoff` pause）時，orchestrator 以 deterministic
sequence 釋放 pause：`scripts/validate-auto-pass-resume.sh` → `scripts/auto-pass-consume-resume.sh`
（唯一 sanctioned writer，清 `pause=null` + 蓋 `resumed_at`）→ re-probe runner，**不得**手動
改 ledger 清 pause（見 `.claude/skills/references/auto-pass-execution-flow.md`
§ Automatic Pause-Release Sequence）。

## Full Source Completion Invariant

`complete` 是 source-level，不是 task-local。task-local closeout（單一 task、blocker hotfix、
PR、version tag、framework-release closeout 或 local-extension deliverable）只是 stage
evidence；sibling tasks、V tasks、verification disposition、source status、parent lifecycle
closeout 仍未完成時不得宣告 source complete。terminal `complete` 最低條件以
`.claude/skills/references/auto-pass-execution-flow.md` § Terminal Complete Sequence 為準。
terminal complete report 送出前，parent source 必須已經由
`scripts/mark-spec-implemented.sh {SOURCE_ID} --auto-archive` 推進至 `IMPLEMENTED` /
archive；`scripts/validate-auto-pass-report.sh` 會對 active `LOCKED` parent + complete report
fail-stop（`POLARIS_AUTO_PASS_TERMINAL_PARENT_NOT_ARCHIVED`）。

terminal `complete` 也必須保留 delivery 可檢視性：required implementation work items
必須有 non-draft workspace PR，且 completion gate / report 能列出 PR URL 與遠端可見的
evidence publication URL 或 marker。合法 marker 由 evidence-producing skill 寫入：
`polaris-evidence-publication:v1`、`polaris-verify-report:v1` 或
`polaris-jira-evidence:v1`。`auto-pass` 只能透過 runner / probe 檢查 current marker 與
report state；不得直接呼叫 GitHub / JIRA API、`publish-delivery-evidence.sh` 或
`publish-jira-evidence.mjs` 來發表佐證。
當 PR state / terminal report 帶有 auto-pass PR ownership payload 時，必須通過
`scripts/auto-pass-pr-ownership-gate.sh`：`isDraft=false`、publisher provenance 為
`polaris-pr-create.sh`、engineering completion marker PASS、base freshness current。generic
GitHub PR、plugin publisher、draft PR 或缺 completion marker 的 PR 只能被拒收為
`blocked_by_gate_failure`，不得被 report 吸收成 source complete。

## Friction Log Capture (pointer)

orchestration 過程中的繞道、deterministic gap、手動補位、env bypass、validator/contract
衝突等訊號必須寫入 ledger `friction_log[]`，不可只在口頭報告交代。canonical contract 在
`.claude/skills/references/friction-capture-contract.md`：emit stage / kind enum、唯一
writer path（`scripts/append-auto-pass-friction.sh`）、deterministic trigger 的內建 call
site 與 NOOP boundary 都以該 reference 為準。

orchestrator 只主動呼叫 `context_pressure` 這個 LLM-judgment trigger（寫 pause artifact
前）；其他 trigger 由 helper / hook / probe / counter 自動 emit。terminal report 的
`friction_log_summary` 由 `scripts/validate-auto-pass-report.sh` 從 ledger 重算，不可手寫。

## Skill Workflow Boundary Gate (pointer)

每段 cross-skill transition（`refinement -> breakdown -> engineering -> verify-AC` 或回到
`refinement (amendment)`）必須以 deterministic boundary gate 收尾。dispatch 前
`scripts/skill-workflow-boundary-gate.sh --skill {next_skill} --start ...` 建 baseline；
inner skill 結束後 `--check` 驗證上一段只動到自己 owning scope。exit 1 +
`POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:{skill}` 視為 deterministic gate failure，
ledger 寫 `gate_failure` friction、terminal `blocked_by_gate_failure`。
`POLARIS_LANGUAGE_POLICY_BYPASS` / `POLARIS_SKILL_BOUNDARY_BYPASS` 在此 gate 無效。

## Routing Policy (pointer)

Full development workflow intent 的 source-state matrix（`refinement` / `auto-pass` /
`framework-release` 邊界、resume 規則、DP-backed 與 JIRA Epic-backed 共用 routing）由
`.claude/rules/skill-routing.md` § Full Development Workflow Route Policy 與
`.claude/skills/references/auto-pass-execution-flow.md` 共同維護。`auto-pass` 只接
locked/current refinement-owned source；其他 case 回 upstream owning skill。當 framework
workspace PR opened + verification stale 時，`auto-pass {KEY}` refresh verify-AC，不重跑 breakdown。

## Legal Terminal

`auto-pass` 合法 terminal：

- `complete`
- `loop_cap_reached`
- `blocked_by_gate_failure`
- `paused_for_user_external_write`
- `user_aborted`

`session_handoff` 與 `paused_for_refinement` 是 ledger `pause.kind` 的 non-terminal
狀態，不是 `terminal_status`；resume / amendment loop 以 runner JSON `next_action`
處理。

terminal priority 與觸發條件以
`.claude/skills/references/auto-pass-execution-flow.md` § Terminal Priority 為準。

## Forbidden Actions

`auto-pass` **不得**：

- 直接改 code、寫 task.md / refinement.md / refinement.json。
- 建 generic GitHub PR、執行 merge、tag、deploy、production write。
- 讀 inner skill 自然語言 final answer 補足 missing marker；missing/UNKNOWN 永遠 blocked。
- recoverable HALT 時停下交還 user（必須繼續 dispatch 至 deterministic terminal）。
- 把 framework workspace merge / sync-to-polaris / tag / GitHub release 寫成 auto-pass
  已執行（`framework-release` 才是 framework workspace self-iteration 的 local-extension tail）。
- 在 amendment mode 改 LOCKED scope（Goal / Background / Decisions / Scope / AC）。

## Final Report (pointer)

terminal 必須產生 durable report：

```text
{source_container}/artifacts/auto-pass/YYYYMMDD-HHMMSS-report.json
```

report schema、follow-up DP seed threshold、`overlap_disposition` 允許值、
`friction_log_summary` 聚合規則、`framework_release_tail` 結構皆以
`.claude/skills/references/auto-pass-report.md` 為 canonical source，由
`scripts/validate-auto-pass-report.sh` 驗證。`complete` 且無 issue / blocker / manual /
follow-up / sunset 時不需 DP seed；其他 terminal 或含 sunset candidate 必須附 follow-up
DP seed reference。
