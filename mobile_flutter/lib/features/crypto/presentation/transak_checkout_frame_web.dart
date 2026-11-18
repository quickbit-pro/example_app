import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:web/web.dart' as web;

/// Browser implementation: an `<iframe>` pointing at the Transak checkout
/// URL. Camera and payment permissions are delegated so Transak's own KYC
/// and card steps work inside the frame.
class TransakCheckoutFrame extends StatefulWidget {
  const TransakCheckoutFrame({required this.url, super.key});

  final String url;

  @override
  State<TransakCheckoutFrame> createState() => _TransakCheckoutFrameState();
}

class _TransakCheckoutFrameState extends State<TransakCheckoutFrame> {
  static int _instances = 0;
  late final String _viewType;
  web.HTMLIFrameElement? _frame;

  late String _frameTitle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frameTitle = context.tr('Transak checkout');
    _frame?.setAttribute('title', _frameTitle);
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'example-transak-${_instances++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = web.HTMLIFrameElement()
        ..src = widget.url
        ..allow =
            'camera *; microphone *; payment *; clipboard-write; accelerometer; gyroscope'
        ..style.border = '0'
        ..style.margin = '0'
        ..style.padding = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.background = 'transparent';
      frame.setAttribute('title', _frameTitle);
      frame.setAttribute('frameborder', '0');
      frame.setAttribute('allowfullscreen', 'true');
      _frame = frame;
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
