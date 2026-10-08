<script setup lang="ts">
// Any KPI split by how customers arrived, their country, app platform or app version.
import { computed, ref } from 'vue';
import type { OverviewData, SegmentRow } from '@/lib/operationsApi';
import { formatPercent } from '@/lib/overviewCharts';

const props = defineProps<{ segments: OverviewData['segments']; money: (value: number) => string }>();

type Dimension = keyof OverviewData['segments'];
const dimension = ref<Dimension>('source');
const dimensions: { key: Dimension; label: string }[] = [
  { key: 'source', label: 'Source' }, { key: 'country', label: 'Country' }, { key: 'platform', label: 'Platform' }, { key: 'appVersion', label: 'App version' },
];
const regionNames = typeof Intl.DisplayNames === 'function' ? new Intl.DisplayNames(undefined, { type: 'region' }) : null;
const rows = computed(() => props.segments[dimension.value] ?? []);

function label(row: SegmentRow) {
  if (dimension.value !== 'country' || row.key.length !== 2) return row.key;
  try { return `${regionNames?.of(row.key) ?? row.key} (${row.key})`; } catch { return row.key; }
}
const rate = (part: number, whole: number) => formatPercent(whole ? (100 * part) / whole : null);
</script>

<template>
  <div>
    <div class="flex flex-wrap rounded-xl border border-slate-200 bg-white p-1 text-xs" role="tablist" aria-label="Split customers by">
      <button v-for="item in dimensions" :key="item.key" type="button" role="tab" class="flex-1 rounded-lg px-3 py-1.5 font-semibold transition"
        :class="dimension === item.key ? 'bg-slate-900 text-white' : 'text-slate-600 hover:bg-slate-50'" :aria-selected="dimension === item.key" @click="dimension = item.key">{{ item.label }}</button>
    </div>
    <div class="mt-3 overflow-x-auto">
      <table v-if="rows.length" class="segment-table w-full whitespace-nowrap text-sm">
        <thead>
          <tr class="text-[11px] font-bold uppercase tracking-wide text-slate-500">
            <th class="pb-2 text-left">Segment</th><th class="pb-2 text-right">Customers</th><th class="pb-2 text-right">Approved</th>
            <th class="pb-2 text-right">Added money</th><th class="pb-2 text-right">Transacting</th><th class="pb-2 text-right">Card spend</th><th class="pb-2 text-right">Fees</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in rows" :key="row.key" class="border-t border-slate-100">
            <td class="py-2 font-semibold text-slate-800">{{ label(row) }}</td>
            <td class="py-2 text-right tabular-nums text-slate-700">{{ row.customers }}</td>
            <td class="py-2 text-right tabular-nums text-slate-600">{{ rate(row.approved, row.customers) }}</td>
            <td class="py-2 text-right tabular-nums text-slate-600" :title="`${row.funded} of ${row.approved} approved`">{{ rate(row.funded, row.approved) }}</td>
            <td class="py-2 text-right tabular-nums text-slate-600">{{ row.transacting }}</td>
            <td class="py-2 text-right tabular-nums text-slate-800">{{ money(row.spend) }}</td>
            <td class="py-2 text-right tabular-nums text-slate-800">{{ money(row.fees) }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else class="text-sm text-slate-500">No customers to split yet.</p>
    </div>
    <p class="mt-3 text-[11px] text-slate-500">
      <template v-if="dimension === 'source'">Referral means the customer signed up with a referral code.</template>
      <template v-else-if="dimension === 'country'">Country from identity verification, otherwise the app language setting.</template>
      <template v-else>From the device the customer last used; web users have no app version.</template>
      Approved is a share of customers; Added money is a share of approved customers. Spend and fees cover the selected period.
    </p>
  </div>
</template>

<style scoped>
.segment-table th, .segment-table td { padding-left: .375rem; padding-right: .375rem; }
.segment-table th:first-child, .segment-table td:first-child { padding-left: 0; }
.segment-table th:last-child, .segment-table td:last-child { padding-right: 0; }
</style>
