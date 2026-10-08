import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import '../../../shared/widgets/safeguarding_statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../application/platform_providers.dart';
import 'platform_widgets.dart';

enum WalletView { assets, addresses, balances }

class WalletsScreen extends ConsumerStatefulWidget {
  const WalletsScreen({this.initialView = WalletView.assets, super.key});

  final WalletView initialView;

  @override
  ConsumerState<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends ConsumerState<WalletsScreen> {
  late WalletView _view = widget.initialView;

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetsProvider);
    final addresses = ref.watch(depositAddressesProvider);
    final balances = ref.watch(bankingBalancesProvider);

    return PlatformActionListener(
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('Assets'))),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(assetsProvider);
            ref.invalidate(depositAddressesProvider);
            ref.invalidate(bankingBalancesProvider);
            await ref.read(assetsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<WalletView>(
                segments: [
                  ButtonSegment(
                    value: WalletView.assets,
                    icon: const Icon(Icons.toll_outlined),
                    label: Text(context.tr('Assets')),
                  ),
                  ButtonSegment(
                    value: WalletView.addresses,
                    icon: const Icon(Icons.qr_code_2),
                    label: Text(context.tr('Addresses')),
                  ),
                  ButtonSegment(
                    value: WalletView.balances,
                    icon: const Icon(Icons.account_balance),
                    label: Text(context.tr('Balances')),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (selection) {
                  setState(() => _view = selection.first);
                },
              ),
              const SizedBox(height: 24),
              Text(context.tr('Crypto actions'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _CryptoActions(assets: assets),
              const SizedBox(height: 24),
              if (_view == WalletView.assets)
                _AssetsAndAddresses(assets: assets, addresses: addresses)
              else
                _selectedData(
                  addresses: addresses,
                  balances: balances,
                ).when(
                  data: (items) => _view == WalletView.addresses
                      ? _DepositAddressList(addresses: items)
                      : ResourceList(
                          resources: items,
                          showSafeguarding: _view == WalletView.balances,
                          emptyTitle: _emptyTitle,
                          emptyMessage: _emptyMessage,
                          icon: _icon,
                        ),
                  error: (error, stackTrace) => ErrorState(
                    error: error,
                    onRetry: _invalidateSelected,
                  ),
                  loading: () => LoadingState(
                      label: context.tr('Loading {p0}', {'p0': _title})),
                ),
              if (_view == WalletView.balances)
                const SafeguardingStatementButton(),
            ],
          ),
        ),
      ),
    );
  }

  String get _title {
    return switch (_view) {
      WalletView.assets => 'Assets',
      WalletView.addresses => 'Deposit addresses',
      WalletView.balances => 'Balances',
    };
  }

  String get _emptyTitle {
    return switch (_view) {
      WalletView.assets => 'No assets yet',
      WalletView.addresses => 'No deposit addresses',
      WalletView.balances => 'No balances yet',
    };
  }

  String get _emptyMessage {
    return switch (_view) {
      WalletView.assets => 'Available crypto assets will appear here.',
      WalletView.addresses => 'Deposit addresses will appear here.',
      WalletView.balances => 'Balances will appear after provider sync.',
    };
  }

  IconData get _icon {
    return switch (_view) {
      WalletView.assets => Icons.toll_outlined,
      WalletView.addresses => Icons.qr_code_2,
      WalletView.balances => Icons.account_balance,
    };
  }

  void _invalidateSelected() {
    switch (_view) {
      case WalletView.assets:
        ref.invalidate(assetsProvider);
        ref.invalidate(depositAddressesProvider);
      case WalletView.addresses:
        ref.invalidate(depositAddressesProvider);
      case WalletView.balances:
        ref.invalidate(bankingBalancesProvider);
    }
  }

  AsyncValue<List<PlatformResource>> _selectedData({
    required AsyncValue<List<PlatformResource>> addresses,
    required AsyncValue<List<PlatformResource>> balances,
  }) {
    return switch (_view) {
      WalletView.assets => ref.watch(assetsProvider),
      WalletView.addresses => addresses,
      WalletView.balances => balances,
    };
  }
}

class _AssetsAndAddresses extends StatelessWidget {
  const _AssetsAndAddresses({
    required this.assets,
    required this.addresses,
  });

  final AsyncValue<List<PlatformResource>> assets;
  final AsyncValue<List<PlatformResource>> addresses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('Assets'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        assets.when(
          data: (items) => ResourceList(
            resources: items,
            emptyTitle: context.tr('No assets yet'),
            emptyMessage:
                context.tr('Available crypto assets will appear here.'),
            icon: Icons.toll_outlined,
          ),
          error: (error, stackTrace) => ErrorState(error: error),
          loading: () => LoadingState(label: context.tr('Loading assets')),
        ),
        const SizedBox(height: 16),
        Text(context.tr('Deposit addresses'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        addresses.when(
          data: (items) => _DepositAddressList(addresses: items),
          error: (error, stackTrace) => ErrorState(error: error),
          loading: () => LoadingState(label: context.tr('Loading addresses')),
        ),
      ],
    );
  }
}

class _DepositAddressList extends StatelessWidget {
  const _DepositAddressList({required this.addresses});

  final List<PlatformResource> addresses;

  @override
  Widget build(BuildContext context) {
    final validAddresses = addresses.where(hasCompleteDepositAddress).toList();

    if (validAddresses.isEmpty) {
      return EmptyState(
        title: context.tr('No deposit addresses'),
        message: context.tr(
            'Deposit addresses will appear here when an address has been issued for an asset and network.'),
        icon: Icons.qr_code_2,
      );
    }

    return Column(
      children: [
        for (final address in validAddresses)
          _DepositAddressCard(address: address),
      ],
    );
  }
}

class _DepositAddressCard extends StatelessWidget {
  const _DepositAddressCard({required this.address});

  final PlatformResource address;

  @override
  Widget build(BuildContext context) {
    final asset = _assetCode(address);
    final network = _networkName(address);
    final value = _depositAddress(address);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.qr_code_2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        network ?? 'Network unavailable',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (value != null)
                  IconButton(
                    tooltip: context.tr('Copy address'),
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: value));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.tr('Address copied'))),
                        );
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (value == null)
              Text(context.tr('Address not available yet.'))
            else
              SelectableText(
                value,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            const SizedBox(height: 12),
            Text(
              network == null
                  ? context.tr(
                      'Wait for the network before depositing. Sending funds on the wrong network can lead to permanent loss.')
                  : context.tr(
                      'Only send {p0} on {p1} to this address. Sending funds on the wrong network can lead to permanent loss.',
                      {'p0': asset, 'p1': network}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showAddressSupportReference(context, address),
                icon: const Icon(Icons.info_outline),
                label: Text(context.tr('Support reference')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CryptoActions extends ConsumerWidget {
  const _CryptoActions({
    required this.assets,
  });

  final AsyncValue<List<PlatformResource>> assets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetItems = assets.valueOrNull ?? const <PlatformResource>[];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionButton(
          icon: Icons.swap_horiz,
          label: context.tr('Move to USD wallet'),
          onPressed: (_) => _showAssetAmountDialog(
            context: context,
            ref: ref,
            title: context.tr('Move to your USD wallet'),
            assets: assetItems,
            submit: (asset, amount) => ref
                .read(platformActionControllerProvider.notifier)
                .run((api) => api.transferCryptoToQuantum(
                      asset: _assetCode(asset),
                      amount: amount,
                    )),
          ),
        ),
        ActionButton(
          icon: Icons.currency_exchange,
          label: context.tr('Buy crypto'),
          onPressed: (_) => _showAssetAmountDialog(
            context: context,
            ref: ref,
            title: context.tr('Buy crypto with USD'),
            assets: assetItems,
            submit: (asset, amount) => ref
                .read(platformActionControllerProvider.notifier)
                .run((api) => api.exchangeQuantumUsdToCrypto(
                      asset: _assetCode(asset),
                      amount:
                          Money(currency: 'USD', minorUnits: amount.minorUnits),
                    )),
          ),
        ),
      ],
    );
  }
}

Future<void> _showAssetAmountDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required List<PlatformResource> assets,
  required Future<void> Function(PlatformResource asset, Money amount) submit,
}) async {
  if (assets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('No assets are available yet.'))),
    );
    return;
  }

  var selected = assets.first;
  final amountController = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<PlatformResource>(
            initialValue: selected,
            items: [
              for (final asset in assets)
                DropdownMenuItem(
                  value: asset,
                  child: Text(_assetCode(asset)),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                selected = value;
              }
            },
            decoration: InputDecoration(labelText: context.tr('Asset')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            decoration: InputDecoration(
                labelText:
                    context.tr('Amount ({p0})', {'p0': _assetCode(selected)})),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.tr('Submit')),
        ),
      ],
    ),
  );

  final amount = _parseMoney(amountController.text, _assetCode(selected));
  if (!context.mounted) {
    amountController.dispose();
    return;
  }
  if (confirmed == true && amount.minorUnits > 0) {
    await submit(selected, amount);
  }

  amountController.dispose();
}

void _showAddressSupportReference(
  BuildContext context,
  PlatformResource address,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _addressLabel(address),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              initiallyExpanded: true,
              tilePadding: EdgeInsets.zero,
              title: Text(context.tr('Support reference')),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        address.id,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('Copy support reference'),
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: address.id),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(context.tr('Support reference copied')),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _assetCode(PlatformResource resource) {
  return _textValue(resource.metadata, const [
        'asset',
        'Asset',
        'assetCode',
        'AssetCode',
        'currencyCode',
        'CurrencyCode',
        'token',
        'Token',
        'currency',
        'Currency',
        'tokenSymbol',
        'TokenSymbol',
      ]) ??
      fallbackText(resource.title, 'Asset unavailable');
}

String _addressLabel(PlatformResource resource) {
  final network = _networkName(resource);
  final asset = _assetCode(resource);

  return network == null ? asset : '$asset • $network';
}

String? _depositAddress(PlatformResource resource) {
  return _textValue(resource.metadata, const [
    'address',
    'Address',
    'depositAddress',
    'DepositAddress',
    'walletAddress',
    'WalletAddress',
    'cryptoAddress',
    'CryptoAddress',
    'publicAddress',
    'PublicAddress',
    'blockchainAddress',
    'BlockchainAddress',
  ]);
}

String? _networkName(PlatformResource resource) {
  return _textValue(resource.metadata, const [
    'network',
    'Network',
    'chain',
    'Chain',
    'blockchain',
    'Blockchain',
    'blockchainNetwork',
    'BlockchainNetwork',
    'protocol',
    'Protocol',
  ]);
}

Money _parseMoney(String value, String currency) {
  final parsed = double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  return Money(currency: currency, minorUnits: (parsed * 100).round());
}

String? _textValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }

  return null;
}
