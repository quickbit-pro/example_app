// Customer journey stages (backend: Admin/AdminCustomerStages.cs). Pure, so tests import it directly.

export interface StageInfo {
  key: string;
  label: string;
  description: string;
  tone: 'accent' | 'warning' | 'positive' | 'neutral' | 'danger';
  /** Name of the reminder email for customers in this stage, when one exists. */
  reminder?: string;
}

export const STAGES: StageInfo[] = [
  { key: 'signed_up', label: 'Not started', description: 'Signed up but never started onboarding.', tone: 'neutral', reminder: 'Finish signing up' },
  { key: 'onboarding', label: 'In onboarding', description: 'Started onboarding but has not submitted verification.', tone: 'warning', reminder: 'Finish signing up' },
  { key: 'in_review', label: 'In review', description: 'Verification submitted and waiting for a decision.', tone: 'accent' },
  { key: 'rejected', label: 'Rejected', description: 'Verification was not approved.', tone: 'danger' },
  { key: 'approved', label: 'Approved, no money', description: 'Verified but has not added money yet.', tone: 'warning', reminder: 'Add money' },
  { key: 'funded', label: 'Money, no card', description: 'Added money but has no card yet.', tone: 'warning', reminder: 'Get a card' },
  { key: 'carded', label: 'Card not used', description: 'Has a card but has never paid with it.', tone: 'warning', reminder: 'Use your card' },
  { key: 'active', label: 'Active', description: 'Paid with the card before and moved money in the last 30 days.', tone: 'positive' },
  { key: 'dormant', label: 'Dormant', description: 'Paid with the card before but nothing in the last 30 days.', tone: 'neutral', reminder: 'Come back' },
];

export function stageInfo(key: string | null | undefined): StageInfo | undefined {
  return STAGES.find(stage => stage.key === key);
}

export function stageLabel(key: string | null | undefined): string {
  return stageInfo(key)?.label ?? (key ? key.replace(/_/g, ' ') : 'Unknown');
}

export function hasReminder(key: string | null | undefined): boolean {
  return Boolean(stageInfo(key)?.reminder);
}

export const STAGE_TONE_CLASS: Record<StageInfo['tone'], string> = {
  accent: 'bg-blue-50 text-blue-700',
  warning: 'bg-amber-50 text-amber-800',
  positive: 'bg-emerald-50 text-emerald-700',
  neutral: 'bg-slate-100 text-slate-600',
  danger: 'bg-red-50 text-red-700',
};
