<script setup lang="ts">
import Button from 'primevue/button';
import Calendar from 'primevue/calendar';
import Card from 'primevue/card';
import Column from 'primevue/column';
import DataTable, {
  type DataTablePageEvent,
  type DataTableSortEvent,
} from 'primevue/datatable';
import Dialog from 'primevue/dialog';
import InputText from 'primevue/inputtext';
import Select from 'primevue/select';
import { onMounted, ref } from 'vue';

import AppShell from '@/components/AppShell.vue';
import { describeAdminError, loadAdminPage } from '@/lib/adminApi';
import { apiClient } from '@/lib/apiClient';
import type { AdminRow, AdminRowValue } from '@/lib/adminResources';

interface FlowDetail {
  id: string;
  time: string;
  traceId?: string | null;
  actorUserId?: string | null;
  ipAddress?: string | null;
  userAgent?: string | null;
  direction?: string | null;
  result: string;
  failureCode?: string | null;
  failureMessage?: string | null;
  app: {
    method: string;
    path: string;
    queryString?: string | null;
    statusCode?: number | null;
    request?: unknown;
    response?: unknown;
  };
  hoppa: {
    method: string;
    endpoint: string;
    queryString?: string | null;
    statusCode?: number | null;
    durationMs: number;
    request?: unknown;
    response?: unknown;
  };
}

const rows = ref<AdminRow[]>([]);
const totalRecords = ref(0);
const loading = ref(false);
const errorMessage = ref('');

const appPath = ref('');
const hoppaEndpoint = ref('');
const direction = ref('');
const result = ref('');
const fromDate = ref<Date | null>(null);
const toDate = ref<Date | null>(null);

const first = ref(0);
const pageSize = ref(25);
const sortField = ref<string | null>(null);
const sortOrder = ref<1 | -1 | null>(null);

const detailVisible = ref(false);
const detailLoading = ref(false);
const detailError = ref('');
const detail = ref<FlowDetail | null>(null);

const resultOptions = [
  { label: 'All results', value: '' },
  { label: 'Success', value: 'success' },
  { label: 'Failed', value: 'failed' },
];

const directionOptions = [
  { label: 'All traffic', value: '' },
  { label: 'Outbound API calls', value: 'outbound' },
  { label: 'Incoming webhooks', value: 'inbound_webhook' },
];

function isPresent(value: AdminRowValue) {
  return value !== null && value !== undefined && String(value).trim() !== '';
}

function getText(row: AdminRow, fields: string[], fallback = '-') {
  for (const field of fields) {
    if (isPresent(row[field])) return String(row[field]);
  }
  return fallback;
}

function formatDate(date: Date | null) {
  if (!date) return '';
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function formatDateTime(value: AdminRowValue) {
  if (!isPresent(value)) return '-';
  const date = new Date(String(value));
  return Number.isNaN(date.getTime())
    ? String(value)
    : new Intl.DateTimeFormat(undefined, {
        dateStyle: 'medium',
        timeStyle: 'medium',
      }).format(date);
}

function resultClass(value: AdminRowValue) {
  return String(value ?? '').toLowerCase() === 'success'
    ? 'border-emerald-200 bg-emerald-50 text-emerald-700'
    : 'border-rose-200 bg-rose-50 text-rose-700';
}

function directionLabel(value: AdminRowValue) {
  return String(value ?? '') === 'inbound_webhook' ? 'Webhook' : 'API call';
}

function directionClass(value: AdminRowValue) {
  return String(value ?? '') === 'inbound_webhook'
    ? 'border-sky-200 bg-sky-50 text-sky-700'
    : 'border-slate-200 bg-slate-50 text-slate-700';
}

function statusClass(status: AdminRowValue) {
  const value = Number(status);
  if (!Number.isFinite(value)) return 'text-slate-500';
  if (value >= 200 && value < 300) return 'text-emerald-700';
  if (value >= 400) return 'text-rose-700';
  return 'text-amber-700';
}

function buildEndpoint() {
  const params = new URLSearchParams();
  if (appPath.value.trim()) params.set('appPath', appPath.value.trim());
  if (hoppaEndpoint.value.trim()) params.set('hoppaEndpoint', hoppaEndpoint.value.trim());
  if (direction.value) params.set('direction', direction.value);
  if (result.value) params.set('result', result.value);
  if (fromDate.value) params.set('from', formatDate(fromDate.value));
  if (toDate.value) params.set('to', formatDate(toDate.value));
  params.set('limit', String(pageSize.value));
  params.set('offset', String(first.value));
  if (sortField.value) {
    params.set('sortBy', sortField.value);
    params.set('sortDir', sortOrder.value === 1 ? 'asc' : 'desc');
  }
  return `/api/v1/admin/hoppa-logs?${params.toString()}`;
}

async function refresh() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const response = await loadAdminPage(buildEndpoint());
    rows.value = response.data.rows;
    totalRecords.value = response.data.totalCount;
    errorMessage.value = response.error ?? '';
  } finally {
    loading.value = false;
  }
}

function onPage(event: DataTablePageEvent) {
  first.value = event.first;
  pageSize.value = event.rows;
  refresh();
}

function onSort(event: DataTableSortEvent) {
  sortField.value = (event.sortField as string | null) ?? null;
  sortOrder.value = (event.sortOrder as 1 | -1 | null) ?? null;
  first.value = 0;
  refresh();
}

function applyFilters() {
  first.value = 0;
  refresh();
}

async function viewLog(row: AdminRow) {
  const id = String(row.id ?? '');
  if (!id) return;
  detailVisible.value = true;
  detailLoading.value = true;
  detailError.value = '';
  detail.value = null;
  try {
    const { data } = await apiClient.get<FlowDetail>(
      `/api/v1/admin/hoppa-logs/${encodeURIComponent(id)}`,
    );
    detail.value = data;
  } catch (error) {
    detailError.value = describeAdminError(error);
  } finally {
    detailLoading.value = false;
  }
}

function pretty(value: unknown) {
  if (value === null || value === undefined || value === '') return '-';
  if (typeof value === 'string') {
    try {
      return JSON.stringify(JSON.parse(value), null, 2);
    } catch {
      return value;
    }
  }
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

onMounted(refresh);
</script>

<template>
  <AppShell>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-xl font-semibold text-slate-950">Hoppa API Logs</h1>
          <p class="text-sm text-slate-500">
            Outbound Hoppa API calls and incoming Hoppa webhook request/response traces.
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

    <Card>
      <template #title>Call Flow</template>
      <template #content>
        <div class="mb-4 grid gap-3 md:grid-cols-2 xl:grid-cols-7 xl:items-end">
          <label class="flex flex-col xl:col-span-2">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">App endpoint</span>
            <InputText v-model="appPath" placeholder="/api/v1/mobile/cards or /api/v1/webhooks/hoppa" />
          </label>
          <label class="flex flex-col xl:col-span-2">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">Hoppa endpoint / event</span>
            <InputText v-model="hoppaEndpoint" placeholder="/api/v2/cards or card.created" />
          </label>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">Direction</span>
            <Select v-model="direction" :options="directionOptions" option-label="label" option-value="value" />
          </label>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">Result</span>
            <Select v-model="result" :options="resultOptions" option-label="label" option-value="value" />
          </label>
          <div>
            <Button label="Apply filters" icon="pi pi-filter" class="w-full" @click="applyFilters" />
          </div>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">From</span>
            <Calendar v-model="fromDate" date-format="yy-mm-dd" show-icon />
          </label>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">To</span>
            <Calendar v-model="toDate" date-format="yy-mm-dd" show-icon />
          </label>
        </div>

        <DataTable
          :value="rows"
          :loading="loading"
          scrollable
          scroll-height="65vh"
          lazy
          paginator
          :first="first"
          :rows="pageSize"
          :total-records="totalRecords"
          :rows-per-page-options="[10, 25, 50, 100, 200]"
          paginator-template="FirstPageLink PrevPageLink CurrentPageReport NextPageLink LastPageLink RowsPerPageDropdown"
          current-page-report-template="{first}-{last} of {totalRecords}"
          removable-sort
          class="text-sm"
          @row-click="(event) => viewLog(event.data)"
          @page="onPage"
          @sort="onSort"
        >
          <template #empty>
            <div class="px-2 py-10 text-center text-sm text-slate-500">
              No Hoppa API logs match the current filters.
            </div>
          </template>
          <Column header="Time" sortable :sort-field="'time'">
            <template #body="{ data }">
              <span class="font-mono text-xs text-slate-700">
                {{ formatDateTime(data.time) }}
              </span>
            </template>
          </Column>
          <Column header="Type" sortable :sort-field="'direction'">
            <template #body="{ data }">
              <span
                class="inline-flex rounded-md border px-2 py-1 text-xs font-semibold"
                :class="directionClass(data.direction)"
              >
                {{ directionLabel(data.direction) }}
              </span>
            </template>
          </Column>
          <Column header="App endpoint" sortable :sort-field="'appEndpoint'">
            <template #body="{ data }">
              <span class="font-mono text-xs text-slate-800">
                {{ getText(data, ['appEndpoint']) }}
              </span>
            </template>
          </Column>
          <Column header="App status" sortable :sort-field="'appStatus'">
            <template #body="{ data }">
              <span class="font-mono text-xs font-semibold" :class="statusClass(data.appStatus)">
                {{ getText(data, ['appStatus']) }}
              </span>
            </template>
          </Column>
          <Column header="Hoppa endpoint / event" sortable :sort-field="'hoppaEndpoint'">
            <template #body="{ data }">
              <span class="font-mono text-xs text-slate-800">
                {{ getText(data, ['hoppaEndpoint']) }}
              </span>
            </template>
          </Column>
          <Column header="Hoppa status" sortable :sort-field="'hoppaStatus'">
            <template #body="{ data }">
              <span class="font-mono text-xs font-semibold" :class="statusClass(data.hoppaStatus)">
                {{ getText(data, ['hoppaStatus']) }}
              </span>
            </template>
          </Column>
          <Column header="Duration" sortable :sort-field="'duration'">
            <template #body="{ data }">
              <span class="font-mono text-xs text-slate-700">
                {{ getText(data, ['duration']) }} ms
              </span>
            </template>
          </Column>
          <Column header="Result" sortable :sort-field="'result'">
            <template #body="{ data }">
              <span
                class="inline-flex rounded-md border px-2 py-1 text-xs font-semibold"
                :class="resultClass(data.result)"
              >
                {{ getText(data, ['result'], 'unknown') }}
              </span>
            </template>
          </Column>
          <Column header="Trace" sortable :sort-field="'traceId'">
            <template #body="{ data }">
              <span class="font-mono text-xs text-slate-500">
                {{ getText(data, ['traceId']) }}
              </span>
            </template>
          </Column>
        </DataTable>
      </template>
    </Card>

    <Dialog
      v-model:visible="detailVisible"
      modal
      header="Hoppa call flow"
      :style="{ width: 'min(1100px, 96vw)' }"
    >
      <div v-if="detailLoading" class="px-2 py-6 text-center text-sm text-slate-500">
        Loading call flow...
      </div>
      <div
        v-else-if="detailError"
        class="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800"
      >
        {{ detailError }}
      </div>
      <div v-else-if="detail" class="space-y-4 text-sm">
        <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Time</p>
            <p class="font-mono text-slate-800">{{ formatDateTime(detail.time) }}</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Type</p>
            <p class="font-semibold text-slate-900">{{ directionLabel(detail.direction) }}</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Result</p>
            <p class="font-semibold capitalize text-slate-900">{{ detail.result }}</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Trace ID</p>
            <p class="font-mono text-slate-800">{{ detail.traceId ?? '-' }}</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Actor user ID</p>
            <p class="font-mono text-slate-800">{{ detail.actorUserId ?? '-' }}</p>
          </div>
        </div>

        <div
          v-if="detail.failureCode || detail.failureMessage"
          class="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800"
        >
          <p class="font-semibold">{{ detail.failureCode ?? 'Hoppa failure' }}</p>
          <p class="mt-1">{{ detail.failureMessage }}</p>
        </div>

        <div class="grid gap-4 xl:grid-cols-2">
          <section>
            <div class="mb-2 flex items-center justify-between gap-3">
              <p class="text-xs font-semibold uppercase text-slate-500">App request</p>
              <p class="font-mono text-xs text-slate-700">
                {{ detail.app.method }} {{ detail.app.path }}{{ detail.app.queryString ?? '' }}
              </p>
            </div>
            <pre class="max-h-80 overflow-auto rounded-md border border-slate-200 bg-slate-950 p-3 text-xs text-emerald-200">{{ pretty(detail.app.request) }}</pre>
          </section>
          <section>
            <div class="mb-2 flex items-center justify-between gap-3">
              <p class="text-xs font-semibold uppercase text-slate-500">
                {{ detail.direction === 'inbound_webhook' ? 'Incoming Hoppa webhook' : 'Hoppa request' }}
              </p>
              <p class="font-mono text-xs text-slate-700">
                {{ detail.hoppa.method }} {{ detail.hoppa.endpoint }}{{ detail.hoppa.queryString ?? '' }}
              </p>
            </div>
            <pre class="max-h-80 overflow-auto rounded-md border border-slate-200 bg-slate-950 p-3 text-xs text-emerald-200">{{ pretty(detail.hoppa.request) }}</pre>
          </section>
          <section>
            <div class="mb-2 flex items-center justify-between gap-3">
              <p class="text-xs font-semibold uppercase text-slate-500">
                {{ detail.direction === 'inbound_webhook' ? 'Webhook log result' : 'Hoppa response' }}
              </p>
              <p class="font-mono text-xs" :class="statusClass(detail.hoppa.statusCode)">
                {{ detail.hoppa.statusCode ?? '-' }} in {{ detail.hoppa.durationMs }} ms
              </p>
            </div>
            <pre class="max-h-80 overflow-auto rounded-md border border-slate-200 bg-slate-950 p-3 text-xs text-emerald-200">{{ pretty(detail.hoppa.response) }}</pre>
          </section>
          <section>
            <div class="mb-2 flex items-center justify-between gap-3">
              <p class="text-xs font-semibold uppercase text-slate-500">App response</p>
              <p class="font-mono text-xs" :class="statusClass(detail.app.statusCode)">
                {{ detail.app.statusCode ?? '-' }}
              </p>
            </div>
            <pre class="max-h-80 overflow-auto rounded-md border border-slate-200 bg-slate-950 p-3 text-xs text-emerald-200">{{ pretty(detail.app.response) }}</pre>
          </section>
        </div>

        <div class="grid gap-4 md:grid-cols-2">
          <div>
            <p class="mb-1 text-xs font-semibold uppercase text-slate-500">IP address</p>
            <p class="font-mono text-slate-800">{{ detail.ipAddress ?? '-' }}</p>
          </div>
          <div>
            <p class="mb-1 text-xs font-semibold uppercase text-slate-500">User agent</p>
            <p class="break-all rounded-md border border-slate-200 bg-slate-50 px-3 py-2 font-mono text-xs text-slate-700">
              {{ detail.userAgent ?? '-' }}
            </p>
          </div>
        </div>
      </div>
    </Dialog>
  </AppShell>
</template>
