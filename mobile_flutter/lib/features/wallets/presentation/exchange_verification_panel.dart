import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../../core/widgets/app_states.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/application/platform_providers.dart';
import 'exchange_support.dart';
import 'exchange_limits_dialog.dart';
import 'exchange_reference_data.dart';
import 'exchange_business_onboarding_dialog.dart';

class ExchangeVerificationPanel extends ConsumerStatefulWidget {
  const ExchangeVerificationPanel({super.key});
  @override
  ConsumerState<ExchangeVerificationPanel> createState() =>
      _ExchangeVerificationPanelState();
}

class _ExchangeVerificationPanelState
    extends ConsumerState<ExchangeVerificationPanel> {
  bool busy = false, applicationOutcomeUnknown = false;
  String? error;
  String? verificationUrl;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      ref.invalidate(exchangeVerificationProvider);
    } catch (e) {
      if (mounted) {
        setState(() => error = applicationOutcomeUnknown
            ? 'We could not confirm your application was received. Refresh your Exchange status. If it is still incomplete, contact support before submitting again.'
            : friendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startBusiness() async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ExchangeBusinessOnboardingDialog());
    if (result == null || !mounted) return;
    if (result['action'] == 'support') {
      await context.push('/support');
      return;
    }
    await run(() async {
      final link = exchangeText(result, 'verificationUrl');
      setState(
          () => verificationUrl = exchangeSafeUrl(link) != null ? link : null);
      if (verificationUrl != null) await openExchangeUrl(verificationUrl!);
    });
  }

  Future<void> completeApplication() async {
    final api = ref.read(mobilePlatformApiProvider);
    final draft = await api.getExchangeApplication();
    if (!mounted) return;
    if (draft['supported'] != true) {
      throw StateError(exchangeText(draft, 'message'));
    }
    if (draft['readyToSubmit'] == true) {
      try {
        await api.submitExchangeApplicationFromSumsub();
        ref.invalidate(exchangeOverviewProvider);
      } catch (e) {
        if (e is DioException &&
            (e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.sendTimeout ||
                e.type == DioExceptionType.connectionError ||
                (e.response?.statusCode ?? 0) >= 500)) {
          applicationOutcomeUnknown = true;
          throw StateError(
              'We could not confirm your application was received. Refresh your Exchange status. If it is still incomplete, contact support before submitting again.');
        }
        rethrow;
      }
      return;
    }
    setState(() => busy = false);
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExchangeApplicationDialog(
            initial: exchangeMap(draft['answers']),
            kycLevel: draft['kycLevel'] == 'SDD' ? 'SDD' : 'CDD',
            missingFields: (draft['missingFields'] as List?)
                ?.map((v) => v.toString())
                .toSet()));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exchangeVerificationProvider);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Align(
                heightFactor: 1,
                alignment: AlignmentDirectional.topStart,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: state.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, st) => Column(children: [
                              const Text(
                                  'Could not check Exchange verification.'),
                              TextButton(
                                  onPressed: () => ref
                                      .invalidate(exchangeVerificationProvider),
                                  child: const Text('Retry'))
                            ]),
                        data: (data) {
                          final provider = exchangeMap(data['provider']);
                          final status = exchangeText(data, 'status');
                          final nextAction =
                              exchangeText(provider, 'nextAction')
                                  .split(':')
                                  .first;
                          final submitted = provider['actionSubmitted'] == true;
                          final business =
                              data['verificationType'] == 'business';
                          final canStart = !business &&
                              data['eligible'] == true &&
                              provider.isEmpty &&
                              [
                                'not_started',
                                'in_progress',
                                'resubmission_required'
                              ].contains(status);
                          final url = provider.isNotEmpty
                              ? exchangeActionUrl(provider)
                              : verificationUrl;
                          return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Exchange verification',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 12),
                                Text(provider.isNotEmpty
                                    ? submitted
                                        ? 'Your information has been submitted for review.'
                                        : ['rejected', 'failed']
                                                .contains(provider['kycStatus'])
                                            ? 'Your Exchange application was not approved. Contact support.'
                                            : provider['kycStatus'] ==
                                                    'accepted'
                                                ? 'Your account is approved. Settlement accounts are being prepared.'
                                                : nextAction == 'tin_required'
                                                    ? 'Provide your tax identification details.'
                                                    : nextAction ==
                                                            'edd_required'
                                                        ? 'Provide additional source of funds information.'
                                                        : [
                                                            'kyc_required',
                                                            'kyb_required'
                                                          ].contains(nextAction)
                                                            ? 'Complete the provider verification to continue.'
                                                            : 'Your Exchange application is under review.'
                                    : business
                                        ? 'Review your saved business details and complete the provider’s business verification.'
                                        : data['eligible'] != true
                                            ? 'Complete your identity verification first.'
                                            : {
                                                  'not_started':
                                                      'Choose your limits and complete Exchange verification.',
                                                  'in_progress':
                                                      'Continue your saved Exchange verification.',
                                                  'resubmission_required':
                                                      'Additional verification information is required.',
                                                  'pending':
                                                      'Your verification is under review.',
                                                  'on_hold':
                                                      'Additional review is in progress.',
                                                  'approved':
                                                      'Verification approved. Activate your Exchange account.',
                                                  'rejected':
                                                      'Verification was not approved. Contact support.'
                                                }[status] ??
                                                'Checking verification status.'),
                                if (exchangeText(provider, 'reason').isNotEmpty)
                                  Text(exchangeText(provider, 'reason')),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (!business &&
                                          status == 'approved' &&
                                          data['hasProviderAccount'] != true)
                                        FilledButton(
                                            onPressed: busy ||
                                                    applicationOutcomeUnknown
                                                ? null
                                                : () =>
                                                    run(completeApplication),
                                            child: const Text(
                                                'Activate Exchange')),
                                      if (url != null &&
                                          exchangeSafeUrl(url) != null &&
                                          !submitted &&
                                          !['accepted', 'rejected', 'failed']
                                              .contains(provider['kycStatus']))
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => run(
                                                    () => openExchangeUrl(url)),
                                            child: const Text(
                                                'Continue verification')),
                                      if (business &&
                                          provider.isEmpty &&
                                          data['hasProviderAccount'] != true)
                                        FilledButton(
                                            onPressed: busy ||
                                                    data['businessOnboardingSupported'] !=
                                                        true
                                                ? null
                                                : startBusiness,
                                            child: const Text(
                                                'Review business details')),
                                      if (business &&
                                          provider.isEmpty &&
                                          data['businessOnboardingSupported'] !=
                                              true)
                                        const Text(
                                            'Business Exchange setup is not available yet. Contact support.'),
                                      if (canStart ||
                                          (!business &&
                                              status == 'approved' &&
                                              ['sdd', 'cdd'].contains(data['tier']) &&
                                              provider.isEmpty))
                                        OutlinedButton(
                                            onPressed: busy
                                                ? null
                                                : () => run(() async {
                                                      final tier = business
                                                          ? 'kyb'
                                                          : await showDialog<
                                                                  String>(
                                                              context: context,
                                                              builder: (context) =>
                                                                  ExchangeLimitsDialog(
                                                                      currentTier: exchangeText(data, 'tier')));
                                                      if (tier == null) return;
                                                      final session = await ref
                                                          .read(
                                                              mobilePlatformApiProvider)
                                                          .startExchangeVerification(
                                                              tier);
                                                      if (!mounted) return;
                                                      setState(() => verificationUrl = null);
                                                      ref.invalidate(exchangeOverviewProvider);
                                                      ref.invalidate(exchangeVerificationProvider);
                                            await ref.read(exchangeVerificationProvider.future);
                                                      if (!mounted) return;
                                                      final link = exchangeText(
                                                          session,
                                                          'verificationUrl');
                                                      if (exchangeSafeUrl(
                                                                  link) !=
                                                              null &&
                                                          mounted) {
                                                        setState(() =>
                                                            verificationUrl =
                                                                link);
                                                        await openExchangeUrl(
                                                            link);
                                                      }
                                                    }),
                                            child: Text(status == 'approved'
                                                ? 'Change limits'
                                                : 'Choose limits and verify')),
                                      if (!submitted &&
                                          ['tin_required', 'edd_required']
                                              .contains(nextAction))
                                        FilledButton(
                                            onPressed: busy
                                                ? null
                                                : () => run(() async {
                                                      await showDialog<void>(
                                                          context: context,
                                                          barrierDismissible:
                                                              false,
                                                          builder: (_) =>
                                                              ExchangeProviderActionDialog(
                                                                  tax: nextAction ==
                                                                      'tin_required'));
                                                    }),
                                            child: const Text(
                                                'Provide information')),
                                    ],
                                  ),
                                ),
                                if (!business &&
                                    status == 'approved' &&
                                    data['hasProviderAccount'] != true)
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                          'We’ll use your completed Sumsub answers. Only missing details will be requested.')),
                                TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => ref.invalidate(
                                            exchangeVerificationProvider),
                                    child: const Text(
                                        'Refresh verification status')),
                                if (busy)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: LinearProgressIndicator(),
                                  ),
                                if (error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .errorContainer,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.error_outline,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onErrorContainer),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(error!,
                                                  softWrap: true,
                                                  style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onErrorContainer)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ]);
                        })))));
  }
}

class ExchangeApplicationDialog extends ConsumerStatefulWidget {
  const ExchangeApplicationDialog(
      {super.key, required this.initial, this.missingFields, this.kycLevel = 'CDD'});
  final Map<String, dynamic> initial;
  final Set<String>? missingFields;
  final String kycLevel;
  @override
  ConsumerState<ExchangeApplicationDialog> createState() =>
      _ExchangeApplicationDialogState();
}

class _ExchangeApplicationDialogState
    extends ConsumerState<ExchangeApplicationDialog> {
  late final Map<String, String> answers =
      widget.initial.map((k, v) => MapEntry(k, v.toString()));
  final scroll = ScrollController();
  bool busy = false, outcomeUnknown = false;
  String? error;
  String value(String key) => answers[key] ?? '';
  late final Set<String>? missingFields =
      widget.missingFields == null ? null : {...widget.missingFields!};
  static const cddFields = {
    'annual_income', 'expected_deposit_one_year', 'hnwi_str',
    'source_of_funds', 'source_of_funds_of_country', 'source_of_wealth_of_country'
  };
  bool applicable(String key) => widget.kycLevel != 'SDD' || !cddFields.contains(key);
  bool asks(String key) =>
      applicable(key) && (missingFields == null || missingFields!.contains(key));
  void change(String key, String v) => setState(() {
        answers[key] = v;
        if (key == 'employment_type_or_status') {
          missingFields?.add('employment_jurisdiction');
          answers.remove('employment_jurisdiction');
        }
      });
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Widget choice(String key, String label, Map<String, String> options) => !asks(
          key)
      ? const SizedBox.shrink()
      : ExchangeFieldLabel(
          label: label,
          child: DropdownButtonFormField<String>(
              initialValue: options.containsKey(value(key).split(':').first)
                  ? value(key).split(':').first
                  : null,
              isExpanded: true,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(hintText: 'Select an option'),
              items: options.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: busy ? null : (v) => change(key, v ?? '')));

  Widget country(String key, String label) => !asks(key)
      ? const SizedBox.shrink()
      : ExchangeCountryField(
          label: label,
          labelAbove: true,
          value: value(key),
          enabled: !busy,
          onChanged: (v) => change(key, v));

  Widget countries(String key, String label) {
    if (!asks(key)) return const SizedBox.shrink();
    final selected = value(key).split(',').where((x) => x.isNotEmpty).toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ExchangeCountryField(
          key: ValueKey('$key-${selected.length}'),
          label: label,
          labelAbove: true,
          value: '',
          enabled: !busy,
          onChanged: (v) => change(key, {...selected, v}.join(','))),
      if (selected.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
            spacing: 8,
            runSpacing: 4,
            children: selected
                .map((code) => InputChip(
                    label: Text(exchangeCountries[code] ?? code),
                    onDeleted: busy
                        ? null
                        : () =>
                            change(key, (selected..remove(code)).join(','))))
                .toList()),
      ],
    ]);
  }

  Widget fields(List<Widget> children) =>
      LayoutBuilder(builder: (context, constraints) {
        final paired = constraints.maxWidth >= 560 &&
            MediaQuery.textScalerOf(context).scale(16) <= 20;
        return Wrap(
            spacing: 20,
            runSpacing: 20,
            children: children
                .where((child) => child is! SizedBox)
                .map((child) => SizedBox(
                    width: paired
                        ? (constraints.maxWidth - 20) / 2
                        : constraints.maxWidth,
                    child: child))
                .toList());
      });

  Widget section(String title, String description, Widget content) {
    const keys = {
      'Personal details': [
        'sdd_country_select',
        'investment_citizenship',
        'acting_capacity'
      ],
      'Employment': [
        'employment_type_or_status',
        'industry',
        'employment_jurisdiction'
      ],
      'Financial profile': [
        'annual_income',
        'expected_deposit_one_year',
        'hnwi_str'
      ],
      'Sources of funds': ['source_of_funds'],
    };
    if (keys.containsKey(title) && !keys[title]!.any(asks)) {
      return const SizedBox.shrink();
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            content,
          ],
        ));
  }

  Future<void> submit() async {
    if (busy || outcomeUnknown) return;
    // Multi-country selectors intentionally have an empty add control; validate their selected values separately.
    if (applicable('source_of_funds') && value('source_of_funds').split(',').contains('71')) {
      setState(() => error = 'Third-party funding requires support review.');
      return;
    }
    final required = [
      'sdd_country_select',
      'investment_citizenship',
      'employment_type_or_status',
      'industry',
      'acting_capacity',
      'annual_income',
      'expected_deposit_one_year',
      'hnwi_str',
      'source_of_funds',
      'source_of_funds_of_country',
      'source_of_wealth_of_country'
    ];
    if (['15', '16'].contains(value('employment_type_or_status'))) {
      required.add('employment_jurisdiction');
    }
    if (required.where(applicable).any((k) => value(k).trim().isEmpty)) {
      setState(() => error = 'Complete all application fields.');
      return;
    }
    final submitted = {...answers};
    if (['18', '19'].contains(value('employment_type_or_status'))) {
      submitted['employment_jurisdiction'] = 'N/A';
    }
    if (value('employment_type_or_status') == '17') {
      submitted.remove('employment_jurisdiction');
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(mobilePlatformApiProvider)
          .submitExchangeApplication(submitted);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          outcomeUnknown = e is DioException &&
              (e.type == DioExceptionType.receiveTimeout ||
                  e.type == DioExceptionType.sendTimeout ||
                  e.type == DioExceptionType.connectionError ||
                  (e.response?.statusCode ?? 0) >= 500);
          error = outcomeUnknown
              ? 'We could not confirm your application was received. Close this form and refresh your Exchange status. If it is still incomplete, contact support before submitting again.'
              : friendlyErrorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final padding = compact ? 20.0 : 28.0;
    return PopScope(
        canPop: !busy,
        child: Dialog(
          insetPadding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 32, vertical: compact ? 16 : 32),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 840),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                        padding:
                            EdgeInsets.fromLTRB(padding, padding, padding, 20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Exchange application',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text(
                                  widget.missingFields == null
                                      ? 'Your available Sumsub answers are prefilled. Review them and complete any missing details.'
                                      : 'Your completed Sumsub answers will be reused. Please complete only the remaining details below.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ])),
                    const Divider(height: 1),
                    Flexible(
                        child: Theme(
                            data: theme.copyWith(
                                inputDecorationTheme:
                                    theme.inputDecorationTheme.copyWith(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: theme.colorScheme.outlineVariant)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: theme.colorScheme.primary,
                                      width: 2)),
                            )),
                            child: Scrollbar(
                                controller: scroll,
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                    controller: scroll,
                                    padding: EdgeInsets.all(padding),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          section(
                                              'Personal details',
                                              'Confirm your residence and who you are acting for.',
                                              fields([
                                                country('sdd_country_select',
                                                    'Country of residence'),
                                                choice(
                                                    'investment_citizenship',
                                                    'Citizenship through investment?',
                                                    {'81': 'Yes', '82': 'No'}),
                                                choice('acting_capacity',
                                                    'Acting on behalf of', {
                                                  '156': 'Myself',
                                                  '157': 'Another person'
                                                }),
                                              ])),
                                          section(
                                              'Employment',
                                              'Tell us about your work or current circumstances.',
                                              fields([
                                                choice(
                                                    'employment_type_or_status',
                                                    'Employment status', {
                                                  '15': 'Employed',
                                                  '16':
                                                      'Self-employed or business owner',
                                                  '17': 'Unemployed',
                                                  '18': 'Retired',
                                                  '19':
                                                      'Student, carer or benefits'
                                                }),
                                                choice('industry', 'Industry',
                                                    exchangeIndustries),
                                                if (value('industry')
                                                    .startsWith('53'))
                                                  ExchangeFieldLabel(
                                                      label:
                                                          'Other industry (optional)',
                                                      child: TextFormField(
                                                          initialValue: value(
                                                                      'industry')
                                                                  .contains(':')
                                                              ? value('industry')
                                                                  .substring(3)
                                                              : '',
                                                          enabled: !busy,
                                                          onChanged: (v) => change(
                                                              'industry',
                                                              v.isEmpty
                                                                  ? '53'
                                                                  : '53:$v'))),
                                                if (['15', '16'].contains(value(
                                                    'employment_type_or_status')))
                                                  country(
                                                      'employment_jurisdiction',
                                                      'Country of employment or business'),
                                              ])),
                                          section(
                                              'Financial profile',
                                              'Choose the ranges that best describe your finances.',
                                              fields([
                                                choice('annual_income',
                                                    'Annual income (EUR)', {
                                                  '74': 'Up to €10,000',
                                                  '75': '€10,000–€50,000',
                                                  '76': '€50,000–€300,000',
                                                  '77': 'Over €300,000'
                                                }),
                                                choice(
                                                    'expected_deposit_one_year',
                                                    'Expected deposits next year (EUR)',
                                                    {
                                                      '83': 'Up to €10,000',
                                                      '84': '€10,000–€150,000',
                                                      '85': 'Over €150,000'
                                                    }),
                                                choice('hnwi_str',
                                                    'Net worth (EUR)', {
                                                  '78': 'Under €100,000',
                                                  '79': '€100,000–€1 million',
                                                  '80': '€1 million or more'
                                                }),
                                              ])),
                                          section(
                                              'Sources of funds',
                                              'Select all that apply.',
                                              Container(
                                                  decoration: BoxDecoration(
                                                      border: Border.all(
                                                          color: theme
                                                              .colorScheme
                                                              .outlineVariant),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12)),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: Column(children: [
                                                    for (final entry
                                                        in exchangeFundSources
                                                            .entries)
                                                      CheckboxListTile(
                                                          contentPadding:
                                                              const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      12),
                                                          controlAffinity:
                                                              ListTileControlAffinity
                                                                  .leading,
                                                          title: Text(
                                                              entry.value,
                                                              style: theme
                                                                  .textTheme
                                                                  .bodyMedium),
                                                          value: value(
                                                                  'source_of_funds')
                                                              .split(',')
                                                              .contains(
                                                                  entry.key),
                                                          onChanged: busy
                                                              ? null
                                                              : (on) {
                                                                  final values = value(
                                                                          'source_of_funds')
                                                                      .split(
                                                                          ',')
                                                                      .where((x) =>
                                                                          x.isNotEmpty)
                                                                      .toSet();
                                                                  on == true
                                                                      ? values.add(
                                                                          entry
                                                                              .key)
                                                                      : values.remove(
                                                                          entry
                                                                              .key);
                                                                  change(
                                                                      'source_of_funds',
                                                                      values.join(
                                                                          ','));
                                                                }),
                                                  ]))),
                                          const SizedBox(height: 24),
                                          fields([
                                            countries(
                                                'source_of_funds_of_country',
                                                'Countries where funds originate'),
                                            countries(
                                                'source_of_wealth_of_country',
                                                'Countries where wealth originates')
                                          ]),
                                        ]))))),
                    const Divider(height: 1),
                    Padding(
                        padding: EdgeInsets.fromLTRB(padding, 16, padding, 20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (error != null) ...[
                                Text(error!,
                                    style: TextStyle(
                                        color: theme.colorScheme.error)),
                                const SizedBox(height: 12)
                              ],
                              if (busy) ...[
                                const LinearProgressIndicator(),
                                const SizedBox(height: 12)
                              ],
                              OverflowBar(
                                  spacing: 12,
                                  overflowSpacing: 8,
                                  alignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => Navigator.pop(context),
                                        child: Text(outcomeUnknown
                                            ? 'Close'
                                            : 'Cancel')),
                                    FilledButton(
                                        onPressed: busy || outcomeUnknown
                                            ? null
                                            : submit,
                                        child: Text(busy
                                            ? 'Submitting…'
                                            : 'Submit application')),
                                  ]),
                            ])),
                  ])),
        ));
  }
}

class ExchangeProviderActionDialog extends ConsumerStatefulWidget {
  const ExchangeProviderActionDialog({super.key, required this.tax});
  final bool tax;
  @override
  ConsumerState<ExchangeProviderActionDialog> createState() =>
      _ExchangeProviderActionDialogState();
}

class _ExchangeProviderActionDialogState
    extends ConsumerState<ExchangeProviderActionDialog> {
  final fields = <String, String>{};
  bool unavailable = false, busy = false;
  String? error;
  Widget field(String key, String label) => TextFormField(
      enabled: !busy,
      maxLength: 2000,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => fields[key] = v.trim());
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: Text(widget.tax
              ? 'Tax identification'
              : 'Source of funds information'),
          content: SizedBox(
              width: 550,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (widget.tax) ...[
                  ExchangeCountryField(
                      label: 'Country of tax residence',
                      value: fields['taxResidency'] ?? '',
                      enabled: !busy,
                      onChanged: (v) =>
                          setState(() => fields['taxResidency'] = v)),
                  CheckboxListTile(
                      title: const Text(
                          'I do not have an available tax identification number'),
                      value: unavailable,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => unavailable = v == true)),
                  if (!unavailable)
                    field('tin', 'Tax identification number')
                  else ...[
                    DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Reason'),
                        items: const {
                          'TIN_COUNTRY_NOT_ISSUE':
                              'Country does not issue TINs',
                          'TIN_NOT_REQUIRED': 'Not required',
                          'TIN_NOT_ISSUED': 'Not issued to me',
                          'TIN_OTHER': 'Other reason'
                        }
                            .entries
                            .map((e) => DropdownMenuItem(
                                value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: busy
                            ? null
                            : (v) => setState(() =>
                                fields['tinNotAvailableReason'] = v ?? '')),
                    if (fields['tinNotAvailableReason'] == 'TIN_OTHER')
                      field('tinNotAvailableReasonDescription',
                          'Explain why TIN is unavailable')
                  ],
                ] else ...[
                  for (final entry in const {
                    'capitalOfCompany': 'Company capital',
                    'giftOrInheritance': 'Gift or inheritance',
                    'profitFromSoldOrMaturingInvestments':
                        'Investment sale or maturity',
                    'profitsFromPropertySale': 'Property sale',
                    'profitsFromSaleOfCompany': 'Company sale',
                    'compensationPayment': 'Compensation',
                    'pension': 'Pension',
                    'other': 'Other source'
                  }.entries)
                    field(entry.key, entry.value),
                  const Text('Salary / employment details (if applicable)'),
                  for (final entry in const {
                    'nameOfEmployer': 'Employer name',
                    'occupation': 'Occupation',
                    'addressOfEmployer': 'Employer address',
                    'noOfYearsInEmployment': 'Years employed',
                    'grossAnnualIncome': 'Gross annual income and currency'
                  }.entries)
                    field('salary.${entry.key}', entry.value),
                  const Text('Document uploads are not available yet. Do not publish sensitive documents or paste document links. Contact support if documents are required.'),
                ],
                if (error != null) Text(error!),
              ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          final api = ref.read(mobilePlatformApiProvider);
                          if (widget.tax) {
                            if ((fields['taxResidency'] ?? '').isEmpty ||
                                (!unavailable &&
                                    (fields['tin'] ?? '').isEmpty) ||
                                (unavailable &&
                                    fields['tinNotAvailableReason'] ==
                                        'TIN_OTHER' &&
                                    (fields['tinNotAvailableReasonDescription'] ??
                                            '')
                                        .isEmpty)) {
                              throw StateError(
                                  'Complete the tax identification fields.');
                            }
                            await api.submitExchangeTin({
                              'taxResidency': fields['taxResidency'],
                              'tin': unavailable ? null : fields['tin'],
                              'tinNotAvailable': unavailable,
                              'tinNotAvailableReason': unavailable
                                  ? fields['tinNotAvailableReason']
                                  : null,
                              'tinNotAvailableReasonDescription': unavailable
                                  ? fields['tinNotAvailableReasonDescription']
                                  : null
                            });
                          } else {
                            final salary = {
                              for (final e in fields.entries.where((e) =>
                                  e.key.startsWith('salary.') &&
                                  e.value.isNotEmpty))
                                e.key.substring(7): e.value
                            };
                            final request = <String, dynamic>{
                              for (final e in fields.entries.where((e) =>
                                  !e.key.startsWith('salary.') &&
                                  e.key != 'fileUrls' &&
                                  e.value.isNotEmpty))
                                e.key: e.value
                            };
                            if (salary.isNotEmpty) {
                              request['professionalSalary'] = salary;
                            }
                            if (request.isEmpty) {
                              throw StateError(
                                  'Provide source of funds details.');
                            }
                            await api.submitExchangeEdd(request);
                          }
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (mounted) {
                            setState(() => error = friendlyErrorMessage(e));
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: Text(busy ? 'Submitting…' : 'Submit information'))
          ]));
}
