# Unit Test Review Checklist

## 1. 測試結構與組織

- **AAA Pattern**：每個測試是否清楚區分 Arrange、Act、Assert 三階段？混在一起會降低可讀性。
- **描述性測試名稱**：`it`/`test` 的描述是否能讓人不看程式碼就知道測什麼？
  - 好：`it('當 locale 為 vi 時應正規化為 vi-vn')`
  - 差：`it('test case 1')`, `it('works')`
- **describe 分組**：是否依功能或場景合理分組？巢狀層數是否過深（>3 層需警覺）？
- **一測試一概念**：單一測試是否只驗證一個行為？多個不相關的 assert 應拆分。

## 2. 測試品質與隔離

- **測試獨立性**：測試之間是否有隱性依賴（共享可變狀態、依賴執行順序）？
- **Setup/Teardown 正確性**：
  - Pinia store 測試：`beforeEach` 中是否有 `setActivePinia(createPinia())`？
  - Mock 重置：`beforeEach` 中是否有 `vi.clearAllMocks()`？
  - 可變的 mock 資料是否在每次測試前重置？
- **Factory function**：重複的 mock 設定是否抽成 factory（如 `createRouteMock()`）？

## 3. 斷言品質

- **Matcher 精確性**：
  - `toBe`：原始值或同一參考
  - `toEqual`：深層相等（忽略 undefined 屬性）
  - `toStrictEqual`：嚴格深層相等（含 undefined 屬性與型別檢查）
  - 使用 `toHaveBeenCalledWith` 而非只檢查 `toHaveBeenCalled`
- **測試行為而非實作**：斷言是否關注輸出/副作用，而非內部狀態或私有方法？
- **邊界案例覆蓋**：是否涵蓋 `null`、`undefined`、空陣列 `[]`、空字串 `''`、error path？
- **防偽陽性**：
  - 無斷言的測試（永遠通過）
  - 只測試 mock 本身而非 SUT 的行為
  - 缺少 `await` 導致 promise 未被驗證
  - `toEqual` 用在應該用 `toStrictEqual` 的場景

## 4. Mocking 最佳實踐

### Mock 邊界原則

核心觀念：**每一層只測自己的邏輯，mock/stub 的對象 = 這個 unit 的邊界以外的東西**。

| 測試層級 | 測試什麼 | Mock/Stub 什麼 |
|---|---|---|
| 元件 (Component) | 渲染邏輯、事件處理 | stub 子元件 + mock composable |
| Composable | 運算邏輯、狀態轉換 | mock store（或用 `createPinia`） |
| Store (Pinia) | state/action 邏輯 | mock API call |

**Mock 邊界切在直接依賴，不多也不少**：
- 不要跳過直接依賴去 mock 更深層的東西（例如：元件測試跳過 composable 直接 mock store）
- 這會導致中間層（composable）的邏輯完全沒被覆蓋，形成覆蓋空洞

### 三種 Mock 策略比較（元件測試 Pinia 相關邏輯）

| | A: Mock Store | B: createPinia | C: Mock Composable（建議） |
|---|---|---|---|
| **做法** | `vi.mock` pinia store | `createTestingPinia()` 注入 | `vi.mock` composable |
| **Mock 邊界** | 跳過 composable 直接 mock store | 使用真實 store | 在元件的直接依賴處 mock |
| **故障定位** | 差 | 中 | 好 |
| **適用場景** | 不建議用於元件測試 | composable/store 自身的 unit test | **元件測試首選** |

> 元件測試採用策略 C（Mock Composable）。`createPinia` / `createTestingPinia` 留給 composable 或 store 自身的 unit test。

### 一般 Mocking 規則

- **邊界 mock 原則**：只 mock 系統邊界（API call、router、瀏覽器 API），不 mock SUT 本身的方法。
- **vi.hoisted pattern**：需要在不同測試中變更 mock 實作時：
  ```ts
  const { myMock } = vi.hoisted(() => ({
    myMock: vi.fn(() => defaultValue),
  }));
  ```
- **mockNuxtImport pattern**（apps 層）：mock Nuxt auto-import 的 composable。
  ```ts
  mockNuxtImport('useRoute', () => useRouteMock);
  ```
- **vi.mock('#imports') pattern**（packages 層）：packages 無法使用 `mockNuxtImport`，改用直接 mock。
- **動態 import 重置**：需要在不同測試間重置模組狀態時，使用 `await import('../module')` 搭配 `vi.resetModules()`。
- **避免 over-mock**：單一測試檔超過 5 個 mock 時，考慮是否該改為 integration test 或重構 SUT。

## 5. Anti-Patterns 速查表

| Anti-Pattern | 嚴重度 | 說明 |
|---|---|---|
| 無斷言測試 | CRITICAL | 測試沒有任何 `expect`，永遠通過 |
| 測試框架行為 | HIGH | 驗證 `vi.fn()` 本身的行為而非 SUT |
| Snapshot 濫用 | HIGH | 對大型物件或經常變動的結構使用 snapshot |
| 實作耦合 | HIGH | 斷言內部狀態、私有方法或呼叫順序 |
| 缺少 await | HIGH | async 操作未 await，斷言在 promise resolve 前執行 |
| 測試錯誤層級的邏輯 | HIGH | 在元件測試中驗證 composable/store 的行為 |
| Copy-paste 測試 | MEDIUM | 大量重複程式碼，應用 `it.each` 或 factory |
| Magic number | MEDIUM | 斷言中出現未解釋的數字或字串 |
| 條件邏輯 | MEDIUM | 測試中包含 `if/else`、`try/catch`、迴圈 |
| 測試間相依 | MEDIUM | 測試 A 的結果影響測試 B（共享可變狀態） |
| 過度測試 getter | LOW | 純 getter/computed 只是回傳值，無需逐一測試 |
| 註解掉的測試 | LOW | `it.skip` 或被註解的測試案例，應刪除或修復 |
| 無故 suppress console | INFO | `vi.spyOn(console, 'error')` 但未斷言，隱藏潛在錯誤 |

## 6. Vue/Nuxt 專屬檢查

- **mount vs shallowMount**：
  - `shallowMount`：單元測試首選，隔離子元件
  - `mount`：需要測試子元件互動時使用
- **nextTick / flushPromises**：
  - DOM 更新後的斷言是否有 `await nextTick()`？
  - 非同步操作（API call）後是否有 `await flushPromises()`？
- **Pinia store 測試 pattern**：
  - 是否在 `beforeEach` 建立新的 pinia instance？
  - **`createPinia` vs `vi.mock` 使用場景**：
    - `createPinia` / `createTestingPinia`：用於 **composable 或 store 自身的 unit test**
    - `vi.mock`：用於 **元件測試** mock composable/store
    - **不要在同一檔案混用** `createPinia` 和 `vi.mock` 同一個 store
- **環境設定**：
  - `vitest.config.ts` 中 `environment: 'nuxt'` 用於需要 Nuxt context 的測試
  - 純邏輯函式可用 `environment: 'node'` 加速
- **全域 mock 意識**：`vitest.setup.ts` 已全域 mock 了 `mixpanel`、`dataLayer`、`sessionStorage`、`localStorage`、`console`、`DcsService`，測試中不需重複 mock。

## 7. 覆蓋率考量

- **有意義的覆蓋 vs 數字灌水**：只為提高覆蓋率而寫的測試（無斷言、只 import）沒有價值。
- **分支覆蓋優先**：`if/else`、`switch`、`?.`、`??` 的各條路徑是否都有測試？
- **未測試路徑檢查**：對照 SUT 原始碼，列出缺少測試的重要分支或 error handling。
