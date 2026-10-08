<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router';
import ReferralRelationships from '@/components/referrals/ReferralRelationships.vue';
import ReferralCommunity from '@/components/referrals/ReferralCommunity.vue';
import ReferralCapControl from '@/components/referrals/ReferralCapControl.vue';
import ReferralRisk from '@/components/referrals/ReferralRisk.vue';
import ReferralLifecycle from '@/components/referrals/ReferralLifecycle.vue';
import ReferralTools from '@/components/referrals/ReferralTools.vue';
import ReferralOfferWorkbench from '@/components/ReferralOfferWorkbench.vue';
import UserPicker from '@/components/UserPicker.vue';
import ReferralMarginEditor from '@/components/ReferralMarginEditor.vue';
import ReferralEarningsCalculator from '@/components/ReferralEarningsCalculator.vue';
import ReferralRewardDrawer from '@/components/ReferralRewardDrawer.vue';
import ReferralLinkDrawer from '@/components/ReferralLinkDrawer.vue';
import AnalyticsChart from '@/components/AnalyticsChart.vue';
import AppShell from '@/components/AppShell.vue';
import StatusPill from '@/components/StatusPill.vue';
import { describeAdminError } from '@/lib/adminApi';
import type { ChartSeries } from '@/lib/chartConfig';
import { referralsApi } from '@/lib/referralsApi';
import { allocationErrors, isBuildUnavailable, isConflict, referralBuildApi, type Capabilities } from '@/lib/referralBuild';
import { BUILDER_STEPS, changeRows, offerSentence, offerSummary, programDiffFields, stepForError, type BuilderStep, type ChangeRow } from '@/lib/referralReview';
import { DEMO_ANALYTICS, DEMO_CREDITS, DEMO_RECONCILIATION } from '@/lib/referralsDemo';
import { CAMPAIGN_LINK_STATUSES, channelLabel, clicksTracked, effectiveLinkStatus, filterCampaignLinks, linkActions, linkStatusTone, ownerLabel, sortCampaignLinks, type CampaignLink } from '@/lib/referralLinks';
import { CREDIT_STATUSES, LEVEL_ICONS, REWARD_EVENT_TYPES, REWARD_STATUSES, discountDescription, friendStageLabel, isVoucherDeliveryMode,
  levelCapLabel, levelConditionLabel, money, newLevel, nextLevelConditions, offerHeadline, privateProgram, programErrors, programOptionLabel, rewardEventLabel, rewardMaximum, rewardRateLabel, statusLabel, statusTone, trimNumber,
  type AdminReward, type LevelAssignment, type OfferDraft, type PartnerReport, type Reconciliation, type ReferralCredit, type ReferralMember,
  type ReferralAnalytics, type ReferralMetrics, type ReferralOffer, type ReferralOptions, type ReferralOverview, type ReferralProgram, type UserOption } from '@/lib/referrals';

type Tab = 'performance' | 'program' | 'ledger' | 'credits' | 'metrics' | 'partners' | 'links' | 'relationships' | 'review' | 'members' | 'tools' | 'community';
type Period = '30' | '90' | '180' | '365' | 'custom';
const PAGE_SIZE = 100;
const programs = ref<ReferralProgram[]>([]);
const overview = ref<ReferralOverview | null>(null);
const program = ref<ReferralProgram | null>(null);
const options = ref<ReferralOptions | null>(null);
const offers = ref<ReferralOffer[]>([]);
const members = ref<ReferralMember[]>([]);
const assignments = ref<LevelAssignment[]>([]);
const ledger = ref<AdminReward[]>([]);
const credits = ref<ReferralCredit[]>([]);
const metrics = ref<ReferralMetrics | null>(null);
const reconciliation = ref<Reconciliation | null>(null);
const analytics = ref<ReferralAnalytics | null>(null);
// ---- campaign links (contract 2026-09-15): 404 = the platform predates them, and the tab stays out ----
const links = ref<CampaignLink[]>([]);
const linksUnavailable = ref(false);
const linksLoading = ref(false);
const linkFilters = ref({ status: '', query: '' });
/** Link opened in the drawer. */
const linkRow = ref<CampaignLink | null>(null);
const analyticsLoading = ref(false);
/** The platform answered 404: it predates GET analytics. The other tabs keep working. */
const analyticsUnavailable = ref(false);
const analyticsFilters = ref({ programId: '', period: '90' as Period, from: '', to: '', top: 10 });
/** Sample data: offered only when the period has no relationships or the endpoint is missing; rendered from the built-in dataset and never sent anywhere. */
const showSample = ref(false);
const sampleAvailable = computed(() => analyticsUnavailable.value || (!!analytics.value && analytics.value.Funnel.Invited === 0));
const sampleMode = computed(() => showSample.value && sampleAvailable.value);
/** What the Performance tab renders: the live payload, or the demo dataset while the sample switch is on. */
const perf = computed<ReferralAnalytics | null>(() => sampleMode.value ? DEMO_ANALYTICS : analytics.value);
const perfReconciliation = computed(() => sampleMode.value ? DEMO_RECONCILIATION : reconciliation.value);
const sectionErrors = ref<Record<string, string>>({});
const original = ref('');
const creating = ref(false);
const loading = ref(true);
const saving = ref(false);
const error = ref('');
const message = ref('');
const route = useRoute(); const router = useRouter();
const allowedTabs: Tab[] = ['performance', 'program', 'partners', 'links', 'ledger', 'credits', 'metrics', 'relationships', 'review', 'members', 'tools', 'community'];
const tab = ref<Tab>(allowedTabs.includes(route.query.tab as Tab) ? route.query.tab as Tab : 'performance');
const stepIds = BUILDER_STEPS.map(s => s.id);
const step = ref<BuilderStep>(stepIds.includes(route.query.step as BuilderStep) ? route.query.step as BuilderStep : 'audience');
watch(tab, value => { void router.replace({ query: { ...route.query, tab: value } }); });
watch(step, value => { void router.replace({ query: { ...route.query, step: value } }); });
watch(() => route.query.tab, value => { if (allowedTabs.includes(value as Tab)) tab.value = value as Tab; });
const publishNewTermsVersion = ref(false);
const offer = ref<OfferDraft>({ OwnerUserId: null, ReferredTierId: null, DiscountCodeId: null, InheritBenefits: false });
const emptyPartner = () => ({ userId: null as number | null, expiresAt: '', agreementReference: '', effectiveFrom: '', effectiveUntil: '', campaignOwnerUserId: null as number | null, channels: '', fundingAllocation: '', notes: '', approve: false });
const partner = ref(emptyPartner());
const addingPartner = ref(false);
const assignment = ref({ userId: null as number | null, levelId: '', expiresAt: '', notes: '' });
const ledgerFilters = ref({ status: '', beneficiaryRole: '', eventType: '' });
const ledgerPage = ref(1);
const creditStatus = ref('');
const creditPage = ref(1);
const cancelTarget = ref<ReferralCredit | null>(null);
const cancelReason = ref('');
/** Ledger row opened in the reward explanation drawer. */
const rewardRow = ref<AdminReward | null>(null);
const rewardCredit = computed(() => rewardRow.value?.Reward.CreditId ? credits.value.find(c => c.Id === rewardRow.value!.Reward.CreditId) ?? null : null);
// ---- versioned publishing capabilities (one request per page; 404/503 = the platform has no versioned publishing) ----
const build = ref<{ state: 'loading' | 'ready' | 'unavailable' | 'error'; capabilities: Capabilities | null; error: string }>({ state: 'loading', capabilities: null, error: '' });
const buildAvailable = computed(() => build.value.state === 'ready');
/** Subpartner → parent partner links of the selected private program (GET team), only when the platform supports it. */
const parentByChild = ref<Record<string, number>>({});
const parentChoice = ref<number | null>(null);
// ---- partners ----
const partnerQuery = ref('');
const detailMember = ref<ReferralMember | null>(null);
/** Per-partner activity (GET members/{id}/report), loaded lazily for the listed partners. null = loading, string = error. */
const reports = ref<Record<number, PartnerReport | null | { error: string }>>({});
/** Server copy shown when a save is refused with 409: the admin keeps their input and compares before reloading. */
const conflict = ref<{ server: ReferralProgram; rows: ChangeRow[]; message: string } | null>(null);
const busy = computed(() => loading.value || saving.value);
const dirty = computed(() => !!program.value && (JSON.stringify(program.value) !== original.value || publishNewTermsVersion.value));
const marginErrors = computed(() => { const m = program.value?.MarginPolicy; return m ? [...allocationErrors(m.Direct, false), ...(m.Team ? allocationErrors(m.Team, true) : [])] : []; });
const errors = computed(() => program.value ? [...programErrors(program.value, overview.value?.TopupRewardLimits, buildAvailable.value), ...marginErrors.value] : []);
const issuesByStep = computed(() => { const counts: Partial<Record<BuilderStep, number>> = {}; for (const e of errors.value) { const s = /basis points|shares|budget|subpartner/i.test(e) ? 'rewards' : stepForError(e); counts[s] = (counts[s] ?? 0) + 1; } return counts; });
const firstIssueStep = computed<BuilderStep>(() => stepIds.find(id => issuesByStep.value[id]) ?? 'review');
const stepIndex = computed(() => stepIds.indexOf(step.value));
const selectedDiscount = computed(() => options.value?.DiscountCodes.find(code => code.Id === offer.value.DiscountCodeId));
const users = computed(() => options.value?.Users ?? []);
const activeMembers = computed(() => members.value.filter(m => m.Status === 'ACTIVE' && (!m.ExpiresAt || Date.parse(m.ExpiresAt) > Date.now())));
const eligibleUsers = computed(() => program.value?.Visibility === 'PRIVATE' ? activeMembers.value.map(m => ({ Id: m.UserId, Name: m.Name, Email: m.Email })) : users.value);
/** Users picked through the search join `users`, so the existing eligibility checks keep working. */
function rememberUser(user: UserOption | null) {
  if (!user || !options.value || options.value.Users.some(u => u.Id === user.Id)) return;
  options.value = { ...options.value, Users: [...options.value.Users, user] };
}
const partnerLabel = computed(() => {
  const id = partner.value.userId;
  if (id === null) return '';
  const member = members.value.find(m => m.UserId === id);
  return member ? `${member.Name} · ${member.Email}` : '';
});
const baseLevel = computed(() => program.value?.Levels.filter(level => !level.Hidden)[0]);
const headline = computed(() => program.value ? offerHeadline(program.value, baseLevel.value) : '');
const sentence = computed(() => program.value ? offerSentence(program.value, baseLevel.value) : '');
const summary = computed(() => program.value ? offerSummary(program.value, baseLevel.value) : null);
const summaryRows = computed(() => summary.value ? [
  { label: 'Your customer receives', value: summary.value.customer }, { label: 'Inviter receives', value: summary.value.inviter }, { label: 'Currency', value: summary.value.currency },
  { label: 'Earning window', value: summary.value.window }, { label: 'Cap', value: summary.value.cap }, { label: 'Delivery', value: summary.value.delivery },
] : []);
const voucherMode = computed(() => isVoucherDeliveryMode(program.value?.DeliveryMode));
const archived = computed(() => program.value?.Status === 'ARCHIVED');
const versioned = computed(() => !!program.value && !creating.value && (!!program.value.OfferVersionId || !!program.value.MarginPolicy));
const currency = computed(() => overview.value?.Currency || program.value?.PayoutCurrency || 'USD');
const stats = computed(() => overview.value ? [
  { label: 'Relationships', value: overview.value.TotalRelationships }, { label: 'Qualified referrals', value: overview.value.QualifiedReferrals },
  { label: 'Qualifying top-up volume', value: money(overview.value.QualifyingTopupVolume, currency.value) }, { label: 'Pending liability', value: money(overview.value.PendingLiability, currency.value) },
  { label: 'Paid rewards', value: money(overview.value.PaidRewards, currency.value) }, { label: 'Welcome paid', value: money(overview.value.WelcomePaid, currency.value) },
  { label: 'Known exposure reserved', value: `${money(overview.value.ReservedExposure, currency.value)}${overview.value.ExposureLimit != null ? ` of ${money(overview.value.ExposureLimit, currency.value)}` : ''}` },
  { label: 'Uncapped recurring commitments', value: overview.value.UnboundedCommitmentCount ?? 'Unavailable' },
  { label: 'Credits paid / failed', value: `${overview.value.CreditsPaid} / ${overview.value.FailedCredits}` }, { label: 'Excluded events', value: overview.value.ExcludedEvents },
] : []);
const allTabs: { id: Tab; label: string }[] = [{ id: 'relationships', label: 'Relationships' }, { id: 'review', label: 'Review' }, { id: 'members', label: 'Member levels' }, { id: 'tools', label: 'Tools' }, { id: 'performance', label: 'Overview' }, { id: 'program', label: 'Programs' }, { id: 'partners', label: 'Partners' }, { id: 'links', label: 'Links' }, { id: 'ledger', label: 'Earnings' }, { id: 'credits', label: 'Credits' }, { id: 'metrics', label: 'Metrics' }];
/** The Links tab only exists once the platform serves campaign links. */
const tabs = computed(() => [...allTabs.filter(item => item.id !== 'links' || !linksUnavailable.value), ...(program.value?.Visibility === 'PUBLIC' ? [{ id: 'community' as Tab, label: 'Community Partners' }] : [])]);
const filteredLinks = computed(() => sortCampaignLinks(filterCampaignLinks(links.value, linkFilters.value)));
const linkCounts = computed(() => ({
  active: links.value.filter(l => effectiveLinkStatus(l) === 'ACTIVE').length,
  clicks: links.value.reduce((n, l) => n + (l.ClickCount ?? 0), 0),
  signups: links.value.reduce((n, l) => n + l.SignupCount, 0),
  qualified: links.value.reduce((n, l) => n + l.QualifiedCount, 0),
  /** Addendum A: clicks exist once any loaded link carries the counters. */
  tracked: links.value.some(clicksTracked),
}));
const periods: { id: Period; label: string }[] = [{ id: '30', label: 'Last 30 days' }, { id: '90', label: 'Last 90 days' }, { id: '180', label: 'Last 180 days' }, { id: '365', label: 'Last 365 days' }, { id: 'custom', label: 'Custom period' }];
const topChoices = [10, 25, 50];
/** creditsPaid / (creditsPaid + creditsFailed) from the overview counters of the program selected above (all time); demo counters in sample mode. */
const creditCounters = computed(() => sampleMode.value ? DEMO_CREDITS : overview.value ? { paid: overview.value.CreditsPaid, failed: overview.value.FailedCredits } : null);
const creditSuccessRate = computed(() => {
  const c = creditCounters.value; const total = c ? c.paid + c.failed : 0;
  return c && total > 0 ? (100 * c.paid) / total : null;
});
const kpis = computed(() => {
  const a = perf.value; const c = creditCounters.value;
  if (!a) return [];
  return [
    { label: 'Qualified friends', value: String(a.Funnel.Qualified), note: `of ${a.Funnel.Invited} invited in the period` },
    { label: 'Qualification rate', value: pct(a.Funnel.QualificationRate), note: 'qualified ÷ invited' },
    { label: 'Accrued contribution', value: money(a.Contribution, a.Currency), note: 'fees collected − provider cost − rewards accrued', negative: a.Contribution < 0 },
    { label: 'Rewards outstanding', value: money(a.Cost.Outstanding, a.Currency), note: 'accrued and not yet paid' },
    { label: 'Credit success rate', value: creditSuccessRate.value === null ? '—' : pct(creditSuccessRate.value), note: c ? `${c.paid} paid, ${c.failed} failed · ${sampleMode.value ? 'sample figures' : 'program selected above, all time'}` : 'no credits yet' },
    { label: 'Average reward per qualified friend', value: money(a.AverageRewardPerQualifiedFriend, a.Currency), note: `average top-up ${money(a.AverageTopupPerQualifiedFriend, a.Currency)}` },
  ];
});
/** Stage rates are % of Invited; the platform supplies the first four, the last two are derived the same way. */
const funnelStages = computed(() => {
  const f = perf.value?.Funnel;
  if (!f) return [];
  const share = (n: number) => f.Invited > 0 ? Math.round((10000 * n) / f.Invited) / 100 : 0;
  return [
    { label: 'Invited', count: f.Invited, rate: f.Invited > 0 ? 100 : 0 }, { label: 'KYC completed', count: f.KycCompleted, rate: f.KycRate },
    { label: 'Card issued', count: f.CardIssued, rate: f.CardRate }, { label: 'Qualified', count: f.Qualified, rate: f.QualificationRate },
    { label: 'Earning now', count: f.Earning, rate: share(f.Earning) }, { label: 'Window ended', count: f.WindowEnded, rate: share(f.WindowEnded) },
  ];
});
const costByType = computed(() => {
  const c = perf.value?.Cost;
  return c ? [{ label: 'Welcome (friend)', amount: c.Welcome }, { label: 'Qualification', amount: c.Qualification }, { label: 'Top-up commission', amount: c.Topup }, { label: 'Adjustments', amount: c.Adjustments }] : [];
});

// ---- chart inputs (AnalyticsChart reads these; the config itself is built in lib/chartConfig.ts) ----
const showWeeklyTable = ref(false);
const analyticsCurrency = computed(() => perf.value?.Currency || currency.value);
/** Compact money for axis ticks; tooltips use the full two-decimal `money`. */
function axisMoney(value: number, currency = analyticsCurrency.value) {
  return `${value.toLocaleString(undefined, { maximumFractionDigits: Math.abs(value) >= 100 ? 0 : 2 })} ${currency}`;
}
const tooltipMoney = (value: number) => money(value, analyticsCurrency.value);
const weekLabels = computed(() => (perf.value?.Weekly ?? []).map(w => day(w.WeekStart)));
const weeklyActivitySeries = computed<ChartSeries[]>(() => {
  const weeks = perf.value?.Weekly ?? [];
  return [
    { label: 'Attributed', data: weeks.map(w => w.Attributed), color: 'neutral', type: 'line' },
    { label: 'Qualified', data: weeks.map(w => w.Qualified), color: 'accent', type: 'line' },
    { label: 'Top-up volume', data: weeks.map(w => w.TopupVolume), color: 'accentFaint', type: 'bar', axis: 'y1', format: tooltipMoney },
  ];
});
const weeklyRewardSeries = computed<ChartSeries[]>(() => {
  const weeks = perf.value?.Weekly ?? [];
  return [
    { label: 'Rewards accrued', data: weeks.map(w => w.RewardsAccrued), color: 'neutralSoft', type: 'bar', format: tooltipMoney },
    { label: 'Rewards paid', data: weeks.map(w => w.RewardsPaid), color: 'accent', type: 'bar', format: tooltipMoney },
    { label: 'Credits paid', data: weeks.map(w => w.CreditsPaid), color: 'neutral', type: 'line', axis: 'y1', dashed: true },
  ];
});
const funnelLabels = computed(() => funnelStages.value.map(stage => stage.label));
/** Accent on the qualified stage, softer accent on the way there, neutral for what happens after. */
const funnelSeries = computed<ChartSeries[]>(() => [{ label: 'Relationships', data: funnelStages.value.map(stage => stage.count),
  color: funnelStages.value.map((_, index) => index === 3 ? 'accent' : index > 3 ? 'neutralSoft' : 'accentSoft') }]);
const funnelShare = (_: number, index: number) => `${pct(funnelStages.value[index]?.rate)} of invited`;
const funnelBarLabel = (value: number, index: number) => `${value} · ${pct(funnelStages.value[index]?.rate)}`;
const costLabels = computed(() => costByType.value.map(row => row.label));
const costSeries = computed<ChartSeries[]>(() => [{ label: 'Reward cost', data: costByType.value.map(row => Math.abs(row.amount)),
  color: ['accent', 'accentSoft', 'neutral', 'neutralSoft'], format: (_, index) => money(costByType.value[index]?.amount, analyticsCurrency.value) }]);
const costStatusSeries = computed<ChartSeries[]>(() => {
  const c = perf.value?.Cost;
  return c ? [{ label: 'Paid', data: [c.Paid], color: 'accent', stack: 'cost', format: tooltipMoney }, { label: 'Outstanding', data: [c.Outstanding], color: 'neutralSoft', stack: 'cost', format: tooltipMoney }] : [];
});
const leaderboardLabels = computed(() => (perf.value?.Leaderboard ?? []).map(row => row.Name || row.Email || `#${row.UserId}`));
/** Partners (private program members) in the accent colour, organic referrers in the soft accent. */
const leaderboardSeries = computed<ChartSeries[]>(() => {
  const rows = perf.value?.Leaderboard ?? [];
  return [{ label: 'Rewards accrued', data: rows.map(row => row.RewardsAccrued), color: rows.length > 1 ? rows.map(row => row.Partner ? 'accent' : 'accentSoft') : 'accent', format: tooltipMoney }];
});
const leaderboardExtra = (_: number, index: number) => {
  const row = perf.value?.Leaderboard[index];
  return row ? [`Qualified ${row.Qualified} of ${row.Attributed} attributed`, `Paid ${money(row.RewardsPaid, analyticsCurrency.value)}`, row.Partner ? 'Partner · private program member' : ''] : undefined;
};
const exclusionLabels = computed(() => (perf.value?.Exclusions ?? []).map(row => statusLabel(row.Reason)));
const exclusionSeries = computed<ChartSeries[]>(() => [{ label: 'Events', data: (perf.value?.Exclusions ?? []).map(row => row.Count), color: 'neutral' }]);
const exclusionExtra = (_: number, index: number) => { const row = perf.value?.Exclusions[index]; return row ? `Excluded basis ${money(row.Amount, analyticsCurrency.value)}` : undefined; };
const programLabels = computed(() => (perf.value?.Programs ?? []).map(p => p.Name));
const programSeries = computed<ChartSeries[]>(() => {
  const rows = perf.value?.Programs ?? [];
  return [{ label: 'Outstanding', data: rows.map(p => p.RewardsOutstanding), color: 'neutralSoft', format: tooltipMoney }, { label: 'Paid', data: rows.map(p => p.RewardsPaid), color: 'accent', format: tooltipMoney }];
});
/** Horizontal bar charts grow with their rows so labels never overlap. */
const rowsHeight = (rows: number) => Math.max(140, rows * 34 + 56);
const metricLabels = computed(() => (metrics.value?.Weeks ?? []).map(w => day(w.WeekStart)));
const metricSeries = computed<ChartSeries[]>(() => {
  const weeks = metrics.value?.Weeks ?? [];
  return [
    { label: 'Attributed', data: weeks.map(w => w.Attributed), color: 'neutral' },
    { label: 'Qualified', data: weeks.map(w => w.Qualified), color: 'accent' },
    { label: 'First purchase ≤30d', data: weeks.map(w => w.FirstPurchaseWithin30Days), color: 'accent', dashed: true },
    { label: 'Repeat use ≤30d', data: weeks.map(w => w.RepeatUseWithin30Days), color: 'neutral', dashed: true },
  ];
});
const economics = computed(() => {
  const a = perf.value;
  return a ? [
    { label: 'Fees collected', value: money(a.FeesCollected, a.Currency), note: 'on commissionable top-ups of referred users' },
    { label: 'Provider cost', value: money(a.ProviderCost, a.Currency), note: 'Interlace cost on those top-ups' },
    { label: 'Rewards accrued', value: money(a.Cost.Accrued, a.Currency), note: `paid ${money(a.Cost.Paid, a.Currency)}` },
    { label: 'Accrued contribution', value: money(a.Contribution, a.Currency), note: 'fees − provider cost − rewards accrued', negative: a.Contribution < 0 },
  ] : [];
});

// ---- partners: filter, activity, level override, subpartner links ----
const filteredMembers = computed(() => {
  const q = partnerQuery.value.trim().toLowerCase();
  return q ? members.value.filter(m => [m.Name, m.Email, m.AgreementReference ?? '', `#${m.UserId}`, m.Status].some(v => v.toLowerCase().includes(q))) : members.value;
});
function activeAssignment(userId: number) { return assignments.value.find(a => a.UserId === userId && !a.RevokedAt && (!a.ExpiresAt || Date.parse(a.ExpiresAt) > Date.now())) ?? null; }
function partnerLevel(m: ReferralMember) { const a = activeAssignment(m.UserId); return a ? { label: a.LevelName, note: 'override' } : { label: 'Metric-based ladder', note: baseLevel.value ? `starts at ${baseLevel.value.Name}` : '' }; }
function partnerActivity(userId: number) { const r = reports.value[userId]; return r && !('error' in r) ? r : null; }
function activityState(userId: number) { const r = reports.value[userId]; return r === undefined ? 'idle' : r === null ? 'loading' : 'error' in r ? 'error' : 'ready'; }
const childrenOf = (userId: number) => Object.entries(parentByChild.value).filter(([, parent]) => parent === userId).map(([child]) => Number(child));
const memberName = (userId: number | null | undefined) => { const m = members.value.find(x => x.UserId === userId); return m ? m.Name : userId ? `User #${userId}` : '—'; };
/** Load partner reports four at a time so a long register does not fire one request per row at once. */
async function loadPartnerActivity(list: ReferralMember[]) {
  const id = program.value?.Id; if (!id) return;
  const queue = list.filter(m => reports.value[m.UserId] === undefined || (reports.value[m.UserId] && 'error' in reports.value[m.UserId]!));
  for (const m of queue) reports.value[m.UserId] = null;
  const worker = async () => { for (let m = queue.shift(); m; m = queue.shift()) { try { reports.value[m.UserId] = await referralsApi.memberReport(id, m.UserId); } catch (e) { reports.value[m.UserId] = { error: readableError(e) }; } } };
  await Promise.all(Array.from({ length: Math.min(4, queue.length) }, worker));
}
async function loadTeam() {
  const id = program.value?.Id;
  if (!id || program.value?.Visibility !== 'PRIVATE' || !buildAvailable.value) { parentByChild.value = {}; return; }
  parentByChild.value = await section('team', {}, () => referralBuildApi.team(id));
}
async function loadBuild() {
  build.value = { state: 'loading', capabilities: null, error: '' };
  try { build.value = { state: 'ready', capabilities: await referralBuildApi.capabilities(), error: '' }; }
  catch (e) { build.value = isBuildUnavailable(e) ? { state: 'unavailable', capabilities: null, error: '' } : { state: 'error', capabilities: null, error: describeAdminError(e) }; }
}

function readableError(e: unknown) {
  const status = (e as { response?: { status?: number } })?.response?.status;
  const detail = describeAdminError(e);
  return status === 404 ? `Referral settings are unavailable from the configured Hoppa API. The company must have referrals enabled and the public referral management endpoints deployed. ${detail}` : detail;
}
function discard() { return !dirty.value || window.confirm('Discard unsaved program changes?'); }
onBeforeRouteLeave(() => discard());
function resetForms() {
  offer.value = { OwnerUserId: null, ReferredTierId: null, DiscountCodeId: null, InheritBenefits: false };
  partner.value = emptyPartner(); addingPartner.value = false; assignment.value = { userId: null, levelId: '', expiresAt: '', notes: '' };
  detailMember.value = null; reports.value = {}; parentChoice.value = null; cancelTarget.value = null; cancelReason.value = ''; publishNewTermsVersion.value = false; conflict.value = null; rewardRow.value = null; linkRow.value = null;
}
/** Secondary resources fail independently: an older platform without the v2 ledger must not hide the program editor. */
async function section<T>(key: string, fallback: T, fn: () => Promise<T>): Promise<T> {
  try { const value = await fn(); delete sectionErrors.value[key]; return value; }
  catch (e) { sectionErrors.value[key] = readableError(e); return fallback; }
}
async function loadProgramSections(id: string | null, visibility: string) {
  const [membership, assigned] = await Promise.all([
    id && visibility === 'PRIVATE' ? section('members', [] as ReferralMember[], () => referralsApi.members(id)) : Promise.resolve([] as ReferralMember[]),
    id ? section('assignments', [] as LevelAssignment[], () => referralsApi.levelAssignments(id)) : Promise.resolve([] as LevelAssignment[]),
  ]);
  members.value = membership; assignments.value = assigned;
  await loadTeam();
  void loadPartnerActivity(membership.slice(0, PAGE_SIZE));
}
async function loadLedger() {
  ledger.value = await section('ledger', [], () => referralsApi.rewards({ programId: program.value?.Id, ...ledgerFilters.value, page: ledgerPage.value, pageSize: PAGE_SIZE }));
}
async function loadCredits() {
  const [rows, summary] = await Promise.all([
    section('credits', [] as ReferralCredit[], () => referralsApi.credits(creditStatus.value, creditPage.value, PAGE_SIZE)),
    section('reconciliation', null as Reconciliation | null, () => referralsApi.reconciliation()),
  ]);
  credits.value = rows; reconciliation.value = summary;
}
function pageLedger(by: number) { ledgerPage.value = Math.max(1, ledgerPage.value + by); void loadLedger(); }
function pageCredits(by: number) { creditPage.value = Math.max(1, creditPage.value + by); void loadCredits(); }
async function loadMetrics() {
  metrics.value = await section('metrics', null, () => referralsApi.metrics(program.value?.Id));
}
/** Every member's links for the selected program. A 404 hides the tab (feature not deployed); other failures keep it with a message. */
async function loadLinks() {
  if (creating.value) { links.value = []; return; }
  linksLoading.value = true;
  try {
    links.value = await referralsApi.links({ programId: program.value?.Id });
    linksUnavailable.value = false; delete sectionErrors.value.links;
  } catch (e) {
    links.value = [];
    if ((e as { response?: { status?: number } })?.response?.status === 404) { linksUnavailable.value = true; delete sectionErrors.value.links; if (tab.value === 'links') tab.value = 'performance'; }
    else sectionErrors.value.links = describeAdminError(e);
  } finally { linksLoading.value = false; }
}
const linkConfirmations: Record<string, (link: CampaignLink) => string> = {
  PAUSED: link => `Pause "${link.Name}"? New sign-ups through ${link.Code} stop attributing; existing relationships keep their earning window.`,
  ACTIVE: link => `Resume "${link.Name}"? Sign-ups through ${link.Code} attribute to ${ownerLabel(link)} again.`,
  ARCHIVED: link => `Archive "${link.Name}"? The link stops attributing for good and cannot be reactivated.`,
};
async function setLinkStatus(link: CampaignLink, status: 'PAUSED' | 'ACTIVE' | 'ARCHIVED') {
  if (!window.confirm(linkConfirmations[status]!(link))) return;
  await run(async () => {
    const updated = await referralsApi.setLinkStatus(link.Id, status);
    links.value = links.value.map(row => row.Id === link.Id ? { ...row, ...updated } : row);
    if (linkRow.value?.Id === link.Id) linkRow.value = links.value.find(row => row.Id === link.Id) ?? null;
  }, status === 'PAUSED' ? 'Link paused. New sign-ups no longer attribute through it.' : status === 'ACTIVE' ? 'Link resumed.' : 'Link archived.');
}
function dayInput(value: Date) { return value.toISOString().slice(0, 10); }
/** Presets end now; a custom period covers whole UTC days. Blank custom bounds fall back to the platform default (last 90 days). */
function analyticsRange(): { from?: string; to?: string } {
  const f = analyticsFilters.value;
  if (f.period === 'custom') return { from: f.from ? `${f.from}T00:00:00Z` : undefined, to: f.to ? `${f.to}T23:59:59Z` : undefined };
  const to = new Date();
  return { from: new Date(to.getTime() - Number(f.period) * 86400000).toISOString(), to: to.toISOString() };
}
function selectPeriod() {
  const f = analyticsFilters.value;
  if (f.period === 'custom') {
    if (!f.from && !f.to) { f.to = dayInput(new Date()); f.from = dayInput(new Date(Date.now() - 90 * 86400000)); }
    return;
  }
  void loadAnalytics();
}
async function loadAnalytics() {
  const f = analyticsFilters.value;
  if (f.period === 'custom' && f.from && f.to && f.from > f.to) { sectionErrors.value.analytics = 'The custom period must start before it ends.'; return; }
  analyticsLoading.value = true; analyticsUnavailable.value = false;
  try {
    const range = analyticsRange();
    analytics.value = await referralsApi.analytics(f.programId || null, range.from, range.to, f.top);
    delete sectionErrors.value.analytics;
  } catch (e) {
    analytics.value = null;
    if ((e as { response?: { status?: number } })?.response?.status === 404) { analyticsUnavailable.value = true; delete sectionErrors.value.analytics; }
    else sectionErrors.value.analytics = describeAdminError(e);
  } finally { analyticsLoading.value = false; }
}
function pct(value: number | null | undefined) { return typeof value === 'number' && Number.isFinite(value) ? `${value.toFixed(1)}%` : '—'; }
function hours(value: number | null | undefined) { return typeof value === 'number' && Number.isFinite(value) ? (value >= 48 ? `${(value / 24).toFixed(1)} days` : `${value.toFixed(1)} h`) : '—'; }
async function load(id?: string | null) {
  loading.value = true; error.value = ''; program.value = null; overview.value = null;
  try {
    const [list, data, choices, benefits] = await Promise.all([referralsApi.programs(), referralsApi.overview(id), referralsApi.options(''), referralsApi.offers(id),
      build.value.state === 'ready' || build.value.state === 'unavailable' ? Promise.resolve() : loadBuild()]);
    programs.value = list; overview.value = data; options.value = choices; offers.value = benefits;
    program.value = structuredClone(data.Program);
    if (!program.value.Levels.length) program.value.Levels = [newLevel(0)];
    creating.value = false; original.value = JSON.stringify(program.value); resetForms();
    ledgerPage.value = 1; creditPage.value = 1;
    await Promise.all([loadProgramSections(data.Program.Id, data.Program.Visibility), loadLedger(), loadCredits(), loadMetrics(), loadAnalytics(), loadLinks()]);
  } catch (e) { error.value = readableError(e); }
  finally { loading.value = false; }
}
async function selectProgram(event: Event) {
  const element = event.target as HTMLSelectElement;
  const id = element.value;
  if (!discard()) { element.value = creating.value ? '__new__' : program.value?.Id ?? ''; return; }
  message.value = ''; await load(id);
}
function createPrivate() {
  if (!discard()) return;
  program.value = privateProgram(); creating.value = true; original.value = ''; offers.value = []; members.value = []; assignments.value = []; parentByChild.value = {}; resetForms(); message.value = ''; error.value = ''; tab.value = 'program'; step.value = 'audience';
}
function addLevel() {
  if (!program.value) return;
  const levels = program.value.Levels;
  // A new level lands below the ladder, strictly harder than the last visible one so the draft validates.
  const conditions = nextLevelConditions(levels);
  const level = newLevel(levels.length, conditions.MinimumQualifiedReferrals, conditions.MinimumTopupVolume);
  let suffix = levels.length + 1;
  while (levels.some(l => l.Code.trim().toUpperCase() === level.Code)) level.Code = `LEVEL_${++suffix}`;
  levels.push(level);
}
function moveLevel(index: number, by: number) {
  const levels = program.value!.Levels;
  const [level] = levels.splice(index, 1); levels.splice(index + by, 0, level!);
}
function optionalNumber(value: string): number | null { return value.trim() === '' ? null : Math.max(0, Number(value) || 0); }
function inputValue(event: Event) { return (event.target as HTMLInputElement).value; }
function iso(value: string) { return value ? new Date(value).toISOString() : null; }
function date(value: string | null | undefined, empty = '—') { return value ? new Date(value).toLocaleString() : empty; }
function day(value: string | null | undefined, empty = '—') { return value ? new Date(value).toLocaleDateString() : empty; }
function userLabel(id: number | null | undefined) { const found = users.value.find(u => u.Id === id); return found ? found.Name : id ? `User #${id}` : '—'; }
function goStep(by: number) { const next = stepIds[stepIndex.value + by]; if (next) { step.value = next; window.scrollTo({ top: 0, behavior: 'smooth' }); } }
/** Enter inside a builder field advances the step; only the Review step's Save button applies the legacy save. */
function submitBuilder() { if (step.value === 'review') void saveProgram(); else goStep(1); }
async function run(action: () => Promise<void>, success: string) {
  if (busy.value) return;
  saving.value = true; error.value = ''; message.value = '';
  try { await action(); message.value = success; }
  catch (e) { error.value = readableError(e); }
  finally { saving.value = false; }
}
/** 409 on save: fetch the server copy and show field-by-field what moved; the admin's input stays in the builder. */
async function showConflict(detail: string) {
  const id = program.value?.Id;
  if (!id || !program.value) { error.value = detail; return; }
  try {
    const server = (await referralsApi.overview(id)).Program;
    conflict.value = { server, rows: changeRows(programDiffFields(server, program.value), server, program.value, program.value.MarginPolicy), message: detail };
    step.value = 'review';
  } catch { error.value = detail; }
}
async function saveProgram() {
  if (!program.value || errors.value.length || busy.value) return;
  if (versioned.value) { error.value = 'This program has versioned offers. Publish the change through the review below instead of the immediate save.'; return; }
  if (!window.confirm('Apply these settings immediately? This updates the live program. Use the versioned publish below to protect existing terms for new referrals.')) return;
  saving.value = true; error.value = ''; message.value = '';
  try {
    const saved = await referralsApi.save(program.value, creating.value, publishNewTermsVersion.value);
    program.value = saved; original.value = JSON.stringify(saved); creating.value = false; publishNewTermsVersion.value = false;
    await load(saved.Id);
    message.value = 'Program saved. Legacy relationships use the current event-time rules. Already accrued rewards remain unchanged.';
  } catch (e) { if (isConflict(e)) await showConflict(readableError(e)); else error.value = readableError(e); }
  finally { saving.value = false; }
}
function editOffer(row: ReferralOffer) {
  offer.value = { OwnerUserId: row.OwnerUserId, ReferredTierId: row.ReferredTierId, DiscountCodeId: row.DiscountCodeId, InheritBenefits: row.InheritBenefits };
  if (options.value && !options.value.Users.some(user => user.Id === row.OwnerUserId)) options.value.Users.push({ Id: row.OwnerUserId, Name: row.OwnerName, Email: row.OwnerEmail });
}
async function saveOffer() {
  const id = program.value?.Id;
  if (!id || !offer.value.OwnerUserId) return;
  await run(async () => {
    await referralsApi.saveOffer(id, { ...offer.value, InheritBenefits: program.value!.Visibility === 'PRIVATE' ? false : offer.value.InheritBenefits });
    offers.value = await referralsApi.offers(id);
  }, 'Inviter offer saved.');
}
function editPartner(userId: number | null) {
  const existing = members.value.find(m => m.UserId === userId);
  partner.value = { ...emptyPartner(), userId, agreementReference: existing?.AgreementReference ?? '', effectiveFrom: existing?.EffectiveFrom?.slice(0, 10) ?? '',
    effectiveUntil: existing?.EffectiveUntil?.slice(0, 10) ?? '', campaignOwnerUserId: existing?.CampaignOwnerUserId ?? null, channels: (existing?.Channels ?? []).join(', '),
    fundingAllocation: existing?.FundingAllocation != null ? String(existing.FundingAllocation) : '', notes: existing?.Notes ?? '', expiresAt: existing?.ExpiresAt?.slice(0, 16) ?? '' };
  addingPartner.value = true;
}
async function refreshMembers(id: string) {
  members.value = await referralsApi.members(id);
  if (detailMember.value) detailMember.value = members.value.find(m => m.UserId === detailMember.value!.UserId) ?? null;
}
async function savePartner() {
  const id = program.value?.Id; const form = partner.value;
  if (!id || !form.userId) return;
  if (form.expiresAt && (!Number.isFinite(Date.parse(form.expiresAt)) || Date.parse(form.expiresAt) <= Date.now())) { error.value = 'Membership expiry must be in the future.'; return; }
  await run(async () => {
    await referralsApi.saveMember(id, form.userId!, {
      Active: true, Approve: form.approve, ExpiresAt: iso(form.expiresAt), AgreementReference: form.agreementReference.trim() || null,
      EffectiveFrom: iso(form.effectiveFrom), EffectiveUntil: iso(form.effectiveUntil), CampaignOwnerUserId: form.campaignOwnerUserId,
      Channels: form.channels.split(',').map(channel => channel.trim()).filter(Boolean), FundingAllocation: optionalNumber(form.fundingAllocation), Notes: form.notes.trim() || null,
    });
    await refreshMembers(id); partner.value = emptyPartner(); addingPartner.value = false;
    void loadPartnerActivity(members.value);
  }, 'Partner register updated.');
}
async function approvePartner(member: ReferralMember) {
  const id = program.value?.Id;
  if (!id) return;
  await run(async () => {
    await referralsApi.saveMember(id, member.UserId, { Active: true, Approve: true, ExpiresAt: member.ExpiresAt, AgreementReference: member.AgreementReference,
      EffectiveFrom: member.EffectiveFrom, EffectiveUntil: member.EffectiveUntil, CampaignOwnerUserId: member.CampaignOwnerUserId, Channels: member.Channels,
      FundingAllocation: member.FundingAllocation, Notes: member.Notes });
    await refreshMembers(id);
  }, 'Partner approved. They can now share this program.');
}
async function revokePartner(member: ReferralMember) {
  const id = program.value?.Id;
  if (!id || !window.confirm(`Revoke ${member.Name}? New referrals stop; existing relationships keep their earning window.`)) return;
  await run(async () => { await referralsApi.saveMember(id, member.UserId, { Active: false }); await refreshMembers(id); }, 'Partner revoked. Existing earning windows continue.');
}
function openPartner(member: ReferralMember) {
  detailMember.value = member; parentChoice.value = parentByChild.value[member.UserId] ?? null;
  assignment.value = { userId: member.UserId, levelId: activeAssignment(member.UserId)?.LevelId ?? '', expiresAt: '', notes: '' };
  if (activityState(member.UserId) !== 'ready') void loadPartnerActivity([member]);
}
async function saveAssignment() {
  const id = program.value?.Id; const form = assignment.value;
  if (!id || !form.userId || !form.levelId) return;
  await run(async () => {
    await referralsApi.saveLevelAssignment(id, form.userId!, { LevelId: form.levelId, Active: true, ExpiresAt: iso(form.expiresAt), Notes: form.notes.trim() || null });
    assignments.value = await referralsApi.levelAssignments(id);
    assignment.value = detailMember.value ? { userId: detailMember.value.UserId, levelId: '', expiresAt: '', notes: '' } : { userId: null, levelId: '', expiresAt: '', notes: '' };
  }, 'Level assignment updated.');
}
async function revokeAssignment(row: LevelAssignment) {
  const id = program.value?.Id;
  if (!id) return;
  await run(async () => { await referralsApi.saveLevelAssignment(id, row.UserId, { LevelId: row.LevelId, Active: false }); assignments.value = await referralsApi.levelAssignments(id); }, 'Level assignment revoked. The user falls back to the metric-based level.');
}
async function assignParent(child: number) {
  const id = program.value?.Id; const parent = parentChoice.value;
  if (!id || !build.value.capabilities?.SubpartnersEnabled) return;
  if (!parent || parent === child || !activeMembers.value.some(m => m.UserId === parent)) { error.value = 'Choose a different active partner of this program as the parent.'; return; }
  await run(async () => { await referralBuildApi.setParent(id, child, parent); parentByChild.value = await referralBuildApi.team(id); }, 'Parent assigned for future attributions. Existing accepted routes remain unchanged.');
}
function canRetry(credit: ReferralCredit) { return ['FAILED', 'TRANSFERRING', 'CONFIRMING'].includes(credit.Status); }
function canCancel(credit: ReferralCredit) { return !credit.ProviderReference && ['PENDING', 'FAILED', 'TRANSFERRING'].includes(credit.Status); }
function creditNote(credit: ReferralCredit) {
  switch (credit.Status) {
    case 'CONFIRMING': return 'Provider outcome unknown; not a confirmed payment yet.';
    case 'TRANSFERRING': return 'Transfer sent; waiting for the provider.';
    case 'FAILED': return credit.NextAttemptAt ? 'Will be retried automatically; retry now to skip the wait.' : 'No automatic retry scheduled.';
    case 'PAID': return credit.ProviderConfirmedAt ? 'Wallet credit confirmed.' : 'Paid.';
    case 'PENDING': return 'Queued for the next credit run.';
    default: return '';
  }
}
async function retryCredit(credit: ReferralCredit) {
  await run(async () => { await referralsApi.retryCredit(credit.Id); await loadCredits(); }, 'Credit retry requested. The provider outcome is confirmed later; watch the status.');
}
async function cancelCredit() {
  const target = cancelTarget.value; const reason = cancelReason.value.trim();
  if (!target || !reason) return;
  await run(async () => { await referralsApi.cancelCredit(target.Id, reason); cancelTarget.value = null; cancelReason.value = ''; await loadCredits(); }, 'Credit cancelled. Its rewards are back to Ready and will be credited again.');
}
onMounted(() => load());
</script>

<template>
  <AppShell>
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div><h1 class="page-title">Referral program</h1><p class="page-subtitle">Offer, qualification, window and caps, delivery, terms, partners and the reward ledger. Interlace only.</p></div>
      <button class="secondary-button" :disabled="busy" @click="discard() && load(program?.Id)">Reload</button>
    </div>
    <div v-if="error" role="alert" class="mt-5 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">{{ error }}</div>
    <div v-if="message" role="status" class="mt-5 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">{{ message }}</div>
    <div v-if="loading" role="status" class="panel mt-6 p-8">Loading referral settings…</div>
    <template v-else-if="program">
      <fieldset :disabled="busy" class="mt-6 min-w-0 space-y-6">
        <div class="panel flex flex-wrap items-end gap-4 p-5">
          <label class="referral-field w-full sm:w-auto sm:flex-1">Referral program
            <select class="field-control" :value="creating ? '__new__' : program.Id ?? ''" @change="selectProgram">
              <option v-if="creating" value="__new__">New private program (unsaved)</option>
              <option v-if="!programs.some(p => p.Visibility === 'PUBLIC')" value="">Public default</option>
              <option v-for="p in programs" :key="p.Id!" :value="p.Id!">{{ programOptionLabel(p, programs) }}</option>
            </select>
          </label>
          <button class="secondary-button" @click="createPrivate">Create private program</button>
          <div class="flex flex-wrap gap-2 self-center"><StatusPill :label="program.Status" :tone="statusTone(program.Status)" /><span class="status-pill status-pill--neutral">{{ program.Visibility === 'PRIVATE' ? 'Invite only' : 'Public' }}</span><span v-if="program.Exists" class="status-pill status-pill--neutral">Terms v{{ program.TermsVersion }}</span><span class="status-pill status-pill--neutral">{{ program.PayoutCurrency }}</span></div>
        </div>
        <div v-if="overview && !creating" class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          <div v-for="metric in stats" :key="metric.label" class="metric-card"><div class="text-sm text-slate-500">{{ metric.label }}</div><div class="mt-2 truncate text-xl font-bold">{{ metric.value }}</div></div>
        </div>
        <div class="flex flex-wrap gap-2" role="tablist">
          <button v-for="item in tabs" :key="item.id" type="button" role="tab" :aria-selected="tab === item.id" :class="tab === item.id ? 'primary-button' : 'secondary-button'" @click="tab = item.id">{{ item.label }}</button>
        </div>

        <ReferralRelationships v-if="tab === 'relationships' && program.Id" :key="program.Id" :program-id="program.Id" />
        <ReferralCommunity v-if="tab === 'community' && program.Id && program.Visibility === 'PUBLIC'" :key="program.Id" :program-id="program.Id" :users="users" />
        <ReferralRisk v-if="tab === 'review' && program.Id" :key="program.Id" :program-id="program.Id" :delivery-mode="program.DeliveryMode" />
        <ReferralLifecycle v-if="tab === 'members' && program.Id" :key="program.Id" :program-id="program.Id" :members="members" :users="users" />
        <ReferralTools v-if="tab === 'tools' && program.Id" :key="program.Id" :program="program" />
        <template v-if="tab === 'performance'">
          <section class="panel p-5 sm:p-6">
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div><h2 class="panel-heading">Performance</h2><p class="mt-2 text-sm text-slate-500">Funnel, cost and contribution of relationships attributed in the period. Amounts are in the payout currency of the response.</p></div>
              <p v-if="perf" class="text-sm text-slate-500">{{ day(perf.From) }} – {{ day(perf.To) }}</p>
            </div>
            <form class="mt-4 flex flex-wrap items-end gap-3" @submit.prevent="loadAnalytics">
              <label class="referral-field">Program<select v-model="analyticsFilters.programId" class="field-control" @change="loadAnalytics"><option value="">All programs</option><option v-for="p in programs" :key="p.Id!" :value="p.Id!">{{ programOptionLabel(p, programs, false) }}</option></select></label>
              <label class="referral-field">Period<select v-model="analyticsFilters.period" class="field-control" @change="selectPeriod"><option v-for="p in periods" :key="p.id" :value="p.id">{{ p.label }}</option></select></label>
              <template v-if="analyticsFilters.period === 'custom'">
                <label class="referral-field">From<input v-model="analyticsFilters.from" type="date" class="field-control" /></label>
                <label class="referral-field">To<input v-model="analyticsFilters.to" type="date" class="field-control" /></label>
              </template>
              <label class="referral-field">Leaderboard size<select v-model.number="analyticsFilters.top" class="field-control" @change="loadAnalytics"><option v-for="n in topChoices" :key="n" :value="n">Top {{ n }}</option></select></label>
              <button class="secondary-button" :disabled="analyticsLoading">{{ analyticsLoading ? 'Loading…' : 'Apply' }}</button>
            </form>
            <p v-if="analyticsUnavailable" role="status" class="mt-4 rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">Analytics not available yet. The connected platform does not expose the referral analytics endpoint; the other tabs are unaffected.</p>
            <div v-if="sampleAvailable" class="mt-4 flex flex-wrap items-center justify-between gap-3">
              <p class="text-sm text-slate-500">{{ analyticsUnavailable ? 'Preview the tab with a built-in dataset.' : 'No relationships were attributed in this period.' }}</p>
              <label class="sample-switch"><input v-model="showSample" type="checkbox" role="switch" :aria-checked="showSample" /> Show sample data</label>
            </div>
            <p v-if="sectionErrors.analytics" role="alert" class="mt-4 text-sm text-red-700">Could not load analytics. {{ sectionErrors.analytics }}</p>
            <p v-else-if="!analytics && analyticsLoading" role="status" class="mt-4 text-sm text-slate-500">Loading analytics…</p>
          </section>
          <template v-if="perf">
            <div v-if="sampleMode" role="status" class="flex flex-wrap items-center gap-3 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">
              <span class="font-semibold uppercase tracking-wide">Sample data, not live figures</span><span>Built-in demo dataset so the tab can be previewed before the program has traffic. Nothing below comes from the connected platform and nothing is sent to it.</span>
            </div>
            <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
              <div v-for="tile in kpis" :key="tile.label" class="metric-card" :class="tile.negative ? 'border-red-200 bg-red-50' : ''"><div class="text-sm text-slate-500">{{ tile.label }}</div><div class="mt-2 truncate text-xl font-bold">{{ tile.value }}</div><div class="mt-1 text-xs text-slate-500">{{ tile.note }}</div></div>
            </div>
            <div class="grid gap-6 xl:grid-cols-2">
              <section class="panel p-5 sm:p-6">
                <h2 class="panel-heading">Funnel</h2><p class="mt-2 text-sm text-slate-500">Relationships attributed in the period, by the furthest stage reached. Percentages are of invited.</p>
                <div class="mt-4">
                  <AnalyticsChart kind="funnel" :labels="funnelLabels" :series="funnelSeries" :height="300" :tooltip-extra="funnelShare" :bar-labels="funnelBarLabel"
                    empty-text="No relationships were attributed in this period." aria-label="Funnel: relationships by furthest stage reached" />
                </div>
                <div class="mt-5 grid gap-3 sm:grid-cols-2">
                  <div class="rounded-xl border border-slate-200 p-3"><p class="text-xs text-slate-500">Median time to qualify</p><p class="mt-1 font-semibold">{{ hours(perf.Funnel.MedianHoursToQualify) }}</p></div>
                  <div class="rounded-xl border border-slate-200 p-3"><p class="text-xs text-slate-500">Average time to qualify</p><p class="mt-1 font-semibold">{{ hours(perf.Funnel.AverageHoursToQualify) }}</p></div>
                </div>
              </section>
              <section class="panel p-5 sm:p-6">
                <h2 class="panel-heading">Fees, cost and contribution</h2><p class="mt-2 text-sm text-slate-500">Fees on commissionable top-ups of referred users in the period, what the provider charged for them, and what the program promised in return.</p>
                <div class="mt-4 grid gap-3 sm:grid-cols-2">
                  <div v-for="tile in economics" :key="tile.label" class="rounded-xl border p-4" :class="tile.negative ? 'border-red-200 bg-red-50' : tile.label === 'Accrued contribution' ? 'border-emerald-200 bg-emerald-50' : 'border-slate-200'"><p class="text-xs text-slate-500">{{ tile.label }}</p><p class="mt-1 text-lg font-semibold">{{ tile.value }}</p><p class="mt-1 text-xs text-slate-500">{{ tile.note }}</p></div>
                </div>
                <h3 class="mt-6 font-semibold">Reward cost breakdown</h3>
                <div class="mt-3 grid items-center gap-4 sm:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
                  <AnalyticsChart kind="doughnut" :labels="costLabels" :series="costSeries" :height="220" empty-text="No reward cost in this period." aria-label="Reward cost by type" />
                  <ul class="space-y-2 text-sm">
                    <li v-for="row in costByType" :key="row.label" class="flex items-baseline justify-between gap-3"><span class="text-slate-500">{{ row.label }}</span><span class="font-semibold" :class="row.amount < 0 ? 'text-red-700' : ''">{{ money(row.amount, perf.Cost.Currency) }}</span></li>
                  </ul>
                </div>
                <p class="mt-5 text-sm font-semibold">Accrued: paid vs outstanding</p>
                <div class="mt-2">
                  <AnalyticsChart kind="horizontalBar" :labels="['Accrued']" :series="costStatusSeries" :height="110" stacked :format-y="axisMoney" empty-text="No rewards accrued in this period." aria-label="Rewards accrued split into paid and outstanding" />
                </div>
                <div class="mt-4 grid gap-3 sm:grid-cols-3">
                  <div v-for="tile in [['Accrued', perf.Cost.Accrued], ['Paid', perf.Cost.Paid], ['Outstanding', perf.Cost.Outstanding]]" :key="String(tile[0])" class="rounded-xl border border-slate-200 p-3"><p class="text-xs text-slate-500">{{ tile[0] }}</p><p class="mt-1 font-semibold">{{ money(Number(tile[1]), perf.Cost.Currency) }}</p></div>
                </div>
              </section>
            </div>
            <section class="panel p-5 sm:p-6">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div><h2 class="panel-heading">Weekly</h2><p class="mt-2 text-sm text-slate-500">Weeks by attribution date. Attributed and qualified relationships as lines; top-up volume, rewards and credits on their own scales.</p></div>
                <button type="button" class="secondary-button" :aria-expanded="showWeeklyTable" @click="showWeeklyTable = !showWeeklyTable">{{ showWeeklyTable ? 'Hide table' : 'Show table' }}</button>
              </div>
              <div class="mt-4 grid gap-6 xl:grid-cols-2">
                <div>
                  <p class="text-sm font-semibold">Relationships and top-up volume</p>
                  <div class="mt-2"><AnalyticsChart kind="bar" :labels="weekLabels" :series="weeklyActivitySeries" :height="280" :format-y1="axisMoney" title-y="Relationships" :title-y1="`Top-up volume (${analyticsCurrency})`" empty-text="No weekly data for this period." aria-label="Weekly attributed and qualified relationships with top-up volume" /></div>
                </div>
                <div>
                  <p class="text-sm font-semibold">Rewards and credits</p>
                  <div class="mt-2"><AnalyticsChart kind="bar" :labels="weekLabels" :series="weeklyRewardSeries" :height="280" :format-y="axisMoney" :title-y="`Rewards (${analyticsCurrency})`" title-y1="Credits paid" empty-text="No weekly data for this period." aria-label="Weekly rewards accrued and paid with credits paid" /></div>
                </div>
              </div>
              <div v-if="showWeeklyTable" class="mt-5 overflow-x-auto"><table class="data-table min-w-[800px]"><thead><tr><th>Week</th><th>Attributed</th><th>Qualified</th><th>Top-up volume</th><th>Rewards accrued</th><th>Rewards paid</th><th>Credits paid</th></tr></thead><tbody>
                <tr v-for="week in perf.Weekly" :key="week.WeekStart"><td>{{ day(week.WeekStart) }}</td><td>{{ week.Attributed }}</td><td>{{ week.Qualified }}<span v-if="week.Attributed" class="text-xs text-slate-500"> ({{ Math.round((week.Qualified / week.Attributed) * 100) }}%)</span></td><td>{{ money(week.TopupVolume, perf.Currency) }}</td><td>{{ money(week.RewardsAccrued, perf.Currency) }}</td><td>{{ money(week.RewardsPaid, perf.Currency) }}</td><td>{{ week.CreditsPaid }}</td></tr>
                <tr v-if="!perf.Weekly.length"><td colspan="7">No weekly data for this period.</td></tr>
              </tbody></table></div>
            </section>
            <section class="panel p-5 sm:p-6">
              <h2 class="panel-heading">Top referrers</h2><p class="mt-2 text-sm text-slate-500">Ranked by activity in the period. Partner marks members of a private program.</p>
              <div class="mt-4">
                <AnalyticsChart kind="horizontalBar" :labels="leaderboardLabels" :series="leaderboardSeries" :height="rowsHeight(perf.Leaderboard.length)" :legend="false" :format-y="axisMoney" :tooltip-extra="leaderboardExtra"
                  :title-y="`Rewards accrued (${analyticsCurrency})`" empty-text="No referrer activity in this period." aria-label="Rewards accrued by top referrers" />
              </div>
              <div class="mt-4 overflow-x-auto"><table class="data-table min-w-[900px]"><thead><tr><th>#</th><th>Referrer</th><th>Level</th><th>Attributed</th><th>Qualified</th><th>Eligible volume</th><th>Rewards accrued</th><th>Rewards paid</th></tr></thead><tbody>
                <tr v-for="(row, index) in perf.Leaderboard" :key="row.UserId"><td>{{ index + 1 }}</td><td>{{ row.Name }}<span v-if="row.Partner" class="status-pill status-pill--neutral ml-2">partner</span><div class="text-xs text-slate-500">{{ row.Email }} · #{{ row.UserId }}</div></td><td class="font-mono text-xs">{{ row.LevelCode || '—' }}</td><td>{{ row.Attributed }}</td><td>{{ row.Qualified }}</td><td>{{ money(row.EligibleVolume, perf.Currency) }}</td><td>{{ money(row.RewardsAccrued, perf.Currency) }}</td><td>{{ money(row.RewardsPaid, perf.Currency) }}</td></tr>
                <tr v-if="!perf.Leaderboard.length"><td colspan="8">No referrer activity in this period.</td></tr></tbody></table></div>
            </section>
            <div class="grid gap-6 xl:grid-cols-2">
              <section class="panel p-5 sm:p-6">
                <h2 class="panel-heading">Programs</h2><p class="mt-2 text-sm text-slate-500">Relationships and rewards per program in the period; reserved exposure is the current value.</p>
                <div v-if="perf.Programs.length > 1" class="mt-4">
                  <AnalyticsChart kind="bar" :labels="programLabels" :series="programSeries" :height="220" :format-y="axisMoney" :title-y="`Rewards (${analyticsCurrency})`" empty-text="No rewards per program in this period." aria-label="Rewards outstanding and paid per program" />
                </div>
                <div class="mt-4 overflow-x-auto"><table class="data-table min-w-[700px]"><thead><tr><th>Program</th><th>Status</th><th>Relationships</th><th>Qualified</th><th>Outstanding</th><th>Paid</th><th>Exposure</th></tr></thead><tbody>
                  <tr v-for="p in perf.Programs" :key="p.Id"><td>{{ p.Name }}<div class="text-xs text-slate-500">{{ p.Visibility.toLowerCase() }}</div></td><td><StatusPill :label="p.Status" :tone="statusTone(p.Status)" /></td><td>{{ p.Relationships }}</td><td>{{ p.Qualified }}</td><td>{{ money(p.RewardsOutstanding, perf.Currency) }}</td><td>{{ money(p.RewardsPaid, perf.Currency) }}</td><td class="text-xs">{{ money(p.ReservedExposure, perf.Currency) }}{{ p.ExposureLimit != null ? ` of ${money(p.ExposureLimit, perf.Currency)}` : '' }}</td></tr>
                  <tr v-if="!perf.Programs.length"><td colspan="7">No programs.</td></tr></tbody></table></div>
              </section>
              <section class="panel p-5 sm:p-6">
                <h2 class="panel-heading">Excluded events</h2><p class="mt-2 text-sm text-slate-500">Top-ups and qualifications in the period that earned nothing, by reason. Amount is the excluded basis.</p>
                <div class="mt-4">
                  <AnalyticsChart kind="horizontalBar" :labels="exclusionLabels" :series="exclusionSeries" :height="rowsHeight(perf.Exclusions.length)" :legend="false" :tooltip-extra="exclusionExtra" title-y="Events" empty-text="No excluded events in this period." aria-label="Excluded events by reason" />
                </div>
                <div class="mt-4 overflow-x-auto"><table class="data-table"><thead><tr><th>Reason</th><th>Count</th><th>Amount</th></tr></thead><tbody>
                  <tr v-for="row in perf.Exclusions" :key="row.Reason"><td>{{ statusLabel(row.Reason) }}<div class="font-mono text-xs text-slate-500">{{ row.Reason }}</div></td><td>{{ row.Count }}</td><td>{{ money(row.Amount, perf.Currency) }}</td></tr>
                  <tr v-if="!perf.Exclusions.length"><td colspan="3">No excluded events in this period.</td></tr></tbody></table></div>
              </section>
            </div>
            <section v-if="perfReconciliation" class="panel p-5 sm:p-6">
              <h2 class="panel-heading">Reconciliation</h2><p class="mt-2 text-sm text-slate-500">Current queue state, generated {{ date(perfReconciliation.GeneratedAt) }}. Manage individual credits on the Credits tab.</p>
              <div class="mt-4 grid gap-3 sm:grid-cols-3 xl:grid-cols-5">
                <div v-for="tile in [['Rewards ready', perfReconciliation.RewardsReady], ['Rewards crediting', perfReconciliation.RewardsCrediting], ['Rewards failed', perfReconciliation.RewardsFailed], ['Credits pending', perfReconciliation.CreditsPending], ['Credits transferring', perfReconciliation.CreditsTransferring], ['Credits confirming', perfReconciliation.CreditsConfirming], ['Credits failed', perfReconciliation.CreditsFailed], ['Credits stale', perfReconciliation.CreditsStale], ['Reserved exposure', `${money(perfReconciliation.ReservedExposure, perfReconciliation.Currency)}${perfReconciliation.ExposureLimit != null ? ` of ${money(perfReconciliation.ExposureLimit, perfReconciliation.Currency)}` : ''}`]]" :key="String(tile[0])" class="rounded-xl border p-4" :class="['Credits stale', 'Credits failed', 'Rewards failed'].includes(String(tile[0])) && Number(tile[1]) > 0 ? 'border-red-200 bg-red-50' : 'border-slate-200'"><p class="text-xs text-slate-500">{{ tile[0] }}</p><p class="mt-1 text-lg font-semibold">{{ tile[1] }}</p></div>
              </div>
            </section>
          </template>
        </template>

        <template v-else-if="tab === 'program'">
        <div v-if="conflict" role="alert" class="rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-900">
          <p class="font-semibold">The live program changed while you were editing (server revision {{ conflict.server.Revision }}, you loaded revision {{ program.Revision }}).</p>
          <p class="mt-1">{{ conflict.message }} Your edits are kept below. Compare the server's values, then reload to merge before saving again.</p>
          <table v-if="conflict.rows.length" class="mt-3 w-full text-sm"><thead><tr class="text-left text-xs uppercase tracking-wide text-slate-500"><th class="pb-1 pr-3 font-semibold">Field</th><th class="pb-1 pr-3 font-semibold">On the server</th><th class="pb-1 font-semibold">Your edit</th></tr></thead><tbody>
            <tr v-for="row in conflict.rows" :key="row.field" class="border-t border-amber-200/70 align-top"><td class="py-1 pr-3" :class="row.detail ? 'pl-4 text-slate-600' : 'font-medium'">{{ row.label }}</td><td class="py-1 pr-3">{{ row.from ?? '—' }}</td><td class="py-1">{{ row.to ?? '—' }}</td></tr>
          </tbody></table>
          <p v-else class="mt-2">No field differs; only the revision moved on.</p>
          <div class="mt-3 flex flex-wrap gap-2"><button type="button" class="secondary-button" @click="conflict = null">Keep editing</button><button type="button" class="primary-button" @click="discard() && load(program.Id)">Reload the server version</button></div>
        </div>
        <div class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_21rem]">
          <div class="min-w-0 space-y-6">
            <nav class="panel p-2" aria-label="Offer builder steps">
              <ol class="grid gap-1 md:grid-cols-5">
                <li v-for="(item, index) in BUILDER_STEPS" :key="item.id">
                  <button type="button" class="step-button" :class="step === item.id ? 'step-button--active' : ''" :aria-current="step === item.id ? 'step' : undefined" @click="step = item.id">
                    <span class="step-index">{{ index + 1 }}</span>
                    <span class="min-w-0"><span class="block truncate text-sm font-semibold">{{ item.label }}</span><span class="block truncate text-xs text-slate-500">{{ item.hint }}</span></span>
                    <span v-if="issuesByStep[item.id]" class="status-pill status-pill--warning ml-auto" :aria-label="`${issuesByStep[item.id]} issues`">{{ issuesByStep[item.id] }}</span>
                  </button>
                </li>
              </ol>
            </nav>
            <form class="space-y-6" @submit.prevent="submitBuilder">
              <template v-if="step === 'audience'">
                <section class="panel p-5 sm:p-6">
                  <h2 class="panel-heading">Audience</h2><p class="mt-1 text-sm text-slate-500">Who this program is for. Public programs are open to every member; private programs are invite-only for approved partners.</p>
                  <div class="mt-5 grid gap-5 sm:grid-cols-2">
                    <label class="referral-field">Program name<input v-model="program.Name" class="field-control" maxlength="80" required /></label>
                    <label class="referral-field">Program status<select v-model="program.Status" class="field-control"><option value="DRAFT">Draft</option><option value="ACTIVE">Active</option><option value="PAUSED">Paused</option><option value="ARCHIVED">Archived</option></select><small>Pausing or archiving stops new invitations. Accepted versioned offers retain their obligations; legacy programs keep their existing pause and archive rules.</small></label>
                    <label class="referral-field sm:col-span-2">Description<textarea v-model="program.Description" rows="4" maxlength="2000" class="field-control resize-y py-2" placeholder="Optional introduction. Required offer conditions are always shown." /><small>Shown alongside the generated qualification and reward conditions. Leave it empty to show only the generated conditions.</small></label>
                    <div class="referral-field">Visibility<div class="flex items-center gap-2"><span class="status-pill status-pill--neutral">{{ program.Visibility === 'PRIVATE' ? 'Invite only · partners must be approved' : 'Public · open to every member' }}</span></div><small>Set when the program is created. Private programs manage their partner register on the Partners tab.</small></div>
                  </div>
                </section>
                <section class="panel p-5 sm:p-6">
                  <h2 class="panel-heading">Terms</h2><p class="mt-1 text-sm text-slate-500">Members accept the current version before their first share; friends accept the attribution at sign-up. A rate change bumps the version automatically.</p>
                  <div class="mt-5 space-y-5">
                    <label class="referral-field">Terms text<textarea v-model="program.TermsText" rows="6" maxlength="20000" class="field-control py-2" placeholder="Who gets what, when, and what stops commission." /></label>
                    <label class="referral-field">Privacy notice<textarea v-model="program.PrivacyNotice" rows="4" maxlength="5000" class="field-control py-2" /><small>Disclose that a published rate can reveal a friend's top-ups to the inviter, and that only pseudonyms are shown.</small></label>
                    <p class="text-sm text-slate-500">Version {{ program.TermsVersion }}{{ program.PublishedAt ? ` · published ${day(program.PublishedAt)}` : '' }}. Whether members must accept again is decided in the Review step.</p>
                  </div>
                </section>
              </template>
              <template v-else-if="step === 'qualification'">
                <section class="panel p-5 sm:p-6">
                  <h2 class="panel-heading">Qualification</h2><p class="mt-1 text-sm text-slate-500">Every enabled condition must be met before the welcome and the qualification reward are paid. The qualifying top-up also earns the normal top-up commission.</p>
                  <div class="mt-5 space-y-3">
                    <label class="check-row"><input v-model="program.QualifyRequiresKyc" type="checkbox" /><span>Requires identity verification (KYC approved)</span></label>
                    <label class="check-row"><input v-model="program.QualifyRequiresPaidCard" type="checkbox" /><span>Requires a paid card<small>Free cards do not count while this is on.</small></span></label>
                    <label class="check-row"><input v-model="program.QualifyRequiresTopup" type="checkbox" /><span>Requires a first external top-up<small>Reward money, vouchers and internal transfers never qualify.</small></span></label>
                    <label class="referral-field">Minimum qualifying top-up ({{ program.PayoutCurrency }})<input :value="program.QualifyMinimumTopup ?? ''" type="number" min="0" step="0.01" placeholder="Platform minimum" class="field-control" @input="program.QualifyMinimumTopup = optionalNumber(inputValue($event))" /><small>Leave blank to use the platform card top-up minimum.</small></label>
                  </div>
                </section>
              </template>
              <template v-else-if="step === 'rewards'">
                <section class="panel p-5 sm:p-6">
                  <h2 class="panel-heading">Rewards</h2><p class="mt-1 text-sm text-slate-500">What the customer gets and what the inviter earns. Per-level inviter rewards are set in the levels below.</p>
                  <div class="mt-5 rounded-2xl bg-slate-950 p-6 text-white"><p class="text-xs uppercase tracking-[0.2em] text-slate-400">Members see</p><p class="mt-2 text-2xl font-semibold">{{ headline }}</p><p class="mt-2 text-sm text-slate-400">{{ program.Name || 'Referral rewards' }} · {{ program.LevelLookbackMonths ? `${program.LevelLookbackMonths} month level lookback` : 'lifetime level lookback' }}</p>
                    <div class="mt-4 flex flex-wrap gap-2"><span v-for="level in program.Levels" :key="level.Id" class="rounded-full border border-white/10 bg-white/5 px-3 py-1.5 text-sm"><span class="mr-2 inline-block size-2.5 rounded-full" :style="{ backgroundColor: level.Color }" />{{ level.Name }}{{ level.Hidden ? ' · hidden' : '' }}<span class="ml-2 text-slate-400">{{ levelConditionLabel(level, program.PayoutCurrency) }}</span></span></div></div>
                  <div class="mt-5 grid gap-5 sm:grid-cols-3">
                    <label class="referral-field">Customer welcome reward<input v-model.number="program.WelcomeAmount" type="number" min="0" step="0.01" required class="field-control" /><small>Added to the customer's balance when they qualify. 0 disables the welcome.</small></label>
                    <label class="referral-field">Welcome currency<select v-model="program.WelcomeCurrency" class="field-control"><option>USD</option><option>USDT</option><option>USDC</option></select></label>
                    <label class="referral-field">Level lookback (months)<input v-model.number="program.LevelLookbackMonths" type="number" min="0" max="1200" required class="field-control" /><small>How long qualified referrals and their top-ups count towards a member's level. 0 = lifetime.</small></label>
                  </div>
                  <p v-if="baseLevel" class="mt-4 text-sm text-slate-500">Inviter on {{ baseLevel.Name }}: {{ rewardRateLabel(baseLevel.QualificationCalculationType, baseLevel.QualificationRate, program.PayoutCurrency) }} when the friend qualifies, then {{ rewardRateLabel(baseLevel.TopupCalculationType, baseLevel.TopupRate, program.PayoutCurrency) }} on eligible top-ups.</p>
                </section>
                <section class="panel p-5 sm:p-6">
                  <div class="flex items-center justify-between gap-3"><h2 class="panel-heading">Levels</h2><button type="button" class="secondary-button" :disabled="program.Levels.length >= 50" @click="addLevel">Add level</button></div>
                  <p class="mt-2 text-sm text-slate-500">Each level sets the inviter's qualification reward and top-up rate. A level is reached when every condition set on it is met: a minimum number of qualified referrals and/or a minimum combined top-up amount of the referred friends, both inside the level lookback. The first visible level has no conditions; every later level needs at least one and must require more than the level before it. Hidden levels are never listed and only apply through a direct assignment (creator rates).</p>
                  <article v-for="(level, index) in program.Levels" :key="level.Id" class="mt-5 rounded-xl border border-slate-200 p-4" :style="{ borderLeftWidth: '4px', borderLeftColor: level.Color }">
                    <div class="flex flex-wrap items-center justify-between gap-3"><h3 class="font-semibold">{{ level.Name || `Level ${index + 1}` }} <span class="text-sm font-normal text-slate-500">· Position {{ index + 1 }}{{ level.Hidden ? ' · hidden' : '' }} · {{ levelConditionLabel(level, program.PayoutCurrency) }}</span></h3>
                      <div class="flex gap-2"><button type="button" class="secondary-button" :aria-label="`Move level ${index + 1} up`" :disabled="index === 0" @click="moveLevel(index, -1)">↑</button><button type="button" class="secondary-button" :aria-label="`Move level ${index + 1} down`" :disabled="index === program.Levels.length - 1" @click="moveLevel(index, 1)">↓</button><button type="button" class="danger-button" :aria-label="`Remove level ${index + 1}`" :disabled="program.Levels.length === 1" @click="program.Levels.splice(index, 1)">Remove</button></div>
                    </div>
                    <div class="mt-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
                      <label class="referral-field">Name<input v-model="level.Name" class="field-control" required maxlength="80" /></label>
                      <label class="referral-field">Code<input v-model="level.Code" class="field-control" required maxlength="32" /></label>
                      <label class="referral-field">Icon<input v-model="level.Icon" class="field-control" list="referral-icons" required maxlength="40" /></label>
                      <label class="referral-field">Color<div class="flex gap-2"><input v-model="level.Color" type="color" class="h-11 w-12" :aria-label="`Level ${index + 1} color picker`" /><input v-model="level.Color" class="field-control min-w-0 w-full" required pattern="#[0-9A-Fa-f]{6}" /></div></label>
                      <label class="referral-field">Min. qualified referrals<input :value="level.MinimumQualifiedReferrals ?? ''" type="number" min="0" max="1000000" step="1" :disabled="level.Hidden" placeholder="No condition" class="field-control" @input="level.MinimumQualifiedReferrals = optionalNumber(inputValue($event))" /><small v-if="level.Hidden">Not used: hidden levels are assigned directly.</small><small v-else>Leave empty for no condition.</small></label>
                      <label class="referral-field">Min. combined top-ups ({{ program.PayoutCurrency }})<input :value="level.MinimumTopupVolume ?? ''" type="number" min="0" step="0.01" :disabled="level.Hidden" placeholder="No condition" class="field-control" @input="level.MinimumTopupVolume = optionalNumber(inputValue($event))" /><small v-if="level.Hidden">Not used: hidden levels are assigned directly.</small><small v-else>Leave empty for no condition. Sum of the referred friends' external card top-ups inside the lookback.</small></label>
                      <label class="referral-field">Qualification reward<select v-model="level.QualificationCalculationType" class="field-control"><option value="FIXED">Fixed amount</option><option value="PERCENT_OF_CARD_FEE" :disabled="buildAvailable">% of card fee (legacy only)</option></select><input v-model.number="level.QualificationRate" aria-label="Qualification rate" type="number" min="0" :max="level.QualificationCalculationType === 'FIXED' ? 9999999999 : 100" step="any" required class="field-control" /><small>Paid to the inviter once, when the friend qualifies.</small></label>
                      <label class="referral-field">Top-up reward<select v-model="level.TopupCalculationType" class="field-control"><option value="PERCENT_OF_TOPUP">% of credited top-up</option><option value="PERCENT_OF_WL_FEE">% of WL fee</option><option value="FIXED">Fixed amount</option></select><input v-model.number="level.TopupRate" aria-label="Top-up rate" type="number" min="0" step="any" required class="field-control" /><small v-if="overview?.TopupRewardLimits">Per eligible external top-up inside the window. Maximum {{ rewardMaximum(level, overview.TopupRewardLimits) }}{{ level.TopupCalculationType === 'FIXED' ? ` ${program.PayoutCurrency} per top-up` : level.TopupCalculationType === 'PERCENT_OF_WL_FEE' ? '% of the WL fee' : '% of the credited top-up' }} (fee minus cost, see below).</small><small v-else-if="program.MarginPolicy">Replaced by the margin share below while margin sharing is on.</small></label>
                      <ReferralCapControl v-model:mode="level.VolumeCapMode" v-model:amount="level.VolumeCapAmount" tier label="Eligible top-up volume cap per friend" :currency="program.PayoutCurrency" :effective="levelCapLabel(program, level, 'volume')" />
                      <ReferralCapControl v-model:mode="level.RecurringRewardCapMode" v-model:amount="level.RecurringRewardCapAmount" tier label="Recurring reward cap per friend" :currency="program.PayoutCurrency" :effective="levelCapLabel(program, level, 'recurring')" />
                      <label class="check-row self-start"><input v-model="level.Hidden" type="checkbox" /><span>Hidden level<small>Only reachable through a level assignment.</small></span></label>
                    </div>
                  </article>
                  <datalist id="referral-icons"><option v-for="icon in LEVEL_ICONS" :key="icon" :value="icon" /></datalist>
                  <div class="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">
                    <p class="font-semibold text-slate-800">Top-up reward maximum: WL fee minus cost</p>
                    <p class="mt-1">Limits use the lowest margin across the company default and active tiers. Every payout is also capped at the actual settled fee minus cost, so fee changes, rounding and partial top-ups can reduce the reward.</p>
                    <p class="mt-1">Each cap uses its own limiting company or tier schedule. Credited-top-up cap = (fee − cost) ÷ (1 − fee) × 100; WL-fee cap = (fee − cost) ÷ fee × 100. Fee and cost are fractions of gross top-up. Actual payment is capped again by settled fee minus attributable cost. Zero is a valid returned cap.</p>
                    <p v-if="overview?.TopupRewardLimits" class="mt-1">Fixed rewards are limited using the minimum gross top-up of {{ overview.TopupRewardLimits.MinimumGrossTopupAmount }} USD. Maximum: {{ overview.TopupRewardLimits.MaxFixedAmount }} {{ program.PayoutCurrency }}; {{ overview.TopupRewardLimits.MaxPercentOfTopup }}% of the credited top-up; or {{ overview.TopupRewardLimits.MaxPercentOfWlFee }}% of the WL fee.</p>
                    <p v-else class="mt-1 text-amber-800">Reward limits were not returned by the platform; saving is blocked until they load.</p>
                    <div v-if="overview?.TopupRewardLimits?.CapSources?.length" class="overflow-x-auto mt-3"><table class="data-table min-w-[650px]"><thead><tr><th>Reward basis</th><th>Limiting schedule</th><th>Fee / cost (% of gross)</th><th>Maximum</th><th>Availability</th></tr></thead><tbody><tr v-for="source in overview.TopupRewardLimits.CapSources" :key="source.Calculation"><td>{{ source.Calculation }}</td><td>{{ source.TierName || (source.ScheduleKind === 'COMPANY' ? 'Company default' : `Tier #${source.TierId}`) }}</td><td>{{ trimNumber(source.FeeRate * 100, 4) }}% / {{ trimNumber(source.CostRate * 100, 4) }}%</td><td>{{ source.Maximum }} {{ source.Calculation === 'FIXED' ? program.PayoutCurrency : '%' }}</td><td>{{ source.Availability.replace(/_/g, ' ').toLowerCase() }}</td></tr></tbody></table></div>
                  </div>
                </section>
                <div v-if="program.Id && !creating" class="grid gap-6 xl:grid-cols-2">
                  <section class="panel p-5 sm:p-6">
                    <h2 class="panel-heading">Adjust the reward split</h2><p class="mt-1 text-sm text-slate-500">Optional settled-margin sharing for versioned offers. Every percentage names its denominator.</p>
                    <div class="mt-5"><ReferralMarginEditor :model-value="program.MarginPolicy ?? null" :capabilities="build.capabilities" :available="buildAvailable" @update:model-value="program.MarginPolicy = $event" /></div>
                  </section>
                  <ReferralEarningsCalculator :program="program" :valid="errors.length === 0" :available="buildAvailable" />
                </div>
              </template>
              <template v-else-if="step === 'limits'">
                <section class="panel p-5 sm:p-6">
                  <h2 class="panel-heading">Window and caps</h2><p class="mt-1 text-sm text-slate-500">How long a friend's top-ups earn commission and which optional limits apply.</p>
                  <div class="mt-5 grid gap-5 sm:grid-cols-2">
                    <label class="referral-field">Earning window (days)<input v-model.number="program.EarningWindowDays" type="number" min="0" max="36500" required class="field-control" /><small>0 = no end.</small></label>
                    <label class="referral-field">Window starts at<select v-model="program.EarningWindowStart" class="field-control"><option value="QUALIFICATION">Qualification</option><option value="ATTRIBUTION">Attribution (sign-up)</option></select></label>
                    <ReferralCapControl v-model:amount="program.MaxEligibleVolumePerRelationship" label="Default eligible top-up volume cap per friend" :currency="program.PayoutCurrency" />
                    <ReferralCapControl v-model:amount="program.MaximumRecurringReward" label="Default recurring reward cap per friend" :currency="program.PayoutCurrency" />
                    <p class="text-sm text-slate-500 sm:col-span-2">Each tier can inherit these defaults or independently set an amount or No cap in Rewards. Accepted referrals keep the tier, rate, limits and earning window captured at attribution. Later tier changes affect new referrals; counters do not reset and refunds do not reopen reward caps.</p>
                    <label class="referral-field">Program exposure limit ({{ program.PayoutCurrency }})<input :value="program.ExposureLimit ?? ''" type="number" min="0" step="0.01" placeholder="No limit" class="field-control" @input="program.ExposureLimit = optionalNumber(inputValue($event))" /><small>New referrals are refused when their known reserved liability would exceed this limit. Uncapped earnings on accepted referrals still accrue and may take known exposure above it. Blank = no program exposure limit.</small></label>
                    <label class="referral-field">Reserved exposure<input :value="money(program.ReservedExposure, program.PayoutCurrency)" readonly class="field-control bg-slate-50" /><small>Known remaining reserved liability, including fixed commitments and bounded recurring rewards. Uncapped future rewards are not a finite lifetime promise represented by this number.</small></label>
                  </div>
                  <p v-if="overview?.ExposureAccountingDescription" class="mt-3 text-sm text-slate-600">{{ overview.ExposureAccountingDescription }}</p>
                </section>
                <section class="panel p-5 sm:p-6">
                  <h2 class="panel-heading">Delivery</h2><p class="mt-1 text-sm text-slate-500">Wallet credit adds rewards to the user's USD balance automatically after provider confirmation. No claim step.</p>
                  <div class="mt-5 grid gap-5 sm:grid-cols-2">
                    <label class="referral-field">Delivery mode<select v-model="program.DeliveryMode" class="field-control"><option value="WALLET_CREDIT">Wallet credit (USD balance)</option><option value="AUTOMATIC_TRANSFER">Automatic transfer (legacy voucher)</option><option value="VOUCHER_PER_COMMISSION">Voucher per commission (legacy)</option></select></label>
                    <label class="referral-field">Payout currency<select v-model="program.PayoutCurrency" class="field-control"><option>USD</option><option>USDT</option><option>USDC</option></select><small>The API prevents currency changes after rewards accrue. Versioned offers need the welcome and payout currency to match.</small></label>
                    <label class="referral-field">Minimum credit amount<input v-model.number="program.MinimumCreditAmount" type="number" min="0" step="0.01" required class="field-control" /><small>Rewards accumulate and are credited once they reach this amount. Provider minimum is 0.01.</small></label>
                    <label v-if="voucherMode" class="referral-field">Voucher claim period (days)<input v-model.number="program.VoucherClaimDays" type="number" min="1" max="365" required class="field-control" /></label>
                  </div>
                </section>
              </template>
              <template v-else>
                <section class="panel p-5 sm:p-6">
                  <h2 class="panel-heading">Review</h2><p class="mt-1 text-sm text-slate-500">The offer as an inviter reads it, generated from the values above.</p>
                  <p class="mt-4 rounded-2xl bg-slate-950 p-5 text-lg font-semibold leading-7 text-white">{{ sentence }}</p>
                  <div v-if="errors.length" role="alert" class="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900"><p class="font-semibold">{{ errors.length }} {{ errors.length === 1 ? 'issue blocks' : 'issues block' }} saving and publishing.</p><ul class="mt-2 list-inside list-disc"><li v-for="validation in errors" :key="validation">{{ validation }} <button type="button" class="underline" @click="step = stepForError(validation)">Fix</button></li></ul></div>
                  <p v-else class="mt-4 text-sm text-emerald-800">Draft values validate locally. Server review and publication also check current policy and funding.</p>
                </section>
                <section class="panel p-5 sm:p-6">
                  <h2 class="panel-heading">{{ creating ? 'Create program' : 'Apply immediately (legacy save)' }}</h2>
                  <p class="mt-1 text-sm text-slate-500">{{ creating ? 'Creates the program with the values above. Versioned publishing becomes available once it exists.' : 'Updates the live program at once; relationships follow the current event-time rules. Already accrued rewards never change.' }}</p>
                  <div v-if="!creating" class="mt-4"><label class="check-row"><input v-model="publishNewTermsVersion" type="checkbox" /><span>Publish new terms version on save<small>Members must accept again before sharing.</small></span></label></div>
                  <div class="mt-4 flex flex-wrap items-center gap-4">
                    <button v-if="!versioned" class="primary-button" type="submit" :disabled="!dirty || errors.length > 0 || busy">{{ saving ? 'Saving…' : creating ? 'Create program' : 'Save program' }}</button>
                    <p v-else class="text-sm text-amber-900">This program already carries versioned offers, so immediate saves are disabled. Publish changes through the review below.</p>
                    <span class="text-sm text-slate-500">{{ dirty ? 'Unsaved changes' : 'All changes saved' }} · revision {{ program.Revision }}</span>
                  </div>
                </section>
                <p v-if="build.state === 'unavailable'" role="status" class="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">Versioned publishing is unavailable on this platform. Drafts, change previews, scheduled versions and subpartner links need a platform with the referral build endpoints; the immediate save above keeps working.</p>
                <div v-else-if="build.state === 'error'" role="alert" class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800"><span>Could not check versioned publishing. {{ build.error }}</span><button type="button" class="secondary-button" @click="loadBuild">Retry</button></div>
                <p v-else-if="build.state === 'loading'" role="status" class="text-sm text-slate-500">Checking versioned publishing…</p>
                <ReferralOfferWorkbench v-if="program.Id && !creating && build.state === 'ready'" :key="program.Id" :program="program" :current="overview?.Program ?? null" :valid="errors.length === 0" :available="buildAvailable" :capabilities="build.capabilities" @published="load(program.Id)" @restore="program = $event" @conflict="showConflict" />
                <p v-else-if="creating" class="text-sm text-slate-500">Create the program first; versioned publishing and the version history appear afterwards.</p>
              </template>
              <div class="flex flex-wrap items-center justify-between gap-3">
                <button type="button" class="secondary-button" :disabled="stepIndex === 0" @click="goStep(-1)">Back</button>
                <span class="text-xs text-slate-500">Step {{ stepIndex + 1 }} of {{ BUILDER_STEPS.length }} · {{ BUILDER_STEPS[stepIndex]?.label }}</span>
                <button v-if="step !== 'review'" type="button" class="primary-button" @click="goStep(1)">Next: {{ BUILDER_STEPS[stepIndex + 1]?.label }}</button>
                <span v-else />
              </div>
            </form>
          </div>
          <aside class="min-w-0 space-y-4 self-start xl:sticky xl:top-6" aria-label="Offer summary">
            <section class="panel p-5">
              <p class="text-xs uppercase tracking-wide text-slate-500">Offer summary</p>
              <p class="mt-2 text-sm font-semibold leading-6">{{ sentence }}</p>
              <dl class="mt-4 space-y-2.5 text-sm">
                <div v-for="row in summaryRows" :key="row.label"><dt class="text-xs text-slate-500">{{ row.label }}</dt><dd class="font-medium">{{ row.value }}</dd></div>
              </dl>
              <div class="mt-4 flex flex-wrap gap-2"><StatusPill :label="program.Status" :tone="statusTone(program.Status)" /><span class="status-pill status-pill--neutral">{{ program.Visibility === 'PRIVATE' ? 'Invite only' : 'Public' }}</span><span v-if="program.Exists" class="status-pill status-pill--neutral">Terms v{{ program.TermsVersion }}</span><span v-if="versioned" class="status-pill status-pill--success">Versioned</span></div>
              <p class="mt-3 text-xs text-slate-500">{{ dirty ? 'Unsaved changes in the builder.' : 'All changes saved.' }}</p>
              <p v-if="errors.length" class="mt-2 text-xs text-amber-900">{{ errors.length }} {{ errors.length === 1 ? 'issue' : 'issues' }} · <button type="button" class="underline" @click="step = firstIssueStep">go to the first</button></p>
              <button v-if="step !== 'review'" type="button" class="secondary-button mt-4 w-full" @click="step = 'review'">Go to review</button>
            </section>
          </aside>
        </div>
        </template>

        <template v-else-if="tab === 'partners'">
        <section v-if="program.Visibility === 'PRIVATE'" class="panel p-5 sm:p-6">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div><h2 class="panel-heading">Partners</h2><p class="mt-2 text-sm text-slate-500">Membership, level assignment, agreements and activity. Only approved partners can share this program; new partners start as pending. Revocation stops new referrals while existing relationships keep their earning window. Partners never receive admin permissions.</p></div>
            <button v-if="program.Exists && !creating" type="button" class="secondary-button" :disabled="archived" @click="addingPartner = !addingPartner; if (!addingPartner) partner = emptyPartner()">{{ addingPartner ? 'Close form' : 'Add partner' }}</button>
          </div>
          <p v-if="!program.Exists || creating" class="mt-4">Save this program before adding partners.</p>
          <template v-else>
            <form v-if="addingPartner" class="mt-5 grid gap-4 rounded-xl border border-slate-200 bg-slate-50 p-4 sm:grid-cols-2 xl:grid-cols-4" @submit.prevent="savePartner">
              <label class="referral-field">Partner user<UserPicker :model-value="partner.userId" :selected-label="partnerLabel" required @update:model-value="editPartner($event)" @select="rememberUser" /></label>
              <label class="referral-field">Agreement reference<input v-model="partner.agreementReference" maxlength="200" class="field-control" /><small>Terms reference for this partner.</small></label>
              <label class="referral-field">Effective from<input v-model="partner.effectiveFrom" type="date" class="field-control" /></label>
              <label class="referral-field">Effective until<input v-model="partner.effectiveUntil" type="date" class="field-control" /></label>
              <label class="referral-field">Campaign owner<select v-model="partner.campaignOwnerUserId" class="field-control"><option :value="null">Not set</option><option v-for="user in users" :key="user.Id" :value="user.Id">{{ user.Name }}</option></select></label>
              <label class="referral-field">Channels<input v-model="partner.channels" class="field-control" /><small>Comma-separated, e.g. youtube, newsletter.</small></label>
              <label class="referral-field">Funding allocation<input v-model="partner.fundingAllocation" type="number" min="0" step="0.01" class="field-control" /></label>
              <label class="referral-field">Membership expires (optional)<input v-model="partner.expiresAt" type="datetime-local" class="field-control" /></label>
              <label class="referral-field sm:col-span-2">Notes<input v-model="partner.notes" maxlength="2000" class="field-control" /></label>
              <div class="flex flex-wrap items-end gap-3 sm:col-span-2"><label class="check-row"><input v-model="partner.approve" type="checkbox" /><span>Approve immediately</span></label><button class="primary-button" :disabled="!partner.userId || archived">Save partner</button></div>
            </form>
            <div class="mt-5 flex flex-wrap items-end gap-3">
              <label class="referral-field flex-1">Filter partners<input v-model="partnerQuery" type="search" placeholder="Name, email, #id, status or agreement reference" class="field-control" /></label>
              <p class="text-xs text-slate-500 sm:max-w-sm">Filters the {{ members.length }} loaded {{ members.length === 1 ? 'partner' : 'partners' }} on this browser. To add someone who is not listed, pick them in the partner form below; it searches the whole platform.</p>
            </div>
            <p v-if="sectionErrors.members" role="alert" class="mt-4 text-sm text-red-700">Could not load the partner register. {{ sectionErrors.members }}</p>
            <div class="mt-5 overflow-x-auto"><table class="data-table min-w-[1100px]"><thead><tr><th>Partner</th><th>Status</th><th>Level</th><th>Effective</th><th>Qualified</th><th>Pending / paid</th><th></th></tr></thead><tbody>
              <tr v-for="m in filteredMembers" :key="m.UserId" :class="detailMember?.UserId === m.UserId ? 'bg-blue-50/60' : ''">
                <td>{{ m.Name }}<div class="text-xs text-slate-500">{{ m.Email }} · #{{ m.UserId }}</div></td>
                <td><StatusPill :label="m.Status === 'ACTIVE' && m.ExpiresAt && Date.parse(m.ExpiresAt) <= Date.now() ? 'EXPIRED' : m.Status" :tone="statusTone(m.Status)" /><div v-if="m.ApprovedAt" class="mt-1 text-xs text-slate-500">approved {{ day(m.ApprovedAt) }}</div></td>
                <td>{{ partnerLevel(m).label }}<div class="text-xs text-slate-500">{{ partnerLevel(m).note }}</div></td>
                <td class="text-xs">{{ day(m.EffectiveFrom) }} → {{ day(m.EffectiveUntil, 'open') }}<div v-if="m.ExpiresAt">membership until {{ day(m.ExpiresAt) }}</div></td>
                <td><template v-if="partnerActivity(m.UserId)">{{ partnerActivity(m.UserId)!.Qualified }}<div class="text-xs text-slate-500">of {{ partnerActivity(m.UserId)!.Attributed }} attributed</div></template><span v-else-if="activityState(m.UserId) === 'error'" class="text-xs text-red-700" :title="(reports[m.UserId] as { error: string }).error">unavailable</span><span v-else class="text-xs text-slate-500">…</span></td>
                <td><template v-if="partnerActivity(m.UserId)">{{ money(partnerActivity(m.UserId)!.RewardsPending, partnerActivity(m.UserId)!.Currency) }}<div class="text-xs text-slate-500">paid {{ money(partnerActivity(m.UserId)!.RewardsPaid, partnerActivity(m.UserId)!.Currency) }}</div></template><span v-else-if="activityState(m.UserId) === 'error'" class="text-xs text-red-700">unavailable</span><span v-else class="text-xs text-slate-500">…</span></td>
                <td><div class="flex flex-wrap justify-end gap-2"><button type="button" class="secondary-button" @click="openPartner(m)">Details</button><button v-if="m.Status === 'PENDING'" type="button" class="primary-button" :disabled="archived" @click="approvePartner(m)">Approve</button><button type="button" class="secondary-button" :disabled="archived || m.Status === 'REVOKED'" @click="revokePartner(m)">Revoke</button></div></td></tr>
              <tr v-if="!filteredMembers.length"><td colspan="7">{{ members.length ? 'No loaded partner matches this filter.' : 'No partners yet. Add the first partner above.' }}</td></tr></tbody></table></div>
            <div v-if="detailMember" class="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-4" aria-label="Partner detail">
              <div class="flex flex-wrap items-start justify-between gap-3"><div><h3 class="font-semibold">{{ detailMember.Name }}</h3><p class="text-xs text-slate-500">{{ detailMember.Email }} · #{{ detailMember.UserId }} · friends are pseudonymised.</p></div><div class="flex gap-2"><button type="button" class="secondary-button" @click="editPartner(detailMember.UserId)">Edit membership</button><button type="button" class="secondary-button" @click="detailMember = null">Close</button></div></div>
              <div class="mt-4 grid gap-4 lg:grid-cols-2">
                <section class="rounded-xl border border-slate-200 bg-white p-4">
                  <h4 class="text-sm font-semibold">Membership</h4>
                  <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5 text-sm">
                    <dt class="text-slate-500">Status</dt><dd><StatusPill :label="detailMember.Status" :tone="statusTone(detailMember.Status)" /></dd>
                    <dt class="text-slate-500">Assigned</dt><dd>{{ date(detailMember.AssignedAt) }}</dd>
                    <dt class="text-slate-500">Approved</dt><dd>{{ detailMember.ApprovedAt ? `${date(detailMember.ApprovedAt)} by ${userLabel(detailMember.ApprovedByUserId)}` : 'Not approved yet' }}</dd>
                    <dt class="text-slate-500">Effective</dt><dd>{{ day(detailMember.EffectiveFrom) }} → {{ day(detailMember.EffectiveUntil, 'open') }}</dd>
                    <dt class="text-slate-500">Membership expires</dt><dd>{{ date(detailMember.ExpiresAt, 'No expiry') }}</dd>
                    <dt class="text-slate-500">Campaign owner</dt><dd>{{ userLabel(detailMember.CampaignOwnerUserId) }}</dd>
                    <dt class="text-slate-500">Channels</dt><dd>{{ detailMember.Channels?.length ? detailMember.Channels.join(', ') : '—' }}</dd>
                    <dt class="text-slate-500">Funding allocation</dt><dd>{{ detailMember.FundingAllocation != null ? money(detailMember.FundingAllocation, program.PayoutCurrency) : 'Not set' }}</dd>
                    <dt class="text-slate-500">Notes</dt><dd>{{ detailMember.Notes || '—' }}</dd>
                  </dl>
                  <h4 class="mt-4 text-sm font-semibold">Terms reference</h4>
                  <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5 text-sm">
                    <dt class="text-slate-500">Agreement</dt><dd>{{ detailMember.AgreementReference || 'No agreement reference recorded' }}</dd>
                    <dt class="text-slate-500">Program terms</dt><dd>Version {{ program.TermsVersion }}{{ program.PublishedAt ? ` · published ${day(program.PublishedAt)}` : '' }}</dd>
                  </dl>
                </section>
                <section class="rounded-xl border border-slate-200 bg-white p-4">
                  <h4 class="text-sm font-semibold">Level override</h4>
                  <p v-if="activeAssignment(detailMember.UserId)" class="mt-2 text-sm">{{ activeAssignment(detailMember.UserId)!.LevelName }} <span class="font-mono text-xs text-slate-500">{{ activeAssignment(detailMember.UserId)!.LevelCode }}</span> · assigned {{ day(activeAssignment(detailMember.UserId)!.AssignedAt) }} · {{ activeAssignment(detailMember.UserId)!.ExpiresAt ? `expires ${date(activeAssignment(detailMember.UserId)!.ExpiresAt)}` : 'no expiry' }}<button type="button" class="secondary-button ml-3" :disabled="archived" @click="revokeAssignment(activeAssignment(detailMember.UserId)!)">Revoke</button></p>
                  <p v-else class="mt-2 text-sm text-slate-500">No override: the metric-based ladder applies.</p>
                  <form class="mt-3 grid gap-3 sm:grid-cols-2" @submit.prevent="saveAssignment">
                    <label class="referral-field">Level<select v-model="assignment.levelId" class="field-control" required><option value="" disabled>Select level</option><option v-for="level in program.Levels.filter(l => l.Id)" :key="level.Id" :value="level.Id">{{ level.Name }}{{ level.Hidden ? ' · hidden' : '' }}</option></select></label>
                    <label class="referral-field">Expires (optional)<input v-model="assignment.expiresAt" type="datetime-local" class="field-control" /></label>
                    <label class="referral-field sm:col-span-2">Notes<input v-model="assignment.notes" maxlength="2000" class="field-control" /></label>
                    <div class="sm:col-span-2"><button class="primary-button" :disabled="!assignment.levelId || archived || dirty">Assign level</button><span v-if="dirty" class="ml-3 text-xs text-amber-700">Save the program first so new levels can be assigned.</span></div>
                  </form>
                  <h4 class="mt-5 text-sm font-semibold">Subpartner link</h4>
                  <p v-if="build.state !== 'ready'" class="mt-2 text-sm text-slate-500">{{ build.state === 'unavailable' ? 'Not available on this platform.' : build.state === 'error' ? 'Could not check the platform capabilities.' : 'Checking…' }}</p>
                  <template v-else>
                    <p v-if="sectionErrors.team" role="alert" class="mt-2 text-sm text-red-700">Could not load subpartner links. {{ sectionErrors.team }}</p>
                    <p class="mt-2 text-sm">Parent partner: <span class="font-medium">{{ parentByChild[detailMember.UserId] ? memberName(parentByChild[detailMember.UserId]) : 'none (direct partner)' }}</span></p>
                    <p v-if="childrenOf(detailMember.UserId).length" class="mt-1 text-sm">Subpartners: {{ childrenOf(detailMember.UserId).map(memberName).join(', ') }}</p>
                    <p v-if="!build.capabilities?.SubpartnersEnabled" class="mt-2 text-sm text-amber-800">Subpartner assignments are disabled on this platform.</p>
                    <form v-else class="mt-3 flex flex-wrap items-end gap-3" @submit.prevent="assignParent(detailMember!.UserId)">
                      <label class="referral-field flex-1">Assign parent partner<select v-model="parentChoice" class="field-control"><option :value="null" disabled>Select an active partner</option><option v-for="m in activeMembers.filter(x => x.UserId !== detailMember!.UserId)" :key="m.UserId" :value="m.UserId">{{ m.Name }} · #{{ m.UserId }}</option></select></label>
                      <button class="secondary-button" :disabled="!parentChoice || archived">Assign parent</button>
                    </form>
                    <p class="mt-2 text-xs text-slate-500">One parent per subpartner, one generation only. Applies to future attributions; accepted routes keep their original recipients.</p>
                  </template>
                </section>
              </div>
              <section class="mt-4 rounded-xl border border-slate-200 bg-white p-4">
                <h4 class="text-sm font-semibold">Activity</h4>
                <p v-if="activityState(detailMember.UserId) === 'error'" role="alert" class="mt-2 text-sm text-red-700">Could not load the report. {{ (reports[detailMember.UserId] as { error: string }).error }} <button type="button" class="underline" @click="loadPartnerActivity([detailMember!])">Retry</button></p>
                <p v-else-if="!partnerActivity(detailMember.UserId)" class="mt-2 text-sm text-slate-500">Loading report…</p>
                <template v-else>
                  <div class="mt-3 grid gap-3 sm:grid-cols-3">
                    <div v-for="tile in [['Attributed', partnerActivity(detailMember.UserId)!.Attributed], ['Qualified', partnerActivity(detailMember.UserId)!.Qualified], ['Earning now', partnerActivity(detailMember.UserId)!.Earning], ['Eligible volume', money(partnerActivity(detailMember.UserId)!.EligibleVolume, partnerActivity(detailMember.UserId)!.Currency)], ['Rewards pending', money(partnerActivity(detailMember.UserId)!.RewardsPending, partnerActivity(detailMember.UserId)!.Currency)], ['Rewards paid', money(partnerActivity(detailMember.UserId)!.RewardsPaid, partnerActivity(detailMember.UserId)!.Currency)]]" :key="String(tile[0])" class="rounded-xl border border-slate-200 p-3"><p class="text-xs text-slate-500">{{ tile[0] }}</p><p class="mt-1 font-semibold">{{ tile[1] }}</p></div>
                  </div>
                  <div class="mt-4 overflow-x-auto"><table class="data-table"><thead><tr><th>Friend</th><th>Stage</th><th>Joined</th><th>Earning until</th><th>Earned</th></tr></thead><tbody>
                    <tr v-for="friend in partnerActivity(detailMember.UserId)!.Friends" :key="friend.Id"><td>{{ friend.RecipientName ? `${friend.RecipientName} · ` : '' }}{{ friend.Alias }}</td><td><StatusPill :label="friendStageLabel(friend.Stage)" :tone="statusTone(friend.Stage)" /></td><td>{{ day(friend.AttributedAt) }}</td><td>{{ day(friend.EarningUntil) }}</td><td class="font-semibold">{{ money(friend.EarnedAmount, friend.Currency) }}</td></tr>
                    <tr v-if="!partnerActivity(detailMember.UserId)!.Friends.length"><td colspan="5">No referrals yet.</td></tr></tbody></table></div>
                </template>
              </section>
            </div>
          </template>
        </section>
        <section v-if="program.Exists && !creating" class="panel p-5 sm:p-6">
          <h2 class="panel-heading">Level assignments</h2><p class="mt-2 text-sm text-slate-500">Give one user a specific level, usually a hidden creator rate inside the public program. An active assignment overrides the metric-based level until it expires or is revoked.</p>
          <form v-if="program.Visibility !== 'PRIVATE'" class="mt-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-[1.4fr_1fr_1fr_1.2fr_auto] xl:items-end" @submit.prevent="saveAssignment">
            <label class="referral-field">User<UserPicker v-model="assignment.userId" required @select="rememberUser" /></label>
            <label class="referral-field">Level<select v-model="assignment.levelId" class="field-control" required><option value="" disabled>Select level</option><option v-for="level in program.Levels.filter(l => l.Id)" :key="level.Id" :value="level.Id">{{ level.Name }}{{ level.Hidden ? ' · hidden' : '' }}</option></select></label>
            <label class="referral-field">Expires (optional)<input v-model="assignment.expiresAt" type="datetime-local" class="field-control" /></label>
            <label class="referral-field">Notes<input v-model="assignment.notes" maxlength="2000" class="field-control" /></label>
            <button class="primary-button" :disabled="!assignment.userId || !assignment.levelId || archived">Assign</button>
          </form>
          <p v-else class="mt-3 text-sm text-slate-500">Assign a partner's level from their detail panel above.</p>
          <p v-if="dirty" class="mt-3 text-sm text-amber-700">Save the program first so new levels can be assigned.</p>
          <p v-if="sectionErrors.assignments" role="alert" class="mt-4 text-sm text-red-700">Could not load level assignments. {{ sectionErrors.assignments }}</p>
          <div class="mt-5 overflow-x-auto"><table class="data-table"><thead><tr><th>User</th><th>Level</th><th>Assigned</th><th>Expires</th><th>Notes</th><th></th></tr></thead><tbody>
            <tr v-for="a in assignments" :key="a.UserId"><td>{{ a.Name }}<div class="text-xs">{{ a.Email }}</div></td><td>{{ a.LevelName }} <span class="font-mono text-xs text-slate-500">{{ a.LevelCode }}</span></td><td>{{ day(a.AssignedAt) }}<div v-if="a.RevokedAt" class="text-xs text-red-700">revoked {{ day(a.RevokedAt) }}</div></td><td>{{ date(a.ExpiresAt, 'No expiry') }}</td><td class="text-xs">{{ a.Notes || '—' }}</td><td class="text-right"><button v-if="!a.RevokedAt" class="secondary-button" :disabled="archived" @click="revokeAssignment(a)">Revoke</button></td></tr>
            <tr v-if="!assignments.length"><td colspan="6">No level assignments.</td></tr></tbody></table></div>
        </section>
        <section class="panel p-5 sm:p-6">
          <h2 class="panel-heading">Referral offers by inviter</h2><p class="mt-2 text-sm text-slate-500">Choose an inviter, the tier for new referred users and an existing discount code. Future referrals snapshot the offer; discount codes remain centrally managed.</p>
          <p v-if="!program.Exists || creating" class="mt-4">Save this program before configuring inviter offers.</p>
          <template v-else>
            <form class="mt-5 space-y-4" @submit.prevent="saveOffer">
              <div class="grid gap-4 sm:grid-cols-3"><label class="referral-field">Referring user<UserPicker v-model="offer.OwnerUserId" :options="program.Visibility === 'PRIVATE' ? eligibleUsers : null" required @select="rememberUser" /></label>
                <label class="referral-field">Tier for referred users<select v-model="offer.ReferredTierId" class="field-control"><option :value="null">No automatic tier</option><option v-if="offer.ReferredTierId && !options?.Tiers.some(t => t.Id === offer.ReferredTierId)" :value="offer.ReferredTierId">Current tier (unavailable)</option><option v-for="tier in options?.Tiers" :key="tier.Id" :value="tier.Id">{{ tier.Name }}</option></select></label>
                <label class="referral-field">Automatic discount<select v-model="offer.DiscountCodeId" class="field-control"><option :value="null">No discount</option><option v-if="offer.DiscountCodeId && !options?.DiscountCodes.some(c => c.Id === offer.DiscountCodeId)" :value="offer.DiscountCodeId">Current discount (unavailable)</option><option v-for="code in options?.DiscountCodes" :key="code.Id" :value="code.Id">{{ code.Code }} · {{ code.Description }}</option></select></label></div>
              <p v-if="selectedDiscount" class="rounded-lg bg-slate-50 p-3 text-sm text-slate-600">{{ discountDescription(selectedDiscount) }}</p>
              <label v-if="program.Visibility === 'PUBLIC'" class="flex items-center gap-2 text-sm"><input v-model="offer.InheritBenefits" type="checkbox" />Inherit for next generation</label>
              <p v-if="program.Visibility === 'PUBLIC'" class="text-sm text-slate-500">When enabled, referred users receive this tier and discount on their own invites, passing the same offer to their referrals.</p>
              <button class="primary-button" :disabled="!offer.OwnerUserId || !eligibleUsers.some(u => u.Id === offer.OwnerUserId)">Save offer</button>
            </form>
            <div class="mt-5 overflow-x-auto"><table class="data-table"><thead><tr><th>Inviter</th><th>Code</th><th>Assigned tier</th><th>Discount</th><th>Inherited</th><th>Updated</th><th></th></tr></thead><tbody><tr v-for="row in offers" :key="row.OwnerUserId"><td>{{ row.OwnerName }}<div class="text-xs">{{ row.OwnerEmail }}</div></td><td>{{ row.ReferralCode }}</td><td>{{ row.ReferredTierName || '—' }}</td><td>{{ row.DiscountCode || '—' }}<div class="text-xs">{{ row.DiscountDescription }}</div></td><td>{{ row.InheritBenefits ? 'Yes' : 'No' }}</td><td>{{ date(row.UpdatedAt) }}</td><td><button class="secondary-button" @click="editOffer(row)">Edit offer</button></td></tr><tr v-if="!offers.length"><td colspan="7">No inviter offers yet.</td></tr></tbody></table></div>
          </template>
        </section>
        </template>

        <section v-else-if="tab === 'links'" class="panel p-5 sm:p-6">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div><h2 class="panel-heading">Campaign links</h2><p class="mt-2 text-sm text-slate-500">Every member's tracking links for this program: who owns each, where it is shared and what it brought in. A link carries no rate and cannot change one. Pausing stops new attribution and leaves existing relationships untouched; archiving is permanent.</p></div>
            <button type="button" class="secondary-button" :disabled="linksLoading" @click="loadLinks">{{ linksLoading ? 'Loading…' : 'Refresh links' }}</button>
          </div>
          <div v-if="links.length" class="mt-4 grid gap-3 sm:grid-cols-4">
            <div class="metric-card"><div class="text-sm text-slate-500">Active links</div><div class="mt-2 text-xl font-bold">{{ linkCounts.active }} <span class="text-sm font-normal text-slate-500">of {{ links.length }}</span></div></div>
            <div class="metric-card"><div class="text-sm text-slate-500">Clicks through links</div><div class="mt-2 text-xl font-bold">{{ linkCounts.tracked ? linkCounts.clicks : '—' }}</div></div>
            <div class="metric-card"><div class="text-sm text-slate-500">Sign-ups through links</div><div class="mt-2 text-xl font-bold">{{ linkCounts.signups }}</div></div>
            <div class="metric-card"><div class="text-sm text-slate-500">Qualified through links</div><div class="mt-2 text-xl font-bold">{{ linkCounts.qualified }}</div></div>
          </div>
          <div class="mt-4 flex flex-wrap items-end gap-3">
            <label class="referral-field">Status<select v-model="linkFilters.status" class="field-control"><option value="">All</option><option v-for="s in CAMPAIGN_LINK_STATUSES" :key="s" :value="s">{{ statusLabel(s) }}</option></select></label>
            <label class="referral-field flex-1">Owner or campaign<input v-model="linkFilters.query" type="search" placeholder="Owner name, email, #id, campaign name or code" class="field-control" /></label>
            <p class="text-xs text-slate-500 sm:max-w-sm">Filters the {{ links.length }} loaded {{ links.length === 1 ? 'link' : 'links' }} on this browser. Expiry is applied as it stands now.</p>
          </div>
          <p v-if="sectionErrors.links" role="alert" class="mt-4 text-sm text-red-700">Could not load campaign links. {{ sectionErrors.links }}</p>
          <div class="mt-5 overflow-x-auto"><table class="data-table min-w-[1280px]"><thead><tr><th>Campaign</th><th>Owner</th><th>Programme</th><th>Channel</th><th>Status</th><th>Clicks</th><th>Sign-ups</th><th>Qualified</th><th>Created</th><th>Expires</th><th></th></tr></thead><tbody>
            <tr v-for="row in filteredLinks" :key="row.Id" class="cursor-pointer" @click="linkRow = row">
              <td>{{ row.Name }}<div class="font-mono text-xs text-slate-500">{{ row.Code }}</div></td>
              <td class="text-xs">{{ ownerLabel(row) }}<div v-if="row.OwnerUserId" class="text-slate-500">#{{ row.OwnerUserId }}</div></td>
              <td class="text-xs">{{ row.ProgramName || '—' }}</td>
              <td>{{ channelLabel(row.Channel) }}<div class="text-xs text-slate-500">{{ row.Locale }}</div></td>
              <td><StatusPill :label="effectiveLinkStatus(row)" :tone="linkStatusTone(effectiveLinkStatus(row))" /></td>
              <td class="font-semibold">{{ clicksTracked(row) ? row.ClickCount ?? 0 : '—' }}<div v-if="clicksTracked(row)" class="text-xs font-normal text-slate-500">{{ row.UniqueClickCount ?? 0 }} unique</div></td>
              <td class="font-semibold">{{ row.SignupCount }}</td><td class="font-semibold">{{ row.QualifiedCount }}</td>
              <td class="text-xs">{{ day(row.CreatedAt) }}</td><td class="text-xs">{{ row.ExpiresAt ? day(row.ExpiresAt) : '—' }}</td>
              <td class="text-right"><div class="flex justify-end gap-2">
                <button v-if="linkActions(row).pause" type="button" class="secondary-button" @click.stop="setLinkStatus(row, 'PAUSED')">Pause</button>
                <button v-if="linkActions(row).resume" type="button" class="secondary-button" @click.stop="setLinkStatus(row, 'ACTIVE')">Resume</button>
                <button v-if="linkActions(row).archive" type="button" class="secondary-button" @click.stop="setLinkStatus(row, 'ARCHIVED')">Archive</button>
                <button type="button" class="secondary-button" @click.stop="linkRow = row">Details</button>
              </div></td></tr>
            <tr v-if="!filteredLinks.length"><td colspan="11">{{ sectionErrors.links ? 'Links unavailable.' : linksLoading ? 'Loading links…' : links.length ? 'No loaded link matches this filter.' : 'No campaign links yet. Members create them from their own referral workspace.' }}</td></tr></tbody></table></div>
          <ReferralLinkDrawer v-if="linkRow" :link="linkRow" :busy="busy" @close="linkRow = null" @pause="setLinkStatus(linkRow, 'PAUSED')" @resume="setLinkStatus(linkRow, 'ACTIVE')" @archive="setLinkStatus(linkRow, 'ARCHIVED')" />
        </section>

        <section v-else-if="tab === 'ledger'" class="panel p-5 sm:p-6">
          <h2 class="panel-heading">Reward ledger</h2><p class="mt-2 text-sm text-slate-500">Every welcome, qualification, top-up and adjustment row for this program. Beneficiary is who is paid; subject is the referred user the event belongs to. Open a row to see how the amount was calculated.</p>
          <form class="mt-4 flex flex-wrap items-end gap-3" @submit.prevent="ledgerPage = 1; loadLedger()">
            <label class="referral-field">Status<select v-model="ledgerFilters.status" class="field-control"><option value="">All</option><option v-for="s in REWARD_STATUSES" :key="s" :value="s">{{ statusLabel(s) }}</option></select></label>
            <label class="referral-field">Beneficiary<select v-model="ledgerFilters.beneficiaryRole" class="field-control"><option value="">All</option><option value="REFERRER">Inviter</option><option value="REFERRED">Friend</option><option value="COMMUNITY">Community partner</option></select></label>
            <label class="referral-field">Type<select v-model="ledgerFilters.eventType" class="field-control"><option value="">All</option><option v-for="t in REWARD_EVENT_TYPES" :key="t" :value="t">{{ rewardEventLabel(t) }}</option></select></label>
            <button class="secondary-button">Apply filters</button>
            <span class="text-xs text-slate-500">Program scope: {{ program.Name }}. Rewards have no date filter on this platform.</span>
          </form>
          <p v-if="sectionErrors.ledger" role="alert" class="mt-4 text-sm text-red-700">Could not load the ledger. {{ sectionErrors.ledger }}</p>
          <div class="mt-5 overflow-x-auto"><table class="data-table min-w-[1000px]"><thead><tr><th>When</th><th>Type</th><th>Beneficiary</th><th>Subject</th><th>Level</th><th>Amount</th><th>Status</th><th>Delivery</th><th></th></tr></thead><tbody>
            <tr v-for="row in ledger" :key="row.Reward.Id" class="cursor-pointer" @click="rewardRow = row"><td class="text-xs">{{ date(row.Reward.OccurredAt) }}</td>
              <td>{{ rewardEventLabel(row.Reward.EventType) }}<div class="text-xs text-slate-500">{{ row.Reward.BeneficiaryRole === 'REFERRED' ? 'friend' : row.Reward.BeneficiaryRole === 'SUBPARTNER' ? 'subpartner' : row.Reward.BeneficiaryRole === 'COMMUNITY' ? 'community partner' : 'inviter' }}{{ row.Reward.BasisAmount > 0 ? ` · on ${money(row.Reward.BasisAmount, row.Reward.BasisCurrency)}` : '' }}</div></td>
              <td class="text-xs">{{ row.BeneficiaryEmail }}<div class="text-slate-500">#{{ row.BeneficiaryUserId }}</div></td>
              <td class="text-xs">{{ row.SubjectEmail }}<div class="text-slate-500">#{{ row.SubjectUserId }}{{ row.Reward.FriendAlias ? ` · ${row.Reward.FriendAlias}` : '' }}</div></td>
              <td class="font-mono text-xs">{{ row.Reward.LevelCode }}</td><td class="font-semibold" :class="row.Reward.Amount < 0 ? 'text-red-700' : ''">{{ money(row.Reward.Amount, row.Reward.Currency) }}</td>
              <td><StatusPill :label="row.Reward.Status" :tone="statusTone(row.Reward.Status)" /></td><td class="font-mono text-xs">{{ row.Reward.CreditId || row.Reward.VoucherId || '—' }}</td>
              <td class="text-right"><button type="button" class="secondary-button" @click.stop="rewardRow = row">Explain</button></td></tr>
            <tr v-if="!ledger.length"><td colspan="9">{{ sectionErrors.ledger ? 'Ledger unavailable.' : ledgerPage > 1 ? 'No more rewards.' : 'No rewards match these filters.' }}</td></tr></tbody></table></div>
          <div class="mt-4 flex flex-wrap items-center justify-between gap-3 text-sm text-slate-500"><span>Page {{ ledgerPage }} · {{ PAGE_SIZE }} rows per page</span><div class="flex gap-2"><button type="button" class="secondary-button" :disabled="ledgerPage === 1" @click="pageLedger(-1)">Previous</button><button type="button" class="secondary-button" :disabled="ledger.length < PAGE_SIZE" @click="pageLedger(1)">Next</button></div></div>
          <ReferralRewardDrawer v-if="rewardRow" :row="rewardRow" :credit="rewardCredit" :credits-loaded="!sectionErrors.credits" @close="rewardRow = null" />
        </section>

        <template v-else-if="tab === 'credits'">
          <section class="panel p-5 sm:p-6">
            <h2 class="panel-heading">Reconciliation</h2>
            <p v-if="sectionErrors.reconciliation" role="alert" class="mt-3 text-sm text-red-700">Could not load the reconciliation summary. {{ sectionErrors.reconciliation }}</p>
            <template v-else-if="reconciliation">
              <p class="mt-2 text-sm text-slate-500">Generated {{ date(reconciliation.GeneratedAt) }}. Stale credits have been transferring or confirming for more than 30 minutes.</p>
              <div class="mt-4 grid gap-3 sm:grid-cols-3 xl:grid-cols-5">
                <div v-for="tile in [['Rewards ready', reconciliation.RewardsReady], ['Rewards crediting', reconciliation.RewardsCrediting], ['Rewards failed', reconciliation.RewardsFailed], ['Credits pending', reconciliation.CreditsPending], ['Credits transferring', reconciliation.CreditsTransferring], ['Credits confirming', reconciliation.CreditsConfirming], ['Credits failed', reconciliation.CreditsFailed], ['Credits stale', reconciliation.CreditsStale], ['Reserved exposure', `${money(reconciliation.ReservedExposure, reconciliation.Currency)}${reconciliation.ExposureLimit != null ? ` of ${money(reconciliation.ExposureLimit, reconciliation.Currency)}` : ''}`]]" :key="String(tile[0])" class="rounded-xl border p-4" :class="['Credits stale', 'Credits failed', 'Rewards failed'].includes(String(tile[0])) && Number(tile[1]) > 0 ? 'border-red-200 bg-red-50' : 'border-slate-200'"><p class="text-xs text-slate-500">{{ tile[0] }}</p><p class="mt-1 text-lg font-semibold">{{ tile[1] }}</p></div>
              </div>
            </template>
            <p v-else class="mt-3 text-sm text-slate-500">No reconciliation summary yet.</p>
          </section>
          <section class="panel p-5 sm:p-6">
            <div class="flex flex-wrap items-end justify-between gap-3"><div><h2 class="panel-heading">Wallet credits</h2><p class="mt-2 text-sm text-slate-500">One credit moves one or more Ready rewards to the user's USD balance. Retry re-sends a failed credit after checking the provider for the same reference; cancel is only possible before the provider accepted a transfer and needs a reason. Transferring and confirming are not payments yet.</p></div>
              <label class="referral-field">Status<select v-model="creditStatus" class="field-control" @change="creditPage = 1; loadCredits()"><option value="">All</option><option v-for="s in CREDIT_STATUSES" :key="s" :value="s">{{ statusLabel(s) }}</option></select></label></div>
            <p v-if="sectionErrors.credits" role="alert" class="mt-4 text-sm text-red-700">Could not load credits. {{ sectionErrors.credits }}</p>
            <div v-if="cancelTarget" class="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4">
              <p class="text-sm font-semibold text-amber-900">Cancel credit {{ money(cancelTarget.Amount, cancelTarget.Currency) }} for {{ cancelTarget.UserEmail }}</p><p class="mt-1 text-sm text-amber-800">The rewards go back to Ready and are credited again later. The platform refuses the cancellation if the provider already accepted the transfer.</p>
              <form class="mt-3 flex flex-wrap items-end gap-3" @submit.prevent="cancelCredit"><label class="referral-field flex-1">Reason (required)<input v-model="cancelReason" maxlength="500" required class="field-control" placeholder="Recorded with the cancellation" /></label><button type="button" class="secondary-button" @click="cancelTarget = null">Keep credit</button><button class="danger-button" :disabled="!cancelReason.trim()">Cancel credit</button></form>
            </div>
            <div class="mt-5 overflow-x-auto"><table class="data-table min-w-[1100px]"><thead><tr><th>Created</th><th>User</th><th>Amount</th><th>Status</th><th>Attempts</th><th>Next retry</th><th>Last error</th><th>Provider ref</th><th></th></tr></thead><tbody>
              <tr v-for="c in credits" :key="c.Id"><td class="text-xs">{{ date(c.CreatedAt) }}<div class="text-slate-500">{{ c.RewardIds.length }} reward{{ c.RewardIds.length === 1 ? '' : 's' }}</div></td>
                <td class="text-xs">{{ c.UserEmail }}<div class="text-slate-500">#{{ c.UserId }} · {{ c.Destination }}</div></td><td class="font-semibold">{{ money(c.Amount, c.Currency) }}</td>
                <td><StatusPill :label="c.Status" :tone="statusTone(c.Status)" /><div v-if="creditNote(c)" class="mt-1 text-xs text-slate-500">{{ creditNote(c) }}</div></td><td>{{ c.Attempts }}</td>
                <td class="text-xs">{{ c.NextAttemptAt && c.Status !== 'PAID' && c.Status !== 'CANCELLED' ? date(c.NextAttemptAt) : '—' }}</td>
                <td class="max-w-xs truncate text-xs text-slate-500" :title="c.LastError || undefined">{{ c.LastError || '—' }}</td>
                <td class="font-mono text-xs">{{ c.ProviderReference || '—' }}<div v-if="c.ProviderConfirmedAt" class="font-sans text-slate-500">confirmed {{ day(c.ProviderConfirmedAt) }}</div></td>
                <td><div class="flex justify-end gap-2"><button v-if="canRetry(c)" class="secondary-button" @click="retryCredit(c)">Retry</button><button v-if="canCancel(c)" class="danger-button" @click="cancelTarget = c; cancelReason = ''">Cancel</button></div></td></tr>
              <tr v-if="!credits.length"><td colspan="9">{{ sectionErrors.credits ? 'Credits unavailable.' : creditPage > 1 ? 'No more credits.' : 'No credits with this status.' }}</td></tr></tbody></table></div>
            <div class="mt-4 flex flex-wrap items-center justify-between gap-3 text-sm text-slate-500"><span>Page {{ creditPage }} · {{ PAGE_SIZE }} rows per page · company-wide</span><div class="flex gap-2"><button type="button" class="secondary-button" :disabled="creditPage === 1" @click="pageCredits(-1)">Previous</button><button type="button" class="secondary-button" :disabled="credits.length < PAGE_SIZE" @click="pageCredits(1)">Next</button></div></div>
          </section>
        </template>

        <section v-else-if="tab === 'metrics'" class="panel p-5 sm:p-6">
          <h2 class="panel-heading">Cohort metrics</h2><p class="mt-2 text-sm text-slate-500">Weekly cohorts by attribution date. First purchase and repeat use are measured within 30 days of qualification. Cash contribution = top-up fees collected − provider cost − rewards paid. Credit counts are company-wide.</p>
          <p v-if="sectionErrors.metrics" role="alert" class="mt-4 text-sm text-red-700">Could not load metrics. {{ sectionErrors.metrics }}</p>
          <template v-else-if="metrics">
            <div class="mt-5 grid gap-3 sm:grid-cols-3 xl:grid-cols-6">
              <div v-for="tile in [['Credits attempted', metrics.CreditsAttempted], ['Credits paid', metrics.CreditsPaid], ['Credit success rate', `${metrics.CreditSuccessRate.toFixed(1)}%`], ['Fees collected', money(metrics.FeesCollected, metrics.Currency)], ['Provider cost', money(metrics.ProviderCost, metrics.Currency)], ['Reward cost', money(metrics.RewardCost, metrics.Currency)]]" :key="String(tile[0])" class="rounded-xl border border-slate-200 p-4"><p class="text-xs text-slate-500">{{ tile[0] }}</p><p class="mt-1 text-lg font-semibold">{{ tile[1] }}</p></div>
            </div>
            <div class="mt-4 rounded-xl border p-4" :class="metrics.Contribution < 0 ? 'border-red-200 bg-red-50' : 'border-emerald-200 bg-emerald-50'"><p class="text-xs text-slate-500">Cash contribution</p><p class="mt-1 text-2xl font-semibold">{{ money(metrics.Contribution, metrics.Currency) }}</p></div>
            <div class="mt-5">
              <AnalyticsChart kind="line" :labels="metricLabels" :series="metricSeries" :height="280" title-y="Relationships" empty-text="No cohorts yet." aria-label="Weekly cohorts: attributed, qualified, first purchase and repeat use" />
            </div>
            <div class="mt-5 overflow-x-auto"><table class="data-table min-w-[700px]"><thead><tr><th>Week</th><th>Attributed</th><th>Qualified</th><th>First purchase ≤30d</th><th>Repeat use ≤30d</th></tr></thead><tbody>
              <tr v-for="week in metrics.Weeks" :key="week.WeekStart"><td>{{ day(week.WeekStart) }}</td><td>{{ week.Attributed }}</td><td>{{ week.Qualified }}<span v-if="week.Attributed" class="text-xs text-slate-500"> ({{ Math.round((week.Qualified / week.Attributed) * 100) }}%)</span></td><td>{{ week.FirstPurchaseWithin30Days }}</td><td>{{ week.RepeatUseWithin30Days }}</td></tr>
              <tr v-if="!metrics.Weeks.length"><td colspan="5">No cohorts yet.</td></tr></tbody></table></div>
          </template>
          <p v-else class="mt-3 text-sm text-slate-500">No metrics yet.</p>
        </section>
      </fieldset>
    </template>
  </AppShell>
</template>

<style scoped>
.referral-field { display: flex; flex-direction: column; gap: .5rem; min-width: 0; font-size: .875rem; font-weight: 600; }
.referral-field small { color: #64748b; font-weight: 400; line-height: 1.5; }
.referral-field select { max-width: 100%; }
.check-row { display: flex; align-items: flex-start; gap: .75rem; border: 1px solid #e2e8f0; border-radius: .75rem; padding: .75rem; font-size: .875rem; font-weight: 600; cursor: pointer; }
.check-row input { margin-top: .2rem; }
.check-row small { display: block; color: #64748b; font-weight: 400; line-height: 1.5; }
fieldset:disabled { opacity: .7; }
.sample-switch { display: inline-flex; align-items: center; gap: .5rem; border: 1px solid #e2e8f0; border-radius: 9999px; padding: .375rem .875rem; font-size: .875rem; font-weight: 600; cursor: pointer; }
.sample-switch input { accent-color: #1d4ed8; }
.step-button { display: flex; width: 100%; align-items: center; gap: .75rem; border-radius: .75rem; padding: .625rem .75rem; text-align: left; transition: background-color .15s; }
.step-button:hover { background: #f1f5f9; }
.step-button--active { background: #eff6ff; box-shadow: inset 0 0 0 1px #bfdbfe; }
.step-index { display: grid; place-items: center; flex: none; width: 1.75rem; height: 1.75rem; border-radius: 9999px; background: #e2e8f0; font-size: .75rem; font-weight: 700; color: #334155; }
.step-button--active .step-index { background: #2563eb; color: #fff; }
</style>
