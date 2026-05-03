# TDD Loop

工程預設採用 Red-Green-Refactor。這不是可選風格，而是降低 patch drift、coverage 漏洞、review 回補成本的主施工節奏。

## 1. 基本循環

| 階段 | 要做什麼 | 完成判定 |
|------|----------|----------|
| RED | 寫一個會失敗的測試 | 測試真的 fail，且 fail 在你預期的位置 |
| GREEN | 寫最少的程式碼讓它過 | 新增測試通過；不要順手擴 scope |
| REFACTOR | 在綠燈下整理 code | 全部測試仍綠 |

規則：
- 一次只推進一個行為
- 一次只新增一個 failing test
- GREEN 階段只做讓目前這個測試過的最小改動
- REFACTOR 不改行為，只改善結構

## 2. 嚴格模式

明確要求 TDD、或 repo 有 patch coverage gate 時，採嚴格模式：

1. 先列 test case 清單，順序由簡到難
2. 每輪只拿一個 case 進循環
3. RED 必須真的執行，不能腦補理論上會 fail
4. GREEN 後跑完整相關測試，不只跑單一 assertion
5. 每輪結束記錄：這輪測了什麼、加了什麼、是否 refactor

建議回報格式：

```text
Cycle 1
RED: it('returns empty array when no results match')
GREEN: added early return [] for empty input
REFACTOR: none
TESTS: 1 passed, 0 failed
```

## 3. 什麼適合 TDD

| 類別 | 做法 |
|------|------|
| util / composable / store / API transformer / 複雜條件分支 | 直接走 TDD |
| config / 純 template / 純 style / type definition | 可不做嚴格 TDD，但要說明原因 |

若 repo 有 Codecov patch gate，除了本質上難以測試的檔案外，不要用只改一行當豁免理由。

## 4. 好測試的最低標準

- 一個 test 只驗一件事
- 名字描述行為，不要用 `test1`、`works`
- 測真實邏輯，不要只測 mock 自己
- assertion 要對準使用者可觀察行為

## 5. 反模式

- Batch mode：先把所有 test 寫完，再一次補實作
- Skip RED：先寫 code，再補測試
- Gold plating：GREEN 時順手做額外優化或加功能
- Mega cycle：一輪做太久，表示行為切太大

## 6. 交付關係

TDD 只保證開發節奏正確，不取代交付 gate。完成後仍要跑：

1. task.md 宣告的 `test_command`
2. workspace-owned `polaris-config/{project}/generated-scripts/ci-local.sh`（若存在；透過 `scripts/ci-local-run.sh --repo <repo>` 執行）
3. `scripts/run-verify-command.sh`

也就是：TDD 不是交付完成，TDD 只是把你帶到比較不會在交付 gate 爆炸的位置。
