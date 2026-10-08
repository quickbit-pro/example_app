import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../application/kyc_providers.dart';

final verificationLinkLauncherProvider =
    Provider<Future<bool> Function(Uri)>((ref) {
  // The link arrives after an HTTP request, when browser popup permission may
  // have expired. Reuse the browser tab; the native launcher ignores this flag.
  return (uri) => launchUrl(uri,
      mode: LaunchMode.externalApplication, webOnlyWindowName: '_self');
});

/// Reopens the existing hosted Sumsub flow for the requested verification steps.
class KycResubmissionPanel extends ConsumerStatefulWidget {
  const KycResubmissionPanel({required this.status, super.key});
  final KycDetailedStatus status;

  @override
  ConsumerState<KycResubmissionPanel> createState() =>
      _KycResubmissionPanelState();
}

class _KycResubmissionPanelState extends ConsumerState<KycResubmissionPanel>
    with WidgetsBindingObserver {
  bool _busy = false;
  Uri? _link;
  String? _error;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(kycDetailedStatusProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(onboardingProvider);
    }
  }

  Future<void> _resume() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = _link ?? await ref.read(kycApiProvider).resumeVerification();
      if (!mounted) return;
      _link = link;
      final opened = await ref.read(verificationLinkLauncherProvider)(link);
      if (!mounted) return;
      setState(() {
        _opened = opened;
        if (!opened) {
          _error = context.tr('Use Open verification to open the secure link.');
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResume = widget.status.requiresDocumentResubmission;
    final label = _busy
        ? context.tr('Opening verification…')
        : _link != null
            ? context.tr('Open verification')
            : context.tr('Reopen verification');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(context.tr('Action required'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(canResume
              ? context.tr(
                  'Reopen the secure Sumsub page to complete the requested verification steps.')
              : context.tr('Contact support for help with your verification.')),
          if (widget.status.interlaceReason?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(widget.status.interlaceReason!),
          ],
          if (canResume &&
              widget.status.interlaceResubmissionDocSets.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final document in widget.status.interlaceResubmissionDocSets)
              Text('• ${_documentLabel(context, document)}'),
          ],
          if (_opened) ...[
            const SizedBox(height: 12),
            Text(context.tr(
                'Complete verification in the secure page, then return here and check your status.')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
          const SizedBox(height: 16),
          if (canResume)
            context.isExampleTheme
                ? ExampleGlassButton(
                    label: label, onPressed: _busy ? null : _resume)
                : FilledButton(
                    onPressed: _busy ? null : _resume, child: Text(label))
          else
            FilledButton(
                onPressed: () => context.go('/support'),
                child: Text(context.tr('Contact support'))),
          TextButton(
              onPressed: () {
                ref.invalidate(dashboardProvider);
                ref.invalidate(onboardingProvider);
                ref.invalidate(kycDetailedStatusProvider);
              },
              child: Text(context.tr('Check status'))),
        ]),
      ),
    );
  }
}

String _documentLabel(BuildContext context, String value) =>
    context.tr(switch (value.toUpperCase()) {
      'IDENTITY' => 'Identity document',
      'SELFIE' => 'Selfie',
      'PROOF_OF_RESIDENCE' => 'Proof of address',
      'APPLICANT_DATA' => 'Personal information',
      _ => friendlyStatus(value),
    });
