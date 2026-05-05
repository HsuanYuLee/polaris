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
links.json
publication-manifest.json
verify-report.md
assets/
  screenshots/
  videos/
  raw/
  files/
<legacy copied evidence files>
```

`README.md` 列出要上傳的檔案，並提醒使用者發布前先檢查截圖與影片內容。README
必須有 Starlight frontmatter，讓 local board 可以直接顯示。

`manifest.json` 記錄：

- `ticket`
- `head_sha`
- `target`
- source repo
- source container
- bundle dir
- generated timestamp
- report generator input contract
- copied item list，包含 source path、bundle filename、size、SHA-256，以及是否需要
  remote publication

`links.json` 由 `scripts/distribute-static-evidence.mjs` 產生。LLM 不判斷檔案歸屬；
distributor 依副檔名機械式分類：

| Extension | Destination | Report behavior |
|-----------|-------------|-----------------|
| `.png`, `.jpg`, `.jpeg`, `.webp`, `.gif`, `.svg` | `assets/screenshots/` | Markdown image |
| `.webm`, `.mp4`, `.mov`, `.m4v` | `assets/videos/` + scoped public mirror | Markdown link, no inline video |
| `.json`, `.har`, `.log`, `.txt`, `.trace` | `assets/raw/` | Supporting evidence link |
| other files | `assets/files/` | Supporting evidence link |

`publication-manifest.json` 記錄 local board publication state。第一版只承諾 local board
可消費；PR / Jira binary upload 是獨立 remote publication flow，不得把 local linkability
視為 remote publication gate PASS。

`verify-report.md` 由 `scripts/generate-verify-report.mjs` 消費 `links.json` 產生。圖片用
relative Markdown image；影片只提供可點擊 link，避免 Starlight 內嵌影片造成瀏覽負擔。

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

收集後可用 distributor / report generator 建 local board report：

```bash
node "${POLARIS_ROOT}/scripts/distribute-static-evidence.mjs" \
  --source "<bundle_dir>" \
  --output-dir "<bundle_dir>" \
  --scope "<WORK_ITEM_ID>"

node "${POLARIS_ROOT}/scripts/generate-verify-report.mjs" \
  --links "<bundle_dir>/links.json" \
  --output "<bundle_dir>/verify-report.md" \
  --title "Verify Report - <WORK_ITEM_ID>"
```

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
