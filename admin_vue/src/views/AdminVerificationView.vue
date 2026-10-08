<script setup lang="ts">
import { onMounted, ref, watch } from 'vue';
import AppShell from '@/components/AppShell.vue';
import StatusPill from '@/components/StatusPill.vue';
import { formatDateTime, relativeTime } from '@/lib/formatters';
import { operationsApi, type VerificationResponse } from '@/lib/operationsApi';

const type = ref('');
const status = ref('');
const loading = ref(true);
const error = ref('');
const result = ref<VerificationResponse>({ items: [], over24Hours: 0, pendingCount: 0, totalCount: 0 });

async function load() {
  loading.value = true;
  error.value = '';
  try { result.value = await operationsApi.verifications({ type: type.value || undefined, status: status.value || undefined }); }
  catch (caught) { error.value = caught instanceof Error ? caught.message : 'Verification cases could not be loaded.'; }
  finally { loading.value = false; }
}

watch([type, status], load);
onMounted(load);
</script>

<template>
  <AppShell>
    <div><h1 class="page-title">Verification</h1><p class="page-subtitle">Review identity and business verification workload in one place.</p></div>
    <section class="mt-7 grid gap-4 sm:grid-cols-3">
      <div class="metric-card"><div class="text-sm font-semibold text-slate-500">All cases</div><div class="mt-3 text-3xl font-bold text-slate-950">{{ result.totalCount }}</div></div>
      <div class="metric-card"><div class="text-sm font-semibold text-slate-500">Waiting for review</div><div class="mt-3 text-3xl font-bold text-amber-700">{{ result.pendingCount }}</div></div>
      <div class="metric-card"><div class="text-sm font-semibold text-slate-500">Waiting over 24h</div><div class="mt-3 text-3xl font-bold" :class="result.over24Hours ? 'text-red-700' : 'text-emerald-700'">{{ result.over24Hours }}</div></div>
    </section>
    <section class="mt-4 panel p-4"><div class="flex flex-col gap-3 sm:flex-row"><select v-model="type" class="field-control sm:min-w-48"><option value="">People and businesses</option><option value="individual">People · KYC</option><option value="business">Businesses · KYB</option></select><select v-model="status" class="field-control sm:min-w-48"><option value="">All statuses</option><option value="pending">Pending</option><option value="submitted">Submitted</option><option value="approved">Approved</option><option value="rejected">Rejected</option></select></div></section>
    <div v-if="error" class="mt-4 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{{ error }}</div>
    <div v-if="loading" class="mt-4 table-shell p-6"><div v-for="row in 5" :key="row" class="mb-4 h-14 animate-pulse rounded-xl bg-slate-100" /></div>
    <div v-else-if="result.items.length" class="mt-4 table-shell overflow-x-auto">
      <table class="data-table min-w-[900px]"><thead><tr><th>Customer</th><th>Verification</th><th>Status</th><th>Submitted</th><th>Waiting time</th><th></th></tr></thead><tbody>
        <tr v-for="item in result.items" :key="item.customerId" class="cursor-pointer" @click="$router.push(`/customers/${item.customerId}`)">
          <td><div class="font-semibold text-slate-950">{{ item.customerName }}</div><div class="mt-1 text-xs text-slate-500">{{ item.email }}</div></td>
          <td><div class="font-semibold text-slate-800">{{ item.verificationType }}</div><div v-if="item.level" class="mt-1 text-xs text-slate-500">{{ item.level }}</div></td>
          <td><StatusPill :label="item.status" /></td>
          <td>{{ formatDateTime(item.submittedAt) }}</td>
          <td>{{ item.submittedAt ? relativeTime(item.submittedAt) : 'Not submitted' }}</td>
          <td class="text-right"><i class="pi pi-angle-right text-slate-400" /></td>
        </tr>
      </tbody></table>
    </div>
    <div v-else class="empty-state mt-4"><i class="pi pi-shield text-3xl text-slate-400" /><div class="mt-4 font-semibold text-slate-900">No verification cases match these filters</div></div>
  </AppShell>
</template>
