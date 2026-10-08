<script setup lang="ts">
import Button from 'primevue/button';
import Calendar from 'primevue/calendar';
import Card from 'primevue/card';
import Column from 'primevue/column';
import DataTable from 'primevue/datatable';
import Dialog from 'primevue/dialog';
import InputText from 'primevue/inputtext';
import { onMounted, ref } from 'vue';

import AppShell from '@/components/AppShell.vue';
import { describeAdminError, loadAdminPage } from '@/lib/adminApi';
import { apiClient } from '@/lib/apiClient';
import type { AdminRow, AdminRowValue } from '@/lib/adminResources';
import type {
  DataTablePageEvent,
  DataTableSortEvent,
} from 'primevue/datatable';

const rows = ref<AdminRow[]>([]);
const totalRecords = ref(0);
const loading = ref(false);
const errorMessage = ref('');

const actorUserId = ref('');
const entityType = ref('');
const fromDate = ref<Date | null>(null);
const toDate = ref<Date | null>(null);

const first = ref(0);
const pageSize = ref(25);
const sortField = ref<string | null>(null);
const sortOrder = ref<1 | -1 | null>(null);

const detailVisible = ref(false);
const detailLoading = ref(false);
const detailError = ref('');
const detail = ref<Record<string, unknown> | null>(null);

function isPresent(value: AdminRowValue) {
  return value !== null && value !== undefined && String(value).trim() !== '';
}

function getText(row: AdminRow, fields: string[], fallback = '—') {
  for (const f of fields) {
    if (isPresent(row[f])) return String(row[f]);
  }
  return fallback;
}

function formatDate(d: Date | null) {
  if (!d) return '';
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function formatDateTime(value: AdminRowValue) {
  if (!isPresent(value)) return '—';
  const d = new Date(String(value));
  return Number.isNaN(d.getTime())
    ? String(value)
    : new Intl.DateTimeFormat(undefined, {
        dateStyle: 'medium',
        timeStyle: 'medium',
      }).format(d);
}

function resultClass(value: AdminRowValue) {
  const v = String(value ?? '').toLowerCase();
  if (v === 'success') {
    return 'border-emerald-200 bg-emerald-50 text-emerald-700';
  }
  if (v === 'failed') {
    return 'border-rose-200 bg-rose-50 text-rose-700';
  }
  return 'border-slate-200 bg-slate-50 text-slate-700';
}

async function refresh() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const params = new URLSearchParams();
    if (actorUserId.value.trim()) params.set('actorUserId', actorUserId.value.trim());
    if (entityType.value.trim()) params.set('entityType', entityType.value.trim());
    if (fromDate.value) params.set('from', formatDate(fromDate.value));
    if (toDate.value) params.set('to', formatDate(toDate.value));
    params.set('limit', String(pageSize.value));
    params.set('offset', String(first.value));
    if (sortField.value) {
      params.set('sortBy', sortField.value);
      params.set('sortDir', sortOrder.value === 1 ? 'asc' : 'desc');
    }
    const endpoint = `/api/v1/admin/audit/events?${params.toString()}`;
    const result = await loadAdminPage(endpoint);
    rows.value = result.data.rows;
    totalRecords.value = result.data.totalCount;
    errorMessage.value = result.error ?? '';
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

async function viewEvent(row: AdminRow) {
  const id = String(row.id ?? '');
  if (!id) return;
  detailVisible.value = true;
  detailLoading.value = true;
  detailError.value = '';
  detail.value = null;
  try {
    const { data } = await apiClient.get<Record<string, unknown>>(
      `/api/v1/admin/audit/events/${encodeURIComponent(id)}`,
    );
    detail.value = data;
  } catch (err) {
    detailError.value = describeAdminError(err);
  } finally {
    detailLoading.value = false;
  }
}

function pretty(value: unknown) {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return JSON.stringify(parsed, null, 2);
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

onMounted(() => {
  refresh();
});
</script>

<template>
  <AppShell>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-xl font-semibold text-slate-950">Audit Log</h1>
          <p class="text-sm text-slate-500">
            Read-only stream of admin actions, with filters by actor, entity, and date range.
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
      <template #title>Events</template>
      <template #content>
        <div class="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-5 lg:items-end">
          <label class="flex flex-col lg:col-span-2">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">Actor user ID</span>
            <InputText v-model="actorUserId" placeholder="GUID" />
          </label>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">Entity type</span>
            <InputText v-model="entityType" placeholder="e.g. user, kyc" />
          </label>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">From</span>
            <Calendar v-model="fromDate" date-format="yy-mm-dd" show-icon />
          </label>
          <label class="flex flex-col">
            <span class="mb-1 text-xs font-semibold uppercase text-slate-500">To</span>
            <Calendar v-model="toDate" date-format="yy-mm-dd" show-icon />
          </label>
          <div class="lg:col-span-5">
            <Button label="Apply filters" icon="pi pi-filter" @click="applyFilters" />
          </div>
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
          @row-click="(e) => viewEvent(e.data)"
          @page="onPage"
          @sort="onSort"
        >
          <template #empty>
            <div class="px-2 py-10 text-center text-sm text-slate-500">
              No audit events match the current filters.
            </div>
          </template>
          <Column header="Time" sortable :sort-field="'time'">
            <template #body="{ data }">
              <span class="font-mono text-xs text-slate-700">
                {{ formatDateTime(data.time) }}
              </span>
            </template>
          </Column>
          <Column header="Actor" sortable :sort-field="'actor'">
            <template #body="{ data }">
              <span class="font-mono text-xs text-slate-700">
                {{ getText(data, ['actor']) }}
              </span>
            </template>
          </Column>
          <Column header="Action" sortable :sort-field="'action'">
            <template #body="{ data }">
              <span class="font-medium text-slate-950">
                {{ getText(data, ['action']) }}
              </span>
            </template>
          </Column>
          <Column header="Target" sortable :sort-field="'target'">
            <template #body="{ data }">
              <span class="text-slate-700">
                {{ getText(data, ['target']) }}
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
      header="Audit event"
      :style="{ width: 'min(900px, 95vw)' }"
    >
      <div v-if="detailLoading" class="px-2 py-6 text-center text-sm text-slate-500">
        Loading event…
      </div>
      <div
        v-else-if="detailError"
        class="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800"
      >
        {{ detailError }}
      </div>
      <div v-else-if="detail" class="space-y-4 text-sm">
        <div class="grid gap-3 sm:grid-cols-2">
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Time</p>
            <p class="font-mono text-slate-800">{{ formatDateTime(detail.time as AdminRowValue) }}</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Actor</p>
            <p class="font-mono text-slate-800">{{ String(detail.actor ?? '—') }}</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Action</p>
            <p class="font-medium text-slate-900">{{ String(detail.action ?? '—') }}</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Target</p>
            <p class="text-slate-800">{{ String(detail.target ?? '—') }}</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">IP address</p>
            <p class="font-mono text-slate-800">{{ String(detail.ipAddress ?? '—') }}</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-slate-500">Trace ID</p>
            <p class="font-mono text-slate-800">{{ String(detail.traceId ?? '—') }}</p>
          </div>
        </div>
        <div>
          <p class="mb-1 text-xs font-semibold uppercase text-slate-500">User agent</p>
          <p class="break-all rounded-md border border-slate-200 bg-slate-50 px-3 py-2 font-mono text-xs text-slate-700">
            {{ String(detail.userAgent ?? '—') }}
          </p>
        </div>
        <div class="grid gap-4 lg:grid-cols-2">
          <div>
            <p class="mb-1 text-xs font-semibold uppercase text-slate-500">Before</p>
            <pre class="max-h-72 overflow-auto rounded-md border border-slate-200 bg-slate-950 p-3 text-xs text-emerald-200">{{ pretty(detail.before) }}</pre>
          </div>
          <div>
            <p class="mb-1 text-xs font-semibold uppercase text-slate-500">After</p>
            <pre class="max-h-72 overflow-auto rounded-md border border-slate-200 bg-slate-950 p-3 text-xs text-emerald-200">{{ pretty(detail.after) }}</pre>
          </div>
        </div>
        <div>
          <p class="mb-1 text-xs font-semibold uppercase text-slate-500">Metadata</p>
          <pre class="max-h-72 overflow-auto rounded-md border border-slate-200 bg-slate-950 p-3 text-xs text-emerald-200">{{ pretty(detail.metadata) }}</pre>
        </div>
      </div>
    </Dialog>
  </AppShell>
</template>
