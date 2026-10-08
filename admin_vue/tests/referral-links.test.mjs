import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
const source = readFileSync(new URL('../src/lib/referralLinks.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
const { effectiveLinkStatus, filterCampaignLinks, linkActions, linkStatusTone, ownerLabel, qualificationShare, sortCampaignLinks, CAMPAIGN_LINK_STATUSES,
  PERFORMANCE_RANGES, clickToSignupRate, clicksTracked, performanceFromResponse, ratePercent } =
  await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
const now = Date.parse('2026-09-15T12:00:00Z');
const link = (over = {}) => ({ Id: 'l1', ProgramId: 'p1', ProgramName: 'Partners', Name: 'Autumn newsletter', Code: 'AUTUMN26', Channel: 'email', Locale: 'en', Destination: 'signup',
  Status: 'ACTIVE', ActiveFrom: '2026-09-01T00:00:00Z', ExpiresAt: null, CreatedAt: '2026-09-01T00:00:00Z', ShareUrl: 'https://x/signup?ref=AUTUMN26', SignupCount: 8, QualifiedCount: 2,
  OfferVersionId: null, SuggestedCaption: null, OwnerUserId: 42, OwnerName: 'Maja', OwnerEmail: 'maja@example.test', ...over });

test('an expired date overrides the stored status except for archived links', () => {
  assert.equal(effectiveLinkStatus(link(), now), 'ACTIVE');
  assert.equal(effectiveLinkStatus(link({ ExpiresAt: '2026-09-01T00:00:00Z' }), now), 'EXPIRED');
  assert.equal(effectiveLinkStatus(link({ ExpiresAt: '2026-10-01T00:00:00Z' }), now), 'ACTIVE');
  assert.equal(effectiveLinkStatus(link({ Status: 'ARCHIVED', ExpiresAt: '2026-09-01T00:00:00Z' }), now), 'ARCHIVED');
  assert.equal(effectiveLinkStatus(link({ Status: 'paused' }), now), 'PAUSED');
});
test('actions follow the lifecycle: pause active, resume paused, archive anything not archived', () => {
  assert.deepEqual(linkActions(link(), now), { pause: true, resume: false, archive: true });
  assert.deepEqual(linkActions(link({ Status: 'PAUSED' }), now), { pause: false, resume: true, archive: true });
  assert.deepEqual(linkActions(link({ ExpiresAt: '2026-09-01T00:00:00Z' }), now), { pause: false, resume: false, archive: true });
  assert.deepEqual(linkActions(link({ Status: 'ARCHIVED' }), now), { pause: false, resume: false, archive: false });
});
test('filters by effective status and by owner, campaign, code or programme text', () => {
  const rows = [link(), link({ Id: 'l2', Name: 'Meetup', Code: 'MEETUP', Channel: 'event', OwnerName: 'Jonas', OwnerEmail: 'jonas@example.test', OwnerUserId: 7, Status: 'PAUSED' }),
    link({ Id: 'l3', Name: 'Old', Code: 'OLD1', ExpiresAt: '2026-01-01T00:00:00Z' })];
  assert.deepEqual(filterCampaignLinks(rows, { status: 'EXPIRED', now }).map(r => r.Id), ['l3']);
  assert.deepEqual(filterCampaignLinks(rows, { status: 'active', now }).map(r => r.Id), ['l1']);
  assert.deepEqual(filterCampaignLinks(rows, { query: 'jonas', now }).map(r => r.Id), ['l2']);
  assert.deepEqual(filterCampaignLinks(rows, { query: '#42', now }).map(r => r.Id), ['l1', 'l3']);
  assert.deepEqual(filterCampaignLinks(rows, { query: 'meetup', now }).map(r => r.Id), ['l2']);
  assert.deepEqual(filterCampaignLinks(rows, { query: 'partners', now }).map(r => r.Id), ['l1', 'l2', 'l3']);
  assert.equal(filterCampaignLinks(rows, { now }).length, 3);
});
test('sorts newest first with undated rows last and reads owner and share', () => {
  const rows = [link({ Id: 'a', CreatedAt: '2026-09-01T00:00:00Z' }), link({ Id: 'b', CreatedAt: null }), link({ Id: 'c', CreatedAt: '2026-09-10T00:00:00Z' })];
  assert.deepEqual(sortCampaignLinks(rows).map(r => r.Id), ['c', 'a', 'b']);
  assert.equal(ownerLabel(link()), 'Maja'); assert.equal(ownerLabel(link({ OwnerName: null })), 'maja@example.test');
  assert.equal(ownerLabel(link({ OwnerName: null, OwnerEmail: null })), 'User #42'); assert.equal(ownerLabel({ OwnerUserId: null }), '—');
  assert.equal(qualificationShare(link()), 25); assert.equal(qualificationShare(link({ SignupCount: 0 })), null); assert.equal(qualificationShare(link({ SignupCount: 3, QualifiedCount: 1 })), 33.33);
  assert.equal(linkStatusTone('ACTIVE'), 'success'); assert.equal(linkStatusTone('PAUSED'), 'warning'); assert.equal(linkStatusTone('ARCHIVED'), 'danger'); assert.equal(linkStatusTone('EXPIRED'), 'neutral');
  assert.deepEqual(CAMPAIGN_LINK_STATUSES, ['DRAFT', 'ACTIVE', 'PAUSED', 'EXPIRED', 'ARCHIVED']);
});

// ---- addendum A: clicks, rate and the per-link performance response ----
test('rate is sign-ups per unique click at 4 dp, null before any unique click, shown as a percent', () => {
  assert.equal(clickToSignupRate(8, 32), 0.25); assert.equal(clickToSignupRate(1, 3), 0.3333); assert.equal(clickToSignupRate(0, 5), 0);
  assert.equal(clickToSignupRate(5, 0), null); assert.equal(clickToSignupRate(5, null), null); assert.equal(clickToSignupRate(5, undefined), null);
  assert.equal(ratePercent(0.25), '25%'); assert.equal(ratePercent(0.3333), '33.3%'); assert.equal(ratePercent(0), '0%'); assert.equal(ratePercent(null), '—'); assert.equal(ratePercent(NaN), '—');
});
test('clicks are tracked only when the platform sends the counters', () => {
  assert.equal(clicksTracked(link()), false);
  assert.equal(clicksTracked(link({ ClickCount: 0, UniqueClickCount: 0 })), true);
  assert.equal(clicksTracked(link({ ClickCount: null, UniqueClickCount: null })), false);
});
test('the performance response tolerates an older platform and keeps the ranges the route accepts', () => {
  assert.deepEqual(performanceFromResponse({ Clicks: 40, UniqueClicks: 32, ClickToSignupRate: 0.25, Signups: 8, Verified: 6, Qualified: 2, Earning: 2, RewardsAccrued: 4.5, RewardsPaid: 1, Currency: 'EUR' }),
    { Clicks: 40, UniqueClicks: 32, ClickToSignupRate: 0.25, Signups: 8, Verified: 6, Qualified: 2, Earning: 2, RewardsAccrued: 4.5, RewardsPaid: 1, Currency: 'EUR' });
  const older = performanceFromResponse({ Signups: 3, Qualified: 1, RewardsAccrued: 2 });
  assert.equal(older.Clicks, 0); assert.equal(older.UniqueClicks, 0); assert.equal(older.ClickToSignupRate, null); assert.equal(older.Signups, 3); assert.equal(older.Currency, 'USD');
  assert.equal(performanceFromResponse(null).Signups, 0);
  assert.equal(performanceFromResponse({ ClickToSignupRate: 'n/a' }).ClickToSignupRate, null);
  assert.deepEqual(PERFORMANCE_RANGES.map(r => r.id), ['7d', '30d', '90d', 'month', 'all']);
});
