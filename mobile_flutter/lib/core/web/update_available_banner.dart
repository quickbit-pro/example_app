import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../brands/example/example_colors.dart';
import '../branding/app_design.dart';
import 'web_app_update.dart';
import '../widgets/app_version_header.dart';

/// Slim bar at the top of the web app once a newer build has been installed
/// by the service worker. Reloading applies it; users can also keep working.
class UpdateAvailableBanner extends StatefulWidget {
  const UpdateAvailableBanner({super.key, this.readyOverride, this.onReload});
  final bool? readyOverride;
  final VoidCallback? onReload;

  @override
  State<UpdateAvailableBanner> createState() => _UpdateAvailableBannerState();
}

class _UpdateAvailableBannerState extends State<UpdateAvailableBanner> {
  bool _ready = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WebAppUpdate.onChange((ready) {
        if (mounted && ready != _ready) {
          setState(() => _ready = ready);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if ((widget.readyOverride == null && !kIsWeb) ||
        !(widget.readyOverride ?? _ready) ||
        _dismissed) {
      return const SizedBox.shrink();
    }
    final brightness = Theme.of(context).brightness;
    Color color(String key, Color fallback) =>
        context.brandDesign.color(brightness, key, fallback: fallback);
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            decoration: BoxDecoration(
              color: color('navigation', ExampleColors.navigationSurface),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: color('accent', ExampleColors.iris)
                      .withValues(alpha: .5)),
              boxShadow: [
                BoxShadow(
                  color: color(
                      'shadowAmbient', Colors.black.withValues(alpha: .35)),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600 ||
                  MediaQuery.textScalerOf(context).scale(13) > 20;
              final message = Row(children: [
                Icon(Icons.system_update_alt_rounded,
                    size: 18, color: color('accent', ExampleColors.iris)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('A new version of the app is ready.'),
                    style: TextStyle(
                      color: color('ink', ExampleColors.pearl),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]);
              final actions = Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: widget.onReload ?? WebAppUpdate.reload,
                      child: Text(context.tr('Update now')),
                    ),
                    IconButton(
                      key: const Key('dismiss-app-update'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _dismissed = true),
                      icon: Icon(Icons.close,
                          size: 16,
                          color: color('textSecondary',
                              ExampleColors.pearl.withValues(alpha: .6))),
                    ),
                  ]);
              return narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [message, actions])
                  : Row(children: [Expanded(child: message), actions]);
            }),
          ),
        ),
      ),
    );
  }
}

/// Give update actions their own space, above the always-visible build badge.
class AppUpdateFrame extends StatelessWidget {
  const AppUpdateFrame(
      {required this.child, super.key, this.readyOverride, this.onReload});
  final Widget child;
  final bool? readyOverride;
  final VoidCallback? onReload;
  @override
  Widget build(BuildContext context) => Column(children: [
        UpdateAvailableBanner(readyOverride: readyOverride, onReload: onReload),
        Expanded(child: AppVersionFrame(child: child)),
      ]);
}
