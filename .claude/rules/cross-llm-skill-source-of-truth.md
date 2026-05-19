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
