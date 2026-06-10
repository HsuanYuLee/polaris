# Changeset / Bump 慣例

Polaris framework workspace 的版號與 CHANGELOG 由 changesets 驅動：作者在 PR 內新增一個
changeset 檔（人寫的 payload），壓版本步驟（`mise run release:version`，見 DP-295-T2）跑
`changeset version` 機械收斂出版號、VERSION mirror 與 CHANGELOG 區塊。CHANGELOG 區塊由本
workspace 的 custom formatter `.changeset/changelog-keepachangelog.cjs` 產生，輸出符合
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 格式。

本 reference 是作者寫 changeset summary 與壓版本機制的 single source of truth；除 Migration
Boundaries 明列的過渡窗口外，**不得**手動編輯 VERSION 或 CHANGELOG。

## 何時要寫 changeset

任何含**行為改動**（會改變 framework 行為的 code / rules / skills / scripts / hooks /
validators / delivery semantics）的 PR 都必須附自己的 changeset 檔。純文件 typo、純
formatting、generated artifact 等無行為意涵的修改不需要。release-readiness gate
（DP-295-T4）會在「有行為改動但缺 changeset」時 block。

## 怎麼寫 changeset

```bash
pnpm exec changeset
```

或直接在 `.changeset/` 下手寫一個 `<task>.md`：

```markdown
---
"polaris-framework-workspace": patch
---

feat: 一句話描述 user-facing 影響
```

- **bump level**（`patch` / `minor` / `major`）寫在 frontmatter，依 semver 判斷：
  - `major`：破壞性變更（移除 / 改變既有 contract、外部使用者需要改動）。
  - `minor`：新增功能 / 新 gate / 新 skill（向後相容）。
  - `patch`：bug fix、文件、內部重構、依賴調整。
- **summary 第一行**用 Conventional Commits 前綴（見下表），formatter 依此分到 Keep a
  Changelog section。summary 要寫清楚 **user-facing 影響**，因為 CHANGELOG 豐富度完全取決
  於這句話（DP-295 R1 風險）。
- **一 PR 一 changeset**（對應自己的 task）；從別的 task branch 切出的 branch 繼承到的
  changeset 要在開 PR 前刪掉，只留自己的。

## Conventional Commits type → Keep a Changelog section 對應

formatter `.changeset/changelog-keepachangelog.cjs` 解析 summary 第一行的
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) 前綴
（`<type>` 或 `<type>(<scope>)`，可帶 `!`），對應到 Keep a Changelog section：

| Conventional Commits type | Keep a Changelog section |
|---------------------------|--------------------------|
| `feat`                    | Added                    |
| `fix`                     | Fixed                    |
| `perf`                    | Changed                  |
| `refactor`                | Changed                  |
| `docs`                    | Changed                  |
| `style`                   | Changed                  |
| `test`                    | Changed                  |
| `chore`                   | Changed                  |
| `build`                   | Changed                  |
| `ci`                      | Changed                  |
| `revert`                  | Removed                  |
| `security`                | Security                 |
| `deprecate` / `deprecated`| Deprecated               |
| 無前綴 / 無法辨識         | Changed（fallback）      |

Keep a Changelog 的六個 section 為 Added、Changed、Deprecated、Removed、Fixed、Security
（[1.1.0 spec](https://keepachangelog.com/en/1.1.0/)）。壓版本後產出的區塊形如：

```markdown
## [X.Y.Z] - 2026-06-09

### Added

- 一句話描述 user-facing 影響

### Fixed

- 另一個修正的 user-facing 影響
```

## 壓版本流程（摘要）

1. PR 內帶 changeset 檔；reviewer 看 summary 判斷 user-facing 影響是否寫清楚。
2. 壓版本步驟（`mise run release:version`）跑 `changeset version`：
   - bump `package.json` 的 `version`（版號 SoT）。
   - 同步 `VERSION` mirror。
   - 用本 formatter 收斂 CHANGELOG 區塊。
   - 刪除已消費的 changeset 檔。
3. 無 pending changeset 時為 no-op（不靜默升版）。
4. 壓版本必須在 PR 被驗證的 HEAD **之前**完成（不得產生事後 release commit 使 evidence
   stale，DP-295 AC-NEG5）。

## Migration Boundaries

DP-295 落地前，VERSION / CHANGELOG 由人工編輯。落地後唯一合法路徑是 changeset 驅動的壓版本
步驟。過渡期間若需手動修補既有 CHANGELOG 歷史區塊，限定在 DP-295 owning plan 明列的窗口內，
且不得寫進 steady-state prose / gate 當常規路徑。
