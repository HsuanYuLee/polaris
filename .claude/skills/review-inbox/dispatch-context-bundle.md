# Review Inbox Dispatch Context v1

## Review Flow

Review the PR from the supplied URL and local repo path. Fetch PR metadata,
changed files, diff, existing reviews, approval state, and re-review signal with
the repo script or `gh`. Read only the verified project handbook paths listed in
the prompt. If no handbook paths are listed, record `project_handbook: none` and
continue without scanning repo guideline folders.

## Severity And Write Rules

Prioritize bugs, regressions, security, type safety, key rule violations, and
missing tests. `must-fix` requires evidence from code, diff, or an explicit rule.
Unverified library behavior or style preference is at most `should-fix`. Do not
repeat existing reviewer comments with the same meaning. Suggested changes are
allowed only when the diff range can be replaced exactly.

## Submit Action

Choose `REQUEST_CHANGES` for any must-fix, `COMMENT` for should-fix only, and
`APPROVE` for no issues or only nits. Keep the review body short and concrete.
Run the language gate before any GitHub review or Slack reply. After submit,
query valid approvals, stale approvals, current requested changes, and remaining
approval count.

Read and bind against the same sha — resolve it first, take the diff pinned to it,
and hand the same value back at submit time:

```bash
REVIEWED_HEAD="$(bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N --print-head)"
bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N \
  --reviewed-head "$REVIEWED_HEAD" --print-diff
bash scripts/submit-pr-review.sh --repository OWNER/REPO --pull-number N \
  --reviewed-head "$REVIEWED_HEAD" --event EVENT --body-file BODY --submit
```

Submitting without `--reviewed-head` is refused. `POLARIS_PR_HEAD_ADVANCED` on stderr
means the author pushed while you were reviewing: the review was submitted and is
correctly bound to what you read. It is a message for you, not a failure.

## Completion Envelope

Return exactly:

```markdown
Status: DONE | ERROR
Artifacts: {pr_url, number, title, author, repo, result, must_fix, should_fix, nit, approve_status, summary}
Detail: /tmp/polaris-agent-{timestamp}.md
Summary: <= 3 sentences
```
