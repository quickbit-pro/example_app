import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../../app/router/app_router.dart';
import '../../../brands/example/example_colors.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/branding/app_design.dart';
import 'sumsub_kyc_adapter.dart';

@JS('exampleSumsub.launch')
external void _launch(
  web.HTMLElement container,
  JSString accessToken,
  JSFunction refreshToken,
  JSFunction onEvent,
  JSString language,
);

/// Browser flow: a full-screen dialog hosting the Sumsub WebSDK (see the
/// `exampleSumsub` helper in `web/app_bridges.js`). Resolves once the applicant
/// has submitted; closing the dialog before that cancels the flow.
Future<SumsubVerificationResult> launchSumsubWeb({
  required String accessToken,
  required Future<String> Function() onTokenExpiration,
}) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null) {
    throw StateError('The verification dialog cannot open before the app.');
  }
  final completer = Completer<SumsubVerificationResult>();
  var status = 'started';

  void settle(SumsubVerificationResult result) {
    if (!completer.isCompleted) completer.complete(result);
  }

  void fail(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }

  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    useSafeArea: false,
    builder: (dialogContext) => _SumsubWebDialog(
      onLaunch: (container) => _launch(
        container,
        accessToken.toJS,
        (() => onTokenExpiration().then((token) => token.toJS).toJS).toJS,
        ((JSString name, JSString payload) {
          final event = name.toDart;
          Map<String, dynamic> data = const {};
          try {
            final decoded = jsonDecode(payload.toDart);
            if (decoded is Map<String, dynamic>) data = decoded;
          } catch (_) {}
          switch (event) {
            case 'status':
              status =
                  (data['reviewStatus'] ?? data['status'] ?? status).toString();
            case 'submitted':
              status = 'submitted';
              settle(
                const SumsubVerificationResult(
                  success: true,
                  status: 'submitted',
                ),
              );
              Future<void>.delayed(const Duration(milliseconds: 900), () {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });
            case 'error':
              final code = (data['code'] ?? '').toString();
              final origin = web.window.location.origin;
              fail(
                StateError(
                  switch (code) {
                    'invalid-origin' =>
                      'Verification is not enabled for $origin. Add this '
                          'domain under "Domains to host WebSDK" in the Sumsub '
                          'dashboard (Dev space → WebSDK settings).',
                    'invalid-token' =>
                      'The verification session expired. Please try again.',
                    'camera-error' =>
                      'Camera access is required. Allow the camera for this site and try again.',
                    _ => 'Verification could not start: '
                        '${data['message'] ?? code.isNotEmpty ? code : 'unknown error'}',
                  },
                ),
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          }
        }).toJS,
        Localizations.localeOf(dialogContext).languageCode.toJS,
      ),
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
  );
  unawaited(dialog.then((_) {
    fail(StateError('Verification was closed before it was submitted.'));
  }));
  return completer.future;
}

class _SumsubWebDialog extends StatefulWidget {
  const _SumsubWebDialog({required this.onLaunch, required this.onClose});

  final void Function(web.HTMLElement container) onLaunch;
  final VoidCallback onClose;

  @override
  State<_SumsubWebDialog> createState() => _SumsubWebDialogState();
}

class _SumsubWebDialogState extends State<_SumsubWebDialog> {
  static int _instances = 0;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'example-sumsub-${_instances++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container = web.HTMLDivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'auto'
        ..style.background = 'var(--brand-background, transparent)';
      widget.onLaunch(container);
      return container;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    return Dialog.fullscreen(
      backgroundColor: isExample
          ? context.brandDesign.color(Theme.of(context).brightness, 'paper',
              fallback: ExampleColors.night)
          : null,
      child: Scaffold(
        backgroundColor: isExample
            ? context.brandDesign.color(Theme.of(context).brightness, 'paper',
                fallback: ExampleColors.night)
            : null,
        appBar: AppBar(
          title: Text(context.tr('Identity verification')),
          leading: IconButton(
            tooltip: context.tr('Close'),
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: HtmlElementView(viewType: _viewType),
          ),
        ),
      ),
    );
  }
}
