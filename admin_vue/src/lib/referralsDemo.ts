// Built-in sample dataset for the referral Performance tab. Shown only behind the "Show sample data"
// switch when the period has no relationships (or the platform has no analytics endpoint yet), so the
// tab can be previewed before the programme has traffic. Rendered locally, never sent to the platform.
// Figures match the design preview: 12 weeks, funnel 340 → 212 → 168 → 121 → 97 → 24, contribution 590 USD.
import type { Reconciliation, ReferralAnalytics, ReferralLeaderboardEntry, ReferralWeeklyPoint } from '@/lib/referrals';

const CURRENCY = 'USD';
/** Mondays from 15 June 2026, twelve weeks up to 31 August 2026. */
const weekStart = (index: number) => new Date(Date.UTC(2026, 5, 15 + 7 * index)).toISOString();
const weeklyRows: [number, number, number, number, number, number][] = [
  // attributed, qualified, top-up volume, rewards accrued, rewards paid, credits paid
  [12, 3, 1400, 26, 22, 0], [18, 6, 2900, 49, 44, 3], [24, 9, 4600, 78, 72, 5], [29, 11, 6100, 96, 90, 7],
  [27, 10, 6800, 104, 98, 8], [33, 13, 8200, 128, 120, 9], [38, 15, 9600, 149, 138, 11], [31, 12, 9100, 132, 122, 10],
  [36, 14, 10400, 151, 136, 9], [34, 12, 10900, 142, 118, 10], [30, 9, 11300, 112, 60, 8], [28, 7, 11100, 91, 30, 7],
];
const weekly: ReferralWeeklyPoint[] = weeklyRows.map(([Attributed, Qualified, TopupVolume, RewardsAccrued, RewardsPaid, CreditsPaid], index) =>
  ({ WeekStart: weekStart(index), Attributed, Qualified, TopupVolume, RewardsAccrued, RewardsPaid, CreditsPaid }));

const leaderRows: [string, number, number, number, number, number, boolean][] = [
  // name, attributed, qualified, eligible volume, rewards accrued, rewards paid, partner
  ['Maja Kovač', 41, 19, 18400, 146, 131, true], ['Luka Horvat', 27, 12, 11200, 79, 71, false], ['Nina Zupan', 22, 10, 8900, 66, 60, false],
  ['Tim Rozman', 19, 8, 7700, 52, 44, true], ['Eva Potočnik', 16, 7, 6100, 46, 41, false], ['Jan Kralj', 14, 6, 4900, 37, 33, false],
  ['Sara Mlakar', 12, 5, 4300, 31, 29, false], ['Nik Bizjak', 11, 5, 3800, 28, 22, false], ['Ana Vidmar', 9, 4, 3100, 24, 24, false], ['Rok Petek', 8, 3, 2200, 18, 14, false],
];
const email = (name: string) => `${name.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, '.')}@example.com`;
const leaderboard: ReferralLeaderboardEntry[] = leaderRows.map(([Name, Attributed, Qualified, EligibleVolume, RewardsAccrued, RewardsPaid, Partner], index) => ({
  UserId: 1001 + index, Name, Email: email(Name), LevelCode: Partner ? 'CREATOR' : Qualified >= 10 ? 'GOLD' : Qualified >= 5 ? 'SILVER' : 'BRONZE', Partner,
  Attributed, Qualified, EligibleVolume, RewardsAccrued, RewardsPaid,
}));

const sum = (pick: (week: ReferralWeeklyPoint) => number) => weekly.reduce((total, week) => total + pick(week), 0);
const invited = sum(w => w.Attributed); // 340
const qualified = sum(w => w.Qualified); // 121
const accrued = sum(w => w.RewardsAccrued); // 1258
const paid = sum(w => w.RewardsPaid); // 1050
const rate = (n: number) => Math.round((10000 * n) / invited) / 100;

export const DEMO_ANALYTICS: ReferralAnalytics = {
  From: '2026-06-14T00:00:00.000Z', To: '2026-09-11T23:59:59.000Z', Currency: CURRENCY,
  Funnel: { Invited: invited, KycCompleted: 212, CardIssued: 168, Qualified: qualified, Earning: 97, WindowEnded: 24,
    KycRate: rate(212), CardRate: rate(168), QualificationRate: rate(qualified), MedianHoursToQualify: 55.2, AverageHoursToQualify: 98.4 },
  Leaderboard: leaderboard,
  Cost: { Welcome: 363, Qualification: 121, Topup: 774, Adjustments: 0, Accrued: accrued, Paid: paid, Outstanding: accrued - paid, Currency: CURRENCY },
  Weekly: weekly,
  Programs: [
    { Id: 'demo-public', Name: 'Invite & Earn', Visibility: 'PUBLIC', Status: 'ACTIVE', Relationships: 296, Qualified: 104, RewardsOutstanding: 171, RewardsPaid: 862, ReservedExposure: 1438, ExposureLimit: 2000 },
    { Id: 'demo-creators', Name: 'Creators', Visibility: 'PRIVATE', Status: 'ACTIVE', Relationships: 44, Qualified: 17, RewardsOutstanding: 37, RewardsPaid: 188, ReservedExposure: 476, ExposureLimit: null },
  ],
  Exclusions: [
    { Reason: 'OUTSIDE_EARNING_WINDOW', Count: 18, Amount: 4120 }, { Reason: 'REWARD_OR_INTERNAL_FUNDS', Count: 7, Amount: 610 },
    { Reason: 'VOLUME_CAP_REACHED', Count: 3, Amount: 1900 }, { Reason: 'NO_MARGIN', Count: 5, Amount: 240 },
  ],
  FeesCollected: 2310, ProviderCost: 462, Contribution: 2310 - 462 - accrued,
  AverageTopupPerQualifiedFriend: Math.round((100 * sum(w => w.TopupVolume)) / qualified) / 100,
  AverageRewardPerQualifiedFriend: Math.round((100 * accrued) / qualified) / 100,
};
/** All-time credit counters behind the "Credit success rate" tile (61 paid, 2 failed → 96.8%). */
export const DEMO_CREDITS = { paid: 61, failed: 2 };
export const DEMO_RECONCILIATION: Reconciliation = {
  GeneratedAt: '2026-09-11T08:00:00.000Z', RewardsReady: 14, RewardsCrediting: 0, RewardsFailed: 0, CreditsPending: 3, CreditsTransferring: 1,
  CreditsConfirming: 2, CreditsFailed: 1, CreditsStale: 0, ReservedExposure: 1914, ExposureLimit: null, Currency: CURRENCY,
};
