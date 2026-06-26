# Cross-LLM Skill Source Of Truth

## Core Rule

共享 Polaris skills 只能在 `.claude/skills/` 編輯。

- `.claude/skills/` 是共享 skill definitions 與 shared references 的 single source of truth。
- `.agents/skills/` 是提供 Codex compatibility 的 runtime-facing mirror path。
- 不得把 `.agents/skills/` 視為獨立 authoring surface。

## Required Mirror Mode

`.agents/skills` 必須是指向 `../.claude/skills` 的 symlink。

這能避免 Claude-facing 與 Codex-facing path 之間出現 copy drift。若 mirror 是實體複製目錄，workspace
就處於降級相容狀態；release 或 framework validation 通過前必須修復。

## Editing Rules

- 更新 shared skill 時，編輯 `.claude/skills/{skill}/SKILL.md`。
- 更新 skills 消費的 shared reference 時，編輯 `.claude/skills/references/*`。
- Company-specific skills 維持在 `.claude/skills/{company}/`。
- Maintainer-only skills 維持在 `.claude/skills/`，並保留既有 scope controls。
- Runtime-specific adapter examples 必須指回 `.claude/skills/references/model-tier-policy.md`；不得在 `.agents/skills`、generated prompts 或 runtime notes 複製具體 model policy。

## Verification

宣告 cross-LLM parity healthy 前：

1. 確認 `.agents/skills` 是指向 `../.claude/skills` 的 symlink。
2. 執行 `scripts/validate-model-tier-policy.sh`。
3. 確認 Codex rule transpile 已同步。
4. 確認 parity checks PASS。

## Dual-Platform Parity Mandate（D43, constitutional）

涉及 Polaris 的開發，**必須做到 Claude / Codex 雙平台全機制相容**。這是 framework
constitutional contract，不是 advisory prose：任何 `.claude/hooks/*.sh` hook，只要被
有效 Claude project hook source（`.claude/settings.json` 與存在時的
`.claude/settings.local.json`，跨所有 active hook event family）啟用，就必須在
`.claude/rules/mechanism-registry.md` 的 **Cross-LLM Hook Parity Registry** 表登記，且其
Codex enforcement 不得退化成 rules prose self-discipline：

- **每支 active hook** 必須 (a) 在 registry 標 `runtime=claude-code-only` +
  runtime-neutral `fallback_script`，或 `runtime=portable` + documented Codex adapter；
  (b) hook script 本身可機器驗證地委派 declared `fallback_script`（只做 payload
  normalization / mode selection，不保留與 fallback 分離的 runtime-specific allow/deny
  判斷）；(c) `codex_invocation_point` 為 `codex_hook` / `guarded_wrapper` / `pr_gate`
  之一（`manual` / `skill_prose` / 空值都不是等價機制）；(d) 具 `adapter_selftest` 與
  payload_contract / golden_fixture，且 Claude 與 Codex payload normalize 後的
  decision-field digest 與 fallback PASS/FAIL 完全一致。
- **Active hook command 必須 canonicalize** 為單一 `.claude/hooks/*.sh` invocation；
  inline shell、`bash -lc`、chained command、redirect、env-injected command、或
  settings.local-only 未註冊 hook 一律 fail-stop。
- **Generated Codex runtime targets**（`AGENTS.md` / `.codex/AGENTS.md`）必須含由
  `scripts/compile-runtime-instructions.sh` 從 registry emit 的 Codex invocation
  guidance；手改 generated target 視為 parity drift。
- **Carve-out** 只允許在 owning DP plan 明文記載 runtime exclusivity 理由（如
  Claude-Code-only IDE feature），並在 registry 標 `parity_exception=<DP>:<reason>`；
  validator 反查 owning DP plan 的 reason，缺 reason 一樣 fail-stop。

Deterministic enforcement 由 `scripts/validate-cross-llm-mechanism-parity.sh` 提供，
並 wire 進 `scripts/check-framework-pr-gate.sh`（PR-merge time）與
`scripts/verify-cross-llm-parity.sh` step 9（release preflight）；違反時 exit 2 +
stderr `POLARIS_CROSS_LLM_PARITY_BLOCKED:{hook}`。BYPASS env（`POLARIS_CROSS_LLM_PARITY_BYPASS`
/ `POLARIS_LANGUAGE_POLICY_BYPASS` / `POLARIS_SKILL_BOUNDARY_BYPASS` 等）不能 silence 這個
gate。

## Why

Rules 可以告訴每個 LLM 該去哪裡編輯，但只有 symlink 能從機制上消除 mirror drift。Rule 定義意圖；
symlink 負責機械 enforcement。

## Platform Notes

在 Windows 或 `core.symlinks=false` 的系統上，`git checkout` 可能會把 `.agents/skills`
materialize 成內容為 `../.claude/skills` 的一般文字檔，而不是真正的 symlink。此狀態下
`scripts/check-skills-mirror-mode.sh` 會 fail。

修復選項：

```bash
git config core.symlinks true
git rm --cached .agents/skills
git checkout HEAD -- .agents/skills
```

或直接重建 alias：

```bash
mise run cross-runtime-sync
```
