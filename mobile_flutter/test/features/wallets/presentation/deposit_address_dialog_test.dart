import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/deposit_address_dialog.dart';

void main() {
  test('combines EVM chains and only offers TRC20 for USDT', () {
    final addresses = [
      const HoppaWalletAsset(
        symbol: 'USDC',
        name: 'USDC',
        network: 'OP / ARB / AVAX / MATIC / ETH / TRX',
        amount: 0,
        fiatValue: 0,
        address: '0xusdc',
        tint: Colors.blue,
        walletId: 'usdc',
      ),
      const HoppaWalletAsset(
        symbol: 'USDT',
        name: 'USDT',
        network: 'ETH / OP / ARB / AVAX / MATIC',
        amount: 0,
        fiatValue: 0,
        address: '0xusdt',
        tint: Colors.green,
        walletId: 'usdt-evm',
      ),
      const HoppaWalletAsset(
        symbol: 'USDT',
        name: 'USDT',
        network: 'TRX',
        amount: 0,
        fiatValue: 0,
        address: 'Tusdt',
        tint: Colors.green,
        walletId: 'usdt-tron',
      ),
    ];

    final usdc = buildStablecoinDepositOptions(addresses, 'USDC');
    expect(usdc, hasLength(1));
    expect(usdc.single.label,
        'Supported EVM networks (Optimism, Arbitrum, Avalanche, Polygon, Ethereum)');
    expect(usdc.single.address, '0xusdc');

    final usdt = buildStablecoinDepositOptions(addresses, 'USDT');
    expect(usdt.map((option) => option.label), [
      'TRC20 (TRX)',
      'Supported EVM networks (Optimism, Arbitrum, Avalanche, Polygon, Ethereum)',
    ]);
    expect(usdt.first.address, 'Tusdt');
  });
}
