import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../brands/example/example.dart';
import '../data/web_install_prompt.dart';
import 'example_auth_field.dart' show exampleControlEdge;

/// "Install EXAMPLE" banner for the web build. Appears only when the browser
/// reports the app is installable (Chrome/Edge `beforeinstallprompt`) and
/// the page is not already running as an installed app. Dismissal lasts for
/// the session.
class InstallAppBanner extends StatefulWidget {
  const InstallAppBanner({super.key, required this.appName});

  final String appName;

  @override
  State<InstallAppBanner> createState() => _InstallAppBannerState();
}

class _InstallAppBannerState extends State<InstallAppBanner> {
  static bool _dismissedThisSession = false;
  bool _available = false;
  bool _busy = false;
  // Chrome fires beforeinstallprompt only when it feels like it (and Safari
  // never does); after a short wait we offer manual instructions instead.
  bool _fallback = false;
  Timer? _fallbackTimer;
  late final String _platform = kIsWeb ? WebInstallPrompt.platform() : 'other';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WebInstallPrompt.onChange((available) {
        if (mounted && available != _available) {
          setState(() => _available = available);
        }
      });
      if (!WebInstallPrompt.installed() && _platform != 'other') {
        _fallbackTimer = Timer(const Duration(seconds: 4), () {
          if (mounted && !_available) setState(() => _fallback = true);
        });
      }
    }
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _showManualSteps() {
    final steps = _platform == 'ios'
        ? const [
            'Open this page in Safari.',
            'Tap the Share button (the square with an arrow).',
            'Choose "Add to Home Screen", then "Add".',
          ]
        : const [
            'Tap the browser menu (⋮) in the top-right corner.',
            'Choose "Add to Home screen" (or "Install app").',
            'Confirm with "Install" or "Add".',
          ];
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Install {p0}', {'p0': widget.appName})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${i + 1}. ${steps[i]}'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('Got it')),
          ),
        ],
      ),
    );
  }

  Future<void> _install() async {
    setState(() => _busy = true);
    final outcome = await WebInstallPrompt.prompt();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (outcome == 'accepted') _available = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _dismissedThisSession || (!_available && !_fallback)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    // Frosted rather than matte: this is the one panel on the screen that
    // sits directly over the atmosphere, so it has real light to blur.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: ExampleGlassPanel(
        material: ExampleGlassMaterial.frosted,
        radius: AppRadii.sm,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: ExampleSurface.of(context, 2),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadii.xs),
                    ),
                    border: ExampleBorders.subtleOf(context),
                  ),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Icon(
                      Icons.install_mobile_rounded,
                      color: ExamplePalette.of(context).accent,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('Install {p0}', {'p0': widget.appName}),
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('Full-screen access and biometric sign-in.'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ExampleInk.secondary(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: context.tr('Not now'),
                  onPressed: () => setState(() => _dismissedThisSession = true),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: ExampleInk.secondary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // One clear action, outlined: the primary CTA on this screen is
            // Sign in and nothing here may compete with it.
            SizedBox(
              height: 44,
              child: ExamplePressable(
                child: OutlinedButton(
                  onPressed:
                      _busy ? null : (_available ? _install : _showManualSteps),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ExampleInk.primary(context),
                    side: exampleControlEdge(context),
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadii.xs)),
                    ),
                    textStyle: theme.textTheme.labelLarge,
                  ),
                  child: Text(
                    _available
                        ? context.tr('Install')
                        : context.tr('How to install'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
