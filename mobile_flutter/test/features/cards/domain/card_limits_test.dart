import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/cards/domain/card_limits.dart';
import 'package:mobile_flutter/features/cards/presentation/card_limits_sheet.dart';

void main() {
  test('parses current limits and tier caps', () {
    final info = CardLimitsInfo.fromJson({
      'currency': 'usd',
      'current': {
        'daily': 250,
        'monthly': '3000',
        'updatedAt': '2026-09-04T10:00:00Z'
      },
      'caps': {'daily': 500, 'weekly': 2000, 'monthly': 6000},
      'capSource': 'card_type',
      'tierName': 'Pro',
      'canUpdate': true,
    });

    expect(info.currency, 'USD');
    expect(info.daily, 250);
    expect(info.weekly, isNull);
    expect(info.monthly, 3000);
    expect(info.capWeekly, 2000);
    expect(info.hasCurrent, isTrue);
    expect(info.hasCaps, isTrue);
    expect(info.tierName, 'Pro');
    expect(info.periods.map((p) => p.label), ['Daily', 'Weekly', 'Monthly']);
    expect(info.periods.first.hasCap, isTrue);
    expect(info.updatedAt, isNotNull);
  });

  test('tolerates an empty payload', () {
    final info = CardLimitsInfo.fromJson(const {});
    expect(info.hasCurrent, isFalse);
    expect(info.hasCaps, isFalse);
    expect(info.canUpdate, isTrue);
    expect(info.capSource, 'none');
  });

  test('limit labels drop empty cents', () {
    expect(cardLimitLabel('USD', 500), r'$500');
    expect(cardLimitLabel('USD', 12.5), r'$12.50');
  });
}
