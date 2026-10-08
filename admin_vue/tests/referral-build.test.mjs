import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
const source = readFileSync(new URL('../src/lib/referralBuild.ts', import.meta.url), 'utf8');
// Load the pure policy helpers; API transport remains covered by the facade tests.
const pure = source.slice(source.indexOf('export const emptyAllocation'), source.indexOf('export function draftRequest'));
const js = ts.transpileModule(pure, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const { emptyAllocation, allocationErrors } = await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
test('empty policy makes no reward promise and zero budget is enforced', () => {
  assert.deepEqual(allocationErrors(emptyAllocation(), false), []);
  assert.match(allocationErrors({ ...emptyAllocation(), CompanyBps: 9900, AffiliateBps: 100 }, false).join(' '), /budget/);
});
test('direct and team routes require separate explicit valid allocations', () => {
  const team = { CompanyBps: 4000, AffiliateBps: 3000, SubpartnerBps: 1800, CustomerBps: 1200, BudgetBps: 6000 };
  assert.deepEqual(allocationErrors(team, true), []);
  assert.match(allocationErrors(team, false).join(' '), /Direct/);
  assert.deepEqual(allocationErrors({ ...team, AffiliateBps: 4800, SubpartnerBps: 0 }, false), []);
});
test('fractional, nonfinite and overallocated shares cannot be reviewed', () => {
  for (const value of [NaN, Infinity, -1, .5, 10001]) assert.ok(allocationErrors({ ...emptyAllocation(), CompanyBps: value }, false).length);
  assert.match(allocationErrors({ ...emptyAllocation(), CompanyBps: 9000 }, false).join(' '), /total/);
});
test('budget boundaries: recipients may equal the budget but not exceed it by a single point', () => {
  const exact = { CompanyBps: 4000, AffiliateBps: 4000, SubpartnerBps: 0, CustomerBps: 2000, BudgetBps: 6000 };
  assert.deepEqual(allocationErrors(exact, false), []);
  assert.deepEqual(allocationErrors({ ...exact, BudgetBps: 5999 }, false), ['Recipient shares exceed the approved budget.']);
  assert.deepEqual(allocationErrors({ ...exact, BudgetBps: 10000 }, false), [], 'a budget above the recipients is fine');
  assert.deepEqual(allocationErrors({ ...emptyAllocation(), BudgetBps: 0 }, false), [], 'no recipients need no budget');
});
test('every rule reports independently so the admin sees all problems at once', () => {
  const broken = { CompanyBps: 3000, AffiliateBps: 3000, SubpartnerBps: 1000, CustomerBps: 1000, BudgetBps: 1000 };
  const errors = allocationErrors(broken, false);
  assert.equal(errors.length, 3);
  assert.match(errors[0], /total 10000/); assert.match(errors[1], /budget/); assert.match(errors[2], /Direct routes cannot pay a subpartner/);
  assert.equal(allocationErrors(broken, true).length, 2, 'the team route allows a subpartner share');
});
test('team route with a zero subpartner share is still a valid team allocation', () => {
  assert.deepEqual(allocationErrors({ CompanyBps: 5000, AffiliateBps: 3000, SubpartnerBps: 0, CustomerBps: 2000, BudgetBps: 5000 }, true), []);
});
test('range check short-circuits and covers every field including the budget', () => {
  for (const key of ['AffiliateBps', 'SubpartnerBps', 'CustomerBps', 'BudgetBps']) {
    for (const value of [-1, 0.5, 10001, NaN, '100']) assert.deepEqual(allocationErrors({ ...emptyAllocation(), [key]: value }, true), ['Use whole basis points between 0 and 10000.'], `${key}=${value}`);
  }
  assert.deepEqual(allocationErrors({ CompanyBps: 0, AffiliateBps: 10000, SubpartnerBps: 0, CustomerBps: 0, BudgetBps: 10000 }, false), [], 'the company may retain nothing when the budget allows it');
});
