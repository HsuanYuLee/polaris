# Refinement DP Source Mode

Progressive-disclosure reference for `refinement` ticketless / DP-backed source handling.

Use this when `refinement` resolves a source as:

- `dp`: existing `DP-NNN` design-plan container
- `topic`: new ticketless topic that must become a DP container
- `artifact_path`: a path under `specs/design-plans/DP-NNN-*`

Core boundary: `refinement` owns the design record and artifact output; it does not write JIRA for DP-backed work.

## T0. Resolve Source

Resolve source via `spec-source-resolver.md`.

| Input | Action |
|-------|--------|
| `DP-NNN` | Locate exactly one `specs/design-plans/DP-NNN-*/plan.md` |
| direct DP plan/refinement path | Use that DP folder as `source_container` |
| topic phrase | Allocate the next `DP-NNN-{slug}` folder, create `plan.md`, set `status: DISCUSSION` |
| `SEEDED` DP | Read `artifacts/research-report.md` when present and convert relevant findings into candidate Decisions |
| `LOCKED` / `IMPLEMENTED` DP | Fail loud for new topic overwrite; continue only when the user is explicitly resuming/reviewing that DP |

DP locator hard rules:

- `DP-NNN` must uniquely match one folder.
- Zero or multiple matches fail loud.
- Do not silently create a replacement DP for the same number.
- `LOCKED` / `IMPLEMENTED` DP cannot be overwritten by a new topic. Open a new DP and add see-also links when direction changes.

## T1. Create Or Update DP Plan

For a new topic:

1. Scan `{workspace_root}/specs/design-plans/DP-*`.
2. Allocate max existing number + 1.
3. Create `{workspace_root}/specs/design-plans/DP-NNN-{topic-slug}/plan.md`.
4. Write frontmatter:
   ```yaml
   ---
   topic: <durable topic>
   created: YYYY-MM-DD
   status: DISCUSSION
   ---
   ```
5. Add initial `## Goal`, `## Background`, and open decision placeholders if known.

`refinement` owns these DP sections:

- `## Goal`
- `## Background`
- `## Decisions`
- `## Blind Spots`
- `## Acceptance Criteria`
- `## Technical Approach` / `## 技術方案`

Every user-confirmed design decision must update `plan.md` before unrelated work continues. Do not keep confirmed decisions only in conversation memory.

每次建立或更新 `plan.md` 後，必須先跑 workspace language gate，通過後才能
sidebar sync 或回報給使用者：

```bash
bash scripts/validate-language-policy.sh \
  --blocking \
  --mode artifact \
  {workspace_root}/specs/design-plans/DP-NNN-{slug}/plan.md
```

若 gate 失敗，先修正自然語言內容並重跑。`plan.md` 違反 workspace language
時，不可宣稱 DP 已可 review。

## T2. Docs-Viewer Sidebar Sync

建立或編輯 DP markdown 後，讓它可在 docs-viewer 導覽。必須先跑 T1/T3 的
language gate；docs-viewer 不應暴露未通過 workspace language policy 的新產生 prose。

Preferred:

```bash
bash scripts/docs-viewer-sync-hook.sh {workspace_root} {changed_dp_markdown_path}
```

Fallback when the hook entrypoint cannot classify the path:

```bash
bash scripts/generate-specs-sidebar.sh {workspace_root}
```

This applies to `plan.md`, `refinement.md`, and any DP markdown artifact intended for review.

## T3. Local Preview

Ticketless source still uses local-first refinement. Write discussion output to:

```text
{workspace_root}/specs/design-plans/DP-NNN-{slug}/refinement.md
```

Preview:

```bash
python3 scripts/refinement-preview.py {workspace_root}/specs/design-plans/DP-NNN-{slug}/refinement.md
```

`refinement.md` should contain downstream implementation information only:

- scope
- technical approach
- acceptance criteria
- edge cases
- risks
- references

Keep full decision history in `plan.md`.

每次建立或更新 `refinement.md` 後，必須先跑 workspace language gate，通過後才能
preview、sidebar sync 或 downstream handoff：

```bash
bash scripts/validate-language-policy.sh \
  --blocking \
  --mode artifact \
  {workspace_root}/specs/design-plans/DP-NNN-{slug}/refinement.md
```

同一輪若同時改了 `plan.md` 與 `refinement.md`，用同一個 command 一起驗。若 gate
失敗，先修正 artifact language，再開 preview 或繼續 refinement flow。

## T4. Artifact Output

When ready for handoff, produce or update:

```text
specs/design-plans/DP-NNN-{slug}/refinement.md
specs/design-plans/DP-NNN-{slug}/refinement.json
```

DP-backed `refinement.json` must include:

```json
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-NNN",
    "container": "{workspace_root}/specs/design-plans/DP-NNN-{slug}",
    "plan_path": "{workspace_root}/specs/design-plans/DP-NNN-{slug}/plan.md",
    "jira_key": null
  }
}
```

The artifact must preserve enough scope, AC, dependencies, edge cases, and downstream hints for `breakdown DP-NNN` to create work orders without redoing refinement.

## T5. LOCKED Handoff Gate

When the user says "定版", "開始做", "可以執行", "lock", or equivalent:

1. Check that Goal, Decisions, Blind Spots, Acceptance Criteria, and Technical Approach are sufficient for breakdown.
2. Ensure `refinement.md` and `refinement.json` are current; `refinement.json` must pass `scripts/refinement-handoff-gate.sh`.
3. Change DP frontmatter to:
   ```yaml
   status: LOCKED
   locked_at: YYYY-MM-DD
   ```
4. Run the relevant artifact validator / handoff gate. If it fails or `refinement.json` is missing, stop and produce/fix the artifact before continuing.
5. Sync docs-viewer sidebar.
6. Tell the user the next command:
   ```text
   breakdown DP-NNN
   ```

Ticketless source never writes JIRA comments, labels, descriptions, or sub-tasks. If a formal cross-team document is needed, route to `sasd-review` or create a JIRA ticket explicitly.
