import { apiClient } from '@/lib/apiClient';
import { normalizeReferral, programRequest, withProgramDefaults,
  type ReferralProgram, type ReferralOverview, type ReferralOffer, type ReferralMember, type ReferralOptions, type OfferDraft,
  type MemberRequest, type PartnerReport, type LevelAssignment, type LevelAssignmentRequest, type AdminReward, type RewardFilters,
  type ReferralCredit, type ReferralMetrics, type Reconciliation, type ReferralAnalytics } from '@/lib/referrals';
import { performanceFromResponse, type CampaignLink, type CampaignLinkPerformance, type PerformanceRange } from '@/lib/referralLinks';
const root = '/api/v1/admin/referrals';
const params = (programId?: string | null) => ({ programId: programId || undefined });
const program = (id: string) => `${root}/programs/${encodeURIComponent(id)}`;
async function get<T>(path: string, query = {}) { return normalizeReferral<T>((await apiClient.get(root + path, { params: query })).data); }
export const referralsApi = {
  programs: async () => (await get<ReferralProgram[]>('/programs')).map(withProgramDefaults),
  overview: async (id?: string | null) => {
    const overview = await get<ReferralOverview>('/overview', params(id));
    return { ...overview, Program: withProgramDefaults(overview.Program) };
  },
  offers: (id?: string | null) => get<ReferralOffer[]>('/invite-benefits', params(id)),
  members: (id: string) => get<ReferralMember[]>(`/programs/${encodeURIComponent(id)}/members`),
  memberReport: (id: string, userId: number) => get<PartnerReport>(`/programs/${encodeURIComponent(id)}/members/${userId}/report`),
  levelAssignments: (id: string) => get<LevelAssignment[]>(`/programs/${encodeURIComponent(id)}/level-assignments`),
  rewards: (filters: RewardFilters = {}) => get<AdminReward[]>('/rewards', {
    programId: filters.programId || undefined, status: filters.status || undefined, beneficiaryRole: filters.beneficiaryRole || undefined,
    eventType: filters.eventType || undefined, page: filters.page ?? 1, pageSize: filters.pageSize ?? 100,
  }),
  metrics: (id?: string | null, range: { from?: string; to?: string } = {}) => get<ReferralMetrics>('/metrics', { ...params(id), from: range.from || undefined, to: range.to || undefined }),
  /** Platform defaults when omitted: all programs, last 90 days, top 10 (capped at 100). from/to are ISO timestamps. */
  analytics: (programId?: string | null, from?: string, to?: string, top?: number) =>
    get<ReferralAnalytics>('/analytics', { ...params(programId), from: from || undefined, to: to || undefined, top: top || undefined }),
  credits: (status?: string, page = 1, pageSize = 100) => get<ReferralCredit[]>('/credits', { status: status || undefined, page, pageSize }),
  reconciliation: () => get<Reconciliation>('/reconciliation'),
  options: (search = '') => get<ReferralOptions>('/options', { search }),
  save: async (draft: ReferralProgram, create: boolean, publishNewTermsVersion = false) => withProgramDefaults(normalizeReferral<ReferralProgram>((await apiClient.request({
    method: create ? 'POST' : 'PUT', url: root + (create ? '/programs' : '/program'),
    params: create ? undefined : params(draft.Id), data: programRequest(draft, publishNewTermsVersion),
  })).data)),
  saveOffer: async (id: string, offer: OfferDraft) => { await apiClient.put(root + '/invite-benefits', offer, { params: params(id) }); },
  saveMember: async (id: string, userId: number, request: MemberRequest) => { await apiClient.put(`${program(id)}/members/${userId}`, request); },
  saveLevelAssignment: async (id: string, userId: number, request: LevelAssignmentRequest) => { await apiClient.put(`${program(id)}/level-assignments/${userId}`, request); },
  /** Campaign links across members. 404 = the platform predates campaign links; the view hides the tab. */
  links: (filters: { programId?: string | null; ownerUserId?: number | null; status?: string } = {}) =>
    get<CampaignLink[]>('/links', { programId: filters.programId || undefined, ownerUserId: filters.ownerUserId || undefined, status: filters.status || undefined }),
  setLinkStatus: async (linkId: string, status: string) => normalizeReferral<CampaignLink>((await apiClient.patch(`${root}/links/${encodeURIComponent(linkId)}`, { Status: status })).data),
  /** Addendum A: one link's figures for a period, any owner. 404 = the platform predates the route; the drawer falls back to the link's counters. */
  linkPerformance: async (linkId: string, range: PerformanceRange = '30d'): Promise<CampaignLinkPerformance> =>
    performanceFromResponse(await get<Partial<CampaignLinkPerformance>>(`/links/${encodeURIComponent(linkId)}/performance`, { range })),
  retryCredit: async (creditId: string) => { await apiClient.post(`${root}/credits/${encodeURIComponent(creditId)}/retry`, {}); },
  cancelCredit: async (creditId: string, reason: string) => { await apiClient.post(`${root}/credits/${encodeURIComponent(creditId)}/cancel`, { Reason: reason }); },
};
