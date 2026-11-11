import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/auth_token_provider.dart';
import '../../banking/application/banking_providers.dart';
import 'business_draft.dart';

final businessWorkflowProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  ref.watch(authSessionGenerationProvider);
  return ref.watch(mobileBankingApiProvider).getBusinessWorkflow();
});

final businessOnboardingStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.watch(mobileBankingApiProvider);
  final workflow = await ref.watch(businessWorkflowProvider.future);
  final state = workflow['state'];
  try {
    if (state == 'SUBMITTED') {
      final status = await api.getBusinessOnboardingStatus();
      return {
        ...status,
        'status': status['status'] ?? status['Status'] ?? 'SUBMITTED',
      };
    }
    if (state == 'DRAFT' || state == 'INFORMATION_REQUIRED') {
      final draft = await api.getBusinessCompliance();
      if (draft['application'] is Map) {
        return {'status': 'DRAFT'};
      }
      throw StateError('The saved business details could not be read.');
    }
  } on DioException catch (error) {
    if (error.response?.statusCode != 404) rethrow;
    if (state == 'SUBMITTED') return {'status': 'SUBMITTED'};
  }
  return const {};
});

final businessOnboardingOptionsProvider =
    FutureProvider<BusinessOnboardingOptions>((ref) async {
  final json =
      await ref.watch(mobileBankingApiProvider).getBusinessOnboardingOptions();
  return BusinessOnboardingOptions.fromJson(json);
});

class BusinessOnboardingOption {
  const BusinessOnboardingOption({required this.key, required this.label});

  final String key;
  final String label;

  factory BusinessOnboardingOption.fromJson(Map<String, dynamic> json) {
    final key = (json['key'] ?? json['Key'] ?? '').toString().trim();
    final label = (json['value'] ?? json['Value'] ?? key).toString().trim();
    return BusinessOnboardingOption(
        key: key, label: label.isEmpty ? key : label);
  }
}

class BusinessIndustryOption extends BusinessOnboardingOption {
  const BusinessIndustryOption({
    required super.key,
    required super.label,
    required this.subIndustries,
  });

  final List<BusinessOnboardingOption> subIndustries;

  factory BusinessIndustryOption.fromJson(Map<String, dynamic> json) {
    final option = BusinessOnboardingOption.fromJson(json);
    final rawSubIndustries =
        json['subIndustries'] ?? json['SubIndustries'] ?? const [];
    return BusinessIndustryOption(
      key: option.key,
      label: option.label,
      subIndustries: _optionList(rawSubIndustries),
    );
  }
}

class BusinessOnboardingOptions {
  const BusinessOnboardingOptions({required this.industries});

  final List<BusinessIndustryOption> industries;

  factory BusinessOnboardingOptions.fromJson(Map<String, dynamic> json) {
    final payload = _unwrapOptions(json);
    final rawIndustries =
        payload['industries'] ?? payload['Industries'] ?? const [];
    final industries = rawIndustries is List
        ? rawIndustries
            .whereType<Map>()
            .map((item) => BusinessIndustryOption.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .where((item) => item.key.isNotEmpty)
            .toList(growable: false)
        : const <BusinessIndustryOption>[];
    return BusinessOnboardingOptions(industries: industries);
  }
}

Map<String, dynamic> _unwrapOptions(Map<String, dynamic> json) {
  for (final key in const ['data', 'Data', 'result', 'Result']) {
    final nested = json[key];
    if (nested is Map) {
      return nested.map((key, value) => MapEntry(key.toString(), value));
    }
  }
  return json;
}

List<BusinessOnboardingOption> _optionList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => BusinessOnboardingOption.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ))
      .where((item) => item.key.isNotEmpty)
      .toList(growable: false);
}

final businessFormControllerProvider =
    AsyncNotifierProvider<BusinessFormController, void>(
  BusinessFormController.new,
);

class BusinessDocumentUpload {
  const BusinessDocumentUpload({
    required this.name,
    this.path,
    this.bytes,
  });

  final String name;
  final String? path;
  final Uint8List? bytes;
}

class BusinessFormController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> saveDraftAndEvidence({
    required List<Map<String, Object?>> associatedPeople,
    required Map<String, Object?> application,
    BusinessDocumentUpload? proofOfFormation,
    BusinessDocumentUpload? proofOfOwnership,
    List<BusinessDocumentUpload?> identityDocuments = const [],
    List<BusinessDocumentUpload?> addressDocuments = const [],
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(mobileBankingApiProvider);
      final draft = await api.saveBusinessDraft(
        localBusinessDraft(application, associatedPeople),
      );
      final people = draft['associatedPeople'] ?? draft['AssociatedPeople'];
      if (people is! List || people.length != associatedPeople.length) {
        throw StateError('The draft did not return all saved people.');
      }
      final personIds = [
        for (final person in people.whereType<Map>())
          (person['id'] ?? person['Id'] ?? '').toString(),
      ];
      if (personIds.length != associatedPeople.length ||
          personIds.any((id) => id.isEmpty) ||
          personIds.toSet().length != personIds.length) {
        throw StateError('The draft did not return valid person references.');
      }

      if (proofOfFormation != null) {
        await api.uploadBusinessOnboardingDocument(
          purpose: 'PROOF_OF_FORMATION',
          path: proofOfFormation.path,
          bytes: proofOfFormation.bytes,
          fileName: proofOfFormation.name,
        );
      }
      if (proofOfOwnership != null) {
        await api.uploadBusinessOnboardingDocument(
          purpose: 'PROOF_OF_OWNERSHIP_STRUCTURE',
          path: proofOfOwnership.path,
          bytes: proofOfOwnership.bytes,
          fileName: proofOfOwnership.name,
        );
      }

      final identities =
          associatedPeople.map(_associatedPersonIdentityKey).toList();
      final identityEvidence =
          _evidenceByIdentity(identities, identityDocuments);
      final addressEvidence = _evidenceByIdentity(identities, addressDocuments);
      for (var index = 0; index < personIds.length; index++) {
        final identityDocument = identityEvidence[identities[index]];
        final addressDocument = addressEvidence[identities[index]];
        if (identityDocument != null) {
          await api.uploadBusinessOnboardingDocument(
            purpose: 'PROOF_OF_IDENTITY',
            path: identityDocument.path,
            bytes: identityDocument.bytes,
            fileName: identityDocument.name,
            associatedPersonId: personIds[index],
          );
        }
        if (addressDocument != null) {
          await api.uploadBusinessOnboardingDocument(
            purpose: 'PROOF_OF_ADDRESS',
            path: addressDocument.path,
            bytes: addressDocument.bytes,
            fileName: addressDocument.name,
            associatedPersonId: personIds[index],
          );
        }
      }
    });
    ref.invalidate(dashboardProvider);
    ref.invalidate(onboardingProvider);
    ref.invalidate(businessOnboardingStatusProvider);
  }
}

// A person holding multiple roles has one draft record per role.
Map<String, BusinessDocumentUpload> _evidenceByIdentity(
  List<String> identities,
  List<BusinessDocumentUpload?> evidence,
) {
  final result = <String, BusinessDocumentUpload>{};
  for (var index = 0;
      index < identities.length && index < evidence.length;
      index++) {
    final document = evidence[index];
    if (document != null) {
      result.putIfAbsent(identities[index], () => document);
    }
  }
  return result;
}

String _associatedPersonIdentityKey(Map<String, Object?> person) {
  String normalized(String key) =>
      person[key]?.toString().trim().toLowerCase() ?? '';
  return [
    normalized('firstName'),
    normalized('lastName'),
    normalized('dateOfBirth'),
    normalized('emailAddress'),
  ].join('|');
}
