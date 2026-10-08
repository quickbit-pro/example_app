<script setup lang="ts">
import Button from 'primevue/button';
import Calendar from 'primevue/calendar';
import Card from 'primevue/card';
import Column from 'primevue/column';
import DataTable from 'primevue/datatable';
import InputText from 'primevue/inputtext';
import { computed, onMounted, ref } from 'vue';

import AppShell from '@/components/AppShell.vue';
import { loadAdminRows } from '@/lib/adminApi';
import type { AdminRow, AdminRowValue } from '@/lib/adminResources';

const rows = ref<AdminRow[]>([]);
const loading = ref(false);
const errorMessage = ref('');

const userId = ref('');
const accountId = ref('');
const fromDate = ref<Date | null>(null);
const toDate = ref<Date | null>(null);

function isPresent(value: AdminRowValue) {
  return value !== null && value !== undefined && String(value).trim() !== '';
}

function getText(row: AdminRow, fields: string[], fallback = '—') {
  for (const field of fields) {
    const v = row[field];
    if (isPresent(v)) {
      return String(v);
    }
  }
  return fallback;
}

function formatDate(d: Date | null) {
  if (!d) return '';
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function formatDateTime(value: AdminRowValue) {
  if (!isPresent(value)) return '—';
  const d = new Date(String(value));
  return Number.isNaN(d.getTime())
    ? String(value)
    : new Intl.DateTimeFormat(undefined, {
        dateStyle: 'medium',
        timeStyle: 'short',
      }).format(d);
}

function formatAmount(row: AdminRow) {
  const amount = row.amount ?? row.value ?? row.totalAmount;
  const currency = row.currency ?? row.currencyCode ?? '';
  if (amount === null || amount === undefined || amount === '') return '—';
  const numeric = Number(amount);
  if (Number.isNaN(numeric)) return String(amount);
  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency',
      currency: String(currency || 'USD'),
      maximumFractionDigits: 2,
    }).format(numeric);
  } catch {
    return `${numeric.toFixed(2)} ${currency}`;
  }
}

function amountTone(row: AdminRow) {
  const amount = Number(row.amount ?? row.value ?? 0);
  if (Number.isNaN(amount) || amount === 0) return 'text-slate-700';
  return amount > 0 ? 'text-emerald-700' : 'text-rose-700';
}

function statusClass(value: AdminRowValue) {
  const v = String(value ?? '').toLowerCase();
  if (['settled', 'success', 'completed', 'cleared'].includes(v)) {
    return 'border-emerald-200 bg-emerald-50 text-emerald-700';
  }
  if (['failed', 'rejected', 'reversed', 'declined'].includes(v)) {
    return 'border-rose-200 bg-rose-50 text-rose-700';
  }
  if (['pending', 'authorized', 'processing', 'held'].includes(v)) {
    return 'border-amber-200 bg-amber-50 text-amber-700';
  }
  return 'border-slate-200 bg-slate-50 text-slate-700';
}

const totals = computed(() => {
  let credits = 0;
  let debits = 0;
  for (const r of rows.value) {
    const a = Number(r.amount ?? r.value ?? 0);
    if (Number.isNaN(a)) continue;
    if (a > 0) credits += a;
    else debits += Math.abs(a);
  }
  return [
    { label: 'Total transactions', value: rows.value.length },
    { label: 'Total credit (sum)', value: credits.toFixed(2) },
    { label: 'Total debit (sum)', value: debits.toFixed(2) },
  ];
});

async function refresh() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const params = new URLSearchParams();
    if (userId.value.trim()) params.set('userId', userId.value.trim());
    if (accountId.value.trim()) params.set('accountId', accountId.value.trim());
    if (fromDate.value) params.set('from', formatDate(fromDate.value));
    if (toDate.value) params.set('to', formatDate(toDate.value));
    params.set('limit', '500');
    const endpoint = `/api/v1/admin/transactions?${params.toString()}`;
    const result = await loadAdminRows(endpoint, []);
    rows.value = result.data;
    errorMessage.value = result.error ?? '';
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  refresh();
});
</script>

<template>
  <AppShell>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-xl font-semibold text-slate-950">Transactions</h1>
          <p class="text-sm text-slate-500">
            Account transactions across the platform. Scope by user, account, or date range.
          </p>
        </div>
        <Button icon="pi pi-refresh" label="Refresh" :loading="loading" @click="refresh" />
      </div>
    </template>

    <div
      v-if="errorMessage"
      class="mb-5 rounded-lg border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800"
    >
      <p class="font-semibold">Backend error</p>
      <p class="mt-1">{{ errorMessage }}</p>
    </div>

    <section class="mb-6 grid gap-3 sm:grid-cols-3">
      <div
        v-for="t in totals"
        :key="t.label"
        class="rounded-lg border border-slate-200 bg-white px-4 py-3"
      >
        <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
          {{ t.label }}
        </p>
        <p class="mt-1 text-2xl font-semibold text-slate-950">{{ t.value }}</p>
      </div>
    </section>

    <Card>
      <template #title>Transactions</template>
      <template #content>
        <div class="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4 lg:items-end">
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">User ID</span>
            <InputText v-model="userId" placeholder="Optional" />
          </label>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">Account ID</span>
            <InputText v-model="accountId" placeholder="Optional" />
          </label>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">From</span>
            <Calendar v-model="fromDate" date-format="yy-mm-dd" show-icon />
          </label>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">To</span>
            <Calendar v-model="toDate" date-format="yy-mm-dd" show-icon />
          </label>
          <div class="lg:col-span-4">
            <Button label="Apply filters" icon="pi pi-filter" @click="refresh" />
          </div>
        </div>

        <DataTable
          :value="rows"
          :loading="loading"
          scrollable
          scroll-height="60vh"
          paginator
          :rows="25"
          :rows-per-page-options="[10, 25, 50, 100]"
          paginator-template="FirstPageLink PrevPageLink CurrentPageReport NextPageLink LastPageLink RowsPerPageDropdown"
          current-page-report-template="{first}-{last} of {totalRecords}"
          removable-sort
          class="text-sm"
        >
          <template #empty>
            <div class="px-2 py-10 text-center text-sm text-slate-500">
              No transactions returned for the current filters.
            </div>
          </template>
          <Column header="When" sortable :sort-field="'bookedAt'">
            <template #body="{ data }">
              <span class="text-xs text-slate-700">
                {{ formatDateTime(data.bookedAt ?? data.createdAt ?? data.time) }}
              </span>
            </template>
          </Column>
          <Column header="Description" sortable :sort-field="'description'">
            <template #body="{ data }">
              <p class="font-medium text-slate-950">
                {{ getText(data, ['description', 'narrative', 'merchantName', 'reference']) }}
              </p>
              <p class="text-xs font-mono text-slate-500">
                {{ getText(data, ['transactionId', 'id']) }}
              </p>
            </template>
          </Column>
          <Column header="Account" sortable :sort-field="'accountId'">
            <template #body="{ data }">
              <span class="text-xs text-slate-700">
                {{ getText(data, ['accountId', 'account']) }}
              </span>
            </template>
          </Column>
          <Column header="User" sortable :sort-field="'userId'">
            <template #body="{ data }">
              <span class="text-xs text-slate-700">
                {{ getText(data, ['userId', 'hoppaUserId']) }}
              </span>
            </template>
          </Column>
          <Column header="Amount" body-class="text-right" sortable :sort-field="'amount'">
            <template #body="{ data }">
              <span class="font-mono text-sm font-semibold" :class="amountTone(data)">
                {{ formatAmount(data) }}
              </span>
            </template>
          </Column>
          <Column header="Status" sortable :sort-field="'status'">
            <template #body="{ data }">
              <span
                class="inline-flex rounded-md border px-2 py-1 text-xs font-semibold"
                :class="statusClass(data.status)"
              >
                {{ getText(data, ['status', 'state'], 'unknown') }}
              </span>
            </template>
          </Column>
        </DataTable>
      </template>
    </Card>
  </AppShell>
</template>
