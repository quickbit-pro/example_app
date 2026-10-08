import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/dashboard/domain/spending_insights.dart';

HoppaActivity _row(
  String id,
  String title,
  double amount, {
  DateTime? at,
  String status = 'Completed',
  String currency = 'USD',
  HoppaActivityKind kind = HoppaActivityKind.card,
}) =>
    HoppaActivity(
      id: id,
      title: title,
      subtitle: '',
      amount: amount,
      currency: currency,
      kind: kind,
      timeLabel: '',
      statusLabel: status,
      bookedAt: at,
    );

void main() {
  final now = DateTime(2026, 9, 15, 12);

  test('this month is summed on its own, last month is the comparison', () {
    final insights = SpendingInsights.compute([
      _row('a', 'Netflix', -9.99, at: DateTime(2026, 9, 2)),
      _row('b', 'Migros', -40, at: DateTime(2026, 9, 5)),
      _row('c', 'Migros', -60, at: DateTime(2026, 9, 9)),
      _row('d', 'Salary', 2000, at: DateTime(2026, 9, 1)),
      _row('e', 'Declined shop', -500,
          at: DateTime(2026, 9, 3), status: 'Declined'),
      _row('f', 'Netflix', -9.99, at: DateTime(2026, 8, 2)),
      _row('g', 'Big shop', -190.01, at: DateTime(2026, 8, 20)),
      _row('h', 'Old', -5, at: DateTime(2026, 7, 30)),
    ], now: now);
    expect(insights.currency, 'USD');
    expect(insights.spent, closeTo(109.99, 0.001));
    expect(insights.payments, 3);
    expect(insights.lastMonthSpent, closeTo(200, 0.001));
    expect(insights.changeFromLastMonth, closeTo(-45.005, 0.01));
    expect(insights.received, 2000);
    expect(insights.net, closeTo(1890.01, 0.001));
    expect(insights.topMerchant?.title, 'Migros');
    expect(insights.topMerchant?.count, 2);
    expect(insights.topMerchant?.total, 100);
    expect(insights.largest?.title, 'Migros');
    expect(insights.largest?.amount, 60);
    expect(insights.recurring.map((r) => r.title), ['Netflix']);
    expect(insights.hasHistory, isTrue);
  });

  test('a window that does not reach last month offers no comparison', () {
    final insights = SpendingInsights.compute([
      _row('a', 'Migros', -40, at: DateTime(2026, 9, 5)),
      _row('b', 'Shop', -10, at: DateTime(2026, 8, 28)),
    ], now: now);
    expect(insights.spent, 40);
    expect(insights.lastMonthSpent, isNull);
    expect(insights.changeFromLastMonth, isNull);
    expect(insights.topMerchant, isNull);
  });

  test('undated rows all count as this month and compare with nothing', () {
    final insights = SpendingInsights.compute([
      _row('a', 'Shop', -10),
      _row('b', 'Shop', -100, status: 'Failed'),
    ], now: now);
    expect(insights.spent, 10);
    expect(insights.payments, 1);
    expect(insights.lastMonthSpent, isNull);
  });

  test('an undated row among dated ones stays out of the month figures', () {
    final insights = SpendingInsights.compute([
      _row('a', 'Shop', -10, at: DateTime(2026, 9, 5)),
      _row('b', 'Mystery', -100),
    ], now: now);
    expect(insights.spent, 10);
    expect(insights.payments, 1);
  });

  test('only the dominant currency is totalled, never a mixed sum', () {
    final insights = SpendingInsights.compute([
      _row('a', 'Shop', -10, at: DateTime(2026, 9, 5)),
      _row('b', 'Shop', -20, at: DateTime(2026, 9, 6)),
      _row('c', 'Cafe', -300, at: DateTime(2026, 9, 7), currency: 'TRY'),
    ], now: now);
    expect(insights.currency, 'USD');
    expect(insights.spent, 30);
    expect(insights.payments, 2);
  });

  test('transfers are not merchants and are not recurring', () {
    final insights = SpendingInsights.compute([
      _row('a', 'Bank transfer', -100,
          at: DateTime(2026, 9, 5), kind: HoppaActivityKind.transfer),
      _row('b', 'Bank transfer', -100,
          at: DateTime(2026, 9, 9), kind: HoppaActivityKind.transfer),
      _row('c', 'Bank transfer', -100,
          at: DateTime(2026, 8, 1), kind: HoppaActivityKind.transfer),
    ], now: now);
    expect(insights.spent, 200);
    expect(insights.topMerchant, isNull);
    expect(insights.recurring, isEmpty);
    expect(insights.largest?.title, 'Bank transfer');
  });

  test('an empty ledger has no history', () {
    final insights = SpendingInsights.compute(const [], now: now);
    expect(insights.hasHistory, isFalse);
    expect(insights.currency, '');
  });
}
