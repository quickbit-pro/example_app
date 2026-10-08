// Campaign links (contract 2026-09-15): a member's tracking links as the admin sees them. Field names
// mirror ReferralCampaignLinkResponse; responses are normalised to PascalCase by normalizeReferral.
// A link never carries a rate or any authority to change one; the admin only changes its status.

export type CampaignLinkStatus = 'DRAFT' | 'ACTIVE' | 'PAUSED' | 'EXPIRED' | 'ARCHIVED';
export const CAMPAIGN_LINK_STATUSES: CampaignLinkStatus[] = ['DRAFT', 'ACTIVE', 'PAUSED', 'EXPIRED', 'ARCHIVED'];
export const CAMPAIGN_CHANNELS = ['social', 'community', 'email', 'website', 'event', 'other'];

export interface CampaignLink {
  Id: string; ProgramId: string; ProgramName: string | null; Name: string; Code: string; Channel: string; Locale: string;
  Destination: string; Status: CampaignLinkStatus | string; ActiveFrom: string | null; ExpiresAt: string | null; CreatedAt: string | null;
  ShareUrl: string | null; SignupCount: number; QualifiedCount: number; OfferVersionId: string | null; SuggestedCaption: string | null;
  /** Present on the admin list; the member endpoints omit them. */
  OwnerUserId?: number | null; OwnerName?: string | null; OwnerEmail?: string | null;
  /** Addendum A: sign-up page visits since creation and the visitors among them (once per day). Absent on a platform that predates clicks. */
  ClickCount?: number | null; UniqueClickCount?: number | null;
}
export interface CampaignLinkFilters { status?: string; query?: string; now?: number }

// ---- per-link performance (addendum A): admin route GET links/{id}/performance?range, company-scoped, any owner ----
export type PerformanceRange = '7d' | '30d' | '90d' | 'month' | 'all';
export const PERFORMANCE_RANGES: { id: PerformanceRange; label: string }[] = [
  { id: '7d', label: 'Last 7 days' }, { id: '30d', label: 'Last 30 days' }, { id: '90d', label: 'Last 90 days' }, { id: 'month', label: 'This month' }, { id: 'all', label: 'All time' },
];
export interface CampaignLinkPerformance {
  Clicks: number; UniqueClicks: number; ClickToSignupRate: number | null;
  Signups: number; Verified: number; Qualified: number; Earning: number; RewardsAccrued: number; RewardsPaid: number; Currency: string;
}
/** Tolerant of an older platform: missing counters read as zero, the rate as null. */
export function performanceFromResponse(raw: Partial<CampaignLinkPerformance> | null | undefined): CampaignLinkPerformance {
  const n = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) ? value : 0);
  const rate = raw?.ClickToSignupRate;
  return {
    Clicks: n(raw?.Clicks), UniqueClicks: n(raw?.UniqueClicks), ClickToSignupRate: typeof rate === 'number' && Number.isFinite(rate) ? rate : null,
    Signups: n(raw?.Signups), Verified: n(raw?.Verified), Qualified: n(raw?.Qualified), Earning: n(raw?.Earning),
    RewardsAccrued: n(raw?.RewardsAccrued), RewardsPaid: n(raw?.RewardsPaid), Currency: raw?.Currency || 'USD',
  };
}
/** The platform's rate is sign-ups per unique click (4 dp), null before any unique click; the same for a link's lifetime counters. */
export function clickToSignupRate(signups: number, uniqueClicks: number | null | undefined): number | null {
  return uniqueClicks && uniqueClicks > 0 ? Math.round((10000 * signups) / uniqueClicks) / 10000 : null;
}
/** A rate as a percentage with one decimal ("12.5%"), or "—" for none. */
export function ratePercent(rate: number | null | undefined): string {
  if (rate === null || rate === undefined || !Number.isFinite(rate)) return '—';
  const text = (rate * 100).toFixed(1);
  return `${text.endsWith('.0') ? text.slice(0, -2) : text}%`;
}
/** Whether the platform counts clicks for this link (the fields are present at all). */
export function clicksTracked(link: Pick<CampaignLink, 'ClickCount' | 'UniqueClickCount'>): boolean {
  return typeof link.ClickCount === 'number' || typeof link.UniqueClickCount === 'number';
}

/** What the status reads as right now: a link whose expiry has passed is expired whatever the row says. */
export function effectiveLinkStatus(link: Pick<CampaignLink, 'Status' | 'ExpiresAt'>, now = Date.now()): string {
  const status = (link.Status || '').toUpperCase();
  if (status === 'ARCHIVED') return status;
  const expires = link.ExpiresAt ? Date.parse(link.ExpiresAt) : NaN;
  return Number.isFinite(expires) && expires <= now ? 'EXPIRED' : status;
}
/** The status changes the admin may make from where the link stands; the platform enforces the same. */
export function linkActions(link: Pick<CampaignLink, 'Status' | 'ExpiresAt'>, now = Date.now()): { pause: boolean; resume: boolean; archive: boolean } {
  const status = effectiveLinkStatus(link, now);
  return { pause: status === 'ACTIVE', resume: status === 'PAUSED', archive: status !== 'ARCHIVED' };
}
export function linkStatusTone(status: string | null | undefined): string {
  switch ((status || '').toUpperCase()) {
    case 'ACTIVE': return 'success';
    case 'PAUSED': case 'DRAFT': return 'warning';
    case 'ARCHIVED': return 'danger';
    default: return 'neutral';
  }
}
export function channelLabel(channel: string | null | undefined): string {
  const value = (channel || '').toLowerCase();
  return value ? `${value.charAt(0).toUpperCase()}${value.slice(1)}` : '—';
}
export function ownerLabel(link: Pick<CampaignLink, 'OwnerName' | 'OwnerEmail' | 'OwnerUserId'>): string {
  return link.OwnerName || link.OwnerEmail || (link.OwnerUserId ? `User #${link.OwnerUserId}` : '—');
}
/** Client-side narrowing of the loaded list: status by effective status, query over campaign, code, owner and programme. */
export function filterCampaignLinks(links: CampaignLink[], filters: CampaignLinkFilters = {}): CampaignLink[] {
  const now = filters.now ?? Date.now();
  const status = (filters.status || '').toUpperCase();
  const q = (filters.query || '').trim().toLowerCase();
  return links.filter(link => {
    if (status && effectiveLinkStatus(link, now) !== status) return false;
    if (!q) return true;
    return [link.Name, link.Code, link.OwnerName ?? '', link.OwnerEmail ?? '', link.OwnerUserId ? `#${link.OwnerUserId}` : '', link.ProgramName ?? '']
      .some(value => value.toLowerCase().includes(q));
  });
}
/** Newest first; rows without a creation date sort last. */
export function sortCampaignLinks(links: CampaignLink[]): CampaignLink[] {
  const stamp = (link: CampaignLink) => { const t = link.CreatedAt ? Date.parse(link.CreatedAt) : NaN; return Number.isFinite(t) ? t : -Infinity; };
  return [...links].sort((a, b) => stamp(b) - stamp(a));
}
/** Share of sign-ups that qualified, as a percentage, or null before any sign-up. */
export function qualificationShare(link: Pick<CampaignLink, 'SignupCount' | 'QualifiedCount'>): number | null {
  return link.SignupCount > 0 ? Math.round((10000 * link.QualifiedCount) / link.SignupCount) / 100 : null;
}
