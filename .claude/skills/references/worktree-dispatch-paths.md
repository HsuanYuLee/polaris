# Worktree Dispatch — Path Map for Gitignored Artifacts

**When to load**: your skill dispatches a sub-agent that runs in a `git worktree add` copy AND that sub-agent needs to read or write any of:

- `specs/{EPIC}/` (task.md, refinement, verification evidence, mockoon fixtures, VR baselines)
- framework company handbook (`{base_dir}/.claude/rules/{company}/handbook/`)
- workspace-owned repo handbook (`{company}/polaris-config/{project}/handbook/`)
- workspace-owned Local CI mirror (`{company}/polaris-config/{project}/generated-scripts/ci-local.sh`)
- `.claude/skills/` (cross-skill references)

Both are gitignored in product repos → they do not exist in a fresh worktree.

## Path Buckets

| What | Where | How in dispatch prompt |
|------|-------|------------------------|
| Tracked source code | Worktree-relative | 預設；`{worktree_path}/src/...` |
| `specs/{EPIC}/` artifacts | 主 checkout（gitignored） | **絕對路徑**：`{company_specs_dir}/{EPIC}/...` |
| Company handbook | workspace-owned polaris-config | **絕對路徑**：`{company_dir}/polaris-config/handbook/index.md`，並展開 index 引用子文件 |
| Repo handbook | workspace-owned polaris-config | **絕對路徑**：`{company_dir}/polaris-config/{project}/handbook/index.md`，並展開 index 引用子文件 |
| Local CI mirror | workspace-owned polaris-config | 用 `bash {base_dir}/scripts/ci-local-run.sh --repo {worktree_path}`；不要直接查 repo-local `.claude/scripts/ci-local.sh` |
| `.claude/skills/` references | workspace 主 checkout（gitignored） | **絕對路徑**：`{base_dir}/.claude/skills/...` |
| Runtime model adapter policy | workspace 主 checkout | **絕對路徑**：`{base_dir}/.claude/skills/references/model-tier-policy.md`；dispatch prompt 使用 semantic model class，runtime adapter 再映射 concrete model / effort |

## Copy-Paste Block for Dispatch Prompts

Embed verbatim near the "Work Order" / "讀取來源" section of every worktree-bound sub-agent prompt. Substitute `{company_base_dir}`, `{EPIC}`, `{worktree_path}` with concrete values before dispatch:

> **Worktree vs 主 checkout 路徑規則**
>
> 你的工作目錄是 worktree：`{worktree_path}`。tracked source file 的讀寫限定於此目錄。
>
> 以下 gitignored 框架檔案在此 worktree 不存在，必須以**主 checkout 絕對路徑**存取：
> - task.md / work order：`{company_specs_dir}/{EPIC}/tasks/T{n}.md`
> - artifacts / handoff：`{company_specs_dir}/{EPIC}/artifacts/`
> - verification evidence：`{company_specs_dir}/{EPIC}/verification/`
> - company handbook：`{company_dir}/polaris-config/handbook/index.md` + index 引用子文件
> - repo handbook：`{company_dir}/polaris-config/{project}/handbook/index.md` + index 引用子文件
> - Local CI mirror：用 `bash {base_dir}/scripts/ci-local-run.sh --repo "{worktree_path}"`；script 會自動讀 workspace-owned canonical generated script
> - skills reference（若需）：`{base_dir}/.claude/skills/references/...`
> - model tier policy（若需指定 sub-agent model class）：`{base_dir}/.claude/skills/references/model-tier-policy.md`；prompt 中寫 semantic class，避免直接寫 provider model ID
>
> 寫入 artifact 也用主 checkout 絕對路徑，使 downstream skill（verify-AC、check-pr-approvals）在主 checkout 讀得到。

## Cross-LLM Compatibility

Codex and other LLMs do not auto-load `.claude/rules/`. SKILL.md files that dispatch worktree sub-agents must embed this path map inline (not just a reference link), so the dispatching model has the paths in context without an extra file load.

For model selection, embed only the semantic class from `model-tier-policy.md` in the dispatch prompt. Runtime-specific adapter examples live in that policy file; copied concrete model names in worktree prompts are treated as drift.

## Rationale

- Worktree 只隔離 tracked 程式碼
- `specs/` 跨 worktree 共享是 by design — pipeline handoff（engineering 寫 evidence → verify-AC 讀 evidence）依賴同一份主 checkout 路徑
- 主 checkout 的 `specs/` 是單一真實來源，沒有 stale-copy 問題

See also: `rules/sub-agent-delegation.md` § Worktree path translation / Gitignored framework artifacts
