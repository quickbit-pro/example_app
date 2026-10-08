// Sample dataset for the Overview page, shown behind a "Sample data" banner when the workspace has
// no customers yet or the overview request fails. Deterministic (seeded) so screenshots and tests
// are stable; only type imports, so tests/overviewCharts.test.mjs can transpile it on its own.
import type { InsightsResponse, OverviewData } from '@/lib/operationsApi';

export interface OverviewReferralSummary {
  qualified: number;
  contribution: number;
  currency: string;
  /** Weekly qualified referrals, oldest first, for the KPI sparkline. */
  weeklyQualified: number[];
  creditsFailed: number;
  /** Rewards the referral programme accrued in the period; a cost against fee revenue. */
  rewardsAccrued: number;
}

/** Small deterministic PRNG (mulberry32) so the sample is identical on every load. */
function seeded(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const isoDay = (date: Date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;

const round = (value: number) => Math.round(value * 100) / 100;

export function buildOverviewDemo(rangeDays = 30, now = new Date()): OverviewData {
  const random = seeded(20260911 + rangeDays);
  const days: string[] = [];
  for (let offset = rangeDays - 1; offset >= 0; offset -= 1) days.push(isoDay(new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset, 12)));

  // 10–20 sign-ups a day with a gentle upward trend and quieter weekends; money follows the customer base.
  const series = days.map((date, index) => {
    const weekend = new Date(date + 'T12:00:00').getDay() % 6 === 0;
    const growth = 12 + (4 * index) / Math.max(1, rangeDays - 1);
    const signups = Math.max(10, Math.min(20, Math.round(growth + (random() - 0.5) * 6 - (weekend ? 2 : 0))));
    const purchases = 40 + Math.round(random() * 30) + index;
    const spend = round(purchases * (22 + random() * 14));
    const declines = Math.round(purchases * (0.06 + random() * 0.05));
    return {
      date, signups, approvals: Math.round(signups * (0.55 + random() * 0.2)),
      deposits: round(2_400 + random() * 1_800 + index * 40), withdrawals: round(300 + random() * 500),
      spend, declines, declinedAmount: round(declines * (30 + random() * 25)), fees: round(purchases * 0.35 + signups * 0.6 + random() * 20),
    };
  });
  const sum = (key: 'signups' | 'approvals' | 'deposits' | 'withdrawals' | 'spend' | 'declines' | 'declinedAmount' | 'fees') =>
    round(series.reduce((total, day) => total + day[key], 0));
  const newCustomers = sum('signups');
  const customers = 312 + newCustomers;
  const approved = Math.round(customers * 0.64);
  const funded = Math.round(approved * 0.58);
  const purchases = Math.round(sum('spend') / 29);
  const fees = sum('fees');
  const transacting = Math.round(funded * 0.82);
  const metric = (current: number, factor: number) => ({ current, previous: Math.round(current * factor) });
  const cohortCount = rangeDays >= 90 ? 13 : 8;
  const amount = (value: number, count: number, factor: number) => ({ amount: value, count, previousAmount: round(value * factor), previousCount: Math.round(count * factor) });

  return {
    attention: [
      { customerId: 'demo-1042', customerName: 'Lena Kovács', customerType: 'individual', priority: 1, reason: 'Verification stuck for 3 days', tone: 'danger', ageHours: 74 },
      { customerId: 'demo-0987', customerName: 'Northwind Studio Kft.', customerType: 'business', priority: 2, reason: 'Business documents expire in 5 days', tone: 'warning', ageHours: 20 },
      { customerId: 'demo-1101', customerName: 'Marek Nowak', customerType: 'individual', priority: 3, reason: 'Card order waiting for funds', tone: 'warning', ageHours: 9 },
    ],
    balances: [{ currency: 'USD', amount: 128_400 }, { currency: 'USDT', amount: 41_250 }, { currency: 'USDC', amount: 19_870 }],
    cards: {
      activeCardholders: metric(Math.round(funded * 0.71), 0.86),
      averageTicket: round(sum('spend') / purchases),
      cash: { amount: 0, count: 0 },
      checks: Math.round(funded * 0.4),
      declineRate: round((100 * sum('declines')) / (sum('declines') + purchases)),
      declines: { amount: sum('declinedAmount'), count: sum('declines') },
      previousDeclineRate: 10.4,
      spend: amount(sum('spend'), purchases, 0.84),
    },
    cohorts: Array.from({ length: cohortCount }, (_, index) => {
      const weeksAgo = cohortCount - 1 - index;
      const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7) - 7 * weeksAgo, 12);
      const size = 70 + Math.round(random() * 40);
      return { size, weekStart: isoDay(monday), weeks: Array.from({ length: weeksAgo + 1 }, (_week, offset) => {
        const rate = Math.round((offset === 0 ? 38 : 24 - offset * 1.2 + random() * 6) * 10) / 10;
        return { offset, rate, active: Math.round((size * rate) / 100) };
      }) };
    }),
    declines: {
      byCard: [{ lastFour: '4821', count: 9 }, { lastFour: '1177', count: 6 }, { lastFour: '9034', count: 4 }],
      byMerchant: [
        { name: 'OPENAI', declined: 31, attempts: 88, rate: 35.2, amount: 1_240 },
        { name: 'STEAM PURCHASE', declined: 18, attempts: 61, rate: 29.5, amount: 540 },
        { name: 'UBER', declined: 9, attempts: 190, rate: 4.7, amount: 164 },
      ],
      byReason: [{ reason: 'Insufficient funds', count: 44 }, { reason: 'Merchant category blocked', count: 21 }, { reason: 'No reason given', count: 12 }],
    },
    freshness: { state: 'current', staleCustomers: 0, errorCustomers: 0 },
    from: new Date(now.getTime() - (rangeDays - 1) * 86_400_000).toISOString(),
    generatedAt: new Date(now.getTime() - 60_000).toISOString(),
    funnel: [
      { key: 'signed_up', label: 'Signed up', value: customers },
      { key: 'started', label: 'Started onboarding', value: Math.round(customers * 0.82) },
      { key: 'submitted', label: 'Submitted verification', value: Math.round(customers * 0.71) },
      { key: 'approved', label: 'Approved', value: approved },
      { key: 'funded', label: 'Added money', value: funded },
      { key: 'carded', label: 'Got a card', value: Math.round(funded * 0.86) },
      { key: 'purchased', label: 'Used the card', value: Math.round(funded * 0.74) },
    ],
    kpis: {
      activationRate: round((100 * funded) / approved), activeCards: Math.round(funded * 1.1), approvals: metric(sum('approvals'), 0.9),
      approvedCustomers: approved, cardsIssued: metric(Math.round(sum('approvals') * 0.7), 0.8), customers, engagedCustomers: Math.round(customers * 0.52),
      fundedCustomers: funded, newCustomers: metric(newCustomers, 0.88), transactingCustomers: metric(transacting, 0.9), verifiedRate: round((100 * approved) / customers),
    },
    money: {
      conversions: 214, deposits: amount(sum('deposits'), 640, 0.91), fundsHeld: 189_520, netDeposits: round(sum('deposits') - sum('withdrawals')),
      transfers: { amount: 8_420, count: 132 }, unconvertedCurrencies: [], withdrawals: amount(sum('withdrawals'), 96, 1.1),
    },
    previousFrom: new Date(now.getTime() - (2 * rangeDays - 1) * 86_400_000).toISOString(),
    rangeDays,
    reportingCurrency: 'USD',
    revenue: {
      byType: [
        { type: 'card_issuance', label: 'Card issuance', amount: round(fees * 0.38), count: 64 },
        { type: 'top_up', label: 'Card top-up', amount: round(fees * 0.27), count: 402 },
        { type: 'card_payment', label: 'Per purchase', amount: round(fees * 0.2), count: 1_180 },
        { type: 'monthly', label: 'Monthly card', amount: round(fees * 0.1), count: 180 },
        { type: 'decline', label: 'Declined payment', amount: round(fees * 0.05), count: 96 },
      ],
      fees: amount(fees, 1_922, 0.87),
      onDeclinedPayments: { amount: round(fees * 0.07), count: 180 },
      perActiveCardholder: round(fees / Math.round(funded * 0.71)),
      perTransactingCustomer: round(fees / transacting),
    },
    segments: {
      appVersion: [{ key: '2.4.0', customers: 410, approved: 300, funded: 190, transacting: 160, spend: round(sum('spend') * 0.7), fees: round(fees * 0.7) },
        { key: '2.3.1', customers: 160, approved: 104, funded: 55, transacting: 41, spend: round(sum('spend') * 0.2), fees: round(fees * 0.2) },
        { key: 'Unknown', customers: customers - 570, approved: approved - 404, funded: funded - 245, transacting: 12, spend: round(sum('spend') * 0.1), fees: round(fees * 0.1) }],
      country: [{ key: 'DE', customers: Math.round(customers * 0.61), approved: Math.round(approved * 0.63), funded: Math.round(funded * 0.66), transacting: Math.round(transacting * 0.64), spend: round(sum('spend') * 0.6), fees: round(fees * 0.62) },
        { key: 'TR', customers: Math.round(customers * 0.22), approved: Math.round(approved * 0.2), funded: Math.round(funded * 0.21), transacting: Math.round(transacting * 0.24), spend: round(sum('spend') * 0.3), fees: round(fees * 0.28) },
        { key: 'Unknown', customers: Math.round(customers * 0.17), approved: Math.round(approved * 0.17), funded: Math.round(funded * 0.13), transacting: Math.round(transacting * 0.12), spend: round(sum('spend') * 0.1), fees: round(fees * 0.1) }],
      platform: [{ key: 'iOS', customers: Math.round(customers * 0.58), approved: Math.round(approved * 0.6), funded: Math.round(funded * 0.62), transacting: Math.round(transacting * 0.6), spend: round(sum('spend') * 0.62), fees: round(fees * 0.6) },
        { key: 'Android', customers: Math.round(customers * 0.3), approved: Math.round(approved * 0.29), funded: Math.round(funded * 0.28), transacting: Math.round(transacting * 0.3), spend: round(sum('spend') * 0.28), fees: round(fees * 0.3) },
        { key: 'Web', customers: Math.round(customers * 0.12), approved: Math.round(approved * 0.11), funded: Math.round(funded * 0.1), transacting: Math.round(transacting * 0.1), spend: round(sum('spend') * 0.1), fees: round(fees * 0.1) }],
      source: [{ key: 'Organic', customers: Math.round(customers * 0.78), approved: Math.round(approved * 0.76), funded: Math.round(funded * 0.72), transacting: Math.round(transacting * 0.72), spend: round(sum('spend') * 0.7), fees: round(fees * 0.7) },
        { key: 'Referral', customers: Math.round(customers * 0.22), approved: Math.round(approved * 0.24), funded: Math.round(funded * 0.28), transacting: Math.round(transacting * 0.28), spend: round(sum('spend') * 0.3), fees: round(fees * 0.3) }],
    },
    series,
    stages: [
      { stage: 'signed_up', count: customers - Math.round(customers * 0.82) }, { stage: 'onboarding', count: Math.round(customers * 0.11) },
      { stage: 'in_review', count: Math.round(customers * 0.05) }, { stage: 'rejected', count: Math.round(customers * 0.02) },
      { stage: 'approved', count: approved - funded }, { stage: 'funded', count: funded - Math.round(funded * 0.86) },
      { stage: 'carded', count: Math.round(funded * 0.12) }, { stage: 'active', count: Math.round(funded * 0.62) }, { stage: 'dormant', count: Math.round(funded * 0.12) },
    ],
    support: { awaiting: 2, oldestWaitingHours: 30 },
    testCustomers: 3,
    timeZone: 'Europe/Berlin',
    to: now.toISOString(),
    topMerchants: [
      { name: 'AMAZON', amount: round(sum('spend') * 0.12), count: 210 },
      { name: 'UBER', amount: round(sum('spend') * 0.07), count: 180 },
      { name: 'OPENAI', amount: round(sum('spend') * 0.05), count: 96 },
      { name: 'SPOTIFY', amount: round(sum('spend') * 0.02), count: 88 },
    ],
    updatedAt: new Date(now.getTime() - 14 * 60_000).toISOString(),
    verificationAging: { pending: 6, over24Hours: 2, rejected: 1 },
  };
}

export const DEMO_REFERRALS: OverviewReferralSummary = { qualified: 23, contribution: 412.5, currency: 'USD', weeklyQualified: [2, 4, 3, 6, 8], creditsFailed: 1, rewardsAccrued: 184 };

export const DEMO_INSIGHTS: InsightsResponse = {
  generatedAt: new Date(2026, 8, 11, 9, 55).toISOString(),
  headline: 'Card spend grew 19% while 1 in 3 OPENAI payments was declined.',
  items: [
    { title: '221 approved customers have not added money', detail: '39% of approved customers never funded their account; that is the largest group stuck in the journey.', tone: 'bad', area: 'customers', link: '/customers?stage=approved' },
    { title: 'Declines concentrated at OPENAI', detail: '31 of 88 OPENAI payments were declined (35%), against 9.9% overall. Raise the merchant category with the card provider.', tone: 'bad', area: 'cards', link: '/money?kind=card_purchase&status=failed' },
    { title: 'Fees up 15%', detail: 'Card issuance and top-up fees drove the increase; $1,000 per week on average.', tone: 'good', area: 'revenue', link: '/money?kind=fee&status=completed' },
  ],
  model: 'deepseek/deepseek-v4.1-flash',
  notice: null,
  rangeDays: 30,
  source: 'ai',
};
