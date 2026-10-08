<script setup lang="ts">
// Dense list of the customers most in need of follow-up (max five), each linking to the customer page.
import type { AttentionItem } from '@/lib/operationsApi';

defineProps<{ items: AttentionItem[]; total: number }>();

function age(hours: number) {
  if (hours < 1) return 'just now';
  if (hours < 24) return `${Math.round(hours)}h`;
  return `${Math.round(hours / 24)}d`;
}
</script>

<template>
  <div class="panel p-5">
    <div class="flex items-center justify-between gap-3">
      <h2 class="panel-heading">Needs attention</h2>
      <RouterLink to="/customers?attention=true" class="text-xs font-semibold text-blue-700">{{ total > items.length ? `View all ${total}` : 'View customers' }}</RouterLink>
    </div>
    <ul v-if="items.length" class="mt-3 divide-y divide-slate-100">
      <li v-for="item in items" :key="item.customerId">
        <RouterLink :to="`/customers/${item.customerId}`" class="group -mx-2 flex items-start gap-3 rounded-xl px-2 py-2.5 transition hover:bg-slate-50">
          <span class="mt-1.5 size-2 shrink-0 rounded-full" :class="item.tone === 'danger' ? 'bg-red-500' : 'bg-amber-500'" />
          <span class="min-w-0 flex-1">
            <span class="flex items-baseline justify-between gap-2">
              <span class="truncate text-sm font-semibold text-slate-900 group-hover:text-blue-700">{{ item.customerName }}</span>
              <span class="shrink-0 text-[11px] font-medium text-slate-400">{{ age(item.ageHours) }}</span>
            </span>
            <span class="mt-0.5 block truncate text-xs" :class="item.tone === 'danger' ? 'text-red-700' : 'text-amber-700'">{{ item.reason }}</span>
          </span>
        </RouterLink>
      </li>
    </ul>
    <p v-else class="mt-4 flex items-center gap-2 text-sm text-slate-500"><i class="pi pi-check-circle text-emerald-600" />No customers need follow-up.</p>
  </div>
</template>
