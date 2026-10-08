import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

/// Android/iOS implementation: a WebView showing the Transak checkout.
class TransakCheckoutFrame extends StatefulWidget {
  const TransakCheckoutFrame({required this.url, super.key});

  final String url;

  @override
  State<TransakCheckoutFrame> createState() => _TransakCheckoutFrameState();
}

class _TransakCheckoutFrameState extends State<TransakCheckoutFrame> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: AppProgressIndicator()),
        ],
      );
}
