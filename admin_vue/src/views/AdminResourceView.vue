<script setup lang="ts">
import Button from 'primevue/button';
import Card from 'primevue/card';
import Column from 'primevue/column';
import DataTable, {
  type DataTablePageEvent,
  type DataTableSortEvent,
} from 'primevue/datatable';
import { computed, onMounted, ref } from 'vue';

import AppShell from '@/components/AppShell.vue';
import { apiClient } from '@/lib/apiClient';
import { loadAdminPage, loadAdminRows } from '@/lib/adminApi';
import { adminResources, type AdminRow, type AdminRowValue } from '@/lib/adminResources';

const rows = ref<AdminRow[]>([]);
const totalRecords = ref(0);
const loading = ref(false);
const backendError = ref('');
const query = ref('');
const selectedStatus = ref('');

const first = ref(0);
const pageSize = ref(25);
const sortField = ref<string | null>(null);
const sortOrder = ref<1 | -1 | null>(null);

// Track whether server-side paging is active. When the user types a search
// query we fall back to the search endpoint which is not paged.
const searchMode = computed(() => query.value.trim().length > 0);

const usersResource = adminResources.users;

const counts = computed(() => {
  const needsReview = rows.value.filter((row) => {
    const status = String(
      row.kycStatus ?? row.verificationStatus ?? row.status ?? '',
    ).toLowerCase();
    return ['manual', 'pending', 'review', 'rejected'].some((token) =>
      status.includes(token),
    );
  }).length;

  return [
    { label: 'Customers (total)', value: searchMode.value ? rows.value.length : totalRecords.value },
    {
      label: 'KYC approved (page)',
      value: rows.value.filter((row) => String(row.kycStatus ?? '').toLowerCase() === 'approved').length,
    },
    { label: 'Need attention (page)', value: needsReview },
    {
      label: 'Holding funds (page)',
      value: rows.value.filter((row) => row.hasFunds === true).length,
    },
  ];
});

const emptyMessage = computed(() => {
  if (backendError.value) {
    return 'No users are available because live data could not be loaded.';
  }
  if (query.value.trim() || selectedStatus.value) {
    return 'No users match the current search and filter.';
  }
  return 'No users were returned.';
});

function isPresent(value: AdminRowValue) {
  return value !== null && value !== undefined && String(value).trim() !== '';
}

function findValue(row: AdminRow, fields: string[]) {
  for (const field of fields) {
    const value = row[field];
    if (isPresent(value)) {
      return value;
    }
  }
  return null;
}

function fullName(row: AdminRow) {
  const firstName = String(row.firstName ?? row.first_name ?? '').trim();
  const lastName = String(row.lastName ?? row.last_name ?? '').trim();
  const name = [firstName, lastName].filter(Boolean).join(' ');
  return name || null;
}

function primaryText(row: AdminRow) {
  return String(
    fullName(row) ??
      findValue(row, ['name', 'displayName', 'fullName', 'email', 'id']) ??
      'Unnamed user',
  );
}

function userDetailLookup(row: AdminRow) {
  return String(
    findValue(row, ['hoppaUserId', 'userId', 'localUserId', 'id', 'email']) ??
      primaryText(row),
  );
}

function statusClass(value: AdminRowValue) {
  const normalized = String(value ?? '').toLowerCase();
  if (
    ['active', 'approved', 'released', 'settled', 'success', 'open', 'verified'].includes(
      normalized,
    )
  ) {
    return 'border-emerald-200 bg-emerald-50 text-emerald-700';
  }
  if (
    ['manual_review', 'pending', 'pending_review', 'held', 'reported', 'blocked', 'high'].includes(
      normalized,
    )
  ) {
    return 'border-amber-200 bg-amber-50 text-amber-700';
  }
  if (['suspended', 'rejected', 'failed', 'frozen'].includes(normalized)) {
    return 'border-rose-200 bg-rose-50 text-rose-700';
  }
  return 'border-slate-200 bg-slate-50 text-slate-700';
}

function humanize(value: string) {
  return value.replace(/_/g, ' ');
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

function nestedValue(value: unknown, keys: string[]): AdminRowValue {
  if (!value || typeof value !== 'object') return null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const match = nestedValue(item, keys);
      if (isPresent(match)) return match;
    }
    return null;
  }

  const record = value as Record<string, unknown>;
  for (const key of keys) {
    const entry = record[key];
    if (typeof entry === 'string' || typeof entry === 'number' || typeof entry === 'boolean') {
      if (isPresent(entry)) return entry;
    }
  }
  for (const entry of Object.values(record)) {
    const match = nestedValue(entry, keys);
    if (isPresent(match)) return match;
  }
  return null;
}

function balanceSummary(assetRows: AdminRow[]) {
  const totals = new Map<string, number>();
  for (const asset of assetRows) {
    const currency = String(findValue(asset, ['asset', 'assetCode', 'currency', 'currencyCode', 'token', 'tokenSymbol']) ?? '').toUpperCase();
    const rawBalance = findValue(asset, ['availableBalance', 'balance', 'amount', 'value']);
    const balance = Number(rawBalance);
    if (!currency || !Number.isFinite(balance)) continue;
    totals.set(currency, (totals.get(currency) ?? 0) + balance);
  }

  const nonZero = [...totals.entries()].filter(([, amount]) => Math.abs(amount) > 0.00000001);
  return {
    hasFunds: nonZero.length > 0,
    text: nonZero.length
      ? nonZero.slice(0, 3).map(([currency, amount]) => `${amount.toLocaleString(undefined, { maximumFractionDigits: 6 })} ${currency}`).join(' · ')
      : totals.size ? 'No funds' : 'Unavailable',
  };
}

async function enrichCustomer(row: AdminRow): Promise<AdminRow> {
  const reference = findValue(row, ['hoppaUserId', 'userId']);
  if (!reference) return row;
  const encoded = encodeURIComponent(String(reference));
  const [kycResult, assetResult] = await Promise.allSettled([
    apiClient.get<unknown>(`/api/v1/admin/kyc/cases/${encoded}`),
    loadAdminRows(`/api/v1/admin/hoppa/users/assets?userId=${encoded}`, []),
  ]);

  const kycStatus = kycResult.status === 'fulfilled'
    ? nestedValue(kycResult.value.data, ['status', 'Status', 'kycStatus', 'KycStatus'])
    : null;
  const assets = assetResult.status === 'fulfilled' ? assetResult.value.data : [];
  const balances = balanceSummary(assets);

  return {
    ...row,
    kycStatus: kycStatus ?? row.kycStatus ?? null,
    balanceSummary: balances.text,
    hasFunds: balances.hasFunds,
  };
}

async function enrichCustomers(sourceRows: AdminRow[]) {
  const enriched: AdminRow[] = [];
  for (let index = 0; index < sourceRows.length; index += 5) {
    enriched.push(...await Promise.all(sourceRows.slice(index, index + 5).map(enrichCustomer)));
  }
  return enriched;
}

function buildSummariesEndpoint() {
  const params = new URLSearchParams();
  params.set('limit', String(pageSize.value));
  params.set('offset', String(first.value));
  if (selectedStatus.value) {
    params.set('status', selectedStatus.value);
  }
  if (sortField.value) {
    params.set('sortBy', sortField.value);
    params.set('sortDir', sortOrder.value === 1 ? 'asc' : 'desc');
  }
  return `/api/v1/admin/users/summaries?${params.toString()}`;
}

async function refreshRows() {
  loading.value = true;
  backendError.value = '';
  try {
    if (searchMode.value) {
      const endpoint = `/api/v1/admin/users/search?q=${encodeURIComponent(
        query.value.trim(),
      )}&limit=100`;
      const result = await loadAdminRows(endpoint, []);
      rows.value = await enrichCustomers(result.data);
      totalRecords.value = result.data.length;
      backendError.value = result.error ?? '';
    } else {
      const result = await loadAdminPage(buildSummariesEndpoint());
      rows.value = await enrichCustomers(result.data.rows);
      totalRecords.value = result.data.totalCount;
      backendError.value = result.error ?? '';
    }
  } finally {
    loading.value = false;
  }
}

function onPage(event: DataTablePageEvent) {
  first.value = event.first;
  pageSize.value = event.rows;
  refreshRows();
}

function onSort(event: DataTableSortEvent) {
  sortField.value = (event.sortField as string | null) ?? null;
  sortOrder.value = (event.sortOrder as 1 | -1 | null) ?? null;
  first.value = 0;
  refreshRows();
}

function onSearch() {
  first.value = 0;
  refreshRows();
}

onMounted(refreshRows);
</script>

<template>
  <AppShell>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 class="text-xl font-semibold text-slate-950">Users</h1>
          <p class="text-sm text-slate-500">
            Search users, compare account state, and open full details in a dedicated page.
          </p>
        </div>
        <Button
          icon="pi pi-refresh"
          label="Refresh"
          :loading="loading"
          @click="refreshRows"
        />
      </div>
    </template>

    <div
      v-if="backendError"
      class="mb-4 rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800"
    >
      Live data unavailable: {{ backendError }}
    </div>

    <div class="mb-4 grid gap-4 xl:grid-cols-4 md:grid-cols-2">
      <Card v-for="item in counts" :key="item.label">
        <template #content>
          <p class="text-sm font-medium text-slate-500">{{ item.label }}</p>
          <p class="mt-2 text-3xl font-semibold text-slate-950">{{ item.value }}</p>
        </template>
      </Card>
    </div>

    <Card>
      <template #content>
        <div class="mb-4 flex flex-wrap items-end gap-3">
          <label class="min-w-72 flex-1">
            <span class="mb-1 block text-xs font-semibold uppercase text-slate-500">
              Find customer
            </span>
            <input
              v-model="query"
              class="h-10 w-full rounded-md border border-slate-300 bg-white px-3 text-sm text-slate-950 outline-none focus:border-slate-950"
              placeholder="Name or email"
              type="search"
              @keyup.enter="onSearch"
            />
          </label>
          <label class="min-w-48">
            <span class="mb-1 block text-xs font-semibold uppercase text-slate-500">
              Status
            </span>
            <select
              v-model="selectedStatus"
              class="h-10 w-full rounded-md border border-slate-300 bg-white px-3 text-sm text-slate-950 outline-none focus:border-slate-950"
              @change="onSearch"
            >
              <option value="">All statuses</option>
              <option value="active">Active</option>
              <option value="suspended">Suspended</option>
              <option value="pending">Pending</option>
            </select>
          </label>
          <Button
            icon="pi pi-search"
            label="Search"
            severity="secondary"
            outlined
            :loading="loading"
            @click="onSearch"
          />
        </div>

        <DataTable
          :value="rows"
          :loading="loading"
          data-key="id"
          :lazy="!searchMode"
          paginator
          :first="first"
          :rows="pageSize"
          :total-records="searchMode ? rows.length : totalRecords"
          :rows-per-page-options="[10, 25, 50, 100]"
          paginator-template="FirstPageLink PrevPageLink CurrentPageReport NextPageLink LastPageLink RowsPerPageDropdown"
          current-page-report-template="{first}-{last} of {totalRecords}"
          removable-sort
          size="small"
          striped-rows
          table-style="min-width: 60rem"
          @page="onPage"
          @sort="onSort"
        >
          <template #empty>
            <div class="py-8 text-center text-sm text-slate-500">
              {{ emptyMessage }}
            </div>
          </template>
          <Column header="Customer" frozen sortable :sort-field="'displayName'">
            <template #body="{ data }">
              <div class="max-w-80">
                <p class="truncate font-semibold text-slate-950">
                  {{ primaryText(data) }}
                </p>
                <p
                  v-if="findValue(data, ['email'])"
                  class="mt-1 truncate text-xs text-slate-500"
                >
                  {{ findValue(data, ['email']) }}
                </p>
              </div>
            </template>
          </Column>
          <Column header="Status" sortable :sort-field="'status'">
            <template #body="{ data }">
              <span
                class="inline-flex rounded-md border px-2.5 py-1 text-xs font-semibold capitalize"
                :class="statusClass(data.status)"
              >
                {{ humanize(String(data.status ?? 'unknown')) }}
              </span>
            </template>
          </Column>
          <Column header="KYC">
            <template #body="{ data }">
              <span class="inline-flex rounded-md border px-2.5 py-1 text-xs font-semibold capitalize" :class="statusClass(findValue(data, ['kycStatus', 'verificationStatus']))">
                {{ humanize(String(findValue(data, ['kycStatus', 'verificationStatus']) ?? 'Unavailable')) }}
              </span>
            </template>
          </Column>
          <Column header="Balances">
            <template #body="{ data }">
              <span class="text-sm font-medium" :class="data.hasFunds ? 'text-slate-900' : 'text-slate-500'">
                {{ data.balanceSummary ?? 'Unavailable' }}
              </span>
            </template>
          </Column>
          <Column header="Last Login" sortable :sort-field="'lastLoginAt'">
            <template #body="{ data }">
              <span class="text-sm text-slate-700">
                {{ formatDateTime(data.lastLoginAt) }}
              </span>
            </template>
          </Column>
          <Column header="Actions" frozen align-frozen="right">
            <template #body="{ data }">
              <RouterLink
                :to="{ name: 'admin-user-detail', params: { lookup: userDetailLookup(data) } }"
                class="inline-flex min-h-9 items-center gap-2 rounded-md border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 hover:border-slate-300 hover:bg-slate-50"
              >
                Details
                <i class="pi pi-arrow-right text-xs" />
              </RouterLink>
            </template>
          </Column>
        </DataTable>
      </template>
    </Card>
  </AppShell>
</template>
