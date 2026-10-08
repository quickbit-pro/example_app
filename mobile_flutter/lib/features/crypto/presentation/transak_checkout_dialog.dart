import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import 'transak_checkout_frame.dart';

Future<void> showTransakCheckout(BuildContext context, String url) {
  if (!context.isExampleTheme) return _showLegacyTransakCheckout(context, url);
  // `useSafeArea` is a property of the route, so it can only be decided from
  // the size at the moment the dialog opens. Everything the customer actually
  // looks at is decided inside the builder instead — see [_CheckoutDialog].
  final desktop = MediaQuery.sizeOf(context).width >= _desktopWidth;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useSafeArea: !desktop,
    builder: (dialogContext) => _CheckoutDialog(url: url),
  );
}

const double _desktopWidth = 900;

class _CheckoutDialog extends StatelessWidget {
  const _CheckoutDialog({required this.url});

  final String url;

  static const double _columnWidth = 480;

  static const double _minHeight = 360;
  static const double _maxHeight = 780;

  static const double _inset = AppSpacing.lg * 2;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final desktop = size.width >= _desktopWidth;
    final isExample = context.isExampleTheme;
    final surface = isExample
        ? ExampleSurface.navigationOf(context)
        : context.brandDesign.color(Theme.of(context).brightness, 'navigation',
            fallback: ExampleColors.navigationSurface);
    final frame = TransakCheckoutFrame(url: url);
    final content = isExample
        ? _ExampleCheckoutChrome(
            surface: surface,
            child: frame,
          )
        : Scaffold(
            backgroundColor: surface,
            appBar: AppBar(
              backgroundColor: surface,
              automaticallyImplyLeading: false,
              title: Text(context.tr('Buy with card')),
              actions: [
                IconButton(
                  tooltip: context.tr('Close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: frame,
          );
    if (!desktop) return Dialog.fullscreen(child: content);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: DecoratedBox(
        // The desktop dialog is an object resting on the page, not a hole
        // punched in the barrier. On paper that separation has to be a real
        // ambient shadow: a 480 pt white column on a white scrim has no edge
        // otherwise.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow:
              isExample ? ExampleShadows.sheetOf(context) : const <BoxShadow>[],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            // Never wider than the viewport can hold, so a short-but-wide
            // window (a split screen at 920) gets a column, not a clip.
            width: math.min(_columnWidth, size.width - _inset),
            // Short desktop windows exist: never ask for more height than the
            // viewport can give, or the dialog overflows instead of scrolling.
            height: math.min(
              _maxHeight,
              math.max(_minHeight, size.height - _inset),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _ExampleCheckoutChrome extends StatelessWidget {
  const _ExampleCheckoutChrome({
    required this.surface,
    required this.child,
  });

  final Color surface;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.tr('Buy with card'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.2,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Decoration for the sentence beside it, so it is
                            // kept out of the semantics tree: a screen reader
                            // that says "lock, secure checkout by Transak"
                            // has been told the same thing twice.
                            ExcludeSemantics(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.lock_outline_rounded,
                                  size: 13,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                context.tr('Secure checkout by Transak'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    // The dialog is not barrier-dismissible, so this is the
                    // only way out. Named for what it closes: inside a nested
                    // surface, a bare "Close" is ambiguous.
                    tooltip: context.tr('Close checkout'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: palette.textSecondary,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: palette.borderSubtle),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _CheckoutSkeleton(),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutSkeleton extends StatelessWidget {
  const _CheckoutSkeleton();

  static const double _receiveFloor = 320;

  static const double _methodFloor = 440;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return Semantics(
      label: context.tr('Loading the checkout'),
      // One announcement for the placeholder, not one per block.
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final showsReceive = height >= _receiveFloor;
            final showsMethod = height >= _methodFloor;
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExampleSkeleton.line(width: 96, sheen: false),
                  const SizedBox(height: AppSpacing.sm),
                  const ExampleSkeleton.card(height: 68, sheen: false),
                  if (showsReceive) ...[
                    const SizedBox(height: AppSpacing.md),
                    const ExampleSkeleton.line(width: 120, sheen: false),
                    const SizedBox(height: AppSpacing.sm),
                    const ExampleSkeleton.card(height: 68, sheen: false),
                  ],
                  if (showsMethod) ...[
                    const SizedBox(height: AppSpacing.lg),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        border: Border.all(color: palette.borderSubtle),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        child: ExampleSkeleton.row(
                          padding: EdgeInsets.zero,
                          sheen: false,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  const ExampleSkeleton(
                    height: 54,
                    radius: AppRadii.pill,
                    sheen: false,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<void> _showLegacyTransakCheckout(BuildContext context, String url) {
  final desktop = MediaQuery.sizeOf(context).width >= 900;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useSafeArea: !desktop,
    builder: (dialogContext) {
      final content = Scaffold(
        backgroundColor: context.brandDesign.color(
            Theme.of(context).brightness, 'navigation',
            fallback: ExampleColors.navigationSurface),
        appBar: AppBar(
          backgroundColor: context.brandDesign.color(
              Theme.of(context).brightness, 'navigation',
              fallback: ExampleColors.navigationSurface),
          automaticallyImplyLeading: false,
          title: Text(context.tr('Buy with card')),
          actions: [
            IconButton(
              tooltip: context.tr('Close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: TransakCheckoutFrame(url: url),
      );
      if (!desktop) return Dialog.fullscreen(child: content);
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            width: 480,
            height: 780,
            child: content,
          ),
        ),
      );
    },
  );
}
