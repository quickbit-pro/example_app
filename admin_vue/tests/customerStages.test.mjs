import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
// Transpile the pure modules and import them, like overviewCharts.test.mjs.
async function load(file) {
  const source = readFileSync(new URL(`../src/lib/${file}`, import.meta.url), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
  return import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}
const stages = await load('customerStages.ts');
const definitions = await load('kpiDefinitions.ts');

test('stages match the backend order and reminders match the templates it sends', () => {
  // backend/src/NeoBanking.Api/Admin/AdminCustomerStages.cs Ordered and AdminReminderService.TemplateByStage
  assert.deepEqual(stages.STAGES.map(stage => stage.key), ['signed_up', 'onboarding', 'in_review', 'rejected', 'approved', 'funded', 'carded', 'active', 'dormant']);
  assert.deepEqual(stages.STAGES.filter(stage => stage.reminder).map(stage => stage.key), ['signed_up', 'onboarding', 'approved', 'funded', 'carded', 'dormant']);
  assert.equal(stages.stageLabel('approved'), 'Approved, no money');
  assert.equal(stages.stageLabel('mystery_stage'), 'mystery stage');
  assert.equal(stages.hasReminder('active'), false);
  assert.equal(stages.STAGES.every(stage => stages.STAGE_TONE_CLASS[stage.tone] && stage.description.endsWith('.')), true);
});

test('every KPI definition is filled and the tooltip names its source and freshness', () => {
  for (const [key, text] of Object.entries(definitions.KPI_DEFINITIONS)) assert.ok(text.length > 30, key);
  const info = definitions.kpiInfo('declineRate', 'Figures as of 10:00.');
  assert.match(info, /percentage points/);
  assert.match(info, /Source: provider transactions/);
  assert.match(info, /Figures as of 10:00\.$/);
});
