// Presentation helpers for the offer builder (summary sentence, publish preview, version history) and
// the reward drawer. Pure functions only: no API access, no Vue. Copy follows the blueprint contract:
// "Your customer receives", "You receive", "Company retains", "eligible credited top-up", "share of settled margin".
import { effectiveLevelCaps, groupedAmount, money, statusLabel, trimNumber, type ReferralLevel, type ReferralProgram, type ReferralReward, type RewardExplanation } from './referrals';
import type { Allocation, MarginPolicy, Preview } from './referralBuild';

export type BuilderStep = 'audience' | 'qualification' | 'rewards' | 'limits' | 'review';
export const BUILDER_STEPS: { id: BuilderStep; label: string; hint: string }[] = [
  { id: 'audience', label: 'Audience', hint: 'Who the program is for and what they accept' },
  { id: 'qualification', label: 'Qualification', hint: 'What a referred customer must do' },
  { id: 'rewards', label: 'Rewards', hint: 'What the customer and the inviter receive' },
  { id: 'limits', label: 'Limits and delivery', hint: 'Window, caps and how rewards are paid' },
  { id: 'review', label: 'Review', hint: 'Check the offer, then save or publish' },
];

const bpsPercent = (bps: number) => `${trimNumber(bps / 100)}%`;
const windowStartLabel = (start: string) => start === 'ATTRIBUTION' ? 'sign-up' : 'qualification';

// ---- offer summary and sentence ----
export interface OfferSummary { customer: string; inviter: string; currency: string; window: string; cap: string; delivery: string }
/** Reward pieces of one level, phrased for the inviter. Empty strings mean "nothing". */
function inviterPieces(program: Pick<ReferralProgram, 'PayoutCurrency' | 'MarginPolicy'>, level: ReferralLevel | undefined): { once: string; recurring: string } {
  const currency = program.PayoutCurrency || 'USD';
  const once = level && level.QualificationRate > 0
    ? (level.QualificationCalculationType === 'FIXED' ? groupedAmount(level.QualificationRate, currency) : `${trimNumber(level.QualificationRate)}% of their card fee`)
    : '';
  let recurring = '';
  if (program.MarginPolicy) {
    if (program.MarginPolicy.Direct.AffiliateBps > 0) recurring = `${bpsPercent(program.MarginPolicy.Direct.AffiliateBps)} share of settled margin`;
  } else if (level && level.TopupRate > 0) {
    recurring = level.TopupCalculationType === 'FIXED' ? `${groupedAmount(level.TopupRate, currency)} per eligible credited top-up`
      : level.TopupCalculationType === 'PERCENT_OF_WL_FEE' ? `${trimNumber(level.TopupRate)}% of the fee on each eligible credited top-up`
      : `${trimNumber(level.TopupRate)}% of each eligible credited top-up`;
  }
  return { once, recurring };
}
function customerPiece(program: Pick<ReferralProgram, 'WelcomeAmount' | 'WelcomeCurrency' | 'PayoutCurrency' | 'MarginPolicy'>): string {
  const welcome = program.WelcomeAmount > 0 ? `${groupedAmount(program.WelcomeAmount, program.WelcomeCurrency || program.PayoutCurrency || 'USD')} when they qualify` : '';
  const share = program.MarginPolicy && program.MarginPolicy.Direct.CustomerBps > 0 ? `${bpsPercent(program.MarginPolicy.Direct.CustomerBps)} share of settled margin` : '';
  return [welcome, share].filter(Boolean).join(' + ');
}
/** "90 days from qualification" for the summary tile; the sentence form reads "for 90 days from qualification" / "from sign-up with no end date". */
function windowPiece(program: Pick<ReferralProgram, 'EarningWindowDays' | 'EarningWindowStart'>, form: 'short' | 'sentence' = 'short'): string {
  const start = windowStartLabel(program.EarningWindowStart);
  if (program.EarningWindowDays > 0) return `${form === 'sentence' ? 'for ' : ''}${program.EarningWindowDays} days from ${start}`;
  return form === 'sentence' ? `from ${start} with no end date` : `No end date, from ${start}`;
}
function capPieces(program: Pick<ReferralProgram, 'PayoutCurrency' | 'MaxEligibleVolumePerRelationship' | 'MaximumRecurringReward'>, level?: ReferralLevel): string[] {
  const currency = program.PayoutCurrency || 'USD';
  const caps = effectiveLevelCaps(program, level);
  const pieces: string[] = [];
  if (level?.VolumeCapMode === 'CAPPED' && !Number.isFinite(level.VolumeCapAmount ?? NaN)) pieces.push('eligible top-up cap amount required');
  if (level?.RecurringRewardCapMode === 'CAPPED' && !Number.isFinite(level.RecurringRewardCapAmount ?? NaN)) pieces.push('recurring reward cap amount required');
  if (caps.volume != null) pieces.push(`${groupedAmount(caps.volume, currency)} of eligible top-ups per friend`);
  if (caps.recurring != null) pieces.push(`${groupedAmount(caps.recurring, currency)} of recurring rewards per friend`);
  return pieces;
}
export function deliveryLabel(mode: string | null | undefined, currency = 'USD'): string {
  return mode === 'WALLET_CREDIT' ? `Added to ${currency} balance` : mode === 'AUTOMATIC_TRANSFER' ? 'Delivered as an automatic voucher (legacy)' : mode === 'VOUCHER_PER_COMMISSION' ? 'Delivered as a voucher per commission (legacy)' : statusLabel(mode) || 'Not set';
}
/** The sticky builder summary: customer reward, inviter reward, currency, window, cap and delivery, each as a short phrase. */
export function offerSummary(program: ReferralProgram, level: ReferralLevel | undefined): OfferSummary {
  const currency = program.PayoutCurrency || 'USD';
  const { once, recurring } = inviterPieces(program, level);
  const caps = capPieces(program, level);
  return {
    customer: customerPiece(program) || 'No welcome reward',
    inviter: [once ? `${once} when they qualify` : '', recurring].filter(Boolean).join(' + ') || 'No inviter reward',
    currency,
    window: recurring ? windowPiece(program) : 'No recurring reward',
    cap: caps.length ? caps.join(' · ') : 'No per-friend cap',
    delivery: deliveryLabel(program.DeliveryMode, currency),
  };
}
/**
 * One sentence an inviter could read, generated from program values (never hard-coded):
 * "Your customer receives $3 when they qualify. You receive $1 when they qualify, then 0.25% of each
 * eligible credited top-up for 90 days from qualification, up to $5,000 of eligible top-ups per friend.
 * Rewards are added to the USD balance."
 */
export function offerSentence(program: ReferralProgram, level: ReferralLevel | undefined): string {
  const currency = program.PayoutCurrency || 'USD';
  const customer = customerPiece(program);
  const { once, recurring } = inviterPieces(program, level);
  const sentences: string[] = [customer ? `Your customer receives ${customer}.` : 'Your customer receives no welcome reward.'];
  if (!once && !recurring) sentences.push('You receive no reward yet.');
  else {
    let you = once ? `You receive ${once} when they qualify` : 'You receive';
    if (recurring) {
      you += `${once ? ', then ' : ' '}${recurring} ${windowPiece(program, 'sentence')}`;
      const caps = capPieces(program, level);
      you += caps.length ? `, up to ${caps.join(' and ')}` : ', with no per-friend cap';
    }
    sentences.push(`${you}.`);
  }
  sentences.push(program.DeliveryMode === 'WALLET_CREDIT' ? `Rewards are added to the ${currency} balance.` : `Rewards: ${deliveryLabel(program.DeliveryMode, currency).toLowerCase()}.`);
  return sentences.join(' ');
}

// ---- publish preview: changed fields in plain language ----
const FIELD_LABELS: Record<string, string> = {
  Name: 'Program name', Description: 'Description', Status: 'Program status', Visibility: 'Visibility', LevelBasis: 'Level basis (deprecated)',
  LevelLookbackMonths: 'Level lookback', EarningWindowDays: 'Earning window', EarningWindowStart: 'Window starts at',
  QualifyRequiresKyc: 'Requires identity verification', QualifyRequiresPaidCard: 'Requires a paid card', QualifyRequiresTopup: 'Requires a first top-up',
  QualifyMinimumTopup: 'Minimum qualifying top-up', WelcomeAmount: 'Customer welcome reward', WelcomeCurrency: 'Welcome currency',
  DeliveryMode: 'Delivery mode', PayoutCurrency: 'Payout currency', VoucherClaimDays: 'Voucher claim period', MinimumCreditAmount: 'Minimum credit amount',
  MaxEligibleVolumePerRelationship: 'Eligible top-up cap per friend', ExposureLimit: 'Program exposure limit', MaximumRecurringReward: 'Maximum recurring reward per friend',
  TermsText: 'Terms text', PrivacyNotice: 'Privacy notice', TermsVersion: 'Terms version', PublishNewTermsVersion: 'New terms version',
  Levels: 'Reward levels', MarginPolicy: 'Margin allocations', 'Margin allocations': 'Margin allocations', Revision: 'Revision',
};
const pascal = (field: string) => field.charAt(0).toUpperCase() + field.slice(1);
/** "WelcomeAmount" → "Customer welcome reward"; unknown names are split on capitals ("someNewField" → "Some new field"). */
export function changedFieldLabel(field: string): string {
  const key = pascal(field.trim());
  const known = FIELD_LABELS[key] ?? FIELD_LABELS[field];
  if (known) return known;
  const words = key.replace(/[_-]+/g, ' ').replace(/([a-z0-9])([A-Z])/g, '$1 $2').replace(/\s+/g, ' ').trim().toLowerCase();
  return words ? words.charAt(0).toUpperCase() + words.slice(1) : 'Unnamed field';
}
const MONEY_FIELDS = new Set(['QualifyMinimumTopup', 'MinimumCreditAmount', 'MaxEligibleVolumePerRelationship', 'ExposureLimit', 'MaximumRecurringReward']);
export function describeAllocation(a: Allocation | null | undefined): string {
  if (!a) return 'Not shared';
  const parts = [`Company retains ${bpsPercent(a.CompanyBps)}`, `affiliate ${bpsPercent(a.AffiliateBps)}`];
  if (a.SubpartnerBps > 0) parts.push(`subpartner ${bpsPercent(a.SubpartnerBps)}`);
  parts.push(`customer ${bpsPercent(a.CustomerBps)}`, `budget ${bpsPercent(a.BudgetBps)}`);
  return parts.join(' · ');
}
export function describeMargin(policy: MarginPolicy | null | undefined): string {
  if (!policy) return 'Not shared';
  return `Direct: ${describeAllocation(policy.Direct)}${policy.Team ? ` · Team: ${describeAllocation(policy.Team)}` : ''}`;
}
function levelSummary(level: Partial<ReferralLevel>, currency: string): string {
  const once = level.QualificationRate && level.QualificationRate > 0 ? (level.QualificationCalculationType === 'FIXED' ? groupedAmount(level.QualificationRate, currency) : `${trimNumber(level.QualificationRate)}% of card fee`) : 'no bonus';
  const recurring = level.TopupRate && level.TopupRate > 0 ? (level.TopupCalculationType === 'FIXED' ? `${groupedAmount(level.TopupRate, currency)} per top-up` : level.TopupCalculationType === 'PERCENT_OF_WL_FEE' ? `${trimNumber(level.TopupRate)}% of fee` : `${trimNumber(level.TopupRate)}% of top-up`) : 'no recurring reward';
  return `${once} when qualified, ${recurring}${level.Hidden ? ', hidden' : ''}`;
}
/** Human text for one program value; money fields use the payout currency, the welcome amount its own currency. */
export function describeFieldValue(field: string, value: unknown, program: Partial<ReferralProgram> | null | undefined): string {
  const key = pascal(field);
  const currency = program?.PayoutCurrency || 'USD';
  if (value === null || value === undefined || value === '') return key === 'MaxEligibleVolumePerRelationship' || key === 'MaximumRecurringReward' || key === 'ExposureLimit' ? 'No limit' : key === 'QualifyMinimumTopup' ? 'Platform minimum' : 'Not set';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (key === 'WelcomeAmount' && typeof value === 'number') return money(value, program?.WelcomeCurrency || currency);
  if (MONEY_FIELDS.has(key) && typeof value === 'number') return money(value, currency);
  if (key === 'LevelLookbackMonths') return Number(value) === 0 ? 'Lifetime' : `${value} months`;
  if (key === 'EarningWindowDays') return Number(value) === 0 ? 'No end date' : `${value} days`;
  if (key === 'VoucherClaimDays') return `${value} days`;
  if (key === 'EarningWindowStart') return value === 'ATTRIBUTION' ? 'Sign-up (attribution)' : value === 'QUALIFICATION' ? 'Qualification' : String(value);
  if (key === 'DeliveryMode') return deliveryLabel(String(value), currency);
  if (key === 'TermsText' || key === 'PrivacyNotice' || key === 'Description') { const text = String(value); return text.trim() ? `${text.length} characters` : 'Empty'; }
  if (key === 'Levels' && Array.isArray(value)) return `${value.length} ${value.length === 1 ? 'level' : 'levels'}`;
  if (key === 'MarginPolicy') return describeMargin(value as MarginPolicy);
  if (key === 'Status' || key === 'Visibility') { const text = statusLabel(String(value)); return text.charAt(0).toUpperCase() + text.slice(1); }
  if (typeof value === 'object') return 'Changed';
  return String(value);
}
export interface ChangeRow { field: string; label: string; from: string | null; to: string | null; detail?: boolean }
/** Per-level differences (matched by code): rate, condition and visibility changes plus added and removed levels. */
export function levelChangeRows(current: ReferralLevel[] | undefined, draft: Partial<ReferralLevel>[] | undefined, currency: string): ChangeRow[] {
  if (!current || !draft) return [];
  const code = (level: Partial<ReferralLevel>) => (level.Code ?? '').trim().toUpperCase();
  const rows: ChangeRow[] = [];
  const before = new Map(current.map(level => [code(level), level]));
  const after = new Map(draft.map(level => [code(level), level]));
  for (const [key, level] of after) {
    const name = level.Name || key;
    const old = before.get(key);
    if (!old) { rows.push({ field: `Levels.${key}`, label: `Level ${name}`, from: 'Not present', to: levelSummary(level, currency), detail: true }); continue; }
    const summaryBefore = levelSummary(old, currency), summaryAfter = levelSummary(level, currency);
    if (summaryBefore !== summaryAfter) rows.push({ field: `Levels.${key}`, label: `Level ${name} · rewards`, from: summaryBefore, to: summaryAfter, detail: true });
    for (const [label, modeKey, amountKey] of [['volume cap', 'VolumeCapMode', 'VolumeCapAmount'], ['recurring reward cap', 'RecurringRewardCapMode', 'RecurringRewardCapAmount']] as const) {
      const describe = (l: Partial<ReferralLevel>) => (l[modeKey] ?? 'INHERIT') === 'INHERIT' ? 'Inherit program default' : l[modeKey] === 'UNLIMITED' ? 'No cap (tier override)' : l[amountKey] == null ? 'Amount required' : money(l[amountKey], currency);
      if (describe(old) !== describe(level)) rows.push({ field: `Levels.${key}.${modeKey}`, label: `Level ${name} · ${label}`, from: describe(old), to: describe(level), detail: true });
    }
    const conditions = (l: Partial<ReferralLevel>) => `${l.MinimumQualifiedReferrals ?? '–'} referrals / ${l.MinimumTopupVolume ?? '–'} top-ups`;
    if (conditions(old) !== conditions(level)) rows.push({ field: `Levels.${key}.conditions`, label: `Level ${name} · conditions`, from: conditions(old), to: conditions(level), detail: true });
    if (old.Name !== level.Name && level.Name) rows.push({ field: `Levels.${key}.name`, label: `Level ${key} · name`, from: old.Name, to: level.Name, detail: true });
  }
  for (const [key, level] of before) if (!after.has(key)) rows.push({ field: `Levels.${key}`, label: `Level ${level.Name || key}`, from: levelSummary(level, currency), to: 'Removed', detail: true });
  return rows;
}
/**
 * Rows for the publish preview: the server's changed-field names as human labels, with old → new values
 * where the current program and the draft policy both carry the field. Unknown or non-derivable values
 * stay null so the UI says "changed" instead of inventing a value.
 */
export function changeRows(fields: readonly string[], current: Partial<ReferralProgram> | null | undefined, draft: Partial<ReferralProgram> | null | undefined, margin?: MarginPolicy | null): ChangeRow[] {
  const rows: ChangeRow[] = [];
  const currency = draft?.PayoutCurrency || current?.PayoutCurrency || 'USD';
  for (const field of fields) {
    const key = field === 'Margin allocations' ? 'MarginPolicy' : pascal(field.trim());
    const label = changedFieldLabel(field);
    if (key === 'MarginPolicy') { rows.push({ field: key, label, from: current ? describeMargin(current.MarginPolicy) : null, to: describeMargin(margin ?? draft?.MarginPolicy) }); continue; }
    if (key === 'Levels') {
      const from = current?.Levels ? describeFieldValue(key, current.Levels, current) : null, to = draft?.Levels ? describeFieldValue(key, draft.Levels, draft) : null;
      rows.push({ field: key, label, from, to }, ...levelChangeRows(current?.Levels, draft?.Levels, currency));
      continue;
    }
    const known = !!current && !!draft && key in draft;
    rows.push({ field: key, label, from: known ? describeFieldValue(key, (current as Record<string, unknown>)[key], current) : null, to: known ? describeFieldValue(key, (draft as Record<string, unknown>)[key], draft) : null });
  }
  return rows;
}
const VOLATILE = new Set(['Exists', 'Id', 'Provider', 'UpdatedAt', 'ReservedExposure', 'PublishedAt', 'OfferVersionId', 'Revision', 'TermsVersion']);
/** Top-level fields whose values differ between two programs (a revision conflict compares the server copy with the edited one). */
export function programDiffFields(a: Partial<ReferralProgram> | null | undefined, b: Partial<ReferralProgram> | null | undefined): string[] {
  if (!a || !b) return [];
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  return [...keys].filter(key => !VOLATILE.has(key) && JSON.stringify((a as Record<string, unknown>)[key] ?? null) !== JSON.stringify((b as Record<string, unknown>)[key] ?? null));
}

// ---- preview validity and effective time ----
export interface PreviewState { status: 'none' | 'valid' | 'expired'; remainingSeconds: number }
/** A preview publishes only before ExpiresAt; a missing or unreadable expiry counts as expired (the server never accepts it). */
export function previewState(preview: Pick<Preview, 'ExpiresAt'> | null | undefined, now = Date.now()): PreviewState {
  if (!preview) return { status: 'none', remainingSeconds: 0 };
  const expires = Date.parse(preview.ExpiresAt);
  if (!Number.isFinite(expires)) return { status: 'expired', remainingSeconds: 0 };
  const remaining = Math.floor((expires - now) / 1000);
  return remaining > 0 ? { status: 'valid', remainingSeconds: remaining } : { status: 'expired', remainingSeconds: 0 };
}
export function remainingLabel(seconds: number): string {
  if (seconds <= 0) return 'expired';
  const minutes = Math.floor(seconds / 60), rest = seconds % 60;
  return minutes > 0 ? `${minutes} min ${String(rest).padStart(2, '0')} s` : `${rest} s`;
}
export function localTimeZone(): string { try { return Intl.DateTimeFormat().resolvedOptions().timeZone || 'local time'; } catch { return 'local time'; } }
/** "1 Oct 2026, 02:00 CEST" in the admin's zone plus "1 Oct 2026, 00:00 UTC", the value the platform stores. */
export function effectiveTimeLabel(iso: string | null | undefined, locale?: string, timeZone?: string): { local: string; utc: string } {
  const date = iso ? new Date(iso) : null;
  if (!date || Number.isNaN(date.getTime())) return { local: 'Not scheduled', utc: '' };
  const parts: Intl.DateTimeFormatOptions = { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' };
  const local = new Intl.DateTimeFormat(locale, { ...parts, timeZone, timeZoneName: 'short' }).format(date);
  const utc = `${new Intl.DateTimeFormat(locale ?? 'en-GB', { ...parts, timeZone: 'UTC', hourCycle: 'h23' }).format(date)} UTC`;
  return { local, utc };
}
/** datetime-local input value (admin's zone) → UTC ISO; empty means "when published". */
export function effectiveAtIso(input: string, now = new Date()): string {
  if (!input.trim()) return now.toISOString();
  const date = new Date(input);
  return Number.isNaN(date.getTime()) ? now.toISOString() : date.toISOString();
}
export function versionStatusLabel(status: string | null | undefined): string {
  switch (status) { case 'DRAFT': return 'Draft'; case 'SCHEDULED': return 'Scheduled'; case 'PUBLISHED': return 'Published'; default: { const text = statusLabel(status); return text ? text.charAt(0).toUpperCase() + text.slice(1) : 'Unknown'; } }
}
export function versionStatusTone(status: string | null | undefined): string {
  return status === 'PUBLISHED' ? 'success' : status === 'SCHEDULED' ? 'warning' : 'neutral';
}

// ---- builder navigation ----
/** Which step a validation message belongs to, so the summary can send the admin to the right place. */
export function stepForError(message: string): BuilderStep {
  const text = message.toLowerCase();
  if (/^level \d|levels\b|reward limits/.test(text)) return 'rewards';
  if (/program name|description|terms text|privacy notice/.test(text)) return 'audience';
  if (/qualifying top-up|welcome amount|welcome currency/.test(text)) return text.includes('qualifying') ? 'qualification' : 'rewards';
  if (/lookback/.test(text)) return 'rewards';
  if (/earning window|eligible volume|maximum recurring|exposure|credit amount|voucher/.test(text)) return 'limits';
  return 'review';
}

// ---- reward drawer ----
export function beneficiaryRoleLabel(role: string | null | undefined): string {
  switch (role) { case 'REFERRER': return 'Inviter'; case 'REFERRED': return 'Referred customer'; case 'SUBPARTNER': return 'Subpartner'; default: { const text = statusLabel(role); return text ? text.charAt(0).toUpperCase() + text.slice(1) : 'Unknown'; } }
}
export function rewardBasisLabel(basis: string | null | undefined): string {
  switch (basis) {
    case 'PERCENT_OF_TOPUP': return 'Percentage of the eligible credited top-up';
    case 'PERCENT_OF_WL_FEE': return 'Percentage of the fee on the eligible top-up';
    case 'PERCENT_OF_CARD_FEE': case 'PERCENT_OF_FEE': return 'Percentage of the card fee';
    case 'FIXED': return 'Fixed amount';
    case 'margin-v1': return 'Share of settled margin';
    case 'WELCOME': return 'Welcome reward (fixed)';
    case 'QUALIFICATION': return 'Qualification bonus';
    case 'CARD_TOPUP': return 'Top-up reward (legacy calculation)';
    case 'ADJUSTMENT': return 'Manual adjustment';
    default: { const text = statusLabel(basis); return text ? text.charAt(0).toUpperCase() + text.slice(1) : 'Not recorded'; }
  }
}
/** The rate with its denominator; null means the platform did not record one. */
export function rewardRateText(basis: string | null | undefined, rate: number | null | undefined, currency: string): string {
  if (rate === null || rate === undefined || !Number.isFinite(rate)) return 'Not recorded';
  if (basis === 'margin-v1') return `${trimNumber(rate)}% of settled margin`;
  if (basis === 'FIXED' || basis === 'WELCOME' || basis === 'QUALIFICATION') return `${groupedAmount(rate, currency)} per event`;
  if (basis === 'PERCENT_OF_WL_FEE') return `${trimNumber(rate)}% of the top-up fee`;
  if (basis === 'PERCENT_OF_CARD_FEE' || basis === 'PERCENT_OF_FEE') return `${trimNumber(rate)}% of the card fee`;
  return `${trimNumber(rate)}% of the credited top-up`;
}
/** Blueprint example: "Only $200 of this top-up was eligible because this friend reached the $5,000 limit." */
export function capNote(explanation: RewardExplanation | null | undefined, reward: Pick<ReferralReward, 'BasisAmount' | 'BasisCurrency'>): string {
  if (!explanation) return 'No calculation evidence was recorded for this reward.';
  const currency = reward.BasisCurrency || 'USD';
  const cap = explanation.VolumeCap, eligible = explanation.EligibleAmount;
  if (cap === null || cap === undefined) return 'No per-friend cap was recorded for this reward.';
  if (eligible !== null && eligible !== undefined && reward.BasisAmount > 0 && eligible < reward.BasisAmount)
    return `Only ${groupedAmount(eligible, currency)} of this ${groupedAmount(reward.BasisAmount, currency)} top-up was eligible because this friend reached the ${groupedAmount(cap, currency)} limit.`;
  if (eligible !== null && eligible !== undefined) return `The whole ${groupedAmount(eligible, currency)} was eligible; the ${groupedAmount(cap, currency)} per-friend limit was not reached.`;
  return `Eligible top-ups are limited to ${groupedAmount(cap, currency)} per friend.`;
}
/** Delivery wording that never announces a provider-dependent step as done. */
export function rewardDeliveryState(reward: Pick<ReferralReward, 'Status' | 'PaidAt' | 'DeliveryMode'>): string {
  switch (reward.Status) {
    case 'PAID': return reward.PaidAt ? 'Confirmed by the provider' : 'Paid';
    case 'CREDITING': return 'Transfer in progress; waiting for provider confirmation';
    case 'READY': return 'Entitled; waiting to be batched into a wallet credit';
    case 'PENDING': return 'Waiting for eligibility or settlement inputs';
    case 'HELD': return 'Held for review';
    case 'FAILED': return 'Delivery or calculation failed; see the credit for the next action';
    case 'CANCELLED': return 'Cancelled; no credit is due';
    case 'REVERSED': return 'Reversed by a compensating entry';
    case 'EXPIRED_UNCLAIMED': return 'Voucher expired unclaimed';
    default: { const text = statusLabel(reward.Status); return text ? text.charAt(0).toUpperCase() + text.slice(1) : 'Unknown'; }
  }
}
