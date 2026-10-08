import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
// Same harness as overviewCharts.test.mjs: transpile the pure module and import it.
const source = readFileSync(new URL('../src/lib/transactionKinds.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const kinds = await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));

test('labels: kinds, fee types and unknown values', () => {
  assert.equal(kinds.kindLabel('card_purchase'), 'Card purchase');
  assert.equal(kinds.kindLabel('fee', 'top_up'), 'Fee · Card top-up');
  assert.equal(kinds.kindLabel('fee_refund', 'card_issuance'), 'Fee refund · Card issuance');
  assert.equal(kinds.kindLabel('mystery_kind'), 'Mystery kind');
  assert.equal(kinds.kindLabel(null), 'Other');
  assert.deepEqual(kinds.sortKinds(['other', 'fee', 'card_purchase', 'zeta']), ['card_purchase', 'fee', 'other', 'zeta']);
});
test('signs and colours: only real money in or out carries a sign; failed and duplicate rows are struck through', () => {
  assert.equal(kinds.amountSign('in'), '+'); assert.equal(kinds.amountSign('out'), '−'); assert.equal(kinds.amountSign('internal'), '');
  assert.match(kinds.amountClass({ direction: 'in', status: 'completed' }), /emerald/);
  assert.match(kinds.amountClass({ direction: 'out', status: 'failed' }), /line-through/);
  assert.match(kinds.amountClass({ direction: 'out', status: 'completed', isDuplicate: true }), /line-through/);
  assert.match(kinds.amountClass({ direction: 'internal', status: 'completed' }), /slate-500/);
  assert.equal(kinds.directionIcon('internal'), 'pi pi-arrow-right-arrow-left');
});
