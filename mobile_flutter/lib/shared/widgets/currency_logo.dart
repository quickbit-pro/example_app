import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class CurrencyLogo extends StatelessWidget {
  const CurrencyLogo({
    required this.symbol,
    this.size = 40,
    this.fallbackIcon,
    this.fallbackColor,
    super.key,
  });

  final String symbol;
  final double size;
  final IconData? fallbackIcon;
  final Color? fallbackColor;

  static bool supports(String symbol) {
    final normalized = symbol.trim().toUpperCase();
    return normalized == 'USDC' || normalized == 'USDT';
  }

  @override
  Widget build(BuildContext context) {
    final normalized = symbol.trim().toUpperCase();
    final asset = switch (normalized) {
      'USDC' => 'assets/crypto/usdc.png',
      'USDT' => 'assets/crypto/usdt.png',
      _ => null,
    };

    if (asset != null) {
      return Semantics(
        image: true,
        label: context.tr('{p0} logo', {'p0': normalized}),
        child: ClipOval(
          child: Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    final color = fallbackColor ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        shape: BoxShape.circle,
      ),
      child: fallbackIcon == null
          ? Text(
              normalized.isEmpty ? '?' : normalized.characters.first,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            )
          : Icon(fallbackIcon, color: color, size: size * .55),
    );
  }
}
