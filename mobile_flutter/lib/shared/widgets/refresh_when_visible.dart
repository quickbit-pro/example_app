import 'dart:async';

import 'package:flutter/material.dart';

/// Refreshes a visible page or dialog on entry, return, and app resume. Incoming
/// activity is discovered without polling pages hidden behind another route.
class RefreshWhenVisible extends StatefulWidget {
  const RefreshWhenVisible(
      {required this.onRefresh, required this.child, super.key});
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<RefreshWhenVisible> createState() => _RefreshWhenVisibleState();
}

class _RefreshWhenVisibleState extends State<RefreshWhenVisible>
    with WidgetsBindingObserver {
  ModalRoute<dynamic>? _route;
  Timer? _timer;
  bool _visible = false;
  bool _refreshing = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _syncVisibility();
  }

  void _syncVisibility() {
    final visible = _foreground && (_route?.isCurrent ?? true);
    if (visible == _visible) return;
    _visible = visible;
    _timer?.cancel();
    if (!visible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || !_visible || !(_route?.isCurrent ?? true) || _refreshing) {
      return;
    }
    _refreshing = true;
    try {
      await widget.onRefresh();
    } catch (_) {
      // The data provider owns the visible error and retry state.
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncVisibility();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
