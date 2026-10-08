import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<String?> showAdditionalInformationDialog(
  BuildContext context, {
  required String title,
  String? supportingText,
  String? personName,
  String? personEmail,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _AdditionalInformationDialog(
      title: title,
      supportingText: supportingText,
      personName: personName,
      personEmail: personEmail,
    ),
  );
}

class _AdditionalInformationDialog extends StatefulWidget {
  const _AdditionalInformationDialog({
    required this.title,
    this.supportingText,
    this.personName,
    this.personEmail,
  });

  final String title;
  final String? supportingText;
  final String? personName;
  final String? personEmail;

  @override
  State<_AdditionalInformationDialog> createState() =>
      _AdditionalInformationDialogState();
}

class _AdditionalInformationDialogState
    extends State<_AdditionalInformationDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = [widget.personName, widget.personEmail]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' · ');

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          title: Text(context.tr('Additional information')),
          actions: [
            TextButton(onPressed: _submit, child: Text(context.tr('Submit'))),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            if (person.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(person),
            ],
            if (widget.supportingText?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              Text(widget.supportingText!),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 6,
              maxLines: null,
              maxLength: 1000,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: context.tr('Your answer'),
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
