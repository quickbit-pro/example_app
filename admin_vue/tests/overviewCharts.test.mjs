import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
// Same harness as chartConfig.test.mjs: transpile the pure modules and import them, no bundler needed.
async function load(file) {
  const source = readFileSync(new URL(`../src/lib/${file}`, import.meta.url), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
  return import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}
const charts = await load('overviewCharts.ts');
const demo = await load('overviewDemo.ts');
const { LIGHT_THEME, DARK_THEME, balanceBars, balancesOption, balancesScale, bucketFor, cumulative, customerGrowthOption, dayRange, feeBreakdownOption, formatCompactAmount,
  funnelConversions, funnelOption, greeting, isAllZero, movingAverage, needsYouItems, pairedBarsOption, pointTrend, readOverviewTheme, sparklineOption, tickInterval, trend,
  weekOf, weeklyBuckets, withAlpha } = charts;
const theme = LIGHT_THEME;
const money = (value, currency) => `${currency} ${value.toFixed(2)}`;

test('theme: CSS variables win per key, missing ones fall back to the light or dark defaults', () => {
  const t = readOverviewTheme(name => name === '--chart-accent' ? ' #123456 ' : '');
  assert.equal(t.accent, '#123456'); assert.equal(t.neutral, LIGHT_THEME.neutral); assert.equal(t.tooltipBackground, LIGHT_THEME.tooltipBackground);
  const dark = readOverviewTheme(() => null, true);
  assert.equal(dark.accent, DARK_THEME.accent); assert.equal(dark.surface, DARK_THEME.surface);
  assert.equal(withAlpha('#ff0000', .5), 'rgba(255, 0, 0, 0.5)'); assert.equal(withAlpha('red', .5), 'red');
});
test('numbers: cumulative sums, trailing average with a partial head, greeting by hour', () => {
  assert.deepEqual(cumulative([1, 2, 3]), [1, 3, 6]);
  assert.deepEqual(movingAverage([2, 4, 6, 8], 3), [2, 3, 4, 6]);
  assert.equal(movingAverage([], 7).length, 0);
  assert.equal(isAllZero([0, 0]), true); assert.equal(isAllZero([0, 1]), false); assert.equal(isAllZero([]), true);
  assert.equal(greeting(6), 'Good morning'); assert.equal(greeting(13), 'Good afternoon'); assert.equal(greeting(19), 'Good evening'); assert.equal(greeting(2), 'Good evening');
});
test('dates: inclusive day range, weekly ticks anchored on the last day, daily ticks for short ranges', () => {
  const days = dayRange(3, new Date(2026, 8, 11, 9));
  assert.deepEqual(days, ['2026-09-09', '2026-09-10', '2026-09-11']);
  const weekly = tickInterval(30);
  assert.equal(weekly(29), true); assert.equal(weekly(22), true); assert.equal(weekly(28), false); assert.equal(weekly(1), true);
  const daily = tickInterval(7);
  assert.equal([0, 1, 2, 3, 4, 5, 6].every(daily), true);
});
test('trends: percentage change on a real base, absolute change on a small one, tone follows whether higher is better', () => {
  assert.deepEqual(trend(120, 100), { label: '+20%', tone: 'positive' });
  assert.deepEqual(trend(80, 100), { label: '−20%', tone: 'negative' });
  assert.deepEqual(trend(80, 100, false), { label: '−20%', tone: 'positive' });
  // 2 → 4 is "+2", never "+100%".
  assert.deepEqual(trend(4, 2), { label: '+2', tone: 'positive' });
  assert.deepEqual(trend(5, 0), { label: '+5', tone: 'positive' });
  assert.deepEqual(trend(3, 7, false), { label: '−4', tone: 'positive' });
  assert.deepEqual(trend(7, 7), { label: '±0', tone: 'neutral' });
  assert.deepEqual(trend(145, 60, true, { minBase: 100, formatDelta: v => `$${v}` }), { label: '+$85', tone: 'positive' });
  assert.deepEqual(trend(300, 200, true, { minBase: 100 }), { label: '+50%', tone: 'positive' });
  assert.equal(trend(0, 0), null);
  assert.deepEqual(trend(100, 100), { label: '0%', tone: 'neutral' });
  assert.deepEqual(pointTrend(12.5, 10, false), { label: '+2.5 pts', tone: 'negative' });
  assert.deepEqual(pointTrend(8, 10, false), { label: '−2 pts', tone: 'positive' });
  assert.equal(pointTrend(null, 10), null);
  assert.match(formatCompactAmount(4700, 'USD', 'en-US'), /\$4\.7K/);
  assert.match(formatCompactAmount(1_200_000, 'HUF', 'en-US'), /1\.2M/);
});
test('weekly buckets: Monday-start weeks, sums per field, 30- and 90-day views go weekly', () => {
  assert.equal(weekOf('2026-09-25'), '2026-09-21');
  assert.equal(weekOf('2026-09-21'), '2026-09-21');
  assert.equal(weekOf('2026-09-27'), '2026-09-21');
  const days = [{ date: '2026-09-19', spend: 1.1, declines: 1 }, { date: '2026-09-21', spend: 2.2, declines: 0 }, { date: '2026-09-25', spend: 3.3, declines: 2 }];
  assert.deepEqual(weeklyBuckets(days, ['spend', 'declines']), [{ date: '2026-09-14', spend: 1.1, declines: 1 }, { date: '2026-09-21', spend: 5.5, declines: 2 }]);
  assert.equal(bucketFor(7), 'day'); assert.equal(bucketFor(30), 'week'); assert.equal(bucketFor(90), 'week');
  const weekly = customerGrowthOption([{ date: '2026-09-14', count: 4 }, { date: '2026-09-21', count: 6 }], theme, 'en-GB', 'week');
  assert.equal(weekly.series[1].name, '4-week average');
  assert.match(weekly.tooltip.formatter([{ seriesIndex: 0, seriesName: 'New customers per week', dataIndex: 1, value: 6 }]), /Week of Mon,? 21 Sept 2026/);
});
test('paired bars: two named daily series in one currency, formatted tooltip', () => {
  const points = [{ day: '2026-09-01', first: 500, second: 120 }, { day: '2026-09-02', first: 300, second: 80 }];
  const option = pairedBarsOption(points, ['Settled spend', 'Declined'], [theme.accent, theme.negative], 'USD', theme, money, 'en-GB');
  assert.deepEqual(option.series.map(s => s.name), ['Settled spend', 'Declined']);
  assert.deepEqual(option.series[0].data, [500, 300]); assert.deepEqual(option.series[1].data, [120, 80]);
  assert.equal(option.series[1].itemStyle.color, theme.negative);
  assert.equal(option.xAxis.axisLabel.formatter('2026-09-01'), '1 Sept');
  const html = option.tooltip.formatter([{ seriesName: 'Declined', dataIndex: 0, value: 120, color: '#000' }]);
  assert.match(html, /Declined: <b>USD 120\.00<\/b>/); assert.match(html, /Tue,? 1 Sept 2026/);
});
test('fee breakdown: largest fee type first, refunded fees as a negative red bar', () => {
  const rows = [{ type: 'top_up', label: 'Card top-up', amount: 101.31, count: 51 }, { type: 'card_issuance', label: 'Card issuance', amount: 219.78, count: 27 },
    { type: 'reversal', label: 'Refunded fees', amount: -39.96, count: 4 }];
  const option = feeBreakdownOption(rows, theme, money, 'USD');
  assert.deepEqual(option.yAxis.data, ['Card issuance', 'Card top-up', 'Refunded fees']);
  assert.equal(option.series[0].data[2].itemStyle.color, theme.negative);
  assert.equal(option.series[0].data[0].itemStyle.color, theme.positive);
  assert.equal(option.series[0].label.formatter({ dataIndex: 1 }), 'USD 101.31');
  assert.match(option.tooltip.formatter({ dataIndex: 0, color: '#000' }), /27 charges/);
});
test('growth option: area of daily counts plus a dashed 7-day average, exact day in the tooltip', () => {
  const points = Array.from({ length: 10 }, (_, i) => ({ date: `2026-09-${String(i + 1).padStart(2, '0')}`, count: i + 1 }));
  const option = customerGrowthOption(points, theme, 'en-GB');
  assert.equal(option.series.length, 2);
  assert.deepEqual(option.series[0].data, points.map(p => p.count));
  assert.deepEqual(option.series[1].data, movingAverage(points.map(p => p.count), 7));
  assert.equal(option.series[1].lineStyle.type, 'dashed');
  assert.equal(option.series[0].areaStyle.color, withAlpha(theme.accent, 0.12));
  assert.equal(option.yAxis.minInterval, 1);
  const html = option.tooltip.formatter([{ seriesIndex: 0, seriesName: 'New customers', dataIndex: 2, value: 3 }, { seriesIndex: 1, seriesName: '7-day average', dataIndex: 2, value: 2 }]);
  assert.match(html, /Thu,? 3 Sept 2026/); assert.match(html, /New customers: <b>3<\/b>/); assert.match(html, /7-day average: <b>2<\/b>/);
  assert.match(option.tooltip.textStyle.fontFamily, /Inter/);
});
test('funnel: journey order kept, share of the first step in labels, step-to-step conversion', () => {
  const steps = [{ key: 'a', label: 'Signed up', value: 200 }, { key: 'b', label: 'Verified', value: 150 }, { key: 'c', label: 'Funded', value: 60 }];
  assert.deepEqual(funnelConversions(steps), [{ from: 'Signed up', to: 'Verified', rate: 75 }, { from: 'Verified', to: 'Funded', rate: 40 }]);
  assert.deepEqual(funnelConversions([{ key: 'a', label: 'A', value: 0 }, { key: 'b', label: 'B', value: 0 }]), [{ from: 'A', to: 'B', rate: null }]);
  const option = funnelOption(steps, theme, 'en-GB');
  assert.equal(option.series[0].sort, 'none');
  assert.deepEqual(option.series[0].data.map(d => d.name), ['Signed up', 'Verified', 'Funded']);
  assert.equal(option.series[0].label.formatter({ name: 'Funded', value: 60, dataIndex: 2 }), '{n|Funded}\n{v|60 · 30%}');
  assert.match(option.tooltip.formatter({ name: 'Verified', value: 150, dataIndex: 1 }), /150 · 75% of Signed up/);
});
test('balances: top eight by amount with the rest folded into Others, labels formatted per currency', () => {
  const balances = Array.from({ length: 10 }, (_, i) => ({ currency: `C${i}`, amount: (i + 1) * 100 }));
  const bars = balanceBars(balances, 8);
  assert.equal(bars.length, 8);
  assert.equal(bars[0].currency, 'C9'); assert.equal(bars[0].amount, 1000);
  assert.deepEqual(bars[7], { label: 'Others (3)', currency: null, amount: 600, count: 3 });
  assert.equal(balanceBars(balances.slice(0, 8), 8).length, 8);
  assert.equal(balanceBars(balances.slice(0, 8), 8).every(b => b.currency), true);
  const option = balancesOption(bars, theme, money, 'en-US');
  assert.equal(option.yAxis.inverse, true);
  assert.equal(option.xAxis.type, 'value');
  const mixed = [{ label: 'HUF', currency: 'HUF', amount: 4_950_000, count: 1 }, { label: 'USD', currency: 'USD', amount: 12_000, count: 1 }, { label: 'ZAR', currency: 'ZAR', amount: 0, count: 1 }];
  assert.equal(balancesScale(bars), 'linear'); assert.equal(balancesScale(mixed), 'log'); assert.equal(balancesScale([mixed[0]]), 'linear');
  const logOption = balancesOption(mixed, theme, money, 'en-US');
  assert.equal(logOption.xAxis.type, 'log'); assert.equal(logOption.series[0].data[2].value, 1);
  assert.equal(logOption.series[0].label.formatter({ dataIndex: 2 }), 'ZAR 0.00');
  assert.deepEqual(option.yAxis.data.slice(0, 2), ['C9', 'C8']);
  assert.equal(option.series[0].label.formatter({ dataIndex: 0 }), 'C9 1000.00');
  assert.equal(option.series[0].label.formatter({ dataIndex: 7 }), '600');
  assert.match(option.tooltip.formatter({ dataIndex: 7 }), /3 smaller currencies/);
});
test('sparkline: no visible axes, no tooltip, a flat series still has a usable range', () => {
  const option = sparklineOption([3, 3, 3], theme, '#112233');
  assert.equal(option.xAxis.show, false); assert.equal(option.yAxis.show, false); assert.equal(option.tooltip.show, false);
  assert.equal(option.series[0].lineStyle.color, '#112233');
  assert.equal(option.yAxis.max({ min: 3, max: 3 }), 4); assert.equal(option.yAxis.max({ min: 1, max: 3 }), 3); assert.equal(option.yAxis.min({ min: 2 }), 0);
});
test('needs-you chips: only counts above zero, referral chip only when reconciliation loaded', () => {
  const items = needsYouItems({ attentionCount: 4, verificationAging: { pending: 6, over24Hours: 2, rejected: 0 }, failedReferralCredits: null });
  assert.deepEqual(items.map(i => i.key), ['followUp', 'pending', 'over24h']);
  assert.equal(items[0].to, '/customers?attention=true'); assert.equal(items[2].tone, 'warning');
  const failed = needsYouItems({ attentionCount: 0, verificationAging: { pending: 0, over24Hours: 0, rejected: 1 }, failedReferralCredits: 3 });
  assert.deepEqual(failed.map(i => [i.key, i.tone, i.to]), [['rejected', 'accent', '/verification'], ['failedCredits', 'danger', '/referrals']]);
  assert.deepEqual(needsYouItems({ attentionCount: 0, verificationAging: { pending: 0, over24Hours: 0, rejected: 0 }, failedReferralCredits: 0 }), []);
  const support = needsYouItems({ attentionCount: 0, verificationAging: { pending: 0, over24Hours: 0, rejected: 0 }, failedReferralCredits: 0, support: { awaiting: 2, oldestWaitingHours: 50 } });
  assert.deepEqual(support.map(i => [i.key, i.tone, i.to, i.label]), [['support', 'warning', '/support', 'tickets awaiting reply · oldest 2d']]);
  assert.equal(needsYouItems({ attentionCount: 0, verificationAging: { pending: 0, over24Hours: 0, rejected: 0 }, failedReferralCredits: 0, support: { awaiting: 1, oldestWaitingHours: 3 } })[0].tone, 'accent');
});
test('demo dataset: deterministic window, every KPI group filled, journey never widens', () => {
  const now = new Date(2026, 8, 11, 10);
  const data = demo.buildOverviewDemo(30, now);
  assert.equal(data.series.length, 30);
  assert.equal(data.series[29].date, '2026-09-11');
  assert.equal(data.series.every(p => p.signups >= 10 && p.signups <= 20), true);
  assert.equal(data.kpis.customers >= 300 && data.kpis.customers < 1000, true);
  assert.equal(data.kpis.newCustomers.current, data.series.reduce((s, p) => s + p.signups, 0));
  assert.equal(data.funnel.length, 7);
  assert.equal(data.stages.length, 9);
  assert.equal(data.cohorts.length, 8);
  assert.equal(data.cohorts.every((cohort, i, all) => cohort.weeks.length === all.length - i), true);
  assert.ok(data.declines.byMerchant.length && data.segments.source.length && data.timeZone && data.generatedAt);
  assert.equal(demo.DEMO_INSIGHTS.items.every(item => item.link?.startsWith('/')), true);
  assert.equal(data.funnel.every((step, i) => i === 0 || step.value <= data.funnel[i - 1].value), true);
  assert.equal(data.revenue.byType.length > 0 && data.cards.spend.amount > 0 && data.money.deposits.amount > 0, true);
  assert.equal(data.attention.length, 3);
  assert.deepEqual(data.verificationAging, { pending: 6, over24Hours: 2, rejected: 1 });
  assert.ok(data.updatedAt);
  assert.deepEqual(demo.buildOverviewDemo(30, now), data);
  assert.equal(demo.buildOverviewDemo(7, now).series.length, 7);
  assert.equal(demo.DEMO_REFERRALS.creditsFailed, 1);
});
