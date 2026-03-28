# Polaris Onboarding Guide

Step-by-step guide to set up Polaris as your AI command workspace.

## Prerequisites

- [ ] [Claude Code CLI](https://claude.ai/claude-code) installed
- [ ] [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated
- [ ] Git configured with your identity

## Phase 1: Clone & Configure (5 min)

### 1.1 Clone Polaris

```bash
git clone https://github.com/HsuanYuLee/polaris.git ~/work
cd ~/work
```

> **Tip**: You can name the directory anything — `~/work`, `~/workspace`, `~/ops`. This becomes your command center.

### 1.2 Initialize your company

**Option A: Interactive wizard (recommended)**

```bash
claude
> /init
```

The wizard auto-detects your GitHub org, lists repos, and guides you through each section.

**Option B: Manual setup**

```bash
# Create company directory
mkdir my-company

# Copy template
cp _template/workspace-config.yaml my-company/workspace-config.yaml

# Edit my-company/workspace-config.yaml with your values
```

Then update the root `workspace-config.yaml`:

```yaml
companies:
  - name: my-company
    base_dir: "~/work/my-company"
```

| Section | Required? | What to fill |
|---------|-----------|-------------|
| `github` | Yes (if using GitHub) | Your GitHub org name |
| `jira` | Optional | JIRA instance URL, project keys |
| `confluence` | Optional | Space key, page IDs |
| `slack` | Optional | Channel IDs for notifications |
| `projects` | Yes | Map your repos to tags/keywords |
| `scrum` | Optional | PR threshold, sprint capacity |
| `infra` | Optional | Ansible repo, dev host |

**Don't have all the values?** That's fine — leave sections empty. Skills gracefully degrade when integrations are missing.

## Phase 2: Bring Your Projects (10 min)

### 2.1 Clone your repos

```bash
# Clone repos into your organization folder
git clone git@github.com:your-org/frontend.git my-company/frontend
git clone git@github.com:your-org/backend.git my-company/backend
git clone git@github.com:your-org/design-system.git my-company/design-system
```

### 2.2 Add project-level rules (optional)

Each project can have its own AI rules:

```bash
mkdir -p my-company/frontend/.claude/rules
```

Create `my-company/frontend/CLAUDE.md` with project-specific conventions:

```markdown
# Frontend Project

## Stack
- Framework: Next.js 14
- Testing: Vitest + Testing Library
- Styling: Tailwind CSS

## Conventions
- Components in `src/components/`, one component per file
- Tests co-located: `Component.test.tsx` next to `Component.tsx`
- API calls go through `src/lib/api/`
```

This L3 context loads automatically when a sub-agent enters the project directory.

### 2.3 Update project mapping

Edit your company's `workspace-config.yaml` to map your projects:

```yaml
projects:
  - name: "frontend"
    repo: "your-org/frontend"
    tags: ["fe", "frontend"]
    keywords: ["UI", "page", "component"]
  - name: "backend"
    repo: "your-org/backend"
    tags: ["be", "backend"]
    keywords: ["API", "endpoint", "service"]
```

This tells Polaris which repo to target when you mention a JIRA tag like `[fe]` or keyword like "API endpoint".

## Phase 3: Customize Your Rules (15 min)

### 3.1 Skill routing

Edit `.claude/rules/company/skill-routing.md` — this is the decision tree that maps your words to skills. Update the examples to use your JIRA project keys:

```markdown
| "work on MYPROJ-123" | `/work-on` | Smart router |
| "fix bug MYPROJ-456" | `/fix-bug` | End-to-end bug fix |
```

### 3.2 JIRA status flow

Edit `.claude/rules/company/jira-status-flow.md` — map your JIRA workflow:

- Update status names to match your board
- Update custom field IDs (`customfield_XXXXX`) — find these in JIRA Admin → Custom Fields
- Update requirement source values

### 3.3 PR & review rules

Edit `.claude/rules/company/pr-and-review.md`:

- Set your approval threshold
- Define your review label name
- Configure pre-PR quality gates

### 3.4 Scenario playbooks

Edit `.claude/rules/company/scenario-playbooks.md` — these are step-by-step recipes. Customize:

- Branch naming conventions
- PR base branch rules
- Bug fix workflow
- Feature development flow

## Phase 4: First Run (2 min)

### 4.1 Launch Polaris

```bash
cd ~/work
claude
```

### 4.2 Try these commands

Start simple:

```
> standup
```
Generates your daily standup from git history + JIRA.

```
> work on MYPROJ-123
```
Smart router: reads the ticket, estimates, creates branch, starts coding.

```
> review PR https://github.com/your-org/frontend/pull/42
```
Structured code review with inline comments.

## Phase 5: Multi-Organization (optional)

To manage multiple organizations from one Polaris instance:

```bash
mkdir -p acme-corp startup-x
```

Each org folder can have its own:
- `.claude/rules/` — organization-specific rules
- `docs/` — workflow documentation
- Project repos as subdirectories

The L1 rules (CLAUDE.md, `rules/bash-command-splitting.md`) apply universally. L2 rules in each org folder apply when working in that context.

## Troubleshooting

### Skills don't trigger

Check `.claude/rules/company/skill-routing.md` — your input must match the patterns defined there.

### JIRA operations fail

1. Verify your company's `workspace-config.yaml` has correct `jira.instance`
2. Check that Claude Code has the Atlassian MCP server connected
3. Ensure your JIRA project keys match config

### PR creation fails

1. Run `gh auth status` to verify GitHub CLI authentication
2. Check that `github.org` in config matches your actual org name
3. Ensure you have push access to the repo

### Config changes don't take effect

Skills read company config fresh each time — no restart needed. But changes to `.claude/rules/` files take effect on the next conversation (or after context compression).

## What's Next

- **Add company-specific skills**: Use `/skill-creator` to build skills unique to your workflow
- **Tune rules iteratively**: As you use Polaris, it learns from feedback and suggests rule upgrades
- **Sync docs to Confluence**: Keep your workflow documentation in `company/docs/` and sync when stable
