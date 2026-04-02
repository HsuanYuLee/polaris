# Slack Message Formatting Rules

Shared reference for all skills that send Slack messages. Covers common formatting pitfalls in Slack's mrkdwn syntax.

## Consumers

All skills that call `slack_send_message` or `mcp__claude_ai_Slack__slack_send_message`.

## URL Formatting

**URL 後面必須換行**。中文或其他非空白字元緊接 URL 會被 Slack parser 吃進連結文字：

```
❌ 錯誤：PR 已建立 <https://github.com/org/repo/pull/123|#123>請幫忙 review
                                                              ^^^^^^^^
                                                              「請幫忙 review」會變成連結的一部分

✅ 正確：PR 已建立 <https://github.com/org/repo/pull/123|#123>
請幫忙 review
```

規則：
- 裸 URL 或 `<url|text>` 格式連結後，若下一個字元不是空白或換行 → **插入換行**
- 連結前的文字不受影響，只有**後面**會吃字

## Markdown 差異

Slack mrkdwn 不是 GitHub Flavored Markdown。常見陷阱：

| 你想要的 | GitHub MD | Slack mrkdwn |
|---------|-----------|-------------|
| **粗體** | `**text**` | `*text*` |
| *斜體* | `*text*` | `_text_` |
| 標題 | `### heading` | 不支援，用 `*bold*` 代替 |
| 分隔線 | `---` | 不支援（會被拒絕發送），用 `────────────────` (unicode box drawing) |
| 代碼區塊 | ` ```code``` ` | 相同 ✅ |
| 引用 | `> text` | 相同 ✅ |

## Message Length

Slack 訊息上限 4000 字元。超過時：
- 截斷並附上 `（... 共 N 項，顯示前 M 項）`
- 或拆成多條訊息（thread reply）
