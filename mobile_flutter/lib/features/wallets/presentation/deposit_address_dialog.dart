import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../shared/shared.dart';
import '../domain/wallet_models.dart';

const _depositAssets = ['USDC', 'USDT'];
const _evmNetworks = {
  'ETH',
  'AVAX',
  'ARB',
  'MATIC',
  'OKT',
  'OP',
  'BSC',
  'BASE',
};

const double _exampleColumnWidth = 520;

Future<void> showStablecoinDepositDialog(
  BuildContext context, {
  required List<HoppaWalletAsset> addresses,
  String initialAsset = 'USDT',
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _StablecoinDepositSheet(
      addresses: addresses,
      initialAsset: initialAsset,
    ),
  );
}

class _StablecoinDepositSheet extends StatefulWidget {
  const _StablecoinDepositSheet({
    required this.addresses,
    required this.initialAsset,
  });

  final List<HoppaWalletAsset> addresses;
  final String initialAsset;

  @override
  State<_StablecoinDepositSheet> createState() =>
      _StablecoinDepositSheetState();
}

class _StablecoinDepositSheetState extends State<_StablecoinDepositSheet> {
  late String _asset =
      _depositAssets.contains(widget.initialAsset.toUpperCase())
          ? widget.initialAsset.toUpperCase()
          : _depositAssets.first;
  String? _networkKey;

  bool _copied = false;
  Timer? _copiedTimer;

  List<DepositNetworkOption> get _options =>
      buildStablecoinDepositOptions(widget.addresses, _asset);

  DepositNetworkOption? get _selected {
    final options = _options;
    if (options.isEmpty) return null;
    return options.firstWhere(
      (option) => option.key == _networkKey,
      orElse: () => options.first,
    );
  }

  void _selectAsset(String value) {
    _cancelCopied();
    setState(() {
      _asset = value;
      _networkKey = null;
      _copied = false;
    });
  }

  void _selectNetwork(String key) {
    _cancelCopied();
    setState(() {
      _networkKey = key;
      _copied = false;
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    return FractionallySizedBox(
      heightFactor: .93,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(context.tr('Deposit {p0}', {'p0': _asset})),
          actions: [
            IconButton(
              tooltip: context.tr('Close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        body: isExample ? _exampleBody(context) : _defaultBody(context),
        bottomNavigationBar: isExample ? _exampleCopyBar(context) : null,
      ),
    );
  }

  Widget _defaultBody(BuildContext context) {
    final theme = Theme.of(context);
    final options = _options;
    final selected = _selected;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        32,
      ),
      children: [
        Text(
          context.tr(
              'Select a network and scan the QR code or copy the address to receive {p0}.',
              {'p0': _asset}),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(context.tr('Stablecoin'), style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          key: ValueKey(_asset),
          initialValue: _asset,
          decoration: const InputDecoration(),
          items: [
            DropdownMenuItem(
              value: 'USDC',
              child: Row(
                children: [
                  const CurrencyLogo(symbol: 'USDC', size: 24),
                  const SizedBox(width: 10),
                  Text(context.tr('USDC (USD Coin)')),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'USDT',
              child: Row(
                children: [
                  const CurrencyLogo(symbol: 'USDT', size: 24),
                  const SizedBox(width: 10),
                  Text(context.tr('USDT (Tether)')),
                ],
              ),
            ),
          ],
          onChanged: (value) {
            if (value != null) _selectAsset(value);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(context.tr('Network'), style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        if (options.length > 1)
          DropdownButtonFormField<String>(
            key: ValueKey('$_asset:${selected?.key}'),
            isExpanded: true,
            initialValue: selected?.key,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.hub_outlined),
            ),
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: option.key,
                  child: Text(option.label,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _networkKey = value),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 15,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Text(
              selected?.label ?? 'No supported network available',
              style: theme.textTheme.titleSmall,
            ),
          ),
        if (selected == null) ...[
          const SizedBox(height: AppSpacing.xl),
          const Icon(Icons.qr_code_2_rounded, size: 64),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr(
                'No {p0} deposit address is available yet.', {'p0': _asset}),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr(
                'Pull to refresh the Accounts screen after the provider enables this wallet.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(
                    color: context.brandDesign.color(
                        theme.brightness, 'borderSubtle',
                        fallback: const Color(0xFFE2E8F0))),
              ),
              child: QrImageView(
                data: selected.address,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(context.tr('Deposit address'),
              style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: SelectableText(
                    selected.address,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: context.brandDesign.isConfigured
                          ? context.brandDesign.monoFontFamily
                          : 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton.outlined(
                tooltip: context.tr('Copy deposit address'),
                onPressed: () => _copyAddress(selected.address),
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: .38),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    context.tr(
                        'Only send {p0} via {p1}. Using another asset or network may permanently lose funds.',
                        {'p0': _asset, 'p1': selected.label}),
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _exampleBody(BuildContext context) {
    final options = _options;
    final selected = _selected;

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        _ExampleIntro(asset: _asset, hasAddress: selected != null),
        const SizedBox(height: AppSpacing.lg),
        ExampleSectionTitle(title: context.tr('Stablecoin')),
        const SizedBox(height: AppSpacing.xs),
        ExampleSegmentedControl<String>(
          height: 44,
          segments: const [
            (value: 'USDC', label: 'USDC'),
            (value: 'USDT', label: 'USDT'),
          ],
          selected: _asset,
          onChanged: _selectAsset,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (selected == null)
          ExampleEmptyState(
            compact: true,
            icon: Icons.qr_code_2_rounded,
            title: context.tr('No {p0} address yet', {'p0': _asset}),
            body: context.tr(
                'This wallet has not been provisioned. Refresh Accounts, or switch to the other stablecoin above.'),
          )
        else ...[
          ExampleListGroup(
            title: context.tr('Network'),
            level: 2,
            dividerInset: AppSpacing.md,
            children: [
              for (final option in options)
                ExampleRow(
                  title: option.standard == 'EVM'
                      ? context.tr('Supported EVM networks')
                      : option.standard,
                  subtitle: option.chains,
                  padding: _rowPadding,
                  semanticsLabel: option.key == selected.key
                      ? context.tr('{p0}, {p1}, selected',
                          {'p0': option.standard, 'p1': option.chains})
                      : context.tr('Receive on {p0}, {p1}',
                          {'p0': option.standard, 'p1': option.chains}),
                  onTap: options.length == 1
                      ? null
                      : () => _selectNetwork(option.key),
                  trailing: option.key == selected.key
                      ? Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: ExamplePalette.of(context).accent,
                        )
                      : null,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _ExampleArrival(
            child: Column(
              children: [
                _ExampleQrBlock(data: selected.address),
                const SizedBox(height: AppSpacing.lg),
                _ExampleAddressPanel(
                  address: selected.address,
                  standard: selected.standard,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ExampleNetworkCaution(
            asset: _asset,
            standard: selected.standard,
            chains: selected.chains,
          ),
        ],
      ],
    );

    final column = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _exampleColumnWidth),
        child: body,
      ),
    );

    return ExampleAliveLayer(child: column);
  }

  Widget _exampleCopyBar(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final selected = _selected;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        border: Border(top: BorderSide(color: palette.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _exampleColumnWidth),
              child: MergeSemantics(
                child: Semantics(
                  liveRegion: true,
                  child: ExampleGlassButton(
                    label: _copied
                        ? context.tr('Copied')
                        : context.tr('Copy address'),
                    icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                    sheen: false,
                    semanticsLabel: _copied
                        ? context
                            .tr('{p0} deposit address copied', {'p0': _asset})
                        : context.tr(
                            'Copy the {p0} deposit address', {'p0': _asset}),
                    onPressed: selected == null
                        ? null
                        : () => _copyPrimary(selected.address),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const EdgeInsets _rowPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  );

  Future<void> _copyAddress(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('Deposit address copied'))),
    );
  }

  Future<void> _copyPrimary(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    _cancelCopied();
    setState(() => _copied = true);
    _copiedTimer = Timer(ExampleMono.copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _cancelCopied() {
    _copiedTimer?.cancel();
    _copiedTimer = null;
  }
}

class _ExampleIntro extends StatelessWidget {
  const _ExampleIntro({required this.asset, required this.hasAddress});

  final String asset;
  final bool hasAddress;

  @override
  Widget build(BuildContext context) => Text(
        hasAddress
            ? 'Choose a network, then scan the code or copy the address to '
                'receive $asset.'
            : context.tr(
                'Choose a stablecoin. A deposit address appears here once the wallet is provisioned.'),
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: ExamplePalette.of(context).textSecondary,
        ),
      );
}

class _ExampleArrival extends StatefulWidget {
  const _ExampleArrival({required this.child});

  final Widget child;

  @override
  State<_ExampleArrival> createState() => _ExampleArrivalState();
}

class _ExampleArrivalState extends State<_ExampleArrival>
    with SingleTickerProviderStateMixin {
  static const double _rise = 8;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ExampleMotion.state,
  );
  Animation<double>? _route;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ExampleMotion.reduced(context)) {
      _detach();
      _started = true;
      _controller.value = 1;
      return;
    }
    if (_started) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _start();
      return;
    }
    _detach();
    _route = animation..addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _start();
  }

  void _start() {
    _detach();
    if (_started) return;
    _started = true;
    _controller.forward();
  }

  void _detach() {
    _route?.removeStatusListener(_onRouteStatus);
    _route = null;
  }

  @override
  void dispose() {
    _detach();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final t = ExampleMotion.arrive.transform(_controller.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * _rise),
              child: child,
            ),
          );
        },
      );
}

class _ExampleQrBlock extends StatelessWidget {
  const _ExampleQrBlock({required this.data});

  final String data;

  static final Color _qrField = ExamplePalette.light.surface;

  static const double _size = 196;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return Center(
      child: Semantics(
        label: context.tr('Deposit address QR code'),
        image: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 2),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: palette.borderSubtle),
            boxShadow: ExampleShadows.ambientOf(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _qrField,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: QrImageView(
                  data: data,
                  size: _size,
                  backgroundColor: _qrField,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExampleAddressPanel extends StatelessWidget {
  const _ExampleAddressPanel({required this.address, required this.standard});

  final String address;
  final String standard;

  static const int _group = 4;

  static const int _maxLines = 6;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 2),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: palette.borderSubtle),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExampleSheen(
              intensity: ExampleSheenIntensity.soft,
              child: Container(height: 1, color: palette.borderSubtle),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('DEPOSIT ADDRESS'),
                          style: ExampleTextStyles.label(context),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        standard.toUpperCase(),
                        maxLines: 1,
                        textAlign: TextAlign.end,
                        style: ExampleTextStyles.label(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ExampleMono(
                    address,
                    size: 13,
                    group: _group,
                    maxLines: _maxLines,
                    copyable: true,
                    color: palette.ink,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExampleNetworkCaution extends StatelessWidget {
  const _ExampleNetworkCaution({
    required this.asset,
    required this.standard,
    required this.chains,
  });

  final String asset;
  final String standard;
  final String chains;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 2),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: palette.warning,
              ),
            ),
            const SizedBox(width: AppSpacing.xs + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Send {p0} on {p1} only', {
                      'p0': asset,
                      'p1': chains.isEmpty ? standard : chains
                    }),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    chains.isEmpty
                        ? context.tr(
                            'Another asset, or another chain, cannot be recovered.')
                        : 'This address accepts $asset on $chains. Another '
                            'asset, or another chain, cannot be recovered.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DepositNetworkOption {
  const DepositNetworkOption({
    required this.key,
    required this.label,
    required this.address,
    this.standard = '',
    this.chains = '',
  });

  final String key;

  final String label;
  final String address;

  final String standard;

  final String chains;
}

const _depositChainNames = {
  'ETH': 'Ethereum',
  'OP': 'Optimism',
  'ARB': 'Arbitrum',
  'AVAX': 'Avalanche',
  'MATIC': 'Polygon',
  'TRX': 'Tron',
  'OKT': 'OKX Chain',
};

List<DepositNetworkOption> buildStablecoinDepositOptions(
  List<HoppaWalletAsset> addresses,
  String asset,
) {
  final matching = addresses.where(
    (address) =>
        address.symbol.toUpperCase() == asset &&
        address.address.trim().isNotEmpty,
  );
  final evmByAddress = <String, ({String address, Set<String> networks})>{};
  final tronByAddress = <String, String>{};

  for (final item in matching) {
    final networks = _normalizedNetworks(item.network);
    for (final network in networks) {
      if (_evmNetworks.contains(network)) {
        final key = item.address.toLowerCase();
        final current = evmByAddress[key];
        evmByAddress[key] = (
          address: item.address,
          networks: {...?current?.networks, network},
        );
      } else if (asset == 'USDT' && network == 'TRX') {
        tronByAddress.putIfAbsent(
            item.address.toLowerCase(), () => item.address);
      }
    }
  }

  final options = <DepositNetworkOption>[];
  if (asset == 'USDT') {
    for (final entry in tronByAddress.entries) {
      options.add(
        DepositNetworkOption(
          key: 'trc20:${entry.key}',
          label: 'TRC20 (TRX)',
          standard: 'TRC20',
          chains: 'TRX',
          address: entry.value,
        ),
      );
    }
  }
  for (final entry in evmByAddress.entries) {
    final networks = entry.value.networks.toList()..sort(_networkSort);
    final chains = networks.map((n) => _depositChainNames[n] ?? n).join(', ');
    final suffix = networks.isEmpty ? '' : ' ($chains)';
    options.add(
      DepositNetworkOption(
        key: 'erc20:${entry.key}',
        label: 'Supported EVM networks$suffix',
        standard: 'EVM',
        chains: chains,
        address: entry.value.address,
      ),
    );
  }
  return options;
}

Set<String> _normalizedNetworks(String value) {
  final networks = <String>{};
  for (final raw in value.split(RegExp(r'[/,()\s]+'))) {
    final normalized = switch (raw.trim().toUpperCase()) {
      'ETHEREUM' || 'ERC20' => 'ETH',
      'TRON' || 'TRC20' => 'TRX',
      'POLYGON' => 'MATIC',
      'ARBITRUM' => 'ARB',
      'OPTIMISM' => 'OP',
      'AVALANCHE' => 'AVAX',
      'BEP20' => 'BSC',
      final network => network,
    };
    if (normalized.isNotEmpty) networks.add(normalized);
  }
  return networks;
}

int _networkSort(String left, String right) {
  const order = ['OP', 'ARB', 'AVAX', 'MATIC', 'ETH', 'BSC', 'BASE', 'OKT'];
  final leftIndex = order.indexOf(left);
  final rightIndex = order.indexOf(right);
  if (leftIndex == -1 && rightIndex == -1) return left.compareTo(right);
  if (leftIndex == -1) return 1;
  if (rightIndex == -1) return -1;
  return leftIndex.compareTo(rightIndex);
}
