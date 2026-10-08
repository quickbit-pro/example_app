import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/banking_models.dart';
import '../../shared/theme/app_theme_extensions.dart';
import 'example_motion.dart';
import 'example_tokens.dart';
import 'example_typography.dart';
import 'example_ui.dart' show ExampleThemeContext;

// The size scale lives with the type system (example_typography.dart) so the
// amount style and this widget can never disagree; re-exported here so a
// screen that imports example_amount.dart has everything it needs.
export 'example_typography.dart' show ExampleAmountSize;

/// How the currency is voiced next to the numerals.
enum ExampleAmountCode {
  /// Show the ISO code only when `Money.formatAmount` did not render a
  /// symbol: crypto, stablecoins, AED, CHF and the rest. `$`, `€` and `£`
  /// speak for themselves.
  auto,

  /// Always show the code, symbol or not. The hero balance uses this so
  /// "USD" is explicit above a multi-currency portfolio.
  always,

  /// Never show the code: the currency is already stated nearby, for
  /// example by a `ExampleCurrencyAvatar` in the same row.
  never,
}

/// How the sign of an amount is voiced.
enum ExampleAmountTone {
  /// On-surface colour whatever the sign. Balances, totals, prices, fees.
  neutral,

  /// Credits are success-coloured and prefixed "+"; debits stay on-surface.
  /// Spending is normal, not an error, so this is the tone for transaction
  /// lists and activity feeds.
  signed,

  /// Gains are success and prefixed "+", losses are danger. Only for
  /// numbers that mean profit or loss: portfolio change, price movement,
  /// exchange-rate difference.
  delta,
}

/// A formatted amount, set in tabular figures from the theme's typeface.
///
/// One numeral voice for the whole app. Every amount goes through
/// `Money.formatAmount`, so decimals, grouping, symbols and Private Mode
/// masking are decided in one place; this widget only decides how the
/// result is set:
///
/// * [size] picks the volume ([ExampleAmountSize.hero] for the one balance
///   on the dashboard down to [ExampleAmountSize.inline] for dense lists).
///   At `hero` and `large` the fraction is set at 60 percent and semibold,
///   the way the dashboard balance already reads; at `medium` and below the
///   string is uniform so digit columns align down a list.
/// * [code] decides whether the ISO code is shown. When it is, it is set
///   smaller, semibold and in the secondary text tone on the same baseline,
///   never at the numerals' size.
/// * [tone] colours by sign. The default is neutral; see [ExampleAmountTone]
///   for when a credit should be green and when a loss may be red.
/// * [animate] crossfades the numerals when the value changes: the new
///   digits fade in and rise 2 px over [ExampleMotion.state] through
///   [ExampleStateSwitch]. No count-up, no ticking; the number is simply
///   correct, then correctly different. Instant under reduced motion and
///   never on first build.
///
/// Both themes are first class. The numerals take the theme's on-surface
/// ink (pearl at night, night on paper) and the sign and code inks come from
/// [ExamplePalette], so a credit is Twilight's `success` on the night ground
/// and `lightSuccess` on paper — never the neon green a dark palette becomes
/// when it is pasted onto white (`success` reads 1.70:1 there).
///
/// A null [amount] renders an em dash at the same size, so a balance that
/// has not loaded holds its line. Pair with `ExampleSkeleton.amount` while a
/// whole panel is loading.
class ExampleAmount extends StatelessWidget {
  const ExampleAmount({
    required this.amount,
    required this.currency,
    this.size = ExampleAmountSize.large,
    this.code = ExampleAmountCode.auto,
    this.tone = ExampleAmountTone.neutral,
    this.animate = true,
    this.color,
    this.textAlign = TextAlign.start,
    this.semanticsLabel,
    super.key,
  });

  /// Major units (dollars, not cents). Null renders [placeholder].
  final double? amount;

  /// ISO code or asset symbol, as stored on `Money.currency`.
  final String currency;

  /// Volume of the numerals.
  final ExampleAmountSize size;

  /// Whether and when the ISO code follows the numerals.
  final ExampleAmountCode code;

  /// Sign colouring.
  final ExampleAmountTone tone;

  /// Crossfade when the value changes.
  final bool animate;

  /// Colour of the numerals when [tone] leaves them neutral. Defaults to the
  /// theme's on-surface colour.
  final Color? color;

  /// Horizontal alignment; also aligns the outgoing and incoming numerals
  /// during a crossfade, so a right-aligned column stays right-aligned.
  final TextAlign textAlign;

  /// Accessible label override. By default the rendered string is read.
  final String? semanticsLabel;

  /// Rendered in place of a null [amount].
  static const String placeholder = '—';

  /// Fraction scale at the two largest sizes (31 / 19 on today's dashboard).
  static const double _fractionScale = .6;

  /// Code scale, clamped so it never drops under 11 px or over 16 px.
  static const double _codeScale = .38;

  @override
  Widget build(BuildContext context) {
    final parts = _AmountParts.resolve(
      amount,
      currency,
      code: code,
      tone: tone,
      splitFraction: _splitsFraction(size),
    );
    final text = _text(context, parts);
    // Privacy changes must remove the previous digits immediately instead
    // of retaining them in an outgoing crossfade.
    if (!animate || Money.maskAmounts) return text;
    return ExampleStateSwitch(
      alignment: _alignment(context),
      child: KeyedSubtree(key: ValueKey<String>(parts.key), child: text),
    );
  }

  static bool _splitsFraction(ExampleAmountSize size) =>
      size == ExampleAmountSize.hero || size == ExampleAmountSize.large;

  static double _fractionSize(ExampleAmountSize size) =>
      (size.fontSize * _fractionScale).roundToDouble();

  static double _codeSize(ExampleAmountSize size) =>
      (size.fontSize * _codeScale).clamp(11.0, 16.0).roundToDouble();

  Alignment _alignment(BuildContext context) {
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return switch (textAlign) {
      TextAlign.left => Alignment.centerLeft,
      TextAlign.right => Alignment.centerRight,
      TextAlign.center || TextAlign.justify => Alignment.center,
      TextAlign.start => AlignmentDirectional.centerStart.resolve(direction),
      TextAlign.end => AlignmentDirectional.centerEnd.resolve(direction),
    };
  }

  Widget _text(BuildContext context, _AmountParts parts) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    final finance = context.financeTheme;
    // Sign inks by role, resolved for the active brightness: Twilight's
    // `success` / `danger` at night, the re-darkened daylight pair on paper.
    // Other brands keep their own two-mode FinanceTheme.
    final palette = ExamplePalette.of(context);
    final positive = isExample ? palette.success : finance.positive;
    final negative = isExample ? palette.danger : finance.negative;
    final neutral = color ?? theme.colorScheme.onSurface;
    final ink = switch (tone) {
      ExampleAmountTone.neutral => neutral,
      ExampleAmountTone.signed => parts.sign > 0 ? positive : neutral,
      ExampleAmountTone.delta => parts.sign > 0
          ? positive
          : parts.sign < 0
              ? negative
              : neutral,
    };
    final secondary =
        isExample ? palette.textSecondary : theme.colorScheme.onSurfaceVariant;

    final base =
        ExampleTextStyles.amount(context, size: size).copyWith(color: ink);
    final codeSize = _codeSize(size);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: parts.number),
          if (parts.fraction.isNotEmpty)
            TextSpan(
              text: parts.fraction,
              style: base.copyWith(
                fontSize: _fractionSize(size),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          if (parts.code != null)
            TextSpan(
              text: ' ${parts.code}',
              style: base.copyWith(
                color: secondary,
                fontSize: codeSize,
                fontWeight: FontWeight.w600,
                letterSpacing: codeSize * .04,
              ),
            ),
        ],
      ),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
      semanticsLabel:
          Money.maskAmounts ? context.tr('Amount hidden') : semanticsLabel,
    );
  }
}

/// The formatted amount split into the runs [ExampleAmount] sets differently.
class _AmountParts {
  const _AmountParts({
    required this.number,
    required this.fraction,
    required this.code,
    required this.sign,
  });

  /// Sign, symbol and whole digits (plus the fraction when not split).
  final String number;

  /// `.35`-style fraction when split out, otherwise empty.
  final String fraction;

  /// ISO code to set small, or null.
  final String? code;

  /// -1, 0 or 1.
  final int sign;

  /// Identity of the rendered state, for the crossfade key.
  String get key => '$number|$fraction|${code ?? ''}|$sign';

  static _AmountParts resolve(
    double? amount,
    String currency, {
    required ExampleAmountCode code,
    required ExampleAmountTone tone,
    required bool splitFraction,
  }) {
    if (Money.maskAmounts) {
      return const _AmountParts(
        number: '••••',
        fraction: '',
        code: null,
        sign: 0,
      );
    }
    final iso = currency.trim().toUpperCase();
    final explicitCode =
        code == ExampleAmountCode.always && iso.isNotEmpty ? iso : null;
    if (amount == null) {
      return _AmountParts(
        number: ExampleAmount.placeholder,
        fraction: '',
        code: explicitCode,
        sign: 0,
      );
    }

    // Money.formatAmount appends " CODE" when it has no symbol for the
    // currency; peel it off so the code can be set small.
    var number = Money.formatAmount(currency, amount);
    String? trailing;
    if (iso.isNotEmpty && number.endsWith(' $iso')) {
      number = number.substring(0, number.length - iso.length - 1);
      trailing = iso;
    }
    final shownCode = switch (code) {
      ExampleAmountCode.auto => trailing,
      ExampleAmountCode.always => explicitCode,
      ExampleAmountCode.never => null,
    };

    final sign = amount > 0 ? 1 : (amount < 0 ? -1 : 0);
    // The formatter already writes "-" for debits; only credits need help.
    if (tone != ExampleAmountTone.neutral && sign > 0) number = '+$number';

    var fraction = '';
    if (splitFraction) {
      final dot = number.lastIndexOf('.');
      if (dot > 0) {
        fraction = number.substring(dot);
        number = number.substring(0, dot);
      }
    }
    return _AmountParts(
      number: number,
      fraction: fraction,
      code: shownCode,
      sign: sign,
    );
  }
}

/// Where a long machine string gives way.
enum ExampleMonoTruncate {
  /// Show the whole string; `maxLines` and an end ellipsis apply.
  none,

  /// Keep the head and tail and elide the middle (`0x1234…abcd`), so both
  /// the prefix that identifies the kind of string and the suffix people
  /// compare against survive.
  middle,
}

/// Machine strings in Geist Mono: wallet addresses, transaction hashes,
/// card numbers, IBANs, one-time codes.
///
/// Monospace is a signal, not a style: it tells the reader "compare these
/// characters, do not read them". Slashed zeros (`ss09`) keep 0 and O
/// apart. Group digits with [group] (4 for card numbers and IBANs) rather
/// than tracking; elide long hashes with [truncate].
///
/// With [copyable] the whole string becomes one 44 pt tap target that copies
/// the full, untruncated [text] to the clipboard. Feedback happens in place:
/// the copy glyph swaps to a check for 1.6 s through [ExampleStateSwitch] and
/// the button's label changes to "Copied" inside a live region, so assistive
/// technology hears it without a toast. [onCopied] is for anything extra the
/// screen wants to do (analytics, a snack bar). Do not make a copyable
/// string a child of another tappable row; give it its own row.
///
/// Outside the Example theme the platform monospace family is used, so a
/// white-label tenant never sees Geist Mono. The copy affordance and its
/// confirmation tick read through [ExamplePalette], so both hold their
/// contrast on paper as well as on the night ground.
class ExampleMono extends StatefulWidget {
  const ExampleMono(
    this.text, {
    this.truncate = ExampleMonoTruncate.none,
    this.head = 6,
    this.tail = 4,
    this.group = 0,
    this.size = 13,
    this.weight = FontWeight.w400,
    this.color,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
    this.copyable = false,
    this.onCopied,
    super.key,
  })  : assert(head > 0, 'head must keep at least one character'),
        assert(tail > 0, 'tail must keep at least one character'),
        assert(group >= 0, 'group is zero (off) or a run length');

  /// The full string. Copied verbatim (trimmed) regardless of display.
  final String text;

  /// Elision strategy.
  final ExampleMonoTruncate truncate;

  /// Characters kept before the ellipsis when truncating. 6 covers `0x`
  /// plus four hex digits.
  final int head;

  /// Characters kept after the ellipsis when truncating.
  final int tail;

  /// Insert a space every [group] characters (0 = off). Applied before
  /// truncation, so head and tail count grouped characters.
  final int group;

  /// Font size. 13 sits under a 14 px body; use 15 or 16 for a card number
  /// on its own line.
  final double size;

  /// Geist Mono ships at 400 and 500; other weights snap to the nearest.
  final FontWeight weight;

  /// Text colour. Defaults to the theme's on-surface colour.
  final Color? color;

  /// Lines before an end ellipsis when not truncating in the middle.
  final int maxLines;

  /// Horizontal alignment.
  final TextAlign textAlign;

  /// Make the string a copy button.
  final bool copyable;

  /// Called after a successful copy, once the in-place feedback has begun.
  final VoidCallback? onCopied;

  /// How long the check mark stays before the copy glyph returns.
  static const Duration copiedFor = Duration(milliseconds: 1600);

  static const String _ellipsis = '…';
  static const double _minTarget = 44;
  static const double _iconBox = 20;
  static const double _iconSize = 16;

  /// `abcdef…wxyz`: keeps [head] and [tail] characters around [ellipsis].
  /// Strings no longer than the elided form come back unchanged.
  static String truncateMiddle(
    String value, {
    int head = 6,
    int tail = 4,
    String ellipsis = _ellipsis,
  }) {
    final trimmed = value.trim();
    if (trimmed.length <= head + tail + ellipsis.length) return trimmed;
    return '${trimmed.substring(0, head)}'
        '$ellipsis'
        '${trimmed.substring(trimmed.length - tail)}';
  }

  /// `4242 4242 4242 4242`: strips existing whitespace and inserts
  /// [separator] every [run] characters. A [run] of zero returns the value
  /// unchanged.
  static String groupEvery(String value, int run, {String separator = ' '}) {
    if (run <= 0) return value;
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    final buffer = StringBuffer();
    for (var index = 0; index < compact.length; index++) {
      if (index > 0 && index % run == 0) buffer.write(separator);
      buffer.write(compact[index]);
    }
    return buffer.toString();
  }

  /// The string as rendered: grouped, then truncated.
  String get display {
    var value = text.trim();
    if (group > 0) value = groupEvery(value, group);
    if (truncate == ExampleMonoTruncate.middle) {
      value = truncateMiddle(value, head: head, tail: tail);
    }
    return value;
  }

  @override
  State<ExampleMono> createState() => _ExampleMonoState();
}

class _ExampleMonoState extends State<ExampleMono> {
  Timer? _revert;
  bool _copied = false;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text.trim()));
    } catch (_) {
      // The clipboard is unavailable (a blocked web context, a headless
      // test). No feedback is more honest than a false check mark.
      return;
    }
    if (!mounted) return;
    _revert?.cancel();
    setState(() => _copied = true);
    _revert = Timer(ExampleMono.copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
    widget.onCopied?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    var style = ExampleTextStyles.mono(
      context,
      size: widget.size,
      weight: widget.weight,
    );
    if (!isExample) {
      style = style.copyWith(
        fontFamily: 'monospace',
        fontFeatures: const <FontFeature>[],
      );
    }
    if (widget.color != null) style = style.copyWith(color: widget.color);

    final display = widget.display;
    final text = Text(
      display,
      textDirection: TextDirection.ltr,
      style: style,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: widget.maxLines > 1,
      textAlign: widget.textAlign,
    );
    if (!widget.copyable) return text;

    final palette = ExamplePalette.of(context);
    final secondary =
        isExample ? palette.textSecondary : theme.colorScheme.onSurfaceVariant;
    final success = isExample ? palette.success : context.financeTheme.positive;

    // MergeSemantics folds the live region and the pressable's button node
    // into one, so the label change to "Copied" is announced.
    return MergeSemantics(
      child: Semantics(
        liveRegion: true,
        child: ExamplePressable(
          onTap: _copy,
          semanticsLabel: _copied
              ? context.tr('Copied')
              : context.tr('Copy {p0}', {'p0': display}),
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.xs)),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: ExampleMono._minTarget),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: text),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox.square(
                    dimension: ExampleMono._iconBox,
                    child: Center(
                      child: ExampleStateSwitch(
                        child: Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          key: ValueKey<bool>(_copied),
                          size: ExampleMono._iconSize,
                          color: _copied ? success : secondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
