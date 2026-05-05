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

## Completion Envelope

Return exactly:

```markdown
Status: DONE | ERROR
Artifacts: {pr_url, number, title, author, repo, result, must_fix, should_fix, nit, approve_status, summary}
Detail: /tmp/polaris-agent-{timestamp}.md
Summary: <= 3 sentences
```
