import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../data/dashboard_providers.dart';

/// Refreshes Home when navigation reveals it, including pushed-page pops and
/// the shell's Android/browser back navigation.
class HomeRefreshOnNavigation extends ConsumerStatefulWidget {
  const HomeRefreshOnNavigation({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HomeRefreshOnNavigation> createState() =>
      _HomeRefreshOnNavigationState();
}

class _HomeRefreshOnNavigationState
    extends ConsumerState<HomeRefreshOnNavigation> with WidgetsBindingObserver {
  GoRouter? _router;
  bool _homeVisible = false;
  int _navigation = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      ++_navigation; // Cancel a refresh queued before the PWA was hidden.
    } else if (state == AppLifecycleState.resumed && !_foreground) {
      _foreground = true;
      if (_homeVisible) _scheduleRefresh();
    }
    // Focus changes (inactive) alone, such as a system prompt, do not refetch.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (identical(router, _router)) return;
    _router?.routerDelegate.removeListener(_onNavigation);
    _router = router;
    _homeVisible = false;
    router.routerDelegate.addListener(_onNavigation);
    _onNavigation();
  }

  void _onNavigation() {
    final visible = _router!.routerDelegate.state.uri.path == AppRoutes.home;
    if (visible == _homeVisible) return;
    _homeVisible = visible;
    ++_navigation;
    if (!visible) return;
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    if (!_foreground) return;
    final navigation = ++_navigation;
    // Navigation may notify while Flutter is building the destination. Wait
    // until that frame finishes before invalidating watched providers.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          !_foreground ||
          !_homeVisible ||
          navigation != _navigation) {
        return;
      }
      try {
        await ref.read(refreshHoppaDashboardProvider)();
      } catch (_) {
        // The dashboard provider exposes the request error and retry UI.
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router?.routerDelegate.removeListener(_onNavigation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
