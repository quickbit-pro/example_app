<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AppShell from '@/components/AppShell.vue';
import StatusPill from '@/components/StatusPill.vue';
import { formatCurrency, formatDateTime } from '@/lib/formatters';
import { operationsApi, type MoneyResponse } from '@/lib/operationsApi';
import { DIRECTION_LABELS, STATUS_LABELS, amountClass, amountSign, directionIcon, kindLabel, sortKinds, type TransactionDirection } from '@/lib/transactionKinds';

const route = useRoute();
const router = useRouter();
const queryText = (key: string) => (typeof route.query[key] === 'string' ? route.query[key] as string : '');
const queryRange = Number(queryText('range'));
const range = ref([0, 7, 30, 90].includes(queryRange) && queryText('range') ? queryRange : route.query.cardId || route.query.budgetId ? 0 : 30);
const search = ref(queryText('q'));
const customerId = ref(String(route.query.customerId ?? ''));
const status = ref(queryText('status'));
const direction = ref(queryText('direction'));
const currency = ref('');
const kind = ref(String(route.query.kind ?? ''));
const cardId = ref(String(route.query.cardId ?? ''));
const budgetId = ref(String(route.query.budgetId ?? ''));
const context = ref(String(route.query.context ?? ''));
const sortBy = ref('date');
const sortDirection = ref<'asc' | 'desc'>('desc');
const page = ref(1);
const pageSize = ref(25);
const loading = ref(true);
const error = ref('');
const result = ref<MoneyResponse>({ activity: [], balances: [], customers: [], filterOptions: { currencies: [], kinds: [], statuses: [] }, kinds: [], limit: 25, offset: 0, rangeDays: 30, recentTransactions: [], totalCount: 0 });
let timer: ReturnType<typeof setTimeout> | undefined;

const maxMovement = computed(() => Math.max(1, ...result.value.activity.flatMap((row) => [row.inflow, row.outflow, row.internal])));
const totalPages = computed(() => Math.max(1, Math.ceil(result.value.totalCount / pageSize.value)));
const firstItem = computed(() => result.value.totalCount ? (page.value - 1) * pageSize.value + 1 : 0);
const lastItem = computed(() => Math.min(page.value * pageSize.value, result.value.totalCount));
const drilldownActive = computed(() => Boolean(cardId.value || budgetId.value));
const kindOptions = computed(() => sortKinds(result.value.filterOptions.kinds));
const directions = Object.entries(DIRECTION_LABELS) as [TransactionDirection, string][];

async function load() {
  loading.value = true; error.value = '';
  try {
    result.value = await operationsApi.money({ range: range.value, q: search.value || undefined, customerId: customerId.value || undefined, status: status.value || undefined,
      direction: direction.value || undefined, currency: currency.value || undefined, kind: kind.value || undefined, cardId: cardId.value || undefined, budgetId: budgetId.value || undefined,
      sortBy: sortBy.value, sortDirection: sortDirection.value, offset: (page.value - 1) * pageSize.value, limit: pageSize.value });
  } catch (caught) { error.value = caught instanceof Error ? caught.message : 'Financial activity could not be loaded.'; }
  finally { loading.value = false; }
}
function queueLoad(resetPage = false) { if (resetPage) page.value = 1; clearTimeout(timer); timer = setTimeout(load, search.value ? 250 : 0); }
function changeSort(field: string) { if (sortBy.value === field) sortDirection.value = sortDirection.value === 'asc' ? 'desc' : 'asc'; else { sortBy.value = field; sortDirection.value = field === 'date' || field === 'amount' ? 'desc' : 'asc'; } queueLoad(); }
function sortIcon(field: string) { if (sortBy.value !== field) return 'pi pi-sort-alt text-slate-300'; return sortDirection.value === 'asc' ? 'pi pi-sort-amount-up text-blue-600' : 'pi pi-sort-amount-down text-blue-600'; }
function clearDrilldown() { cardId.value = ''; budgetId.value = ''; context.value = ''; router.replace({ path: '/money', query: customerId.value ? { customerId: customerId.value } : {} }); queueLoad(true); }
function customerChanged() { if (drilldownActive.value) { cardId.value = ''; budgetId.value = ''; context.value = ''; } router.replace({ path: '/money', query: customerId.value ? { customerId: customerId.value } : {} }); queueLoad(true); }
function clearFilters() { search.value = ''; status.value = ''; direction.value = ''; currency.value = ''; kind.value = ''; page.value = 1; load(); }
function amounts(entry: MoneyResponse['kinds'][number]) { return entry.amounts.slice(0, 2).map(item => formatCurrency(item.amount, item.currency)).join(' · '); }

watch([range, status, direction, currency, kind, pageSize], () => queueLoad(true));
watch(search, () => queueLoad(true));
watch(page, () => queueLoad());
onBeforeUnmount(() => clearTimeout(timer));
onMounted(load);
</script>

<template>
  <AppShell>
    <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div><h1 class="page-title">Money</h1><p class="page-subtitle">Every customer transaction, classified: what it was, which way the money moved, and whether it went through.</p></div>
      <div class="flex rounded-xl border border-slate-200 bg-white p-1"><button v-for="option in [7,30,90,0]" :key="option" class="rounded-lg px-3 py-2 text-xs font-semibold" :class="range === option ? 'bg-blue-600 text-white' : 'text-slate-600'" @click="range = option">{{ option === 0 ? 'All time' : `${option} days` }}</button></div>
    </div>
    <section v-if="drilldownActive" class="mt-5 flex flex-col gap-3 rounded-2xl border border-blue-200 bg-blue-50 p-4 text-blue-950 sm:flex-row sm:items-center sm:justify-between"><div><div class="text-xs font-bold uppercase tracking-wide text-blue-600">Transaction drill-down</div><div class="mt-1 font-bold">{{ context || (cardId ? 'Selected card' : 'Selected budget') }}</div></div><button class="secondary-button !border-blue-200 !bg-white" @click="clearDrilldown"><i class="pi pi-times" />Show all customer transactions</button></section>

    <section class="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <div v-for="balance in result.balances" :key="balance.currency" class="metric-card"><div class="flex items-center justify-between"><span class="grid size-9 place-items-center rounded-xl bg-slate-100 text-xs font-bold">{{ balance.currency }}</span><i class="pi pi-wallet text-blue-600" /></div><div class="mt-4 text-2xl font-bold text-slate-950">{{ formatCurrency(balance.amount, balance.currency) }}</div><div class="mt-1 text-xs text-slate-500">Available customer funds</div></div>
      <div v-if="!result.balances.length && !loading" class="metric-card text-sm text-slate-500">Balances will appear after synchronization.</div>
    </section>

    <section class="mt-4 grid gap-4 xl:grid-cols-2">
      <div class="panel p-5">
        <h2 class="panel-heading">Movement by currency</h2>
        <p class="mt-1 text-xs text-slate-500">Completed transactions. Card top-ups and conversions move the customer's own money and are shown separately.</p>
        <div v-if="result.activity.length" class="mt-5 space-y-6">
          <div v-for="item in result.activity" :key="item.currency">
            <div class="mb-3 flex justify-between"><span class="font-bold text-slate-900">{{ item.currency }}</span><span class="text-xs text-slate-500">{{ item.transactionCount.toLocaleString() }} completed</span></div>
            <div class="space-y-2.5">
              <div class="flex items-center gap-3"><span class="w-24 text-xs text-slate-500">Money in</span><div class="h-3 flex-1 rounded-full bg-slate-100"><div class="h-full rounded-full bg-emerald-600" :style="{ width: `${Math.max(2, item.inflow / maxMovement * 100)}%` }" /></div><span class="w-32 text-right text-xs font-semibold">{{ formatCurrency(item.inflow, item.currency) }}</span></div>
              <div class="flex items-center gap-3"><span class="w-24 text-xs text-slate-500">Money out</span><div class="h-3 flex-1 rounded-full bg-slate-100"><div class="h-full rounded-full bg-blue-600" :style="{ width: `${Math.max(2, item.outflow / maxMovement * 100)}%` }" /></div><span class="w-32 text-right text-xs font-semibold">{{ formatCurrency(item.outflow, item.currency) }}</span></div>
              <div class="flex items-center gap-3"><span class="w-24 text-xs text-slate-500">Own balances</span><div class="h-3 flex-1 rounded-full bg-slate-100"><div class="h-full rounded-full bg-slate-300" :style="{ width: `${Math.max(2, item.internal / maxMovement * 100)}%` }" /></div><span class="w-32 text-right text-xs font-semibold text-slate-500">{{ formatCurrency(item.internal, item.currency) }}</span></div>
            </div>
          </div>
        </div>
        <div v-else class="mt-5 text-sm text-slate-500">No completed transactions match this selection.</div>
      </div>
      <div class="panel p-5">
        <h2 class="panel-heading">By type</h2>
        <p class="mt-1 text-xs text-slate-500">Completed transactions, each movement counted once. Select a type to filter the table.</p>
        <div v-if="result.kinds.length" class="mt-4 divide-y divide-slate-100">
          <button v-for="entry in result.kinds" :key="entry.kind" type="button" class="flex w-full items-center justify-between gap-3 py-2.5 text-left transition hover:text-blue-700" :class="kind === entry.kind ? 'text-blue-700' : ''" @click="kind = kind === entry.kind ? '' : entry.kind">
            <span class="text-sm font-semibold">{{ kindLabel(entry.kind) }}</span>
            <span class="flex items-center gap-4 text-xs"><span class="text-slate-500">{{ entry.count.toLocaleString() }}</span><span class="min-w-32 text-right font-semibold tabular-nums text-slate-800">{{ amounts(entry) }}</span></span>
          </button>
        </div>
        <div v-else class="mt-5 text-sm text-slate-500">No completed transactions match this selection.</div>
      </div>
    </section>

    <section class="mt-4 panel p-4">
      <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-7">
        <label class="relative xl:col-span-2"><i class="pi pi-search absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" /><input v-model="search" class="field-control w-full pl-11" placeholder="Search customer, merchant or description" /></label>
        <select v-model="customerId" class="field-control" @change="customerChanged"><option value="">All customers</option><option v-for="customer in result.customers" :key="customer.id" :value="customer.id">{{ customer.name }}</option></select>
        <select v-model="kind" class="field-control"><option value="">All types</option><option v-for="option in kindOptions" :key="option" :value="option">{{ kindLabel(option) }}</option></select>
        <select v-model="status" class="field-control"><option value="">All statuses</option><option v-for="option in result.filterOptions.statuses" :key="option" :value="option">{{ STATUS_LABELS[option] ?? option }}</option></select>
        <select v-model="direction" class="field-control"><option value="">All directions</option><option v-for="[value, label] in directions" :key="value" :value="value">{{ label }}</option></select>
        <select v-model="currency" class="field-control"><option value="">All currencies</option><option v-for="option in result.filterOptions.currencies" :key="option" :value="option">{{ option }}</option></select>
      </div>
    </section>

    <div class="mt-4 flex items-center justify-between"><h2 class="panel-heading">Transactions</h2><div class="text-sm font-semibold text-slate-600">{{ result.totalCount.toLocaleString() }} matching</div></div>
    <div v-if="error" class="mt-4 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{{ error }} <button class="ml-2 font-semibold underline" @click="load">Try again</button></div>
    <div v-if="loading" class="mt-4 table-shell h-56 animate-pulse bg-slate-100" />
    <div v-else-if="result.recentTransactions.length" class="mt-4 table-shell overflow-x-auto">
      <table class="data-table min-w-[1180px]">
        <thead><tr>
          <th><button class="inline-flex items-center gap-2" @click="changeSort('customer')">Customer <i :class="sortIcon('customer')" /></button></th>
          <th><button class="inline-flex items-center gap-2" @click="changeSort('description')">Description <i :class="sortIcon('description')" /></button></th>
          <th><button class="inline-flex items-center gap-2" @click="changeSort('kind')">Type <i :class="sortIcon('kind')" /></button></th>
          <th><button class="inline-flex items-center gap-2" @click="changeSort('direction')">Direction <i :class="sortIcon('direction')" /></button></th>
          <th><button class="inline-flex items-center gap-2" @click="changeSort('status')">Status <i :class="sortIcon('status')" /></button></th>
          <th><button class="inline-flex items-center gap-2" @click="changeSort('date')">Date <i :class="sortIcon('date')" /></button></th>
          <th class="text-right"><button class="inline-flex items-center gap-2" @click="changeSort('amount')">Amount <i :class="sortIcon('amount')" /></button></th>
        </tr></thead>
        <tbody>
          <tr v-for="transaction in result.recentTransactions" :key="transaction.reference" class="cursor-pointer" :class="transaction.isDuplicate || !transaction.isPrimary ? 'opacity-60' : ''" @click="$router.push(`/customers/${transaction.customerId}`)">
            <td class="font-semibold text-slate-900">{{ transaction.customerName }}</td>
            <td>
              <div class="max-w-md truncate" :title="transaction.description">{{ transaction.merchant || transaction.description }}</div>
              <div v-if="transaction.merchant && transaction.merchant !== transaction.description" class="mt-0.5 max-w-md truncate text-xs text-slate-400" :title="transaction.description">{{ transaction.description }}</div>
              <div v-if="transaction.isDuplicate || !transaction.isPrimary" class="mt-1 text-[11px] font-semibold text-slate-500">{{ transaction.isDuplicate ? 'Duplicate provider record · not counted' : 'Related provider leg · not counted' }}</div>
            </td>
            <td class="whitespace-nowrap text-xs font-semibold text-slate-700">{{ kindLabel(transaction.kind, transaction.feeType) }}</td>
            <td class="whitespace-nowrap"><span class="text-xs font-semibold" :class="transaction.direction === 'in' ? 'text-emerald-700' : 'text-slate-600'"><i :class="directionIcon(transaction.direction)" class="mr-1.5" />{{ DIRECTION_LABELS[transaction.direction] ?? transaction.direction }}</span></td>
            <td><StatusPill :label="STATUS_LABELS[transaction.status] ?? transaction.status" :tone="transaction.status === 'completed' ? 'success' : transaction.status === 'failed' ? 'danger' : transaction.status === 'pending' ? 'warning' : 'neutral'" /></td>
            <td class="whitespace-nowrap">{{ formatDateTime(transaction.occurredAt) }}</td>
            <td class="whitespace-nowrap text-right font-bold" :class="amountClass(transaction)">{{ amountSign(transaction.direction) }}{{ formatCurrency(transaction.amount, transaction.currency) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-else class="empty-state mt-4"><div class="font-semibold text-slate-900">No transactions match these filters</div><button class="secondary-button mt-4" @click="clearFilters">Clear table filters</button></div>
    <div v-if="result.totalCount" class="mt-4 flex flex-col gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 sm:flex-row sm:items-center sm:justify-between"><div class="text-sm text-slate-500">Showing {{ firstItem }}–{{ lastItem }} of {{ result.totalCount.toLocaleString() }}</div><div class="flex items-center gap-2"><select v-model.number="pageSize" class="field-control !py-2"><option :value="10">10 rows</option><option :value="25">25 rows</option><option :value="50">50 rows</option><option :value="100">100 rows</option></select><button class="secondary-button !px-3" :disabled="page <= 1" @click="page--"><i class="pi pi-angle-left" /></button><span class="px-2 text-sm font-semibold">{{ page }} / {{ totalPages }}</span><button class="secondary-button !px-3" :disabled="page >= totalPages" @click="page++"><i class="pi pi-angle-right" /></button></div></div>
  </AppShell>
</template>
