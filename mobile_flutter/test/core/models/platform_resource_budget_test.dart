import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';

void main() {
  for (final pascalCase in [false, true]) {
    test('budget response preserves distinct IDs under a shared account, pascalCase=$pascalCase', () async {
      String key(String value) => pascalCase
          ? value[0].toUpperCase() + value.substring(1) : value;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        expect(options.path, '/api/v1/mobile/banking/budgets');
        handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
          key('budgets'): [
            for (final id in ['main-budget', 'secondary-budget']) {
              key('budgetId'): id,
              key('accountId'): 'parent-account',
              key('name'): id,
              key('balances'): [{key('currency'): 'EUR', key('availableBalance'): 44.89}],
            },
          ],
        }));
      }));
      final budgets = await MobilePlatformApi(dio).getBudgets();
      expect(budgets.map((b) => b.id), ['main-budget', 'secondary-budget']);
      expect(budgets.map((b) => b.metadata[key('accountId')]), everyElement('parent-account'));
    });
  }
  test('account-only resources retain their account ID', () {
    expect(PlatformResource.fromJson({'accountId': 'account-only'}).id, 'account-only');
  });
  test('explicit resource identity remains preferred', () {
    expect(PlatformResource.fromJson({'id': 'resource', 'budgetId': 'budget', 'accountId': 'account'}).id, 'resource');
  });
}
