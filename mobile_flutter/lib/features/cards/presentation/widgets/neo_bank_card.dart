import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/branding/app_design.dart';
import '../../../../core/models/banking_models.dart';

/// Neo-bank style payment card visual: gradient skin, subtle decorations,
/// chip + brand mark, optional masked PAN. Adapts to a compact mode for use
/// in horizontal carousels.
class NeoBankCard extends StatelessWidget {
  const NeoBankCard({
    super.key,
    required this.label,
    required this.last4,
    required this.network,
    required this.virtual,
    this.status = CardStatus.active,
    this.holderName,
    this.balanceText,
    this.compact = false,
    this.skin = NeoCardSkin.midnight,
    this.artworkUrl,
    this.artworkAlt,
    this.textColorHex,
    this.onTap,
  });

  /// Convenience: build directly from a [PaymentCard].
  factory NeoBankCard.fromCard(
    PaymentCard card, {
    bool compact = false,
    NeoCardSkin? skin,
    String? holderName,
    VoidCallback? onTap,
  }) {
    return NeoBankCard(
      label: card.label,
      last4: card.last4,
      network: card.network,
      virtual: card.virtual,
      status: card.status,
      holderName: holderName,
      balanceText: card.balance.formatted,
      compact: compact,
      skin:
          skin ?? NeoCardSkin.fromSeed(card.id.isEmpty ? card.label : card.id),
      artworkUrl: compact
          ? (card.cardThumbnailUrl.isNotEmpty
              ? card.cardThumbnailUrl
              : card.artworkUrl)
          : card.artworkUrl,
      artworkAlt: card.cardImageAlt,
      textColorHex: card.cardTextColor,
      onTap: onTap,
    );
  }

  final String label;
  final String last4;
  final String network;
  final bool virtual;
  final CardStatus status;
  final String? holderName;
  final String? balanceText;
  final bool compact;
  final NeoCardSkin skin;
  final String? artworkUrl;
  final String? artworkAlt;
  final String? textColorHex;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // ISO/IEC 7810 ID-1 proportions (85.60 × 53.98 mm) in every size.
    const cardAspect = 1.586;
    final width = compact ? 280.0 : double.infinity;
    final height = compact ? 280.0 / cardAspect : null;
    final radius = BorderRadius.circular(compact ? 22 : 26);
    final isFrozen = status == CardStatus.frozen;
    final design = context.brandDesign;
    final brightness = Theme.of(context).brightness;
    final contentColor = _hexColor(textColorHex) ??
        design.color(brightness, 'cardForeground', fallback: Colors.white);
    final decorationColor =
        design.color(brightness, 'cardDecoration', fallback: Colors.white);
    final overlayColor =
        design.color(brightness, 'cardOverlay', fallback: Colors.black);
    final skinColors = skin.colorsFor(context);
    final imageUrl = artworkUrl?.trim() ?? '';

    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          colors: skinColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: skinColors.last.withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Soft decorative orbs.
            Positioned(
              right: -40,
              top: -40,
              child: _Orb(
                  color: decorationColor.withValues(alpha: 0.10), size: 160),
            ),
            Positioned(
              left: -30,
              bottom: -50,
              child: _Orb(
                  color: decorationColor.withValues(alpha: 0.06), size: 180),
            ),
            // Subtle diagonal sheen.
            Positioned.fill(
              child: CustomPaint(painter: _SheenPainter(decorationColor)),
            ),
            if (imageUrl.isNotEmpty)
              Positioned.fill(
                child: Image.network(
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  imageUrl,
                  fit: BoxFit.cover,
                  semanticLabel: artworkAlt?.trim().isEmpty ?? true
                      ? context.tr('Card design')
                      : artworkAlt,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            // Frozen overlay.
            if (isFrozen)
              Positioned.fill(
                child: ColoredBox(
                  color: overlayColor.withValues(alpha: 0.32),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(compact ? 16 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        virtual
                            ? Icons.smartphone_rounded
                            : Icons.contactless_rounded,
                        size: 18,
                        color: contentColor.withValues(alpha: 0.85),
                      ),
                      const Spacer(),
                      if (network.trim().isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: overlayColor.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: contentColor.withValues(alpha: .3),
                            ),
                          ),
                          child: Text(
                            _networkDisplayName(network),
                            style: TextStyle(
                              color: contentColor,
                              fontSize: compact ? 10 : 12,
                              letterSpacing: .7,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        virtual
                            ? context.tr('VIRTUAL')
                            : context.tr('PHYSICAL'),
                        style: TextStyle(
                          color: contentColor.withValues(alpha: 0.85),
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (balanceText != null && balanceText!.isNotEmpty) ...[
                    Text(
                      balanceText!,
                      style: TextStyle(
                        color: contentColor,
                        fontSize: compact ? 18 : 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: contentColor.withValues(alpha: 0.92),
                      fontSize: compact ? 12 : 13,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          '••••  ••••  ••••  ${last4.isEmpty ? '0000' : last4}',
                          style: TextStyle(
                            color: contentColor,
                            fontSize: compact ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!compact && holderName != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      holderName!.toUpperCase(),
                      style: TextStyle(
                        color: contentColor.withValues(alpha: 0.78),
                        fontSize: 11,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isFrozen)
              const Positioned(
                right: 14,
                top: 52,
                child: _FrozenBadge(),
              ),
          ],
        ),
      ),
    );
    final card =
        compact ? face : AspectRatio(aspectRatio: cardAspect, child: face);

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

Color? _hexColor(String? value) {
  final normalized = value?.trim().replaceFirst('#', '') ?? '';
  if (normalized.length != 6 && normalized.length != 8) return null;
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) return null;
  return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
}

class NeoCardSkin {
  const NeoCardSkin(this.colors, {this.name = 'Custom'});

  final List<Color> colors;
  final String name;

  static const midnight = NeoCardSkin(
    [Color(0xFF0F172A), Color(0xFF312E81), Color(0xFF7C3AED)],
    name: 'Midnight',
  );
  static const aurora = NeoCardSkin(
    [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFFEC4899)],
    name: 'Aurora',
  );
  static const sunset = NeoCardSkin(
    [Color(0xFFF97316), Color(0xFFDB2777), Color(0xFF7C3AED)],
    name: 'Sunset',
  );
  static const forest = NeoCardSkin(
    [Color(0xFF064E3B), Color(0xFF0F766E), Color(0xFF22C55E)],
    name: 'Forest',
  );
  static const onyx = NeoCardSkin(
    [Color(0xFF111827), Color(0xFF1F2937), Color(0xFF374151)],
    name: 'Onyx',
  );

  static const all = [midnight, aurora, sunset, forest, onyx];

  /// Brand colors replace the built-in fallback skins. Explicit custom skins
  /// remain owned by their caller, just like card artwork from the API.
  List<Color> colorsFor(BuildContext context) {
    if (!all.contains(this)) return colors;
    final design = context.brandDesign;
    final brightness = Theme.of(context).brightness;
    return [
      design.color(brightness, 'cardStart', fallback: colors[0]),
      design.color(brightness, 'cardMiddle', fallback: colors[1]),
      design.color(brightness, 'cardEnd', fallback: colors[2]),
    ];
  }

  /// Deterministic skin based on a string (so the same card always renders
  /// the same gradient).
  factory NeoCardSkin.fromSeed(String seed) {
    if (seed.isEmpty) return midnight;
    final hash = seed.codeUnits.fold<int>(0, (acc, c) => acc + c);
    return all[hash % all.length];
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _SheenPainter extends CustomPainter {
  const _SheenPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.45,
        size.width,
        size.height * 0.7,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final paint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SheenPainter oldDelegate) =>
      oldDelegate.color != color;
}

String _networkDisplayName(String network) {
  final normalized = network.trim().toLowerCase();
  if (normalized.contains('master')) return 'MASTERCARD';
  if (normalized.contains('visa')) return 'VISA';
  return network.trim().toUpperCase();
}

class _FrozenBadge extends StatelessWidget {
  const _FrozenBadge();

  @override
  Widget build(BuildContext context) {
    final foreground = context.brandDesign.color(
      Theme.of(context).brightness,
      'cardForeground',
      fallback: Colors.white,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.ac_unit, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            context.tr('FROZEN'),
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// Avoid unused import warning when this file is consumed standalone.
// ignore: unused_element
double _silence(double v) => math.max(0, v);
