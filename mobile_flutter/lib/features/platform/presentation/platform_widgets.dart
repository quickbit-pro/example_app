import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:ui' show ImageFilter;
import '../../../shared/widgets/safeguarding_statement.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../brands/example/example.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/models/platform_models.dart';
import '../application/platform_providers.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

class ResourceList extends StatelessWidget {
  const ResourceList({
    required this.resources,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.icon = Icons.segment,
    this.showSafeguarding = false,
    super.key,
  });

  final List<PlatformResource> resources;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData icon;
  final bool showSafeguarding;

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) return _legacy(context);
    if (resources.isEmpty) {
      return ExampleEmptyState(
        compact: true,
        title: emptyTitle,
        body: emptyMessage,
        icon: Icons.inbox_outlined,
      );
    }

    return ExampleListGroup(
      children: [
        for (final resource in resources)
          ExampleRow(
            leading: ExampleIconTile(icon: icon, color: ExampleColors.iris),
            title: _friendlyResourceTitle(resource),
            subtitle: _rowSubtitle(resource),
            trailing: ExampleRow.chevron,
            semanticsLabel: context
                .tr('Open {p0}', {'p0': _friendlyResourceTitle(resource)}),
            onTap: () => showPlatformResourceDetails(context, resource,
                showSafeguarding: showSafeguarding),
          ),
      ],
    );
  }

  /// The pre-Example tree, kept byte-identical for every white-label tenant.
  Widget _legacy(BuildContext context) {
    if (resources.isEmpty) {
      return EmptyState(
        title: emptyTitle,
        message: emptyMessage,
        icon: Icons.inbox_outlined,
      );
    }

    return Column(
      children: [
        for (final resource in resources)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _friendlyResourceTitle(resource),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_friendlyResourceSubtitle(resource) != null) ...[
                          const SizedBox(height: 4),
                          SelectableText(
                            _friendlyResourceSubtitle(resource)!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (_displayFacts(resource).isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final fact in _displayFacts(resource))
                                Chip(
                                  label: Text(fact),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('View details'),
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => showPlatformResourceDetails(
                        context, resource,
                        showSafeguarding: showSafeguarding),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class PlatformActionListener extends ConsumerWidget {
  const PlatformActionListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.maybeOf(context);

    void showActionMessage(String message) {
      if (messenger == null) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!messenger.mounted) {
          return;
        }

        messenger.showSnackBar(SnackBar(content: Text(message)));
      });
    }

    ref.listen(platformActionControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (result) {
          if (result == null) {
            return;
          }
          showActionMessage(result.message);
        },
        error: (error, stackTrace) =>
            showActionMessage(friendlyErrorMessage(error)),
      );
    });

    return child;
  }
}

class ActionButton extends ConsumerWidget {
  const ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final void Function(WidgetRef ref) onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);

    return FilledButton.icon(
      onPressed: action.isLoading ? null : () => onPressed(ref),
      icon: action.isLoading
          ? const SizedBox.square(
              dimension: 18,
              child: AppProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    );
  }
}

String _friendlyResourceTitle(PlatformResource resource) {
  final title = resource.title.trim();
  if (title.isNotEmpty && !_looksTechnicalId(title)) {
    return friendlyStatus(title);
  }

  return _resourceKind(resource.metadata);
}

String? _friendlyResourceSubtitle(PlatformResource resource) {
  final subtitle = resource.subtitle.trim();
  if (subtitle.isNotEmpty && !_looksTechnicalId(subtitle)) {
    return friendlyStatus(subtitle);
  }

  final metadata = resource.metadata;
  final candidates = [
    metadata['address'],
    metadata['Address'],
    metadata['depositAddress'],
    metadata['DepositAddress'],
    metadata['walletAddress'],
    metadata['WalletAddress'],
    metadata['cryptoAddress'],
    metadata['CryptoAddress'],
    metadata['blockchainAddress'],
    metadata['BlockchainAddress'],
    metadata['status'],
    metadata['Status'],
    metadata['state'],
    metadata['State'],
    metadata['network'],
    metadata['Network'],
    metadata['provider'],
    metadata['Provider'],
  ];
  for (final candidate in candidates) {
    final value = candidate?.toString().trim() ?? '';
    if (value.isNotEmpty && !_looksTechnicalId(value)) {
      return friendlyStatus(value);
    }
  }

  return null;
}

/// True for a string a person verifies character by character rather than
/// reads: a chain address, a hash, a long provider reference. These are the
/// strings every generic fintech template renders as body copy and lets the
/// end ellipsis eat — which removes exactly the characters people compare.
bool platformLooksMachineString(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 18 || trimmed.contains(' ')) return false;
  return trimmed.startsWith('0x') ||
      RegExp(r'^[A-Za-z0-9]{18,}$').hasMatch(trimmed) ||
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9:_-]{17,}$').hasMatch(trimmed);
}

/// The facts as label/value pairs, so the Example sheet can set the label and
/// the value in two different voices instead of gluing them into one string.
List<({String label, String value})> _displayPairs(PlatformResource resource) {
  final metadata = resource.metadata;
  final pairs = [
    _labeledPair('Asset', metadata, const [
      'asset',
      'Asset',
      'assetCode',
      'AssetCode',
      'currency',
      'Currency',
    ]),
    _labeledPair(
        'Network', metadata, const ['network', 'Network', 'chain', 'Chain']),
    _labeledPair('Available', metadata, const [
      'available',
      'Available',
      'availableBalance',
      'AvailableBalance',
      'balance',
      'Balance',
    ]),
    _labeledPair(
        'Status', metadata, const ['status', 'Status', 'state', 'State']),
  ].whereType<({String label, String value})>().toList();

  final seen = <String>{};
  return [
    for (final pair in pairs)
      if (seen.add('${pair.label}:${pair.value}'.toLowerCase())) pair,
  ].take(4).toList();
}

({String label, String value})? _labeledPair(
  String label,
  Map<String, dynamic> metadata,
  List<String> keys,
) {
  for (final key in keys) {
    final value = metadata[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && !_looksTechnicalId(value)) {
      return (label: label, value: friendlyStatus(value));
    }
  }
  return null;
}

List<String> _displayFacts(PlatformResource resource) {
  final metadata = resource.metadata;
  final facts = [
    _labeledValue('Asset', metadata, const [
      'asset',
      'Asset',
      'assetCode',
      'AssetCode',
      'currency',
      'Currency',
    ]),
    _labeledValue(
        'Network', metadata, const ['network', 'Network', 'chain', 'Chain']),
    _labeledValue('Available', metadata, const [
      'available',
      'Available',
      'availableBalance',
      'AvailableBalance',
      'balance',
      'Balance',
    ]),
    _labeledValue(
        'Status', metadata, const ['status', 'Status', 'state', 'State']),
  ].whereType<String>().toList();

  final seen = <String>{};
  return [
    for (final fact in facts)
      if (seen.add(fact.toLowerCase())) fact,
  ].take(4).toList();
}

String? _labeledValue(
  String label,
  Map<String, dynamic> metadata,
  List<String> keys,
) {
  for (final key in keys) {
    final value = metadata[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && !_looksTechnicalId(value)) {
      return '$label ${friendlyStatus(value)}';
    }
  }

  return null;
}

String _resourceKind(Map<String, dynamic> metadata) {
  final kind = metadata['type'] ??
      metadata['Type'] ??
      metadata['resourceType'] ??
      metadata['ResourceType'] ??
      metadata['assetCode'] ??
      metadata['AssetCode'] ??
      metadata['currency'] ??
      metadata['Currency'];
  final value = kind?.toString().trim() ?? '';
  if (value.isNotEmpty && !_looksTechnicalId(value)) {
    return friendlyStatus(value);
  }

  return 'Item';
}

bool _looksTechnicalId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return false;
  }

  return RegExp(r'^[a-z]+_[a-z0-9_]+$', caseSensitive: false)
          .hasMatch(normalized) ||
      RegExp(r'^[0-9a-f]{8}-[0-9a-f-]{27,}$', caseSensitive: false)
          .hasMatch(normalized) ||
      RegExp(r'^[A-Z0-9]{12,}$').hasMatch(normalized);
}

/// Bottom sheet with the full resource payload. Shared by the legacy detail
/// button and the Example row.
void showPlatformResourceDetails(
  BuildContext context,
  PlatformResource resource, {
  bool showSafeguarding = false,
}) {
  final example = context.isExampleTheme;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: example,
    builder: (context) => example
        ? _ExampleResourceSheet(
            resource: resource, showSafeguarding: showSafeguarding)
        : _legacyResourceSheet(context, resource,
            showSafeguarding: showSafeguarding),
  );
}

/// The resource as Example reads it: what it is, the facts as a labelled list
/// with one rhythm, and the support reference in the machine voice.
///
/// The reference is the whole point of this sheet and it is the one thing the
/// pre-Example version got wrong: a provider id set in body copy inside a
/// collapsed `ExpansionTile`, elided at the END by the text engine. The last
/// characters of a reference are exactly what a person reads back to support
/// or compares against a block explorer, so [ExampleMono] keeps the head and
/// the tail and gives way in the middle, and the whole string is one 44 pt
/// copy target that confirms in place instead of behind a toast.
class _ExampleResourceSheet extends StatelessWidget {
  const _ExampleResourceSheet(
      {required this.resource, required this.showSafeguarding});

  final PlatformResource resource;
  final bool showSafeguarding;

  @override
  Widget build(BuildContext context) {
    final subtitle = _friendlyResourceSubtitle(resource);
    final pairs = _displayPairs(resource);
    final machineSubtitle =
        subtitle != null && platformLooksMachineString(subtitle);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _friendlyResourceTitle(resource),
              style: TextStyle(
                fontSize: 19,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: -.2,
                color: ExampleInk.primary(context),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              // An address that arrived as the subtitle is a machine string,
              // not a sentence: it gets the mono voice and its own copy
              // target rather than being set as prose that wraps mid-hash.
              if (machineSubtitle)
                ExampleMono(
                  subtitle,
                  truncate: ExampleMonoTruncate.middle,
                  head: 10,
                  tail: 8,
                  size: 13.5,
                  copyable: true,
                  color: ExampleInk.secondary(context),
                )
              else
                SelectableText(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: ExampleInk.secondary(context),
                  ),
                ),
            ],
            if (pairs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ExampleListGroup(
                children: [
                  for (final pair in pairs)
                    PlatformFactRow(label: pair.label, value: pair.value),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (showSafeguarding) const SafeguardingStatementButton(),
            Text(
              context.tr('Support reference'),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: .3,
                color: ExampleInk.tertiary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            ExampleMono(
              resource.id,
              truncate: ExampleMonoTruncate.middle,
              head: 10,
              tail: 8,
              size: 14,
              copyable: true,
              color: ExampleInk.primary(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pre-Example sheet, kept byte-identical for every white-label tenant.
Widget _legacyResourceSheet(
  BuildContext context,
  PlatformResource resource, {
  bool showSafeguarding = false,
}) =>
    SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _friendlyResourceTitle(resource),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_friendlyResourceSubtitle(resource) != null)
              SelectableText(_friendlyResourceSubtitle(resource)!),
            const SizedBox(height: 16),
            if (_displayFacts(resource).isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final fact in _displayFacts(resource))
                    Chip(label: Text(fact)),
                ],
              ),
            const SizedBox(height: 16),
            if (showSafeguarding) const SafeguardingStatementButton(),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.tr('Support reference')),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        resource.id,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('Copy support reference'),
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: resource.id),
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
    );

// ---------------------------------------------------------------------------
// Example service-screen vocabulary.
//
// Six platform screens (banking services, payments, KYC status, banking
// onboarding, tiers, transaction status) share one rhythm: the app bar carries
// the title, a [PlatformLede] carries the single sentence under it, and
// everything below is a `ExampleListGroup` of `ExampleRow`s under a
// `ExampleSectionTitle`. Nothing here renders for another brand — every widget
// is either chosen by `context.isExampleTheme` at the call site or falls back
// to the pre-Example tree itself.
// ---------------------------------------------------------------------------

/// Body padding of a Example platform screen. The shell owns the bottom bar, so
/// the list only has to clear its own last row.
const EdgeInsets platformExamplePadding = EdgeInsets.fromLTRB(
  AppSpacing.md,
  AppSpacing.sm,
  AppSpacing.md,
  AppSpacing.xl,
);

/// The gap between two sections on a platform screen.
const SizedBox platformSectionGap = SizedBox(height: AppSpacing.lg);

/// One sentence of secondary ink under the app bar, with an optional status
/// pill on the right. The title already lives in the app bar, so the lede
/// never repeats it: it says what the screen is for, and the pill says where
/// the account stands.
class PlatformLede extends StatelessWidget {
  const PlatformLede({required this.text, this.trailing, super.key});

  final String text;

  /// A [PlatformStatusPill] or nothing. The lede text yields first, so a long
  /// sentence wraps instead of squeezing the pill.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final line = Text(
      text,
      style: TextStyle(
        fontSize: 13.5,
        height: 1.45,
        color: ExampleInk.secondary(context),
      ),
    );
    final pill = trailing;
    if (pill == null) return line;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: line),
        const SizedBox(width: AppSpacing.sm),
        Padding(padding: const EdgeInsets.only(top: 1), child: pill),
      ],
    );
  }
}

/// A platform action as a Example row: tinted icon tile, label, one line of
/// description, chevron. While the shared action controller runs, every row is
/// dimmed and inert; the row the user actually pressed swaps its chevron for a
/// spinner over `ExampleMotion.state`, so the feedback lands where the finger
/// is instead of on all six rows at once.
class PlatformActionRow extends ConsumerStatefulWidget {
  const PlatformActionRow({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.description,
    this.tint = ExampleColors.iris,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? description;

  /// Null renders the row visible but inert (an action that is not unlocked
  /// yet), exactly as a disabled button did.
  final void Function(BuildContext context, WidgetRef ref)? onPressed;
  final Color tint;
  final bool enabled;

  @override
  ConsumerState<PlatformActionRow> createState() => _PlatformActionRowState();
}

class _PlatformActionRowState extends ConsumerState<PlatformActionRow> {
  bool _pending = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(platformActionControllerProvider, (previous, next) {
      if (!next.isLoading && _pending && mounted) {
        setState(() => _pending = false);
      }
    });
    final busy = ref.watch(platformActionControllerProvider).isLoading;
    final live = widget.enabled && !busy && widget.onPressed != null;
    return ExampleRow(
      leading: ExampleIconTile(icon: widget.icon, color: widget.tint),
      title: widget.label,
      subtitle: widget.description,
      enabled: widget.enabled && !busy,
      trailing: ExampleStateSwitch(
        child: _pending && busy
            ? const SizedBox.square(
                key: ValueKey('platform-action-busy'),
                dimension: 18,
                child: AppProgressIndicator(strokeWidth: 2),
              )
            : KeyedSubtree(
                key: const ValueKey('platform-action-chevron'),
                child: ExampleRow.chevronOf(context),
              ),
      ),
      semanticsLabel: widget.label,
      onTap: live
          ? () {
              setState(() => _pending = true);
              widget.onPressed!(context, ref);
            }
          : null,
    );
  }
}

/// Brand token for a provider status string. Semantic colour reaches the
/// screen through a [PlatformStatusPill] and nowhere else: rows, amounts and
/// icons stay in the resting palette.
Color platformStatusColor(String value) {
  final status = value.toLowerCase();
  const settled = [
    'approv',
    'active',
    'complet',
    'success',
    'verified',
    'ready',
    'settled',
    'enabled',
    'passed',
  ];
  const stopped = [
    'reject',
    'fail',
    'declin',
    'block',
    'cancel',
    'expired',
    'suspend',
    'revoked',
  ];
  const waiting = [
    'pending',
    'review',
    'progress',
    'await',
    'submit',
    'required',
    'action',
    'started',
  ];
  if (settled.any(status.contains)) return ExampleColors.success;
  if (stopped.any(status.contains)) return ExampleColors.danger;
  if (waiting.any(status.contains)) return ExampleColors.warning;
  return ExampleColors.iris;
}

/// Status as a [ExamplePill]: the one place a semantic hue is allowed on these
/// screens. Both themes resolve through `ExampleInk.accent`, so the label
/// clears 4.5:1 on paper as well as on night.
class PlatformStatusPill extends StatelessWidget {
  const PlatformStatusPill({required this.status, this.dot = true, super.key});

  final String status;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final label = friendlyStatus(status);
    return ExamplePill(
      label: label,
      color: platformStatusColor(status),
      dot: dot,
    );
  }
}

/// One `label -> value` line in a Example detail sheet.
///
/// A machine string does not get the same treatment as a word. Addresses,
/// hashes and provider references are set in Geist Mono, given way in the
/// middle so the tail survives, and made their own copy target with in-place
/// confirmation; everything else stays a 56 pt row with the value right
/// aligned in the tabular column the rest of the app uses. That split is the
/// whole reason a detail sheet reads as crypto-literate instead of as a JSON
/// dump with a font applied to it.
class PlatformFactRow extends StatelessWidget {
  const PlatformFactRow({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (!platformLooksMachineString(value)) {
      return ExampleRow(
        title: label,
        trailing: ExampleRowValue(value: value),
        semanticsLabel: '$label, $value',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: .3,
              // Tertiary ink composites to 4.59:1 on lightPaper and 5.15:1 on
              // darkSurface, so the label clears the body floor in both
              // themes even at this size.
              color: ExampleInk.tertiary(context),
            ),
          ),
          const SizedBox(height: 2),
          ExampleMono(
            value,
            truncate: ExampleMonoTruncate.middle,
            head: 10,
            tail: 8,
            size: 13.5,
            copyable: true,
            color: ExampleInk.primary(context),
          ),
        ],
      ),
    );
  }
}

/// Shape-matched placeholder for a group of rows that is still loading.
class PlatformLoadingGroup extends StatelessWidget {
  const PlatformLoadingGroup({
    this.title,
    this.rows = 3,
    this.label = 'Loading',
    super.key,
  });

  final String? title;
  final int rows;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: label,
        // One host for the whole list, never one per row.
        child: ExampleSheen.text(
          intensity: ExampleSheenIntensity.soft,
          child: ExampleListGroup(
            title: title,
            children: [
              for (var i = 0; i < rows; i++) const ExampleSkeleton.row(),
            ],
          ),
        ),
      );
}

/// Empty section: the Example composition for Example, the shared one for every
/// other tenant.
class PlatformEmptyState extends StatelessWidget {
  const PlatformEmptyState({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.compact = true,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) => context.isExampleTheme
      ? ExampleEmptyState(
          title: title,
          body: message,
          icon: icon,
          compact: compact,
        )
      : EmptyState(title: title, message: message, icon: icon);
}

/// Failed section, with the provisioning special case preserved: right after
/// registration the banking provider answers 502/503/504 for a minute or two,
/// and that is a wait, not a failure.
class PlatformErrorState extends StatelessWidget {
  const PlatformErrorState({
    required this.error,
    this.onRetry,
    this.compact = true,
    super.key,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  bool get _providerWarmingUp =>
      error is DioException &&
      const {502, 503, 504}
          .contains((error as DioException).response?.statusCode);

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) {
      return ErrorState(error: error, onRetry: onRetry);
    }
    if (_providerWarmingUp) {
      return ExampleEmptyState(
        icon: Icons.hourglass_top_rounded,
        title: context.tr('Your account is being set up'),
        body: context.tr(
            'This usually takes a minute right after registration. Please wait a moment and try again.'),
        actionLabel: onRetry == null ? null : context.tr('Try again'),
        onAction: onRetry,
        compact: compact,
      );
    }
    return ExampleErrorState(
      error: error,
      onRetry: onRetry,
      compact: compact,
    );
  }
}

/// Frosted action bar pinned to the bottom of a flow, above the safe area.
///
/// One of the four surfaces the law lets us frost: it floats over scrolling
/// content it can actually blur. The blur is bounded by a `ClipRect` and sits
/// in its own `RepaintBoundary`, and it falls back to the opaque navigation
/// surface when the platform asks for high contrast.
class PlatformStickyBar extends StatelessWidget {
  const PlatformStickyBar({required this.child, super.key});

  final Widget child;

  static const double _sigma = 18;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final frosted = !(MediaQuery.maybeHighContrastOf(context) ?? false);
    final Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: frosted ? null : palette.navigation,
        gradient: frosted
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [palette.glassTop, palette.navigationGlass],
              )
            : null,
        border: Border(top: ExampleBorders.hairlineSideOf(context)),
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
          child: child,
        ),
      ),
    );
    if (!frosted) return surface;
    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma),
          child: surface,
        ),
      ),
    );
  }
}

/// One line under a resource row title: its own subtitle, then the first fact
/// the payload carries, so the row says something without a chip cloud.
String? _rowSubtitle(PlatformResource resource) {
  final raw = _friendlyResourceSubtitle(resource);
  // A chain address reaching a row's subtitle is the common case here, and a
  // row subtitle elides at the END — which throws away the last characters,
  // the only ones anybody actually verifies. Give way in the middle instead;
  // the sheet behind the row shows the string whole, in mono, copyable.
  final subtitle = raw != null && platformLooksMachineString(raw)
      ? ExampleMono.truncateMiddle(raw, head: 10, tail: 8)
      : raw;
  final facts = _displayFacts(resource);
  if (subtitle == null) return facts.isEmpty ? null : facts.join(' · ');
  if (facts.isEmpty) return subtitle;
  return '$subtitle · ${facts.first}';
}
