class PlatformResource {
  const PlatformResource({
    required this.id,
    required this.title,
    required this.subtitle,
    this.metadata = const {},
  });

  factory PlatformResource.fromJson(Map<String, dynamic> json) {
    final firstName = _firstText(json, const ['firstName', 'FirstName']);
    final lastName = _firstText(json, const ['lastName', 'LastName']);
    final composedName = [firstName, lastName]
        .where((part) => part != null && part.trim().isNotEmpty)
        .join(' ');
    final address = _firstText(json, const [
      'address',
      'Address',
      'depositAddress',
      'DepositAddress',
      'walletAddress',
      'WalletAddress',
      'cryptoAddress',
      'CryptoAddress',
      'destinationAddress',
      'DestinationAddress',
      'publicAddress',
      'PublicAddress',
      'blockchainAddress',
      'BlockchainAddress',
    ]);
    final currency = _firstText(json, const [
      'currency',
      'Currency',
      'asset',
      'Asset',
      'assetCode',
      'AssetCode',
      'currencyCode',
      'CurrencyCode',
      'token',
      'Token',
      'tokenSymbol',
      'TokenSymbol',
    ]);
    final network = _firstText(json, const [
      'network',
      'Network',
      'chain',
      'Chain',
      'blockchain',
      'Blockchain',
      'blockchainNetwork',
      'BlockchainNetwork',
    ]);
    final id = json['id'] ??
        json['Id'] ??
        json['tierId'] ??
        json['TierId'] ??
        json['selectedTierId'] ??
        json['SelectedTierId'] ??
        json['cardTierId'] ??
        json['CardTierId'] ??
        json['uuid'] ??
        json['Uuid'] ??
        json['reference'] ??
        json['Reference'] ??
        json['accountId'] ??
        json['AccountId'] ??
        json['walletId'] ??
        json['WalletId'] ??
        json['assetId'] ??
        json['AssetId'] ??
        json['addressId'] ??
        json['AddressId'] ??
        json['BalanceId'];
    final explicitTitle = _firstText(json, const [
      'title',
      'Title',
      'tierName',
      'TierName',
      'nickname',
      'Nickname',
      'name',
      'Name',
      'fullName',
      'FullName',
      'displayName',
      'DisplayName',
      'holderName',
      'HolderName',
      'customer',
      'Customer',
      'customerName',
      'CustomerName',
      'merchant',
      'Merchant',
      'merchantName',
      'MerchantName',
      'recipient',
      'Recipient',
      'counterparty',
      'Counterparty',
      'businessName',
      'BusinessName',
      'companyName',
      'CompanyName',
      'label',
      'Label',
    ]);
    final title = explicitTitle ??
        (composedName.isEmpty ? null : composedName) ??
        currency ??
        network ??
        _firstText(json, const ['type', 'Type', 'status', 'Status']);
    final subtitle = address ??
        _firstText(json, const [
          'subtitle',
          'Subtitle',
          'description',
          'Description',
          'availableBalance',
          'AvailableBalance',
          'available',
          'Available',
          'balance',
          'Balance',
          'iban',
          'Iban',
          'accountNumber',
          'AccountNumber',
          'state',
          'State',
          'status',
          'Status',
          'provider',
          'Provider',
          'network',
          'Network',
        ]);

    return PlatformResource(
      id: (id ?? title ?? 'item').toString(),
      title: (title ?? id ?? 'Item').toString(),
      subtitle: (subtitle ?? '').toString(),
      metadata: json,
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final Map<String, dynamic> metadata;
}

List<PlatformResource> depositAddressesFromWallets(
  Iterable<PlatformResource> wallets,
) {
  final addresses = <PlatformResource>[];
  for (final wallet in wallets) {
    _appendWalletAddressResources(addresses, wallet);
  }

  return addresses;
}

List<PlatformResource> mergeDepositAddressResources(
  Iterable<PlatformResource> primary,
  Iterable<PlatformResource> secondary,
) {
  final merged = <PlatformResource>[];
  final seen = <String>{};

  for (final resource in [...primary, ...secondary]) {
    if (!hasCompleteDepositAddress(resource)) {
      continue;
    }
    final key = _depositAddressResourceKey(resource);
    if (key == null || seen.add(key)) {
      merged.add(resource);
    }
  }

  return merged;
}

String? _firstText(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];

    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }

  return null;
}

bool hasCompleteDepositAddress(PlatformResource resource) {
  final address = _firstText(resource.metadata, _addressValueKeys);
  final asset = _firstText(resource.metadata, _assetKeys);
  final network = _firstText(resource.metadata, _networkKeys);

  return address != null && asset != null && network != null;
}

void _appendWalletAddressResources(
  List<PlatformResource> addresses,
  PlatformResource wallet,
) {
  final metadata = wallet.metadata;

  if (_firstText(metadata, _addressValueKeys) != null) {
    _appendWalletAddressResource(addresses, wallet, metadata);
  }

  for (final key in _addressContainerKeys) {
    _appendAddressValue(addresses, wallet, metadata[key], impliedKey: null);
  }
}

void _appendAddressValue(
  List<PlatformResource> addresses,
  PlatformResource wallet,
  Object? value, {
  String? impliedKey,
}) {
  if (value == null) {
    return;
  }

  if (value is List) {
    for (final item in value) {
      _appendAddressValue(addresses, wallet, item, impliedKey: impliedKey);
    }
    return;
  }

  if (value is Map<String, dynamic>) {
    if (_firstText(value, _addressValueKeys) != null) {
      _appendWalletAddressResource(
        addresses,
        wallet,
        impliedKey == null ? value : _withImpliedAddressKey(value, impliedKey),
      );
      return;
    }

    for (final entry in value.entries) {
      _appendAddressValue(
        addresses,
        wallet,
        entry.value,
        impliedKey: entry.key,
      );
    }
    return;
  }

  if (value is Map) {
    _appendAddressValue(
      addresses,
      wallet,
      value.map((key, item) => MapEntry(key.toString(), item)),
      impliedKey: impliedKey,
    );
    return;
  }

  if (value is! String || !_canUseImpliedNetworkAddress(impliedKey)) {
    return;
  }

  final text = value.trim();
  if (text.isEmpty) {
    return;
  }

  _appendWalletAddressResource(
    addresses,
    wallet,
    {
      'address': text,
      if (impliedKey != null) 'network': impliedKey,
    },
  );
}

void _appendWalletAddressResource(
  List<PlatformResource> addresses,
  PlatformResource wallet,
  Map<String, dynamic> address,
) {
  final resource = _walletAddressResource(wallet, address);
  if (hasCompleteDepositAddress(resource)) {
    addresses.add(resource);
  }
}

Map<String, dynamic> _withImpliedAddressKey(
  Map<String, dynamic> json,
  String impliedKey,
) {
  return {
    ...json,
    if (_firstText(json, _networkKeys) == null) 'network': impliedKey,
  };
}

PlatformResource _walletAddressResource(
  PlatformResource wallet,
  Map<String, dynamic> address,
) {
  final walletMetadata = wallet.metadata;
  final normalized = <String, dynamic>{
    ...address,
    'walletId': _firstText(walletMetadata, _walletIdKeys) ?? wallet.id,
    if (_firstText(walletMetadata, const ['accountId', 'AccountId']) != null)
      'accountId': _firstText(walletMetadata, const ['accountId', 'AccountId']),
    if (_firstText(walletMetadata, const ['nickname', 'Nickname']) != null)
      'walletNickname':
          _firstText(walletMetadata, const ['nickname', 'Nickname']),
    if (_firstText(address, _assetKeys) == null &&
        _firstText(walletMetadata, _assetKeys) != null)
      'currency': _firstText(walletMetadata, _assetKeys),
    if (_firstText(address, _networkKeys) == null &&
        _firstText(walletMetadata, _networkKeys) != null)
      'network': _firstText(walletMetadata, _networkKeys),
  };

  normalized['id'] ??= _firstText(normalized, _addressIdKeys) ??
      [
        normalized['walletId'],
        _firstText(normalized, _assetKeys),
        _firstText(normalized, _networkKeys),
        _firstText(normalized, _addressValueKeys),
      ].where((part) => part != null && part.toString().trim().isNotEmpty).join(
            ':',
          );
  normalized['source'] ??= 'wallet';

  return PlatformResource.fromJson(normalized);
}

bool _canUseImpliedNetworkAddress(String? impliedKey) {
  final key = impliedKey?.trim();
  if (key == null || key.isEmpty) {
    return false;
  }

  final normalized = key.toLowerCase();
  const metadataKeys = {
    ..._addressValueKeys,
    ..._addressIdKeys,
    ..._assetKeys,
    ..._networkKeys,
    ..._walletIdKeys,
    'accountid',
    'nickname',
    'selected',
    'enabled',
    'active',
    'status',
    'state',
    'type',
  };

  return !metadataKeys.map((item) => item.toLowerCase()).contains(normalized);
}

String? _depositAddressResourceKey(PlatformResource resource) {
  final address = _firstText(resource.metadata, _addressValueKeys);
  final asset = _firstText(resource.metadata, _assetKeys);
  final id = _firstText(resource.metadata, _addressIdKeys) ??
      (address == null ? resource.id : null);
  final parts = [address, asset]
      .where((part) => part != null && part.trim().isNotEmpty)
      .map((part) => part!.trim().toLowerCase())
      .toList();

  if (parts.isNotEmpty) {
    return parts.join('|');
  }

  return id?.trim().toLowerCase();
}

const _addressContainerKeys = [
  'addresses',
  'Addresses',
  'depositAddresses',
  'DepositAddresses',
  'cryptoAddresses',
  'CryptoAddresses',
  'walletAddresses',
  'WalletAddresses',
  'addressList',
  'AddressList',
];

const _addressValueKeys = [
  'address',
  'Address',
  'depositAddress',
  'DepositAddress',
  'walletAddress',
  'WalletAddress',
  'cryptoAddress',
  'CryptoAddress',
  'publicAddress',
  'PublicAddress',
  'blockchainAddress',
  'BlockchainAddress',
];

const _addressIdKeys = [
  'addressId',
  'AddressId',
  'depositAddressId',
  'DepositAddressId',
  'walletAddressId',
  'WalletAddressId',
];

const _assetKeys = [
  'asset',
  'Asset',
  'assetCode',
  'AssetCode',
  'currency',
  'Currency',
  'currencyCode',
  'CurrencyCode',
  'token',
  'Token',
  'tokenSymbol',
  'TokenSymbol',
];

const _networkKeys = [
  'network',
  'Network',
  'chain',
  'Chain',
  'blockchain',
  'Blockchain',
  'blockchainNetwork',
  'BlockchainNetwork',
  'protocol',
  'Protocol',
];

const _walletIdKeys = [
  'id',
  'Id',
  'walletId',
  'WalletId',
];

class ActionResult {
  const ActionResult({
    required this.message,
    this.reference,
    this.metadata = const {},
  });

  factory ActionResult.fromJson(Map<String, dynamic>? json, String fallback) {
    if (json == null || json.isEmpty) {
      return ActionResult(message: fallback);
    }

    final message = _firstNonEmptyValue(
          json,
          const ['message', 'Message', 'status', 'Status', 'state', 'State'],
        ) ??
        fallback;
    final reference =
        json['id'] ?? json['reference'] ?? json['requestId'] ?? json['url'];

    return ActionResult(
      message: message,
      reference: reference?.toString(),
      metadata: json,
    );
  }

  final String message;
  final String? reference;
  final Map<String, dynamic> metadata;
}

String? _firstNonEmptyValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
  }

  return null;
}

class KycDetailedStatus {
  const KycDetailedStatus({
    required this.hoppaStatus,
    required this.bankStatus,
    required this.cardIssuerStatus,
    required this.nextAction,
    this.interlaceKycApproved = false,
    this.interlaceRequiredAction,
    this.interlaceReason,
    this.interlaceResubmissionDocSets = const [],
    this.equalsMoneyAccountId,
    this.equalsMoneyApplicationStatus,
    this.equalsMoneyStatus,
    this.equalsMoneyRequiredAction,
    this.equalsMoneyActionUrl,
    this.equalsMoneyApproved,
    this.equalsMoneyExternalId,
    this.equalsMoneyApplicationId,
    this.equalsMoneyAdditionalDocumentsRequested = const [],
  });

  factory KycDetailedStatus.fromJson(Map<String, dynamic> json) {
    final hoppaApproved = _asBool(json['HoppaCardKycApproved']) ??
        _asBool(json['hoppaCardKycApproved']);
    final cardIssuerApproved = _asBool(json['CardIssuerKycApproved']) ??
        _asBool(json['cardIssuerKycApproved']);
    final interlace = _asMap(json['Interlace'] ?? json['interlace']);
    final interlaceAction = interlace == null
        ? null
        : _firstNonEmptyValue(
            interlace, const ['RequiredAction', 'requiredAction']);
    final needsDocuments =
        interlaceAction?.trim().toUpperCase() == 'RESUBMIT_DOCUMENTS';
    final interlaceReason = interlace == null
        ? null
        : _firstNonEmptyValue(interlace, const ['Reason', 'reason']);
    final rawDocSets =
        interlace?['ResubmissionDocSets'] ?? interlace?['resubmissionDocSets'];
    final equalsMoney = _asMap(json['EqualsMoney'] ?? json['equalsMoney']);
    final equalsMoneyApproved = equalsMoney == null
        ? null
        : _asBool(equalsMoney['Approved'] ?? equalsMoney['approved']);
    final equalsMoneyAccountId = equalsMoney == null
        ? null
        : _firstNonEmptyValue(equalsMoney, const [
            'AccountId',
            'accountId',
          ]);
    final equalsMoneyExternalId = equalsMoney == null
        ? null
        : _firstNonEmptyValue(equalsMoney, const [
            'ExternalId',
            'externalId',
          ]);
    final equalsMoneyApplicationId = equalsMoney == null
        ? null
        : _firstNonEmptyValue(equalsMoney, const [
            'ApplicationId',
            'applicationId',
          ]);
    final equalsMoneyApplicationStatus = equalsMoney == null
        ? null
        : _firstNonEmptyValue(equalsMoney, const [
            'ApplicationStatus',
            'applicationStatus',
          ]);
    final equalsMoneyStatus = equalsMoney == null
        ? null
        : _firstNonEmptyValue(equalsMoney, const [
            'Status',
            'status',
          ]);
    final equalsMoneyRequiredAction = equalsMoney == null
        ? null
        : _firstNonEmptyValue(equalsMoney, const [
            'RequiredAction',
            'requiredAction',
          ]);

    return KycDetailedStatus(
      interlaceKycApproved: (interlaceAction?.trim().isEmpty ?? true) &&
          _asBool(interlace?['Approved'] ?? interlace?['approved']) != false &&
          (interlace?['Status'] ?? interlace?['status'])
                  ?.toString()
                  .trim()
                  .toLowerCase() ==
              'approved',
      hoppaStatus: needsDocuments
          ? 'action_required'
          : _identityStatus(
              hoppaApproved,
              json['hoppaStatus'] ??
                  json['hoppacardStatus'] ??
                  json['HoppaCardStatus'],
            ),
      bankStatus: _statusFromApproved(
        equalsMoneyApproved,
        json['bankStatus'] ??
            json['BankStatus'] ??
            equalsMoney?['Status'] ??
            equalsMoney?['status'] ??
            equalsMoney?['ApplicationStatus'] ??
            equalsMoney?['applicationStatus'],
      ),
      cardIssuerStatus: interlaceAction != null
          ? 'action_required'
          : _statusFromApproved(
              cardIssuerApproved,
              json['cardIssuerStatus'] ??
                  json['issuerStatus'] ??
                  json['CardIssuerStatus'] ??
                  interlace?['Status'] ??
                  interlace?['status'],
            ),
      nextAction: ((interlaceAction != null ? interlaceReason : null) ??
              (needsDocuments
                  ? 'Upload the requested replacement documents.'
                  : null) ??
              json['nextAction'] ??
              json['requiredAction'] ??
              equalsMoneyRequiredAction ??
              (hoppaApproved == true ? 'KYC approved' : 'Complete KYC'))
          .toString(),
      interlaceRequiredAction: interlaceAction,
      interlaceReason: interlaceReason,
      interlaceResubmissionDocSets: rawDocSets is List
          ? rawDocSets.whereType<String>().toList(growable: false)
          : const [],
      equalsMoneyAccountId: equalsMoneyAccountId,
      equalsMoneyApplicationStatus: equalsMoneyApplicationStatus,
      equalsMoneyStatus: equalsMoneyStatus,
      equalsMoneyRequiredAction: equalsMoneyRequiredAction,
      equalsMoneyActionUrl: equalsMoney == null
          ? null
          : _firstNonEmptyValue(equalsMoney, const [
              'ActionUrl',
              'actionUrl',
            ]),
      equalsMoneyApproved: equalsMoneyApproved,
      equalsMoneyExternalId: equalsMoneyExternalId,
      equalsMoneyApplicationId: equalsMoneyApplicationId,
      equalsMoneyAdditionalDocumentsRequested: equalsMoney == null
          ? const []
          : _equalsMoneyAdditionalDocuments(equalsMoney),
    );
  }

  final String hoppaStatus;
  final String bankStatus;
  final String cardIssuerStatus;
  final bool interlaceKycApproved;
  final String nextAction;
  final String? interlaceRequiredAction;
  final String? interlaceReason;
  final List<String> interlaceResubmissionDocSets;

  bool get requiresDocumentResubmission =>
      interlaceRequiredAction?.trim().toUpperCase() == 'RESUBMIT_DOCUMENTS';
  bool get hasInterlaceAction =>
      interlaceRequiredAction?.trim().isNotEmpty ?? false;

  final String? equalsMoneyAccountId;
  final String? equalsMoneyApplicationStatus;
  final String? equalsMoneyStatus;
  final String? equalsMoneyRequiredAction;
  final String? equalsMoneyActionUrl;
  final bool? equalsMoneyApproved;
  final String? equalsMoneyExternalId;
  final String? equalsMoneyApplicationId;
  final List<EqualsMoneyAdditionalDocumentRequest>
      equalsMoneyAdditionalDocumentsRequested;

  bool get isHoppaApproved =>
      !requiresDocumentResubmission && _isReadyProviderStatus(hoppaStatus);

  bool get isBankApproved => canUseEqualsMoneyBanking;

  bool get isCardIssuerApproved =>
      !hasInterlaceAction && _isReadyProviderStatus(cardIssuerStatus);

  bool get hasEqualsMoneyAccount =>
      equalsMoneyAccountId != null && equalsMoneyAccountId!.trim().isNotEmpty;

  bool get hasEqualsMoneyActionUrl =>
      equalsMoneyActionUrl != null && equalsMoneyActionUrl!.trim().isNotEmpty;

  bool get hasEqualsMoneyApplication =>
      equalsMoneyApplicationId != null &&
      equalsMoneyApplicationId!.trim().isNotEmpty;

  bool get hasEqualsMoneyExternalReference =>
      equalsMoneyExternalId != null && equalsMoneyExternalId!.trim().isNotEmpty;

  bool get hasEqualsMoneyReviewState =>
      hasEqualsMoneyApplication ||
      hasEqualsMoneyExternalReference ||
      equalsMoneyApproved == true ||
      _isReviewProviderStatus(equalsMoneyStatus) ||
      (equalsMoneyApplicationStatus != null &&
          _isReviewProviderStatus(equalsMoneyApplicationStatus));

  bool get requiresEqualsMoneyAction =>
      hasEqualsMoneyActionUrl ||
      (equalsMoneyRequiredAction != null &&
          equalsMoneyRequiredAction!.trim().isNotEmpty) ||
      equalsMoneyAdditionalDocumentsRequested.isNotEmpty;

  bool get isEqualsMoneyOnboarded =>
      !requiresEqualsMoneyAction &&
      (hasEqualsMoneyAccount ||
          equalsMoneyApproved == true ||
          (equalsMoneyApproved == null &&
              (_isReadyProviderStatus(equalsMoneyStatus) ||
                  _isReadyProviderStatus(equalsMoneyApplicationStatus))));

  bool get canUseEqualsMoneyBanking =>
      isEqualsMoneyOnboarded && !requiresEqualsMoneyAction;

  int get completedSetupStepCount => [
        isHoppaApproved,
        canUseEqualsMoneyBanking,
        isCardIssuerApproved,
      ].where((isComplete) => isComplete).length;

  int get setupStepCount => 3;
}

class EqualsMoneyAdditionalDocumentRequest {
  const EqualsMoneyAdditionalDocumentRequest({
    required this.type,
    required this.text,
    this.expectedResponseType = 'file',
    this.additionalInformation,
    this.applicationId,
    this.informationRequestId,
    this.associatedPersonId,
    this.associatedPersonName,
    this.associatedPersonEmail,
    this.requestedAt,
  });

  factory EqualsMoneyAdditionalDocumentRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    final type = _firstNonEmptyValue(json, const ['type', 'Type']) ?? 'OTHER';
    return EqualsMoneyAdditionalDocumentRequest(
      type: type,
      text: _firstNonEmptyValue(json, const ['text', 'Text']) ??
          type.replaceAll('_', ' '),
      expectedResponseType: _firstNonEmptyValue(json, const [
            'expectedResponseType',
            'ExpectedResponseType',
          ]) ??
          'file',
      additionalInformation: _firstNonEmptyValue(json, const [
        'additionalInformation',
        'AdditionalInformation',
      ]),
      applicationId: _firstNonEmptyValue(json, const [
        'applicationId',
        'ApplicationId',
      ]),
      informationRequestId: _firstNonEmptyValue(json, const [
        'informationRequestId',
        'InformationRequestId',
      ]),
      associatedPersonId: _firstNonEmptyValue(json, const [
        'associatedPersonId',
        'AssociatedPersonId',
      ]),
      associatedPersonName: _firstNonEmptyValue(json, const [
        'associatedPersonName',
        'AssociatedPersonName',
        'personName',
        'PersonName',
      ]),
      associatedPersonEmail: _firstNonEmptyValue(json, const [
        'associatedPersonEmail',
        'AssociatedPersonEmail',
        'personEmail',
        'PersonEmail',
      ]),
      requestedAt: _firstNonEmptyValue(json, const [
        'requestedAt',
        'RequestedAt',
      ]),
    );
  }

  final String type;
  final String text;
  final String expectedResponseType;
  final String? additionalInformation;
  final String? applicationId;
  final String? informationRequestId;
  final String? associatedPersonId;
  final String? associatedPersonName;
  final String? associatedPersonEmail;
  final String? requestedAt;

  bool get expectsFiles => expectedResponseType.trim().toLowerCase() == 'file';
}

class TransactionStatusSummary {
  const TransactionStatusSummary({
    required this.totalCount,
    required this.completedCount,
    required this.pendingCount,
    required this.failedCount,
  });

  factory TransactionStatusSummary.fromJson(Map<String, dynamic> json) {
    return TransactionStatusSummary(
      totalCount: _asInt(json['totalCount'] ?? json['total']),
      completedCount: _asInt(json['completedCount'] ?? json['completed']),
      pendingCount: _asInt(json['pendingCount'] ?? json['pending']),
      failedCount: _asInt(json['failedCount'] ?? json['failed']),
    );
  }

  final int totalCount;
  final int completedCount;
  final int pendingCount;
  final int failedCount;
}

class QuantumTopUpEstimate {
  const QuantumTopUpEstimate({
    required this.success,
    required this.usdAmount,
    this.message,
    this.usdt,
    this.usdc,
    this.topUpFee,
    this.topUpFeePercent,
  });

  factory QuantumTopUpEstimate.fromJson(Map<String, dynamic> json) {
    return QuantumTopUpEstimate(
      success: _asBool(json['success'] ?? json['Success']) ?? true,
      message: (json['message'] ?? json['Message'])?.toString(),
      usdAmount: _asDouble(json['usdAmount'] ?? json['UsdAmount']),
      usdt: QuantumTopUpQuote.fromAny(
        json['usdt'] ?? json['USDT'] ?? json['usdToUsdt'] ?? json['UsdToUsdt'],
      ),
      usdc: QuantumTopUpQuote.fromAny(
        json['usdc'] ?? json['USDC'] ?? json['usdToUsdc'] ?? json['UsdToUsdc'],
      ),
      topUpFee: _asDoubleOrNull(
        json['topupfee'] ??
            json['topUpFee'] ??
            json['Topupfee'] ??
            json['TopUpFee'],
      ),
      topUpFeePercent: _asDoubleOrNull(
        json['topupfeepercent'] ??
            json['topUpFeePercent'] ??
            json['Topupfeepercent'] ??
            json['TopUpFeePercent'],
      ),
    );
  }

  final bool success;
  final String? message;
  final double usdAmount;
  final QuantumTopUpQuote? usdt;
  final QuantumTopUpQuote? usdc;
  final double? topUpFee;
  final double? topUpFeePercent;

  QuantumTopUpQuote? quoteFor(String currency) {
    switch (currency.trim().toUpperCase()) {
      case 'USDT':
        return usdt;
      case 'USDC':
        return usdc;
      default:
        return null;
    }
  }
}

class QuantumTopUpQuote {
  const QuantumTopUpQuote({
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.baseAmount,
    required this.rfqAmount,
    required this.rfqCurrency,
    required this.fee,
    required this.rate,
    required this.quoteId,
    required this.quoteTime,
    this.feeCurrency,
    this.ttlMs = 0,
  });

  factory QuantumTopUpQuote.fromJson(Map<String, dynamic> json) {
    return QuantumTopUpQuote(
      baseCurrency:
          (json['baseCurrency'] ?? json['BaseCurrency'])?.toString() ?? '',
      quoteCurrency:
          (json['quoteCurrency'] ?? json['QuoteCurrency'])?.toString() ?? '',
      baseAmount: _asDouble(json['baseAmount'] ?? json['BaseAmount']),
      rfqAmount: _asDouble(json['rfqAmount'] ?? json['RfqAmount']),
      rfqCurrency:
          (json['rfqCurrency'] ?? json['RfqCurrency'])?.toString() ?? '',
      fee: _asDouble(json['fee'] ?? json['Fee']),
      feeCurrency: (json['feeCurrency'] ?? json['FeeCurrency'])?.toString(),
      rate: _asDouble(json['rate'] ?? json['Rate']),
      quoteId: (json['quoteId'] ?? json['QuoteId'])?.toString() ?? '',
      quoteTime: (json['quoteTime'] ?? json['QuoteTime'])?.toString() ?? '',
      ttlMs: _asInt(json['ttlMs'] ?? json['TtlMs']),
    );
  }

  static QuantumTopUpQuote? fromAny(Object? value) {
    final map = _asMap(value);
    return map == null ? null : QuantumTopUpQuote.fromJson(map);
  }

  final String baseCurrency;
  final String quoteCurrency;
  final double baseAmount;
  final double rfqAmount;
  final String rfqCurrency;
  final double fee;
  final String? feeCurrency;
  final double rate;
  final String quoteId;
  final String quoteTime;
  final int ttlMs;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }

  return 0;
}

double _asDouble(Object? value) {
  return _asDoubleOrNull(value) ?? 0;
}

double? _asDoubleOrNull(Object? value) {
  if (value is int) {
    return value.toDouble();
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }

  return null;
}

bool? _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }

  return null;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  return null;
}

List<EqualsMoneyAdditionalDocumentRequest> _equalsMoneyAdditionalDocuments(
  Map<String, dynamic> equalsMoney,
) {
  final raw = equalsMoney['additionalDocumentsRequested'] ??
      equalsMoney['AdditionalDocumentsRequested'];
  if (raw is! List) {
    return const [];
  }

  return raw
      .map(_asMap)
      .whereType<Map<String, dynamic>>()
      .map(EqualsMoneyAdditionalDocumentRequest.fromJson)
      .toList(growable: false);
}

String _identityStatus(bool? approved, Object? fallback) {
  // An explicit negative identity decision overrides stale status text.
  if (approved == false && _isReadyProviderStatus(fallback?.toString())) {
    return 'pending';
  }
  return _statusFromApproved(approved, fallback);
}

String _statusFromApproved(bool? approved, Object? fallback) {
  if (approved == true) {
    return 'approved';
  }
  if (approved == false && fallback == null) {
    return 'pending';
  }

  return fallback?.toString() ?? 'pending';
}

bool _isReadyProviderStatus(String? value) {
  final normalized = value?.toLowerCase().replaceAll('_', '-').trim();
  return normalized == 'approved' ||
      normalized == 'verified' ||
      normalized == 'complete' ||
      normalized == 'completed' ||
      normalized == 'active' ||
      normalized == 'ready';
}

bool _isReviewProviderStatus(String? value) {
  final normalized = value?.toLowerCase().replaceAll('_', '-').trim();
  return normalized == 'submitted' ||
      normalized == 'pending' ||
      normalized == 'review' ||
      normalized == 'in-review' ||
      normalized == 'waiting' ||
      normalized == 'wait-for-review';
}
