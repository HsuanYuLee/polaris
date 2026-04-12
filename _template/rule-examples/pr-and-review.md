# PR & Review Rules

## PR Creation
- **Automatically transition JIRA to CODE REVIEW after PR is created**: no manual action needed from the user
- **Automatically add `need review` label after PR is created**: after `gh pr create` completes, run `gh pr edit <number> --add-label "need review"`
- **Do not open a PR if quality checks fail**: if tests fail or coverage is insufficient, fix them before proceeding
- **Always run `dev-quality-check` before pushing code changes**: all quality checks go through this skill; do not write separate validation logic in individual skills
- **Code changes must not reduce overall coverage**: Codecov `project` check requires coverage to stay at or above the base branch (threshold 1%)
- **Pre-push quality gate (enforced by hook)**: `.claude/hooks/pre-push-quality-gate.sh` intercepts `git push` and verifies that `dev-quality-check` has passed (marker file `/tmp/.quality-gate-passed-{branch}`). Push is blocked if not passed. Main branches (main/master/develop) are not intercepted. Marker expires after 24 hours

## Review
- **Self-review of your own PR is strictly forbidden**: under no circumstances (bug-triage, fix-pr-review, after opening a PR) may you submit a GitHub review comment on your own PR. Review is only for reviewing others' code
- **Rebase before submitting a review or re-review**: at the start of fix-pr-review, rebase the base branch before making fixes; also rebase before sending a review request via review-pr / git-pr-workflow
- **Report PR approval status after completing a review**: after review-pr finishes, report approval progress (current X/{required} approves); the required approvals count is read from `github.required_approvals` in the workspace config
- **Pre-PR review loop is capped at 3 rounds**: if blocking issues remain after 3 rounds, list the outstanding issues and ask the user
- **Every review comment must receive a response**: regardless of whether a fix was made, always reply (fixed / reason not fixed / needs discussion)
