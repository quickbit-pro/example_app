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
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${result['title'] ?? 'Recipient name check'}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${result['message'] ?? 'Check the recipient details.'}'),
            if (result['actualName'] is String &&
                (result['actualName'] as String).isNotEmpty)
              Text('Account holder name: ${result['actualName']}'),
            if (needsAcknowledgement(result)) ...[
              const SizedBox(height: 8),
              const Text(
                  'Sending money to incorrect account details could result in loss of funds. Check the details with the recipient using a trusted contact method.'),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: acknowledged,
                  onChanged: result['canProceed'] == false
                      ? null
                      : (value) => onChanged(value == true),
                  title: const Text(
                      'I have checked the recipient details and understand the risk of continuing.')),
            ],
          ])));
}
