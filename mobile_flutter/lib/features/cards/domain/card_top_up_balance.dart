import '../../wallets/domain/wallet_models.dart';

const cardTopUpFundingCurrencies = {'USD', 'USDT', 'USDC'};

// Stablecoin funding is estimated at 1 USD per USDT/USDC. Work in eight
// decimal places so binary floating-point tails cannot lose a cent on Max.
BigInt _units(double amount) =>
    BigInt.parse(amount.toStringAsFixed(8).replaceAll('.', ''));

final _scale = BigInt.from(100000000);

double cardTopUpAvailable(List<HoppaWalletAsset> balances) {
  var total = BigInt.zero;
  for (final balance in balances) {
    if (cardTopUpFundingCurrencies
            .contains(balance.symbol.trim().toUpperCase()) &&
        balance.amount.isFinite &&
        balance.amount > 0) {
      total += _units(balance.amount);
    }
  }
  return total.toDouble() / _scale.toDouble();
}

double cardBalanceQuickAmount(double available, double fraction,
    {bool wholeDollarMax = false}) {
  if (!available.isFinite || available <= 0) return 0;
  final units = _units(available);
  if (wholeDollarMax && fraction == 1) {
    return (units ~/ _scale).toDouble();
  }
  final percent = BigInt.from((fraction * 100).round());
  final cents = units * percent ~/ _scale;
  return cents.toDouble() / 100;
}
