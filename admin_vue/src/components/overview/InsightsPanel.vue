<script setup lang="ts">
// Briefing at the top of the Overview. The server writes it from aggregate KPIs only (no customer
// data) with the configured model, or with fixed rules when the model is unavailable.
import { computed, onMounted, ref, watch } from 'vue';
import { relativeTime } from '@/lib/formatters';
import { operationsApi, type InsightsResponse } from '@/lib/operationsApi';

const props = defineProps<{ range: number; sample?: InsightsResponse | null }>();

const loading = ref(false);
const refreshing = ref(false);
const error = ref('');
const loaded = ref<InsightsResponse | null>(null);
let requestId = 0;

const data = computed(() => props.sample ?? loaded.value);
const sourceLabel = computed(() => {
  if (!data.value) return '';
  if (data.value.source === 'rules') return 'Rule-based summary';
  const model = (data.value.model?.split('/').pop()?.replace(/-/g, ' ') ?? 'AI').replace(/\b\w/g, c => c.toUpperCase()).replace(/^Deepseek/, 'DeepSeek');
  return `AI summary · ${model}`;
});
const toneIcon: Record<string, string> = { good: 'pi pi-arrow-up-right text-emerald-600', bad: 'pi pi-exclamation-circle text-amber-600', neutral: 'pi pi-info-circle text-blue-600' };

async function load(refresh = false) {
  if (props.sample) return;
  const id = ++requestId;
  if (refresh) refreshing.value = true; else loading.value = true;
  error.value = '';
  try {
    const result = await operationsApi.insights(props.range, refresh);
    if (id === requestId) loaded.value = result;
  } catch (caught) {
    if (id === requestId) error.value = caught instanceof Error ? caught.message : 'The summary could not be loaded.';
  } finally {
    if (id === requestId) { loading.value = false; refreshing.value = false; }
  }
}

watch(() => props.range, () => void load());
onMounted(() => void load());
</script>

<template>
  <section class="insights panel p-5" aria-labelledby="insights-heading" :aria-busy="loading">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="flex items-center gap-2">
        <span class="grid size-8 place-items-center rounded-lg bg-violet-50 text-violet-600"><i class="pi pi-sparkles text-sm" /></span>
        <h2 id="insights-heading" class="panel-heading">What changed</h2>
      </div>
      <div class="flex items-center gap-3 text-xs text-slate-500">
        <span v-if="data">{{ sourceLabel }} · {{ relativeTime(data.generatedAt) }}</span>
        <button v-if="!sample" type="button" class="inline-flex items-center gap-1.5 rounded-lg px-2 py-1 font-semibold text-blue-700 hover:bg-blue-50 disabled:opacity-50"
          :disabled="loading || refreshing" @click="load(true)">
          <i class="pi pi-refresh text-[11px]" :class="refreshing ? 'pi-spin' : ''" />Refresh
        </button>
      </div>
    </div>

    <div v-if="loading && !data" class="mt-4 space-y-2" aria-hidden="true">
      <div class="h-5 w-3/4 animate-pulse rounded bg-slate-100" />
      <div class="h-4 w-full animate-pulse rounded bg-slate-100" />
      <div class="h-4 w-5/6 animate-pulse rounded bg-slate-100" />
    </div>
    <p v-else-if="error && !data" class="mt-3 text-sm text-slate-500">{{ error }}</p>
    <template v-else-if="data">
      <p class="mt-3 text-[15px] font-semibold leading-snug text-slate-900">{{ data.headline }}</p>
      <ul class="mt-4 grid gap-3 md:grid-cols-2" :class="data.items.length > 4 ? 'xl:grid-cols-3' : ''">
        <li v-for="(item, index) in data.items" :key="index" class="flex gap-3 rounded-xl border border-slate-100 bg-slate-50/60 p-3">
          <i :class="toneIcon[item.tone] ?? toneIcon.neutral" class="mt-0.5 text-sm" />
          <div class="min-w-0">
            <div class="text-sm font-semibold text-slate-900">{{ item.title }}</div>
            <div class="mt-1 text-xs leading-relaxed text-slate-600">{{ item.detail }}</div>
            <RouterLink v-if="item.link" :to="item.link" class="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-blue-700 hover:underline">
              Open<i class="pi pi-arrow-right text-[9px]" />
            </RouterLink>
          </div>
        </li>
      </ul>
      <p class="mt-3 text-[11px] text-slate-400">
        <template v-if="data.notice">{{ data.notice }} </template>
        <template v-else-if="data.source === 'ai'">Written by AI from the figures on this page; no customer names or contact details are shared with the model. Check the numbers before acting.</template>
      </p>
    </template>
  </section>
</template>
