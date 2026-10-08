import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/privacy/private_mode_provider.dart';

import '../../../../brands/example/example_ui.dart';
import '../../../../core/models/banking_models.dart';

/// Displays the card artwork supplied by the server, with shared sizing,
/// status and motion styling across the Cards feature. A provisioned card
/// without artwork uses a neutral placeholder.
class CardFace extends ConsumerWidget {
  const CardFace({
    this.card,
    this.showBalance = false,
    this.height = 188,
    this.compact = false,
    this.status,
    this.onTap,
    this.frozen = false,
    this.interactive = true,
    this.enableHoverTilt = true,
    this.sweepOnArrival = true,
    this.semanticsLabel,
    super.key,
  });

  /// Server card data, including artwork URL and text metadata.
  final PaymentCard? card;
  final bool showBalance;

  /// Rendered height. Callers size by width / [aspectRatio].
  final double height;

  /// Thumbnail dressing: fewer marks, tighter padding.
  final bool compact;

  /// Overrides `card.status` while an optimistic freeze is in flight.
  final CardStatus? status;

  final VoidCallback? onTap;

  /// Frosted freeze overlay. Derived from [status] by the fallback.
  final bool frozen;

  /// Pointer tilt and press response. Off for a face that is only decoration.
  final bool interactive;

  /// Disable when an ancestor ExampleTiltCard supplies phone and pointer tilt.
  final bool enableHoverTilt;

  /// One specular pass after the route settles. Off for every face but the
  /// one the screen arrives on.
  final bool sweepOnArrival;

  /// Accessible name. Null lets the face publish its own masked description;
  /// an ancestor [ExamplePressable] that carries a label already excludes this
  /// subtree, so a deck card correctly passes nothing.
  final String? semanticsLabel;

  /// ISO 7810 ID-1. The only ratio a card face is ever drawn at.
  static const double aspectRatio = 1.586;

  /// Height for a face that spans [width].
  static double heightFor(double width) => width / aspectRatio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (showBalance) ref.watch(privateModeProvider);
    final face = ExampleLivingCard(
      card: card,
      height: height,
      compact: compact,
      status: status,
      onTap: onTap,
      frozen: frozen,
      interactive: interactive,
      enableHoverTilt: enableHoverTilt,
      sweepOnArrival: sweepOnArrival,
      semanticsLabel: semanticsLabel,
    );
    if (!showBalance || card == null) return face;
    final ink = cardArtworkTextColor(card!.cardTextColor);
    final shadow = ink.computeLuminance() > .5 ? Colors.black : Colors.white;
    return Stack(
      children: [
        face,
        Positioned(
          left: (height * .085).clamp(10.0, 16.0),
          right: 16,
          top: height * .62,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                card!.hasReportedBalance
                    ? '${card!.balance.formatted} ${card!.balance.currency}'
                    : context.tr('Balance unavailable'),
                key: ValueKey('card-preview-balance-${card!.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: (height * .078).clamp(15.0, 20.0),
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.2,
                  shadows: [
                    Shadow(
                        color: shadow.withValues(alpha: .55),
                        blurRadius: 6,
                        offset: const Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
