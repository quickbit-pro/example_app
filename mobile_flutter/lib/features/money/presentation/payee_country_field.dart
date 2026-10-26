import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../wallets/presentation/exchange_reference_data.dart';

/// Geographic selection; the payment provider still validates route eligibility.
class PayeeCountryField extends StatelessWidget {
  const PayeeCountryField(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged});
  final String label, value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => FormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        validator: (v) => exchangeCountries.containsKey(v)
            ? null
            : context.tr('Select a country'),
        builder: (field) => InkWell(
          onTap: () async {
            final selected = await showDialog<String>(
                context: context, builder: (_) => _CountrySearch(title: label));
            if (selected != null && context.mounted) onChanged(selected);
          },
          child: InputDecorator(
            decoration: InputDecoration(
                labelText: label,
                errorText: field.errorText,
                suffixIcon: const Icon(Icons.arrow_drop_down)),
            child: Text(
                exchangeCountries[value] ?? context.tr('Select a country')),
          ),
        ),
      );
}

class _CountrySearch extends StatefulWidget {
  const _CountrySearch({required this.title});
  final String title;
  @override
  State<_CountrySearch> createState() => _CountrySearchState();
}

class _CountrySearchState extends State<_CountrySearch> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final entries = exchangeCountries.entries
        .where((e) =>
            e.value.toLowerCase().contains(query) ||
            e.key.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
            width: 440,
            height: 400,
            child: Column(children: [
              TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                      labelText: context.tr('Search countries'),
                      prefixIcon: const Icon(Icons.search)),
                  onChanged: (v) =>
                      setState(() => query = v.trim().toLowerCase())),
              const SizedBox(height: 8),
              Expanded(
                  child: entries.isEmpty
                      ? Center(child: Text(context.tr('No results')))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (_, index) {
                            final entry = entries[index];
                            return ListTile(
                                title: Text(entry.value),
                                trailing: Text(entry.key),
                                onTap: () => Navigator.pop(context, entry.key));
                          })),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Cancel')))
        ]);
  }
}
