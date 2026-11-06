import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/cache/display_snapshot.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../data/service_onboarding_provider.dart';
import '../../domain/service_onboarding.dart';

List<ServiceOnboardingItem> watchServiceOnboarding(WidgetRef ref,
    {required bool isBusinessAccount}) {
  if (isBusinessAccount) {
    return const [];
  }
  final owner = ref.watch(displayCacheOwnerProvider);
  return (ref.watch(homeServiceOnboardingProvider).valueOrNull ?? const [])
      .where((item) => item.owner == owner)
      .toList(growable: false);
}

/// The desktop toolbar uses one line when it fits, otherwise a pinned second
/// row. Status text remains readable rather than being clipped or hidden.
class ServiceOnboardingButtons extends ConsumerWidget {
  const ServiceOnboardingButtons({required this.items, super.key});
  final List<ServiceOnboardingItem> items;

  static double _width(BuildContext context, ServiceOnboardingItem item) {
    double measure(String value, double size) {
      final painter = TextPainter(
          text: TextSpan(
              text: value,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontSize: size, fontWeight: FontWeight.w600)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context))
        ..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return measure(context.tr(item.kind.label), 12) +
        measure(context.tr(item.stage.label), 10.5) +
        78;
  }

  static bool fitsInline(BuildContext context,
          List<ServiceOnboardingItem> items, double width) =>
      items.fold<double>(0, (sum, item) => sum + _width(context, item) + 8) <=
      width;

  static double height(
      BuildContext context, List<ServiceOnboardingItem> items, double width) {
    if (items.isEmpty) {
      return 0;
    }
    var rows = 1;
    var used = 0.0;
    for (final item in items) {
      final next = math.min(width, _width(context, item));
      if (used > 0 && used + 8 + next > width) {
        rows++;
        used = 0;
      }
      used += (used == 0 ? 0 : 8) + next;
    }
    return rows * _buttonHeight(context) + (rows - 1) * 8;
  }

  static double _buttonHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return scale.scale(12) > 20
        ? scale.scale(12) * 1.25 + scale.scale(10.5) * 1.15 + 24
        : math.max(36, scale.scale(12) * 1.25 + 16);
  }

  static PreferredSizeWidget? bottom(BuildContext context,
          List<ServiceOnboardingItem> items, double width) =>
      items.isEmpty
          ? null
          : PreferredSize(
              preferredSize: Size.fromHeight(
                  height(context, items, math.max(1, width - 32)) + 16),
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: ServiceOnboardingButtons(items: items))));

  Future<void> _open(
      BuildContext context, WidgetRef ref, ServiceOnboardingItem item) async {
    if (item.owner != ref.read(displayCacheOwnerProvider)) {
      return;
    }
    if (item.stage == OnboardingStage.complete) {
      try {
        final store = await ref.read(onboardingNoticeStoreProvider.future);
        await store.acknowledge(item.kind);
        if (!context.mounted) {
          return;
        }
        ref.invalidate(homeServiceOnboardingProvider);
      } catch (_) {
        /* Local display preferences must not block the status page. */
      }
    }
    if (!context.mounted || item.owner != ref.read(displayCacheOwnerProvider)) {
      return;
    }
    final target = item.blockedBy ?? item.kind;
    if (item.blockedBy != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('Complete {p0} before starting {p1}.', {
        'p0': context.tr(target.label),
        'p1': context.tr(item.kind.label)
      }))));
    }
    final route = switch (target) {
      OnboardingService.cryptoCards =>
        item.stage == OnboardingStage.complete && item.blockedBy == null
            ? AppRoutes.kycStatus
            : AppRoutes.kyc,
      OnboardingService.banking => AppRoutes.bankingOnboarding,
      OnboardingService.exchange => AppRoutes.exchangeOnboarding,
    };
    await context.push(route);
    if (context.mounted) refreshServiceOnboarding(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final item in items)
        Builder(builder: (context) {
          final (color, icon) = switch (item.stage) {
            OnboardingStage.complete => (
                dark ? const Color(0xFF8BDB9B) : const Color(0xFF237A34),
                Icons.check_circle_rounded
              ),
            OnboardingStage.needUpdate => (
                dark ? const Color(0xFFFFC477) : const Color(0xFF9A4D00),
                Icons.warning_amber_rounded
              ),
            OnboardingStage.rejected => (
                dark ? const Color(0xFFFFA4B4) : const Color(0xFFB42343),
                Icons.cancel_outlined
              ),
            OnboardingStage.inProgress => (
                dark ? const Color(0xFFA5C8FF) : const Color(0xFF245FB2),
                Icons.schedule_rounded
              ),
            OnboardingStage.start => (
                theme.colorScheme.primary,
                Icons.play_arrow_rounded
              ),
            OnboardingStage.unavailable => (
                theme.colorScheme.onSurfaceVariant,
                Icons.help_outline_rounded
              ),
          };
          final name = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(context.tr(item.kind.label),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))
          ]);
          final status = Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(context.tr(item.stage.label),
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: color)));
          final content = MediaQuery.textScalerOf(context).scale(12) > 20
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [name, const SizedBox(height: 4), status])
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [name, const SizedBox(width: 7), status]);
          return Tooltip(
              message: item.blockedBy == null
                  ? '${context.tr(item.kind.label)}: ${context.tr(item.stage.label)}'
                  : context.tr('Complete {p0} before starting {p1}.', {
                      'p0': context.tr(item.blockedBy!.label),
                      'p1': context.tr(item.kind.label)
                    }),
              child: OutlinedButton(
                  key: ValueKey('onboarding-${item.kind.name}'),
                  onPressed: () => _open(context, ref, item),
                  style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, _buttonHeight(context)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      foregroundColor: theme.colorScheme.onSurface,
                      backgroundColor:
                          color.withValues(alpha: dark ? .10 : .06),
                      side: BorderSide(color: color.withValues(alpha: .42)),
                      shape: const StadiumBorder(),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: content));
        })
    ]);
  }
}

/// Compact phone layout below Home's brand/actions row.
class ServiceOnboardingBanner extends ConsumerWidget {
  const ServiceOnboardingBanner({required this.isBusinessAccount, super.key});
  final bool isBusinessAccount;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        watchServiceOnboarding(ref, isBusinessAccount: isBusinessAccount);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ServiceOnboardingButtons(items: items));
  }
}
