<script setup lang="ts">
// Chips for everything that needs an operator today; each links to the page where it is handled.
import type { NeedsYouItem } from '@/lib/overviewCharts';

defineProps<{ items: NeedsYouItem[] }>();

const toneClass: Record<NeedsYouItem['tone'], string> = {
  accent: 'border-slate-200 bg-white text-slate-800 hover:border-blue-300 hover:bg-blue-50/60',
  warning: 'border-amber-200 bg-amber-50 text-amber-900 hover:border-amber-300',
  danger: 'border-red-200 bg-red-50 text-red-800 hover:border-red-300',
};
const iconClass: Record<NeedsYouItem['tone'], string> = { accent: 'text-blue-600', warning: 'text-amber-600', danger: 'text-red-600' };
</script>

<template>
  <section aria-label="Needs you">
    <div v-if="items.length" class="flex flex-wrap items-center gap-2">
      <span class="mr-1 text-xs font-bold uppercase tracking-wide text-slate-500">Needs you</span>
      <RouterLink
        v-for="item in items"
        :key="item.key"
        :to="item.to"
        class="inline-flex min-h-9 items-center gap-2 rounded-xl border px-3 text-sm font-semibold shadow-[0_1px_2px_rgba(15,23,42,0.04)] transition"
        :class="toneClass[item.tone]"
      >
        <i :class="[item.icon, iconClass[item.tone]]" class="text-xs" />
        <span class="tabular-nums">{{ item.count.toLocaleString() }}</span>
        <span class="font-medium opacity-80">{{ item.label }}</span>
        <i class="pi pi-arrow-right text-[10px] opacity-50" />
      </RouterLink>
    </div>
    <p v-else class="flex items-center gap-2 text-sm text-slate-500">
      <i class="pi pi-check-circle text-emerald-600" />
      Nothing needs your attention right now.
    </p>
  </section>
</template>
