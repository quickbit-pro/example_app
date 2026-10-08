// Referral program v2 types. Field names mirror the platform DTOs (Models/V2/Referrals.cs);
// responses are normalised to PascalCase by normalizeReferral, enum values are never touched.

export type QualificationCalculationType = 'FIXED' | 'PERCENT_OF_CARD_FEE';
export type TopupCalculationType = 'FIXED' | 'PERCENT_OF_TOPUP' | 'PERCENT_OF_WL_FEE';
/** WALLET_CREDIT credits the user's USD balance automatically; the voucher modes are legacy. */
export type DeliveryMode = 'WALLET_CREDIT' | 'AUTOMATIC_TRANSFER' | 'VOUCHER_PER_COMMISSION';
export type EarningWindowStart = 'ATTRIBUTION' | 'QUALIFICATION';

export type ReferralCapMode = 'INHERIT' | 'UNLIMITED' | 'CAPPED';
export interface ReferralLevel {
  VolumeCapMode?: ReferralCapMode; VolumeCapAmount?: number | null;
  RecurringRewardCapMode?: ReferralCapMode; RecurringRewardCapAmount?: number | null;
  EffectiveVolumeCap?: number | null; EffectiveRecurringRewardCap?: number | null;
  VolumeCapSource?: string; RecurringRewardCapSource?: string;
  Id?: string; Code: string; Name: string; Icon: string; Color: string;
  DisplayOrder: number;
  /** Deprecated single threshold; kept equal to MinimumQualifiedReferrals ?? 0 for old readers. */
  MinimumMetricValue: number;
  /** Level conditions. Null = no condition; every condition that is set must be met (AND). */
  MinimumQualifiedReferrals: number | null; MinimumTopupVolume: number | null;
  QualificationCalculationType: QualificationCalculationType | string; QualificationRate: number;
  TopupCalculationType: TopupCalculationType | string; TopupRate: number;
  /** Hidden levels are never listed and only apply through a level assignment. */
  Hidden: boolean;
}
export interface ReferralProgram {
  MaximumRecurringReward?: number | null; OfferVersionId?: string | null; MarginPolicy?: import('./referralBuild').MarginPolicy | null;
  Exists: boolean; Id: string | null; Provider: string; Name: string; Description: string | null;
  Visibility: string; Revision: number; Status: string; LevelBasis: string; LevelLookbackMonths: number;
  EarningWindowDays: number; EarningWindowStart: EarningWindowStart | string;
  QualifyRequiresKyc: boolean; QualifyRequiresPaidCard: boolean; QualifyRequiresTopup: boolean;
  PromoCodePolicyEnabled?: boolean;
  /** Null means the platform card top-up minimum applies. */
  QualifyMinimumTopup: number | null;
  WelcomeAmount: number; WelcomeCurrency: string;
  DeliveryMode: DeliveryMode | string; PayoutCurrency: string; VoucherClaimDays: number;
  MinimumCreditAmount: number; MaxEligibleVolumePerRelationship: number | null; ExposureLimit: number | null;
  ReservedExposure: number; TermsVersion: number; TermsText: string | null; PrivacyNotice: string | null;
  PublishedAt: string | null; UpdatedAt?: string | null; Levels: ReferralLevel[];
}
export interface MarginCapSource { Calculation: string; Maximum: number; ScheduleKind: string; TierId: number | null; TierName: string | null; FeeRate: number; CostRate: number; Formula: string; Availability: string }
export interface RewardLimits { MaxFixedAmount: number; MaxPercentOfTopup: number; MaxPercentOfWlFee: number; MinimumGrossTopupAmount: number; CapSources?: MarginCapSource[] | null }
export interface ReferralOverview {
  UnboundedCommitmentCount?: number; ExposureAccountingDescription?: string;
  Program: ReferralProgram; TotalRelationships: number; QualifiedReferrals: number; QualifyingTopupVolume: number;
  PendingLiability: number; PaidRewards: number; WelcomePaid: number; ReservedExposure: number; ExposureLimit: number | null;
  CreditsPaid: number; FailedCredits: number; ExcludedEvents: number; Currency: string; TopupRewardLimits: RewardLimits | null;
}
/** Partner register row. PENDING until approved; only ACTIVE members can invite. */
export interface ReferralMember {
  UserId: number; Name: string; Email: string; Status: string; AssignedAt: string; ExpiresAt: string | null;
  AgreementReference?: string | null; EffectiveFrom?: string | null; EffectiveUntil?: string | null;
  CampaignOwnerUserId?: number | null; Channels?: string[] | null; FundingAllocation?: number | null; Notes?: string | null;
  ApprovedByUserId?: number | null; ApprovedAt?: string | null;
}
export interface MemberRequest {
  Active: boolean; Approve?: boolean; ExpiresAt?: string | null; AgreementReference?: string | null;
  EffectiveFrom?: string | null; EffectiveUntil?: string | null; CampaignOwnerUserId?: number | null;
  Channels?: string[] | null; FundingAllocation?: number | null; Notes?: string | null;
}
export interface ReferralFriend {
  Id: string; Alias: string; Stage: string; AttributedAt: string; KycCompletedAt: string | null; FirstCardAt: string | null;
  FirstTopupAt: string | null; QualifiedAt: string | null; EarningUntil: string | null; EarnedAmount: number; Currency: string;
  RecipientName: string | null;
}
export interface PartnerReport {
  UserId: number; Name: string; Attributed: number; Qualified: number; Earning: number; EligibleVolume: number;
  RewardsPending: number; RewardsPaid: number; Currency: string; Friends: ReferralFriend[];
}
export interface LevelAssignment {
  UserId: number; Name: string; Email: string; LevelId: string; LevelCode: string; LevelName: string;
  AssignedAt: string; ExpiresAt: string | null; RevokedAt: string | null; Notes: string | null;
}
export interface LevelAssignmentRequest { LevelId: string; Active: boolean; ExpiresAt?: string | null; Notes?: string | null }
/**
 * Calculation evidence recorded with a reward (ReferralRewardExplanation on the platform). Basis is the
 * calculation type ("PERCENT_OF_TOPUP", "FIXED", "margin-v1") or, for legacy rows, the event type. Null
 * members were not recorded and must be shown as unknown rather than zero.
 */
export interface RewardExplanation {
  Basis: string; Rate: number | null; OfferVersionId: string | null; TermsVersion: number | null;
  EligibleAmount: number | null; VolumeCap: number | null; Rounding: string; DeliveryExplanation: string;
}
export interface ReferralReward {
  Id: string; EventType: string; BeneficiaryRole: string; LevelCode: string; BasisAmount: number; BasisCurrency: string;
  Amount: number; Currency: string; DeliveryMode: string; Status: string; Stage: string; CreditId: string | null;
  VoucherId: string | null; FriendAlias: string | null; OccurredAt: string; CreatedAt: string; PaidAt: string | null;
  /** Absent on platforms that predate reward explanations. */
  Explanation?: RewardExplanation | null;
}
export interface AdminReward { Reward: ReferralReward; BeneficiaryUserId: number; BeneficiaryEmail: string; SubjectUserId: number; SubjectEmail: string }
export interface RewardFilters { programId?: string | null; status?: string; beneficiaryRole?: string; eventType?: string; page?: number; pageSize?: number }
export interface ReferralCredit {
  Id: string; UserId: number; UserEmail: string; Destination: string; Amount: number; Currency: string; Status: string;
  Attempts: number; LastError: string | null; NextAttemptAt: string | null; ProviderReference: string | null;
  ProviderConfirmedAt: string | null; CreatedAt: string; UpdatedAt: string; RewardIds: string[];
}
export interface WeeklyMetric { WeekStart: string; Attributed: number; Qualified: number; FirstPurchaseWithin30Days: number; RepeatUseWithin30Days: number }
export interface ReferralMetrics {
  Weeks: WeeklyMetric[]; CreditsAttempted: number; CreditsPaid: number; CreditSuccessRate: number; FeesCollected: number;
  ProviderCost: number; RewardCost: number; Contribution: number; Currency: string;
}
export interface Reconciliation {
  GeneratedAt: string; RewardsReady: number; RewardsCrediting: number; RewardsFailed: number; CreditsPending: number;
  CreditsTransferring: number; CreditsConfirming: number; CreditsFailed: number; CreditsStale: number;
  ReservedExposure: number; ExposureLimit: number | null; Currency: string;
}
export interface ReferralOffer {
  OwnerUserId: number; OwnerName: string; OwnerEmail: string; ReferralCode: string;
  ReferredTierId: number | null; ReferredTierName: string | null;
  DiscountCodeId: number | null; DiscountCode: string | null; DiscountDescription: string | null;
  InheritBenefits: boolean; UpdatedAt: string;
}
export interface OfferDraft { OwnerUserId: number | null; ReferredTierId: number | null; DiscountCodeId: number | null; InheritBenefits: boolean }
export interface UserOption { Id: number; Name: string; Email: string }
export interface DiscountOption {
  Id: number; Code: string; Description: string | null; DiscountType: string;
  BuyDiscountPercent: number; MonthlyDiscountPercent: number; YearlyDiscountPercent: number;
  BuyDiscountFixed: number | null; MonthlyDiscountFixed: number | null; YearlyDiscountFixed: number | null;
  TierMonthlyDiscountPercent: number; TierYearlyDiscountPercent: number;
  TierMonthlyDiscountFixed: number | null; TierYearlyDiscountFixed: number | null;
  CardDiscountDurationMonths: number; TierDiscountDurationMonths: number;
}
export interface ReferralOptions { Users: UserOption[]; HasMoreUsers: boolean; Tiers: { Id: number; Name: string }[]; DiscountCodes: DiscountOption[] }

// ---- analytics (GET analytics; mirrors ReferralAnalyticsResponse) ----
/** Relationships attributed in the period. All three rates are percentages (0–100) of Invited. */
export interface ReferralFunnel {
  Invited: number; KycCompleted: number; CardIssued: number; Qualified: number; Earning: number; WindowEnded: number;
  KycRate: number; CardRate: number; QualificationRate: number; MedianHoursToQualify: number | null; AverageHoursToQualify: number | null;
}
export interface ReferralLeaderboardEntry {
  UserId: number; Name: string; Email: string; LevelCode: string | null; Partner: boolean;
  Attributed: number; Qualified: number; EligibleVolume: number; RewardsAccrued: number; RewardsPaid: number;
}
export interface ReferralRewardCost { Welcome: number; Qualification: number; Topup: number; Adjustments: number; Accrued: number; Paid: number; Outstanding: number; Currency: string }
export interface ReferralWeeklyPoint { WeekStart: string; Attributed: number; Qualified: number; TopupVolume: number; RewardsAccrued: number; RewardsPaid: number; CreditsPaid: number }
export interface ReferralProgramStats {
  Id: string; Name: string; Visibility: string; Status: string; Relationships: number; Qualified: number;
  RewardsOutstanding: number; RewardsPaid: number; ReservedExposure: number; ExposureLimit: number | null;
}
export interface ReferralExclusionStat { Reason: string; Count: number; Amount: number }
/** Contribution = fees collected on commissionable top-ups of referred users − provider cost − rewards accrued. */
export interface ReferralAnalytics {
  From: string; To: string; Currency: string; Funnel: ReferralFunnel; Leaderboard: ReferralLeaderboardEntry[]; Cost: ReferralRewardCost;
  Weekly: ReferralWeeklyPoint[]; Programs: ReferralProgramStats[]; Exclusions: ReferralExclusionStat[];
  FeesCollected: number; ProviderCost: number; Contribution: number; AverageTopupPerQualifiedFriend: number; AverageRewardPerQualifiedFriend: number;
}

export const REWARD_STATUSES = ['PENDING', 'READY', 'CREDITING', 'PAID', 'FAILED', 'HELD', 'CANCELLED', 'REVERSED', 'EXPIRED_UNCLAIMED'];
export const REWARD_EVENT_TYPES = ['WELCOME', 'QUALIFICATION', 'CARD_TOPUP', 'ADJUSTMENT'];
export const CREDIT_STATUSES = ['PENDING', 'TRANSFERRING', 'CONFIRMING', 'PAID', 'FAILED', 'CANCELLED'];
export const LEVEL_ICONS = ['sparkles', 'gem', 'star', 'crown', 'trophy', 'rocket', 'shield', 'zap', 'gift', 'award', 'heart', 'flame'];

// Public API versions use PascalCase or camelCase. Normalize field names only, never enum values.
export function normalizeReferral<T>(value: unknown): T {
  if (Array.isArray(value)) return value.map(item => normalizeReferral(item)) as T;
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) =>
    [key.charAt(0).toUpperCase() + key.slice(1), normalizeReferral(item)])) as T;
  return value as T;
}
export const isVoucherDeliveryMode = (mode?: string | null): boolean => mode === 'AUTOMATIC_TRANSFER' || mode === 'VOUCHER_PER_COMMISSION';

export function newLevel(index: number, minimumQualifiedReferrals: number | null = null, minimumTopupVolume: number | null = null): ReferralLevel {
  const palette = ['#7C3AED', '#0891B2', '#D97706', '#DB2777', '#16A34A'];
  return { Id: crypto.randomUUID(), Code: `LEVEL_${index + 1}`, Name: `Level ${index + 1}`, Icon: index === 0 ? 'sparkles' : 'gem', Color: palette[index % palette.length]!,
    DisplayOrder: index, MinimumMetricValue: minimumQualifiedReferrals ?? 0,
    MinimumQualifiedReferrals: minimumQualifiedReferrals, MinimumTopupVolume: minimumTopupVolume,
    QualificationCalculationType: 'FIXED', QualificationRate: 1,
    TopupCalculationType: 'PERCENT_OF_TOPUP', TopupRate: 0.25, Hidden: false, VolumeCapMode: 'INHERIT', VolumeCapAmount: null, RecurringRewardCapMode: 'INHERIT', RecurringRewardCapAmount: null };
}
/** A condition counts as set only when it is a positive number; null, undefined and 0 all mean "no condition". */
export const conditionValue = (value: unknown): number | null => typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : null;
/**
 * Conditions a level carries, as the platform stores them. Levels from a backend that predates the two
 * conditions only have MinimumMetricValue, whose meaning the retired program-wide level basis decided.
 */
export function levelConditions(level: Partial<ReferralLevel>, levelBasis?: string | null): { MinimumQualifiedReferrals: number | null; MinimumTopupVolume: number | null } {
  const hasNewShape = 'MinimumQualifiedReferrals' in level || 'MinimumTopupVolume' in level;
  if (hasNewShape) return { MinimumQualifiedReferrals: conditionValue(level.MinimumQualifiedReferrals), MinimumTopupVolume: conditionValue(level.MinimumTopupVolume) };
  const legacy = conditionValue(level.MinimumMetricValue);
  return levelBasis === 'REFERRED_TOPUP_VOLUME'
    ? { MinimumQualifiedReferrals: null, MinimumTopupVolume: legacy }
    : { MinimumQualifiedReferrals: legacy === null ? null : Math.ceil(legacy), MinimumTopupVolume: null };
}
/** Conditions for a level appended below the current ladder: strictly harder than the last visible level. */
export function nextLevelConditions(levels: ReferralLevel[]): { MinimumQualifiedReferrals: number | null; MinimumTopupVolume: number | null } {
  const visible = levels.filter(level => !level.Hidden);
  if (!visible.length) return { MinimumQualifiedReferrals: null, MinimumTopupVolume: null };
  const last = visible[visible.length - 1]!;
  const qualified = conditionValue(last.MinimumQualifiedReferrals), volume = conditionValue(last.MinimumTopupVolume);
  return { MinimumQualifiedReferrals: qualified !== null || volume === null ? (qualified ?? 0) + 5 : null, MinimumTopupVolume: volume === null ? null : volume + 1000 };
}
/** "$5,000", "€1,250.5", "3 USDT": grouped short money for sentences and labels. */
export function groupedAmount(amount: number, currency: string): string {
  const symbol = currencySymbols[currency.toUpperCase()];
  const text = amount.toLocaleString(undefined, { maximumFractionDigits: 2 });
  return symbol ? `${symbol}${text}` : `${text} ${currency}`;
}
/** "5 referrals · $2,000 top-ups"; "no conditions" for a level without any; "assigned directly" for hidden ones. */
export function levelConditionLabel(level: Pick<ReferralLevel, 'MinimumQualifiedReferrals' | 'MinimumTopupVolume' | 'Hidden'>, currency = 'USD'): string {
  if (level.Hidden) return 'assigned directly';
  const parts: string[] = [];
  const qualified = conditionValue(level.MinimumQualifiedReferrals), volume = conditionValue(level.MinimumTopupVolume);
  if (qualified !== null) parts.push(`${qualified.toLocaleString(undefined, { maximumFractionDigits: 0 })} ${qualified === 1 ? 'referral' : 'referrals'}`);
  if (volume !== null) parts.push(`${groupedAmount(volume, currency)} top-ups`);
  return parts.length ? parts.join(' · ') : 'no conditions';
}
/** Defaults match UpdateReferralProgramRequest on the platform. */
export function defaultProgram(): ReferralProgram {
  return { Exists: false, Id: null, Provider: 'INTERLACE', Name: 'Public referral program', Description: '', Visibility: 'PUBLIC',
    Revision: 1, Status: 'DRAFT', LevelBasis: 'SUCCESSFUL_REFERRAL_COUNT', LevelLookbackMonths: 6,
    EarningWindowDays: 90, EarningWindowStart: 'QUALIFICATION',
    QualifyRequiresKyc: true, QualifyRequiresPaidCard: true, QualifyRequiresTopup: true, QualifyMinimumTopup: null,
    WelcomeAmount: 3, WelcomeCurrency: 'USD', DeliveryMode: 'WALLET_CREDIT', PayoutCurrency: 'USD', VoucherClaimDays: 30,
    MinimumCreditAmount: 0.01, MaxEligibleVolumePerRelationship: null, ExposureLimit: null, ReservedExposure: 0,
    TermsVersion: 1, TermsText: '', PrivacyNotice: '', PublishedAt: null, Levels: [newLevel(0)] };
}
export function privateProgram(): ReferralProgram {
  const level = { ...newLevel(0), Code: 'PARTNER', Name: 'Partner', QualificationRate: 0, TopupRate: 0.5 };
  return { ...defaultProgram(), Name: 'Private referral program', Visibility: 'PRIVATE', Levels: [level] };
}
/** Programs loaded from the API may predate v2 fields; fill the defaults so every control is bound. */
export function withProgramDefaults(program: ReferralProgram): ReferralProgram {
  const base = defaultProgram();
  const merged: ReferralProgram = { ...base, ...program, Levels: (program.Levels ?? []).map((level, index) => ({ ...newLevel(index), ...level, ...levelConditions(level, program.LevelBasis) })) };
  merged.Description ??= '';
  merged.TermsText ??= '';
  merged.PrivacyNotice ??= '';
  return merged;
}
export function rewardMaximum(level: Pick<ReferralLevel, 'TopupCalculationType'>, limits: RewardLimits): number {
  return level.TopupCalculationType === 'FIXED' ? limits.MaxFixedAmount :
    level.TopupCalculationType === 'PERCENT_OF_WL_FEE' ? limits.MaxPercentOfWlFee : limits.MaxPercentOfTopup;
}
/** The actual schedule for one cap. Older APIs without provenance must show a generic formula. */
export function marginBreakdown(limits: RewardLimits | null | undefined, calculation = 'PERCENT_OF_TOPUP'): { fee: number; cost: number; margin: number; creditedBase: number } | null {
  const source = limits?.CapSources?.find(s => s.Calculation === calculation);
  if (!source || source.Availability === 'INVALID_SCHEDULE') return null;
  return { fee: source.FeeRate * 100, cost: source.CostRate * 100, margin: Math.max(0, source.FeeRate - source.CostRate) * 100, creditedBase: (1 - source.FeeRate) * 100 };
}
/** "Name · private · active", with a short id suffix when another programme carries the same name. */
/** Recompute from editable policy; server effective fields may be stale in a draft. */
export function effectiveLevelCaps(program: Pick<ReferralProgram, 'MaxEligibleVolumePerRelationship' | 'MaximumRecurringReward'>, level?: Partial<ReferralLevel>) {
  const resolve = (mode: ReferralCapMode | undefined, amount: number | null | undefined, fallback: number | null | undefined) =>
    mode === 'UNLIMITED' ? null : mode === 'CAPPED' ? amount ?? null : fallback ?? null;
  return { volume: resolve(level?.VolumeCapMode, level?.VolumeCapAmount, program.MaxEligibleVolumePerRelationship),
    recurring: resolve(level?.RecurringRewardCapMode, level?.RecurringRewardCapAmount, program.MaximumRecurringReward) };
}
export function levelCapLabel(program: ReferralProgram, level: ReferralLevel, kind: 'volume' | 'recurring'): string {
  const value = effectiveLevelCaps(program, level)[kind];
  const mode = (kind === 'volume' ? level.VolumeCapMode : level.RecurringRewardCapMode) ?? 'INHERIT';
  const amount = mode === 'CAPPED' && value === null ? 'Amount required' : value === null ? 'No cap' : money(value, program.PayoutCurrency);
  return `${amount} · ${mode === 'INHERIT' ? 'inherited program default' : 'tier override'}`;
}
export function programOptionLabel(program: Pick<ReferralProgram, 'Id' | 'Name' | 'Visibility' | 'Status'>, programs: Pick<ReferralProgram, 'Id' | 'Name'>[], withStatus = true): string {
  const name = program.Name.trim().toLowerCase();
  const duplicate = programs.some(p => p.Id !== program.Id && p.Name.trim().toLowerCase() === name);
  const suffix = duplicate && program.Id ? ` · #${String(program.Id).slice(0, 8)}` : '';
  return `${program.Name} · ${program.Visibility.toLowerCase()}${withStatus ? ` · ${program.Status.toLowerCase()}` : ''}${suffix}`;
}
export function programErrors(program: ReferralProgram, limits: RewardLimits | null | undefined, reviewedPublication = false): string[] {
  const errors: string[] = [];
  const number = (n: unknown, min: number, max: number): n is number => typeof n === 'number' && Number.isFinite(n) && n >= min && n <= max;
  const optional = (n: unknown, min: number, max: number) => n === null || n === undefined || number(n, min, max);
  if (!program.Name.trim() || program.Name.length > 80) errors.push('Enter a program name of 1–80 characters.');
  if ((program.Description?.length ?? 0) > 2000) errors.push('Description must be at most 2000 characters.');
  if (!number(program.LevelLookbackMonths, 0, 1200) || !Number.isInteger(program.LevelLookbackMonths)) errors.push('Level lookback must be whole months between 0 and 1200.');
  if (!number(program.EarningWindowDays, 0, 36500) || !Number.isInteger(program.EarningWindowDays)) errors.push('Earning window must be whole days between 0 and 36500.');
  if (!optional(program.QualifyMinimumTopup, 0, 9999999999)) errors.push('Minimum qualifying top-up must be blank or a non-negative amount.');
  if (reviewedPublication && program.WelcomeCurrency.trim().toUpperCase() !== program.PayoutCurrency.trim().toUpperCase()) errors.push('Welcome currency must match payout currency for reviewed publication.');
  if (!number(program.WelcomeAmount, 0, 9999999999)) errors.push('Welcome amount must be a non-negative amount.');
  if (!number(program.MinimumCreditAmount, 0, 9999999999)) errors.push('Minimum credit amount must be a non-negative amount.');
  if (!optional(program.MaxEligibleVolumePerRelationship, 0, 9999999999)) errors.push('Max eligible volume must be no cap or a non-negative amount.');
  if (!optional(program.MaximumRecurringReward, 0, 9999999999)) errors.push('Maximum recurring reward must be no cap or a non-negative amount.');
  if (!optional(program.ExposureLimit, 0, 9999999999)) errors.push('Exposure limit must be blank or a non-negative amount.');
  if (isVoucherDeliveryMode(program.DeliveryMode) && (!number(program.VoucherClaimDays, 1, 365) || !Number.isInteger(program.VoucherClaimDays))) errors.push('Voucher claim period must be 1–365 whole days.');
  if ((program.TermsText?.length ?? 0) > 20000) errors.push('Terms text must be at most 20000 characters.');
  if ((program.PrivacyNotice?.length ?? 0) > 5000) errors.push('Privacy notice must be at most 5000 characters.');
  if (!limits || ![limits.MaxFixedAmount, limits.MaxPercentOfTopup, limits.MaxPercentOfWlFee].every(n => number(n, 0, Number.MAX_VALUE))) errors.push('Reload reward limits before saving.');
  if (program.Levels.length < 1 || program.Levels.length > 50) errors.push('Add between 1 and 50 levels.');
  const codes = new Set<string>();
  // Mirrors ReferralService on the platform: the first visible level has no conditions; every later visible
  // level has at least one and is strictly harder than the previous visible one. Hidden levels are reached by
  // assignment only, so their conditions are ignored.
  let previousVisible: { MinimumQualifiedReferrals: number | null; MinimumTopupVolume: number | null } | null = null;
  program.Levels.forEach((level, index) => {
    const prefix = `Level ${index + 1}: `;
    for (const [label, mode, amount] of [['volume', level.VolumeCapMode, level.VolumeCapAmount], ['recurring reward', level.RecurringRewardCapMode, level.RecurringRewardCapAmount]] as const) {
      if (mode != null && !['INHERIT', 'UNLIMITED', 'CAPPED'].includes(mode)) errors.push(prefix + `invalid ${label} cap mode.`);
      if (mode === 'CAPPED' && !number(amount, 0, 9999999999)) errors.push(prefix + `${label} cap requires a non-negative amount.`);
    }
    const code = level.Code.trim().toUpperCase();
    if (!code || code.length > 32 || codes.has(code)) errors.push(prefix + 'use a unique code of 1–32 characters.');
    codes.add(code);
    if (!level.Name.trim() || level.Name.length > 80) errors.push(prefix + 'enter a name of 1–80 characters.');
    if (!/^#[0-9a-f]{6}$/i.test(level.Color)) errors.push(prefix + 'enter a six-digit hex color.');
    if (!level.Icon.trim() || level.Icon.length > 40) errors.push(prefix + 'enter an icon name of 1–40 characters.');
    if (!level.Hidden) {
      let valid = true;
      if (!optional(level.MinimumQualifiedReferrals, 0, 1_000_000) || (typeof level.MinimumQualifiedReferrals === 'number' && !Number.isInteger(level.MinimumQualifiedReferrals))) { valid = false; errors.push(prefix + 'minimum qualified referrals must be blank or a whole number up to 1,000,000.'); }
      if (!optional(level.MinimumTopupVolume, 0, 1e14)) { valid = false; errors.push(prefix + 'minimum combined top-ups must be blank or a non-negative amount.'); }
      if (valid) {
        const current = { MinimumQualifiedReferrals: conditionValue(level.MinimumQualifiedReferrals), MinimumTopupVolume: conditionValue(level.MinimumTopupVolume) };
        const set = (c: typeof current) => [c.MinimumQualifiedReferrals, c.MinimumTopupVolume].filter(v => v !== null).length;
        if (previousVisible === null) {
          if (set(current)) errors.push(prefix + 'the first visible level has no conditions.');
        } else if (!set(current)) errors.push(prefix + 'set at least one condition on every level above the first.');
        else {
          // Every condition on the previous level stays set and does not drop; at least one grows or is new.
          const keys = ['MinimumQualifiedReferrals', 'MinimumTopupVolume'] as const;
          const keeps = keys.every(key => previousVisible![key] === null || (current[key] !== null && current[key]! >= previousVisible![key]!));
          const harder = keys.some(key => current[key] !== null && (previousVisible![key] === null || current[key]! > previousVisible![key]!));
          if (!keeps || !harder) errors.push(prefix + 'each level must require more than the previous one.');
        }
        previousVisible = current;
      }
    }
    if (reviewedPublication && level.QualificationCalculationType !== 'FIXED') errors.push(prefix + 'reviewed publication requires a fixed qualification reward; a percentage of the card fee is not supported.');
    if (!number(level.QualificationRate, 0, level.QualificationCalculationType === 'FIXED' ? 9999999999 : 100)) errors.push(prefix + 'invalid qualification reward.');
    if (!number(level.TopupRate, 0, level.TopupCalculationType === 'FIXED' ? 9999999999 : 100)) errors.push(prefix + 'invalid top-up reward.');
    else if (limits && level.TopupRate > rewardMaximum(level, limits)) errors.push(prefix + `top-up reward exceeds the fee-minus-cost maximum of ${rewardMaximum(level, limits)}${level.TopupCalculationType === 'FIXED' ? ` ${program.PayoutCurrency}` : '%'}.`);
  });
  return errors;
}
export function programRequest(program: ReferralProgram, publishNewTermsVersion = false) {
  const { Exists, Id, Provider, UpdatedAt, ReservedExposure, PublishedAt, OfferVersionId, MarginPolicy, ...request } = program;
  return { ...request, Name: request.Name.trim(), Description: request.Description?.trim() || null,
    TermsText: request.TermsText?.trim() || null, PrivacyNotice: request.PrivacyNotice?.trim() || null,
    PublishNewTermsVersion: publishNewTermsVersion,
    Levels: request.Levels.map((level, index) => {
      // Hidden levels carry no conditions; 0 means "no condition" and is stored as null. MinimumMetricValue is
      // the deprecated single threshold and stays equal to the qualified-referrals condition for old readers.
      const conditions = level.Hidden ? { MinimumQualifiedReferrals: null, MinimumTopupVolume: null } : levelConditions(level);
      const { EffectiveVolumeCap, EffectiveRecurringRewardCap, VolumeCapSource, RecurringRewardCapSource, ...editableLevel } = level;
      return { ...editableLevel, VolumeCapMode: level.VolumeCapMode ?? 'INHERIT', VolumeCapAmount: level.VolumeCapMode === 'CAPPED' ? level.VolumeCapAmount : null, RecurringRewardCapMode: level.RecurringRewardCapMode ?? 'INHERIT', RecurringRewardCapAmount: level.RecurringRewardCapMode === 'CAPPED' ? level.RecurringRewardCapAmount : null, ...conditions, MinimumMetricValue: conditions.MinimumQualifiedReferrals ?? 0, Name: level.Name.trim(), Code: level.Code.trim().toUpperCase(), DisplayOrder: index };
    }) };
}

// ---- formatting (kept in sync with the web admin's referral-format.ts) ----
/** "1", "1.5", "0.25": a number without trailing zeros (at most four decimals). */
export function trimNumber(value: number, digits = 2): string {
  if (!Number.isFinite(value)) return '0';
  const text = value.toString(); const dot = text.indexOf('.');
  const decimals = dot === -1 ? 0 : Math.min(4, text.length - dot - 1);
  const fixed = value.toFixed(Math.max(digits, decimals));
  const stripped = fixed.includes('.') ? fixed.replace(/0+$/, '').replace(/\.$/, '') : fixed;
  return stripped === '-0' ? '0' : stripped;
}
const currencySymbols: Record<string, string> = { USD: '$', USDT: 'USDT ', USDC: 'USDC ', EUR: '€', GBP: '£' };
/** "$3", "$1.50", "USDT 3": short money for headlines. */
export function moneyShort(amount: number, currency = 'USD'): string {
  const symbol = currencySymbols[currency.toUpperCase()];
  return symbol ? `${symbol}${trimNumber(amount)}` : `${trimNumber(amount)} ${currency}`;
}
/** Two-decimal money with the currency code, for ledgers and totals. */
export function money(amount: number | null | undefined, currency = 'USD'): string {
  const value = typeof amount === 'number' && Number.isFinite(amount) ? amount : 0;
  return `${value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${currency}`;
}
export function rewardRateLabel(calculation: string, rate: number, currency: string): string {
  if (calculation === 'FIXED') return `${trimNumber(rate)} ${currency}`;
  const basis = calculation === 'PERCENT_OF_WL_FEE' ? 'WL fee' : calculation === 'PERCENT_OF_CARD_FEE' || calculation === 'PERCENT_OF_FEE' ? 'card fee' : 'top-up';
  return `${trimNumber(rate)}% of ${basis}`;
}
/** "$3 for them. $1 + 0.25% for you." generated from program values, never hard-coded. */
export function offerHeadline(program: Pick<ReferralProgram, 'WelcomeAmount' | 'WelcomeCurrency' | 'PayoutCurrency' | 'MarginPolicy'>, level: ReferralLevel | undefined): string {
  const friend = program.WelcomeAmount > 0 ? `${moneyShort(program.WelcomeAmount, program.WelcomeCurrency || 'USD')} for them.` : '';
  const parts: string[] = [];
  if (level && level.QualificationRate > 0) parts.push(level.QualificationCalculationType === 'FIXED' ? moneyShort(level.QualificationRate, program.PayoutCurrency) : `${trimNumber(level.QualificationRate)}% of their card fee`);
  if (program.MarginPolicy) {
    const rate = program.MarginPolicy.Direct.AffiliateBps / 100;
    if (rate > 0) parts.push(`${trimNumber(rate)}% of settled margin`);
  } else if (level && level.TopupRate > 0) parts.push(level.TopupCalculationType === 'FIXED' ? `${moneyShort(level.TopupRate, program.PayoutCurrency)} per top-up` : level.TopupCalculationType === 'PERCENT_OF_WL_FEE' ? `${trimNumber(level.TopupRate)}% of top-up fees` : `${trimNumber(level.TopupRate)}%`);
  const you = parts.join(' + ');
  if (friend && you) return `${friend} ${you} for you.`;
  return friend || (you ? `${you} for you.` : 'Invite friends and earn rewards.');
}
const friendStageLabels: Record<string, string> = { INVITED: 'Invited', VERIFYING: 'Verifying', CARD_ISSUED: 'Card issued', QUALIFIED: 'Qualified', WINDOW_ENDED: 'Window ended' };
export function friendStageLabel(stage: string): string { return friendStageLabels[stage] || stage.toLowerCase().replace(/_/g, ' '); }
const rewardEventLabels: Record<string, string> = { WELCOME: 'Welcome reward', QUALIFICATION: 'Friend qualified', CARD_TOPUP: 'Friend top-up', ADJUSTMENT: 'Adjustment' };
export function rewardEventLabel(eventType: string): string { return rewardEventLabels[eventType] || eventType.toLowerCase().replace(/_/g, ' '); }
export function statusLabel(value: string | null | undefined): string { return (value ?? '').toLowerCase().replace(/_/g, ' '); }
export function statusTone(value: string | null | undefined): string {
  switch (value) {
    case 'ACTIVE': case 'PAID': case 'QUALIFIED': case 'READY': return 'success';
    case 'PENDING': case 'TRANSFERRING': case 'CONFIRMING': case 'CREDITING': case 'HELD': case 'VERIFYING': case 'CARD_ISSUED': return 'warning';
    case 'FAILED': case 'REVOKED': case 'CANCELLED': case 'REVERSED': case 'ARCHIVED': return 'danger';
    default: return 'neutral';
  }
}
export function discountDescription(code: DiscountOption): string {
  const fixed = code.DiscountType === 'fixed';
  const value = (p: number, f: number | null) => fixed ? (f == null ? 'unchanged' : `${f} final price`) : `${p}% off`;
  const duration = (n: number) => n ? `${n} months` : 'no relative expiry';
  return `Card purchase: ${value(code.BuyDiscountPercent, code.BuyDiscountFixed)} · Card monthly: ${value(code.MonthlyDiscountPercent, code.MonthlyDiscountFixed)} · Card yearly: ${value(code.YearlyDiscountPercent, code.YearlyDiscountFixed)} · Tier monthly: ${value(code.TierMonthlyDiscountPercent, code.TierMonthlyDiscountFixed)} · Tier yearly: ${value(code.TierYearlyDiscountPercent, code.TierYearlyDiscountFixed)} · Card duration: ${duration(code.CardDiscountDurationMonths)} · Tier duration: ${duration(code.TierDiscountDurationMonths)}`;
}
