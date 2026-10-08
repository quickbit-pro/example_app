import 'package:flutter/material.dart';

/// Non-web platforms never build this; the card detail screen uses the
/// WebView there.
class SecureCardFrame extends StatelessWidget {
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
