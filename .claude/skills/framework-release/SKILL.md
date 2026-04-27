---
name: framework-release
description: "Local-only release workflow for Polaris/framework changes. Use this whenever the user says 升版, framework release, polaris release, sync to polaris, push framework, 發版, or when VERSION/CHANGELOG/framework rules/skills/scripts were changed and need to be committed or pushed. This skill prevents the common failure mode of only pushing the workspace repo while forgetting sync-to-polaris, template tag, GitHub release, account restoration, and final two-repo verification."
---

# Framework Release

This is a local-only skill for releasing Polaris/framework changes from the working instance repo to the upstream Polaris template repo.

Use it when the task is about publishing framework changes, not product-ticket implementation. The goal is to finish the whole release chain, not just create a commit.

## Release Boundary

A framework release is not complete until both repos are aligned:

- Workspace instance repo, usually `/Users/hsuanyu.lee/work`
- Polaris template repo, usually `/Users/hsuanyu.lee/polaris`

Do not treat `git push origin main` in the workspace repo as the end of the release. That only publishes the working instance. The template still needs `sync-to-polaris.sh --push`, tag creation, release creation, and final verification.

## Preconditions

Before changing or pushing anything:

1. Confirm the current repo is the framework workspace:

   ```bash
   git -C /Users/hsuanyu.lee/work status --short --branch
   git -C /Users/hsuanyu.lee/work remote -v
   ```

2. Confirm the template repo exists and inspect its state:

   ```bash
   git -C /Users/hsuanyu.lee/polaris status --short --branch
   git -C /Users/hsuanyu.lee/polaris log --oneline --decorate -3
   ```

3. If `/Users/hsuanyu.lee/polaris` has unrelated local changes, stop and ask the user before syncing. Do not overwrite local template changes silently.

4. If the workspace repo has unrelated changes, commit only the intended framework files. Never sweep ignored product worktrees or user files into the release.

## Required Chain

Run this chain for any VERSION bump or framework publishing request.

### 1. Validate Local Changes

Run the checks that are appropriate to the files changed. At minimum:

```bash
python3 scripts/readme-lint.py
git diff --check
bash scripts/gates/gate-version-lint.sh --repo /Users/hsuanyu.lee/work
```

If a changed script has a self-test, run it. For example:

```bash
bash scripts/validate-escalation-sidecar.sh --self-test
```

If a skill was changed because of user feedback or agent behavior drift, also run:

```bash
bash scripts/check-feedback-signals.sh --skill <skill-name>
```

### 2. Commit Workspace Repo

Stage only intentional framework files.

```bash
git -C /Users/hsuanyu.lee/work add <files>
git -C /Users/hsuanyu.lee/work commit -m "<type>(framework): v<version> <summary>"
```

After commit:

```bash
git -C /Users/hsuanyu.lee/work status --short --branch
git -C /Users/hsuanyu.lee/work log --oneline --decorate -3
```

### 3. Push Workspace Repo

```bash
git -C /Users/hsuanyu.lee/work push origin main
```

If the pre-push hook warns about a missing quality marker, report it. The warning is advisory unless the hook exits non-zero.

### 4. Sync To Polaris Template

This step is mandatory. Do not skip it after a VERSION bump.

```bash
bash /Users/hsuanyu.lee/work/scripts/sync-to-polaris.sh \
  --polaris /Users/hsuanyu.lee/polaris \
  --push
```

This script is responsible for:

- copying framework files into the template repo
- genericizing company-specific references
- committing the template repo
- tagging `v<VERSION>`
- pushing template `main` and tags
- creating a GitHub release when missing
- switching GitHub accounts when needed
- switching the GitHub account back afterward

Do not replace this with a manual `git push template main` unless the script is broken and the user explicitly accepts the fallback.

### 5. Final Verification

Always verify both repos and the active GitHub account before the final answer.

```bash
git -C /Users/hsuanyu.lee/work status --short --branch
git -C /Users/hsuanyu.lee/work log --oneline --decorate -2

git -C /Users/hsuanyu.lee/polaris status --short --branch
git -C /Users/hsuanyu.lee/polaris log --oneline --decorate -2

cat /Users/hsuanyu.lee/work/VERSION
cat /Users/hsuanyu.lee/polaris/VERSION

gh auth status
```

If a release was expected, verify the tag exists locally in the template repo:

```bash
git -C /Users/hsuanyu.lee/polaris tag -l "v$(cat /Users/hsuanyu.lee/work/VERSION)"
```

If network access is available and `gh` is authenticated, verify the GitHub release:

```bash
gh release view "v$(cat /Users/hsuanyu.lee/work/VERSION)" \
  --repo HsuanYuLee/polaris \
  --json tagName,url
```

## Failure Rules

Stop and report clearly when:

- workspace VERSION and template VERSION differ after sync
- workspace push succeeded but template sync failed
- template tag is missing after `sync-to-polaris.sh --push`
- GitHub account was not restored to the original active account
- template repo has unexpected local changes before sync
- `sync-to-polaris.sh` reports leak-check warnings that look material

Do not hide partial release state. Tell the user exactly which step completed and which step failed.

## Final Response Format

Keep the final answer short and include:

- workspace commit SHA
- template commit SHA
- version tag
- release URL, if created or verified
- final repo cleanliness
- any advisory warnings from hooks

Example:

```text
Framework release complete.

Workspace: 4924701 fix(framework): v3.73.2 gate-closure escalation
Template: e8a92ba fix(framework): v3.73.2 gate-closure escalation
Tag: v3.73.2
Release: https://github.com/HsuanYuLee/polaris/releases/tag/v3.73.2

Both repos are clean. GitHub active account is restored to your-username.
```
