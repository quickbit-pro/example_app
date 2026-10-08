import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/shell/banking_shell.dart';
import '../brands/example/example_startup_splash.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_states.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/cards/presentation/cards_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import 'preview_bridge.dart';
import 'preview_configuration.dart';
import 'preview_fixtures.dart';

class CustomerPreviewHost extends StatefulWidget {
  const CustomerPreviewHost({super.key});

  @override
  State<CustomerPreviewHost> createState() => _CustomerPreviewHostState();
}

class _CustomerPreviewHostState extends State<CustomerPreviewHost> {
  late final void Function() _unsubscribe;
  CustomerPreviewConfiguration? _configuration;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _unsubscribe = listenForPreviewMessages(_apply);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sendPreviewMessage({'type': 'customer-preview-ready'});
    });
  }

  Future<void> _apply(Map<String, dynamic> message) async {
    final revision = ++_revision;
    try {
      final configuration = await CustomerPreviewConfiguration.fromMessage(
        message,
        revision: revision,
      );
      if (!mounted || revision != _revision) return;
      setState(() => _configuration = configuration);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        sendPreviewMessage({
          'type': 'customer-preview-applied',
          'appName': configuration.branding.appName,
          'theme': configuration.brightness.name,
          'screen': configuration.screen,
        });
      });
    } catch (error) {
      if (!mounted || revision != _revision) return;
      sendPreviewMessage({
        'type': 'customer-preview-error',
        'message': 'Could not apply this brand: $error',
      });
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configuration = _configuration;
    if (configuration == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            body: Center(child: Text(context.tr('Preparing app preview…')))),
      );
    }
    return CustomerPreviewApp(
      configuration: configuration,
    );
  }
}

/// Renders the shipping screens and navigation shell. Only providers, the
/// router's allowed destinations, and asset loading are preview-specific.
class CustomerPreviewApp extends StatefulWidget {
  const CustomerPreviewApp({required this.configuration, super.key});

  final CustomerPreviewConfiguration configuration;

  @override
  State<CustomerPreviewApp> createState() => _CustomerPreviewAppState();
}

class _CustomerPreviewAppState extends State<CustomerPreviewApp> {
  late AppThemes _themes = buildAppThemes(widget.configuration.branding);
  late final GoRouter _router = GoRouter(
    initialLocation: '/${widget.configuration.screen}',
    overridePlatformDefaultLocation: true,
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/splash',
          builder: (_, __) => const ExampleStartupSplash(
                child: LoginScreen(),
              )),
      GoRoute(
          path: '/loader',
          builder: (_, __) => const Scaffold(
                body:
                    Center(child: LoadingState(label: 'Loading your account')),
              )),
      ShellRoute(
        builder: (_, __, child) => BankingShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/cards', builder: (_, __) => const CardsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
    onException: (context, state, router) {
      // The guide previews presentation; it never navigates into signup,
      // payment, KYC, camera, or external-link flows.
      sendPreviewMessage({
        'type': 'customer-preview-notice',
        'message':
            'This action is disabled in the styling preview. Use the screen selector.',
      });
      router.go('/${widget.configuration.screen}');
    },
  );

  @override
  void didUpdateWidget(covariant CustomerPreviewApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _themes = buildAppThemes(widget.configuration.branding);
    // Editing branding must preserve the navigator, input state and focus.
    // Only an explicit screen selection changes the current preview route.
    if (oldWidget.configuration.screen != widget.configuration.screen) {
      _router.go('/${widget.configuration.screen}');
    }
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
        overrides: customerPreviewOverrides(widget.configuration.branding),
        child: DefaultAssetBundle(
          bundle: widget.configuration.bundle,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: context.tr('{p0} styling preview',
                {'p0': widget.configuration.branding.appName}),
            theme: _themes.light,
            darkTheme: _themes.dark,
            themeMode: widget.configuration.brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            routerConfig: _router,
          ),
        ),
      );
}
