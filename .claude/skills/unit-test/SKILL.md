---
name: unit-test
description: >
  Project-aware unit testing guide with mock patterns and best practices.
  Auto-detects test framework (Jest/Vitest) and provides appropriate examples.
  Use when: (1) writing or fixing unit tests, (2) user says "寫測試", "write test",
  "補測試", "add test", (3) user encounters mock patterns or test failures,
  (4) user asks how to test a composable, component, or store, (5) user says
  "mock imports", "test store", "怎麼測", "測試怎麼寫".
metadata:
  author: Polaris
  version: 1.0.0
---

# Unit Test Guide

## 0. Project Detection

| 條件 | 測試框架 | 測試指令 | 設定檔 |
|------|---------|---------|--------|
| 存在 `vitest.config.ts` | Vitest | `npx vitest run` | vitest.config.ts |
| 存在 `jest.config.js` | Jest | `npx jest` | jest.config.js |

> 如果某專案有專屬的 `unit-test` skill（覆蓋此通用版本），應從該專案目錄使用。

## 1. TDD 紀律：先寫測試，再寫實作

測試不是事後補的文件，是開發的一部分。

### Red-Green-Refactor 循環

| 階段 | 做什麼 | 驗證 |
|------|--------|------|
| **RED** | 寫一個會失敗的測試 | 跑測試，確認 assertion fail |
| **GREEN** | 寫最少的程式碼讓測試通過 | 跑測試，確認通過 |
| **REFACTOR** | 改善程式碼品質 | 跑測試，確認仍通過 |

### 好測試的特徵

- **一個測試只測一件事** — 名字裡有 "and" 就該拆
- **名字描述行為** — `it('returns empty array when no packages match')` 而非 `it('test1')`
- **測真實邏輯** — import 並執行 source function，不是只操作 mock 物件

## 2. Jest 測試模式（Vue 2.7 專案）

### 2.1 基本測試結構

```ts
import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { targetFunction } from '../targetModule';

describe('targetFunction', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return expected result for valid input', () => {
    const result = targetFunction('valid-input');
    expect(result).toBe('expected-output');
  });

  it('should handle edge case', () => {
    const result = targetFunction('');
    expect(result).toBeNull();
  });
});
```

### 2.2 Vue Component 測試

```ts
import { mount, shallowMount } from '@vue/test-utils';
import MyComponent from '../MyComponent.vue';

describe('MyComponent', () => {
  it('renders correctly with props', () => {
    const wrapper = mount(MyComponent, {
      props: {
        title: 'Test Title',
        isVisible: true,
      },
    });

    expect(wrapper.text()).toContain('Test Title');
    expect(wrapper.find('.component').exists()).toBe(true);
  });

  it('emits event on button click', async () => {
    const wrapper = mount(MyComponent);
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('submit')).toBeTruthy();
  });
});
```

### 2.3 Vuex Store 測試

```ts
import { createStore } from 'vuex';
import myModule from '../store/modules/myModule';

describe('myModule store', () => {
  let store;

  beforeEach(() => {
    store = createStore({
      modules: {
        myModule: { ...myModule, namespaced: true },
      },
    });
  });

  it('initial state is correct', () => {
    expect(store.state.myModule.items).toEqual([]);
    expect(store.state.myModule.loading).toBe(false);
  });

  it('mutation updates state', () => {
    store.commit('myModule/SET_ITEMS', [{ id: 1 }]);
    expect(store.state.myModule.items).toEqual([{ id: 1 }]);
  });

  it('action dispatches correctly', async () => {
    await store.dispatch('myModule/fetchItems');
    expect(store.state.myModule.items.length).toBeGreaterThan(0);
  });
});
```

### 2.4 Mock 技巧（Jest）

```ts
// Mock 整個模組
jest.mock('../api/product', () => ({
  getProduct: jest.fn().mockResolvedValue({ id: 1, name: 'Test' }),
}));

// Mock 特定函式
import { getProduct } from '../api/product';
const mockGetProduct = getProduct as jest.MockedFunction<typeof getProduct>;

// 在不同測試中改變 mock 行為
it('handles API error', async () => {
  mockGetProduct.mockRejectedValueOnce(new Error('API Error'));
  // ...
});

// Mock 外部套件
jest.mock('lodash-es', () => ({
  ...jest.requireActual('lodash-es'),
  debounce: (fn) => fn, // 移除 debounce delay
}));

// Mock Vue Router
jest.mock('vue-router', () => ({
  useRoute: jest.fn(() => ({
    params: { id: '123' },
    query: {},
  })),
  useRouter: jest.fn(() => ({
    push: jest.fn(),
    replace: jest.fn(),
  })),
}));
```

### 2.5 Async 測試

```ts
it('fetches data on mount', async () => {
  const wrapper = mount(MyComponent);

  // 等待所有 pending promises
  await wrapper.vm.$nextTick();
  // 或
  await flushPromises();

  expect(wrapper.find('.data').text()).toBe('loaded data');
});
```

## 3. 測試策略

### 需要寫測試的

| 類型 | 測試位置 | 說明 |
|------|---------|------|
| Utility function | 同目錄 `.test.ts` | 純函式，最容易測 |
| Composable（pure logic） | 同目錄 `.test.ts` | Mock 外部依賴 |
| Store（mutations/actions） | 同目錄 `.test.ts` | 驗證狀態變更 |
| Component（互動邏輯） | 同目錄 `.test.ts` | 驗證 props/emits/render |

### 不需要寫測試的

- 純型別定義（`types.ts`, `*.d.ts`）
- 常數檔（`constants.ts`）
- Barrel exports（`index.ts`）
- 純 template/style 變更
- 設定檔（`*.config.ts`）

## 4. Coverage

### 必須覆蓋

- 每個 public export 至少一個測試（happy path）
- 主要分支路徑：null/undefined 處理、條件判斷
- 邊界情況：空陣列、空字串、零值

### 建議覆蓋

- 錯誤處理：異常輸入、API 錯誤
- 型別安全：回傳物件符合預期結構

### 不需要覆蓋

- 第三方套件的內部行為
- 純 CSS/樣式變更
- 環境設定檔

## Do / Don't

- Do: 先寫測試再寫實作（TDD）
- Do: 測真實邏輯，import source function 並執行
- Do: 每個測試獨立，不依賴其他測試的執行順序
- Do: beforeEach 清除 mock 狀態
- Don't: 產生只驗證 mock 回傳值的無效測試
- Don't: 測試實作細節（private methods）
- Don't: 在測試中硬編碼大量 mock data，應抽到 fixture/factory
