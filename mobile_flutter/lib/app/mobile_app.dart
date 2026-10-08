import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/app_localization_delegates.dart';
import '../core/l10n/locale_preference_provider.dart';

import '../brands/example/example_colors.dart';
import '../brands/example/example_startup_splash.dart';
import '../core/web/update_available_banner.dart';
import '../core/web/web_safe_area_padding.dart';
import '../core/api/dio_provider.dart';
import '../core/privacy/private_mode_provider.dart';
import '../core/theme/app_theme_provider.dart';
import '../core/theme/theme_preference_provider.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/notifications/notifications.dart';
import 'router/app_router.dart';

class MobileApp extends ConsumerStatefulWidget {
  const MobileApp({super.key});

  @override
  ConsumerState<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends ConsumerState<MobileApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final router = ref.watch(routerProvider);
    final themes = ref.watch(appThemesProvider);
    // User preference (Light/Dark/System) overrides the tenant default when
    // set. Falls back to tenant default while loading or when null.
    final overrideAsync = ref.watch(themePreferenceProvider);
    final preferred = overrideAsync.maybeWhen(
      data: (override) => override,
      orElse: () => null,
    );
    // Example now ships both themes as first-class. Resolution order, highest
    // first: the debug `?theme=` URL flag, the preference the customer set in
    // Settings → Appearance, the tenant's APP_THEME_MODE, then the device.
    //
    // `themes.mode` already decodes APP_THEME_MODE and defaults it to dark,
    // so the tenant default is honoured before the system setting rather than
    // instead of it; a tenant that wants the device to decide ships
    // APP_THEME_MODE=system.
    //
    // Other brands keep exactly the behaviour they had: preference, else
    // tenant default.
    final debugMode = ref.watch(debugThemeModeOverrideProvider);
    // `preferred` is null for the first frame or two while SharedPreferences
    // answers. `bootThemeModeProvider` carries the same key as main() read it
    // off disk before runApp, and stands in only for that window — the moment
    // the notifier has a value, that value wins, so this can never go stale.
    // The result: Example's first painted frame is already the final theme
    // instead of a Twilight flash under the splash.
    final bootMode = ref.watch(bootThemeModeProvider);
    final stored = overrideAsync.hasValue ? overrideAsync.value : bootMode;
    final mode = config.branding.isExample
        ? (debugMode ?? stored ?? themes.mode)
        : (preferred ?? themes.mode);
    // Private Mode: re-key the navigator so every visible amount re-renders
    // through Money.formatAmount with the new mask state.
    final privateMode = ref.watch(privateModeProvider).valueOrNull ?? false;
    final notifications = ref.watch(pushNotificationServiceProvider);
    notifications
      ..onOpenRoute = router.go
      ..onForegroundMessage = (message) {
        final title = message.notification?.title ?? 'Account update';
        final body = message.notification?.body ?? '';
        final route = message.data['route'];
        _messengerKey.currentState
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(body.isEmpty ? title : '$title\n$body'),
              action: route == null
                  ? null
                  : SnackBarAction(
                      label: context.tr('View'),
                      onPressed: () => notifications.openRoute(route),
                    ),
            ),
          );
      };

    ref.listen(authControllerProvider, (previous, next) {
      final wasAuthenticated = previous?.valueOrNull?.isAuthenticated ?? false;
      final isAuthenticated = next.valueOrNull?.isAuthenticated ?? false;
      if (!wasAuthenticated && isAuthenticated) {
        notifications.activate();
      } else if (wasAuthenticated && !isAuthenticated) {
        notifications.deactivate();
      }
    });

    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      title: config.branding.appName,
      locale: ref.watch(localePreferenceProvider),
      supportedLocales: appLanguages.map((language) => language.locale),
      localizationsDelegates: appLocalizationsDelegates,
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: mode,
      routerConfig: router,
      builder: (context, child) {
        final content = KeyedSubtree(
          key: ValueKey('private-mode-$privateMode'),
          // Both routed pages and the update overlay need the browser's
          // status-bar/notch insets on installed iPhone web apps.
          child: WebSafeAreaPadding(
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: UpdateAvailableBanner(),
                ),
              ],
            ),
          ),
        );
        final splash =
            config.branding.isExample || config.branding.design.isConfigured
                ? ExampleStartupSplash(child: content)
                : content;
        if (!config.branding.isExample) return splash;
        final dark = Theme.of(context).brightness == Brightness.dark;
        // Pages without an AppBar still need chrome that follows the palette.
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: ExamplePalette.of(context).navigation,
          ),
          // Brand splash over the cold start while the session is restored.
          child: splash,
        );
      },
    );
  }
}
