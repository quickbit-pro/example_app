<script setup lang="ts">
// Thin vue-echarts wrapper: the option is built in lib/chartConfig.ts from the props and the palette
// read from the --chart-* CSS variables in styles.css (at mount and again whenever the theme changes).
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import VChart from 'vue-echarts';
import '@/lib/echarts';
import { buildChartOption, isEmptySeries, readTheme, type ChartFormatting, type ChartKind, type ChartSeries } from '@/lib/chartConfig';

const props = withDefaults(defineProps<{
  kind: ChartKind;
  labels: string[];
  series: ChartSeries[];
  /** Chart height in pixels; the width follows the container (autoresize). */
  height?: number;
  emptyText?: string;
  ariaLabel?: string;
  formatY?: ChartFormatting['formatY'];
  formatY1?: ChartFormatting['formatY1'];
  tooltipExtra?: ChartFormatting['tooltipExtra'];
  barLabels?: ChartFormatting['barLabels'];
  titleX?: string;
  titleY?: string;
  titleY1?: string;
  stacked?: boolean;
  legend?: boolean;
}>(), { height: 260, emptyText: 'No data for this period', ariaLabel: undefined, formatY: undefined, formatY1: undefined, tooltipExtra: undefined,
  barLabels: undefined, titleX: undefined, titleY: undefined, titleY1: undefined, stacked: false, legend: undefined });

const root = ref<HTMLElement | null>(null);
const theme = ref(readTheme(() => ''));
const empty = computed(() => isEmptySeries(props.labels, props.series));
const option = computed(() => empty.value ? null : buildChartOption(props.kind, props.labels, props.series, theme.value, {
  formatY: props.formatY, formatY1: props.formatY1, tooltipExtra: props.tooltipExtra, barLabels: props.barLabels,
  titleX: props.titleX, titleY: props.titleY, titleY1: props.titleY1, stacked: props.stacked, legend: props.legend,
}));
/** Every option change replaces the previous one, so a kind switch never leaves stale axes or series behind. */
const updateOptions = { notMerge: true };

function refreshTheme() {
  if (typeof getComputedStyle !== 'function' || typeof document === 'undefined') return;
  const style = getComputedStyle(root.value ?? document.documentElement);
  theme.value = readTheme(variable => style.getPropertyValue(variable));
}
const media = typeof window !== 'undefined' && 'matchMedia' in window ? window.matchMedia('(prefers-color-scheme: dark)') : null;
const observer = typeof MutationObserver !== 'undefined' ? new MutationObserver(refreshTheme) : null;
onMounted(() => {
  refreshTheme();
  media?.addEventListener('change', refreshTheme);
  observer?.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'data-theme'] });
});
onBeforeUnmount(() => { media?.removeEventListener('change', refreshTheme); observer?.disconnect(); });
</script>

<template>
  <div ref="root" class="analytics-chart" :style="{ height: `${height}px` }">
    <p v-if="empty" class="analytics-chart__empty" role="status">{{ emptyText }}</p>
    <VChart v-else-if="option" class="analytics-chart__chart" :option="option" :update-options="updateOptions" autoresize role="img" :aria-label="ariaLabel" />
  </div>
</template>

<style scoped>
.analytics-chart { position: relative; width: 100%; min-width: 0; }
.analytics-chart__chart { display: block; width: 100%; height: 100%; }
.analytics-chart__empty { display: grid; height: 100%; place-items: center; margin: 0; border: 1px dashed var(--chart-grid, #e2e8f0); border-radius: .75rem; color: var(--chart-text, #64748b); font-size: .875rem; }
</style>
