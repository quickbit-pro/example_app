import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// All requirements, evidence purposes and policy versions come from the backend.
/// Kept identical in the three independently released mobile applications.
class EqualsComplianceScreen extends StatefulWidget {
  const EqualsComplianceScreen(
      {required this.load,
      required this.call,
      required this.upload,
      this.uploadPerson,
      this.saveApplication,
      this.pickFile,
      super.key});
  final Future<Map<String, dynamic>> Function() load;
  final Future<Map<String, dynamic>> Function(
      String operation, Map<String, dynamic> body) call;
  final Future<int> Function(String purpose, PlatformFile file) upload;
  final Future<void> Function(
      String personId, String purpose, PlatformFile file)? uploadPerson;
  final Future<void> Function(Map<String, dynamic> application)?
      saveApplication;
  final Future<PlatformFile?> Function()? pickFile;
  @override
  State<EqualsComplianceScreen> createState() => _EqualsComplianceScreenState();
}

class _EqualsComplianceScreenState extends State<EqualsComplianceScreen> {
  Map<String, dynamic> _profile = {},
      _data = {},
      _evaluation = {},
      _application = {};
  List<dynamic> _documents = [];
  List<Map<String, dynamic>> _people = [];
  bool _busy = true;
  String? _error;
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  Map<String, dynamic> get _answers =>
      _data.putIfAbsent('answers', () => <String, dynamic>{})
          as Map<String, dynamic>;
  Map<String, dynamic> _answer(String id) => _answers.putIfAbsent(
          id, () => <String, dynamic>{'text': '', 'documentIds': <int>[]})
      as Map<String, dynamic>;

  Future<void> _load() async {
    try {
      final result = await widget.load();
      _profile = _map(result['profile']);
      _application = _map(result['application']);
      _data = _map(result['data']);
      _data['answers'] = _map(_data['answers']);
      for (final key in (_data['answers'] as Map).keys.toList()) {
        _answers[key] = _map(_answers[key]);
      }
      _documents = result['documents'] as List? ?? [];
      _people = (result['people'] as List? ?? []).map(_map).toList();
      await _evaluate();
    } catch (e) {
      _error = complianceError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _evaluate() async {
    final next =
        await widget.call('requirements', {..._profile, 'compliance': _data});
    _evaluation = next;
    _data['policyVersion'] = next['policyVersion'];
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = complianceError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save({bool complete = false}) async {
    if (complete && !(_form.currentState?.validate() ?? false)) return;
    await _run(() async {
      await widget.call('draft', _data);
      await _evaluate();
      if (complete) {
        if ((_evaluation['errors'] as List? ?? []).isNotEmpty) {
          throw StateError((_evaluation['errors'] as List).join('\n'));
        }
        await widget.call('', _data);
        if (mounted) Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Due diligence progress saved')));
      }
    });
  }

  Future<PlatformFile?> _pickFile() async {
    if (widget.pickFile != null) return widget.pickFile!();
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true);
    return result?.files.single;
  }

  Future<void> _upload(Map<String, dynamic> requirement) async {
    await _run(() async {
      final file = await _pickFile();
      if (file == null) return;
      if (file.size == 0 || file.size > 10 * 1024 * 1024) {
        throw StateError('Choose a file between 1 byte and 10 MB.');
      }
      final id =
          await widget.upload(requirement['documentPurpose'] as String, file);
      if (id <= 0) {
        throw StateError(
            'The upload did not return an evidence reference. Please retry.');
      }
      final answer = _answer(requirement['id'] as String);
      answer['documentIds'] =
          {...(answer['documentIds'] as List? ?? []), id}.toList();
      _documents.add({
        'complianceDocumentId': id,
        'purpose': requirement['documentPurpose'],
        'fileName': file.name
      });
      await widget.call('draft', _data);
    });
  }

  Future<void> _uploadPerson(
      Map<String, dynamic> person, String purpose, String flag) async {
    await _run(() async {
      final file = await _pickFile();
      if (file == null) return;
      if (file.size == 0 || file.size > 10 * 1024 * 1024) {
        throw StateError('Choose a file between 1 byte and 10 MB.');
      }
      await widget.uploadPerson!(
          person['externalId'].toString(), purpose, file);
      for (final p
          in _people.where((p) => p['externalId'] == person['externalId'])) {
        p[flag] = true;
      }
    });
  }

  Widget _boolean(String key, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<bool>(
          initialValue: _data[key] as bool?,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: true, child: Text('Yes')),
            DropdownMenuItem(value: false, child: Text('No'))
          ],
          onChanged: _busy
              ? null
              : (value) {
                  setState(() => _data[key] = value);
                },
          validator: (value) => value == null ? 'Choose yes or no' : null));

  Widget _route(String key, String label, Map<String, String> options) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<String>(
              initialValue: _data[key] as String?,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder()),
              items: options.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() => _data[key] = value);
                    }));

  @override
  Widget build(BuildContext context) {
    final requirements =
        (_evaluation['requirements'] as List? ?? []).map(_map).toList();
    final errors = _evaluation['errors'] as List? ?? [];
    return Scaffold(
        appBar: AppBar(title: const Text('Business due diligence')),
        body: AbsorbPointer(
            absorbing: _busy,
            child: Form(
                key: _form,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  if (_busy) const LinearProgressIndicator(),
                  const Text(
                      'Provide information and evidence for Equals Money to review. Equals Money makes the approval decision.'),
                  const SizedBox(height: 16),
                  if (_error != null)
                    SelectableText(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (_profile.isEmpty && !_busy)
                    TextButton(
                        onPressed: () => _run(_load),
                        child: const Text('Retry loading checklist')),
                  if (_profile.isNotEmpty) ...[
                    Text('Policy: ${_evaluation['policyVersion'] ?? ''}'),
                    if (widget.saveApplication != null)
                      ExpansionTile(
                          title: const Text('Saved business details'),
                          children: [
                            for (final field in const {
                              'website': 'Website (optional)',
                              'businessPromotionDescription':
                                  'How customers find the business',
                              'taxId': 'Business tax ID',
                              'regionOfIncorporation': 'Region of incorporation'
                            }.entries)
                              TextFormField(
                                  initialValue:
                                      _application[field.key]?.toString(),
                                  decoration:
                                      InputDecoration(labelText: field.value),
                                  onChanged: (v) =>
                                      _application[field.key] = v.trim()),
                            TextButton(
                                onPressed: () => _run(() async {
                                      await widget.call('draft', _data);
                                      await widget
                                          .saveApplication!(_application);
                                      await _load();
                                    }),
                                child: const Text(
                                    'Save business details and refresh checklist')),
                          ]),
                    if (_evaluation['requiresDirector'] == true)
                      const Text(
                          'This legal form requires a director in the associated people section.'),
                    if (_evaluation['requiresSoleTraderOwner'] == true)
                      const Text(
                          'The sole trader must be both the authorised applicant and 100% beneficial owner.'),
                    const SizedBox(height: 20),
                    _boolean('isDropshipping',
                        'Does the business use dropshipping?'),
                    _boolean('hasTrustOwnership',
                        'Trust, nominee or fiduciary ownership?'),
                    _boolean('noProhibitedRegionalExposure',
                        'No exposure to prohibited regions?'),
                    const Text(
                        'Include all business, ownership and payment locations. The checklist identifies any restrictions for those locations.'),
                    const SizedBox(height: 16),
                    if (_evaluation['asksOperationalExpenses'] == true)
                      _boolean('operationalExpensesOnly',
                          'Account used only for operational expenses?'),
                    if (_evaluation['asksFundRegulator'] == true)
                      _boolean('fundManagerApprovedRegulator',
                          'Fund manager has an Equals-approved regulator?'),
                    _route('sourceOfFundsRoute',
                        'Source-of-funds evidence', const {
                      'AUDITED': 'Audited financial statements',
                      'BANK_STATEMENTS': 'Bank statements and invoices',
                      'UNAUDITED': 'Unaudited financial statements'
                    }),
                    if ((_profile['website']?.toString() ?? '').trim().isEmpty)
                      _route('noWebsiteEvidenceRoute',
                          'Evidence for a business without a website', const {
                        'BANK_STATEMENTS': 'Three months of bank statements',
                        'INVOICES': 'Purchase and sales invoices'
                      }),
                    TextFormField(
                        initialValue: _data['ownershipExplanation'] as String?,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const InputDecoration(
                            labelText:
                                'Indirect ownership and effective control',
                            helperText:
                                'Name controllers, intermediate entities, voting rights and percentages. Explain any no-UBO case.',
                            helperMaxLines: 3),
                        onChanged: (v) => _data['ownershipExplanation'] = v),
                    const SizedBox(height: 16),
                    OutlinedButton(
                        onPressed: () => _run(_evaluate),
                        child: const Text('Refresh requirements')),
                    for (final error in errors)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(error.toString(),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    _requirement({
                      'id': 'FORMATION',
                      'label':
                          'Proof of formation, registration or equivalent legal-form evidence',
                      'documentPurpose': 'PROOF_OF_FORMATION',
                      'evidenceOnly': true
                    }),
                    if (widget.uploadPerson != null)
                      for (final person in {
                        for (final p in _people) p['externalId']: p
                      }.values)
                        Card(
                            child: Column(children: [
                          ListTile(
                              title: Text(
                                  '${person['firstName']} ${person['lastName']}')),
                          for (final entry in const {
                            'PROOF_OF_IDENTITY': 'identityDocumentUploaded',
                            'PROOF_OF_ADDRESS': 'addressDocumentUploaded'
                          }.entries)
                            ListTile(
                                title: Text(entry.key == 'PROOF_OF_IDENTITY'
                                    ? 'Identity evidence'
                                    : 'Address evidence'),
                                trailing: person[entry.value] == true
                                    ? const Icon(Icons.check_circle)
                                    : TextButton(
                                        onPressed: () => _uploadPerson(
                                            person, entry.key, entry.value),
                                        child: const Text('Upload'))),
                        ])),
                    for (final requirement in requirements)
                      _requirement(requirement),
                    const SizedBox(height: 20),
                    OutlinedButton(
                        onPressed: () => _save(),
                        child: const Text('Save progress')),
                    FilledButton(
                        onPressed: () => _save(complete: true),
                        child: const Text('Save checklist and continue')),
                  ],
                ]))));
  }

  Widget _requirement(Map<String, dynamic> requirement) {
    final id = requirement['id'] as String;
    final answer = _answer(id);
    final notApplicable =
        (answer['notApplicableReason']?.toString() ?? '').isNotEmpty;
    final selected = answer['documentIds'] as List? ?? [];
    final purpose = requirement['documentPurpose'];
    return Card(
        key: ValueKey(id),
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(requirement['label']?.toString() ?? id),
              if (requirement['evidenceOnly'] != true)
                TextFormField(
                    key: ValueKey('$id-text'),
                    initialValue: answer['text']?.toString(),
                    minLines: 2,
                    maxLines: 8,
                    decoration:
                        const InputDecoration(labelText: 'Your response'),
                    onChanged: (v) => answer['text'] = v,
                    validator: (v) =>
                        !notApplicable && (v?.trim().isEmpty ?? true)
                            ? 'Provide a response'
                            : null),
              if (requirement['allowNotApplicable'] == true)
                TextFormField(
                    initialValue: answer['notApplicableReason']?.toString(),
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'If not applicable, explain why'),
                    onChanged: (v) =>
                        setState(() => answer['notApplicableReason'] = v)),
              if (purpose != null) ...[
                for (final doc in _documents
                    .map(_map)
                    .where((d) => d['purpose'] == purpose))
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          doc['fileName']?.toString() ?? 'Uploaded evidence'),
                      value: selected.contains(doc['complianceDocumentId']),
                      onChanged: (checked) => setState(() {
                            answer['documentIds'] = checked == true
                                ? {...selected, doc['complianceDocumentId']}
                                    .toList()
                                : selected
                                    .where(
                                        (v) => v != doc['complianceDocumentId'])
                                    .toList();
                          })),
                TextButton.icon(
                    onPressed: () => _upload(requirement),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload supporting evidence')),
              ],
            ])));
  }
}

String complianceError(Object error) {
  dynamic data = error is DioException ? error.response?.data : null;
  if (data is Map && data['detail'] is String) {
    try {
      final nested = jsonDecode(data['detail'] as String);
      if (nested is Map) data = nested;
    } catch (_) {}
  }
  if (data is Map) {
    final errors = data['errors'] ?? data['validationErrors'];
    if (errors is List && errors.isNotEmpty) return errors.join('\n');
    if (errors is Map) {
      return errors.values.expand((v) => v is List ? v : [v]).join('\n');
    }
    return (data['detail'] ??
            data['message'] ??
            data['error'] ??
            'Could not save due diligence. Please retry.')
        .toString();
  }
  return error.toString().replaceFirst('Bad state: ', '');
}
