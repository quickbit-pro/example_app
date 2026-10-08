<script setup lang="ts">
// KPI tile: label, headline value, one line of context and an optional axis-less sparkline. Tiles
// without a natural series keep the sparkline slot empty (same height) rather than drawing fake data.
// With `to`, the whole tile opens the customers or transactions behind the number; `info` explains it.
import { computed } from 'vue';
import type { RouteLocationRaw } from 'vue-router';
import VChart from 'vue-echarts';
import '@/lib/overviewEcharts';
import { isAllZero, sparklineOption, type OverviewTheme, type Trend } from '@/lib/overviewCharts';

const props = withDefaults(defineProps<{
  label: string;
  value: string;
  sub?: string;
  subTone?: 'positive' | 'neutral' | 'warning';
  icon: string;
  iconTone?: 'accent' | 'positive';
  sparkline?: number[] | null;
  sparklineLabel?: string;
  /** Change against the previous period of the same length. */
  trend?: Trend | null;
  trendTitle?: string;
  /** Definition, source and freshness, shown from the (i) button. */
  info?: string;
  /** Where the number comes from: a filtered customer or transaction list. */
  to?: RouteLocationRaw;
  theme: OverviewTheme;
}>(), { sub: '', subTone: 'neutral', iconTone: 'accent', sparkline: null, sparklineLabel: undefined, trend: null, trendTitle: undefined, info: undefined, to: undefined });

const option = computed(() => {
  const values = props.sparkline;
  if (!values || values.length < 2 || isAllZero(values)) return null;
  return sparklineOption(values, props.theme, props.iconTone === 'positive' ? props.theme.positive : props.theme.accent);
});
const subClass = computed(() => ({ positive: 'text-emerald-700', warning: 'text-amber-700', neutral: 'text-slate-500' }[props.subTone]));
const trendClass = computed(() => ({ positive: 'bg-emerald-50 text-emerald-700', negative: 'bg-red-50 text-red-700', neutral: 'bg-slate-100 text-slate-600' }[props.trend?.tone ?? 'neutral']));
</script>

<template>
  <div class="metric-card kpi-tile relative flex h-full flex-col p-4" :class="to ? 'kpi-tile--link' : ''">
    <RouterLink v-if="to" :to="to" class="kpi-tile__link" :aria-label="`${label}: ${value}. Show the details`" />
    <div class="flex items-center justify-between gap-2">
      <span class="truncate text-[13px] font-semibold text-slate-600">{{ label }}</span>
      <span class="flex items-center gap-2">
        <span v-if="info" class="kpi-info" tabindex="0" role="button" :aria-label="`About ${label}`">
          <i class="pi pi-info-circle text-xs text-slate-400" />
          <span class="kpi-info__tip" role="tooltip">{{ info }}</span>
        </span>
        <i :class="[icon, iconTone === 'positive' ? 'text-emerald-600' : 'text-blue-600']" class="text-sm" />
      </span>
    </div>
    <div class="mt-3 flex flex-wrap items-baseline gap-x-2 gap-y-1">
      <span class="text-[26px] font-bold leading-none tracking-tight text-slate-950">{{ value }}</span>
      <span v-if="trend" class="rounded-md px-1.5 py-0.5 text-[11px] font-bold tabular-nums" :class="trendClass" :title="trendTitle">{{ trend.label }}</span>
    </div>
    <div class="mt-2 min-h-4 text-xs font-medium" :class="subClass">{{ sub }}</div>
    <div class="kpi-spark mt-3">
      <VChart v-if="option" class="kpi-spark__canvas" :option="option" autoresize role="img" :aria-label="sparklineLabel" />
    </div>
    <i v-if="to" class="pi pi-arrow-right kpi-tile__go" aria-hidden="true" />
  </div>
</template>

<style scoped>
.kpi-spark { height: 36px; width: 100%; min-width: 0; }
.kpi-spark__canvas { display: block; width: 100%; height: 100%; }
.kpi-tile--link { transition: border-color .15s, box-shadow .15s; }
.kpi-tile--link:hover { border-color: #93c5fd; box-shadow: 0 4px 14px rgba(37, 99, 235, .08); }
.kpi-tile__link { position: absolute; inset: 0; z-index: 1; border-radius: inherit; }
.kpi-tile__link:focus-visible { outline: 2px solid #2563eb; outline-offset: 2px; }
.kpi-tile__go { position: absolute; right: 12px; bottom: 10px; font-size: 10px; color: #94a3b8; opacity: 0; transition: opacity .15s; }
.kpi-tile--link:hover .kpi-tile__go { opacity: 1; }
.kpi-info { position: relative; z-index: 2; display: inline-grid; place-items: center; cursor: help; border-radius: 9999px; }
.kpi-info:focus-visible { outline: 2px solid #2563eb; outline-offset: 2px; }
.kpi-info__tip { display: none; position: absolute; right: -8px; top: calc(100% + 8px); width: 260px; padding: 10px 12px; border-radius: 10px;
  background: #0f172a; color: #f8fafc; font-size: 12px; font-weight: 500; line-height: 1.45; white-space: pre-line; text-align: left;
  box-shadow: 0 6px 20px rgba(15, 23, 42, .18); }
.kpi-info:hover .kpi-info__tip, .kpi-info:focus .kpi-info__tip { display: block; }
</style>
