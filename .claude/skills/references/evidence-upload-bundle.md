---
title: "Evidence Upload Bundle"
description: "固定 engineering / verify-AC 圖片、影片、JSON 佐證的人工上傳包輸出位置與 helper contract。"
---

# Upload Bundle Contract

本 reference 定義人工上傳截圖、影片與 evidence JSON 時使用的本地資料夾。

它不是 gate evidence writer。`/tmp/polaris-*` 與 repo `.polaris/evidence/**`
仍然是 machine evidence source of truth。

## Canonical Location

Bundle 一律寫在 source spec container 的 `artifacts/` 目錄：

```text
specs/{EPIC_OR_TICKET}/artifacts/{WORK_ITEM_ID}-pr-upload/
specs/{EPIC_OR_TICKET}/artifacts/{WORK_ITEM_ID}-jira-upload/
specs/{EPIC_OR_TICKET}/artifacts/{WORK_ITEM_ID}-evidence-upload/
```

使用規則：

| Target | Folder suffix | Consumer |
|--------|---------------|----------|
| `pr` | `-pr-upload` | Engineering PR comment |
| `jira` | `-jira-upload` | verify-AC Jira attachment/comment |
| `both` | `-evidence-upload` | PR + Jira 共用 handoff |

Source container 是該 work item 所屬、同時擁有 `tasks/` 與 `artifacts/` 的 spec
folder。Epic child task 使用 Epic container。

## Bundle Contents

每個 bundle 包含：

```text
README.md
manifest.json
<copied evidence files>
```

`README.md` 列出要上傳的檔案，並提醒使用者發布前先檢查截圖與影片內容。

`manifest.json` 記錄：

- `ticket`
- `head_sha`
- `target`
- source repo
- generated timestamp
- copied item list，包含 source path、bundle filename、size、SHA-256，以及是否需要
  remote publication

Helper 預設會重建目標 bundle folder，避免上一輪截圖或影片殘留。若需要保留既有檔案，可傳
`--no-clean`。

## Helper

使用方式：

```bash
bash "${POLARIS_ROOT}/scripts/collect-evidence-upload-bundle.sh" \
  --repo "<repo_root>" \
  --ticket "<WORK_ITEM_ID>" \
  --head-sha "<HEAD_SHA>" \
  --source-container "<spec_container>" \
  --target pr
```

Helper 會收集既有 evidence：

- `/tmp/polaris-ci-local-*{head_sha}*.json`
- `/tmp/polaris-verified-{ticket}-{head_sha}.json`
- `/tmp/polaris-vr-{ticket}-{head_sha}.json`
- `<repo>/.polaris/evidence/verify/**`
- `<repo>/.polaris/evidence/vr/**`
- `<repo>/.polaris/evidence/playwright/{ticket}/playwright-behavior-video.json`
- behavior JSON 內引用的 Playwright video file

若 baseline / compare 截圖等 artifact 有相同 basename，helper 會產生不衝突的 bundle
filename，避免互相覆蓋。

## Engineering Flow

當 local VR 或 Playwright behavior evidence 存在時，engineering 必須在 final
PR-visible publication gate 前產生 `pr` bundle。Final response 或 handoff artifact
必須列出 bundle path，讓使用者在 CLI/API 無法上傳 binary attachment 時可直接拖曳到
PR UI。

Completion gate 仍要求 PR-visible marker：

```text
polaris-evidence-publication:v1 ticket={ticket} head={head_sha}
```

Local upload bundle 本身不可滿足 completion。

## verify-AC Flow

當 verify-AC 收集 screenshots、videos、VR diffs、traces 或其他需要人工檢視 /
Jira upload 的 visual evidence 時，必須產生 `jira` bundle，並在 verification report
列出 bundle path。

若 PASS-only run 沒有 visual/manual evidence，可以跳過 bundle creation。

## Safety

Helper 會原樣複製 binary 與 JSON evidence。發布前，人類必須檢查是否包含 secrets、
private customer data 或無關個資；不安全的檔案不可上傳。
