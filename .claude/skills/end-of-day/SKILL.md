---
name: end-of-day
description: >
  DEPRECATED — use /standup instead. Standup v2.0 includes auto-triage (Step 0).
  All end-of-day triggers ("下班", "收工", "EOD", "wrap up") now route to standup.
  This skill exists only as a redirect for backwards compatibility.
metadata:
  author: Polaris
  version: 2.0.0-deprecated
---

# End of Day — DEPRECATED

> **This skill has been merged into `/standup` (v2.0).** All end-of-day triggers now route directly to standup, which includes auto-triage in Step 0.

If you're reading this, invoke `/standup` instead. The standup skill will:
1. Auto-run `/my-triage` if `.daily-triage.json` is missing or stale (Step 0)
2. Collect git/JIRA/Calendar activity (Steps 1-6)
3. Build TDT from triage-ranked items (Step 7)
4. Format and push to Confluence (Steps 8-10)
