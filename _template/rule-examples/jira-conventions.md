# JIRA Conventions

- **Never guess when a JIRA ticket is missing information**: proactively list what is missing (path, Figma, AC, API doc) and ask the user to fill it in
- **Attach a clickable link after creating a JIRA sub-task**: after `createJiraIssue` completes, the response must include the full JIRA URL (`https://{jira.instance}/browse/XX-NNN`); do not return only the ticket key
- **PM-provided examples are not implementation specs**: HTML/code snippets from the PM in JIRA are a reference direction, not a dev spec. Read the corresponding codebase component first before deciding the implementation approach when creating sub-tasks or writing the Dev Scope
- **When the parent ticket contains only external links, retrieve the content before creating sub-tasks**: if the parent ticket description contains only inaccessible external links (ChatGPT, Google Docs, etc.), do not infer requirements on your own. Proactively inform the user that "the description is insufficient and needs to be supplemented"
- **Breakdown estimates must include a Happy Flow verification scenario**: each sub-task describes the user-facing operation steps and expected results, laying the groundwork for future e2e tests
- **After breakdown is confirmed, use a sub-agent to create sub-tasks in parallel**: batch-create JIRA sub-tasks, fill in estimates, and update the parent ticket — do not wait for confirmation one ticket at a time
