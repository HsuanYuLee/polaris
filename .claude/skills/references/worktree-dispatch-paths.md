---
title: "Worktree Dispatch Path Map"
description: "worktree-bound dispatch 時，gitignored framework artifacts 必須使用主 checkout absolute path 的路徑規則。"
---

# Worktree Dispatch — Path Map for Gitignored Artifacts

**載入時機**：skill dispatch 的 sub-agent 會在 `git worktree add` 複本內工作，且需要讀寫下列任一類 artifact：

- `specs/{EPIC}/` (task.md, refinement, verification evidence, mockoon fixtures, VR baselines)
- framework company handbook (`{base_dir}/.claude/rules/{company}/handbook/`)
- workspace-owned repo handbook (`{company}/polaris-config/{project}/handbook/`)
- workspace-owned Local CI mirror (`{company}/polaris-config/{project}/generated-scripts/ci-local.sh`)
- `.claude/skills/` (cross-skill references)

這些 artifact 在 product repo 通常是 gitignored，因此 fresh worktree 內不會存在。

## Path Buckets

| What | Where | How in dispatch prompt |
|------|-------|------------------------|
| Tracked source code | Worktree-relative | 預設；`{worktree_path}/src/...`；讀寫限定於 task worktree |
| `specs/{EPIC}/` / `design-plans/DP-NNN-*` artifacts | 主 checkout（gitignored） | **絕對路徑**：`{company_specs_dir}/{EPIC}/...` 或 `{base_dir}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-...` |
| Company handbook | workspace-owned polaris-config | **絕對路徑**：`{company_dir}/polaris-config/handbook/index.md`，並展開 index 引用子文件 |
| Repo handbook | workspace-owned polaris-config | **絕對路徑**：`{company_dir}/polaris-config/{project}/handbook/index.md`，並展開 index 引用子文件 |
| Local CI mirror | workspace-owned polaris-config | 用 `bash {base_dir}/scripts/ci-local-run.sh --repo {worktree_path}`；不要直接查 repo-local `.claude/scripts/ci-local.sh` |
| `.claude/skills/` references | workspace 主 checkout（gitignored） | **絕對路徑**：`{base_dir}/.claude/skills/...` |
| Runtime model adapter policy | workspace 主 checkout | **絕對路徑**：`{base_dir}/.claude/skills/references/model-tier-policy.md`；dispatch prompt 使用 semantic model class，Codex 用 `.codex/agents/polaris-*.toml` custom agent，Claude Code 用 subagent model frontmatter / per-invocation model |

## Copy-Paste Block for Dispatch Prompts

Embed verbatim near the "Work Order" / "讀取來源" section of every worktree-bound sub-agent prompt. Substitute `{company_base_dir}`, `{EPIC}`, `{worktree_path}` with concrete values before dispatch:

> **Worktree vs 主 checkout 路徑規則**
>
> 你的工作目錄是 worktree：`{worktree_path}`。tracked source file 的讀寫限定於此目錄。
> 所有 implementation、test、verify、commit、PR create 都以此 worktree 為 repo / cwd。
>
> 以下 gitignored 框架檔案在此 worktree 不存在，必須以**主 checkout 絕對路徑**存取：
> - task.md / work order：`{company_specs_dir}/{EPIC}/tasks/T{n}.md`
> - DP task.md / refinement：`{base_dir}/docs-manager/src/content/docs/specs/design-plans/DP-NNN-.../tasks/T{n}/index.md`
> - artifacts / handoff：`{company_specs_dir}/{EPIC}/artifacts/`
> - verification evidence：`{company_specs_dir}/{EPIC}/verification/`
> - company handbook：`{company_dir}/polaris-config/handbook/index.md` + index 引用子文件
> - repo handbook：`{company_dir}/polaris-config/{project}/handbook/index.md` + index 引用子文件
> - Local CI mirror：用 `bash {base_dir}/scripts/ci-local-run.sh --repo "{worktree_path}"`；script 會自動讀 workspace-owned canonical generated script
> - skills reference（若需）：`{base_dir}/.claude/skills/references/...`
> - model tier policy（若需指定 sub-agent model class）：`{base_dir}/.claude/skills/references/model-tier-policy.md`；prompt 中寫 semantic class，避免直接寫 provider model ID
> - Codex runtime profiles（Codex only）：`{base_dir}/.codex/agents/polaris-*.toml`；只影響 spawned child agent，不改 main session model
>
> 寫入 artifact 也用主 checkout 絕對路徑，使 downstream skill（verify-AC、check-pr-approvals）在主 checkout 讀得到。
>
> 禁止把 `docs-manager/src/content/docs/specs/**`、`.claude/skills/**` 或
> `polaris-config/**` copy / rsync / mirror 到 worktree；需要讀取時使用上列主 checkout
> absolute path。

## Cross-LLM Compatibility

Codex 與其他 LLM 不會自動載入 `.claude/rules/`。會 dispatch worktree sub-agent 的
SKILL.md 必須把此 path map inline 放進 prompt，不只放 reference link，確保 dispatching
model 不需額外載檔也有路徑脈絡。

Model selection 只在 dispatch prompt 內放 `model-tier-policy.md` 的 semantic class。
Runtime-specific adapter example 留在該 policy file，Codex project profiles 留在
`.codex/agents/polaris-*.toml`；worktree prompt 若複製 concrete model name 視為 drift。
Codex profile 無法使用時 fallback to `inherit`，並在 Completion Envelope 記錄原因。

## Rationale

- Worktree 只隔離 tracked 程式碼
- `specs/` 跨 worktree 共享是 by design — pipeline handoff（engineering 寫 evidence → verify-AC 讀 evidence）依賴同一份主 checkout 路徑
- 主 checkout 的 `specs/` 是單一真實來源，沒有 stale-copy 問題

See also: `rules/sub-agent-delegation.md` § Worktree path translation / Gitignored framework artifacts
