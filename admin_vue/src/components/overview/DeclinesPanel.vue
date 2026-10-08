<script setup lang="ts">
// Where card payments are declined: by merchant (with that merchant's decline rate), by the
// provider's reason and by card. Each merchant row opens the declined payments behind it.
import { computed, ref } from 'vue';
import type { OverviewData } from '@/lib/operationsApi';
import { formatPercent } from '@/lib/overviewCharts';

const props = defineProps<{ declines: OverviewData['declines']; days: number; money: (value: number) => string }>();

const tab = ref<'merchant' | 'reason' | 'card'>('merchant');
const tabs = [{ key: 'merchant', label: 'Merchants' }, { key: 'reason', label: 'Reasons' }, { key: 'card', label: 'Cards' }] as const;
const empty = computed(() => !props.declines.byMerchant.length);
const reasonTotal = computed(() => props.declines.byReason.reduce((sum, row) => sum + row.count, 0));
</script>

<template>
  <div>
    <div class="flex rounded-xl border border-slate-200 bg-white p-1 text-xs" role="tablist" aria-label="Break declines down by">
      <button v-for="item in tabs" :key="item.key" type="button" role="tab" class="flex-1 rounded-lg px-3 py-1.5 font-semibold transition"
        :class="tab === item.key ? 'bg-slate-900 text-white' : 'text-slate-600 hover:bg-slate-50'" :aria-selected="tab === item.key" @click="tab = item.key">{{ item.label }}</button>
    </div>
    <p v-if="empty" class="mt-4 text-sm text-slate-500">No declined card payments in the last {{ days }} days.</p>
    <table v-else-if="tab === 'merchant'" class="mt-3 w-full text-sm">
      <thead><tr class="text-[11px] font-bold uppercase tracking-wide text-slate-500"><th class="pb-2 text-left">Merchant</th><th class="pb-2 text-right">Declined</th><th class="pb-2 text-right">Of attempts</th><th class="pb-2 text-right">Amount</th></tr></thead>
      <tbody>
        <tr v-for="row in declines.byMerchant" :key="row.name" class="border-t border-slate-100">
          <td class="py-2"><RouterLink :to="{ path: '/money', query: { kind: 'card_purchase', status: 'failed', q: row.name } }" class="font-semibold text-slate-800 hover:text-blue-700">{{ row.name }}</RouterLink></td>
          <td class="py-2 text-right tabular-nums text-slate-700">{{ row.declined }}</td>
          <td class="py-2 text-right tabular-nums" :class="(row.rate ?? 0) >= 50 ? 'font-semibold text-red-700' : 'text-slate-600'">{{ formatPercent(row.rate) }} of {{ row.attempts }}</td>
          <td class="py-2 text-right tabular-nums text-slate-700">{{ money(row.amount) }}</td>
        </tr>
      </tbody>
    </table>
    <div v-else-if="tab === 'reason'" class="mt-3 space-y-2">
      <div v-for="row in declines.byReason" :key="row.reason" class="flex items-center gap-3 text-sm">
        <span class="min-w-0 flex-1 truncate text-slate-700" :title="row.reason">{{ row.reason }}</span>
        <div class="h-2 w-32 rounded-full bg-slate-100"><div class="h-full rounded-full bg-red-400" :style="{ width: `${Math.max(4, 100 * row.count / Math.max(1, reasonTotal))}%` }" /></div>
        <span class="w-8 text-right tabular-nums font-semibold text-slate-800">{{ row.count }}</span>
      </div>
      <p v-if="declines.byReason.length === 1 && declines.byReason[0]?.reason === 'No reason given'" class="text-xs text-slate-500">The provider did not send decline reasons for these payments.</p>
    </div>
    <table v-else class="mt-3 w-full text-sm">
      <thead><tr class="text-[11px] font-bold uppercase tracking-wide text-slate-500"><th class="pb-2 text-left">Card</th><th class="pb-2 text-right">Declined payments</th></tr></thead>
      <tbody>
        <tr v-for="row in declines.byCard" :key="row.lastFour" class="border-t border-slate-100">
          <td class="py-2 font-semibold text-slate-800">•••• {{ row.lastFour }}</td>
          <td class="py-2 text-right tabular-nums text-slate-700">{{ row.count }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
