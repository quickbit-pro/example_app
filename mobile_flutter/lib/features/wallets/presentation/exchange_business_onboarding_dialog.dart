import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/app_states.dart';
import '../../platform/application/platform_providers.dart';
import 'exchange_support.dart';

/// Review saved details before creating a provider-owned corporate KYB application.
class ExchangeBusinessOnboardingDialog extends ConsumerStatefulWidget {
  const ExchangeBusinessOnboardingDialog({super.key});

  @override
  ConsumerState<ExchangeBusinessOnboardingDialog> createState() =>
      _ExchangeBusinessOnboardingDialogState();
}

class _ExchangeBusinessOnboardingDialogState
    extends ConsumerState<ExchangeBusinessOnboardingDialog> {
  Map<String, dynamic>? draft;
  bool busy = false, authorisationRequired = false, codeSent = false;
  String? error;
  final code = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => run(() async {
        final value = await ref
            .read(mobilePlatformApiProvider)
            .getExchangeBusinessApplication();
        if (mounted) setState(() => draft = value);
      });

  Future<void> start() async {
    final result =
        await ref.read(mobilePlatformApiProvider).startExchangeBusiness();
    if (!mounted) return;
    if (result['status'] == 'authorisation_required') {
      setState(() {
        authorisationRequired = true;
        codeSent = false;
        code.clear();
      });
      return;
    }
    ref.invalidate(exchangeVerificationProvider);
    ref.invalidate(exchangeOverviewProvider);
    Navigator.pop(context, result);
  }

  Widget detail(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 3),
            SelectableText(value.isEmpty ? 'Not provided' : value,
                style: theme.textTheme.bodyLarge),
          ],
        )),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final issues =
        (draft?['issues'] as List?)?.map((v) => v.toString()).toList() ?? [];
    final primary = FilledButton(
      onPressed: busy ||
              draft == null ||
              (authorisationRequired
                  ? !codeSent || code.text.length != 6
                  : draft?['readyToSubmit'] != true)
          ? null
          : () => run(() async {
                if (authorisationRequired) {
                  final result = await ref
                      .read(mobilePlatformApiProvider)
                      .authoriseExchangeBusiness(code.text);
                  if (result['authorised'] != true) {
                    throw StateError(
                        'Email authorisation was not confirmed. Check the code and try again.');
                  }
                }
                await start();
              }),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
          authorisationRequired
              ? 'Verify and continue'
              : 'Continue to verification',
          textAlign: TextAlign.center),
    );
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 560),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 16, 18),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.business_center_outlined,
                    color: colors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Business Exchange',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        authorisationRequired
                            ? 'Confirm your email'
                            : 'Review your company details',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant)),
                  ])),
              IconButton(
                  tooltip: 'Close',
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20)),
            ]),
          ),
          Flexible(
              child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (draft != null) ...[
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest
                            .withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: colors.outlineVariant.withValues(alpha: .5)),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('REGISTERED COMPANY',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    letterSpacing: 1.1,
                                    color: colors.onSurfaceVariant)),
                            const SizedBox(height: 6),
                            SelectableText(
                                exchangeText(draft!, 'legalName').isEmpty
                                    ? 'Not provided'
                                    : exchangeText(draft!, 'legalName'),
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(height: 1)),
                            detail(
                                Icons.person_outline_rounded,
                                'Contact person',
                                exchangeText(draft!, 'contactName')),
                            detail(Icons.alternate_email_rounded, 'Email',
                                exchangeText(draft!, 'contactEmail')),
                            detail(Icons.phone_outlined, 'Mobile number',
                                exchangeText(draft!, 'contactPhone')),
                          ]),
                    ),
                    const SizedBox(height: 12),
                    Text(
                        'Prefilled from your saved company and profile details.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant)),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => Navigator.pop(context,
                                  <String, dynamic>{'action': 'support'}),
                          icon:
                              const Icon(Icons.support_agent_rounded, size: 18),
                          label: const Text('Need to update these details?'),
                        )),
                    if (issues.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.errorContainer.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 18, color: colors.onErrorContainer),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text('A detail needs your attention',
                                        style: theme.textTheme.labelLarge)),
                              ]),
                              for (final issue in issues)
                                Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(issue)),
                              TextButton(
                                  onPressed: busy ? null : load,
                                  child: const Text('Refresh details')),
                            ]),
                      ),
                    ] else if (!authorisationRequired) ...[
                      const SizedBox(height: 10),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.open_in_new_rounded,
                                size: 18, color: colors.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(
                                    'Next, complete company verification with BoomFi/ZBX. They may ask for more details or documents.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color: colors.onSurfaceVariant))),
                          ]),
                    ],
                  ],
                  if (authorisationRequired) ...[
                    const SizedBox(height: 16),
                    Text(
                        'An account already uses this email. Confirm it to connect your company to Exchange.',
                        style: theme.textTheme.bodyMedium),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                    await ref
                                        .read(mobilePlatformApiProvider)
                                        .sendExchangeBusinessCode();
                                    if (mounted)
                                      setState(() => codeSent = true);
                                  }),
                          icon:
                              const Icon(Icons.mail_outline_rounded, size: 18),
                          label: Text(codeSent
                              ? 'Resend email code'
                              : 'Send email code'),
                        )),
                    if (codeSent) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: code,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6)
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Email verification code',
                            helperText:
                                'Enter the six-digit code sent to your email.'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(error!,
                                style: TextStyle(color: colors.error)))),
                  if (draft == null && !busy)
                    TextButton(onPressed: load, child: const Text('Retry')),
                ]),
          )),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Divider(
              height: 1, color: colors.outlineVariant.withValues(alpha: .5)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: LayoutBuilder(builder: (context, constraints) {
              final cancel = TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'));
              return constraints.maxWidth < 360
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [primary, const SizedBox(height: 4), cancel])
                  : Row(children: [
                      cancel,
                      const SizedBox(width: 16),
                      Expanded(child: Align(alignment: Alignment.centerRight, child: primary))
                    ]);
            }),
          ),
        ]),
      ),
    );
  }
}
