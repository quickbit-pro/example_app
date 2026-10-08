import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
// Same harness as referrals.test.mjs: transpile the pure module and import it, no bundler needed.
// The module only imports ECharts *types*, which the transpile erases, so nothing from node_modules is loaded.
const source = readFileSync(new URL('../src/lib/chartConfig.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
assert.doesNotMatch(js, /from ['"]echarts/, 'chartConfig must stay free of runtime ECharts imports');
const { FALLBACK_THEME, buildChartOption, escapeHtml, isEmptySeries, numberOf, readTheme, withAlpha } = await import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
const theme = FALLBACK_THEME;
const weeks = ['1 Jan', '8 Jan', '15 Jan'];
const strip = html => html.replace(/<[^>]+>/g, '');

test('empty detection: no labels, no series or only zeros show the placeholder', () => {
  assert.equal(isEmptySeries([], [{ label: 'a', data: [1], color: 'accent' }]), true);
  assert.equal(isEmptySeries(weeks, []), true);
  assert.equal(isEmptySeries(weeks, [{ label: 'a', data: [0, null, NaN], color: 'accent' }]), true);
  assert.equal(isEmptySeries(weeks, [{ label: 'a', data: [0, 0, 2], color: 'accent' }]), false);
});
test('theme falls back per variable when the CSS variable is missing', () => {
  const t = readTheme(name => name === '--chart-accent' ? ' #123456 ' : '');
  assert.equal(t.colors.accent, '#123456'); assert.equal(t.colors.neutral, FALLBACK_THEME.colors.neutral); assert.equal(t.text, FALLBACK_THEME.text);
  assert.equal(withAlpha('#ff0000', .5), 'rgba(255, 0, 0, 0.5)'); assert.equal(withAlpha('red', .5), 'red');
});
test('value extraction and escaping helpers', () => {
  assert.equal(numberOf(4), 4); assert.equal(numberOf([1, 7]), 7); assert.equal(numberOf({ value: 3 }), 3); assert.ok(Number.isNaN(numberOf(null)));
  assert.equal(escapeHtml('<b>a & "b"</b>'), '&lt;b&gt;a &amp; &quot;b&quot;&lt;/b&gt;');
});
test('mixed weekly chart: lines and bars on two axes, cross pointer, per-axis formatters', () => {
  const option = buildChartOption('bar', weeks, [
    { label: 'Attributed', data: [3, 4, 5], color: 'neutral', type: 'line' },
    { label: 'Top-up volume', data: [10, 20, 30.5], color: 'accentFaint', type: 'bar', axis: 'y1', format: v => `$${v}` },
  ], theme, { formatY: v => `${v} rel`, formatY1: v => `$${v}`, titleY: 'Relationships', titleY1: 'Volume' });
  assert.deepEqual(option.xAxis.data, weeks); assert.equal(option.xAxis.type, 'category'); assert.equal(option.xAxis.inverse, false);
  assert.equal(option.series[0].type, 'line'); assert.equal(option.series[0].lineStyle.color, theme.colors.neutral); assert.equal(option.series[0].yAxisIndex, 0);
  assert.equal(option.series[1].type, 'bar'); assert.equal(option.series[1].yAxisIndex, 1); assert.equal(option.series[1].itemStyle.color, theme.colors.accentFaint);
  assert.equal(option.yAxis.length, 2, 'secondary axis is created when a series uses y1');
  assert.equal(option.yAxis[0].axisLabel.formatter(4), '4 rel'); assert.equal(option.yAxis[1].axisLabel.formatter(20), '$20');
  assert.equal(option.yAxis[0].minInterval, 1, 'count axis keeps integer ticks'); assert.equal(option.yAxis[1].minInterval, undefined, 'money axis may use fractional ticks');
  assert.equal(option.yAxis[0].name, 'Relationships'); assert.equal(option.yAxis[1].position, 'right'); assert.equal(option.yAxis[1].splitLine.show, false);
  assert.equal(option.legend.show, true); assert.equal(option.legend.type, 'scroll', 'legend stays on one row instead of wrapping into the axis labels');
  assert.equal(option.tooltip.trigger, 'axis'); assert.equal(option.tooltip.axisPointer.type, 'cross');
  assert.equal(option.tooltip.axisPointer.label.formatter({ value: 20, axisDimension: 'y', axisIndex: 1 }), '$20');
  assert.equal(option.tooltip.axisPointer.label.formatter({ value: '8 Jan', axisDimension: 'x', axisIndex: 0 }), '8 Jan');
  const html = option.tooltip.formatter([
    { seriesIndex: 0, dataIndex: 1, seriesName: 'Attributed', value: 4, color: '#111', axisValueLabel: '8 Jan' },
    { seriesIndex: 1, dataIndex: 1, seriesName: 'Top-up volume', value: 20, color: '#222' },
  ]);
  assert.match(strip(html), /^8 JanAttributed: 4 relTop-up volume: \$20$/);
  assert.equal(option.tooltip.formatter([{ seriesIndex: 0, dataIndex: 0, value: null }]), '', 'points without a value are dropped');
});
test('pure line chart uses a line pointer and dashed styles', () => {
  const option = buildChartOption('line', weeks, [{ label: 'a', data: [1, 2, 3], color: 'accent' }, { label: 'b', data: [1, 1, 1], color: 'accent', dashed: true, fill: true }], theme);
  assert.equal(option.tooltip.axisPointer.type, 'line'); assert.equal(option.tooltip.axisPointer.label.show, false);
  assert.equal(option.series[1].lineStyle.type, 'dashed'); assert.equal(option.series[1].areaStyle.color, withAlpha(theme.colors.accent, .15)); assert.equal(option.series[0].areaStyle, undefined);
});
test('horizontal bars: value axis on x, category inverted, bar labels, per-bar colours and extra tooltip lines', () => {
  const option = buildChartOption('horizontalBar', ['Maja', 'Luka'], [{ label: 'Rewards', data: [10, 4], color: ['accent', 'accentSoft'] }], theme,
    { barLabels: (v, i) => `${v} · ${i}`, tooltipExtra: (_, i) => [i === 0 ? 'Partner' : '', 'Paid 3'], legend: false, titleY: 'Rewards' });
  assert.equal(option.xAxis.type, 'value'); assert.equal(option.xAxis.name, 'Rewards'); assert.equal(option.xAxis.nameLocation, 'middle');
  assert.equal(option.yAxis.type, 'category'); assert.equal(option.yAxis.inverse, true, 'first row is drawn at the top');
  assert.ok(option.grid.right >= 80, 'room is reserved beside the bars for their labels');
  assert.equal(option.legend.show, false);
  assert.equal(option.tooltip.axisPointer.type, 'shadow');
  assert.deepEqual(option.series[0].data.map(d => d.itemStyle.color), [theme.colors.accent, theme.colors.accentSoft]);
  assert.deepEqual(option.series[0].itemStyle.borderRadius, [0, 4, 4, 0]);
  assert.equal(option.series[0].label.formatter({ value: 4, dataIndex: 1 }), '4 · 1');
  const html = option.tooltip.formatter([{ seriesIndex: 0, dataIndex: 0, seriesName: 'Rewards', value: 10, axisValue: 'Maja' }]);
  assert.equal(strip(html), 'MajaRewards: 10PartnerPaid 3', 'empty extra lines are skipped');
});
test('tooltip escapes names from the payload', () => {
  const option = buildChartOption('horizontalBar', ['<img>'], [{ label: 'x', data: [1], color: 'accent' }], theme);
  const html = option.tooltip.formatter([{ seriesIndex: 0, dataIndex: 0, seriesName: 'a<b', value: 1, axisValue: '<img>' }]);
  assert.doesNotMatch(html, /<img>|a<b/); assert.match(html, /&lt;img&gt;/);
});
test('doughnut: pie with the requested radius, palette per slice, share in the tooltip and signed formatting by index', () => {
  const amounts = [30, -10];
  const option = buildChartOption('doughnut', ['Welcome', 'Adjustments'], [{ label: 'Cost', data: amounts.map(Math.abs), color: ['accent', 'neutral'], format: (_, i) => `${amounts[i]} USD` }], theme);
  const pie = option.series[0];
  assert.equal(pie.type, 'pie'); assert.deepEqual(pie.radius, ['55%', '78%']);
  assert.deepEqual(pie.data.map(d => [d.name, d.value, d.itemStyle.color]), [['Welcome', 30, theme.colors.accent], ['Adjustments', 10, theme.colors.neutral]]);
  assert.equal(option.xAxis, undefined); assert.equal(option.yAxis, undefined); assert.equal(option.legend.show, true);
  assert.equal(option.tooltip.trigger, 'item');
  assert.equal(strip(option.tooltip.formatter({ dataIndex: 1, name: 'Adjustments', value: 10 })), 'Adjustments: -10 USD (25.0%)');
  const defaults = buildChartOption('doughnut', ['a', 'b'], [{ label: 'Cost', data: [1, 2], color: 'accent' }], theme);
  assert.deepEqual(defaults.series[0].data.map(d => d.itemStyle.color), [theme.colors.accent, theme.colors.accentSoft], 'single colour falls back to the slice order');
});
test('funnel: real funnel series in journey order with "name / count · share" labels', () => {
  const stages = ['Invited', 'KYC completed', 'Qualified'];
  const option = buildChartOption('funnel', stages, [{ label: 'Relationships', data: [340, 212, 121], color: ['accentSoft', 'accentSoft', 'accent'] }], theme,
    { barLabels: (v, i) => `${v} · ${[100, 62.4, 35.6][i]}%`, tooltipExtra: (_, i) => `${[100, 62.4, 35.6][i]}% of invited` });
  const funnel = option.series[0];
  assert.equal(funnel.type, 'funnel'); assert.equal(funnel.sort, 'none', 'stages keep the journey order');
  assert.deepEqual(funnel.data.map(d => d.name), stages); assert.deepEqual(funnel.data.map(d => d.value), [340, 212, 121]);
  assert.equal(funnel.data[2].itemStyle.color, theme.colors.accent);
  assert.equal(funnel.label.position, 'right');
  assert.equal(funnel.label.formatter({ name: 'KYC completed', value: 212, dataIndex: 1 }), '{n|KYC completed}\n{v|212 · 62.4%}');
  assert.equal(option.legend.show, false);
  assert.equal(strip(option.tooltip.formatter({ dataIndex: 1, name: 'KYC completed', value: 212 })), 'KYC completed: 21262.4% of invited');
});
test('stacked flag stacks every bar series and drops the bar radius', () => {
  const explicit = buildChartOption('horizontalBar', ['Accrued'], [{ label: 'Paid', data: [1], color: 'accent', stack: 'c' }, { label: 'Outstanding', data: [2], color: 'neutralSoft', stack: 'c' }], theme);
  assert.equal(explicit.series[0].stack, 'c'); assert.equal(explicit.series[1].stack, 'c'); assert.equal(explicit.series[0].itemStyle.borderRadius, 0);
  const implicit = buildChartOption('horizontalBar', ['Accrued'], [{ label: 'Paid', data: [1], color: 'accent' }, { label: 'Outstanding', data: [2], color: 'neutralSoft' }], theme, { stacked: true });
  assert.equal(implicit.series[0].stack, 'total'); assert.equal(implicit.series[1].stack, 'total');
  const grouped = buildChartOption('bar', ['A', 'B'], [{ label: 'Paid', data: [1, 2], color: 'accent' }, { label: 'Outstanding', data: [2, 3], color: 'neutralSoft' }], theme);
  assert.equal(grouped.series[0].stack, undefined); assert.deepEqual(grouped.series[0].itemStyle.borderRadius, [4, 4, 0, 0]);
});
