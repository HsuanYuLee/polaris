# Workspace Overlay Contract

Framework work 會同時接觸兩種 filesystem surface：

| Layer | Purpose | Write policy |
|-------|---------|--------------|
| Task worktree | tracked implementation files、commit、workspace PR | 只在這裡做 implementation write |
| Workspace overlay | main checkout 的 local runtime context，例如 ignored specs、`.codex/`、maintainer-local skills | implementation 期間只能 read-only |
| Generated output | `docs-manager/dist`、`.astro` 這類 build artifact | 只供 verification，永遠不是 authoring source |

## Rules

- DP-backed framework implementation 必須發生在 task worktree。
- Main checkout overlay 可以讀取 runtime context 與 validation input，但不得變成 implementation surface。
- Specs authoring source 是 `docs-manager/src/content/docs/specs`，不是 generated `docs-manager/dist`。
- `framework-release` 這類 local maintainer skill 在有 governed release plan 前，維持在 portable repo 外。
- Consumer 應呼叫 `scripts/resolve-workspace-overlay.sh`，不要各自硬寫 local path。

## Resolver Kinds

```bash
scripts/resolve-workspace-overlay.sh --kind specs-root
scripts/resolve-workspace-overlay.sh --kind codex-rules
scripts/resolve-workspace-overlay.sh --kind local-skill framework-release
scripts/resolve-workspace-overlay.sh --kind generated-output
```

Resolver 會輸出 JSON，包含：

- `kind`
- `path`
- `exists`
- `authoring_allowed`
- `generated`

必要 overlay 不存在時必須 fail loud。`generated-output` 可存在或不存在，但一律回傳 `authoring_allowed: false`。
