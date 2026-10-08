import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../routes.dart';

/// Retains page history for shell destinations reached with GoRouter.go.
/// Dialogs and pushed pages still use the navigator's normal pop handling.
class AppBackNavigation extends StatefulWidget {
  const AppBackNavigation({required this.child, super.key});

  final Widget child;

  @override
  State<AppBackNavigation> createState() => _AppBackNavigationState();
}

class _AppBackNavigationState extends State<AppBackNavigation> {
  GoRouter? _router;
  final List<Uri> _history = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (identical(router, _router)) return;
    _router?.routerDelegate.removeListener(_recordLocation);
    _router = router;
    _history.clear();
    router.routerDelegate.addListener(_recordLocation);
    _recordLocation();
  }

  void _recordLocation() {
    final location = _router!.routerDelegate.state.uri;
    if (_history.isNotEmpty && _history.last == location) return;
    final previous = _history.indexOf(location);
    if (previous >= 0) {
      _history.removeRange(previous + 1, _history.length);
    } else {
      // A nested route opened directly can pop to a parent never visited yet.
      if (_history.isNotEmpty &&
          _history.last.path.startsWith('${location.path}/')) {
        _history.removeLast();
      }
      _history.add(location);
    }
    setState(() {});
  }

  bool get _canHandlePageBack =>
      _history.length > 1 ||
      _router!.routerDelegate.state.uri.path != AppRoutes.home;

  void _goBackThroughHistory() {
    final router = _router!;
    if (_history.length > 1) {
      _history.removeLast();
      router.go(_history.last.toString());
      return;
    }
    final path = router.routerDelegate.state.uri.path;
    if (path == AppRoutes.home) return;
    // A deep link has no in-app predecessor. Return to its owning section.
    final parent = path.startsWith('${AppRoutes.money}/')
        ? AppRoutes.money
        : path.startsWith('${AppRoutes.cards}/')
            ? AppRoutes.cards
            : AppRoutes.home;
    _history.clear();
    router.go(parent);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_recordLocation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
        // The shell is one root route even when go() has visited many pages.
        // PopScope advertises this extra history to Android's predictive-back
        // dispatcher; BackButtonListener alone leaves canHandlePop false and
        // Android may finish the activity without sending a back event.
        canPop: !_canHandlePageBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goBackThroughHistory();
        },
        // GoRouter first pops dialogs / the deepest navigator, respecting its
        // own PopScopes. Only an exhausted shell reaches the callback above.
        child: NotificationListener<NavigationNotification>(
          onNotification: (notification) {
            // A one-page nested navigator reports false independently of the
            // root PopScope. Include shell history so that later notification
            // cannot switch Android's back handling off again.
            if (!notification.canHandlePop && _canHandlePageBack) {
              const NavigationNotification(canHandlePop: true)
                  .dispatch(context);
              return true;
            }
            return false;
          },
          child: widget.child,
        ),
      );
}
