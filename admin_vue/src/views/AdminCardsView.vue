<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AppShell from '@/components/AppShell.vue';
import StatusPill from '@/components/StatusPill.vue';
import { formatCurrency, formatDate, humanize } from '@/lib/formatters';
import { operationsApi, type CardPortfolioResponse } from '@/lib/operationsApi';

const route = useRoute();
const router = useRouter();
const loading = ref(true);
const error = ref('');
const refreshing = ref(false);
const refreshNote = ref('');
const search = ref('');
const customerId = ref('');
const status = ref('');
const currency = ref('');
const sortBy = ref('issued');
const sortDirection = ref<'asc' | 'desc'>('desc');
const page = ref(1);
const pageSize = ref(25);
const result = ref<CardPortfolioResponse>({ activeCount: 0, customers: [], filterOptions: { currencies: [], statuses: [] }, items: [], limit: 25, offset: 0, totalCount: 0 });
let timer: ReturnType<typeof setTimeout> | undefined;

const totalPages = computed(() => Math.max(1, Math.ceil(result.value.totalCount / pageSize.value)));
const firstItem = computed(() => result.value.totalCount ? (page.value - 1) * pageSize.value + 1 : 0);
const lastItem = computed(() => Math.min(page.value * pageSize.value, result.value.totalCount));

/** Re-syncs balances from the banking provider: the filtered customer, or every card holder in batches. */
async function refreshBalances() {
  if (refreshing.value) return;
  refreshing.value = true; error.value = ''; refreshNote.value = customerId.value ? 'Refreshing this customer…' : 'Refreshing balances…';
  try {
    let refreshed = 0, failed = 0, remaining = 0, rounds = 0;
    do {
      const result = await operationsApi.refreshCards(customerId.value ? { customerId: customerId.value } : { limit: 40 });
      refreshed += result.refreshed; failed += result.failed; remaining = result.remaining; rounds += 1;
      refreshNote.value = remaining ? `Refreshed ${refreshed} customers, ${remaining} to go…` : '';
    } while (remaining > 0 && rounds < 25);
    await load();
    refreshNote.value = failed
      ? `Balances refreshed for ${refreshed} ${refreshed === 1 ? 'customer' : 'customers'}; ${failed} could not be refreshed (the provider did not answer).`
      : `Balances refreshed for ${refreshed} ${refreshed === 1 ? 'customer' : 'customers'} at ${new Date().toLocaleTimeString()}.`;
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'Balances could not be refreshed.'; refreshNote.value = '';
  } finally { refreshing.value = false; }
}
async function load() {
  loading.value = true; error.value = '';
  try {
    result.value = await operationsApi.cards({ q: search.value || undefined, customerId: customerId.value || undefined, status: status.value || undefined, currency: currency.value || undefined, sortBy: sortBy.value, sortDirection: sortDirection.value, offset: (page.value - 1) * pageSize.value, limit: pageSize.value });
  } catch (caught) { error.value = caught instanceof Error ? caught.message : 'Cards could not be loaded.'; }
  finally { loading.value = false; }
}
function queueLoad(resetPage = false) { if (resetPage) page.value = 1; clearTimeout(timer); timer = setTimeout(load, search.value ? 250 : 0); }
function changeSort(field: string) { if (sortBy.value === field) sortDirection.value = sortDirection.value === 'asc' ? 'desc' : 'asc'; else { sortBy.value = field; sortDirection.value = field === 'issued' || field === 'balance' ? 'desc' : 'asc'; } queueLoad(); }
function sortIcon(field: string) { if (sortBy.value !== field) return 'pi pi-sort-alt text-slate-300'; return sortDirection.value === 'asc' ? 'pi pi-sort-amount-up text-blue-600' : 'pi pi-sort-amount-down text-blue-600'; }
function openCard(card: CardPortfolioResponse['items'][number]) { router.push({ path: '/money', query: { customerId: card.customerId, cardId: card.reference, context: `${humanize(card.type)} card •••• ${card.lastFour || '—'}` } }); }
function clearFilters() { search.value = ''; customerId.value = ''; status.value = ''; currency.value = ''; page.value = 1; load(); }

watch([customerId, status, currency, pageSize], () => queueLoad(true));
watch(search, () => queueLoad(true));
watch(page, () => queueLoad());
onBeforeUnmount(() => clearTimeout(timer));
// "View cards" on the customer page lands here with ?customerId=…; setting the filter triggers the watcher's load.
onMounted(() => {
  const preset = typeof route.query.customerId === 'string' ? route.query.customerId : '';
  if (preset) customerId.value = preset;
  else load();
});
</script>

<template>
  <AppShell>
    <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
      <div><h1 class="page-title">Cards</h1><p class="page-subtitle">Search the card portfolio, compare balances, and open a card’s transaction history.</p></div>
      <div class="flex flex-col items-start gap-1 sm:items-end">
        <button type="button" class="secondary-button" :disabled="refreshing" :title="customerId ? 'Refresh this customer’s balances from the banking provider' : 'Refresh every card holder’s balances from the banking provider'" @click="refreshBalances"><i class="pi pi-refresh" :class="refreshing ? 'pi-spin' : ''" aria-hidden="true" />{{ refreshing ? 'Refreshing…' : customerId ? 'Refresh this customer' : 'Refresh balances' }}</button>
        <span v-if="refreshNote" class="text-xs text-slate-500" role="status" aria-live="polite">{{ refreshNote }}</span>
      </div>
    </div>
    <section class="mt-7 grid gap-4 sm:grid-cols-3"><div class="metric-card"><div class="text-sm font-semibold text-slate-500">Matching cards</div><div class="mt-3 text-3xl font-bold text-slate-950">{{ result.totalCount }}</div></div><div class="metric-card"><div class="text-sm font-semibold text-slate-500">Active cards</div><div class="mt-3 text-3xl font-bold text-emerald-700">{{ result.activeCount }}</div></div><div class="metric-card"><div class="text-sm font-semibold text-slate-500">Activation rate</div><div class="mt-3 text-3xl font-bold text-slate-950">{{ result.totalCount ? Math.round(result.activeCount / result.totalCount * 100) : 0 }}%</div></div></section>
    <section class="mt-4 panel p-4"><div class="grid gap-3 md:grid-cols-2 xl:grid-cols-5"><label class="relative xl:col-span-2"><i class="pi pi-search absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" /><input v-model="search" class="field-control w-full pl-11" placeholder="Search customer, card type or last four" /></label><select v-model="customerId" class="field-control"><option value="">All customers</option><option v-for="customer in result.customers" :key="customer.id" :value="customer.id">{{ customer.name }}</option></select><select v-model="status" class="field-control"><option value="">All statuses</option><option v-for="option in result.filterOptions.statuses" :key="option" :value="option">{{ humanize(option) }}</option></select><select v-model="currency" class="field-control"><option value="">All currencies</option><option v-for="option in result.filterOptions.currencies" :key="option" :value="option">{{ option }}</option></select></div></section>
    <div v-if="error" class="mt-4 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{{ error }} <button class="ml-2 font-semibold underline" @click="load">Try again</button></div>
    <div v-if="loading" class="mt-4 table-shell h-64 animate-pulse bg-slate-100" />
    <div v-else-if="result.items.length" class="mt-4 table-shell overflow-x-auto"><table class="data-table min-w-[1050px]"><thead><tr><th><button class="inline-flex items-center gap-2" @click="changeSort('customer')">Customer <i :class="sortIcon('customer')" /></button></th><th><button class="inline-flex items-center gap-2" @click="changeSort('type')">Card <i :class="sortIcon('type')" /></button></th><th><button class="inline-flex items-center gap-2" @click="changeSort('currency')">Currency <i :class="sortIcon('currency')" /></button></th><th class="text-right"><button class="inline-flex items-center gap-2" @click="changeSort('balance')">Balance <i :class="sortIcon('balance')" /></button></th><th><button class="inline-flex items-center gap-2" @click="changeSort('status')">Status <i :class="sortIcon('status')" /></button></th><th><button class="inline-flex items-center gap-2" @click="changeSort('issued')">Issued <i :class="sortIcon('issued')" /></button></th><th>Activated</th><th></th></tr></thead><tbody><tr v-for="card in result.items" :key="`${card.customerId}-${card.reference}`" class="cursor-pointer" @click="openCard(card)"><td><button class="text-left font-semibold text-slate-950 hover:text-blue-700" @click.stop="$router.push(`/customers/${card.customerId}`)">{{ card.customerName }}</button></td><td><div class="font-semibold text-slate-800">{{ humanize(card.type) }}</div><div class="mt-1 text-xs tracking-wider text-slate-500">•••• {{ card.lastFour || '—' }}</div></td><td>{{ card.currency || 'Not available' }}</td><td class="text-right font-bold text-slate-950">{{ card.balance !== null && card.currency ? formatCurrency(card.balance, card.currency) : 'Not available' }}</td><td><StatusPill :label="card.status" /></td><td>{{ formatDate(card.issuedAt) }}</td><td>{{ formatDate(card.activatedAt) }}</td><td class="text-right"><i class="pi pi-angle-right text-slate-400" /></td></tr></tbody></table></div>
    <div v-else class="empty-state mt-4"><i class="pi pi-credit-card text-3xl text-slate-400" /><div class="mt-4 font-semibold text-slate-900">No cards match these filters</div><button class="secondary-button mt-4" @click="clearFilters">Clear filters</button></div>
    <div v-if="result.totalCount" class="mt-4 flex flex-col gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 sm:flex-row sm:items-center sm:justify-between"><div class="text-sm text-slate-500">Showing {{ firstItem }}–{{ lastItem }} of {{ result.totalCount }}</div><div class="flex items-center gap-2"><select v-model.number="pageSize" class="field-control !py-2"><option :value="10">10 rows</option><option :value="25">25 rows</option><option :value="50">50 rows</option></select><button class="secondary-button !px-3" :disabled="page <= 1" @click="page--"><i class="pi pi-angle-left" /></button><span class="px-2 text-sm font-semibold">{{ page }} / {{ totalPages }}</span><button class="secondary-button !px-3" :disabled="page >= totalPages" @click="page++"><i class="pi pi-angle-right" /></button></div></div>
  </AppShell>
</template>
