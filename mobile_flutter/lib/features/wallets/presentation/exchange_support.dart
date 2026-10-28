import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'exchange_reference_data.dart';

Object? exchangeValue(Map map, String key) {
  final snake =
      key.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
  final camel =
      key.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase());
  return map[key] ??
      map[snake] ??
      map[camel] ??
      map['${camel[0].toUpperCase()}${camel.substring(1)}'];
}

String exchangeText(Map map, String key) =>
    exchangeValue(map, key)?.toString() ?? '';
Map<String, dynamic> exchangeMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
Uri? exchangeSafeUrl(String? text) {
  final uri = Uri.tryParse(text ?? '');
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

String? exchangeActionUrl(Object? value) {
  if (value is Map) {
    for (final key in [
      'actionUrl',
      'ActionUrl',
      'action_url',
      'verificationUrl',
      'verification_url',
      'next_action',
      'nextAction',
      'NextAction'
    ]) {
      final text = value[key]?.toString() ?? '';
      final candidate =
          (text.startsWith('kyc_required:') || text.startsWith('kyb_required:')) ? text.substring(13) : text;
      if (exchangeSafeUrl(candidate) != null) return candidate;
    }
    for (final nested in value.values) {
      final url = exchangeActionUrl(nested);
      if (url != null) return url;
    }
  }
  if (value is List) {
    for (final nested in value) {
      final url = exchangeActionUrl(nested);
      if (url != null) return url;
    }
  }
  return null;
}

Future<void> openExchangeUrl(String value) async {
  final uri = exchangeSafeUrl(value);
  if (uri == null ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('Could not open verification. Please retry.');
  }
}

class ExchangeTerms extends StatelessWidget {
  const ExchangeTerms(
      {super.key,
      required this.accepted,
      required this.onChanged,
      this.enabled = true,
      this.withdrawal = false});
  final bool accepted, enabled, withdrawal;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Column(children: [
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: accepted,
            onChanged: enabled ? (v) => onChanged(v == true) : null,
            title: Text(
                'I agree to the ZBX Terms of Business and Risk Disclosure and authorise this ${withdrawal ? 'withdrawal' : 'exchange'}.'),
            controlAffinity: ListTileControlAffinity.leading),
        TextButton(
            onPressed: () => showDialog<void>(
                context: context,
                builder: (context) =>
                    AlertDialog(
                        title:
                            const Text('Crypto Exchange — Terms & Disclosures'),
                        content: const SingleChildScrollView(
                            child: SelectableText(exchangeTerms)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Back'))
                        ])),
            child:
                const Text('View ZBX Terms of Business and Risk Disclosure')),
      ]);
}

class ExchangeCountryField extends StatelessWidget {
  const ExchangeCountryField(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged,
      this.enabled = true,
      this.labelAbove = false});
  final String label, value;
  final ValueChanged<String> onChanged;
  final bool enabled, labelAbove;
  @override
  Widget build(BuildContext context) {
    final field = DropdownButtonFormField<String>(
        initialValue: exchangeCountries.containsKey(value) ? value : null,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
            labelText: labelAbove ? null : label,
            hintText: labelAbove ? 'Select a country' : null),
        items: exchangeCountries.entries
            .map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: enabled ? (v) => onChanged(v ?? '') : null,
        validator: (v) => v == null ? 'Select a country' : null);
    return labelAbove ? ExchangeFieldLabel(label: label, child: field) : field;
  }
}

class ExchangeFieldLabel extends StatelessWidget {
  const ExchangeFieldLabel(
      {super.key, required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child
        ],
      );
}

bool exchangeBankComplete(Map<String, dynamic> bank) {
  final iban = (bank['accountNumber'] ?? '')
      .toString()
      .replaceAll(RegExp(r'\s'), '')
      .toUpperCase();
  if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$').hasMatch(iban)) {
    return false;
  }
  final rearranged = iban.substring(4) + iban.substring(0, 4);
  var remainder = 0;
  for (final code in rearranged.codeUnits) {
    final digits =
        code >= 65 ? (code - 55).toString() : String.fromCharCode(code);
    for (final digit in digits.codeUnits) {
      remainder = (remainder * 10 + digit - 48) % 97;
    }
  }
  if (bank['beneficiaryType'] == 'individual' &&
      ['firstName', 'lastName']
          .any((key) => (bank[key] ?? '').toString().trim().isEmpty)) {
    return false;
  }
  return remainder == 1 &&
      ['name', 'bankName', 'accountHolderName', 'country']
          .every((key) => (bank[key] ?? '').toString().trim().isNotEmpty);
}

class ExchangeBankFields extends StatelessWidget {
  const ExchangeBankFields(
      {super.key,
      required this.value,
      required this.onChanged,
      this.enabled = true});
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => ExchangeBankGrid(children: [
        for (final field in const {
          'name': 'Destination name',
          'accountNumber': 'IBAN',
          'bankName': 'Bank name',
          'accountHolderName': 'Account holder'
        }.entries)
          Padding(
              padding: EdgeInsets.zero,
              child: ExchangeFieldLabel(
                  label: field.value,
                  child: TextFormField(
                      key: ValueKey('bank-${field.key}'),
                      initialValue: value[field.key]?.toString() ?? '',
                      enabled: enabled,
                      decoration: const InputDecoration(),
                      onChanged: (v) => onChanged({
                            ...value,
                            field.key: field.key == 'accountNumber'
                                ? v.replaceAll(RegExp(r'\s'), '').toUpperCase()
                                : v.trim()
                          })))),
        ExchangeCountryField(
            label: 'Bank country',
            labelAbove: true,
            value: value['country']?.toString() ?? '',
            enabled: enabled,
            onChanged: (v) => onChanged({...value, 'country': v})),
        ExchangeFieldLabel(
            label: 'Account holder type',
            child: DropdownButtonFormField<String>(
                initialValue:
                    value['beneficiaryType']?.toString() ?? 'individual',
                decoration: const InputDecoration(),
                items: const [
                  DropdownMenuItem(value: 'business', child: Text('Business')),
                  DropdownMenuItem(
                      value: 'individual', child: Text('Individual'))
                ],
                onChanged: enabled
                    ? (v) => onChanged({...value, 'beneficiaryType': v})
                    : null)),
        if (value['beneficiaryType'] == 'individual') ...[
          for (final field in const {
            'firstName': 'First name',
            'lastName': 'Last name'
          }.entries)
            ExchangeFieldLabel(
                label: field.value,
                child: TextFormField(
                    initialValue: value[field.key]?.toString() ?? '',
                    enabled: enabled,
                    decoration: const InputDecoration(),
                    onChanged: (v) =>
                        onChanged({...value, field.key: v.trim()}))),
        ],
      ]);
}

/// Consistent bounded dialogs with a scrollable body and always-visible actions.
class ExchangeDialog extends StatelessWidget {
  const ExchangeDialog(
      {super.key,
      required this.title,
      required this.child,
      required this.actions,
      this.subtitle,
      this.scrollController,
      this.width = 600});
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final ScrollController? scrollController;
  @override
  Widget build(BuildContext context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: 800),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(subtitle!,
                              style: Theme.of(context).textTheme.bodyMedium)
                        ],
                      ])),
              Flexible(
                  child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: child)),
              const Divider(height: 1),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      overflowSpacing: 8,
                      children: actions)),
            ]),
      ));
}

/// A single compact group for provider fees and limits, with wrapping on mobile.
class ExchangeFeesSummary extends StatelessWidget {
  const ExchangeFeesSummary({required this.title, required this.details, super.key});
  final String title;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(spacing: 16, runSpacing: 4, children: [
            for (final detail in details)
              Text(detail, style: theme.textTheme.bodySmall?.copyWith(height: 1.35)),
          ]),
        ])),
      ]),
    );
  }
}

class ExchangeNotice extends StatelessWidget {
  const ExchangeNotice(this.message, {super.key, this.isError = false});
  final String message;
  final bool isError;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
        liveRegion: true,
        child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: (isError ? colors.error : colors.primary)
                    .withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(isError ? Icons.error_outline : Icons.info_outline,
                  size: 20, color: isError ? colors.error : colors.primary),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(message,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.5))),
            ])));
  }
}

String exchangeNetworkName(Object? chainId) =>
    switch (int.tryParse('$chainId')) {
      0 => 'Bank transfer · SEPA',
      1 => 'Ethereum',
      137 => 'Polygon',
      42161 => 'Arbitrum',
      -200 => 'Tron',
      1399811149 => 'Solana',
      _ => 'Network unavailable',
    };

class ExchangeFormColumn extends StatelessWidget {
  const ExchangeFormColumn({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 20),
              children[i],
            ]
          ]);
}

class ExchangeBankGrid extends StatelessWidget {
  const ExchangeBankGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 500 &&
                MediaQuery.textScalerOf(context).scale(16) <= 20
            ? 2
            : 1;
        return Wrap(spacing: 20, runSpacing: 20, children: [
          for (final child in children)
            SizedBox(
                width: (constraints.maxWidth - (columns - 1) * 20) / columns,
                child: child)
        ]);
      });
}
