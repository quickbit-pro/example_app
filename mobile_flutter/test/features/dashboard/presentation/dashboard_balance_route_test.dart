import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/app/routes.dart';
import 'package:mobile_flutter/features/dashboard/presentation/dashboard_screen.dart';

void main() {
  test('home provider balances open their matching account sections', () {
    expect(providerBalanceRouteFor('Interlace'), AppRoutes.walletAssets);
    expect(providerBalanceRouteFor('EqualsMoney'), AppRoutes.money);
    expect(
        providerBalanceRouteFor('BoomFi Exchange'), AppRoutes.walletExchange);
    expect(providerBalanceRouteFor('Unknown provider'), AppRoutes.money);
  });

  test('home provider balances use compact customer-facing labels', () {
    expect(providerBalanceLabelFor('Interlace'), 'Crypto cards');
    expect(providerBalanceLabelFor('EqualsMoney'), 'Fiat account');
    expect(providerBalanceLabelFor('BoomFi Exchange'), 'Exchange');
  });

  test('home activity opens the transaction detail route', () {
    expect(dashboardActivityRoute('txn/42'), '/transactions/txn%2F42');
  });
}
