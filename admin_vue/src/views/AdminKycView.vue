<script setup lang="ts">
import Button from 'primevue/button';
import Card from 'primevue/card';
import Column from 'primevue/column';
import DataTable from 'primevue/datatable';
import Dropdown from 'primevue/dropdown';
import InputText from 'primevue/inputtext';
import Tag from 'primevue/tag';
import Textarea from 'primevue/textarea';
import { computed, onMounted, ref } from 'vue';

import AppShell from '@/components/AppShell.vue';
import {
  describeAdminError,
  loadAdminPage,
  runAdminAction,
} from '@/lib/adminApi';
import type { AdminRow, AdminRowValue } from '@/lib/adminResources';
import type {
  DataTablePageEvent,
  DataTableSortEvent,
} from 'primevue/datatable';

const rows = ref<AdminRow[]>([]);
const totalRecords = ref(0);
const loading = ref(false);
const errorMessage = ref('');
const query = ref('');
const statusFilter = ref<string | null>(null);
const selected = ref<AdminRow | null>(null);

const first = ref(0);
const pageSize = ref(25);
const sortField = ref<string | null>(null);
const sortOrder = ref<1 | -1 | null>(null);

const decisionOutcome = ref<'approved' | 'rejected' | 'manual_review'>('approved');
const decisionReason = ref('');
const submittingDecision = ref(false);
const decisionMessage = ref('');
const decisionTone = ref<'success' | 'danger' | 'neutral'>('neutral');

const statusOptions = [
  { label: 'All statuses', value: null },
  { label: 'Pending', value: 'pending' },
  { label: 'Submitted', value: 'submitted' },
  { label: 'Manual review', value: 'manual_review' },
  { label: 'Approved', value: 'approved' },
  { label: 'Rejected', value: 'rejected' },
];

const outcomeOptions = [
  { label: 'Approve', value: 'approved' },
  { label: 'Reject', value: 'rejected' },
  { label: 'Send to manual review', value: 'manual_review' },
];

function isPresent(value: AdminRowValue) {
  return value !== null && value !== undefined && String(value).trim() !== '';
}

function getText(row: AdminRow, fields: string[], fallback = '—') {
  for (const field of fields) {
    const value = row[field];
    if (isPresent(value)) {
      return String(value);
    }
  }
  return fallback;
}

function statusClass(value: AdminRowValue) {
  const v = String(value ?? '').toLowerCase();
  if (['approved', 'verified', 'success', 'active'].includes(v)) {
    return 'border-emerald-200 bg-emerald-50 text-emerald-700';
  }
  if (['rejected', 'failed', 'blocked'].includes(v)) {
    return 'border-rose-200 bg-rose-50 text-rose-700';
  }
  if (['manual_review', 'pending', 'submitted', 'in_review'].includes(v)) {
    return 'border-amber-200 bg-amber-50 text-amber-700';
  }
  return 'border-slate-200 bg-slate-50 text-slate-700';
}

function formatDateTime(value: AdminRowValue) {
  if (!isPresent(value)) {
    return 'Not provided';
  }
  const date = new Date(String(value));
  return Number.isNaN(date.getTime())
    ? String(value)
    : new Intl.DateTimeFormat(undefined, {
        dateStyle: 'medium',
        timeStyle: 'short',
      }).format(date);
}

const filteredRows = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) return rows.value;
  return rows.value.filter((row) =>
    Object.values(row).some((v) =>
      String(v ?? '').toLowerCase().includes(q),
    ),
  );
});

const summary = computed(() => {
  const counts: Record<string, number> = {};
  for (const r of rows.value) {
    const s = String(r.status ?? '').toLowerCase() || 'unknown';
    counts[s] = (counts[s] ?? 0) + 1;
  }
  return [
    { label: 'Cases (total)', value: totalRecords.value, tone: 'neutral' as const },
    {
      label: 'Pending review (page)',
      value: (counts.pending ?? 0) + (counts.submitted ?? 0) + (counts.manual_review ?? 0),
      tone: 'warning' as const,
    },
    { label: 'Approved (page)', value: counts.approved ?? 0, tone: 'success' as const },
    { label: 'Rejected (page)', value: counts.rejected ?? 0, tone: 'danger' as const },
  ];
});

const summaryToneClass: Record<'neutral' | 'warning' | 'success' | 'danger', string> = {
  neutral: 'border-slate-200 bg-slate-50 text-slate-700',
  warning: 'border-amber-200 bg-amber-50 text-amber-800',
  success: 'border-emerald-200 bg-emerald-50 text-emerald-800',
  danger: 'border-rose-200 bg-rose-50 text-rose-800',
};

async function refreshCases() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const params = new URLSearchParams();
    if (statusFilter.value) {
      params.set('status', statusFilter.value);
    }
    params.set('limit', String(pageSize.value));
    params.set('offset', String(first.value));
    if (sortField.value) {
      params.set('sortBy', sortField.value);
      params.set('sortDir', sortOrder.value === 1 ? 'asc' : 'desc');
    }
    const endpoint = `/api/v1/admin/kyc/local-cases?${params.toString()}`;
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
  refreshCases();
}

function onSort(event: DataTableSortEvent) {
  sortField.value = (event.sortField as string | null) ?? null;
  sortOrder.value = (event.sortOrder as 1 | -1 | null) ?? null;
  first.value = 0;
  refreshCases();
}

function onFilterChange() {
  first.value = 0;
  refreshCases();
}

function selectCase(row: AdminRow) {
  selected.value = row;
  decisionReason.value = '';
  decisionOutcome.value = 'approved';
  decisionMessage.value = '';
  decisionTone.value = 'neutral';
}

function caseId(row: AdminRow | null) {
  if (!row) {
    return '';
  }
  return String(
    row.caseId ?? row.id ?? row.hoppaUserId ?? row.localUserId ?? '',
  );
}

async function submitDecision() {
  const id = caseId(selected.value);
  if (!id) {
    decisionMessage.value = 'No case selected.';
    decisionTone.value = 'danger';
    return;
  }
  submittingDecision.value = true;
  decisionMessage.value = '';
  try {
    await runAdminAction(
      'post',
      `/api/v1/admin/kyc/cases/${encodeURIComponent(id)}/decisions`,
      {
        outcome: decisionOutcome.value,
        reason: decisionReason.value.trim() || undefined,
      },
    );
    decisionMessage.value = `Decision (${decisionOutcome.value}) submitted.`;
    decisionTone.value = 'success';
    await refreshCases();
  } catch (err) {
    decisionMessage.value = describeAdminError(err);
    decisionTone.value = 'danger';
  } finally {
    submittingDecision.value = false;
  }
}

onMounted(() => {
  refreshCases();
});
</script>

<template>
  <AppShell>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-xl font-semibold text-slate-950">KYC Cases</h1>
          <p class="text-sm text-slate-500">
            Review verification cases and submit approve / reject / manual-review decisions.
          </p>
        </div>
        <div class="flex items-center gap-3">
          <Button icon="pi pi-refresh" label="Refresh" :loading="loading" @click="refreshCases" />
        </div>
      </div>
    </template>

    <div
      v-if="errorMessage"
      class="mb-5 rounded-lg border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800"
    >
      <p class="font-semibold">Backend error</p>
      <p class="mt-1">{{ errorMessage }}</p>
    </div>

    <section class="mb-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <div
        v-for="card in summary"
        :key="card.label"
        class="rounded-lg border px-4 py-3"
        :class="summaryToneClass[card.tone]"
      >
        <p class="text-xs font-semibold uppercase tracking-wide opacity-80">
          {{ card.label }}
        </p>
        <p class="mt-1 text-2xl font-semibold">{{ card.value }}</p>
      </div>
    </section>

    <section class="grid gap-6 xl:grid-cols-3">
      <Card class="xl:col-span-2">
        <template #title>
          <div class="flex flex-wrap items-center gap-3">
            <span>Cases</span>
            <span class="text-xs font-medium text-slate-500">
              {{ filteredRows.length }} visible
            </span>
          </div>
        </template>
        <template #content>
          <div class="mb-4 flex flex-wrap items-center gap-3">
            <span class="p-input-icon-left flex-1 min-w-[12rem]">
              <i class="pi pi-search" />
              <InputText
                v-model="query"
                placeholder="Search by name, email, ID…"
                class="w-full"
              />
            </span>
            <Dropdown
              v-model="statusFilter"
              :options="statusOptions"
              option-label="label"
              option-value="value"
              placeholder="Filter status"
              class="w-56"
              @change="onFilterChange"
            />
          </div>
          <DataTable
            :value="filteredRows"
            :loading="loading"
            data-key="caseId"
            scrollable
            scroll-height="60vh"
            selection-mode="single"
            :selection="selected"
            @row-select="(e) => selectCase(e.data)"
            lazy
            paginator
            :first="first"
            :rows="pageSize"
            :total-records="totalRecords"
            :rows-per-page-options="[10, 25, 50, 100]"
            paginator-template="FirstPageLink PrevPageLink CurrentPageReport NextPageLink LastPageLink RowsPerPageDropdown"
            current-page-report-template="{first}-{last} of {totalRecords}"
            removable-sort
            class="text-sm"
            @page="onPage"
            @sort="onSort"
          >
            <template #empty>
              <div class="px-2 py-10 text-center text-sm text-slate-500">
                No KYC cases match the current filters.
              </div>
            </template>
            <Column header="Customer" sortable :sort-field="'displayName'">
              <template #body="{ data }">
                <p class="font-medium text-slate-950">
                  {{ getText(data, ['displayName', 'fullName']) }}
                </p>
                <p class="text-xs text-slate-500">
                  {{ getText(data, ['email']) }}
                </p>
              </template>
            </Column>
            <Column header="Status" sortable :sort-field="'status'">
              <template #body="{ data }">
                <span
                  class="inline-flex rounded-md border px-2 py-1 text-xs font-semibold"
                  :class="statusClass(data.status)"
                >
                  {{ getText(data, ['status'], 'unknown') }}
                </span>
              </template>
            </Column>
            <Column field="level" header="Level" sortable />
            <Column field="provider" header="Provider" sortable />
            <Column field="countryCode" header="Country" sortable />
            <Column header="Submitted" sortable :sort-field="'submittedAt'">
              <template #body="{ data }">
                <span class="text-xs text-slate-600">
                  {{ formatDateTime(data.submittedAt ?? data.startedAt) }}
                </span>
              </template>
            </Column>
            <Column header="Reviewed" sortable :sort-field="'reviewedAt'">
              <template #body="{ data }">
                <span class="text-xs text-slate-600">
                  {{ formatDateTime(data.reviewedAt) }}
                </span>
              </template>
            </Column>
          </DataTable>
        </template>
      </Card>

      <Card>
        <template #title>Decision panel</template>
        <template #content>
          <div v-if="!selected" class="text-sm text-slate-500">
            Select a case from the table to record a decision.
          </div>
          <div v-else class="space-y-4">
            <div class="rounded-lg border border-slate-200 p-3">
              <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Selected case
              </p>
              <p class="mt-1 font-semibold text-slate-950">
                {{ getText(selected, ['displayName', 'fullName', 'email']) }}
              </p>
              <p class="mt-0.5 break-all font-mono text-xs text-slate-500">
                {{ caseId(selected) }}
              </p>
              <div class="mt-2 flex flex-wrap gap-2">
                <Tag :value="getText(selected, ['status'], 'unknown')" />
                <Tag v-if="selected.level" severity="info" :value="String(selected.level)" />
                <Tag v-if="selected.provider" severity="secondary" :value="String(selected.provider)" />
              </div>
            </div>

            <label class="block">
              <span class="mb-1 block text-xs font-semibold uppercase text-slate-500">
                Outcome
              </span>
              <Dropdown
                v-model="decisionOutcome"
                :options="outcomeOptions"
                option-label="label"
                option-value="value"
                class="w-full"
              />
            </label>
            <label class="block">
              <span class="mb-1 block text-xs font-semibold uppercase text-slate-500">
                Reason / notes
              </span>
              <Textarea
                v-model="decisionReason"
                rows="4"
                class="w-full"
                placeholder="Audit trail notes (optional)"
              />
            </label>
            <Button
              icon="pi pi-check"
              label="Submit decision"
              :loading="submittingDecision"
              class="w-full"
              @click="submitDecision"
            />
            <div
              v-if="decisionMessage"
              class="rounded-md border px-3 py-2 text-sm"
              :class="summaryToneClass[decisionTone]"
            >
              {{ decisionMessage }}
            </div>
          </div>
        </template>
      </Card>
    </section>
  </AppShell>
</template>
