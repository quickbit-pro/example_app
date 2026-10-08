import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Browser implementation: an `<iframe>` pointing at the issuer's secure
/// widget page. Ready is reported when the frame's own `load` event has
/// fired (the document and its images are in) plus a short settle time for
/// data the page fetches afterwards, so the flip never lands on a blank
/// page. A `card-secure-widget-status` message from providers that post one
/// resolves it earlier; a long fallback timer covers everything else.
class SecureCardFrame extends StatefulWidget {
  const SecureCardFrame({
    required this.url,
    required this.onReady,
    required this.onError,
    required this.onRefresh,
    super.key,
  });

  final String url;
  final VoidCallback onReady;
  final ValueChanged<String> onError;
  final VoidCallback onRefresh;

  @override
  State<SecureCardFrame> createState() => _SecureCardFrameState();
}

class _SecureCardFrameState extends State<SecureCardFrame> {
  static int _instances = 0;
  static const _settleAfterLoad = Duration(milliseconds: 300);
  static const _fallback = Duration(seconds: 7);
  late final String _viewType;
  Timer? _readyTimer;
  bool _settled = false;
  bool _failed = false;
  bool _loaded = false;
  JSFunction? _listener;
  JSFunction? _loadListener;
  web.HTMLIFrameElement? _frame;

  void _ready() {
    if (_settled || _failed || !mounted) return;
    _settled = true;
    _readyTimer?.cancel();
    widget.onReady();
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'example-secure-card-${_instances++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = web.HTMLIFrameElement()
        ..src = widget.url
        ..allow = 'clipboard-write'
        ..scrolling = 'no'
        ..style.border = '0'
        ..style.margin = '0'
        ..style.padding = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden'
        ..style.background = 'transparent'
        ..style.colorScheme = 'dark';
      frame.setAttribute('title', 'Secure card details');
      frame.setAttribute('allowtransparency', 'true');
      frame.setAttribute('frameborder', '0');
      _loadListener = ((web.Event event) {
        if (_failed || !mounted) return;
        if (_loaded) {
          _failed = true;
          _readyTimer?.cancel();
          widget.onRefresh();
          return;
        }
        _loaded = true;
        // Document and images are in; give the page a moment to fetch and
        // draw the card data before the front face flips away.
        _readyTimer?.cancel();
        _readyTimer = Timer(_settleAfterLoad, _ready);
      }).toJS;
      frame.addEventListener('load', _loadListener);
      _frame = frame;
      return frame;
    });
    _listener = ((web.MessageEvent event) {
      final data = event.data;
      if (data == null ||
          _failed ||
          !mounted ||
          event.source != _frame?.contentWindow ||
          event.origin != Uri.parse(widget.url).origin) {
        return;
      }
      final payload = data.dartify();
      if (payload is! Map) return;
      if (payload['type'] != 'card-secure-widget-status') return;
      if (payload['status'] == 'success') {
        _ready();
      } else if (payload['status'] == 'error') {
        _failed = true;
        _readyTimer?.cancel();
        widget.onError(
          (payload['message'] ?? 'Secure card data could not be loaded.')
              .toString(),
        );
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
    _readyTimer = Timer(_fallback, _ready);
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    if (_listener != null) {
      web.window.removeEventListener('message', _listener);
    }
    if (_frame != null && _loadListener != null) {
      _frame!.removeEventListener('load', _loadListener);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
