// Pure helpers and ECharts option builders for the Overview page. No DOM access and no runtime
// imports: the view reads the palette from the --chart-* CSS variables and hands it in, so this
// module is unit-tested with node:test (tests/overviewCharts.test.mjs) exactly like chartConfig.ts.
// ECharts modules are registered in lib/overviewEcharts.ts.
import type { BarSeriesOption, FunnelSeriesOption, LineSeriesOption } from 'echarts/charts';
import type { GridComponentOption, LegendComponentOption, TooltipComponentOption } from 'echarts/components';
import type { ComposeOption } from 'echarts/core';

export type OverviewChartOption = ComposeOption<BarSeriesOption | LineSeriesOption | FunnelSeriesOption | GridComponentOption | TooltipComponentOption | LegendComponentOption>;

export interface OverviewTheme {
  accent: string; accentSoft: string; accentFaint: string; neutral: string; neutralSoft: string; negative: string; positive: string;
  text: string; grid: string; surface: string; tooltipBackground: string; tooltipText: string;
}
export const FONT_FAMILY = 'Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif';
/** Same variable names as styles.css so the page follows the shared chart palette (and its .dark overrides) when present. */
export const THEME_VARIABLES: Record<keyof OverviewTheme, string> = {
  accent: '--chart-accent', accentSoft: '--chart-accent-soft', accentFaint: '--chart-accent-faint', neutral: '--chart-neutral',
  neutralSoft: '--chart-neutral-soft', negative: '--chart-negative', positive: '--chart-positive', text: '--chart-text', grid: '--chart-grid',
  surface: '--chart-surface', tooltipBackground: '--chart-tooltip-bg', tooltipText: '--chart-tooltip-text',
};
export const LIGHT_THEME: OverviewTheme = {
  accent: '#1d4ed8', accentSoft: '#93c5fd', accentFaint: '#dbeafe', neutral: '#64748b', neutralSoft: '#cbd5e1', negative: '#dc2626', positive: '#059669',
  text: '#64748b', grid: '#e2e8f0', surface: '#ffffff', tooltipBackground: '#0f172a', tooltipText: '#f8fafc',
};
export const DARK_THEME: OverviewTheme = {
  accent: '#60a5fa', accentSoft: '#3b82f6', accentFaint: '#1e3a8a', neutral: '#94a3b8', neutralSoft: '#475569', negative: '#f87171', positive: '#34d399',
  text: '#94a3b8', grid: '#334155', surface: '#0f172a', tooltipBackground: '#f8fafc', tooltipText: '#0f172a',
};
/** Builds the theme from a CSS variable reader, falling back per variable to the light or dark defaults. */
export function readOverviewTheme(read: (variable: string) => string | null | undefined, dark = false): OverviewTheme {
  const fallback = dark ? DARK_THEME : LIGHT_THEME;
  const entries = (Object.keys(fallback) as (keyof OverviewTheme)[]).map(key => [key, (read(THEME_VARIABLES[key]) ?? '').trim() || fallback[key]]);
  return Object.fromEntries(entries) as unknown as OverviewTheme;
}
/** "#rrggbb" → "rgba(r, g, b, a)"; other colour syntaxes are returned unchanged. */
export function withAlpha(color: string, alpha: number): string {
  const match = /^#([0-9a-f]{6})$/i.exec(color.trim());
  if (!match) return color;
  const n = parseInt(match[1]!, 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
}
/** Tooltips are HTML: customer names, reasons and currency codes from the payload are escaped first. */
export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] ?? c);
}
/** ECharts hands the point value as a number, an [x, y] pair or a `{ value }` item depending on the series. */
export function numberOf(value: unknown): number {
  if (typeof value === 'number') return value;
  if (Array.isArray(value)) return numberOf(value[value.length - 1]);
  if (value && typeof value === 'object' && 'value' in value) return numberOf((value as { value: unknown }).value);
  return value == null || value === '' ? Number.NaN : Number(value);
}

// ---- data shapes (structural copies of operationsApi.OverviewData so this file has no runtime dependency) ----
export interface DailyCount { count: number; date: string }
export interface FunnelStep { key: string; label: string; value: number }
export interface Balance { amount: number; currency: string }
export interface FunnelConversion { from: string; to: string; /** 0–100, null when the previous step is empty. */ rate: number | null }
export interface NeedsYouItem {
  key: 'followUp' | 'pending' | 'over24h' | 'rejected' | 'failedCredits' | 'support';
  count: number; label: string; to: string; tone: 'accent' | 'warning' | 'danger'; icon: string;
}
export interface NeedsYouInput {
  attentionCount: number;
  verificationAging: { over24Hours: number; pending: number; rejected: number };
  /** Null while referrals are unavailable (disabled programme, failed request). */
  failedReferralCredits: number | null;
  support?: { awaiting: number; oldestWaitingHours: number | null };
}
/** A change against the previous period; the tone says whether it is good news. */
export interface Trend { label: string; tone: 'positive' | 'negative' | 'neutral' }
export interface DailyPair { day: string; first: number; second: number }
export interface FeeRow { type: string; label: string; amount: number; count: number }

// ---- dates ----
/** Local-date "YYYY-MM-DD" of a Date. */
export function isoDay(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
/** "YYYY-MM-DD" → Date at local noon, so formatting never slides across midnight. */
export function parseDay(day: string): Date {
  const [y, m, d] = day.split('-').map(Number);
  return new Date(y || 1970, (m || 1) - 1, d || 1, 12);
}
/** `count` consecutive days ending on `end` (inclusive), oldest first. */
export function dayRange(count: number, end: Date): string[] {
  const days: string[] = [];
  for (let offset = count - 1; offset >= 0; offset -= 1) {
    const date = new Date(end.getFullYear(), end.getMonth(), end.getDate() - offset, 12);
    days.push(isoDay(date));
  }
  return days;
}
const shortDay = (date: Date, locale?: string) => new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short' }).format(date);
const longDay = (date: Date, locale?: string) => new Intl.DateTimeFormat(locale, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }).format(date);
export function formatDayShort(day: string, locale?: string): string { return shortDay(parseDay(day), locale); }
export function formatDayLong(day: string, locale?: string): string { return longDay(parseDay(day), locale); }
/** Which category indexes get an axis label: every day up to two weeks, otherwise weekly, anchored on the last day. */
export function tickInterval(count: number): (index: number) => boolean {
  const step = count <= 14 ? 1 : 7;
  return index => (count - 1 - index) % step === 0;
}

// ---- numbers ----
export function cumulative(values: readonly number[]): number[] {
  let sum = 0;
  return values.map(value => (sum += value));
}
/** Trailing moving average; the first points average what is available so the line starts on day one. */
export function movingAverage(values: readonly number[], window = 7): number[] {
  return values.map((_, index) => {
    const start = Math.max(0, index - window + 1);
    const slice = values.slice(start, index + 1);
    const avg = slice.reduce((sum, v) => sum + v, 0) / slice.length;
    return Math.round(avg * 100) / 100;
  });
}
export function formatPercent(value: number | null | undefined): string {
  return value == null || !Number.isFinite(value) ? '–' : `${Math.round(value)}%`;
}
/** Compact axis amounts ("$4.7K", "HUF 1.2M"); falls back to a plain compact number with the code. */
export function formatCompactAmount(value: number, currency: string, locale?: string): string {
  try {
    return new Intl.NumberFormat(locale, { style: 'currency', currency, notation: 'compact', maximumFractionDigits: 1 }).format(value);
  } catch {
    return `${new Intl.NumberFormat(locale, { notation: 'compact', maximumFractionDigits: 1 }).format(value)} ${currency}`;
  }
}
export function greeting(hour: number): string {
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 18) return 'Good afternoon';
  return 'Good evening';
}

// ---- derived data ----
/**
 * Percentage change against the previous period. `higherIsBetter` decides the tone, so a falling
 * decline rate reads as good news. Nothing to compare with gives "New" rather than an infinite change.
 */
export interface TrendOptions {
  /** Below this base a percentage misleads ("+100%" for 2 → 4), so the absolute change is shown. */
  minBase?: number;
  /** Formats the absolute change, e.g. as currency; defaults to a plain number. */
  formatDelta?: (value: number) => string;
}
export function trend(current: number, previous: number, higherIsBetter = true, options: TrendOptions = {}): Trend | null {
  if (!Number.isFinite(current) || !Number.isFinite(previous)) return null;
  const { minBase = 10, formatDelta = (value: number) => value.toLocaleString(undefined, { maximumFractionDigits: 2 }) } = options;
  const delta = current - previous;
  if (Math.abs(previous) < minBase) {
    if (delta === 0) return previous === 0 ? null : { label: '±0', tone: 'neutral' };
    const up = delta > 0;
    return { label: `${up ? '+' : '−'}${formatDelta(Math.abs(delta))}`, tone: up === higherIsBetter ? 'positive' : 'negative' };
  }
  const change = Math.round((100 * delta) / Math.abs(previous));
  if (change === 0) return { label: '0%', tone: 'neutral' };
  const up = change > 0;
  return { label: `${up ? '+' : '−'}${Math.abs(change).toLocaleString()}%`, tone: up === higherIsBetter ? 'positive' : 'negative' };
}
/** Change of a rate in percentage points ("+2.5 pts"). */
export function pointTrend(current: number | null, previous: number | null, higherIsBetter = true): Trend | null {
  if (current == null || previous == null || !Number.isFinite(current) || !Number.isFinite(previous)) return null;
  const change = Math.round((current - previous) * 10) / 10;
  if (change === 0) return { label: '0 pts', tone: 'neutral' };
  const up = change > 0;
  return { label: `${up ? '+' : '−'}${Math.abs(change)} pts`, tone: up === higherIsBetter ? 'positive' : 'negative' };
}
export type Bucket = 'day' | 'week';
/** Monday of the week that contains `day` ("YYYY-MM-DD"). */
export function weekOf(day: string): string {
  const date = parseDay(day);
  const offset = (date.getDay() + 6) % 7;
  return isoDay(new Date(date.getFullYear(), date.getMonth(), date.getDate() - offset, 12));
}
/**
 * Sums daily points into Monday-start weeks for the given numeric fields. Partial weeks at
 * either end keep only the days that were in the range.
 */
export function weeklyBuckets<T extends { date: string }, K extends keyof T & string>(points: readonly T[], keys: readonly K[]): ({ date: string } & Record<K, number>)[] {
  const weeks = new Map<string, { date: string } & Record<K, number>>();
  for (const point of points) {
    const week = weekOf(point.date);
    const bucket = weeks.get(week) ?? ({ date: week, ...Object.fromEntries(keys.map(key => [key, 0])) } as { date: string } & Record<K, number>);
    for (const key of keys) (bucket as Record<string, number>)[key] = Math.round(((bucket[key] as number) + Number(point[key] ?? 0)) * 100) / 100;
    weeks.set(week, bucket);
  }
  return [...weeks.values()].sort((a, b) => a.date.localeCompare(b.date));
}
/** 30- and 90-day views read better by week; the daily bars are mostly empty for a young programme. */
export function bucketFor(rangeDays: number): Bucket {
  return rangeDays > 14 ? 'week' : 'day';
}
function bucketTitle(day: string, bucket: Bucket, locale?: string): string {
  return bucket === 'week' ? `Week of ${formatDayLong(day, locale)}` : formatDayLong(day, locale);
}

export function funnelConversions(steps: readonly FunnelStep[]): FunnelConversion[] {
  return steps.slice(1).map((step, index) => {
    const previous = steps[index]!;
    return { from: previous.label, to: step.label, rate: previous.value > 0 ? Math.round((100 * step.value) / previous.value) : null };
  });
}
export interface BalanceBar { label: string; currency: string | null; amount: number; count: number }
/** Largest `limit` balances by amount; the rest are folded into one "Others" bar (a plain number, it spans currencies). */
export function balanceBars(balances: readonly Balance[], limit = 8): BalanceBar[] {
  const sorted = [...balances].filter(b => Number.isFinite(b.amount)).sort((a, b) => b.amount - a.amount);
  if (sorted.length <= limit) return sorted.map(b => ({ label: b.currency, currency: b.currency, amount: b.amount, count: 1 }));
  const shown = sorted.slice(0, limit - 1);
  const rest = sorted.slice(limit - 1);
  return [...shown.map(b => ({ label: b.currency, currency: b.currency, amount: b.amount, count: 1 })),
    { label: `Others (${rest.length})`, currency: null, amount: rest.reduce((sum, b) => sum + b.amount, 0), count: rest.length }];
}
/** Only counts above zero become chips; the referral chip needs a loaded reconciliation. */
export function needsYouItems(input: NeedsYouInput): NeedsYouItem[] {
  const items: NeedsYouItem[] = [
    { key: 'followUp', count: input.attentionCount, label: 'need follow-up', to: '/customers?attention=true', tone: 'accent', icon: 'pi pi-user-edit' },
    { key: 'pending', count: input.verificationAging.pending, label: 'pending', to: '/verification', tone: 'accent', icon: 'pi pi-shield' },
    { key: 'over24h', count: input.verificationAging.over24Hours, label: 'pending over 24 h', to: '/verification', tone: 'warning', icon: 'pi pi-clock' },
    { key: 'rejected', count: input.verificationAging.rejected, label: 'rejected', to: '/verification', tone: 'accent', icon: 'pi pi-ban' },
    { key: 'failedCredits', count: input.failedReferralCredits ?? 0, label: 'failed referral credits', to: '/referrals', tone: 'danger', icon: 'pi pi-exclamation-triangle' },
    { key: 'support', count: input.support?.awaiting ?? 0, label: input.support?.oldestWaitingHours != null && input.support.oldestWaitingHours >= 24
      ? `tickets awaiting reply · oldest ${Math.floor(input.support.oldestWaitingHours / 24)}d` : 'tickets awaiting reply', to: '/support',
    tone: (input.support?.oldestWaitingHours ?? 0) >= 24 ? 'warning' : 'accent', icon: 'pi pi-ticket' },
  ];
  return items.filter(item => item.count > 0);
}
export function isAllZero(values: readonly number[]): boolean {
  return values.every(value => !Number.isFinite(value) || value === 0);
}

// ---- option builders ----
type Loose = Record<string, unknown>;
interface Params { seriesIndex?: number; dataIndex: number; seriesName?: string; name?: string; value?: unknown; color?: string; axisValue?: string | number; axisValueLabel?: string }
const marker = (color: string | undefined) => color ? `<span style="display:inline-block;width:8px;height:8px;margin-right:6px;border-radius:50%;background:${escapeHtml(color)}"></span>` : '';
function tooltipBase(theme: OverviewTheme): Loose {
  return { backgroundColor: theme.tooltipBackground, borderWidth: 0, padding: [8, 12], appendToBody: true, confine: true,
    textStyle: { color: theme.tooltipText, fontSize: 12, fontFamily: FONT_FAMILY }, extraCssText: 'border-radius:8px;box-shadow:0 6px 20px rgba(15,23,42,.18);' };
}
function base(theme: OverviewTheme): Loose {
  return { textStyle: { fontFamily: FONT_FAMILY, color: theme.text }, animationDuration: 300, animationDurationUpdate: 300 };
}
const tooltipTitle = (text: string) => `<div style="font-weight:600;margin-bottom:4px">${escapeHtml(text)}</div>`;
const tooltipRow = (color: string | undefined, name: string, value: string) => `<div>${marker(color)}${escapeHtml(name)}: <b>${escapeHtml(value)}</b></div>`;

/** Tiny axis-less line for a KPI tile; the area fades into the card. */
export function sparklineOption(values: readonly number[], theme: OverviewTheme, color: string = theme.accent): OverviewChartOption {
  return { ...base(theme), animation: false, grid: { left: 2, right: 2, top: 4, bottom: 2 }, tooltip: { show: false },
    xAxis: { type: 'category', show: false, boundaryGap: false, data: values.map((_, i) => i) },
    yAxis: { type: 'value', show: false, min: (extent: { min: number }) => Math.min(0, extent.min), max: (extent: { max: number; min: number }) => extent.max === extent.min ? extent.max + 1 : extent.max },
    series: [{ type: 'line', data: [...values], smooth: 0.4, symbol: 'none', silent: true, lineStyle: { color, width: 1.5 },
      areaStyle: { color: withAlpha(color, 0.14) } }] } as OverviewChartOption;
}

/** New customers per day (area) with a trailing 7-day average (line) on a labelled day axis. */
export function customerGrowthOption(points: readonly DailyCount[], theme: OverviewTheme, locale?: string, bucket: Bucket = 'day'): OverviewChartOption {
  const days = points.map(point => point.date);
  const counts = points.map(point => point.count);
  const average = movingAverage(counts, bucket === 'week' ? 4 : 7);
  const averageName = bucket === 'week' ? '4-week average' : '7-day average';
  return { ...base(theme),
    legend: { show: true, bottom: 0, left: 'center', icon: 'circle', itemWidth: 8, itemHeight: 8, itemGap: 14, textStyle: { color: theme.text, fontSize: 11 } },
    // boundaryGap is off so the last label sits on the right edge: reserve half a label of room for it.
    grid: { left: 8, right: 28, top: 12, bottom: 30, containLabel: true },
    tooltip: { ...tooltipBase(theme), trigger: 'axis', axisPointer: { type: 'line', lineStyle: { color: withAlpha(theme.text, 0.6), type: 'dashed' } },
      formatter: (raw: Params | Params[]) => {
        const list = Array.isArray(raw) ? raw : [raw];
        const first = list[0];
        if (!first) return '';
        const day = days[first.dataIndex] ?? String(first.axisValue ?? '');
        const rows = list.map(p => {
          const value = numberOf(p.value);
          const text = p.seriesIndex === 1 ? value.toLocaleString(locale, { maximumFractionDigits: 1 }) : value.toLocaleString(locale);
          return tooltipRow(p.color, p.seriesName ?? '', text);
        });
        return tooltipTitle(bucketTitle(day, bucket, locale)) + rows.join('');
      } },
    xAxis: { type: 'category', data: days, boundaryGap: false, axisLine: { lineStyle: { color: theme.grid } }, axisTick: { show: false },
      axisLabel: { color: theme.text, fontSize: 11, margin: 10, hideOverlap: true, interval: tickInterval(days.length), formatter: (day: string) => formatDayShort(day, locale) } },
    yAxis: { type: 'value', min: 0, minInterval: 1, splitNumber: 4, axisLine: { show: false }, axisTick: { show: false },
      axisLabel: { color: theme.text, fontSize: 11, formatter: (value: number) => value.toLocaleString(locale) }, splitLine: { lineStyle: { color: withAlpha(theme.grid, 0.9) } } },
    series: [
      { type: 'line', name: bucket === 'week' ? 'New customers per week' : 'New customers', data: counts, smooth: 0.3, symbol: 'circle', symbolSize: 5, showSymbol: false, z: 2,
        lineStyle: { color: theme.accent, width: 2 }, itemStyle: { color: theme.accent, borderColor: theme.surface, borderWidth: 1.5 },
        areaStyle: { color: withAlpha(theme.accent, 0.12) }, emphasis: { focus: 'none', scale: 1.4 } },
      { type: 'line', name: averageName, data: average, smooth: 0.4, symbol: 'none', z: 3,
        lineStyle: { color: theme.neutral, width: 1.5, type: 'dashed' }, itemStyle: { color: theme.neutral } },
    ] } as OverviewChartOption;
}

/** Two grouped daily bar series in one currency (e.g. settled spend vs declined, deposits vs withdrawals). */
export function pairedBarsOption(points: readonly DailyPair[], names: readonly [string, string], colors: readonly [string, string], currency: string,
  theme: OverviewTheme, formatAmount: (value: number, currency: string) => string, locale?: string, bucket: Bucket = 'day'): OverviewChartOption {
  const days = points.map(point => point.day);
  return { ...base(theme),
    legend: { show: true, bottom: 0, left: 'center', icon: 'circle', itemWidth: 8, itemHeight: 8, itemGap: 14, textStyle: { color: theme.text, fontSize: 11 } },
    grid: { left: 8, right: 12, top: 12, bottom: 30, containLabel: true },
    tooltip: { ...tooltipBase(theme), trigger: 'axis', axisPointer: { type: 'shadow', shadowStyle: { color: withAlpha(theme.grid, 0.45) } },
      formatter: (raw: Params | Params[]) => {
        const list = Array.isArray(raw) ? raw : [raw];
        const first = list[0];
        if (!first) return '';
        const rows = list.map(p => tooltipRow(p.color, p.seriesName ?? '', formatAmount(numberOf(p.value), currency)));
        return tooltipTitle(bucketTitle(points[first.dataIndex]?.day ?? String(first.axisValue ?? ''), bucket, locale)) + rows.join('');
      } },
    xAxis: { type: 'category', data: days, axisLine: { lineStyle: { color: theme.grid } }, axisTick: { show: false },
      axisLabel: { color: theme.text, fontSize: 11, margin: 10, hideOverlap: true, interval: tickInterval(days.length), formatter: (day: string) => formatDayShort(day, locale) } },
    yAxis: { type: 'value', min: 0, splitNumber: 4, axisLine: { show: false }, axisTick: { show: false },
      axisLabel: { color: theme.text, fontSize: 11, formatter: (value: number) => formatCompactAmount(value, currency, locale) }, splitLine: { lineStyle: { color: withAlpha(theme.grid, 0.9) } } },
    series: [
      { type: 'bar', name: names[0], data: points.map(point => point.first), barMaxWidth: 22, barGap: '10%', itemStyle: { color: colors[0], borderRadius: [3, 3, 0, 0] } },
      { type: 'bar', name: names[1], data: points.map(point => point.second), barMaxWidth: 22, itemStyle: { color: colors[1], borderRadius: [3, 3, 0, 0] } },
    ] } as OverviewChartOption;
}

/** Fee revenue per fee type as horizontal bars, largest first; refunded fees are a negative bar. */
export function feeBreakdownOption(rows: readonly FeeRow[], theme: OverviewTheme, formatAmount: (value: number, currency: string) => string, currency: string): OverviewChartOption {
  const sorted = [...rows].sort((a, b) => b.amount - a.amount);
  return { ...base(theme),
    grid: { left: 8, right: 96, top: 4, bottom: 4, containLabel: true },
    tooltip: { ...tooltipBase(theme), trigger: 'item', formatter: (p: Params) => {
      const row = sorted[p.dataIndex];
      return row ? tooltipRow(p.color, row.label, `${formatAmount(row.amount, currency)} · ${row.count.toLocaleString()} ${row.count === 1 ? 'charge' : 'charges'}`) : '';
    } },
    xAxis: { type: 'value', show: false },
    yAxis: { type: 'category', data: sorted.map(row => row.label), inverse: true, axisLine: { show: false }, axisTick: { show: false },
      axisLabel: { color: theme.text, fontSize: 12, fontWeight: 600, margin: 10 } },
    series: [{ type: 'bar', data: sorted.map(row => ({ value: row.amount, itemStyle: { color: row.amount < 0 ? theme.negative : theme.positive } })),
      barMaxWidth: 16, barCategoryGap: '38%', itemStyle: { borderRadius: 4 },
      label: { show: true, position: 'right', distance: 8, color: theme.text, fontSize: 12, fontWeight: 600, formatter: (p: Params) => { const row = sorted[p.dataIndex]; return row ? formatAmount(row.amount, currency) : ''; } } }] } as OverviewChartOption;
}

/** Onboarding steps in journey order; each stage is labelled with its count and share of the first step. */
export function funnelOption(steps: readonly FunnelStep[], theme: OverviewTheme, locale?: string): OverviewChartOption {
  const first = steps[0]?.value ?? 0;
  const shades = [theme.accent, withAlpha(theme.accent, 0.8), withAlpha(theme.accent, 0.6), withAlpha(theme.accent, 0.42), withAlpha(theme.accent, 0.3), withAlpha(theme.accent, 0.22)];
  const share = (value: number) => first > 0 ? `${Math.round((100 * value) / first)}%` : '–';
  const data = steps.map((step, index) => ({ name: step.label, value: step.value, itemStyle: { color: shades[Math.min(index, shades.length - 1)] } }));
  return { ...base(theme),
    tooltip: { ...tooltipBase(theme), trigger: 'item', formatter: (p: Params) => {
      const value = numberOf(p.value);
      return tooltipRow(p.color, p.name ?? '', `${value.toLocaleString(locale)} · ${share(value)} of ${steps[0]?.label ?? 'start'}`);
    } },
    series: [{ type: 'funnel', sort: 'none', funnelAlign: 'center', gap: 3, left: 8, right: '46%', top: 4, bottom: 4, minSize: '12%', maxSize: '100%', data,
      label: { show: true, position: 'right', formatter: (p: Params) => `{n|${p.name ?? ''}}\n{v|${numberOf(p.value).toLocaleString(locale)} · ${share(numberOf(p.value))}}`,
        rich: { n: { color: theme.text, fontSize: 11, lineHeight: 15 }, v: { color: theme.text, fontSize: 12, fontWeight: 600, lineHeight: 17 } } },
      labelLine: { length: 14, lineStyle: { color: theme.grid, width: 1 } }, itemStyle: { borderColor: theme.surface, borderWidth: 1 }, emphasis: { label: { fontSize: 12 } } }] } as OverviewChartOption;
}

/** Amounts in different currencies are not converted; when the largest is over 50× the smallest positive one, a log axis keeps every bar visible. */
export function balancesScale(bars: readonly BalanceBar[]): 'linear' | 'log' {
  const positive = bars.map(bar => bar.amount).filter(amount => amount > 0);
  if (positive.length < 2) return 'linear';
  return Math.max(...positive) / Math.min(...positive) > 50 ? 'log' : 'linear';
}
/** Horizontal bar per currency (largest first); `formatAmount` renders the labels, the "Others" bar has no currency. */
export function balancesOption(bars: readonly BalanceBar[], theme: OverviewTheme, formatAmount: (value: number, currency: string) => string, locale?: string): OverviewChartOption {
  const label = (bar: BalanceBar) => bar.currency ? formatAmount(bar.amount, bar.currency) : bar.amount.toLocaleString(locale, { maximumFractionDigits: 0 });
  const log = balancesScale(bars) === 'log';
  return { ...base(theme),
    grid: { left: 8, right: 120, top: 4, bottom: 4, containLabel: true },
    tooltip: { ...tooltipBase(theme), trigger: 'item', formatter: (p: Params) => {
      const bar = bars[p.dataIndex];
      if (!bar) return '';
      const extra = bar.currency ? '' : `<div style="opacity:.75">${bar.count} smaller currencies, amounts summed as plain numbers</div>`;
      return tooltipRow(p.color, bar.label, label(bar)) + extra;
    } },
    xAxis: log ? { type: 'log', min: 1, show: false } : { type: 'value', min: 0, show: false },
    yAxis: { type: 'category', data: bars.map(bar => bar.label), inverse: true, axisLine: { show: false }, axisTick: { show: false },
      axisLabel: { color: theme.text, fontSize: 12, fontWeight: 600, margin: 10 } },
    series: [{ type: 'bar', data: bars.map((bar, index) => ({ value: log && bar.amount <= 0 ? 1 : bar.amount, itemStyle: { color: bar.currency ? (index === 0 ? theme.accent : theme.accentSoft) : theme.neutralSoft } })),
      barMaxWidth: 18, barCategoryGap: '38%', itemStyle: { borderRadius: [0, 4, 4, 0] },
      label: { show: true, position: 'right', distance: 8, color: theme.text, fontSize: 12, fontWeight: 600, formatter: (p: Params) => { const bar = bars[p.dataIndex]; return bar ? label(bar) : ''; } } }] } as OverviewChartOption;
}
