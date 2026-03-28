# wt (worktrunk) Setup Guide

> **Quick setup**: Run `bash scripts/setup-wt.sh` to automate all steps below.

## Installation

Install `wt` via Homebrew (recommended) or Cargo:

```bash
# Homebrew
brew install worktrunk

# Cargo (alternative)
cargo install worktrunk
```

Verify installation:

```bash
which wt
wt --version
```

## Shell Integration

Shell integration enables `wt` to change your working directory (e.g. `wt switch`).
Without it, `wt` runs as a bare binary and cannot `cd` into worktrees.

```bash
wt config shell install
```

This adds a shell function to your `.zshrc` / `.bashrc`. Restart your shell or run:

```bash
source ~/.zshrc  # or source ~/.bashrc
```

Verify shell integration:

```bash
type wt
# Should show: "wt is a shell function" (not "wt is /opt/homebrew/bin/wt")
```

## User Config

Location: `~/.config/worktrunk/config.toml`

This configures global wt behavior (commit generation, merge strategy, etc.).
A template is provided at `references/user-config.toml`.

Key settings:

| Setting | Description |
|---------|-------------|
| `commit.generation.command` | Uses Claude Haiku to generate commit messages |
| `commit.stage` | `"all"` — auto-stage all changes before commit |
| `merge.squash` | Squash merge for clean history |
| `merge.rebase` | Rebase before merge |
| `merge.remove` | Remove worktree after merge |
| `merge.verify` | Run pre-merge hooks before merging |

## Project Config

Location: `<project-root>/.config/wt.toml`

This configures per-project hooks (post-create setup, pre-merge checks).
A template is provided at `references/project-config.toml`.

Key hooks:

| Hook | Description |
|------|-------------|
| `post-create.env` | Copies `.env` files from primary worktree to new worktree |
| `post-create.install` | Runs `pnpm install` after creating a worktree |
| `pre-merge.lint` | Runs lint before merging |
| `pre-merge.test` | Runs unit tests before merging |

Template variables available in hooks:

- `{{ worktree_path }}` — path of the new worktree
- `{{ primary_worktree_path }}` — path of the main (primary) worktree

## Claude Code Permissions

Add `Bash(wt:*)` to `.claude/settings.local.json` so Claude Code can run `wt` commands
without prompting:

```json
{
  "permissions": {
    "allow": ["Bash(wt:*)"]
  }
}
```

## Troubleshooting

### `wt: command not found`

- Ensure Homebrew bin is in your `$PATH`: `export PATH="/opt/homebrew/bin:$PATH"`
- Or install via Cargo: `cargo install worktrunk`

### `wt switch` doesn't change directory

- Shell integration is missing. Run `wt config shell install` and restart your shell.
- Check with `type wt` — it should say "shell function", not a file path.

### `pnpm install` fails in new worktree

- The `post-create` hook copies `.env` files but doesn't handle all project-specific setup.
- Manually check if additional config files need to be copied.

### Merge fails with lint/test errors

- Fix issues in the worktree, commit, then retry `wt merge <target>`.
- To skip pre-merge hooks (not recommended): `wt merge <target> --no-verify`.
