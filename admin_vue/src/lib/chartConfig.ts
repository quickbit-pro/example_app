// Pure ECharts option builders for the admin analytics charts. No DOM access here: the
// AnalyticsChart component reads the palette from the --chart-* CSS variables and hands it in,
// so this module can be unit-tested with node:test like referrals.ts. The ECharts modules are
// registered in lib/echarts.ts; this file only imports types.
import type { BarSeriesOption, FunnelSeriesOption, LineSeriesOption, PieSeriesOption } from 'echarts/charts';
import type { GridComponentOption, LegendComponentOption, TooltipComponentOption } from 'echarts/components';
import type { ComposeOption } from 'echarts/core';

export type ChartOption = ComposeOption<BarSeriesOption | LineSeriesOption | PieSeriesOption | FunnelSeriesOption | GridComponentOption | TooltipComponentOption | LegendComponentOption>;
export type ChartKind = 'line' | 'bar' | 'horizontalBar' | 'doughnut' | 'funnel';
/** Small fixed palette: accent for the primary series, neutrals for context, red only for negatives. */
export type SeriesColor = 'accent' | 'accentSoft' | 'accentFaint' | 'neutral' | 'neutralSoft' | 'negative' | 'positive';
export interface ChartSeries {
  label: string;
  data: (number | null)[];
  /** One colour for the series, or one per slice/bar/stage (doughnuts, funnels, single-series bars). */
  color: SeriesColor | SeriesColor[];
  /** Mixed charts: a 'line' series on a 'bar' chart (or the other way round). */
  type?: 'line' | 'bar';
  /** 'y1' puts the series on the secondary (right-hand) value axis. */
  axis?: 'y' | 'y1';
  stack?: string;
  dashed?: boolean;
  fill?: boolean;
  /** Tooltip value formatter; receives the point index so callers can show a signed amount behind an absolute slice. */
  format?: (value: number, index: number) => string;
}
export interface ChartTheme {
  colors: Record<SeriesColor, string>;
  text: string; grid: string; surface: string; tooltipBackground: string; tooltipText: string;
}
export interface ChartFormatting {
  /** Tick formatter of the primary value axis (y, or x on horizontal bars). Also the tooltip fallback for series without `format`. */
  formatY?: (value: number) => string;
  /** Tick formatter of the secondary value axis (y1). */
  formatY1?: (value: number) => string;
  /** Extra tooltip lines under the value, per series and point. */
  tooltipExtra?: (seriesIndex: number, index: number) => string | string[] | undefined;
  /** Horizontal bars: text drawn beside each bar of the first series. Funnels: the detail line under each stage name. */
  barLabels?: (value: number, index: number) => string;
  titleX?: string; titleY?: string; titleY1?: string;
  /** Stacks every bar series that has no explicit `stack` of its own. */
  stacked?: boolean;
  /** Defaults to true for doughnuts and multi-series charts. */
  legend?: boolean;
}
/** The subset of ECharts callback params the builders read; kept local so tests can pass plain objects. */
export interface CallbackParams {
  seriesIndex?: number; dataIndex: number; seriesName?: string; name?: string; value?: unknown; color?: string;
  axisValue?: string | number; axisValueLabel?: string;
}

export const FONT_FAMILY = 'Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif';
export const THEME_VARIABLES = {
  accent: '--chart-accent', accentSoft: '--chart-accent-soft', accentFaint: '--chart-accent-faint', neutral: '--chart-neutral',
  neutralSoft: '--chart-neutral-soft', negative: '--chart-negative', positive: '--chart-positive',
  text: '--chart-text', grid: '--chart-grid', surface: '--chart-surface', tooltipBackground: '--chart-tooltip-bg', tooltipText: '--chart-tooltip-text',
} as const;
/** Same values as the :root declarations in styles.css, used when a variable is missing (tests, detached nodes). */
export const FALLBACK_THEME: ChartTheme = {
  colors: { accent: '#1d4ed8', accentSoft: '#93c5fd', accentFaint: '#dbeafe', neutral: '#64748b', neutralSoft: '#cbd5e1', negative: '#dc2626', positive: '#059669' },
  text: '#64748b', grid: '#e2e8f0', surface: '#ffffff', tooltipBackground: '#0f172a', tooltipText: '#f8fafc',
};
const SLICE_ORDER: SeriesColor[] = ['accent', 'accentSoft', 'neutral', 'neutralSoft', 'accentFaint', 'positive', 'negative'];

/** Builds the theme from a CSS variable reader (getComputedStyle(...).getPropertyValue), falling back per variable. */
export function readTheme(read: (variable: string) => string | null | undefined): ChartTheme {
  const value = (variable: string, fallback: string) => (read(variable) ?? '').trim() || fallback;
  const colors = Object.fromEntries((Object.keys(FALLBACK_THEME.colors) as SeriesColor[]).map(key => [key, value(THEME_VARIABLES[key], FALLBACK_THEME.colors[key])])) as Record<SeriesColor, string>;
  return { colors, text: value(THEME_VARIABLES.text, FALLBACK_THEME.text), grid: value(THEME_VARIABLES.grid, FALLBACK_THEME.grid),
    surface: value(THEME_VARIABLES.surface, FALLBACK_THEME.surface), tooltipBackground: value(THEME_VARIABLES.tooltipBackground, FALLBACK_THEME.tooltipBackground),
    tooltipText: value(THEME_VARIABLES.tooltipText, FALLBACK_THEME.tooltipText) };
}
/** A chart with no labels, no series or only zero/missing values shows the placeholder instead of an empty canvas. */
export function isEmptySeries(labels: readonly string[], series: readonly ChartSeries[]): boolean {
  return !labels.length || !series.length || series.every(s => s.data.every(v => typeof v !== 'number' || !Number.isFinite(v) || v === 0));
}
/** "#rrggbb" → "rgba(r,g,b,a)"; other colour syntaxes are returned unchanged. */
export function withAlpha(color: string, alpha: number): string {
  const match = /^#([0-9a-f]{6})$/i.exec(color.trim());
  if (!match) return color;
  const n = parseInt(match[1]!, 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
}
/** Tooltips are HTML: names, e-mails and reason codes from the payload are escaped before they are rendered. */
export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] ?? c);
}
/** ECharts hands the point value as a number, an [x, y] pair or a `{ value }` data item depending on the series. */
export function numberOf(value: unknown): number {
  if (typeof value === 'number') return value;
  if (Array.isArray(value)) return numberOf(value[value.length - 1]);
  if (value && typeof value === 'object' && 'value' in value) return numberOf((value as { value: unknown }).value);
  return value == null || value === '' ? Number.NaN : Number(value);
}
const defaultFormat = (value: number) => value.toLocaleString();
const marker = (color: string | undefined) => color ? `<span style="display:inline-block;width:8px;height:8px;margin-right:6px;border-radius:50%;background:${escapeHtml(color)}"></span>` : '';
function extraLines(extra: string | string[] | undefined): string {
  const lines = extra == null ? [] : Array.isArray(extra) ? extra : [extra];
  return lines.filter(Boolean).map(line => `<div style="opacity:.75">${escapeHtml(line)}</div>`).join('');
}
/** One colour per data point: a single key repeats, an array cycles. */
function colorsOf(series: ChartSeries, count: number, theme: ChartTheme): string[] {
  const keys = Array.isArray(series.color) ? series.color : [series.color];
  return Array.from({ length: Math.max(count, 1) }, (_, i) => theme.colors[keys[i % keys.length] ?? 'accent']);
}

type Loose = Record<string, unknown>;

export function buildChartOption(kind: ChartKind, labels: readonly string[], series: readonly ChartSeries[], theme: ChartTheme, formatting: ChartFormatting = {}): ChartOption {
  const count = labels.length;
  const legend = formatting.legend ?? (kind === 'doughnut' || series.length > 1);
  const horizontal = kind === 'horizontalBar';
  const formatFor = (seriesIndex: number, index: number, value: number) => {
    const s = series[seriesIndex];
    if (s?.format) return s.format(value, index);
    const axisFormat = s?.axis === 'y1' ? formatting.formatY1 : formatting.formatY;
    return (axisFormat ?? defaultFormat)(value);
  };
  // A scrolling legend stays on one row at any width, so it never wraps into the category axis labels.
  const legendOption: Loose = { show: legend, type: 'scroll', bottom: 0, left: 'center', icon: 'circle', itemWidth: 8, itemHeight: 8, itemGap: 14,
    textStyle: { color: theme.text, fontSize: 11 }, inactiveColor: withAlpha(theme.text, 0.35),
    pageIconSize: 10, pageIconColor: theme.text, pageIconInactiveColor: withAlpha(theme.text, 0.3), pageTextStyle: { color: theme.text, fontSize: 11 } };
  const tooltipBase: Loose = { backgroundColor: theme.tooltipBackground, borderWidth: 0, padding: [8, 12], appendToBody: true,
    textStyle: { color: theme.tooltipText, fontSize: 12, fontFamily: FONT_FAMILY }, extraCssText: 'border-radius:8px;box-shadow:0 6px 20px rgba(15,23,42,.18);' };
  const base: Loose = { textStyle: { fontFamily: FONT_FAMILY, color: theme.text }, animationDuration: 350, animationDurationUpdate: 350, legend: legendOption };

  // One series, one slice/stage per label: doughnut and funnel share the item tooltip.
  if (kind === 'doughnut' || kind === 'funnel') {
    const s = series[0];
    const values = labels.map((_, i) => s?.data[i] ?? null);
    const colors = s && (Array.isArray(s.color) || kind === 'funnel') ? colorsOf(s, count, theme) : SLICE_ORDER.map(key => theme.colors[key]);
    const total = values.reduce<number>((sum, v) => sum + (typeof v === 'number' && Number.isFinite(v) ? Math.abs(v) : 0), 0);
    const data = labels.map((name, i) => ({ name, value: values[i], itemStyle: { color: colors[i % colors.length] } }));
    const tooltip: Loose = { ...tooltipBase, trigger: 'item', formatter: (p: CallbackParams) => {
      const value = numberOf(p.value);
      if (!Number.isFinite(value)) return '';
      const share = kind === 'doughnut' && total > 0 ? ` (${((100 * Math.abs(value)) / total).toFixed(1)}%)` : '';
      return `<div>${marker(p.color)}${escapeHtml(p.name ?? '')}: <b>${escapeHtml(formatFor(0, p.dataIndex, value))}</b>${share}</div>${extraLines(formatting.tooltipExtra?.(0, p.dataIndex))}`;
    } };
    if (kind === 'doughnut') {
      return { ...base, tooltip, series: [{ type: 'pie', name: s?.label ?? '', radius: ['55%', '78%'], center: ['50%', legend ? '44%' : '50%'], data, avoidLabelOverlap: false,
        label: { show: false }, labelLine: { show: false }, itemStyle: { borderColor: theme.surface, borderWidth: 2 }, emphasis: { scale: true, scaleSize: 4 } }] } as ChartOption;
    }
    // The journey stays in data order (sort none); every stage carries "name" over "count · share" to its right.
    const label: Loose = { show: true, position: 'right', formatter: (p: CallbackParams) => {
      const value = numberOf(p.value);
      const detail = Number.isFinite(value) ? (formatting.barLabels ? formatting.barLabels(value, p.dataIndex) : formatFor(0, p.dataIndex, value)) : '';
      return `{n|${p.name ?? ''}}\n{v|${detail}}`;
    }, rich: { n: { color: theme.text, fontSize: 11, lineHeight: 15 }, v: { color: theme.text, fontSize: 12, fontWeight: 600, lineHeight: 17 } } };
    return { ...base, legend: { ...legendOption, show: false }, tooltip, series: [{ type: 'funnel', name: s?.label ?? '', sort: 'none', funnelAlign: 'center', gap: 2,
      left: 8, right: '48%', top: 6, bottom: 6, minSize: '10%', maxSize: '100%', data, label, labelLine: { length: 14, lineStyle: { color: theme.grid, width: 1 } },
      itemStyle: { borderColor: theme.surface, borderWidth: 1 }, emphasis: { label: { fontSize: 12 } } }] } as ChartOption;
  }

  // Cartesian charts: bars and lines on a category axis with one or two value axes.
  const typeOf = (s: ChartSeries) => s.type ?? (kind === 'line' ? 'line' : 'bar');
  const hasLine = series.some(s => typeOf(s) === 'line');
  const hasBar = series.some(s => typeOf(s) === 'bar');
  const hasY1 = !horizontal && series.some(s => s.axis === 'y1');
  const stackOf = (s: ChartSeries) => s.stack ?? (formatting.stacked ? 'total' : undefined);
  const stacked = series.some(s => typeOf(s) === 'bar' && !!stackOf(s));
  const integerAxis = (axis: 'y' | 'y1') => series.filter(s => (s.axis ?? 'y') === axis).every(s => s.data.every(v => v == null || Number.isInteger(v)));
  const pointer = hasLine && hasBar ? 'cross' : hasLine ? 'line' : 'shadow';
  const valueDimension = horizontal ? 'x' : 'y';
  const nameStyle = (align: 'left' | 'right' | 'center') => ({ color: theme.text, fontSize: 11, align });
  const valueAxis = (format: ChartFormatting['formatY'], title: string | undefined, position: 'left' | 'right' | 'bottom', showGrid: boolean, integer: boolean): Loose => ({
    type: 'value', position: position === 'bottom' ? undefined : position, min: 0, minInterval: integer ? 1 : undefined, splitNumber: 5,
    name: title, nameLocation: position === 'bottom' ? 'middle' : 'end', nameGap: position === 'bottom' ? 26 : 14, nameTextStyle: nameStyle(position === 'right' ? 'right' : position === 'left' ? 'left' : 'center'),
    axisLine: { show: false }, axisTick: { show: false },
    axisLabel: { color: theme.text, fontSize: 11, margin: 6, formatter: (value: number) => (format ?? defaultFormat)(value) },
    splitLine: { show: showGrid, lineStyle: { color: withAlpha(theme.grid, 0.9) } },
  });
  const categoryAxis = (title: string | undefined): Loose => ({
    type: 'category', data: [...labels], inverse: horizontal, boundaryGap: true,
    name: title, nameLocation: horizontal ? 'end' : 'middle', nameGap: horizontal ? 14 : 26, nameTextStyle: nameStyle(horizontal ? 'right' : 'center'),
    axisLine: { lineStyle: { color: theme.grid } }, axisTick: { show: false }, splitLine: { show: false },
    axisLabel: { color: theme.text, fontSize: 11, margin: 8, hideOverlap: true, interval: horizontal ? 0 : 'auto', ...(horizontal ? { width: 140, overflow: 'truncate' } : {}) },
  });
  const titleTop = !horizontal && !!(formatting.titleY || formatting.titleY1);
  const grid: Loose = { left: 8, right: horizontal && formatting.barLabels ? 96 : 12, top: titleTop ? 30 : 12, containLabel: true,
    bottom: (legend ? 30 : 4) + (horizontal && formatting.titleY ? 22 : 0) + (!horizontal && formatting.titleX ? 22 : 0) };
  const tooltip: Loose = { ...tooltipBase, trigger: 'axis', axisPointer: {
    type: pointer, lineStyle: { color: withAlpha(theme.text, 0.6), type: 'dashed' }, crossStyle: { color: withAlpha(theme.text, 0.6), type: 'dashed' }, shadowStyle: { color: withAlpha(theme.grid, 0.45) },
    label: { show: pointer === 'cross', backgroundColor: theme.tooltipBackground, color: theme.tooltipText, fontSize: 11, borderRadius: 4, padding: [3, 6],
      formatter: (p: { value: unknown; axisDimension?: string; axisIndex?: number }) => p.axisDimension === valueDimension
        ? ((p.axisIndex === 1 ? formatting.formatY1 : formatting.formatY) ?? defaultFormat)(numberOf(p.value)) : String(p.value ?? '') },
  }, formatter: (params: CallbackParams | CallbackParams[]) => {
    const points = (Array.isArray(params) ? params : [params]).filter(p => Number.isFinite(numberOf(p.value)));
    if (!points.length) return '';
    const first = points[0]!;
    const title = first.axisValueLabel ?? first.axisValue ?? first.name ?? '';
    const rows = points.map(p => {
      const seriesIndex = p.seriesIndex ?? 0;
      return `<div>${marker(p.color)}${escapeHtml(p.seriesName ?? '')}: <b>${escapeHtml(formatFor(seriesIndex, p.dataIndex, numberOf(p.value)))}</b></div>${extraLines(formatting.tooltipExtra?.(seriesIndex, p.dataIndex))}`;
    });
    return `<div style="font-weight:600;margin-bottom:4px">${escapeHtml(String(title))}</div>${rows.join('')}`;
  } };
  const built = series.map((s, index): Loose => {
    const colors = colorsOf(s, count, theme);
    const perPoint = Array.isArray(s.color) && s.color.length > 1;
    const data = perPoint ? s.data.map((value, i) => ({ value, itemStyle: { color: colors[i] } })) : [...s.data];
    const common: Loose = { name: s.label, data, yAxisIndex: hasY1 && s.axis === 'y1' ? 1 : 0 };
    if (typeOf(s) === 'line') {
      return { ...common, type: 'line', smooth: 0.3, symbol: 'circle', symbolSize: 6, connectNulls: true, z: 3,
        lineStyle: { color: colors[0], width: 2, type: s.dashed ? 'dashed' : 'solid' }, itemStyle: { color: colors[0], borderColor: theme.surface, borderWidth: 1.5 },
        areaStyle: s.fill ? { color: withAlpha(colors[0]!, 0.15) } : undefined, emphasis: { focus: 'none', scale: 1.5 } };
    }
    const label = horizontal && index === 0 && formatting.barLabels ? { show: true, position: 'right', distance: 8, color: theme.text, fontSize: 12, fontWeight: 600,
      formatter: (p: CallbackParams) => { const value = numberOf(p.value); return Number.isFinite(value) ? formatting.barLabels!(value, p.dataIndex) : ''; } } : undefined;
    return { ...common, type: 'bar', stack: stackOf(s), barMaxWidth: horizontal ? 26 : 36, z: 2, label,
      itemStyle: { color: colors[0], borderRadius: stacked ? 0 : horizontal ? [0, 4, 4, 0] : [4, 4, 0, 0] } };
  });
  const axes = horizontal
    ? { xAxis: valueAxis(formatting.formatY, formatting.titleY, 'bottom', true, integerAxis('y')), yAxis: categoryAxis(formatting.titleX) }
    : { xAxis: categoryAxis(formatting.titleX), yAxis: [valueAxis(formatting.formatY, formatting.titleY, 'left', true, integerAxis('y')),
      ...(hasY1 ? [valueAxis(formatting.formatY1, formatting.titleY1, 'right', false, integerAxis('y1'))] : [])] };
  return { ...base, tooltip, grid, ...axes, series: built } as ChartOption;
}
