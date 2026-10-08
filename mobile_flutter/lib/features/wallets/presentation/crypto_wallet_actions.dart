import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../shared/shared.dart';
import '../../../core/widgets/app_states.dart';
import '../data/wallet_providers.dart';
import '../domain/wallet_models.dart';
import '../domain/withdrawal_networks.dart';
import 'crypto_withdrawal_dialog.dart';
import 'deposit_address_dialog.dart';

/// Crypto-only installations without member transfers withdraw a stablecoin
/// to an external address straight from Home.
Future<void> openCryptoSend(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    // Only stablecoins can be withdrawn on-chain; the USD card balance is
    // spent through the card or exchanged first.
    const withdrawable = {'USDC', 'USDT'};
    final assets = (await ref.read(hoppaWalletAssetsProvider.future))
        .where((asset) =>
            asset.amount >= minimumCryptoWithdrawal &&
            withdrawable.contains(asset.symbol.toUpperCase()))
        .toList()
      ..sort((a, b) => b.fiatValue.compareTo(a.fiatValue));
    if (!context.mounted) return;
    if (assets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr(
              'You need at least 5 USDT or 5 USDC to withdraw. Buy or deposit first.')),
        ),
      );
      return;
    }
    final asset = assets.length == 1
        ? assets.first
        : await _pickSendAsset(context, assets);
    if (asset == null || !context.mounted) return;
    await showCryptoWithdrawalDialog(context, asset: asset);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyErrorMessage(error))),
    );
  }
}

Future<HoppaWalletAsset?> _pickSendAsset(
  BuildContext context,
  List<HoppaWalletAsset> assets,
) {
  return showModalBottomSheet<HoppaWalletAsset>(
    context: context,
    useRootNavigator: true,
    backgroundColor: ExampleSurface.navigationOf(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.tr('What do you want to send?'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ExampleInk.primary(sheetContext),
                ),
              ),
            ),
          ),
          for (final asset in assets)
            ListTile(
              leading: CurrencyLogo(
                symbol: asset.symbol,
                fallbackIcon: Icons.token_outlined,
              ),
              title: Text(
                asset.symbol,
                style: TextStyle(color: ExampleInk.primary(sheetContext)),
              ),
              subtitle: Text(
                '${asset.amount.toStringAsFixed(2)} ${asset.symbol}'
                '${asset.network.isNotEmpty ? ' · ${asset.network}' : ''}',
                style: TextStyle(color: ExampleInk.tertiary(sheetContext)),
              ),
              onTap: () => Navigator.of(sheetContext).pop(asset),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Open the same stablecoin/network picker from Home and Request.
Future<void> openCryptoDeposit(BuildContext context, WidgetRef ref) async {
  try {
    final addresses = await ref.read(hoppaWalletAddressesProvider.future);
    if (!context.mounted) return;
    await showStablecoinDepositDialog(
      context,
      addresses: addresses,
      initialAsset: 'USDT',
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyErrorMessage(error))),
    );
  }
}
