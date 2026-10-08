import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../brands/example/example_colors.dart';
import '../branding/app_design.dart';
import 'web_app_update.dart';

/// Slim bar at the top of the web app once a newer build has been installed
/// by the service worker. Reloading applies it; users can also keep working.
class UpdateAvailableBanner extends StatefulWidget {
  const UpdateAvailableBanner({super.key});

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
    if (!kIsWeb || !_ready || _dismissed) {
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
                  color:
                      color('accent', ExampleColors.iris).withValues(alpha: .5)),
              boxShadow: [
                BoxShadow(
                  color: color(
                      'shadowAmbient', Colors.black.withValues(alpha: .35)),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
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
                TextButton(
                  onPressed: WebAppUpdate.reload,
                  child: Text(context.tr('Update now')),
                ),
                IconButton(
                  tooltip: context.tr('Later'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _dismissed = true),
                  icon: Icon(Icons.close,
                      size: 16,
                      color: color('textSecondary',
                          ExampleColors.pearl.withValues(alpha: .6))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
