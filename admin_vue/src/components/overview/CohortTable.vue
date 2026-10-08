<script setup lang="ts">
// Weekly signup cohorts: the share of each cohort that moved money in each week since signing up.
import { computed } from 'vue';
import type { Cohort } from '@/lib/operationsApi';
import { formatDayShort } from '@/lib/overviewCharts';

const props = defineProps<{ cohorts: Cohort[] }>();

const width = computed(() => Math.max(1, ...props.cohorts.map(cohort => cohort.weeks.length)));
const visible = computed(() => props.cohorts.filter(cohort => cohort.size > 0));
function cellStyle(rate: number | null) {
  if (rate == null) return {};
  const alpha = Math.min(1, 0.08 + rate / 100 * 0.92);
  return { background: `rgba(37, 99, 235, ${alpha.toFixed(2)})`, color: rate >= 45 ? '#ffffff' : '#0f172a' };
}
</script>

<template>
  <div class="overflow-x-auto">
    <table v-if="visible.length" class="cohort-table w-full text-xs">
      <thead>
        <tr class="text-[11px] font-bold uppercase tracking-wide text-slate-500">
          <th class="pb-2 text-left">Signed up</th>
          <th class="pb-2 text-right">Customers</th>
          <th v-for="offset in width" :key="offset" class="pb-2 text-center">W{{ offset - 1 }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="cohort in visible" :key="cohort.weekStart">
          <td class="whitespace-nowrap py-1 pr-3 font-semibold text-slate-700">Week of {{ formatDayShort(cohort.weekStart) }}</td>
          <td class="py-1 pr-3 text-right tabular-nums text-slate-600">{{ cohort.size }}</td>
          <td v-for="offset in width" :key="offset" class="p-0.5">
            <div v-if="cohort.weeks[offset - 1]" class="cohort-cell" :style="cellStyle(cohort.weeks[offset - 1]!.rate)"
              :title="`${cohort.weeks[offset - 1]!.active} of ${cohort.size} moved money in week ${offset - 1}`">
              {{ cohort.weeks[offset - 1]!.rate == null ? '–' : `${Math.round(cohort.weeks[offset - 1]!.rate!)}%` }}
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-else class="text-sm text-slate-500">Cohorts appear once customers sign up in the selected weeks.</p>
  </div>
</template>

<style scoped>
.cohort-table th, .cohort-table td { padding-left: .25rem; padding-right: .25rem; }
.cohort-cell { min-width: 44px; border-radius: 6px; padding: 5px 4px; text-align: center; font-weight: 600; font-variant-numeric: tabular-nums; }
</style>
