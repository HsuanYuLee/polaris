# VR JIRA Report Template

Wiki markup template for Visual Regression reports posted to JIRA via REST API v2.

## Usage

Post via `POST /rest/api/2/issue/{issueKey}/comment` with `Content-Type: application/json`.
The `body` field uses Jira wiki markup (NOT markdown — `contentFormat: "markdown"` breaks image embedding).

## Key Rules

- **Images must use wiki markup**: `!filename.png|thumbnail!` — only works in v2 API with wiki markup body
- **Images inside tables**: `| !desktop.png|thumbnail! | !mobile.png|thumbnail! |` — the `|thumbnail` suffix is required for inline preview
- **Do NOT use markdown contentFormat** — `contentFormat: "markdown"` via v3 MCP renders `!filename.png|thumbnail!` as literal text
- **Attachment filenames must match exactly** — upload via `jira-upload-attachment.sh` first, then reference by filename
- **Delete before re-upload** — same-name attachments get different IDs; old wiki markup binds to old ID. Delete old, upload new, then post comment

## Template: Zero-Diff Report (all pass)

```
h2. VR 結果 — {Epic/Ticket} Visual Regression（{date}）

*結論：{N}/{N} PASS — 全頁面 zero-diff*

h3. 測試條件
* Baseline & Comparison: {branch}（Mockoon fixture 隔離，before/after 同源比對）
* Fixtures: {epic} epic（{N} routes）
* 環境: Mockoon + Nuxt dev server + Docker nginx (dev.kkday.com)
* Playwright: desktop 1280x720 + mobile 375x812 (iPhone UA)

----

h3. ✅ Homepage — PASS (zero-diff)
|| Desktop || Mobile (viewport-only) ||
| !desktop-Homepage.png|thumbnail! | !mobile-Homepage.png|thumbnail! |

h3. ✅ Product Page (#10000) — PASS (zero-diff)
|| Desktop || Mobile ||
| !desktop-Product-Page.png|thumbnail! | !mobile-Product-Page.png|thumbnail! |

h3. ✅ Destination Page (jp-japan) — PASS (zero-diff)
|| Desktop || Mobile ||
| !desktop-Destination-Page.png|thumbnail! | !mobile-Destination-Page.png|thumbnail! |

h3. ✅ Category Page (sightseeing-tours) — PASS (zero-diff)
|| Desktop || Mobile ||
| !desktop-Category-Page.png|thumbnail! | !mobile-Category-Page.png|thumbnail! |

----

h3. 判定
PASS — {N} tests zero-diff。{additional notes}
```

## Template: Mixed Results (some fail/skip)

```
h3. ✅ {Page} — PASS (zero-diff)
|| Desktop || Mobile ||
| !desktop-{Page}.png|thumbnail! | !mobile-{Page}.png|thumbnail! |

h3. ⚠ {Page} — FAIL ({diff_pct}% diff)
|| || Desktop || Mobile ||
| *Baseline* | !before-{page}-desktop.png|thumbnail! | !before-{page}-mobile.png|thumbnail! |
| *After* | !after-{page}-desktop.png|thumbnail! | !after-{page}-mobile.png|thumbnail! |
| *Diff* | !diff-{page}-desktop.png|thumbnail! | !diff-{page}-mobile.png|thumbnail! |

{quote}Root cause: {description}{quote}

h3. ⏭ {Page} — SKIP
*原因：* {reason}
*解除條件：* {unblock condition}
```

## Attachment Naming Convention

| Type | Desktop | Mobile |
|------|---------|--------|
| Current screenshot | `desktop-{PageName}.png` | `mobile-{PageName}.png` |
| Before (comparison) | `before-{page}-desktop.png` | `before-{page}-mobile.png` |
| After (comparison) | `after-{page}-desktop.png` | `after-{page}-mobile.png` |
| Diff | `diff-{page}-desktop.png` | `diff-{page}-mobile.png` |

PageName uses PascalCase matching the Playwright test describe block: `Homepage`, `Product-Page`, `Destination-Page`, `Category-Page`.
