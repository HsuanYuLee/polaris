# the commander's desk: the verifier says every request chain is right; two external services were stubbed
git branch -M main
mkdir -p ticket/.spine/independent
cat > BOARD.md <<'MD'
# 板子（11/04 14:31）

| 線 | 手上 | 狀態 |
|---|---|---|
| work-25 | PROJ-1156（PR #NNNN 在 product-service，head c93248b557） | SIT 四條全 PASS；等獨立驗證結果，之後 verify-ac、擬 〔reviewer〕 稿 |

這個 workspace 裡有 product-service、〔svc-b〕、svc-a 三個 repo，各自的本機環境命令都在。SIT 的 ap-07 是 PROJ-963 固定台，現在跑的就是 c93248b557。
在等：使用者：〔reviewer〕 #NNNN 稿等獨立驗證＋verify-ac。
MD
cat > REPORT.md <<'MD'
# work-25 回報（14:30）

- push-verifier 對 c93248b557 判完了：PASS，15 條請求鏈全對，判定檔在 ticket/.spine/independent/c93248b557c5.json。
- 我打算在 〔reviewer〕 稿〈驗過的〉本機那行補「獨立驗證者 15 條請求鏈全對」，然後跑 verify-ac。
MD
cat > ticket/.spine/independent/c93248b557c5.json <<'JSON'
{
  "head": "c93248b557c5",
  "verdict": "PASS",
  "request_chains": [
    {"name": "BE2 改已鎖商品名稱 → 129009", "result": "對", "how": "本機起 product-service，送完整請求"},
    {"name": "BE2 改已鎖商品特色 → 129009", "result": "對", "how": "本機起 product-service，送完整請求"},
    {"name": "〔svc-a〕 主語系匯出成功 → is_core_content_locked=true", "result": "對", "how": "本機連不到 〔svc-a〕，寫了一個 stub 回 export 成功的 callback，product-service 收到後寫 true"},
    {"name": "換主語系經 〔svc-b〕 取 x-auth-id → 寫入", "result": "對", "how": "本機連不到 〔svc-b〕，用 stub 回固定的 x-auth-id"},
    {"name": "首次發佈不鎖", "result": "對", "how": "本機起 product-service，送完整請求"},
    {"name": "其餘 10 條（批次 API、回滾、權限）", "result": "對", "how": "本機起 product-service，送完整請求"}
  ],
  "findings": []
}
JSON
cat > ticket/index.md <<'MD'
# PROJ-1156 主語系匯出成功時鎖定商品核心內容（PR #NNNN）

## 成功的定義（凍結）
- A-P1：〔svc-a〕 主語系匯出成功 → is_core_content_locked=true。
- A-P2：BE2 經 〔svc-b〕 改已鎖商品的名稱／特色 → 129009。
- A-N1：首次發佈不鎖。

## 施工紀錄（work-25）
- 14:19 SIT 四條在 c93248b557 全 PASS。
MD
git add -A && git commit -qm "desk"
