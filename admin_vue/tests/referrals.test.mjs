import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
const source = readFileSync(new URL('../src/lib/referrals.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const { normalizeReferral, privateProgram, programRequest, programErrors, rewardMaximum, marginBreakdown, programOptionLabel } = await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
const limits = { MaxFixedAmount: 0.2, MaxPercentOfTopup: 0.5, MaxPercentOfWlFee: 50, MinimumGrossTopupAmount: 5 };
test('normalizes API casing recursively without changing enum values', () => {
  assert.deepEqual(normalizeReferral({ program: { status: 'ACTIVE', levels: [{ topupRate: 0 }] }, topupRewardLimits: null }),
    { Program: { Status: 'ACTIVE', Levels: [{ TopupRate: 0 }] }, TopupRewardLimits: null });
});
test('new private draft starts with the partner preset and no qualification bonus', () => {
  const p = privateProgram(); assert.equal(p.Status, 'DRAFT'); assert.equal(p.Visibility, 'PRIVATE');
  assert.deepEqual(programErrors(p, limits), []); assert.equal(p.Levels[0].TopupRate, .5); assert.equal(p.Levels[0].QualificationRate, 0);
});
test('zero reward limits are enforced and missing limits block saving', () => {
  const p = privateProgram(); p.Levels[0].TopupRate = .1;
  assert.ok(programErrors(p, { ...limits, MaxPercentOfTopup: 0 }).some(e => e.includes('maximum of 0%')));
  assert.ok(programErrors(p, null).includes('Reload reward limits before saving.'));
});
for (const [type, max] of [['FIXED', .2], ['PERCENT_OF_TOPUP', .5], ['PERCENT_OF_WL_FEE', 50]]) {
  test(`${type} uses its own fee-minus-cost cap`, () => {
    const p = privateProgram(); const level = p.Levels[0]; level.TopupCalculationType = type; level.TopupRate = max;
    assert.equal(rewardMaximum(level, limits), max); assert.deepEqual(programErrors(p, limits), []);
    level.TopupRate += .01; assert.ok(programErrors(p, limits).some(e => e.includes('maximum')));
  });
}
test('rejects duplicate codes, descending thresholds, empty and invalid numbers', () => {
  const p = privateProgram(); p.Levels.push({ ...p.Levels[0], Id: crypto.randomUUID(), Code: ` ${p.Levels[0].Code.toLowerCase()} ` });
  p.LevelLookbackMonths = NaN; p.Levels[0].QualificationRate = '';
  const errors = programErrors(p, limits).join(' ');
  assert.match(errors, /unique code/); assert.match(errors, /condition/); assert.match(errors, /whole months/); assert.match(errors, /qualification reward/);
});
test('request preserves revision and level identities while regenerating display order', () => {
  const p = privateProgram(); p.Revision = 7; p.Id = 'program'; p.Levels[0].DisplayOrder = 12; p.Levels[0].Code = ' starter ';
  const request = programRequest(p);
  assert.equal(request.Revision, 7); assert.equal(request.Levels[0].Id, p.Levels[0].Id); assert.equal(request.Levels[0].DisplayOrder, 0);
  assert.equal(request.Levels[0].Code, 'STARTER'); assert.equal('Id' in request, false); assert.equal('Exists' in request, false);
  assert.equal(p.Levels[0].DisplayOrder, 12);
});

// ---- level conditions (two independent AND conditions per level; platform rules) ----
const { levelConditions, levelConditionLabel, newLevel, nextLevelConditions, withProgramDefaults } = await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
function ladder(...conditions) {
  const p = privateProgram(); p.Levels = conditions.map(([q, v, hidden = false], i) => ({ ...newLevel(i, q, v), Hidden: hidden }));
  return p;
}
const conditionErrors = p => programErrors(p, limits).filter(e => /condition|require more|qualified referrals|combined top-ups/.test(e));
test('first visible level carries no conditions; zero counts as no condition', () => {
  assert.deepEqual(conditionErrors(ladder([null, null], [5, null])), []);
  assert.deepEqual(conditionErrors(ladder([0, 0], [null, 2000])), []);
  assert.match(conditionErrors(ladder([3, null])).join(' '), /Level 1: the first visible level has no conditions/);
  assert.match(conditionErrors(ladder([null, 500], [5, null])).join(' '), /Level 1: the first visible level/);
});
test('levels above the first need at least one condition', () => {
  assert.match(conditionErrors(ladder([null, null], [null, null])).join(' '), /Level 2: set at least one condition/);
  assert.match(conditionErrors(ladder([null, null], [0, 0])).join(' '), /Level 2: set at least one condition/);
});
test('each level must be strictly harder on the conditions the previous level set', () => {
  assert.deepEqual(conditionErrors(ladder([null, null], [5, null], [10, null])), []);
  assert.deepEqual(conditionErrors(ladder([null, null], [5, null], [5, 2000])), [], 'same count plus a new condition is harder');
  assert.deepEqual(conditionErrors(ladder([null, null], [5, 1000], [5, 2000])), [], 'one condition grows, the other stays');
  assert.match(conditionErrors(ladder([null, null], [5, null], [5, null])).join(' '), /Level 3: each level must require more/);
  assert.match(conditionErrors(ladder([null, null], [5, null], [4, 9000])).join(' '), /Level 3: each level must require more/, 'a condition may not drop');
  assert.match(conditionErrors(ladder([null, null], [5, 1000], [null, 2000])).join(' '), /Level 3: each level must require more/, 'a set condition may not be removed');
  assert.match(conditionErrors(ladder([null, null], [5, 1000], [6, 900])).join(' '), /Level 3: each level must require more/);
});
test('hidden levels are skipped by the ladder rules', () => {
  assert.deepEqual(conditionErrors(ladder([null, null], [99, 5, true], [5, null])), []);
  assert.deepEqual(conditionErrors(ladder([7, 7, true], [null, null], [null, 100])), []);
});
test('condition values are range- and integer-checked', () => {
  assert.match(conditionErrors(ladder([null, null], [2.5, null])).join(' '), /whole number/);
  assert.match(conditionErrors(ladder([null, null], [1_000_001, null])).join(' '), /whole number up to 1,000,000/);
  assert.match(conditionErrors(ladder([null, null], [null, -1])).join(' '), /combined top-ups must be blank or a non-negative amount/);
});
test('request sends both conditions, nulls hidden ones and keeps the deprecated threshold in step', () => {
  const p = ladder([null, null], [5, 2000], [0, 0, true]); p.Levels[1].MinimumTopupVolume = 2000; p.Levels[2].MinimumQualifiedReferrals = 9;
  const levels = programRequest(p).Levels;
  assert.deepEqual(levels.map(l => [l.MinimumQualifiedReferrals, l.MinimumTopupVolume, l.MinimumMetricValue]), [[null, null, 0], [5, 2000, 5], [null, null, 0]]);
  assert.equal(programRequest(p).LevelBasis, p.LevelBasis, 'LevelBasis is passed through untouched');
  const volumeOnly = ladder([null, null], [null, 2000]);
  assert.deepEqual(programRequest(volumeOnly).Levels[1] && [programRequest(volumeOnly).Levels[1].MinimumQualifiedReferrals, programRequest(volumeOnly).Levels[1].MinimumMetricValue], [null, 0]);
});
test('programs from an old backend map the single threshold through the retired level basis', () => {
  const base = { ...privateProgram(), Levels: [{ Code: 'A', Name: 'A', MinimumMetricValue: 0 }, { Code: 'B', Name: 'B', MinimumMetricValue: 5 }] };
  assert.deepEqual(withProgramDefaults({ ...base, LevelBasis: 'SUCCESSFUL_REFERRAL_COUNT' }).Levels.map(l => [l.MinimumQualifiedReferrals, l.MinimumTopupVolume]), [[null, null], [5, null]]);
  assert.deepEqual(withProgramDefaults({ ...base, LevelBasis: 'REFERRED_TOPUP_VOLUME' }).Levels.map(l => [l.MinimumQualifiedReferrals, l.MinimumTopupVolume]), [[null, null], [null, 5]]);
  // New backends send the two fields; the deprecated threshold is then ignored even when present.
  assert.deepEqual(levelConditions({ MinimumMetricValue: 5, MinimumQualifiedReferrals: null, MinimumTopupVolume: 2000 }, 'SUCCESSFUL_REFERRAL_COUNT'), { MinimumQualifiedReferrals: null, MinimumTopupVolume: 2000 });
  assert.deepEqual(levelConditions({ MinimumMetricValue: 5, MinimumQualifiedReferrals: 0, MinimumTopupVolume: 0 }), { MinimumQualifiedReferrals: null, MinimumTopupVolume: null });
});
test('condition labels and the next-level suggestion', () => {
  const money = (2000).toLocaleString(undefined, { maximumFractionDigits: 2 });
  assert.equal(levelConditionLabel({ MinimumQualifiedReferrals: 5, MinimumTopupVolume: 2000, Hidden: false }), `5 referrals · $${money} top-ups`);
  assert.equal(levelConditionLabel({ MinimumQualifiedReferrals: 1, MinimumTopupVolume: null, Hidden: false }), '1 referral');
  assert.equal(levelConditionLabel({ MinimumQualifiedReferrals: null, MinimumTopupVolume: 2000, Hidden: false }, 'EUR'), `€${money} top-ups`);
  assert.equal(levelConditionLabel({ MinimumQualifiedReferrals: null, MinimumTopupVolume: null, Hidden: false }), 'no conditions');
  assert.equal(levelConditionLabel({ MinimumQualifiedReferrals: 5, MinimumTopupVolume: null, Hidden: true }), 'assigned directly');
  assert.deepEqual(nextLevelConditions([]), { MinimumQualifiedReferrals: null, MinimumTopupVolume: null });
  assert.deepEqual(nextLevelConditions(ladder([null, null]).Levels), { MinimumQualifiedReferrals: 5, MinimumTopupVolume: null });
  assert.deepEqual(nextLevelConditions(ladder([null, null], [5, 1000]).Levels), { MinimumQualifiedReferrals: 10, MinimumTopupVolume: 2000 });
  assert.deepEqual(nextLevelConditions(ladder([null, null], [null, 1000]).Levels), { MinimumQualifiedReferrals: null, MinimumTopupVolume: 2000 });
  for (const p of [ladder([null, null]), ladder([null, null], [5, 1000]), ladder([null, null], [null, 1000])]) {
    const next = nextLevelConditions(p.Levels); p.Levels.push(newLevel(p.Levels.length, next.MinimumQualifiedReferrals, next.MinimumTopupVolume));
    assert.deepEqual(conditionErrors(p), [], 'a suggested level always validates');
  }
});

test('margin breakdown uses each real limiting schedule and never inverts independent minima', () => {
  const limits = { MaxFixedAmount: .1, MaxPercentOfTopup: 2.05128205, MaxPercentOfWlFee: 60, MinimumGrossTopupAmount: 5 };
  assert.equal(marginBreakdown(limits), null, 'older APIs have no reliable schedule provenance');
  const CapSources = [{ Calculation: 'PERCENT_OF_TOPUP', FeeRate: .025, CostRate: .005, Availability: 'AVAILABLE' }, { Calculation: 'PERCENT_OF_WL_FEE', FeeRate: .05, CostRate: .02, Availability: 'AVAILABLE' }];
  const topup = marginBreakdown({ ...limits, CapSources });
  assert.equal(topup.fee, 2.5); assert.equal(topup.cost, .5);
  const fee = marginBreakdown({ ...limits, CapSources }, 'PERCENT_OF_WL_FEE');
  assert.equal(fee.fee, 5); assert.equal(fee.cost, 2);
  assert.equal(marginBreakdown(null), null);
  assert.equal(marginBreakdown({ ...limits, CapSources: [{ ...CapSources[0], CostRate: .025, Availability: 'ZERO_MARGIN' }] }).margin, 0, 'zero margin is a valid returned result');
});
test('programOptionLabel adds an id suffix only for duplicate names', () => {
  const programs = [
    { Id: 'aaaaaaaa-1111', Name: 'Example Creators', Visibility: 'PRIVATE', Status: 'ACTIVE' },
    { Id: 'bbbbbbbb-2222', Name: 'Example Creators', Visibility: 'PRIVATE', Status: 'ACTIVE' },
    { Id: 'cccccccc-3333', Name: 'Example Invite & Earn', Visibility: 'PUBLIC', Status: 'ACTIVE' },
  ];
  assert.equal(programOptionLabel(programs[0], programs), 'Example Creators · private · active · #aaaaaaaa');
  assert.equal(programOptionLabel(programs[1], programs, false), 'Example Creators · private · #bbbbbbbb');
  assert.equal(programOptionLabel(programs[2], programs), 'Example Invite & Earn · public · active');
});

test('cap modes round-trip independently, keep zero, remove stale response fields', () => {
  const p = privateProgram();
  p.MaxEligibleVolumePerRelationship = 1000;
  p.MaximumRecurringReward = 20;
  Object.assign(p.Levels[0], { VolumeCapMode: 'UNLIMITED', VolumeCapAmount: 99, RecurringRewardCapMode: 'CAPPED', RecurringRewardCapAmount: 0, EffectiveVolumeCap: 1000, EffectiveRecurringRewardCap: 20, VolumeCapSource: 'PROGRAM_DEFAULT' });
  const request = programRequest(p);
  assert.equal(request.Levels[0].VolumeCapMode, 'UNLIMITED');
  assert.equal(request.Levels[0].VolumeCapAmount, null);
  assert.equal(request.Levels[0].RecurringRewardCapAmount, 0);
  assert.ok(!('EffectiveVolumeCap' in request.Levels[0]));
  assert.ok(!('VolumeCapSource' in request.Levels[0]));
  assert.deepEqual(programErrors(p, limits), []);
  p.Levels[0].RecurringRewardCapAmount = null;
  assert.match(programErrors(p, limits).join(' '), /recurring reward cap requires/);
  p.Levels[0].RecurringRewardCapMode = 'INHERIT';
  p.Levels[0].VolumeCapMode = 'INHERIT';
  p.MaxEligibleVolumePerRelationship = null;
  p.MaximumRecurringReward = null;
  assert.deepEqual(programErrors(p, limits), []);
});

test('caps reject negative and nonfinite values without changing rates or reward amounts', () => {
  const p = privateProgram();
  p.Levels[0].TopupCalculationType = 'PERCENT_OF_WL_FEE'; p.Levels[0].TopupRate = 40;
  p.WelcomeAmount = 3; p.Levels[0].QualificationRate = 1; p.EarningWindowDays = 365;
  for (const invalid of [-1, Number.NaN, Number.POSITIVE_INFINITY]) {
    p.MaximumRecurringReward = invalid;
    assert.match(programErrors(p, limits).join(' '), /Maximum recurring reward/);
  }
  p.MaximumRecurringReward = null;
  const request = programRequest(p);
  assert.equal(request.Levels[0].TopupRate, 40);
  assert.equal(request.WelcomeAmount, 3);
  assert.equal(request.Levels[0].QualificationRate, 1);
  assert.equal(request.EarningWindowDays, 365);
});

test('reviewed publication requires fixed qualification and matching currencies before draft save', () => {
  const p = privateProgram(); p.WelcomeCurrency = 'USDT';
  p.Levels[0].QualificationCalculationType = 'PERCENT_OF_CARD_FEE';
  assert.deepEqual(programErrors(p, limits), [], 'legacy settings stay readable');
  const errors = programErrors(p, limits, true);
  assert.match(errors.join(' '), /Welcome currency must match payout currency/);
  assert.match(errors.join(' '), /requires a fixed qualification reward/);
  p.Levels[0].QualificationCalculationType = 'FIXED'; p.Levels[0].QualificationRate = 1;
  p.WelcomeCurrency = p.PayoutCurrency; p.WelcomeAmount = 3; p.EarningWindowDays = 365;
  p.MaxEligibleVolumePerRelationship = null; p.MaximumRecurringReward = null;
  assert.deepEqual(programErrors(p, limits, true), []);
});
