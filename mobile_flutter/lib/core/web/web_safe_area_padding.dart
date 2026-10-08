import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_safe_area.dart';

/// Gives the web build the safe-area insets Flutter never sees.
///
/// The web engine reports a zero view padding on every browser, so on an
/// installed iPhone web app the bottom bar sat under the home indicator and
/// the top of every page under the status bar: `SafeArea` had nothing to
/// avoid. The page measures `env(safe-area-inset-*)` and this widget folds
/// it into the ambient [MediaQuery], so the same `SafeArea` widgets that work
/// in the native app work in the browser too. Native platforms and browsers
/// with no insets are left exactly as they were.
class WebSafeAreaPadding extends StatefulWidget {
  const WebSafeAreaPadding({
    required this.child,
    this.insets = WebSafeArea.insets,
    super.key,
  });

  final Widget child;

  /// Where the insets come from; the page bridge by default, a fixture in
  /// tests.
  final EdgeInsets Function() insets;

  @override
  State<WebSafeAreaPadding> createState() => _WebSafeAreaPaddingState();
}

class _WebSafeAreaPaddingState extends State<WebSafeAreaPadding>
    with WidgetsBindingObserver {
  EdgeInsets _insets = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _insets = widget.insets();
    // The viewport meta is patched to `viewport-fit=cover` as the engine
    // starts; Safari applies it a beat later, so look once more after the
    // first frame has settled.
    if (kIsWeb) {
      Future<void>.delayed(const Duration(milliseconds: 600), _refresh);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _refresh();

  void _refresh() {
    if (!mounted) return;
    final next = widget.insets();
    if (next != _insets) setState(() => _insets = next);
  }

  @override
  Widget build(BuildContext context) {
    if (_insets == EdgeInsets.zero) return widget.child;
    final media = MediaQuery.of(context);
    final viewPadding = EdgeInsets.fromLTRB(
      math.max(media.viewPadding.left, _insets.left),
      math.max(media.viewPadding.top, _insets.top),
      math.max(media.viewPadding.right, _insets.right),
      math.max(media.viewPadding.bottom, _insets.bottom),
    );
    // As the framework derives it from the view: the keyboard, when it is up,
    // already covers the bottom inset, so padding gives way to viewInsets.
    final padding = EdgeInsets.fromLTRB(
      math.max(0, viewPadding.left - media.viewInsets.left),
      math.max(0, viewPadding.top - media.viewInsets.top),
      math.max(0, viewPadding.right - media.viewInsets.right),
      math.max(0, viewPadding.bottom - media.viewInsets.bottom),
    );
    return MediaQuery(
      data: media.copyWith(padding: padding, viewPadding: viewPadding),
      child: widget.child,
    );
  }
}
