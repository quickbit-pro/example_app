<script setup lang="ts">
// One ECharts instance at a fixed height; a null option shows the panel's empty state instead of a blank canvas.
import VChart from 'vue-echarts';
import '@/lib/overviewEcharts';
import type { OverviewChartOption } from '@/lib/overviewCharts';

withDefaults(defineProps<{
  option: OverviewChartOption | null;
  height: number;
  emptyText?: string;
  ariaLabel?: string;
}>(), { emptyText: 'No data for this period', ariaLabel: undefined });

/** Every option change replaces the previous one so a currency switch never leaves stale bars behind. */
const updateOptions = { notMerge: true };
</script>

<template>
  <div class="overview-chart" :style="{ height: `${height}px` }">
    <p v-if="!option" class="overview-chart__empty" role="status">{{ emptyText }}</p>
    <VChart v-else class="overview-chart__canvas" :option="option" :update-options="updateOptions" autoresize role="img" :aria-label="ariaLabel" />
  </div>
</template>

<style scoped>
.overview-chart { position: relative; width: 100%; min-width: 0; }
.overview-chart__canvas { display: block; width: 100%; height: 100%; }
.overview-chart__empty { display: grid; height: 100%; place-items: center; margin: 0; border: 1px dashed var(--chart-grid, #e2e8f0); border-radius: .75rem; padding: 0 1rem; color: var(--chart-text, #64748b); font-size: .875rem; text-align: center; }
</style>
