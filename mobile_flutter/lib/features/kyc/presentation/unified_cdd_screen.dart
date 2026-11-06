import '../../../shared/widgets/equals_fee_schedule.dart';
import 'dart:convert';
import 'package:go_router/go_router.dart';
import '../../onboarding/presentation/personal_onboarding_gate.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/equals_money.dart';
import '../../../shared/widgets/searchable_multi_select_dropdown.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/personal_onboarding_localizations.dart';
import '../application/kyc_providers.dart';
import '../../dashboard/data/dashboard_providers.dart';

const unifiedCddRoot = '/api/v1/mobile/onboarding/cdd';
final unifiedCddPreferenceProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final config = await ref.watch(mobileTenantConfigProvider.future);
  if (!config.unifiedCddOnboardingEnabled) return false;
  final result = await ref
      .watch(dioProvider)
      .get<Map<String, dynamic>>('$unifiedCddRoot/preferences');
  return result.data?['enabled'] == true;
});

String unifiedCddErrorMessage(DioException error) {
  final status = error.response?.statusCode;
  if (status == 404 || status == 502 || status == 503) {
    return 'Verification is temporarily unavailable. Please try again shortly.';
  }
  if (status == 428) {
    return 'Review and accept the current Equals Money agreements before continuing.';
  }
  if (status == 429) {
    return 'Too many attempts. Please wait a moment and try again. Your answers are still here.';
  }
  Object? data = error.response?.data;
  for (var depth = 0; depth < 5; depth++) {
    if (data is String) {
      final text = data;
      try {
        data = jsonDecode(text);
      } catch (_) {
        if (text.trim().isNotEmpty &&
            text.length < 400 &&
            !text.contains('<') &&
            !text.contains('{')) {
          return text;
        }
        break;
      }
    }
    if (data is! Map) break;
    final message = data['message'];
    if (message is String &&
        message.trim().isNotEmpty &&
        message.length < 400 &&
        !message.contains('{') &&
        !message.contains('<')) {
      return message;
    }
    final errors = data['errors'];
    if (errors is Map) {
      final messages = errors.values
          .expand((value) => value is List ? value : [value])
          .whereType<String>()
          .where((message) =>
              message.length < 300 &&
              !message.contains('<') &&
              !message.contains('{'))
          .toList();
      if (messages.isNotEmpty) return messages.take(4).join('\n');
    }
    data = data['detail'];
  }
  return error.response == null
      ? 'Could not connect. Please retry this step.'
      : 'Could not complete verification. Please retry this step.';
}

String unifiedCddMissingFieldLabel(String field) =>
    const {
      'cdd.address.postCode': 'Postal / ZIP code',
      'cdd.address.street': 'Street address',
      'cdd.address.town': 'City',
      'cdd.address.country': 'Address country',
      'cdd.info.nationality': 'Nationality',
      'cdd.info.firstName': 'First name',
      'cdd.info.lastName': 'Last name',
      'cdd.info.dob': 'Date of birth',
      'cdd.identity.number': 'Identity document number',
      'cdd.identity.validUntil': 'Identity document expiry date',
      'cdd.documents.IDENTITY': 'Identity document',
      'cdd.documents.SELFIE': 'Identity selfie',
      'cdd.documents.PROOF_OF_RESIDENCE': 'Proof of address',
    }[field] ??
    (field.startsWith('cdd.questionnaire.')
        ? 'Verification questionnaire answers'
        : 'Verification details');

/// Uses the existing registration choices and questionnaire option lists. No legacy KYC call.
class UnifiedCddScreen extends ConsumerStatefulWidget {
  const UnifiedCddScreen({super.key});
  @override
  ConsumerState<UnifiedCddScreen> createState() => _UnifiedCddScreenState();
}

class _UnifiedCddScreenState extends ConsumerState<UnifiedCddScreen> {
  final _form = GlobalKey<FormState>();
  final _errorAnchor = GlobalKey();
  final _summaryAnchor = GlobalKey();
  final _fieldKeys = <String, GlobalKey>{};
  final _fieldLabels = <String, String>{};
  Set<String> _invalidFields = {};
  bool _validationAttempted = false;

  GlobalKey _anchor(String key, String label) {
    _fieldLabels[key] = context.tr(label);
    return _fieldKeys.putIfAbsent(key, () => GlobalKey(debugLabel: key));
  }

  void _showAt(GlobalKey key) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = key.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(target,
              alignment: .12, duration: const Duration(milliseconds: 250));
        }
      });
  void _saveAnswers() {
    final invalid = _form.currentState?.validateGranularly();
    if (invalid == null) return;
    final keys = <String>{};
    for (final field in invalid) {
      field.context.visitAncestorElements((element) {
        for (final entry in _fieldKeys.entries) {
          if (element.widget.key == entry.value) {
            keys.add(entry.key);
            return false;
          }
        }
        return true;
      });
    }
    setState(() {
      _validationAttempted = true;
      _invalidFields = keys;
    });
    if (invalid.isNotEmpty) {
      _showAt(_summaryAnchor);
      return;
    }
    _request('answers');
  }

  Map<String, dynamic>? _state;
  Map<String, dynamic> _answers = {};
  bool _busy = false;
  String? _error;
  String? _url;
  bool _dirty = false;
  @override
  void initState() {
    super.initState();
  }

  Map<String, dynamic> _normalise(Map data) => data.map((key, value) {
        final name = key.toString();
        return MapEntry(name[0].toLowerCase() + name.substring(1), value);
      });
  Future<void> _request(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final Response response = action == 'refresh'
          ? await dio.get(unifiedCddRoot)
          : action == 'answers'
              ? await dio.put('$unifiedCddRoot/answers', data: _answers)
              : await dio.post('$unifiedCddRoot/$action');
      if (!mounted) return;
      final state = _normalise(response.data as Map);
      setState(() {
        _state = state;
        _url = state['verificationUrl'] as String? ?? _url;
        if (!_dirty || action == 'answers') {
          _answers = state['answers'] is Map
              ? _normalise(state['answers'] as Map)
              : {};
          _dirty = false;
        }
      });
      ref.invalidate(kycDetailedStatusProvider);
      ref.invalidate(hoppaDashboardProvider);
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _error = unifiedCddErrorMessage(e));
        _showAt(_errorAnchor);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load onboarding. Please retry.');
        _showAt(_errorAnchor);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _change(String key, dynamic value) => setState(() {
        _answers[key] = value;
        _dirty = true;
        _invalidFields.remove(key);
      });
  Widget _choice(String key, String label, List<String> options) => Padding(
      key: _anchor(key, label),
      padding: const EdgeInsets.only(bottom: 12),
      child: SearchableSingleSelectDropdown(
          label: context.tr(label),
          value: _answers[key] as String?,
          options: options,
          labelBuilder: (v) => personalOnboardingOptionLabel(context, v),
          onChanged: (v) => _change(key, v),
          enabled: !_busy));
  Widget _multiple(String key, String label, List<String> options,
          {OptionLabelBuilder? labelBuilder}) =>
      Padding(
          key: _anchor(key, label),
          padding: const EdgeInsets.only(bottom: 12),
          child: SearchableMultiSelectDropdown(
              label: context.tr(label),
              values: List<String>.from(_answers[key] as List? ?? []),
              options: options,
              labelBuilder: labelBuilder ??
                  (v) => personalOnboardingOptionLabel(context, v),
              onChanged: (v) => _change(key, v)));
  Widget _yesNo(String key, String label) => Padding(
      key: _anchor(key, label),
      padding: const EdgeInsets.only(bottom: 16),
      child: SearchableSingleSelectDropdown(
        label: context.tr(label),
        value: _answers[key] == null
            ? null
            : (_answers[key] == true ? 'Yes' : 'No'),
        options: const ['Yes', 'No'],
        labelBuilder: (value) => context.tr(value),
        enabled: !_busy,
        onChanged: (value) => _change(key, value == 'Yes'),
      ));
  Widget _text(String key, String label, {String? hint}) => Padding(
      key: _anchor(key, label),
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
          key: ValueKey('$key:${_state?['status']}'),
          initialValue: _answers[key] as String?,
          enabled: !_busy,
          decoration:
              InputDecoration(labelText: context.tr(label), hintText: hint),
          validator: (v) {
            if (v?.trim().isNotEmpty != true) return context.tr('Required');
            if (key == 'documentIssueDate') {
              final date = DateTime.tryParse(v!.trim());
              if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v.trim()) ||
                  date == null ||
                  date.toIso8601String().substring(0, 10) != v.trim() ||
                  date.isAfter(DateTime.now())) {
                return context.tr('Enter a valid date in YYYY-MM-DD format');
              }
            }
            return null;
          },
          onChanged: (v) => _change(key, v)));
  String _providerStatus(dynamic value) => switch (value?.toString()) {
        'invite_required' => 'Accept your banking invite to continue',
        'payment_required' => 'Complete your onboarding payment to continue',
        'approved' => 'Approved',
        'rejected' => 'Not approved',
        'disabled_in_staging' => 'Unavailable in staging',
        'reconciliation_required' =>
          'In progress — we are checking your submission',
        'submitted' => 'In progress — awaiting provider review',
        'not_started' || 'dispatching' || 'pending' => 'In progress',
        _ => 'In progress',
      };

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final missing = List<String>.from(state?['missingFields'] as List? ?? []);
    final submitted = state?['submissionRequested'] == true;
    final approved = state?['status'] == 'approved';
    final banking = state?['banking'] == true;
    return PersonalOnboardingGate(
        banking: banking && approved,
        onReady: () {
          if (_state == null) _request('session');
        },
        child: Scaffold(
            appBar: AppBar(title: Text(context.tr('Set up your services'))),
            body: SafeArea(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                      context.tr(
                                          'Verify once for your selected services'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall),
                                  const SizedBox(height: 12),
                                  Text(context.tr(
                                      'Your identity and proof of address will be used for your crypto card and the additional services you selected.')),
                                  if (_error != null)
                                    Padding(
                                        key: _errorAnchor,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Text(_error!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error))),
                                  if (_busy) const LinearProgressIndicator(),
                                  if (state == null)
                                    OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _request('session'),
                                        child: Text(context.tr('Retry'))),
                                  if (state != null) ...[
                                    const SizedBox(height: 16),
                                    if (approved)
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                            Icons.check_circle_outline,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                        title: Text(
                                            context.tr('Identity verified')),
                                        subtitle: Text(context.tr(
                                            'Your identity and proof of address are approved.')),
                                      )
                                    else
                                      Text(
                                          '${context.tr('Identity verification')}: ${state['status']}'),
                                    if (!approved && _url != null)
                                      FilledButton(
                                          onPressed: _busy
                                              ? null
                                              : () async {
                                                  final uri =
                                                      Uri.tryParse(_url!);
                                                  if (uri == null ||
                                                      uri.scheme != 'https' ||
                                                      uri.host.isEmpty ||
                                                      !await launchUrl(uri,
                                                          mode: LaunchMode
                                                              .externalApplication)) {
                                                    if (mounted) {
                                                      setState(() => _error =
                                                          'Could not open verification. Please retry.');
                                                    }
                                                  }
                                                },
                                          child: Text(context
                                              .tr('Continue verification'))),
                                    Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                            icon: const Icon(Icons.refresh,
                                                size: 18),
                                            onPressed: _busy
                                                ? null
                                                : () => _request('refresh'),
                                            label: Text(
                                                context.tr('Check status')))),
                                    const SizedBox(height: 24),
                                    if (approved && !submitted) ...[
                                      Text(
                                          context.tr('Finish your application'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 8),
                                      Text(context.tr(
                                          'Your verification is complete. Answer the remaining questions, then submit to activate your selected services.')),
                                      const SizedBox(height: 20),
                                    ],
                                    if (approved && !submitted)
                                      if (_invalidFields.isNotEmpty)
                                        Container(
                                            key: _summaryAnchor,
                                            margin: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .errorContainer,
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      context.tr(
                                                          'Please complete the following fields:'),
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600)),
                                                  for (final key
                                                      in _invalidFields)
                                                    TextButton(
                                                        onPressed: () =>
                                                            _showAt(_fieldKeys[
                                                                key]!),
                                                        child: Text(
                                                            _fieldLabels[key] ??
                                                                key)),
                                                ])),
                                    Form(
                                        key: _form,
                                        autovalidateMode: _validationAttempted
                                            ? AutovalidateMode.onUserInteraction
                                            : AutovalidateMode.disabled,
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              if (banking) ...[
                                                Text(
                                                    context.tr(
                                                        'Equals Money account details'),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium),
                                                const SizedBox(height: 12),
                                                _multiple(
                                                    'equalsMainPurpose',
                                                    'Main purposes',
                                                    equalsPersonalPurposeOptions),
                                                _multiple(
                                                    'equalsSourceOfFunds',
                                                    'Sources of funds',
                                                    equalsPersonalSourceOfFundsOptions),
                                                _multiple(
                                                    'equalsDestinationCountries',
                                                    'Destination countries',
                                                    equalsCountryCodes,
                                                    labelBuilder: (v) =>
                                                        personalOnboardingCountryLabel(
                                                            context, v)),
                                                _multiple(
                                                    'equalsCurrenciesRequired',
                                                    'Required currencies',
                                                    equalsSupportedCurrencyCodes),
                                                _choice(
                                                    'equalsExpectedAnnualVolume',
                                                    'Annual volume',
                                                    equalsAnnualVolumeOptions),
                                                _choice(
                                                    'equalsExpectedPayments',
                                                    'Number of payments',
                                                    equalsPersonalPaymentCountOptions),
                                                const SizedBox(height: 12),
                                                Text(
                                                    context.tr(
                                                        'Equals Money cards'),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium),
                                                const SizedBox(height: 12),
                                                _yesNo('equalsCardsRequested',
                                                    'Request cards'),
                                                if (_answers[
                                                        'equalsCardsRequested'] ==
                                                    true) ...[
                                                  _multiple(
                                                      'equalsCardPurposes',
                                                      'Card purposes',
                                                      equalsPersonalPurposeOptions),
                                                  _choice(
                                                      'equalsCardAnnualSpend',
                                                      'Annual card spend',
                                                      equalsAnnualVolumeOptions),
                                                  _choice(
                                                      'equalsNumberOfCardsRequired',
                                                      'Number of cards required',
                                                      equalsCardCountOptions),
                                                  _yesNo(
                                                      'equalsAtmWithdrawalsRequired',
                                                      'ATM withdrawals required'),
                                                ],
                                                const SizedBox(height: 12),
                                              ],
                                              if (missing
                                                  .contains('annualSalary'))
                                                _choice(
                                                    'annualSalary',
                                                    'Annual salary (USD)',
                                                    const [
                                                      '0-10000',
                                                      '10001-30000',
                                                      '30001-50000',
                                                      '50001-75000',
                                                      '75001-100000',
                                                      '100001-150000',
                                                      '150001-250000',
                                                      '250001+'
                                                    ]),
                                              if (missing
                                                  .contains('occupation'))
                                                ref.watch(occupationCodesProvider).when(
                                                    data: (items) => Padding(
                                                        key: _anchor(
                                                            'occupation',
                                                            'Occupation'),
                                                        padding:
                                                            const EdgeInsets.only(
                                                                bottom: 12),
                                                        child: SearchableSingleSelectDropdown(
                                                            label: context.tr(
                                                                'Occupation'),
                                                            value:
                                                                _answers['occupation']
                                                                    as String?,
                                                            options: items
                                                                .where((i) => RegExp(r'^\d{2}-\d{4}$').hasMatch(i.value))
                                                                .map((i) => i.value)
                                                                .toList(),
                                                            labelBuilder: (v) => items.firstWhere((i) => i.value == v).title,
                                                            onChanged: (v) => _change('occupation', v))),
                                                    error: (_, __) => TextButton(onPressed: () => ref.invalidate(occupationCodesProvider), child: Text(context.tr('Retry occupations'))),
                                                    loading: () => const LinearProgressIndicator()),
                                              if (missing.contains(
                                                      'accountPurpose') &&
                                                  !banking)
                                                _text('accountPurpose',
                                                    'Account purpose'),
                                              if (missing.contains(
                                                      'expectedMonthlyVolume') &&
                                                  (!banking ||
                                                      (_state?['answers']
                                                              is Map &&
                                                          _normalise(_state![
                                                                          'answers']
                                                                      as Map)[
                                                                  'equalsExpectedAnnualVolume'] !=
                                                              null)))
                                                _choice(
                                                    'expectedMonthlyVolume',
                                                    'Expected monthly volume (USD)',
                                                    const [
                                                      '0-1000',
                                                      '1001-5000',
                                                      '5001-15000',
                                                      '15001-50000',
                                                      '50001-100000',
                                                      '100001+'
                                                    ]),
                                              if (missing.contains(
                                                  'documentIssueDate'))
                                                _text('documentIssueDate',
                                                    'Document issue date',
                                                    hint: 'YYYY-MM-DD'),
                                              if (missing.contains(
                                                  'cdd.address.postCode'))
                                                _text('postCode',
                                                    'Postal / ZIP code'),
                                              if (missing.any(
                                                  (v) => v.startsWith('cdd.')))
                                                Container(
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 12),
                                                    padding:
                                                        const EdgeInsets.all(
                                                            12),
                                                    decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .errorContainer,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12)),
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                              context.tr(
                                                                  'Missing from your verification:'),
                                                              style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600)),
                                                          for (final label in missing
                                                              .where((v) =>
                                                                  v.startsWith(
                                                                      'cdd.'))
                                                              .map(
                                                                  unifiedCddMissingFieldLabel)
                                                              .toSet())
                                                            Text(
                                                                '• ${context.tr(label)}'),
                                                          const SizedBox(
                                                              height: 8),
                                                          Text(context.tr(missing
                                                                  .contains(
                                                                      'cdd.address.postCode')
                                                              ? 'Enter your postal / ZIP code above, then save your answers. Contact support if other verification details are missing.'
                                                              : 'These details are needed before your services can be activated. Check status to refresh, or contact support for help.')),
                                                          TextButton(
                                                              onPressed: () =>
                                                                  context.push(
                                                                      '/support'),
                                                              child: Text(
                                                                  context.tr(
                                                                      'Contact support'))),
                                                        ])),
                                              if (banking)
                                                const EqualsFeeScheduleButton(),
                                              const SizedBox(height: 16),
                                              OutlinedButton(
                                                  onPressed: _busy
                                                      ? null
                                                      : _saveAnswers,
                                                  child: Text(context
                                                      .tr('Save answers'))),
                                              if (!_dirty &&
                                                  missing.isEmpty &&
                                                  (!banking ||
                                                      _answers[
                                                              'equalsCardsRequested']
                                                          is bool)) ...[
                                                const SizedBox(height: 16),
                                                FilledButton(
                                                    onPressed: _busy
                                                        ? null
                                                        : () =>
                                                            _request('submit'),
                                                    child: Text(context.tr(
                                                        'Activate selected services'))),
                                              ],
                                            ])),
                                    if (submitted) ...[
                                      Text(context.tr('Application submitted'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 8),
                                      Text(context.tr(
                                          'Your application is in progress. You do not need to submit it again.')),
                                      const SizedBox(height: 16),
                                      ListTile(
                                          title:
                                              Text(context.tr('Crypto card')),
                                          subtitle: Text(context.tr(
                                              _providerStatus(
                                                  state['interlace'])))),
                                      if (state['exchange'] == true)
                                        ListTile(
                                            title: Text(context.tr('Exchange')),
                                            subtitle: Text(context.tr(
                                                _providerStatus(
                                                    state['boomFi'])))),
                                      if (banking)
                                        ListTile(
                                            title: Text(context.tr('Banking')),
                                            subtitle: Text(context.tr(
                                                _providerStatus(
                                                    state['equalsMoney'])))),
                                      Text(context.tr(
                                          'Each provider reviews your application separately. You can return here to check progress.')),
                                      if (const {
                                            'invite_required',
                                            'payment_required'
                                          }.contains(state['equalsMoney']) ||
                                          state['interlace'] ==
                                              'payment_required') ...[
                                        const SizedBox(height: 16),
                                        FilledButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _request('submit'),
                                            child: const Text(
                                                'Continue activation')),
                                      ],
                                    ],
                                  ],
                                ])))))));
  }
}
