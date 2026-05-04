---
title: "Visual Regression Fixture Flow"
description: "visual-regression 的 Mockoon Record → Compare workflow、per-epic fixture lifecycle、edge cases 與 troubleshooting。"
---

# Fixture Lifecycle Contract

這份 reference 負責 Mockoon fixtures 建立、更新與 per-epic isolation。

## When To Record

需要建立或更新 fixtures 時使用 Record -> Compare flow：

| Trigger | Action |
|---|---|
| first VR setup for a domain | record configured proxy routes |
| new API endpoint added | record affected route |
| fixture data stale | re-record affected routes |
| 使用者要求重錄 fixture | run this workflow |

Record -> Compare 是 fixture lifecycle operation，不是 SIT / Local comparison path。

## Record Path

用 record flag 啟動環境，讓 Mockoon 以 proxy mode forward requests 到 real backend：

`scripts/polaris-env.sh start <company> --vr --record`

接著 capture baseline screenshots，確認 proxy mode 頁面本身正常。

注意：Mockoon CLI proxy mode 不一定自動把 response 寫回 environment JSON。若 runner 尚未支援
auto-record，需 manually request endpoints，將 response 補進 Mockoon environment routes，
或透過後續 automation 改善。

Review fixture file 時檢查：

- Dynamic data，例如 timestamps、session tokens。
- Plain JSON body 卻保留 `Content-Encoding: gzip` header。
- 過大的 responses 是否真的需要錄。
- Missing CSR endpoints。

Record 完成後 stop environment。

## Compare Path

不帶 record flag 重新啟動：

`scripts/polaris-env.sh start <company> --vr`

Replay mode 下跑 Playwright compare。預期結果是 zero-diff：相同 code、相同 fixture data
應產生相同 screenshots。

若有 diff：

| Symptom | Likely cause |
|---|---|
| numbers or text changed | dynamic endpoint 未 capture |
| layout shift | response timing or readiness selector 不穩 |
| grey skeleton / empty section | CSR endpoint missing from fixtures |
| SSR API 500 | gzip header/body mismatch |
| blank page | fixture server port or health check 錯誤 |

Replay mode switch 後必須 full VR pass + human screenshot review。這會抓出 proxy mode fallback
到 SIT 而 replay mode 變 broken 的情況。

## Commit Fixture State

Fixtures 的 source of truth 在 per-epic directory：

`docs-manager/src/content/docs/specs/companies/{company}/{EPIC}/tests/mockoon/`

新 epic 可從前一個 epic 複製 fixture set，刪除不相關 routes，再重錄 API format 已變更的
routes。Product repo 不 commit fixtures。

Shared company mockoon config 只放 proxy mapping 或 env overrides；每個 epic 的 environment
JSON 必須完整獨立。

## Runner Integration

`fixtures.mockoon.start` 接受包含 `*.json` 的 directory。Active epic 由 runtime context
解析，不靠 hardcoded `--epic` flag。

VR normal run 使用 replay mode；只有 fixture update workflow 使用 record mode。

## Edge Cases

| Situation | Handling |
|---|---|
| stash pop conflicts | abort，回報 conflict 與 stash ref |
| forced SIT unreachable | 回報錯誤，詢問是否 fallback Local |
| dev server no hot reload | polling timeout 後 abort，建議重啟 |
| diff > 50% | major diff，手動確認 |
| fixture server fails | warn，無 fixtures 繼續但標記 nondeterministic |
| no `pages[]` | config error，stop |
| test dir missing | create domain tooling directory |

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| recording 後資料仍錯 | dynamic endpoint 被當 static fixture | 移除或重錄 route |
| fixture server says data too recent | CLI version 太舊 | 更新 fixture server CLI |
| SSR hang | Redis、DB、或 required service 未啟動 | 啟動 service，重跑 health check |
| SIT 200 but local 500 | local env 指向不可達 backend | API base URLs route through fixture proxy |
| first page load very slow | SSR cold start | 先 warm up homepage request |
