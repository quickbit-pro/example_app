import '../../../shared/widgets/equals_fee_schedule.dart';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/tiers_screen.dart'
    show tierIdOf, tierTitleOf;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/dio_provider.dart';
import 'onboarding_stripe.dart';

const personalOnboardingRoot = '/api/v1/mobile/onboarding';
Map<String, dynamic> onboardingObject(dynamic value) {
  if (value is String) value = jsonDecode(value);
  if (value is! Map) throw const FormatException('Invalid onboarding response');
  return value.map((key, value) {
    final name = key.toString();
    return MapEntry(
        name.isEmpty ? name : name[0].toLowerCase() + name.substring(1), value);
  });
}

/// Uses the same invite and payment gates as the dashboard. Only server status unlocks access.
class PersonalOnboardingGate extends ConsumerStatefulWidget {
  const PersonalOnboardingGate(
      {required this.child, this.banking = false, this.onReady, super.key});
  final Widget child;
  final bool banking;
  final VoidCallback? onReady;
  @override
  ConsumerState<PersonalOnboardingGate> createState() =>
      _PersonalOnboardingGateState();
}

class _PersonalOnboardingGateState extends ConsumerState<PersonalOnboardingGate>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _decision;
  Map<String, dynamic>? _invite;
  String? _error;
  bool _busy = false;
  bool _ready = false;
  bool _confirming = false;
  Timer? _timer;
  final _code = TextEditingController();
  String? get _action => _decision?['nextAction']?.toString();
  int? get _gate => _action == 'PAY_GATE_1'
      ? 1
      : (_action == 'PAY_GATE_2' && widget.banking ? 2 : null);
  bool get _inviteRequired =>
      widget.banking && _invite?['inviteRequired'] == true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_refresh);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_ready && !_busy) _refresh();
    });
  }

  @override
  void didUpdateWidget(covariant PersonalOnboardingGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.banking != oldWidget.banking) {
      _ready = false;
      Future.microtask(_refresh);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    await _run(() async {
      final dio = ref.read(dioProvider);
      final decision = onboardingObject(
          (await dio.get('$personalOnboardingRoot/requirements')).data);
      if (decision['nextAction'] is! String) {
        throw const FormatException('Missing onboarding status');
      }
      final invite = widget.banking
          ? onboardingObject(
              (await dio.get('$personalOnboardingRoot/invite')).data)
          : null;
      if (widget.banking && invite?['inviteRequired'] is! bool) {
        throw const FormatException('Missing invite status');
      }
      if (!mounted) return;
      setState(() {
        _decision = decision;
        _invite = invite;
      });
      final ready = _gate == null &&
          !_inviteRequired &&
          (const {
                'START_KYC1',
                'START_KYC2',
                'AWAIT_IBAN',
                'NONE',
                'LEGACY_FLOW'
              }.contains(_action) ||
              (_action == 'PAY_GATE_2' && !widget.banking));
      if (_gate == null) _confirming = false;
      final notify = ready && !_ready;
      setState(() => _ready = ready);
      if (notify) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onReady?.call();
        });
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on DioException catch (error) {
      var message = 'Could not load onboarding requirements. Please try again.';
      try {
        var data = onboardingObject(error.response?.data);
        if (data['detail'] != null) data = onboardingObject(data['detail']);
        final text = data['message'];
        if (text is String &&
            text.length < 400 &&
            !text.contains('{') &&
            !text.contains('<')) {
          message = text;
        }
      } catch (_) {}
      if (mounted) setState(() => _error = message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not complete this step. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteAction(bool verify) async {
    await _run(() async {
      await ref.read(dioProvider).post(
          '$personalOnboardingRoot/invite/${verify ? 'verify' : 'request'}',
          data: verify ? {'code': _code.text} : null);
      _code.clear();
    });
    // Keep validation errors visible until the user edits or refreshes.
    if (_error == null) await _refresh();
  }

  Future<Map<String, dynamic>> _checkout(int gate, bool accepted) async {
    final response = await ref.read(dioProvider).post(
        '$personalOnboardingRoot/gates/$gate/checkout',
        data: {'termsAccepted': accepted},
        options:
            Options(validateStatus: (s) => s != null && (s < 300 || s == 428)));
    return onboardingObject(response.data);
  }

  Future<void> _choosePlan() async {
    await _run(() async {
      final tiers = await ref.read(tiersProvider.future);
      if (!mounted) return;
      final tier = await showDialog<int>(
          context: context,
          builder: (context) => SimpleDialog(
                  title: const Text('Choose your onboarding plan'),
                  children: [
                    for (final tier in tiers)
                      if (tierIdOf(tier) != null)
                        SimpleDialogOption(
                            onPressed: () =>
                                Navigator.pop(context, tierIdOf(tier)),
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(tierTitleOf(tier)))),
                  ]));
      if (tier == null) return;
      await ref
          .read(dioProvider)
          .post('$personalOnboardingRoot/tier', data: {'tierId': tier});
      ref.invalidate(currentTierProvider);
    });
    if (_error == null) await _refresh();
  }

  Future<void> _pay() async {
    final gate = _gate;
    if (gate == null) return;
    await _run(() async {
      var checkout = await _checkout(gate, false);
      if (checkout['error'] == 'PAYMENT_TERMS_REQUIRED') {
        if (checkout['terms'] is! Map || !mounted) {
          throw const FormatException('Missing terms');
        }
        final accepted = await showDialog<bool>(
            context: context, builder: (_) => _TermsDialog(checkout: checkout));
        if (accepted != true || !mounted) return;
        checkout = await _checkout(gate, true);
      }
      if (checkout['status'] == 'completed') return;
      if (checkout['status'] == 'processing') {
        _confirming = true;
        return;
      }
      final key = checkout['publishableKey'];
      final secret = checkout['clientSecret'];
      if (key is! String ||
          !key.startsWith('pk_') ||
          secret is! String ||
          secret.isEmpty) {
        throw const FormatException('Missing payment details');
      }
      if (!mounted) return;
      _confirming = await showOnboardingPayment(context,
          publishableKey: key, clientSecret: secret);
    });
    if (_error == null) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    final inviteStatus = _invite?['inviteStatus'];
    final newCode = _invite?['canRequestNewCode'] == true;
    return Scaffold(
        appBar: AppBar(title: const Text('Complete account setup')),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_busy) const LinearProgressIndicator(),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Text(_error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              if (_gate != null) ...[
                                Text(
                                    _confirming
                                        ? 'Confirming your payment'
                                        : 'Onboarding payment',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                const SizedBox(height: 16),
                                Text(_confirming
                                    ? 'We are waiting for payment confirmation. You do not need to pay again.'
                                    : 'Review the fee and payment terms for your selected plan, then pay securely with Stripe.'),
                                const SizedBox(height: 24),
                                if (!_confirming)
                                  FilledButton(
                                      onPressed: _busy ? null : _pay,
                                      child: const Text('Review payment')),
                                const EqualsFeeScheduleButton(),
                              ] else if (_inviteRequired) ...[
                                Text('Equals Money banking invite',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                const SizedBox(height: 16),
                                if (inviteStatus == 'pending')
                                  const Text(
                                      'Your invite request is waiting for administrator approval. Your code will arrive by email.')
                                else if (inviteStatus == 'denied')
                                  const Text(
                                      'Your invite request was declined. Contact support for help.')
                                else if (inviteStatus == 'approved' &&
                                    !newCode) ...[
                                  const Text(
                                      'Enter the 8-character invite code from your email.'),
                                  const SizedBox(height: 16),
                                  TextField(
                                      controller: _code,
                                      enabled: !_busy,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      autofillHints: const [
                                        AutofillHints.oneTimeCode
                                      ],
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                            RegExp('[a-zA-Z0-9]')),
                                        LengthLimitingTextInputFormatter(8)
                                      ],
                                      onChanged: (_) => setState(() {}),
                                      decoration: const InputDecoration(
                                          labelText: 'Invite code')),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                      onPressed: _busy || _code.text.length != 8
                                          ? null
                                          : () => _inviteAction(true),
                                      child: const Text('Verify invite code')),
                                ] else ...[
                                  Text(newCode
                                      ? 'Your code expired or reached its attempt limit. Request a new code.'
                                      : 'Banking is available by invitation. Request access to continue.'),
                                  const SizedBox(height: 24),
                                  FilledButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _inviteAction(false),
                                      child: Text(newCode
                                          ? 'Request new code'
                                          : 'Request invite')),
                                ],
                              ] else if (_action == 'SELECT_TIER') ...[
                                const Text(
                                    'Choose a plan to continue onboarding.'),
                                FilledButton(
                                    onPressed: _busy ? null : _choosePlan,
                                    child: const Text('Choose plan')),
                              ] else if (_action == 'VERIFY_EMAIL')
                                const Text(
                                    'Verify your email address before continuing.')
                              else if (_action == 'CONTACT_SUPPORT')
                                const Text(
                                    'Your application needs a review. Contact support to continue.'),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                  onPressed: _busy ? null : _refresh,
                                  child: const Text('Check status')),
                            ]))))));
  }
}

class _TermsDialog extends StatefulWidget {
  const _TermsDialog({required this.checkout});
  final Map<String, dynamic> checkout;
  @override
  State<_TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<_TermsDialog> {
  bool _accepted = false;
  @override
  Widget build(BuildContext context) {
    final terms = onboardingObject(widget.checkout['terms']);
    final url = Uri.tryParse(terms['termsUrl']?.toString() ?? '');
    return AlertDialog(
        title: Text('${terms['title'] ?? 'Payment terms'}'),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      '${widget.checkout['amount']} ${widget.checkout['currency']}',
                      style: Theme.of(context).textTheme.titleLarge),
                  if (widget.checkout['description'] != null)
                    Text('${widget.checkout['description']}'),
                  const SizedBox(height: 16),
                  Text('${terms['intro'] ?? ''}'),
                  if (terms['secondaryIntro'] != null)
                    Text('${terms['secondaryIntro']}'),
                  for (final item in terms['items'] as List? ?? [])
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('• $item')),
                  if (url?.scheme == 'https')
                    TextButton(
                        onPressed: () => launchUrl(url!,
                            mode: LaunchMode.externalApplication),
                        child: const Text('Read payment terms')),
                  CheckboxListTile(
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v == true),
                      title: Text(
                          '${terms['checkboxLabel'] ?? 'I accept these payment terms'}')),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _accepted ? () => Navigator.pop(context, true) : null,
              child: const Text('Continue to payment')),
        ]);
  }
}
