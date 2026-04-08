# JIRA Quality Rules

Universal rules for working with JIRA tickets. These apply regardless of company or project.

## Ticket Information Quality

- **Never guess when a JIRA ticket is missing information**: proactively list what is missing (file paths, design mockups, acceptance criteria, API docs) and ask the user to fill it in. Do not infer requirements from incomplete data
- **PM-provided examples are not implementation specs**: HTML snippets, code samples, or screenshots from the PM in JIRA are a reference direction, not a dev spec. Read the corresponding codebase component first before deciding the implementation approach
- **When the parent ticket contains only external links, retrieve the content before proceeding**: if the description contains only inaccessible external links (ChatGPT, Google Docs, etc.), do not infer requirements on your own. Proactively inform the user that "the description is insufficient and needs to be supplemented"

## Sub-task Creation

- **Attach a clickable link after creating a JIRA sub-task**: after `createJiraIssue` completes, the response must include the full JIRA URL (`https://{config: jira.instance}/browse/XX-NNN`); do not return only the ticket key
- **Breakdown estimates must include a verification scenario**: each sub-task describes the user-facing operation steps and expected results, laying the groundwork for future testing
- **After breakdown is confirmed, batch-create sub-tasks**: use a sub-agent to create JIRA sub-tasks in parallel, fill in estimates, and update the parent ticket — do not wait for confirmation one ticket at a time

## Attachment Handling

- **Delete before re-uploading**: JIRA wiki markup `!filename.png|thumbnail!` binds to the attachment ID at comment creation time, not by filename lookup. Uploading a same-name file creates a new ID; old comments still point to the old ID. Re-upload flow: (1) delete old attachment (2) upload new file (3) re-post comment. Applies to all JIRA attachment operations (screenshots, design files, test reports)
