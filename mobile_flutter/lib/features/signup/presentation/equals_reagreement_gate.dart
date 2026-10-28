import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/auth_token_provider.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import 'legal_agreements.dart';

class EqualsAgreementStatus {
  const EqualsAgreementStatus(
      {required this.requiresAcceptance,
      required this.available,
      required this.version,
      required this.termsUrl,
      required this.privacyUrl});

  factory EqualsAgreementStatus.fromJson(Map<String, dynamic> json) {
    final documents = json['documents'] as Map<String, dynamic>;
    return EqualsAgreementStatus(
      requiresAcceptance: json['requiresAcceptance'] as bool,
      available: documents['available'] as bool,
      version: documents['version'] as String,
      termsUrl: documents['termsUrl'] as String,
      privacyUrl: documents['privacyUrl'] as String,
    );
  }
  final bool requiresAcceptance;
  final bool available;
  final String version;
  final String termsUrl;
  final String privacyUrl;
}

final equalsAgreementStatusProvider =
    FutureProvider.autoDispose<EqualsAgreementStatus>((ref) async {
  ref.watch(equalsConsentRevisionProvider);
  final response = await ref
      .watch(dioProvider)
      .get<Map<String, dynamic>>('/api/v1/mobile/agreements/equals/status');
  return EqualsAgreementStatus.fromJson(response.data!);
});

/// Preserves the existing navigator while preventing access until the server
/// confirms the current session has accepted both agreements.
class EqualsReagreementGate extends ConsumerStatefulWidget {
  const EqualsReagreementGate({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<EqualsReagreementGate> createState() =>
      _EqualsReagreementGateState();
}

class _EqualsReagreementGateState extends ConsumerState<EqualsReagreementGate>
    with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.resumed &&
        ref.read(authControllerProvider).valueOrNull?.isAuthenticated == true) {
      ref.invalidate(equalsAgreementStatusProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth?.isAuthenticated != true || auth?.biometricLocked == true) {
      return widget.child;
    }
    final status = ref.watch(equalsAgreementStatusProvider);
    final generation = ref.watch(authSessionGenerationProvider);
    final blocked = status.isReloading ||
        status.hasError ||
        status.valueOrNull?.requiresAcceptance != false;
    return Stack(fit: StackFit.expand, children: [
      Offstage(offstage: blocked, child: widget.child),
      if (blocked)
        Positioned.fill(
            // MaterialApp.builder places this gate above the app navigator.
            // Give the blocking surface its own navigator for document dialogs.
            child: HeroControllerScope.none(child: Navigator(
              pages: [MaterialPage<void>(child: Scaffold(
                body: SafeArea(
                    child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(context.tr('Review Equals Money agreements'),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                status.when(
                  data: (value) => EqualsAgreementReview(
                      key: ValueKey('$generation:${value.version}'),
                      status: value),
                  loading: () => const CircularProgressIndicator(),
                  error: (error, stack) => Column(children: [
                    Text(context.tr(
                        'We could not check your agreements. Please try again.')),
                    TextButton(
                        onPressed: () =>
                            ref.invalidate(equalsAgreementStatusProvider),
                        child: Text(context.tr('Try again'))),
                  ]),
                ),
                const SizedBox(height: 16),
                TextButton(
                    onPressed: () => launchUrl(Uri(
                        scheme: 'mailto',
                        path:
                            ref.read(appConfigProvider).branding.supportEmail)),
                    child: Text(context.tr('Contact support'))),
                if (status.valueOrNull case final current?)
                  TextButton(
                      onPressed: () => launchUrl(
                          Uri.parse(current.privacyUrl.contains('/en-be/')
                              ? 'https://equalsmoney.com/en-be/complaints'
                              : 'https://equalsmoney.com/complaints'),
                          mode: LaunchMode.externalApplication),
                      child: Text(context.tr('Contact Equals Money'))),
                TextButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                    child: Text(context.tr('Sign out'))),
              ]),
            ),
          ),
        ))))],
              onDidRemovePage: (_) {},
            ))),
    ]);
  }
}

class EqualsAgreementReview extends ConsumerStatefulWidget {
  const EqualsAgreementReview({required this.status, super.key});
  final EqualsAgreementStatus status;

  @override
  ConsumerState<EqualsAgreementReview> createState() =>
      _EqualsAgreementReviewState();
}

class _EqualsAgreementReviewState extends ConsumerState<EqualsAgreementReview> {
  final _accepted = <LegalAgreementKey>{};
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final status = widget.status;
    try {
      await ref
          .read(dioProvider)
          .post<void>('/api/v1/mobile/agreements/equals/accept', data: {
        'version': status.version, 'termsUrl': status.termsUrl,
        'privacyUrl': status.privacyUrl,
        'termsAccepted': _accepted.contains(LegalAgreementKey.equalsTerms),
        'privacyAccepted': _accepted.contains(LegalAgreementKey.equalsPrivacy),
        // Both shared rows require review to the bottom before separate acceptance.
        'termsAccessed': _accepted.contains(LegalAgreementKey.equalsTerms),
      });
      if (mounted) ref.invalidate(equalsAgreementStatusProvider);
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 409) {
        _accepted.clear();
        ref.invalidate(equalsAgreementStatusProvider);
        _error =
            'The documents changed. Review the current documents before continuing.';
      } else {
        _error = 'Acceptance could not be saved. Please try again.';
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    if (!status.available) {
      return Column(children: [
        Text(context.tr(
            'Equals Money terms are currently unavailable. Please contact support before continuing.')),
        TextButton(
            onPressed: () => ref.invalidate(equalsAgreementStatusProvider),
            child: Text(context.tr('Try again'))),
      ]);
    }
    final specs = [
      LegalAgreementSpec(
          key: LegalAgreementKey.equalsTerms,
          title: 'I accept the Equals Money Terms and Conditions',
          lead: 'Review the ',
          links: [
            LegalDocumentLink(
                'Equals Money Terms and Conditions', status.termsUrl)
          ],
          trail: '.'),
      LegalAgreementSpec(
          key: LegalAgreementKey.equalsPrivacy,
          title: 'I confirm I have read and agree to the Equals Privacy Policy',
          lead: 'Review the ',
          links: [
            LegalDocumentLink('Equals Privacy Policy', status.privacyUrl)
          ],
          trail: '.'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AbsorbPointer(
          absorbing: _saving,
          child: LegalAgreementsSection(
            specs: specs,
            accepted: _accepted,
            onChanged: (key, accepted) => setState(() {
              if (accepted) {
                _accepted.add(key);
              } else {
                _accepted.remove(key);
              }
            }),
          )),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(context.tr(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 20),
      FilledButton(
          onPressed: _saving || !allLegalAgreementsAccepted(specs, _accepted)
              ? null
              : _save,
          child: Text(context
              .tr(_saving ? 'Saving acceptance...' : 'Accept and Continue'))),
    ]);
  }
}
