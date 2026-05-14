#!/usr/bin/env node
import assert from 'node:assert/strict';
import { detectStackedDeliveryLane } from '../detect-stacked-delivery-lane.mjs';

function task(id, extra = {}) {
  return {
    id,
    independent_release: true,
    independent_revert: true,
    strong_coupling: false,
    ...extra,
  };
}

function run() {
  const t3 = detectStackedDeliveryLane({
    tasks: [
      task('T3e', { aggregation_branch: true }),
      task('T3f', { base: 'T3e', depends_on: ['T3e'] }),
      task('T3g', { base: 'T3f', depends_on: ['T3f'] }),
      task('T3h', { base: 'T3g', depends_on: ['T3g'] }),
      task('T3i', { base: 'T3h', depends_on: ['T3h'] }),
      task('T3j', { base: 'T3i', depends_on: ['T3i'] }),
      task('T3k', { base: 'T3j', depends_on: ['T3j'] }),
    ],
  });
  assert.equal(t3.status, 'required');
  assert.equal(t3.lanes[0].feat_task, 'T3e');

  const t8 = detectStackedDeliveryLane({
    tasks: [
      task('T8a', { aggregation_branch: true }),
      task('T8b', { base: 'T8a', depends_on: ['T8a'] }),
      task('T8c', { base: 'T8b', depends_on: ['T8b'] }),
      task('T8d', { base: 'T8c', depends_on: ['T8c'] }),
      task('T8e', { base: 'T8d', depends_on: ['T8d'] }),
      task('T8f', { base: 'T8e', depends_on: ['T8e'] }),
    ],
  });
  assert.equal(t8.status, 'required');
  assert.deepEqual(t8.lanes[0].tasks, ['T8a', 'T8b', 'T8c', 'T8d', 'T8e', 'T8f']);

  const twoTaskFlow = detectStackedDeliveryLane({
    tasks: [
      task('T1'),
      task('T2', { depends_on: ['T1'] }),
    ],
  });
  assert.equal(twoTaskFlow.status, 'ok');
  assert.equal(twoTaskFlow.lanes.length, 0);

  const advisoryFromNamesOnly = detectStackedDeliveryLane({
    tasks: [
      { id: 'T4a' },
      { id: 'T4b' },
      { id: 'T4c' },
    ],
  });
  assert.equal(advisoryFromNamesOnly.status, 'advisory');
  assert.equal(advisoryFromNamesOnly.lanes[0].recommendation, 'review_sibling_epic_before_preview');

  const overridden = detectStackedDeliveryLane({
    decision: {
      override: true,
      reason: 'PM explicitly keeps this lane in one Epic for a short-lived patch train.',
    },
    tasks: [
      task('T9a', { aggregation_branch: true }),
      task('T9b', { base: 'T9a', depends_on: ['T9a'] }),
      task('T9c', { base: 'T9b', depends_on: ['T9b'] }),
    ],
  });
  assert.equal(overridden.status, 'overridden');
  assert.equal(overridden.override.accepted, true);
  assert.match(overridden.summary, /overridden/i);

  console.log('PASS detect-stacked-delivery-lane selftest');
}

run();
