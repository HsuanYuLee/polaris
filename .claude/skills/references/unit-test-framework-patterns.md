---
title: "Unit Test Framework Patterns"
description: "unit-test 的 Jest/Vitest/Vue component/store/composable/mock/async 測試 pattern 與範例。"
---

# Framework Pattern Contract

這份 reference 收斂常用 Jest / Vitest / Vue 測試 patterns。優先跟隨 repo 既有測試風格。

## Basic Structure

```ts
import { describe, expect, it, beforeEach } from 'vitest';
import { targetFunction } from '../targetModule';

describe('targetFunction', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns expected result for valid input', () => {
    expect(targetFunction('valid-input')).toBe('expected-output');
  });
});
```

Jest 專案使用 `jest.clearAllMocks()` 與 `jest.fn()`；Vitest 專案使用 `vi.clearAllMocks()` 與
`vi.fn()`。

## Vue Component

```ts
import { mount } from '@vue/test-utils';
import MyComponent from '../MyComponent.vue';

it('emits submit when button is clicked', async () => {
  const wrapper = mount(MyComponent);
  await wrapper.find('button').trigger('click');
  expect(wrapper.emitted('submit')).toBeTruthy();
});
```

測 props、emits、user-visible render。不要測 private methods。

## Store / Composable

Store 測 state transitions、mutations/actions result。Composable 測 public returned API 與 side
effects。外部 API、router、time、storage 可 mock；source module 的核心邏輯不要 mock。

## Mock Patterns

Mock dependency boundary：

```ts
vi.mock('../api/product', () => ({
  getProduct: vi.fn().mockResolvedValue({ id: 1, name: 'Test' }),
}));
```

同一 dependency 在不同 tests 需要不同結果時，在 `beforeEach` reset mock state。

Router mock 只保留測試需要的 params/query/push/replace。

## Async

Async component / composable tests 要等待 pending promises 或 next tick：

```ts
await wrapper.vm.$nextTick();
await flushPromises();
```

Assertion 放在 async side effect 完成後。
