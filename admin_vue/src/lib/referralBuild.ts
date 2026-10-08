import { apiClient } from './apiClient';
import { normalizeReferral, programRequest, type ReferralProgram } from './referrals';
export interface Capabilities { MarginSharingEnabled: boolean; SubpartnersEnabled: boolean }
export interface Allocation { CompanyBps: number; AffiliateBps: number; SubpartnerBps: number; CustomerBps: number; BudgetBps: number }
export interface MarginPolicy { Direct: Allocation; Team: Allocation | null }
export interface DraftRequest { Policy: ReturnType<typeof programRequest>; Margin: MarginPolicy | null; DraftRevision?: number }
export interface Draft { Id: string; BaseRevision: number; DraftRevision: number; Status: string; Draft: DraftRequest; EffectiveAt: string | null; Reason: string | null }
export interface Preview { DraftId: string; DraftRevision: number; Hash: string; ExpiresAt: string; EffectiveAt: string; ExistingQualified: number; ExistingUnqualified: number; Cohort: string; ChangedFields: string[]; TermsAcceptanceRequired: boolean; Warnings: string[] }
export interface Simulation { CalculationVersion: string; Currency: string; Basis: string; EligibleAmount: number; InviterReward: number | null; CustomerRecurringReward: number | null; SubpartnerReward: number | null; CompanyRetained: number | null; QualificationReward: number; WelcomeReward: number; Status: string; Warnings: string[] }
export const emptyAllocation = (): Allocation => ({ CompanyBps: 10000, AffiliateBps: 0, SubpartnerBps: 0, CustomerBps: 0, BudgetBps: 0 });
export function allocationErrors(a: Allocation, team: boolean): string[] {
  const values = Object.values(a);
  if (values.some(v => !Number.isInteger(v) || v < 0 || v > 10000)) return ['Use whole basis points between 0 and 10000.'];
  const errors: string[] = [];
  if (a.CompanyBps + a.AffiliateBps + a.SubpartnerBps + a.CustomerBps !== 10000) errors.push('All shares must total 10000 basis points (100%).');
  if (a.AffiliateBps + a.SubpartnerBps + a.CustomerBps > a.BudgetBps) errors.push('Recipient shares exceed the approved budget.');
  if (!team && a.SubpartnerBps !== 0) errors.push('Direct routes cannot pay a subpartner.');
  return errors;
}
export function draftRequest(program: ReferralProgram, margin: MarginPolicy | null, revision?: number): DraftRequest {
  return { Policy: programRequest(program), Margin: margin, DraftRevision: revision };
}
/** 404 and 503 from GET capabilities mean the connected platform has no versioned publishing; anything else is a failure to retry. */
export function isBuildUnavailable(error: unknown): boolean {
  const status = (error as { response?: { status?: number } })?.response?.status;
  return status === 404 || status === 503;
}
/** 409 from a save: the server copy moved on (revision or draft revision); keep the input and let the admin compare. */
export function isConflict(error: unknown): boolean {
  return (error as { response?: { status?: number } })?.response?.status === 409;
}
const root = '/api/v1/admin/referrals';
const path = (programId: string) => `${root}/programs/${encodeURIComponent(programId)}`;
async function request<T>(method: string, url: string, data?: unknown): Promise<T> { return normalizeReferral<T>((await apiClient.request({ method, url, data })).data); }
export const referralBuildApi = {
  capabilities: () => request<Capabilities>('GET', `${root}/capabilities`),
  versions: (p: string) => request<Draft[]>('GET', `${path(p)}/versions`),
  saveDraft: (p: string, d: DraftRequest, id?: string) => request<Draft>(id ? 'PUT' : 'POST', `${path(p)}/drafts${id ? `/${encodeURIComponent(id)}` : ''}`, d),
  preview: (p: string, d: Draft, effectiveAt: string) => request<Preview>('POST', `${path(p)}/drafts/${d.Id}/change-preview`, { DraftRevision: d.DraftRevision, EffectiveAt: effectiveAt }),
  publish: (p: string, preview: Preview, reason: string, key: string) => request<Draft>('POST', `${path(p)}/drafts/${preview.DraftId}/publish`, { PreviewHash: preview.Hash, Reason: reason, IdempotencyKey: key }),
  team: (p: string) => request<Record<string, number>>('GET', `${path(p)}/team`),
  setParent: (p: string, child: number, parent: number) => request<void>('PUT', `${path(p)}/team/${child}/${parent}`),
  simulate: (p: string, data: unknown) => request<Simulation>('POST', `${path(p)}/simulate`, data),
};
