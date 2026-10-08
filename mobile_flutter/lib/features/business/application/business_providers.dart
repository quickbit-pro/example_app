import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../banking/application/banking_providers.dart';

final businessOnboardingStatusProvider =
    FutureProvider<Map<String, dynamic>>((ref) {
  return ref.watch(mobileBankingApiProvider).getBusinessOnboardingStatus();
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

  Future<void> submit({
    required String legalName,
    required String registrationNumber,
    required String country,
    required String activity,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(mobileBankingApiProvider).submitBusinessProfile(
            legalName: legalName,
            registrationNumber: registrationNumber,
            country: country,
            activity: activity,
          ),
    );
    ref.invalidate(dashboardProvider);
    ref.invalidate(onboardingProvider);
    ref.invalidate(businessOnboardingStatusProvider);
  }

  Future<void> submitDirectEqualsBusiness({
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
      final uniquePeople = <Map<String, Object?>>[];
      final uniquePersonIndexes = <String, int>{};
      final rolePersonIndexes = <int>[];
      for (final person in associatedPeople) {
        final identityKey = _associatedPersonIdentityKey(person);
        final uniqueIndex = uniquePersonIndexes.putIfAbsent(identityKey, () {
          uniquePeople.add(person);
          return uniquePeople.length - 1;
        });
        rolePersonIndexes.add(uniqueIndex);
      }
      final peopleResponse =
          await api.createBusinessAssociatedPeople(uniquePeople);
      final createdPeople = _extractCreatedPeople(peopleResponse);
      final personIds = [
        for (final person in createdPeople)
          (person['id'] ?? person['Id'] ?? '').toString(),
      ];

      if (personIds.length != uniquePeople.length ||
          personIds.any((id) => id.isEmpty)) {
        throw StateError('Failed to create EqualsMoney associated people.');
      }

      await api.submitDirectEqualsBusinessApplication({
        ...application,
        'associatedPeople': [
          for (var i = 0; i < associatedPeople.length; i++)
            {
              'associatedPersonId': personIds[rolePersonIndexes[i]],
              'associationType':
                  associatedPeople[i]['associationType']?.toString() ??
                      'APPLICANT',
              if (associatedPeople[i]['jobTitle'] != null)
                'jobTitle': associatedPeople[i]['jobTitle'],
              if (associatedPeople[i]['ownershipPercentage'] != null)
                'ownershipPercentage': associatedPeople[i]
                    ['ownershipPercentage'],
            },
        ],
      });

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

      for (var uniqueIndex = 0; uniqueIndex < personIds.length; uniqueIndex++) {
        BusinessDocumentUpload? identityDocument;
        BusinessDocumentUpload? addressDocument;
        for (var roleIndex = 0;
            roleIndex < rolePersonIndexes.length;
            roleIndex++) {
          if (rolePersonIndexes[roleIndex] != uniqueIndex) continue;
          if (identityDocument == null &&
              roleIndex < identityDocuments.length) {
            identityDocument = identityDocuments[roleIndex];
          }
          if (addressDocument == null && roleIndex < addressDocuments.length) {
            addressDocument = addressDocuments[roleIndex];
          }
        }
        if (identityDocument != null) {
          await api.uploadBusinessOnboardingDocument(
            purpose: 'PROOF_OF_IDENTITY',
            path: identityDocument.path,
            bytes: identityDocument.bytes,
            fileName: identityDocument.name,
            associatedPersonId: personIds[uniqueIndex],
          );
        }
        if (addressDocument != null) {
          await api.uploadBusinessOnboardingDocument(
            purpose: 'PROOF_OF_ADDRESS',
            path: addressDocument.path,
            bytes: addressDocument.bytes,
            fileName: addressDocument.name,
            associatedPersonId: personIds[uniqueIndex],
          );
        }
      }

      // Compliance is completed on the next screen before submission.
    });
    ref.invalidate(dashboardProvider);
    ref.invalidate(onboardingProvider);
    ref.invalidate(businessOnboardingStatusProvider);
  }
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

List<Map<String, dynamic>> _extractCreatedPeople(Map<String, dynamic> json) {
  final value =
      json['associatedPeople'] ?? json['AssociatedPeople'] ?? json['data'];
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  if (json['id'] != null || json['Id'] != null) {
    return [json];
  }

  return const [];
}
