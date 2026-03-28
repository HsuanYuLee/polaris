# Bash 指令規則

## 核心原則：避免 cd

不要在 Bash 指令中使用 `cd`。改用各工具自帶的 path 參數或絕對路徑。

`cd <path> && <cmd>` 是複合指令，permission pattern 難以維護（`cd * && *`、`cd * && * | *`...），經常觸發權限確認彈窗。單一指令直接 match 簡單 pattern（如 `Bash(git *)`），不會跳確認。

### 替代方案

| 工具 | ❌ 避免 | ✅ 改用 |
|------|--------|--------|
| git | `cd /repo && git status` | `git -C /repo status` |
| pnpm | `cd /repo && pnpm test` | `pnpm -C /repo test` |
| gh | `cd /repo && gh pr list` | `gh pr list --repo owner/repo` |
| node | `cd /repo && node script.js` | `node /repo/script.js` |
| bash | `cd /repo && bash script.sh` | `bash /repo/script.sh` |
| skill scripts | `cd /skill && ./run.sh` | `/full/path/to/skill/run.sh` |

唯一允許 `cd` 的情境：工具完全不支援 path 參數且必須在特定目錄執行（極少見）。

## 不要用 `&&` 串接多條獨立指令

```
# ✅ 好：平行發出多個 Bash tool call
Bash: git -C /repo log --oneline -5
Bash: git -C /repo status
Bash: git -C /repo diff --name-only
```

```
# ❌ 壞：全部串在一起
Bash: git -C /repo log --oneline -5 && git -C /repo status && git -C /repo diff --name-only
```

## Pipe 是可以的

Pipe 算同一條指令，可以正常使用：

```
# ✅ 好
Bash: git -C /repo branch -a | grep -i claude
Bash: gh api repos/org/repo/pulls/123/comments --paginate | python3 -c "..."
Bash: /path/to/fetch.sh --author user | /path/to/check.sh --threshold 2
```

## 判斷標準

| 情境 | 做法 |
|------|------|
| 需要在特定目錄執行 | 用工具的 path 參數（`git -C`、`pnpm -C`、`gh --repo`） |
| 一條指令 + pipe | 直接執行 ✅ |
| 多條獨立指令 | 拆成平行 Bash tool call ✅ |
| 有依賴順序的操作 | 拆成 sequential Bash tool call ✅ |

## 為什麼

settings.json 的 `permissions.allow` 用 glob pattern 匹配指令。
用 `cd` 需要 `cd * && *` 等複合 pattern，多段組合 pattern 難維護且經常漏配。
用工具的 path 參數讓指令保持單一，match 簡單 pattern（如 `git *`、`pnpm *`）。
