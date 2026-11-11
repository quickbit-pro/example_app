/// Convert the existing business form into the reviewed local KYB contract.
Map<String, dynamic> localBusinessDraft(
    Map<String, Object?> app, List<Map<String, Object?>> people) {
  Map<String, dynamic> address(Map value) => {
        'addressLine1': value['streetName'],
        'addressLine2': value['buildingName'],
        'buildingNumber': value['buildingNumber'],
        'city': value['city'],
        'region': value['region'],
        'postcode': value['postcode'],
        'country': value['countryCode'],
      };
  final addresses = (app['addresses'] as List? ?? []).cast<Map>();
  final registered =
      addresses.where((a) => a['addressType'] == 'REGISTERED').firstOrNull;
  final trading =
      addresses.where((a) => a['addressType'] == 'TRADING').firstOrNull;
  final applicant =
      people.where((p) => p['associationType'] == 'APPLICANT').firstOrNull;
  if (registered == null || applicant == null) {
    throw StateError('Registered address and applicant are required.');
  }
  return {
    'businessType': app['type'],
    'registeredName': app['registeredName'],
    'tradingName': (app['tradingNames'] as List? ?? []).firstOrNull,
    'registrationNumber': app['registrationNumber'],
    'countryOfIncorporation': app['countryOfIncorporation'],
    'regionOfIncorporation': app['regionOfIncorporation'],
    'incorporationDate': app['incorporationDate'],
    'businessOverview': app['businessOverview'],
    'industry': app['industry'],
    'employeeCount': app['employeeCount'],
    'website': app['website'],
    'taxId': app['taxId'],
    'promotionDescription': app['businessPromotionDescription'],
    'registeredAddress': address(registered),
    if (trading != null) 'tradingAddress': address(trading),
    'featureInformation': app['featureInformation'],
    'contactEmail': applicant['emailAddress'],
    'contactPhone': app['phoneNumber'] ?? applicant['phoneNumber'],
    'associatedPeople': people.map((p) {
      final residences = (p['addresses'] as List? ?? []).cast<Map>();
      final nationalities = p['nationalities'] as List? ?? [];
      return {
        'associationType': p['associationType'],
        'firstName': p['firstName'],
        'middleName': p['middleName'],
        'lastName': p['lastName'],
        'email': p['emailAddress'],
        'phoneNumber': p['phoneNumber'],
        'dob': p['dateOfBirth'],
        'nationality': nationalities.firstOrNull,
        'nationalities': nationalities,
        'taxId': p['taxId'],
        'jobTitle': p['jobTitle'],
        'ownershipPercentage': p['ownershipPercentage'],
        'isPrimaryApplicant': p['associationType'] == 'APPLICANT',
        if (residences.isNotEmpty) 'address': address(residences.first),
      };
    }).toList(),
  };
}
