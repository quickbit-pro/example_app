// Labels and signs for classified ledger rows (admin_transactions). Pure and DOM-free so
// tests/transactionKinds.test.mjs can import it the same way as overviewCharts.ts.

export type TransactionDirection = 'in' | 'out' | 'internal' | 'none';

export const KIND_LABELS: Record<string, string> = {
  card_purchase: 'Card purchase',
  card_refund: 'Card refund',
  card_cash: 'ATM withdrawal',
  card_check: 'Card check',
  card_funding: 'Card top-up',
  card_event: 'Card event',
  deposit: 'Deposit',
  withdrawal: 'Withdrawal',
  conversion: 'Conversion',
  transfer: 'Transfer',
  fee: 'Fee',
  fee_refund: 'Fee refund',
  other: 'Other',
};

export const FEE_LABELS: Record<string, string> = {
  card_issuance: 'Card issuance',
  top_up: 'Card top-up',
  card_payment: 'Per purchase',
  decline: 'Declined payment',
  monthly: 'Monthly card',
  exchange: 'Exchange',
  withdrawal: 'Withdrawal',
  transfer: 'Transfer',
  card: 'Card',
  other: 'Other',
};

export const DIRECTION_LABELS: Record<TransactionDirection, string> = {
  in: 'Money in',
  out: 'Money out',
  internal: 'Between own balances',
  none: 'No money moved',
};

export const STATUS_LABELS: Record<string, string> = {
  completed: 'Completed',
  pending: 'Pending',
  failed: 'Failed',
  other: 'Other',
};

/** Order of the type filter: what operators look for first. */
export const KIND_ORDER = ['card_purchase', 'deposit', 'withdrawal', 'fee', 'transfer', 'conversion', 'card_funding', 'card_refund',
  'fee_refund', 'card_check', 'card_cash', 'card_event', 'other'];

export function kindLabel(kind: string | null | undefined, feeType?: string | null): string {
  if (!kind) return 'Other';
  const base = KIND_LABELS[kind] ?? kind.replace(/[_-]+/g, ' ').replace(/^./, c => c.toUpperCase());
  if ((kind === 'fee' || kind === 'fee_refund') && feeType) return `${base} · ${FEE_LABELS[feeType] ?? feeType.replace(/_/g, ' ')}`;
  return base;
}

export function sortKinds(kinds: readonly string[]): string[] {
  const rank = (kind: string) => { const index = KIND_ORDER.indexOf(kind); return index < 0 ? KIND_ORDER.length : index; };
  return [...kinds].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
}

/** "+" for money in, "−" for money out; internal moves and checks carry no sign. */
export function amountSign(direction: string): string {
  return direction === 'in' ? '+' : direction === 'out' ? '−' : '';
}

/** Tailwind colour for an amount: failed and related rows are muted so they never read as money that moved. */
export function amountClass(row: { direction: string; status: string; isPrimary?: boolean; isDuplicate?: boolean }): string {
  if (row.status === 'failed' || row.isDuplicate || row.isPrimary === false) return 'text-slate-400 line-through decoration-slate-300';
  if (row.direction === 'in') return 'text-emerald-700';
  if (row.direction === 'internal' || row.direction === 'none') return 'text-slate-500';
  return 'text-slate-900';
}

export function directionIcon(direction: string): string {
  return direction === 'in' ? 'pi pi-arrow-down-left' : direction === 'out' ? 'pi pi-arrow-up-right' : direction === 'internal' ? 'pi pi-arrow-right-arrow-left' : 'pi pi-minus';
}
