import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../core/branding/app_design.dart';
import '../../shared/widgets/brand_asset.dart';
import 'example_colors.dart';
import 'example_mark.dart';

/// Holds a customer-branded splash while the stored session is restored,
/// then fades it out. Later authentication changes never reopen the splash.
class ExampleStartupSplash extends ConsumerStatefulWidget {
  const ExampleStartupSplash({required this.child, super.key});

  final Widget child;

  static const bootChoreography = Duration(milliseconds: 1600);

  @override
  ConsumerState<ExampleStartupSplash> createState() =>
      _ExampleStartupSplashState();
}

class _ExampleStartupSplashState extends ConsumerState<ExampleStartupSplash> {
  // Keep a short minimum on web and a longer native launch interval.
  static final _minimum = kIsWeb
      ? const Duration(milliseconds: 450)
      : ExampleStartupSplash.bootChoreography +
          const Duration(milliseconds: 150);
  static const _longest = Duration(seconds: 8);

  bool _minimumElapsed = false;
  bool _sessionReady = false;
  Timer? _dismissTimer;
  Timer? _capTimer;
  var _visible = true;
  var _fading = false;
  var _timersStarted = false;
  var _reduceMotion = false;
  Duration _fadeDuration = const Duration(milliseconds: 320);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final design = context.brandDesign;
    _reduceMotion = !design.motionEnabled ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _fadeDuration = _reduceMotion
        ? Duration.zero
        : Duration(milliseconds: (320 * design.motionDurationScale).round());
    if (design.isConfigured && !design.splashEnabled) {
      _dismissTimer?.cancel();
      _capTimer?.cancel();
      _visible = false;
      return;
    }
    if (_timersStarted) return;
    _timersStarted = true;
    final minimum = _reduceMotion
        ? Duration.zero
        : design.isConfigured
            ? Duration(milliseconds: design.splashMinimumDurationMs)
            : _minimum;
    final maximum = design.isConfigured
        ? Duration(milliseconds: design.splashMaximumDurationMs)
        : _longest;
    if (minimum == Duration.zero) {
      _minimumElapsed = true;
    } else {
      _dismissTimer = Timer(minimum, () {
        _minimumElapsed = true;
        if (_sessionReady) _startFade();
      });
    }
    _capTimer = Timer(maximum, _startFade);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _capTimer?.cancel();
    super.dispose();
  }

  void _handleAuth(AsyncValue<AuthState> value) {
    if (value.isLoading) return;
    // Let the sign-in screen request biometrics from the customer's tap.
    // Browser passkeys can reject prompts launched during background restore.
    _scheduleDismiss();
  }

  void _scheduleDismiss() {
    _sessionReady = true;
    if (!_minimumElapsed || !_visible || _fading) return;
    // Auth may settle during build; schedule the fade after that build.
    _dismissTimer?.cancel();
    _dismissTimer = Timer(Duration.zero, _startFade);
  }

  void _startFade() {
    if (!mounted || !_visible || _fading) return;
    _dismissTimer?.cancel();
    _capTimer?.cancel();
    setState(() {
      _fading = true;
      if (_fadeDuration == Duration.zero) _visible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;

    ref.listen(authControllerProvider, (previous, next) => _handleAuth(next));
    _handleAuth(ref.read(authControllerProvider));

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: _fading,
          child: AnimatedOpacity(
            opacity: _fading ? 0 : 1,
            duration: _fadeDuration,
            curve: Curves.easeOut,
            onEnd: () {
              if (_fading && mounted) setState(() => _visible = false);
            },
            child: context.brandDesign.isConfigured
                ? const _ConfiguredSplashArtwork()
                // The radial glow has transparent pixels. Paint a solid ground
                // beneath it so the session loader cannot show through.
                : const ColoredBox(
                    color: ExampleColors.appBackground,
                    child: DecoratedBox(
                      decoration: exampleBootBackdrop,
                      child: Center(child: ExampleLoader.boot(intro: !kIsWeb)),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Uses the same prepared image and background as the native/web launch view.
class _ConfiguredSplashArtwork extends StatelessWidget {
  const _ConfiguredSplashArtwork();

  @override
  Widget build(BuildContext context) {
    final design = context.brandDesign;
    final theme = Theme.of(context);
    final splashAsset = design.asset('splash');
    final name = BrandAsset.nameOf(context);
    return ColoredBox(
      color: design.splashBackground(
        theme.brightness,
        fallback: theme.scaffoldBackgroundColor,
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandAsset(
                  path: splashAsset.isNotEmpty
                      ? splashAsset
                      : AppDesignTheme.logoOf(context),
                  size: 132,
                  width: 198,
                ),
                const SizedBox(height: 24),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: BrandWordmark(height: 24),
                ),
                const SizedBox(height: 32),
                ExampleLoader(
                    semanticsLabel: context.tr('Loading {p0}', {'p0': name})),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
