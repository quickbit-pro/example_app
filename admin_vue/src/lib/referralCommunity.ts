import { apiClient } from '@/lib/apiClient';
import { normalizeReferral } from '@/lib/referrals';
export interface CommunityPolicy { Enabled: boolean; Revision: number; BudgetBps: number; CommunityL2Bps: number; CommunityL3Bps: number; LeaderL2Bps: number; LeaderL3Bps: number }
export interface CommunityMember { Id: string; UserId: number; Plan: string; ParentUserId: number | null; PlanRevision: number; L2Bps: number; L3Bps: number; EnabledAt: string; ExpiresAt: string | null; RevokedAt: string | null; Status: string; AgreementReference: string | null; Notes: string | null }
export interface CommunityEnable { Plan: 'LEADER' | 'COMMUNITY'; ParentUserId: number | null; ExpiresAt: string | null; AgreementReference: string | null; Notes: string | null }
const path = (programId: string) => `/api/v1/admin/referrals/programs/${encodeURIComponent(programId)}/community`;
export const communityApi = {
  policy: async (id: string) => normalizeReferral<CommunityPolicy>((await apiClient.get(`${path(id)}/policy`)).data),
  savePolicy: async (id: string, policy: CommunityPolicy) => normalizeReferral<CommunityPolicy>((await apiClient.put(`${path(id)}/policy`, policy)).data),
  members: async (id: string) => normalizeReferral<CommunityMember[]>((await apiClient.get(`${path(id)}/members`)).data),
  enable: async (id: string, user: number, body: CommunityEnable) => normalizeReferral<CommunityMember>((await apiClient.post(`${path(id)}/members/${user}/enable`, body)).data),
  revoke: async (id: string, user: number, reason: string) => normalizeReferral<CommunityMember>((await apiClient.post(`${path(id)}/members/${user}/revoke`, { Reason: reason })).data),
};
export function communityVolumeEquivalent(bps: number, marginPercent = 2): string { return `${(bps / 10000 * marginPercent).toFixed(2)}%`; }
