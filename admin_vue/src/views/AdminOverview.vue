<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import AppShell from '@/components/AppShell.vue';
import AttentionList from '@/components/overview/AttentionList.vue';
import CohortTable from '@/components/overview/CohortTable.vue';
import DeclinesPanel from '@/components/overview/DeclinesPanel.vue';
import InsightsPanel from '@/components/overview/InsightsPanel.vue';
import KpiTile from '@/components/overview/KpiTile.vue';
import NeedsYouStrip from '@/components/overview/NeedsYouStrip.vue';
import OverviewChart from '@/components/overview/OverviewChart.vue';
import SegmentsPanel from '@/components/overview/SegmentsPanel.vue';
import { STAGES, STAGE_TONE_CLASS } from '@/lib/customerStages';
import { formatCurrency, formatDateTime, relativeTime } from '@/lib/formatters';
import { kpiInfo, type KpiKey } from '@/lib/kpiDefinitions';
import { operationsApi, type OverviewData } from '@/lib/operationsApi';
import {
  balanceBars, balancesOption, balancesScale, bucketFor, customerGrowthOption, feeBreakdownOption, formatPercent, funnelConversions, funnelOption,
  greeting, isAllZero, needsYouItems, pairedBarsOption, pointTrend, readOverviewTheme, trend, weeklyBuckets, type OverviewTheme,
} from '@/lib/overviewCharts';
import { DEMO_INSIGHTS, DEMO_REFERRALS, buildOverviewDemo, type OverviewReferralSummary } from '@/lib/overviewDemo';
import { referralsApi } from '@/lib/referralsApi';

const range = ref(30);
const loading = ref(true);
const error = ref('');
const overview = ref<OverviewData | null>(null);
const referrals = ref<OverviewReferralSummary | null>(null);
const showSample = ref(false);
const theme = ref<OverviewTheme>(readOverviewTheme(() => ''));
const now = ref(new Date());
const timeZone = ref('UTC');
const timeZones = ref<string[]>([]);
const savingZone = ref(false);
let requestId = 0;

/** Sample mode is offered only when the workspace is empty or the overview could not be loaded (stable across reloads: the error is kept until a result arrives). */
const sampleAvailable = computed(() => !!error.value || (overview.value !== null && overview.value.kpis.customers === 0));
const sampleActive = computed(() => showSample.value && sampleAvailable.value);
const data = computed<OverviewData | null>(() => sampleActive.value ? buildOverviewDemo(range.value, now.value) : overview.value);
const referralData = computed(() => sampleActive.value ? DEMO_REFERRALS : referrals.value);
const firstLoad = computed(() => loading.value && !overview.value && !error.value);

const title = computed(() => greeting(now.value.getHours()));
const days = computed(() => data.value?.rangeDays || range.value);
const currency = computed(() => data.value?.reportingCurrency || 'USD');
const bucket = computed(() => bucketFor(days.value));
const trendTitle = computed(() => `Compared with the previous ${days.value} days`);
const asOf = computed(() => data.value ? `Figures as of ${formatDateTime(data.value.generatedAt)}${data.value.updatedAt ? `, from customer data refreshed ${relativeTime(data.value.updatedAt)}` : ''}.` : '');
const zoneOptions = computed(() => [...new Set([timeZone.value, ...timeZones.value])]);
const money = (value: number) => formatCurrency(value, currency.value);
const count = (value: number) => value.toLocaleString();
const plural = (value: number, one: string, many: string) => `${count(value)} ${value === 1 ? one : many}`;
const info = (key: KpiKey) => kpiInfo(key, asOf.value);
/** Amount changes under $100 read as "+$45" instead of a percentage of almost nothing. */
const amountTrend = (current: number, previous: number, higherIsBetter = true) =>
  trend(current, previous, higherIsBetter, { minBase: 100, formatDelta: value => formatCurrency(value, currency.value) });
const basis = computed(() => {
  if (!data.value) return '';
  const parts = [`Amounts in ${currency.value}, USD stablecoins counted 1:1`, `days in ${data.value.timeZone}`];
  if (data.value.money.unconvertedCurrencies.length) parts.push(`${data.value.money.unconvertedCurrencies.join(', ')} not converted`);
  if (data.value.testCustomers) parts.push(`${plural(data.value.testCustomers, 'test account', 'test accounts')} left out`);
  parts.push(`changes compare with the previous ${days.value} days`);
  return parts.join(' · ');
});
const moneyRoute = (query: Record<string, string>) => ({ path: '/money', query: { range: String(days.value), ...query } });

const needsYou = computed(() => data.value ? needsYouItems({ attentionCount: data.value.attention.length, verificationAging: data.value.verificationAging,
  failedReferralCredits: referralData.value?.creditsFailed ?? null, support: data.value.support }) : []);
const stageCounts = computed(() => new Map((data.value?.stages ?? []).map(stage => [stage.stage, stage.count])));
const stageTotal = computed(() => [...stageCounts.value.values()].reduce((sum, value) => sum + value, 0));

const series = computed(() => data.value?.series ?? []);
const buckets = computed(() => bucket.value === 'week'
  ? weeklyBuckets(series.value, ['signups', 'approvals', 'deposits', 'withdrawals', 'spend', 'declines', 'declinedAmount', 'fees'])
  : series.value);
const signups = computed(() => buckets.value.map(point => ({ date: point.date, count: point.signups })));
const growthOption = computed(() => signups.value.length && !isAllZero(signups.value.map(point => point.count)) ? customerGrowthOption(signups.value, theme.value, undefined, bucket.value) : null);
const cardChart = computed(() => {
  const points = buckets.value.map(point => ({ day: point.date, first: point.spend, second: point.declinedAmount }));
  return points.length && !isAllZero(points.flatMap(point => [point.first, point.second]))
    ? pairedBarsOption(points, ['Settled spend', 'Declined'], [theme.value.accent, theme.value.negative], currency.value, theme.value, formatCurrency, undefined, bucket.value) : null;
});
const moneyChart = computed(() => {
  const points = buckets.value.map(point => ({ day: point.date, first: point.deposits, second: point.withdrawals }));
  return points.length && !isAllZero(points.flatMap(point => [point.first, point.second]))
    ? pairedBarsOption(points, ['Deposits', 'Withdrawals'], [theme.value.positive, theme.value.neutralSoft], currency.value, theme.value, formatCurrency, undefined, bucket.value) : null;
});
const perBucket = computed(() => bucket.value === 'week' ? 'per week' : 'per day');
const feeRows = computed(() => data.value?.revenue.byType ?? []);
const feeChart = computed(() => feeRows.value.length ? feeBreakdownOption(feeRows.value, theme.value, formatCurrency, currency.value) : null);
const feeHeight = computed(() => Math.max(120, 34 * feeRows.value.length + 8));

const funnelSteps = computed(() => data.value?.funnel ?? []);
const funnelChart = computed(() => funnelSteps.value.length && (funnelSteps.value[0]?.value ?? 0) > 0 ? funnelOption(funnelSteps.value, theme.value) : null);
const conversions = computed(() => funnelConversions(funnelSteps.value));

const merchants = computed(() => data.value?.topMerchants ?? []);
const merchantMax = computed(() => Math.max(1, ...merchants.value.map(merchant => merchant.amount)));

const bars = computed(() => balanceBars(data.value?.balances ?? [], 8));
const balancesChart = computed(() => bars.value.length && !isAllZero(bars.value.map(bar => bar.amount)) ? balancesOption(bars.value, theme.value, formatCurrency) : null);
const balancesHeight = computed(() => Math.max(120, 36 * bars.value.length + 8));
const balancesNote = computed(() => balancesScale(bars.value) === 'log' ? 'Not converted · bar lengths on a log scale' : 'Not converted between currencies');

const attentionItems = computed(() => [...(data.value?.attention ?? [])].sort((a, b) => a.priority - b.priority).slice(0, 5));
const referralSub = computed(() => referralData.value ? `${formatCurrency(referralData.value.contribution, referralData.value.currency)} contribution` : '');
const declineTone = computed(() => (data.value?.cards.declineRate ?? 0) >= 10 ? 'warning' : 'neutral');
/** Fees minus referral rewards; provider costs are not known here, so this is before them. */
const contribution = computed(() => data.value && referralData.value ? data.value.revenue.fees.amount - referralData.value.rewardsAccrued : null);

async function load() {
  const id = ++requestId;
  loading.value = true;
  now.value = new Date();
  try {
    const result = await operationsApi.overview(range.value);
    if (id !== requestId) return;
    overview.value = result;
    timeZone.value = result.timeZone || timeZone.value;
    error.value = '';
  } catch (caught) {
    if (id !== requestId) return;
    error.value = caught instanceof Error ? caught.message : 'The overview could not be loaded.';
  } finally {
    if (id === requestId) loading.value = false;
  }
}
/** Referral figures are optional: a disabled programme (404) or a failed request just hides the tile. */
async function loadReferrals() {
  const id = requestId;
  const to = new Date();
  const from = new Date(to.getTime() - range.value * 86_400_000);
  const [analytics, reconciliation] = await Promise.allSettled([referralsApi.analytics(undefined, from.toISOString(), to.toISOString()), referralsApi.reconciliation()]);
  if (id !== requestId) return;
  if (analytics.status !== 'fulfilled') { referrals.value = null; return; }
  const value = analytics.value;
  referrals.value = { qualified: value.Funnel?.Qualified ?? 0, contribution: value.Contribution ?? 0, currency: value.Currency || 'USD',
    weeklyQualified: (value.Weekly ?? []).map(week => week.Qualified), creditsFailed: reconciliation.status === 'fulfilled' ? reconciliation.value.CreditsFailed : 0,
    rewardsAccrued: value.Cost?.Accrued ?? 0 };
}
async function loadSettings() {
  try {
    const settings = await operationsApi.reportingSettings();
    timeZone.value = settings.timeZone;
    timeZones.value = settings.suggestedTimeZones;
  } catch {
    // The selector keeps the zone the overview reported.
  }
}
async function changeTimeZone(zone: string) {
  if (zone === timeZone.value) return;
  savingZone.value = true;
  try {
    await operationsApi.saveReportingSettings(zone);
    timeZone.value = zone;
    await load();
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'The time zone could not be saved.';
  } finally {
    savingZone.value = false;
  }
}
function reload() { void load(); void loadReferrals(); }

function refreshTheme() {
  if (typeof getComputedStyle !== 'function' || typeof document === 'undefined') return;
  const root = document.documentElement;
  const style = getComputedStyle(root);
  theme.value = readOverviewTheme(variable => style.getPropertyValue(variable), root.classList.contains('dark') || root.getAttribute('data-theme') === 'dark');
}
const observer = typeof MutationObserver !== 'undefined' ? new MutationObserver(refreshTheme) : null;

watch(range, reload);
onMounted(() => { refreshTheme(); observer?.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'data-theme'] }); reload(); void loadSettings(); });
onBeforeUnmount(() => observer?.disconnect());
</script>

<template>
  <AppShell>
    <div class="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <h1 class="page-title">{{ title }}</h1>
        <p class="page-subtitle">How customers, money, cards and revenue are moving, and what needs your attention.</p>
      </div>
      <div class="flex flex-wrap items-center gap-3">
        <button
          v-if="sampleAvailable"
          type="button"
          class="inline-flex min-h-9 items-center gap-2 rounded-xl border px-3 text-xs font-semibold transition"
          :class="showSample ? 'border-violet-300 bg-violet-50 text-violet-800' : 'border-slate-200 bg-white text-slate-600 hover:bg-slate-50'"
          :aria-pressed="showSample"
          @click="showSample = !showSample"
        ><i class="pi pi-sparkles" />{{ showSample ? 'Hide sample data' : 'Show sample data' }}</button>
        <div class="flex rounded-xl border border-slate-200 bg-white p-1" role="group" aria-label="Period">
          <button
            v-for="option in [7, 30, 90]"
            :key="option"
            type="button"
            class="rounded-lg px-3 py-2 text-xs font-semibold transition"
            :class="range === option ? 'bg-blue-600 text-white' : 'text-slate-600 hover:bg-slate-50'"
            :aria-pressed="range === option"
            @click="range = option"
          >{{ option }} days</button>
        </div>
        <label class="flex items-center gap-2 text-xs font-medium text-slate-500" title="Where a reporting day starts. Saved for everyone who uses this admin panel.">
          <i class="pi pi-globe" />
          <span class="sr-only">Reporting time zone</span>
          <select class="field-control !min-h-9 !py-1 text-xs font-semibold" :value="timeZone" :disabled="savingZone || sampleActive" @change="changeTimeZone(($event.target as HTMLSelectElement).value)">
            <option v-for="zone in zoneOptions" :key="zone" :value="zone">{{ zone }}</option>
          </select>
        </label>
      </div>
    </div>
    <p v-if="data" class="mt-2 text-xs text-slate-500"><i class="pi pi-clock mr-1" />{{ asOf }}<span v-if="loading && !firstLoad" class="ml-1 text-slate-400">Refreshing…</span></p>

    <div v-if="error && !sampleActive" class="mt-6 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
      <div class="font-semibold">Overview temporarily unavailable</div>
      <div class="mt-1">{{ error }}</div>
      <button class="secondary-button mt-3" type="button" @click="reload">Try again</button>
    </div>

    <div v-if="firstLoad" class="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-busy="true">
      <div v-for="item in 8" :key="item" class="metric-card h-36 animate-pulse bg-slate-100" />
    </div>

    <template v-else-if="data">
      <div v-if="sampleActive" class="mt-6 flex items-start gap-3 rounded-2xl border border-violet-200 bg-violet-50 p-4 text-sm text-violet-900">
        <i class="pi pi-sparkles mt-0.5" />
        <div>
          <div class="font-semibold">Sample data, not live figures</div>
          <div class="mt-0.5 text-violet-800">This is what the overview looks like with an active customer base. Turn it off to return to your workspace.</div>
        </div>
      </div>
      <div v-else-if="data.freshness.state !== 'current'" class="mt-6 flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
        <i class="pi pi-refresh mt-0.5" />
        <div>
          <div class="font-semibold">{{ data.freshness.errorCustomers ? 'Some customer information could not be refreshed' : 'Some customer information is out of date' }}</div>
          <div class="mt-0.5 text-amber-800">{{ plural(data.freshness.staleCustomers, 'customer', 'customers') }} not refreshed for over an hour · {{ data.freshness.errorCustomers }} need retry</div>
        </div>
      </div>

      <div class="mt-6" :class="loading ? 'opacity-70 transition' : 'transition'">
        <NeedsYouStrip :items="needsYou" />
        <InsightsPanel class="mt-4" :range="range" :sample="sampleActive ? { ...DEMO_INSIGHTS, generatedAt: data.generatedAt, rangeDays: days } : null" />

        <section class="mt-6" aria-labelledby="journey-now">
          <div class="flex items-center justify-between gap-3">
            <h2 id="journey-now" class="text-xs font-bold uppercase tracking-wide text-slate-500">Where customers are now</h2>
            <span class="text-xs text-slate-500">{{ plural(stageTotal, 'customer', 'customers') }} · select a stage to see them and send a reminder</span>
          </div>
          <div class="mt-3 flex flex-wrap gap-2">
            <RouterLink v-for="stage in STAGES" :key="stage.key" :to="{ path: '/customers', query: { stage: stage.key } }" :title="stage.description"
              class="inline-flex min-h-9 items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 text-sm font-semibold text-slate-800 transition hover:border-blue-300 hover:bg-blue-50/60">
              <span class="rounded-md px-1.5 py-0.5 text-xs font-bold tabular-nums" :class="STAGE_TONE_CLASS[stage.tone]">{{ count(stageCounts.get(stage.key) ?? 0) }}</span>
              <span class="font-medium">{{ stage.label }}</span>
            </RouterLink>
          </div>
        </section>

        <p class="mt-5 text-xs text-slate-500">{{ basis }}</p>

        <section class="mt-3" aria-labelledby="kpi-customers">
          <h2 id="kpi-customers" class="text-xs font-bold uppercase tracking-wide text-slate-500">Customers</h2>
          <div class="mt-3 grid gap-4 sm:grid-cols-2" :class="referralData ? 'lg:grid-cols-3 xl:grid-cols-5' : 'xl:grid-cols-4'">
            <KpiTile label="New customers" :value="count(data.kpis.newCustomers.current)" :trend="trend(data.kpis.newCustomers.current, data.kpis.newCustomers.previous)" :trend-title="trendTitle"
              :sub="`${count(data.kpis.customers)} customers in total`" icon="pi pi-user-plus" :sparkline="signups.map(point => point.count)" sparkline-label="New customers"
              :info="info('newCustomers')" :to="{ path: '/customers', query: { since: data.from } }" :theme="theme" />
            <KpiTile label="Approved" :value="count(data.kpis.approvals.current)" :trend="trend(data.kpis.approvals.current, data.kpis.approvals.previous)" :trend-title="trendTitle"
              :sub="`${count(data.kpis.approvedCustomers)} approved · ${formatPercent(data.kpis.verifiedRate)} of all customers`" icon="pi pi-shield" icon-tone="positive"
              :sparkline="buckets.map(point => point.approvals)" sparkline-label="Approvals" :info="info('approvals')" to="/verification" :theme="theme" />
            <KpiTile label="Added money" :value="formatPercent(data.kpis.activationRate)" :sub="`${count(data.kpis.fundedCustomers)} of ${count(data.kpis.approvedCustomers)} approved customers`"
              :sub-tone="(data.kpis.activationRate ?? 0) < 50 ? 'warning' : 'neutral'" icon="pi pi-wallet" :info="info('addedMoney')"
              :to="{ path: '/customers', query: { stage: 'approved' } }" :theme="theme" />
            <KpiTile label="Transacting" :value="count(data.kpis.transactingCustomers.current)" :trend="trend(data.kpis.transactingCustomers.current, data.kpis.transactingCustomers.previous)"
              :trend-title="trendTitle" :sub="`Moved money · ${count(data.kpis.engagedCustomers)} signed in`" icon="pi pi-bolt" :info="info('transacting')"
              :to="{ path: '/customers', query: { stage: 'active' } }" :theme="theme" />
            <KpiTile v-if="referralData" label="Referral qualified" :value="referralData.qualified.toLocaleString()" :sub="referralSub" :sub-tone="referralData.contribution >= 0 ? 'positive' : 'warning'"
              icon="pi pi-gift" :sparkline="referralData.weeklyQualified" sparkline-label="Qualified referrals per week" :info="info('referral')" to="/referrals" :theme="theme" />
          </div>
        </section>

        <section class="mt-6" aria-labelledby="kpi-money">
          <div class="flex items-center justify-between gap-3">
            <h2 id="kpi-money" class="text-xs font-bold uppercase tracking-wide text-slate-500">Money</h2>
            <RouterLink :to="moneyRoute({})" class="text-xs font-semibold text-blue-700">View transactions</RouterLink>
          </div>
          <div class="mt-3 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <KpiTile label="Deposits" :value="money(data.money.deposits.amount)" :trend="amountTrend(data.money.deposits.amount, data.money.deposits.previousAmount)" :trend-title="trendTitle"
              :sub="plural(data.money.deposits.count, 'deposit', 'deposits')" icon="pi pi-arrow-down-left" icon-tone="positive" :sparkline="buckets.map(point => point.deposits)" sparkline-label="Deposits"
              :info="info('deposits')" :to="moneyRoute({ kind: 'deposit', status: 'completed' })" :theme="theme" />
            <KpiTile label="Withdrawals" :value="money(data.money.withdrawals.amount)" :trend="amountTrend(data.money.withdrawals.amount, data.money.withdrawals.previousAmount, false)" :trend-title="trendTitle"
              :sub="plural(data.money.withdrawals.count, 'withdrawal', 'withdrawals')" icon="pi pi-arrow-up-right" :sparkline="buckets.map(point => point.withdrawals)" sparkline-label="Withdrawals"
              :info="info('withdrawals')" :to="moneyRoute({ kind: 'withdrawal', status: 'completed' })" :theme="theme" />
            <KpiTile label="Net new money" :value="money(data.money.netDeposits)" sub="Deposits minus withdrawals" :sub-tone="data.money.netDeposits < 0 ? 'warning' : 'positive'" icon="pi pi-chart-line"
              :info="info('netNewMoney')" :to="moneyRoute({ status: 'completed' })" :theme="theme" />
            <KpiTile label="Customer funds" :value="money(data.money.fundsHeld)"
              :sub="`${plural(data.money.transfers.count, 'transfer', 'transfers')} between customers · ${plural(data.money.conversions, 'conversion', 'conversions')}`" icon="pi pi-building-columns"
              :info="info('customerFunds')" to="/money" :theme="theme" />
          </div>
        </section>

        <section class="mt-6" aria-labelledby="kpi-cards">
          <div class="flex items-center justify-between gap-3">
            <h2 id="kpi-cards" class="text-xs font-bold uppercase tracking-wide text-slate-500">Cards</h2>
            <RouterLink to="/cards" class="text-xs font-semibold text-blue-700">View cards</RouterLink>
          </div>
          <div class="mt-3 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <KpiTile label="Card spend" :value="money(data.cards.spend.amount)" :trend="amountTrend(data.cards.spend.amount, data.cards.spend.previousAmount)" :trend-title="trendTitle"
              :sub="`${plural(data.cards.spend.count, 'purchase', 'purchases')}${data.cards.averageTicket != null ? ` · avg ${money(data.cards.averageTicket)}` : ''}`" icon="pi pi-shopping-cart"
              :sparkline="buckets.map(point => point.spend)" sparkline-label="Settled card spend" :info="info('cardSpend')" :to="moneyRoute({ kind: 'card_purchase', status: 'completed' })" :theme="theme" />
            <KpiTile label="Active cardholders" :value="count(data.cards.activeCardholders.current)" :trend="trend(data.cards.activeCardholders.current, data.cards.activeCardholders.previous)"
              :trend-title="trendTitle" :sub="`Made a purchase · ${plural(data.kpis.activeCards, 'active card', 'active cards')}`" icon="pi pi-credit-card" :info="info('activeCardholders')"
              :to="{ path: '/customers', query: { stage: 'active' } }" :theme="theme" />
            <KpiTile label="Decline rate" :value="formatPercent(data.cards.declineRate)" :trend="pointTrend(data.cards.declineRate, data.cards.previousDeclineRate, false)" :trend-title="trendTitle"
              :sub="`${plural(data.cards.declines.count, 'declined payment', 'declined payments')} · ${money(data.cards.declines.amount)}`" :sub-tone="declineTone" icon="pi pi-ban"
              :sparkline="buckets.map(point => point.declines)" sparkline-label="Declined card payments" :info="info('declineRate')" :to="moneyRoute({ kind: 'card_purchase', status: 'failed' })" :theme="theme" />
            <KpiTile label="Cards issued" :value="count(data.kpis.cardsIssued.current)" :trend="trend(data.kpis.cardsIssued.current, data.kpis.cardsIssued.previous)" :trend-title="trendTitle"
              :sub="`${plural(data.cards.checks, 'card check', 'card checks')} (wallet set-up)`" icon="pi pi-id-card" :info="info('cardsIssued')" to="/cards" :theme="theme" />
          </div>
        </section>

        <section class="mt-6" aria-labelledby="kpi-revenue">
          <h2 id="kpi-revenue" class="text-xs font-bold uppercase tracking-wide text-slate-500">Revenue</h2>
          <div class="mt-3 grid items-stretch gap-4 xl:grid-cols-4">
            <KpiTile label="Fees collected" :value="money(data.revenue.fees.amount)" :trend="amountTrend(data.revenue.fees.amount, data.revenue.fees.previousAmount)" :trend-title="trendTitle"
              :sub="plural(data.revenue.fees.count, 'charge', 'charges')" icon="pi pi-dollar" icon-tone="positive" :sparkline="buckets.map(point => point.fees)" sparkline-label="Fees"
              :info="info('fees')" :to="moneyRoute({ kind: 'fee', status: 'completed' })" :theme="theme" />
            <KpiTile label="Fees on declined payments" :value="money(data.revenue.onDeclinedPayments.amount)"
              :sub="`${plural(data.revenue.onDeclinedPayments.count, 'charge', 'charges')} on payments that did not go through`" :sub-tone="data.revenue.onDeclinedPayments.count ? 'warning' : 'neutral'"
              icon="pi pi-exclamation-triangle" :info="info('feesOnDeclines')" :to="moneyRoute({ kind: 'fee', status: 'completed' })" :theme="theme" />
            <div class="panel p-5 xl:col-span-2">
              <div class="flex items-center justify-between gap-3">
                <h3 class="panel-heading">Fees by type</h3>
                <span class="text-xs text-slate-500">Last {{ days }} days</span>
              </div>
              <OverviewChart class="mt-3" :option="feeChart" :height="feeHeight" empty-text="No fees charged in this period" aria-label="Fees collected by type" />
            </div>
          </div>
          <div class="mt-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-label="Unit economics">
            <div class="metric-card p-4">
              <div class="text-[13px] font-semibold text-slate-600">Fees per transacting customer</div>
              <div class="mt-2 text-xl font-bold text-slate-950">{{ data.revenue.perTransactingCustomer != null ? money(data.revenue.perTransactingCustomer) : '–' }}</div>
              <div class="mt-1 text-xs text-slate-500">{{ plural(data.kpis.transactingCustomers.current, 'customer', 'customers') }} moved money</div>
            </div>
            <div class="metric-card p-4">
              <div class="text-[13px] font-semibold text-slate-600">Fees per active cardholder</div>
              <div class="mt-2 text-xl font-bold text-slate-950">{{ data.revenue.perActiveCardholder != null ? money(data.revenue.perActiveCardholder) : '–' }}</div>
              <div class="mt-1 text-xs text-slate-500">{{ plural(data.cards.activeCardholders.current, 'cardholder', 'cardholders') }} made a purchase</div>
            </div>
            <div class="metric-card p-4">
              <div class="text-[13px] font-semibold text-slate-600">Referral rewards</div>
              <div class="mt-2 text-xl font-bold text-slate-950">{{ referralData ? formatCurrency(referralData.rewardsAccrued, referralData.currency) : '–' }}</div>
              <div class="mt-1 text-xs text-slate-500">{{ referralData ? 'Accrued in the period' : 'Referral programme not available' }}</div>
            </div>
            <div class="metric-card p-4">
              <div class="text-[13px] font-semibold text-slate-600">Contribution</div>
              <div class="mt-2 text-xl font-bold" :class="(contribution ?? 0) < 0 ? 'text-red-700' : 'text-slate-950'">{{ contribution != null ? money(contribution) : '–' }}</div>
              <div class="mt-1 text-xs text-slate-500">Fees minus referral rewards, before provider costs</div>
            </div>
          </div>
        </section>

        <section class="mt-6 grid items-start gap-4 xl:grid-cols-3">
          <div class="panel p-5 xl:col-span-2">
            <div class="flex items-center justify-between gap-3">
              <h2 class="panel-heading">Customer growth</h2>
              <span class="text-xs text-slate-500">New customers {{ perBucket }} · last {{ days }} days</span>
            </div>
            <OverviewChart class="mt-4" :option="growthOption" :height="250" empty-text="No new customers in this period" :aria-label="`New customers ${perBucket} with a moving average`" />
          </div>
          <AttentionList :items="attentionItems" :total="data.attention.length" />
        </section>

        <section class="mt-4 grid items-start gap-4 xl:grid-cols-2">
          <div class="panel p-5">
            <div class="flex items-center justify-between gap-3">
              <h2 class="panel-heading">Card payments</h2>
              <span class="text-xs text-slate-500">Settled vs declined {{ perBucket }}</span>
            </div>
            <OverviewChart class="mt-4" :option="cardChart" :height="240" empty-text="No card payments in this period" :aria-label="`Settled and declined card payments ${perBucket}`" />
          </div>
          <div class="panel p-5">
            <div class="flex items-center justify-between gap-3">
              <h2 class="panel-heading">Money in and out</h2>
              <span class="text-xs text-slate-500">Deposits vs withdrawals {{ perBucket }}</span>
            </div>
            <OverviewChart class="mt-4" :option="moneyChart" :height="240" empty-text="No deposits or withdrawals in this period" :aria-label="`Deposits and withdrawals ${perBucket}`" />
          </div>
        </section>

        <section class="mt-4 grid items-start gap-4 xl:grid-cols-2">
          <div class="panel p-5">
            <div class="flex items-center justify-between gap-3">
              <h2 class="panel-heading">Declined payments</h2>
              <RouterLink :to="moneyRoute({ kind: 'card_purchase', status: 'failed' })" class="text-xs font-semibold text-blue-700">View declines</RouterLink>
            </div>
            <p class="mt-1 text-xs text-slate-500">Last {{ days }} days. A high share at one merchant usually points to a merchant category, 3-D Secure or limit issue to raise with the card provider.</p>
            <DeclinesPanel class="mt-3" :declines="data.declines" :days="days" :money="money" />
          </div>
          <div class="panel p-5">
            <div class="flex items-center justify-between gap-3">
              <h2 class="panel-heading">Segments</h2>
              <RouterLink to="/customers" class="text-xs font-semibold text-blue-700">View customers</RouterLink>
            </div>
            <SegmentsPanel class="mt-3" :segments="data.segments" :money="money" />
          </div>
        </section>

        <section class="mt-4 grid items-start gap-4 xl:grid-cols-2">
          <div class="panel p-5">
            <div class="flex items-center justify-between gap-3">
              <h2 class="panel-heading">Customer journey</h2>
              <RouterLink to="/customers" class="text-xs font-semibold text-blue-700">View customers</RouterLink>
            </div>
            <p class="mt-1 text-xs text-slate-500">All customers by the furthest step reached; each step includes only customers who passed the one before.</p>
            <OverviewChart class="mt-4" :option="funnelChart" :height="280" empty-text="The journey will appear once customers start signing up" aria-label="Customer journey from sign-up to first card purchase" />
            <div v-if="funnelChart && conversions.length" class="mt-3 flex flex-wrap gap-x-5 gap-y-1 border-t border-slate-100 pt-3 text-[11px] text-slate-500">
              <span v-for="step in conversions" :key="step.to" class="inline-flex items-center gap-1">
                <span>{{ step.from }}</span><i class="pi pi-arrow-right text-[9px] text-slate-400" /><span>{{ step.to }}</span>
                <span class="ml-1 font-bold text-slate-800">{{ formatPercent(step.rate) }}</span>
              </span>
            </div>
          </div>

          <div class="panel p-5">
            <div class="flex items-center justify-between gap-3">
              <h2 class="panel-heading">Do customers stick?</h2>
              <span class="text-xs text-slate-500">Share of each signup week that moved money</span>
            </div>
            <p class="mt-1 text-xs text-slate-500">W0 is the week of signing up, W1 the week after, and so on. Darker means more of the cohort was active.</p>
            <CohortTable class="mt-4" :cohorts="data.cohorts" />
          </div>
        </section>

        <section class="mt-4 grid items-start gap-4 xl:grid-cols-2">
          <div class="panel p-5">
            <div class="flex items-center justify-between gap-3">
              <h2 class="panel-heading">Top merchants</h2>
              <span class="text-xs text-slate-500">Settled card spend · last {{ days }} days</span>
            </div>
            <table v-if="merchants.length" class="merchant-table mt-4 w-full text-sm">
              <thead>
                <tr class="text-[11px] font-bold uppercase tracking-wide text-slate-500">
                  <th class="pb-2 text-left">Merchant</th><th class="pb-2 text-right">Purchases</th><th class="pb-2 text-right">Spend</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="merchant in merchants" :key="merchant.name" class="border-t border-slate-100">
                  <td class="py-2">
                    <RouterLink :to="moneyRoute({ kind: 'card_purchase', status: 'completed', q: merchant.name })" class="font-semibold text-slate-800 hover:text-blue-700">{{ merchant.name }}</RouterLink>
                    <div class="mt-1 h-1.5 rounded-full bg-slate-100"><div class="h-full rounded-full bg-blue-600" :style="{ width: `${Math.max(2, (100 * merchant.amount) / merchantMax)}%` }" /></div>
                  </td>
                  <td class="py-2 text-right tabular-nums text-slate-600">{{ count(merchant.count) }}</td>
                  <td class="py-2 text-right font-semibold tabular-nums text-slate-900">{{ money(merchant.amount) }}</td>
                </tr>
              </tbody>
            </table>
            <p v-else class="mt-4 text-sm text-slate-500">No settled card purchases in this period.</p>
          </div>

          <div class="panel p-5">
            <div class="flex items-center justify-between gap-3">
              <h2 class="panel-heading">Customer funds by currency</h2>
              <RouterLink to="/money" class="text-xs font-semibold text-blue-700">View money</RouterLink>
            </div>
            <div v-if="balancesChart" class="mt-1 text-xs text-slate-500">{{ balancesNote }}</div>
            <OverviewChart class="mt-4" :option="balancesChart" :height="balancesHeight" empty-text="Balances will appear after the first customer refresh" aria-label="Customer balances by currency" />
          </div>
        </section>
      </div>
    </template>
  </AppShell>
</template>

<style scoped>
.merchant-table th, .merchant-table td { padding-left: .375rem; padding-right: .375rem; }
.merchant-table th:first-child, .merchant-table td:first-child { padding-left: 0; }
.merchant-table th:last-child, .merchant-table td:last-child { padding-right: 0; }
</style>
