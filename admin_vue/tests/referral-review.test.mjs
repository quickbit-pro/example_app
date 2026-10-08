import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';
// referralReview.ts imports runtime helpers from referrals.ts, so both modules are transpiled into a
// temporary directory and imported as files; type-only imports (referralBuild) are erased by the transpile.
const dir = mkdtempSync(join(tmpdir(), 'referral-review-'));
for (const name of ['referrals', 'referralReview']) {
  const source = readFileSync(new URL(`../src/lib/${name}.ts`, import.meta.url), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText.replace(/from '\.\/(\w+)'/g, "from './$1.js'");
  writeFileSync(join(dir, `${name}.js`), js);
}
const { defaultProgram, newLevel, privateProgram, groupedAmount } = await import(pathToFileURL(join(dir, 'referrals.js')).href);
const { BUILDER_STEPS, beneficiaryRoleLabel, capNote, changeRows, changedFieldLabel, describeFieldValue, describeMargin, effectiveAtIso, effectiveTimeLabel, levelChangeRows,
  offerSentence, offerSummary, previewState, programDiffFields, remainingLabel, rewardBasisLabel, rewardDeliveryState, rewardRateText, stepForError, versionStatusLabel, versionStatusTone }
  = await import(pathToFileURL(join(dir, 'referralReview.js')).href);
const usd = n => groupedAmount(n, 'USD');
const base = () => defaultProgram(); // $3 welcome, level 1: $1 fixed + 0.25% of top-up, 90 days from qualification, wallet credit, no caps
const level = p => p.Levels[0];

// ---- offer sentence and summary ----
test('offer sentence is generated from program values in the blueprint copy', () => {
  const p = base();
  assert.equal(offerSentence(p, level(p)), `Your customer receives ${usd(3)} when they qualify. You receive ${usd(1)} when they qualify, then 0.25% of each eligible credited top-up for 90 days from qualification, with no per-friend cap. Rewards are added to the USD balance.`);
  p.MaxEligibleVolumePerRelationship = 5000; p.MaximumRecurringReward = 50;
  assert.match(offerSentence(p, level(p)), new RegExp(`up to \\${usd(5000)} of eligible top-ups per friend and \\${usd(50)} of recurring rewards per friend\\.`));
  assert.match(offerSentence(p, level(p)), /\$5,000/, 'thousands are grouped like the blueprint examples');
});
test('offer sentence covers margin sharing, sign-up windows, vouchers and empty offers', () => {
  const p = base(); p.MarginPolicy = { Direct: { CompanyBps: 4000, AffiliateBps: 3000, SubpartnerBps: 0, CustomerBps: 1200, BudgetBps: 6000 }, Team: null };
  p.EarningWindowDays = 0; p.EarningWindowStart = 'ATTRIBUTION'; p.DeliveryMode = 'VOUCHER_PER_COMMISSION';
  const sentence = offerSentence(p, level(p));
  assert.match(sentence, /Your customer receives \$3 when they qualify \+ 12% share of settled margin\./);
  assert.match(sentence, /then 30% share of settled margin from sign-up with no end date, with no per-friend cap\./);
  assert.match(sentence, /Rewards: delivered as a voucher per commission \(legacy\)\.$/);
  const empty = base(); empty.WelcomeAmount = 0; level(empty).QualificationRate = 0; level(empty).TopupRate = 0;
  assert.equal(offerSentence(empty, level(empty)), 'Your customer receives no welcome reward. You receive no reward yet. Rewards are added to the USD balance.');
  const onceOnly = base(); level(onceOnly).TopupRate = 0;
  assert.equal(offerSentence(onceOnly, level(onceOnly)), `Your customer receives ${usd(3)} when they qualify. You receive ${usd(1)} when they qualify. Rewards are added to the USD balance.`);
  assert.match(offerSentence(base(), undefined), /You receive no reward yet/, 'no level means no inviter promise');
});
test('offer summary names customer reward, inviter reward, currency, window, cap and delivery', () => {
  const p = base(); p.MaxEligibleVolumePerRelationship = 5000;
  assert.deepEqual(offerSummary(p, level(p)), { customer: `${usd(3)} when they qualify`, inviter: `${usd(1)} when they qualify + 0.25% of each eligible credited top-up`, currency: 'USD',
    window: '90 days from qualification', cap: `${usd(5000)} of eligible top-ups per friend`, delivery: 'Added to USD balance' });
  const none = base(); none.WelcomeAmount = 0; level(none).QualificationRate = 0; level(none).TopupRate = 0; none.EarningWindowDays = 0;
  const s = offerSummary(none, level(none));
  assert.equal(s.customer, 'No welcome reward'); assert.equal(s.inviter, 'No inviter reward'); assert.equal(s.window, 'No recurring reward'); assert.equal(s.cap, 'No per-friend cap');
  const fixed = base(); level(fixed).TopupCalculationType = 'FIXED'; level(fixed).TopupRate = 0.5; fixed.EarningWindowDays = 0;
  assert.equal(offerSummary(fixed, level(fixed)).inviter, `${usd(1)} when they qualify + ${usd(0.5)} per eligible credited top-up`);
  assert.equal(offerSummary(fixed, level(fixed)).window, 'No end date, from qualification');
});

// ---- changed-field labelling ----
test('changed fields get human labels in any casing; unknown names are split on capitals', () => {
  assert.equal(changedFieldLabel('WelcomeAmount'), 'Customer welcome reward');
  assert.equal(changedFieldLabel('welcomeAmount'), 'Customer welcome reward');
  assert.equal(changedFieldLabel('Margin allocations'), 'Margin allocations');
  assert.equal(changedFieldLabel('MaxEligibleVolumePerRelationship'), 'Eligible top-up cap per friend');
  assert.equal(changedFieldLabel('SomeNewField'), 'Some new field');
  assert.equal(changedFieldLabel('another_flag'), 'Another flag');
  assert.equal(changedFieldLabel(''), 'Unnamed field');
});
test('field values are described in plain language with the right currency', () => {
  const p = base(); p.WelcomeCurrency = 'USDT';
  assert.equal(describeFieldValue('WelcomeAmount', 3, p), '3.00 USDT');
  assert.equal(describeFieldValue('MaxEligibleVolumePerRelationship', null, p), 'No limit');
  assert.equal(describeFieldValue('MaxEligibleVolumePerRelationship', 5000, p), '5,000.00 USD');
  assert.equal(describeFieldValue('QualifyMinimumTopup', null, p), 'Platform minimum');
  assert.equal(describeFieldValue('QualifyRequiresKyc', false, p), 'No');
  assert.equal(describeFieldValue('EarningWindowDays', 0, p), 'No end date'); assert.equal(describeFieldValue('EarningWindowDays', 90, p), '90 days');
  assert.equal(describeFieldValue('LevelLookbackMonths', 0, p), 'Lifetime');
  assert.equal(describeFieldValue('EarningWindowStart', 'ATTRIBUTION', p), 'Sign-up (attribution)');
  assert.equal(describeFieldValue('DeliveryMode', 'WALLET_CREDIT', p), 'Added to USD balance');
  assert.equal(describeFieldValue('TermsText', 'abc', p), '3 characters'); assert.equal(describeFieldValue('TermsText', '  ', p), 'Empty');
  assert.equal(describeFieldValue('Status', 'ACTIVE', p), 'Active');
  assert.equal(describeFieldValue('Levels', [1, 2], p), '2 levels');
  assert.equal(describeMargin({ Direct: { CompanyBps: 4000, AffiliateBps: 3000, SubpartnerBps: 0, CustomerBps: 3000, BudgetBps: 6000 }, Team: null }), 'Direct: Company retains 40% · affiliate 30% · customer 30% · budget 60%');
  assert.equal(describeMargin(null), 'Not shared');
});
test('change rows pair labels with old → new values where both sides carry the field', () => {
  const current = base(); current.MarginPolicy = null;
  const draft = { ...base(), WelcomeAmount: 5, EarningWindowDays: 120, Levels: [{ ...newLevel(0), TopupRate: 0.5 }, newLevel(1, 5, null)] };
  const rows = changeRows(['WelcomeAmount', 'earningWindowDays', 'Levels', 'Margin allocations', 'MysteryField'], current, draft, { Direct: { CompanyBps: 5000, AffiliateBps: 3000, SubpartnerBps: 0, CustomerBps: 2000, BudgetBps: 5000 }, Team: null });
  assert.deepEqual(rows[0], { field: 'WelcomeAmount', label: 'Customer welcome reward', from: '3.00 USD', to: '5.00 USD' });
  assert.deepEqual(rows[1], { field: 'EarningWindowDays', label: 'Earning window', from: '90 days', to: '120 days' });
  assert.deepEqual(rows[2], { field: 'Levels', label: 'Reward levels', from: '1 level', to: '2 levels' });
  const details = rows.filter(r => r.detail);
  assert.equal(details.length, 2);
  assert.equal(details[0].label, 'Level Level 1 · rewards'); assert.match(details[0].from, /0\.25% of top-up/); assert.match(details[0].to, /0\.5% of top-up/);
  assert.equal(details[1].label, 'Level Level 2'); assert.equal(details[1].from, 'Not present');
  const margin = rows.find(r => r.field === 'MarginPolicy');
  assert.equal(margin.from, 'Not shared'); assert.match(margin.to, /^Direct: Company retains 50%/);
  const unknown = rows.find(r => r.field === 'MysteryField');
  assert.deepEqual(unknown, { field: 'MysteryField', label: 'Mystery field', from: null, to: null }, 'a value the client cannot derive is not invented');
  assert.deepEqual(changeRows(['WelcomeAmount'], null, draft), [{ field: 'WelcomeAmount', label: 'Customer welcome reward', from: null, to: null }], 'without the current program no old value is claimed');
});
test('level change rows report removed levels and condition changes', () => {
  const before = [newLevel(0), newLevel(1, 5, null)]; const after = [{ ...newLevel(0), Name: 'Starter' }, { ...newLevel(1, 5, 2000), Code: 'LEVEL_2' }];
  const rows = levelChangeRows(before, after, 'USD');
  assert.deepEqual(rows.map(r => r.label), ['Level LEVEL_1 · name', 'Level Level 2 · conditions']);
  assert.equal(rows[1].from, '5 referrals / – top-ups'); assert.equal(rows[1].to, '5 referrals / 2000 top-ups');
  assert.deepEqual(levelChangeRows(before, [before[0]], 'USD').map(r => [r.label, r.to]), [['Level Level 2', 'Removed']]);
  assert.deepEqual(levelChangeRows(undefined, after, 'USD'), []);
});
test('program diff lists the fields that moved and ignores volatile metadata', () => {
  const a = privateProgram(); const b = { ...a, Name: 'Creators', Revision: 9, UpdatedAt: 'later', Levels: [{ ...a.Levels[0], TopupRate: 0.1 }] };
  assert.deepEqual(programDiffFields(a, b), ['Name', 'Levels']);
  assert.deepEqual(programDiffFields(a, null), []);
});

// ---- preview expiry and effective time ----
test('preview validity follows ExpiresAt; unreadable expiry never publishes', () => {
  const now = Date.parse('2026-10-01T10:00:00Z');
  assert.deepEqual(previewState(null, now), { status: 'none', remainingSeconds: 0 });
  assert.deepEqual(previewState({ ExpiresAt: '2026-10-01T10:09:30Z' }, now), { status: 'valid', remainingSeconds: 570 });
  assert.deepEqual(previewState({ ExpiresAt: '2026-10-01T10:00:00Z' }, now), { status: 'expired', remainingSeconds: 0 });
  assert.deepEqual(previewState({ ExpiresAt: '2026-10-01T09:59:59Z' }, now), { status: 'expired', remainingSeconds: 0 });
  assert.deepEqual(previewState({ ExpiresAt: 'garbage' }, now), { status: 'expired', remainingSeconds: 0 });
  assert.equal(remainingLabel(570), '9 min 30 s'); assert.equal(remainingLabel(45), '45 s'); assert.equal(remainingLabel(0), 'expired');
});
test('effective time shows the admin zone and the stored UTC value', () => {
  const { local, utc } = effectiveTimeLabel('2026-10-01T00:00:00Z', 'en-GB', 'Europe/Ljubljana');
  assert.match(local, /1 Oct 2026/); assert.match(local, /02:00/); assert.match(local, /CEST|GMT\+2/);
  assert.equal(utc, '1 Oct 2026, 00:00 UTC');
  assert.deepEqual(effectiveTimeLabel(null), { local: 'Not scheduled', utc: '' });
  assert.deepEqual(effectiveTimeLabel('not a date'), { local: 'Not scheduled', utc: '' });
  const now = new Date('2026-10-01T10:00:00Z');
  assert.equal(effectiveAtIso('', now), now.toISOString(), 'blank means apply when published');
  assert.equal(effectiveAtIso('2026-10-05T14:30', now), new Date('2026-10-05T14:30').toISOString(), 'local input is converted to UTC');
  assert.equal(effectiveAtIso('nope', now), now.toISOString());
});
test('version statuses and builder steps', () => {
  assert.equal(versionStatusLabel('DRAFT'), 'Draft'); assert.equal(versionStatusLabel('SCHEDULED'), 'Scheduled'); assert.equal(versionStatusLabel('PUBLISHED'), 'Published'); assert.equal(versionStatusLabel('SOMETHING_ELSE'), 'Something else');
  assert.equal(versionStatusTone('PUBLISHED'), 'success'); assert.equal(versionStatusTone('SCHEDULED'), 'warning'); assert.equal(versionStatusTone('DRAFT'), 'neutral');
  assert.deepEqual(BUILDER_STEPS.map(s => s.id), ['audience', 'qualification', 'rewards', 'limits', 'review']);
  assert.equal(stepForError('Level 2: invalid top-up reward.'), 'rewards');
  assert.equal(stepForError('Enter a program name of 1–80 characters.'), 'audience');
  assert.equal(stepForError('Minimum qualifying top-up must be blank or a non-negative amount.'), 'qualification');
  assert.equal(stepForError('Welcome amount must be a non-negative amount.'), 'rewards');
  assert.equal(stepForError('Earning window must be whole days between 0 and 36500.'), 'limits');
  assert.equal(stepForError('Exposure limit must be blank or a non-negative amount.'), 'limits');
  assert.equal(stepForError('Reload reward limits before saving.'), 'rewards');
});

// ---- reward drawer ----
test('cap note follows the blueprint wording and never invents a cap', () => {
  const reward = { BasisAmount: 1000, BasisCurrency: 'USD' };
  assert.equal(capNote({ VolumeCap: 5000, EligibleAmount: 200 }, reward), `Only ${usd(200)} of this ${usd(1000)} top-up was eligible because this friend reached the ${usd(5000)} limit.`);
  assert.equal(capNote({ VolumeCap: 5000, EligibleAmount: 1000 }, reward), `The whole ${usd(1000)} was eligible; the ${usd(5000)} per-friend limit was not reached.`);
  assert.equal(capNote({ VolumeCap: 5000, EligibleAmount: null }, reward), `Eligible top-ups are limited to ${usd(5000)} per friend.`);
  assert.equal(capNote({ VolumeCap: null, EligibleAmount: null }, reward), 'No per-friend cap was recorded for this reward.');
  assert.equal(capNote(null, reward), 'No calculation evidence was recorded for this reward.');
});
test('rates name their denominator and unknown values stay unknown', () => {
  assert.equal(rewardRateText('PERCENT_OF_TOPUP', 0.25, 'USD'), '0.25% of the credited top-up');
  assert.equal(rewardRateText('margin-v1', 30, 'USD'), '30% of settled margin');
  assert.equal(rewardRateText('FIXED', 1, 'USD'), `${usd(1)} per event`);
  assert.equal(rewardRateText('PERCENT_OF_WL_FEE', 50, 'USD'), '50% of the top-up fee');
  assert.equal(rewardRateText('PERCENT_OF_TOPUP', null, 'USD'), 'Not recorded');
  assert.equal(rewardBasisLabel('margin-v1'), 'Share of settled margin'); assert.equal(rewardBasisLabel('PERCENT_OF_TOPUP'), 'Percentage of the eligible credited top-up'); assert.equal(rewardBasisLabel(undefined), 'Not recorded');
  assert.equal(beneficiaryRoleLabel('REFERRER'), 'Inviter'); assert.equal(beneficiaryRoleLabel('REFERRED'), 'Referred customer'); assert.equal(beneficiaryRoleLabel('SUBPARTNER'), 'Subpartner');
  assert.equal(rewardDeliveryState({ Status: 'CREDITING', PaidAt: null, DeliveryMode: 'WALLET_CREDIT' }), 'Transfer in progress; waiting for provider confirmation');
  assert.equal(rewardDeliveryState({ Status: 'PAID', PaidAt: '2026-09-01T00:00:00Z', DeliveryMode: 'WALLET_CREDIT' }), 'Confirmed by the provider');
  assert.equal(rewardDeliveryState({ Status: 'FAILED', PaidAt: null, DeliveryMode: 'WALLET_CREDIT' }), 'Delivery or calculation failed; see the credit for the next action');
});

test('tier summaries resolve overrides and inherited defaults without stale server values', () => {
  const p = base(); p.MaxEligibleVolumePerRelationship = 1000; p.MaximumRecurringReward = 10;
  const l = level(p); l.VolumeCapMode = 'UNLIMITED'; l.RecurringRewardCapMode = 'CAPPED'; l.RecurringRewardCapAmount = 0;
  l.EffectiveVolumeCap = 999; l.EffectiveRecurringRewardCap = 999;
  assert.equal(offerSummary(p, l).cap, `${usd(0)} of recurring rewards per friend`);
  l.VolumeCapMode = 'CAPPED'; l.VolumeCapAmount = 0; l.RecurringRewardCapMode = 'UNLIMITED';
  assert.equal(offerSummary(p, l).cap, `${usd(0)} of eligible top-ups per friend`);
  l.VolumeCapMode = 'INHERIT'; l.RecurringRewardCapMode = 'INHERIT';
  assert.match(offerSummary(p, l).cap, /1,000/);
  p.MaxEligibleVolumePerRelationship = 25;
  assert.match(offerSummary(p, l).cap, /25/);
  const next = { ...l, VolumeCapMode: 'UNLIMITED', RecurringRewardCapMode: 'CAPPED', RecurringRewardCapAmount: 0 };
  const rows = levelChangeRows([l], [next], 'USD');
  assert.ok(rows.some(r => r.to === 'No cap (tier override)'));
  assert.ok(rows.some(r => r.label.includes('recurring reward cap') && r.to.includes('0.00')));
});

test('an incomplete explicit cap is never described as unlimited', () => {
  const p = base(); const l = level(p);
  l.VolumeCapMode = 'CAPPED'; l.VolumeCapAmount = null;
  assert.match(offerSummary(p, l).cap, /amount required/);
  assert.doesNotMatch(offerSummary(p, l).cap, /No per-friend cap/);
  assert.doesNotMatch(offerSentence(p, l), /no per-friend cap/);
});
