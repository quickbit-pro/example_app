import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class PayeeNameCheck extends StatelessWidget {
  const PayeeNameCheck(
      {required this.result,
      required this.acknowledged,
      required this.onChanged,
      super.key});
  final Map<String, dynamic> result;
  final bool acknowledged;
  final ValueChanged<bool> onChanged;
  static bool needsAcknowledgement(Map<String, dynamic> result) =>
      result['requiresAcknowledgement'] == true ||
      result['status'] == 'warning';
  String get outcome => switch (result['reasonCode']) {
        'N200' || 'N206' || 'N207' => 'close_match',
        'N201' || 'N204' || 'N205' => 'no_match',
        _ => result['outcome']?.toString() ?? '',
      };

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                switch (outcome) {
                  'close_match' => context.tr('Close name match'),
                  'no_match' => context.tr('Recipient name does not match'),
                  'unavailable' => context.tr('Name check unavailable'),
                  _ => result['title']?.toString() ?? context.tr('Recipient name check'),
                },
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(switch (outcome) {
              'close_match' =>
                context.tr('The name you entered is similar to the name held by the recipient’s bank.'),
              'no_match' =>
                context.tr('The name you entered does not match the name held by the recipient’s bank.'),
              'unavailable' => context.tr('We couldn’t check the recipient’s name.'),
              _ =>
                result['message']?.toString() ?? context.tr('Check the recipient details.'),
            }),
            if (result['actualName'] is String &&
                (result['actualName'] as String).isNotEmpty)
              Text(context.tr('Account holder name: {p0}', {'p0': result['actualName']})),
            if (needsAcknowledgement(result)) ...[
              const SizedBox(height: 8),
              Text(
                  context.tr('Sending money to incorrect account details could result in loss of funds. Check the details with the recipient using a trusted contact method.')),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: acknowledged,
                  onChanged: result['canProceed'] == false
                      ? null
                      : (value) => onChanged(value == true),
                  title: Text(
                      context.tr('I have checked the recipient details and understand the risk of continuing.'))),
            ],
          ])));
}
