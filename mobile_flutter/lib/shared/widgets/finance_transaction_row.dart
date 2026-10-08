import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme_extensions.dart';
import '../../brands/example/example_tokens.dart';
import '../../brands/example/example_ui.dart';
import '../../core/branding/app_design.dart';
import '../../core/models/banking_models.dart';
import 'currency_logo.dart';
import 'status_chip.dart';

class FinanceTransactionRow extends StatelessWidget {
  const FinanceTransactionRow({
    required this.currency,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
    required this.statusTone,
    this.secondaryAmount,
    this.detailLabel = '',
    this.fallbackColor,
    this.amountColor,
    this.onDetailTap,
    this.onTap,
    this.logoUrl = '',
    super.key,
  });

  final String currency;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final String amount;
  final String status;
  final FinanceStatusTone statusTone;
  final String? secondaryAmount;
  final String detailLabel;
  final Color? fallbackColor;
  final Color? amountColor;
  final VoidCallback? onDetailTap;
  final VoidCallback? onTap;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isExample = context.isExampleTheme;

    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(
        horizontal: isExample ? 12 : 16,
        vertical: isExample ? 7 : 6,
      ),
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (fallbackColor ?? colorScheme.primary)
              .withValues(alpha: isExample ? .13 : .16),
          shape: BoxShape.circle,
        ),
        child: logoUrl.trim().isEmpty
            ? CurrencyLogo(
                symbol: currency,
                size: 32,
                fallbackColor: fallbackColor,
                fallbackIcon: fallbackIcon,
              )
            : ClipOval(
                child: Image.network(
                  logoUrl.trim(),
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => CurrencyLogo(
                    symbol: currency,
                    size: 32,
                    fallbackColor: fallbackColor,
                    fallbackIcon: fallbackIcon,
                  ),
                ),
              ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isExample
            ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)
            : null,
      ),
      isThreeLine: detailLabel.isNotEmpty,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: amountColor ??
                          (isExample && amount.startsWith('+')
                              ? (context.brandDesign.isConfigured
                                  ? context.financeTheme.positive
                                  : ExampleColors.success)
                              : null),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (secondaryAmount case final secondary?)
                    Text(
                      secondary,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (detailLabel.isNotEmpty)
            InkWell(
              onTap: onDetailTap,
              borderRadius: BorderRadius.circular(
                context.brandShape.radius(AppRadii.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(detailLabel),
                    if (onDetailTap != null) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.info_outline_rounded, size: 14),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(label: status, tone: statusTone),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right_rounded),
          ],
        ],
      ),
    );
  }
}

/// A Example transaction line: merchant avatar, merchant name, a quiet
/// descriptor (time and kind, plus a status pill only when something needs
/// attention) and the amount in the app's one numeral voice.
///
/// Anatomy is [ExampleRow]'s to the pixel — the same 16 pt gutter, the same
/// 40 pt leading square, the same 8 pt gap, the same 56 pt floor, the same
/// hover wash on [ExampleMotion.state] — so a group of these and a group of
/// `ExampleRow`s share one divider inset and one rhythm. It is a separate
/// widget for exactly one reason: the descriptor line carries a widget (the
/// status pill), which `ExampleRow`'s `String subtitle` cannot. Everything
/// else delegates: [ExamplePressable] for the press, [ExampleAmount] for the
/// numerals, [ExamplePill] for the status, [ExampleInk] for every colour.
///
/// Put rows in a `ExampleListGroup` (which draws the surface and the dividers
/// and insets them to [ExampleRow.textInset]) or straight into a
/// `ListView.builder` with [divider] on. Never wrap one in a panel of its
/// own: a list of cards is the pattern this replaces.
///
/// Both themes are first class — every colour resolves through [ExampleInk],
/// so the row is pearl on night and night on paper with no branch at the
/// call site. Outside the Example theme nothing here is reachable; keep using
/// [FinanceTransactionRow].
class ExampleTransactionRow extends StatefulWidget {
  const ExampleTransactionRow({
    required this.title,
    required this.amount,
    required this.currency,
    this.descriptor = '',
    this.tint = ExampleColors.iris,
    this.logoUrl = '',
    this.fallbackIcon,
    this.statusLabel,
    this.statusColor = ExampleColors.warning,
    this.secondaryLabel,
    this.identityLabel,
    this.onTap,
    this.divider = false,
    this.semanticsLabel,
    super.key,
  });

  /// Merchant or counterparty, already through `transactionDisplayTitle`.
  final String title;

  /// Signed major units: negative spends, positive credits. Null renders the
  /// [ExampleAmount] placeholder, so a row whose amount has not arrived still
  /// holds its line.
  final double? amount;

  /// ISO code or asset symbol, as stored on `Money.currency`.
  final String currency;

  /// The quiet line under the title: time first, then kind
  /// ("15:24 · Card payment"). Set in tabular figures so the times form a
  /// column down the list.
  final String descriptor;

  /// Category tint of the avatar disc. A `ExampleColors` token only; use
  /// [tintFor] to derive it from a merchant category or a transaction kind.
  final Color tint;

  /// Merchant logo. Falls back to [fallbackIcon] or initials while loading or
  /// on any network failure, so the row never shows a hole.
  final String logoUrl;

  /// Optional operation icon for activity lists. Other callers retain their
  /// merchant initials when no logo is available.
  final IconData? fallbackIcon;

  /// Status shown as a [ExamplePill] on the descriptor line. Leave it null for
  /// anything settled: a list where every row says "Completed" says nothing.
  final String? statusLabel;

  /// Pill hue; a `ExampleColors` token, deepened for paper by [ExamplePill].
  final Color statusColor;

  /// Caption under the amount — the settlement currency, a rate, a fee.
  final String? secondaryLabel;

  /// Actual card/account identity below the row, with enough width to stay
  /// readable without taking space from the amount or FX settlement caption.
  final String? identityLabel;

  final VoidCallback? onTap;

  /// Hairline under the row, inset to the text column. Leave it false inside
  /// a `ExampleListGroup`, which draws its own.
  final bool divider;

  /// Accessible name. Defaults to the title, descriptor and amount read as
  /// one item.
  final String? semanticsLabel;

  /// Press scale for a row: shallower than a button's .97, because a list is
  /// touched hundreds of times a day and should acknowledge, not perform.
  static const double pressedScale = .99;

  /// Category tint from the `ExampleColors` palette, and nothing else.
  ///
  /// Pass a merchant category ("Groceries", "Transport") or a transaction
  /// kind ("Exchange", "Top up"); matching is on substrings, case-insensitive,
  /// so raw provider strings work unchanged. Anything unrecognised takes
  /// [fallback], which keeps a list of unknown merchants uniform rather than
  /// randomly coloured.
  static Color tintFor(String category, {Color fallback = ExampleColors.iris}) {
    final value = category.toLowerCase();
    bool has(List<String> words) => words.any(value.contains);
    if (has(const [
      'salary',
      'income',
      'top up',
      'top-up',
      'topup',
      'deposit',
      'refund',
      'payroll'
    ])) {
      return ExampleColors.success;
    }
    if (has(const [
      'transfer',
      'transport',
      'travel',
      'taxi',
      'uber',
      'ride',
      'flight'
    ])) {
      return ExampleColors.teal;
    }
    if (has(const [
      'exchange',
      'convert',
      'crypto',
      'btc',
      'eth',
      'usdc',
      'usdt',
      'swap'
    ])) {
      return ExampleColors.violet;
    }
    if (has(const ['fee', 'charge', 'interest', 'tax'])) {
      return ExampleColors.warning;
    }
    if (has(const ['subscription', 'utilities', 'bill', 'rent', 'insurance'])) {
      return ExampleColors.lavender;
    }
    return fallback;
  }

  /// One or two initials for the avatar disc: the first letters of the first
  /// two words, or the first two letters of a single word.
  static String initialsFor(String name) {
    final words = name
        .trim()
        .split(RegExp(r'[\s·/,-]+'))
        .where(
            (word) => word.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(word))
        .toList();
    if (words.isEmpty) return '—';
    if (words.length == 1) {
      final word = words.first;
      return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  @override
  State<ExampleTransactionRow> createState() => _ExampleTransactionRowState();
}

class _ExampleTransactionRowState extends State<ExampleTransactionRow> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  String get _semanticsLabel {
    if (widget.semanticsLabel case final label?) return label;
    final amount = widget.amount == null
        ? ''
        : Money.formatAmount(widget.currency, widget.amount!);
    return [
      widget.title,
      if (widget.statusLabel case final status?) status,
      if (widget.descriptor.isNotEmpty) widget.descriptor,
      if (widget.identityLabel case final identity?) identity,
      if (amount.isNotEmpty) amount,
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final interactive = widget.onTap != null;
    final titleStyle = (theme.textTheme.titleSmall ??
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))
        .copyWith(
      fontWeight: FontWeight.w600,
      color: ExampleInk.primary(context),
      height: 1.3,
    );
    final descriptorStyle =
        (theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
      color: ExampleInk.secondary(context),
      height: 1.35,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget content = Row(
      children: [
        SizedBox.square(
          dimension: ExampleRow.leadingSize,
          child: ExampleTransactionAvatar(
            name: widget.title,
            tint: widget.tint,
            logoUrl: widget.logoUrl,
            fallbackIcon: widget.fallbackIcon,
          ),
        ),
        const SizedBox(width: ExampleRow.leadingGap),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              Row(
                children: [
                  if (widget.statusLabel case final status?) ...[
                    ExamplePill(
                      label: status,
                      color: widget.statusColor,
                      fontSize: 10,
                    ),
                    const SizedBox(width: AppSpacing.xxs + 2),
                  ],
                  Flexible(
                    child: Text(
                      widget.descriptor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: descriptorStyle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ExampleAmount(
              amount: widget.amount,
              currency: widget.currency,
              size: ExampleAmountSize.small,
              tone: ExampleAmountTone.signed,
              code: ExampleAmountCode.auto,
              textAlign: TextAlign.end,
              // A list never crossfades: the rows are rebuilt by scrolling,
              // not by a value changing under the reader.
              animate: false,
            ),
            if (widget.secondaryLabel case final caption?)
              Text(
                caption,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  color: ExampleInk.tertiary(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ],
    );

    if (widget.identityLabel case final identity?) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: ExampleRow.leadingSize + ExampleRow.leadingGap,
              top: 3,
            ),
            child:
                Text(identity, style: descriptorStyle.copyWith(fontSize: 11.5)),
          ),
        ],
      );
    }

    content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(padding: ExampleRow.defaultPadding, child: content),
    );

    content = AnimatedContainer(
      duration: ExampleMotion.of(context, ExampleMotion.state),
      curve: ExampleMotion.arrive,
      color: _hovered && interactive
          ? ExampleInk.hover(context)
          : ExampleInk.hoverOff(context),
      child: content,
    );

    if (widget.divider) {
      content = Stack(
        alignment: Alignment.topLeft,
        children: [
          content,
          PositionedDirectional(
            start: ExampleRow.textInset,
            end: 0,
            bottom: 0,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: ExampleBorders.hairlineSideOf(context)),
              ),
            ),
          ),
        ],
      );
    }

    content = MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: interactive ? (_) => _setHovered(true) : null,
      onExit: interactive ? (_) => _setHovered(false) : null,
      child: content,
    );

    if (!interactive) {
      return MergeSemantics(
        child: Semantics(label: _semanticsLabel, child: content),
      );
    }
    return ExamplePressable(
      onTap: widget.onTap,
      pressedScale: ExampleTransactionRow.pressedScale,
      borderRadius: BorderRadius.circular(
        context.brandShape.radius(AppRadii.xs),
      ),
      semanticsLabel: _semanticsLabel,
      child: content,
    );
  }
}

/// The disc at the head of a transaction row: the merchant's logo when there
/// is one, otherwise an operation icon or its initials on a category tint.
///
/// Deliberately not `ExampleAvatar`, which is the account holder's brand disc
/// — one fixed violet gradient. Six rows of the identical gradient is a list
/// with no identity in it, so merchants get their own letters on a tint drawn
/// only from `ExampleColors`. The wash keeps its Twilight hue in both themes
/// and only the glyph is deepened for paper, exactly as `ExampleIconTile` and
/// `ExamplePill` do, so a category reads as the same colour on both grounds.
class ExampleTransactionAvatar extends StatelessWidget {
  const ExampleTransactionAvatar({
    required this.name,
    this.tint = ExampleColors.iris,
    this.logoUrl = '',
    this.fallbackIcon,
    this.size = ExampleRow.leadingSize,
    super.key,
  });

  final String name;
  final Color tint;
  final String logoUrl;
  final IconData? fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = ExampleTransactionRow.initialsFor(name);
    final glyph = fallbackIcon != null
        ? Icon(
            fallbackIcon,
            size: size * .55,
            color: ExampleInk.accent(context, tint),
          )
        : Text(
            initials,
            maxLines: 1,
            style: TextStyle(
              fontSize: size * (initials.length > 1 ? .34 : .42),
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: .2,
              color: ExampleInk.accent(context, tint),
            ),
          );
    final url = logoUrl.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ExampleInk.tint(context, tint, alpha: .16),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? glyph
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Center(child: glyph),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : Center(child: glyph),
            ),
    );
  }
}
