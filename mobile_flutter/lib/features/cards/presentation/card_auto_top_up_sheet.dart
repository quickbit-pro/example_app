import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../profile/presentation/security_sheets.dart' show showExampleSheet;
import '../data/card_auto_top_up_api.dart';

Future<void> showCardAutoTopUp(BuildContext context, PaymentCard card) =>
    showExampleSheet<void>(context,
        builder: (_) => CardAutoTopUpSheet(card: card));

class CardAutoTopUpSheet extends ConsumerStatefulWidget {
  const CardAutoTopUpSheet({required this.card, super.key});
  final PaymentCard card;
  @override
  ConsumerState<CardAutoTopUpSheet> createState() => _CardAutoTopUpSheetState();
}

class _CardAutoTopUpSheetState extends ConsumerState<CardAutoTopUpSheet> {
  final _form = GlobalKey<FormState>();
  final _threshold = TextEditingController();
  final _target = TextEditingController();
  final _limit = TextEditingController();
  final _maximum = TextEditingController();
  final _depositAmounts = {
    for (final currency in ['USDC', 'USDT']) currency: TextEditingController()
  };
  final _deposits = {'USDC': false, 'USDT': false};
  Map<String, dynamic>? _settings;
  String _mode = 'low-balance';
  bool _enabled = false, _consent = false, _busy = false;
  String? _error;
  OverlayEntry? _savedToast;
  Timer? _savedToastTimer;
  bool get _enabling =>
      _mode == 'deposit' ? _deposits.values.any((v) => v) : _enabled;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hideSavedToast();
    for (final c in [
      _threshold,
      _target,
      _limit,
      _maximum,
      ..._depositAmounts.values
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _amount(Object? value) {
    final amount = num.tryParse(value?.toString() ?? '') ?? 0;
    return amount > 0 ? amount.toString() : '';
  }

  List<Map> _rows(String key) =>
      (_settings?[key] as List? ?? []).whereType<Map>().toList();
  void _select(String mode) {
    _mode = mode;
    _consent = false;
    _error = null;
    _hideSavedToast();
    final s = _settings!;
    _enabled =
        s[mode == 'low-balance' ? 'lowBalanceEnabled' : 'failedTxEnabled'] ==
            true;
    _threshold.text = _amount(s['watermark']);
    _target.text = _amount(s['targetBalance']);
    _maximum.text = _amount(s['failedTxMaxAmount']);
    _limit.text = _amount(s[mode == 'low-balance'
        ? 'lowBalanceMonthlyLimit'
        : 'failedTxMonthlyLimit']);
    for (final currency in _deposits.keys) {
      final existing = _rows('depositSettings')
          .where((s) => s['currency'] == currency)
          .firstOrNull;
      _deposits[currency] = existing?['enabled'] == true;
      _depositAmounts[currency]!.text = _amount(existing?['maxAmount']);
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings =
          await ref.read(cardAutoTopUpApiProvider).load(widget.card.id);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _select(settings['depositEnabled'] == true
            ? 'deposit'
            : settings['failedTxEnabled'] == true
                ? 'failed-tx'
                : 'low-balance');
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double _value(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_enabling && !_consent) {
      setState(() =>
          _error = 'Accept the automatic top-up authorization to continue.');
      return;
    }
    if (_mode == 'low-balance' &&
        _enabled &&
        _value(_target) <= _value(_threshold)) {
      setState(() => _error =
          'Target balance must be greater than the balance threshold.');
      return;
    }
    final cardId = int.tryParse(widget.card.id);
    if (cardId == null || cardId <= 0) {
      setState(() => _error = 'Automatic top-up is unavailable for this card.');
      return;
    }
    final payload = <String, dynamic>{
      'cardId': cardId,
      'disclaimerAccepted': _enabling && _consent
    };
    if (_mode == 'deposit') {
      payload['settings'] = [
        for (final c in _deposits.keys)
          {
            'currency': c,
            'enabled': _deposits[c],
            'maxAmount': _deposits[c]! ? _value(_depositAmounts[c]!) : 0
          }
      ];
    } else {
      payload.addAll(
          {'enabled': _enabled, 'monthlyLimit': _enabled ? _value(_limit) : 0});
      if (_mode == 'low-balance') {
        payload.addAll({
          'watermark': _enabled ? _value(_threshold) : 0,
          'targetBalance': _enabled ? _value(_target) : 0
        });
      } else {
        payload['maxAmount'] = _enabled ? _value(_maximum) : 0;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _hideSavedToast();
    });
    try {
      final settings =
          await ref.read(cardAutoTopUpApiProvider).save(_mode, payload);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _select(_mode);
      });
      _showSavedToast();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _hideSavedToast() {
    _savedToastTimer?.cancel();
    _savedToastTimer = null;
    _savedToast?.remove();
    _savedToast?.dispose();
    _savedToast = null;
  }

  void _showSavedToast() {
    _hideSavedToast();
    final colors = Theme.of(context).colorScheme;
    final message = context.tr('Automatic top-up settings saved.');
    // The page's ScaffoldMessenger is behind the modal sheet. Put feedback
    // in the root overlay so it stays visible while the settings remain open.
    _savedToast = OverlayEntry(
        builder: (context) => Positioned(
              top: MediaQuery.paddingOf(context).top + 16,
              left: 16,
              right: 16,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Semantics(
                    liveRegion: true,
                    child: Material(
                      color: colors.inverseSurface,
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Text(message,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onInverseSurface)),
                      ),
                    ),
                  ),
                ),
              ),
            ));
    Overlay.of(context, rootOverlay: true).insert(_savedToast!);
    _savedToastTimer = Timer(const Duration(seconds: 3), _hideSavedToast);
  }

  Widget _number(String label, TextEditingController controller,
          {bool active = true}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            controller: controller,
            enabled: !_busy && active,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: context.tr(label)),
            validator: (_) => active &&
                    (_value(controller) <= 0 || !_value(controller).isFinite)
                ? context.tr('Enter an amount greater than zero.')
                : null,
          ));
  String _money(Object? value) => Money.formatAmount(
      'USD', num.tryParse(value?.toString() ?? '')?.toDouble() ?? 0);
  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final active = [
      if (settings?['lowBalanceEnabled'] == true) 'Low balance',
      if (settings?['failedTxEnabled'] == true) 'Failed payment',
      if (settings?['depositEnabled'] == true) 'Crypto deposit'
    ];
    return Form(
        key: _form,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text(context.tr('Auto-Reload'),
                        style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(
                    tooltip: context.tr('Close'),
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ]),
              Text('${widget.card.displayLabel} · ${widget.card.last4}'),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(context.tr(_error!),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (settings == null && !_busy)
                TextButton(
                    onPressed: _load, child: Text(context.tr('Try again'))),
              if (settings != null) ...[
                Text(active.isEmpty
                    ? context.tr('Status: Off')
                    : '${context.tr('Active')}: ${active.map(context.tr).join(', ')}'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    initialValue: _mode,
                    isExpanded: true,
                    decoration:
                        InputDecoration(labelText: context.tr('Trigger')),
                    items: [
                      for (final item in const {
                        'low-balance': 'Low balance',
                        'failed-tx': 'Failed payment',
                        'deposit': 'Crypto deposit'
                      }.entries)
                        DropdownMenuItem(
                            value: item.key,
                            child: Text(context.tr(item.value)))
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _select(value!))),
                const SizedBox(height: 12),
                Text(context.tr(
                    'Uses your existing in-app balance. Applicable card top-up fees apply. Top-ups can fail if funds are insufficient.')),
                const SizedBox(height: 8),
                if (_mode != 'deposit') ...[
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.tr('Enable this trigger')),
                      value: _enabled,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                                _enabled = value;
                                _consent = false;
                              })),
                  if (_mode == 'low-balance') ...[
                    _number('When card balance is below (USD)', _threshold,
                        active: _enabled),
                    _number('Reload up to this balance (USD)', _target,
                        active: _enabled),
                  ] else ...[
                    Text(context.tr(
                        'Adds funds after an insufficient-funds decline. You may need to retry the payment.')),
                    const SizedBox(height: 12),
                    _number('Maximum per top-up (USD)', _maximum,
                        active: _enabled),
                  ],
                  _number('Monthly top-up limit (USD)', _limit,
                      active: _enabled),
                  Text(
                      '${context.tr('Used this month (UTC)')}: ${_money(settings[_mode == 'low-balance' ? 'lowBalanceUsedThisMonth' : 'failedTxUsedThisMonth'])}'),
                ] else ...[
                  Text(context.tr(
                      'Crypto deposit triggers are available for Interlace cards. Each currency can fund one card at a time.')),
                  for (final currency in _deposits.keys) ...[
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(currency),
                        value: _deposits[currency]!,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _deposits[currency] = value;
                                  _consent = false;
                                })),
                    for (final assigned in _rows('assignedDepositCurrencies')
                        .where((a) =>
                            a['currency'] == currency &&
                            a['cardId'].toString() != widget.card.id))
                      Text(context.tr(
                          'Assigned to card {p0}. Disable it on that card before switching.',
                          {
                            'p0': assigned['maskedCardNumber'] ??
                                assigned['cardId']
                          })),
                    _number('Maximum per deposit ($currency)',
                        _depositAmounts[currency]!,
                        active: _deposits[currency]!),
                    Text(
                        '${context.tr('Used this month (UTC)')}: ${Money.formatAmount(currency, num.tryParse(_rows('depositSettings').where((row) => row['currency'] == currency).firstOrNull?['usedThisMonth']?.toString() ?? '')?.toDouble() ?? 0)}'),
                  ],
                ],
                const SizedBox(height: 12),
                if (_enabling) ...[
                  Text(context.tr(
                      'Enabling this trigger turns off the other Auto-Reload triggers on this card.')),
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _consent,
                      onChanged: _busy
                          ? null
                          : (value) =>
                              setState(() => _consent = value ?? false),
                      title: Text(context.tr(
                          'I authorize automatic top-ups from my in-app balance under these limits, including applicable fees.'))),
                ],
                FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(context.tr('Save settings'))),
              ],
            ]));
  }
}
