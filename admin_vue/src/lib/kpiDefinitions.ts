// What each Overview figure means, shown in the (i) tooltip of its tile. Keep in sync with
// backend/src/NeoBanking.Api/Admin/AdminKpiService.cs; tests/kpiDefinitions.test.mjs checks every key is filled.

export const KPI_DEFINITIONS = {
  newCustomers: 'Customers who signed up in the period. Test accounts are left out of every figure.',
  approvals: 'Customers whose verification was approved in the period.',
  addedMoney: 'Share of approved customers who ever received money: a deposit, a transfer from another customer, a balance above zero or a card.',
  transacting: 'Customers who started a completed money movement in the period: deposit, withdrawal, card purchase, card top-up, conversion or a transfer they sent.',
  deposits: 'Completed deposits from outside the programme. Conversions and card top-ups move the customer’s own money and are not deposits.',
  withdrawals: 'Completed withdrawals out of the programme.',
  netNewMoney: 'Deposits minus withdrawals in the period.',
  customerFunds: 'Sum of current customer balances from the latest refresh, in USD with USD stablecoins counted 1:1.',
  cardSpend: 'Settled card purchases minus card refunds. Declined or pending payments and zero-amount card checks are left out.',
  activeCardholders: 'Customers with at least one settled card purchase in the period.',
  declineRate: 'Declined card purchases divided by all purchase attempts (settled plus declined). Change is shown in percentage points.',
  cardsIssued: 'Cards issued in the period. Card checks are zero-amount authorisations, for example when a card is added to Apple Pay or Google Pay.',
  fees: 'Completed fees charged to customers minus refunded fees. Provider costs are not deducted.',
  feesOnDeclines: 'Decline fees plus per-purchase fees charged on card payments that were declined.',
  referral: 'Qualified referrals and the referral programme’s contribution in the period.',
} as const;

export type KpiKey = keyof typeof KPI_DEFINITIONS;

/** Tooltip text: the definition, then where the figure comes from and how fresh it is. */
export function kpiInfo(key: KpiKey, asOf: string): string {
  return `${KPI_DEFINITIONS[key]}\n\nSource: provider transactions and customer records, refreshed about every 15 minutes. ${asOf}`;
}
