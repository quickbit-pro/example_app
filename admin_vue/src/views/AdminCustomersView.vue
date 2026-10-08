<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AppShell from '@/components/AppShell.vue';
import ReminderDialog from '@/components/ReminderDialog.vue';
import StatusPill from '@/components/StatusPill.vue';
import { STAGES, STAGE_TONE_CLASS, hasReminder, stageInfo, stageLabel } from '@/lib/customerStages';
import { formatCurrency, formatDate, humanize, relativeTime } from '@/lib/formatters';
import { operationsApi, type CustomerListResponse } from '@/lib/operationsApi';

const route = useRoute();
const router = useRouter();
const search = ref('');
const type = ref('');
const attentionOnly = ref(route.query.attention === 'true');
const testAccounts = ref('');
const stage = ref(typeof route.query.stage === 'string' ? route.query.stage : '');
const since = ref(typeof route.query.since === 'string' ? route.query.since : '');
const loading = ref(true);
const error = ref('');
const notice = ref('');
const reminderOpen = ref(false);
const result = ref<CustomerListResponse>({ attentionCount: 0, items: [], totalCount: 0 });
let timer: ReturnType<typeof setTimeout> | undefined;

const counts = computed(() => new Map((result.value.stageCounts ?? []).map(item => [item.stage, item.count])));
const selectedStage = computed(() => stageInfo(stage.value));

async function load() {
  loading.value = true;
  error.value = '';
  try {
    result.value = await operationsApi.customers({
      attention: attentionOnly.value || undefined,
      limit: 100,
      q: search.value || undefined,
      since: since.value || undefined,
      stage: stage.value || undefined,
      testAccounts: testAccounts.value || undefined,
      type: type.value || undefined,
    });
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'Customers could not be loaded.';
  } finally {
    loading.value = false;
  }
}
function syncQuery() {
  const query: Record<string, string> = {};
  if (stage.value) query.stage = stage.value;
  if (since.value) query.since = since.value;
  if (attentionOnly.value) query.attention = 'true';
  router.replace({ path: '/customers', query });
}
function chooseStage(value: string) { stage.value = stage.value === value ? '' : value; }
function reminderSent(queued: number) {
  reminderOpen.value = false;
  notice.value = queued === 1 ? '1 reminder email was queued.' : `${queued.toLocaleString()} reminder emails were queued.`;
  void load();
}
function clearFilters() { search.value = ''; type.value = ''; testAccounts.value = ''; attentionOnly.value = false; stage.value = ''; since.value = ''; }

watch([search, type, attentionOnly, testAccounts, stage, since], () => {
  notice.value = '';
  syncQuery();
  clearTimeout(timer);
  timer = setTimeout(load, 250);
});
onBeforeUnmount(() => clearTimeout(timer));
onMounted(load);
</script>

<template>
  <AppShell>
    <div>
      <h1 class="page-title">Customers</h1>
      <p class="page-subtitle">Find customers, see where they are in the journey, and help them move forward.</p>
    </div>

    <section class="mt-7 panel p-4">
      <div class="flex flex-col gap-3 lg:flex-row">
        <label class="relative flex-1">
          <i class="pi pi-search absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" />
          <input v-model="search" class="field-control w-full pl-11" placeholder="Search by name, email or phone" />
        </label>
        <select v-model="type" class="field-control min-w-44">
          <option value="">People and businesses</option>
          <option value="individual">People</option>
          <option value="business">Businesses</option>
        </select>
        <select v-model="testAccounts" class="field-control min-w-44" aria-label="Test accounts">
          <option value="">All accounts</option>
          <option value="exclude">Hide test accounts</option>
          <option value="only">Only test accounts</option>
        </select>
        <button
          class="secondary-button"
          :class="attentionOnly ? '!border-amber-300 !bg-amber-50 !text-amber-800' : ''"
          @click="attentionOnly = !attentionOnly"
        >
          <i class="pi pi-exclamation-circle" />Needs attention
        </button>
      </div>
      <div class="mt-3 flex flex-wrap gap-2" role="group" aria-label="Journey stage">
        <button v-for="item in STAGES" :key="item.key" type="button" :title="item.description"
          class="inline-flex min-h-8 items-center gap-2 rounded-lg border px-2.5 text-xs font-semibold transition"
          :class="stage === item.key ? 'border-blue-400 bg-blue-50 text-blue-800' : 'border-slate-200 bg-white text-slate-700 hover:bg-slate-50'"
          :aria-pressed="stage === item.key" @click="chooseStage(item.key)">
          {{ item.label }}<span class="rounded-md px-1.5 py-0.5 tabular-nums" :class="STAGE_TONE_CLASS[item.tone]">{{ (counts.get(item.key) ?? 0).toLocaleString() }}</span>
        </button>
        <button v-if="since" type="button" class="inline-flex min-h-8 items-center gap-2 rounded-lg border border-blue-400 bg-blue-50 px-2.5 text-xs font-semibold text-blue-800" @click="since = ''">
          Signed up since {{ formatDate(since) }}<i class="pi pi-times text-[10px]" />
        </button>
      </div>
    </section>

    <section v-if="selectedStage" class="mt-4 flex flex-col gap-3 rounded-2xl border border-blue-200 bg-blue-50 p-4 text-blue-950 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <div class="font-bold">{{ selectedStage.label }} · {{ result.totalCount.toLocaleString() }} {{ result.totalCount === 1 ? 'customer' : 'customers' }}</div>
        <div class="mt-0.5 text-sm text-blue-900/80">{{ selectedStage.description }}</div>
      </div>
      <button v-if="hasReminder(stage)" type="button" class="primary-button" :disabled="!result.totalCount" @click="reminderOpen = true">
        <i class="pi pi-send" />Send “{{ selectedStage.reminder }}” reminder
      </button>
    </section>
    <div v-if="notice" class="mt-4 rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm font-semibold text-emerald-800">{{ notice }}</div>

    <div class="mt-4 flex items-center justify-between">
      <div class="text-sm font-semibold text-slate-700">
        <span v-if="attentionOnly">{{ result.totalCount }} customers need attention</span>
        <span v-else>{{ result.totalCount }} customers · {{ result.attentionCount }} need attention</span>
      </div>
      <div class="text-xs text-slate-500">No technical identifiers shown</div>
    </div>

    <div v-if="error" class="mt-4 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
      {{ error }} <button class="ml-2 font-semibold underline" @click="load">Try again</button>
    </div>

    <div v-if="loading" class="mt-4 table-shell p-6">
      <div v-for="row in 6" :key="row" class="mb-4 h-14 animate-pulse rounded-xl bg-slate-100 last:mb-0" />
    </div>

    <div v-else-if="result.items.length" class="mt-4 table-shell overflow-x-auto">
      <table class="data-table min-w-[1200px]">
        <thead><tr><th>Customer</th><th>Stage</th><th>Onboarding</th><th>Verification</th><th>Balances</th><th>Cards</th><th>Last activity</th><th>Attention</th></tr></thead>
        <tbody>
          <tr v-for="customer in result.items" :key="customer.customerId" class="cursor-pointer" @click="$router.push(`/customers/${customer.customerId}`)">
            <td>
              <div class="flex items-center gap-2 font-semibold text-slate-950">{{ customer.name }}<span v-if="customer.isTestAccount" class="rounded-md bg-violet-50 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-violet-700">Test</span></div>
              <div class="mt-1 text-xs text-slate-500">{{ customer.email }}</div>
            </td>
            <td><span class="inline-flex whitespace-nowrap rounded-lg px-2 py-1 text-xs font-semibold" :class="STAGE_TONE_CLASS[stageInfo(customer.stage)?.tone ?? 'neutral']" :title="stageInfo(customer.stage)?.description">{{ stageLabel(customer.stage) }}</span></td>
            <td>
              <StatusPill :label="customer.onboardingStatus" />
              <div class="mt-1.5 text-xs text-slate-500">{{ humanize(customer.onboardingStep) }}</div>
            </td>
            <td><StatusPill :label="customer.verificationStatus" /></td>
            <td>
              <div v-if="customer.balances.length" class="space-y-1">
                <div v-for="balance in customer.balances.slice(0, 2)" :key="balance.currency" class="whitespace-nowrap text-xs font-semibold text-slate-700">{{ formatCurrency(balance.amount, balance.currency) }}</div>
              </div>
              <span v-else class="text-xs text-slate-400">Not available</span>
            </td>
            <td><span class="font-semibold text-slate-900">{{ customer.activeCards }}</span><span class="text-xs text-slate-400"> / {{ customer.totalCards }}</span></td>
            <td class="whitespace-nowrap">{{ relativeTime(customer.lastActivityAt) }}</td>
            <td>
              <span v-if="customer.attentionReason" class="inline-flex max-w-52 items-center gap-2 rounded-xl px-2.5 py-2 text-xs font-semibold" :class="customer.attentionTone === 'danger' ? 'bg-red-50 text-red-700' : 'bg-amber-50 text-amber-700'">
                <i class="pi pi-exclamation-circle" />{{ customer.attentionReason }}
              </span>
              <span v-else class="inline-flex items-center gap-2 text-xs font-semibold text-emerald-700"><i class="pi pi-check-circle" />Healthy</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-else class="empty-state mt-4">
      <div class="grid size-12 place-items-center rounded-full bg-slate-100 text-slate-500"><i class="pi pi-users text-xl" /></div>
      <div class="mt-4 font-semibold text-slate-900">No customers match these filters</div>
      <div class="mt-1 text-sm text-slate-500">Clear the search, the stage or the customer type.</div>
      <button class="secondary-button mt-4" @click="clearFilters">Clear filters</button>
    </div>

    <ReminderDialog v-if="reminderOpen && stage" :stage="stage" @close="reminderOpen = false" @sent="reminderSent" />
  </AppShell>
</template>
