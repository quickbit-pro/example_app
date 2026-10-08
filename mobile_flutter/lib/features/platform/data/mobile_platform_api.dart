import '../../../core/models/upload_document.dart';
import 'package:dio/dio.dart';

import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../rewards/domain/rewards_models.dart';
import '../../rewards/domain/referral_community.dart';
import '../../rewards/domain/referral_lifecycle.dart';
import '../../rewards/domain/referral_member_status.dart';
import '../../signup/domain/referral_quote.dart';
import '../../wallets/domain/exchange_models.dart';
import '../../wallets/domain/withdrawal_models.dart';
import '../../dashboard/domain/market_rates.dart';
import '../../dashboard/domain/dashboard_models.dart';
import '../../cards/domain/card_control_capabilities.dart';
import '../../cards/domain/card_limits.dart';

class MobilePlatformApi {
  const MobilePlatformApi(this._dio);

  final Dio _dio;

  Future<ActionResult> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String accountType,
    String? phone,
    String? referralCode,
    String? referralSource,
    String? invitationToken,
    Map<String, dynamic>? legalAgreements,
    bool? referralAccepted,
    int? referralTermsVersion,
    String? registrationAttemptId,
    String? referralQuoteId,
    String? referralTermsHash,
    String? referralPolicyHash,
    bool referralNeedsReview = false,
    String? installationToken,
  }) {
    return _postAction(
      '/api/v1/mobile/auth/signup',
      {
        'email': email,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
        'accountType': accountType,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (referralCode != null && referralCode.trim().isNotEmpty)
          'referralCode': referralCode.trim(),
        if (referralSource != null && referralSource.trim().isNotEmpty)
          'referralSource': referralSource.trim(),
        if (invitationToken != null && invitationToken.isNotEmpty)
          'invitationToken': invitationToken,
        if (legalAgreements != null) 'legalAgreements': legalAgreements,
        if (referralAccepted != null) 'referralAccepted': referralAccepted,
        if (referralTermsVersion != null)
          'referralTermsVersion': referralTermsVersion,
        if (registrationAttemptId != null)
          'registrationAttemptId': registrationAttemptId,
        if (referralQuoteId != null) 'referralQuoteId': referralQuoteId,
        if (referralTermsHash != null) 'referralTermsHash': referralTermsHash,
        if (referralPolicyHash != null)
          'referralPolicyHash': referralPolicyHash,
        if (referralNeedsReview) 'referralNeedsReview': true,
        if (installationToken != null) 'installationToken': installationToken,
      },
      'Account created',
    );
  }

  Future<ReferralQuote> getReferralQuote(
      {required String registrationAttemptId,
      required String referralCode,
      required String source,
      String? invitationToken,
      required String locale}) async {
    final response = await _dio.post<dynamic>(
        '/api/v1/mobile/auth/referral-quote',
        data: {
          'registrationAttemptId': registrationAttemptId,
          'referralCode': referralCode.trim(),
          'source': source,
          'locale': locale,
          if (invitationToken != null) 'invitationToken': invitationToken
        },
        options: Options(
            extra: const {'skipAuthRefresh': true, 'sensitiveRequest': true}));
    final quote =
        ReferralQuote.fromJson(_mapFromAny(response.data) ?? const {});
    if (quote.registrationAttemptId != registrationAttemptId) {
      throw const FormatException(
          'Referral offer belongs to a different signup');
    }
    return quote;
  }

  Future<ReferralSignupOutcome?> getReferralAttributionOutcome() async {
    final response =
        await _dio.get<dynamic>('/api/v1/mobile/auth/referral-attribution');
    final data = _mapFromAny(response.data) ?? const {};
    final status = data['status'] ?? data['Status'];
    if (status == 'NOT_REQUESTED') return null;
    return ReferralSignupOutcome.fromJson(
        {...data, 'referralAttributionStatus': status});
  }

  Future<ReferralGeoStatus> getReferralGeoStatus() async =>
      ReferralGeoStatus.fromJson(
          await _getMap('/api/v1/mobile/rewards/referrals/geo-eligibility'));

  Future<ReferralLevelLifecycle> getReferralLevelLifecycle(
      {String? programId}) async {
    final response = await _dio.get<dynamic>(
        '/api/v1/mobile/rewards/referrals/level-lifecycle',
        queryParameters: {if (programId != null) 'programId': programId});
    return ReferralLevelLifecycle.fromJson(
        _mapFromAny(response.data) ?? const {});
  }

  Future<ReferralLevelHistory> getReferralLevelHistory(
      {String? programId, int page = 1}) async {
    final response = await _dio.get<dynamic>(
        '/api/v1/mobile/rewards/referrals/level-history',
        queryParameters: {
          if (programId != null) 'programId': programId,
          'page': page,
          'pageSize': 25
        });
    return ReferralLevelHistory.fromJson(
        _mapFromAny(response.data) ?? const {});
  }

  /// What a referral code promises before the account exists: the inviter's
  /// display name, the welcome reward and the terms version to echo back.
  /// Null when the code is unknown or the backend does not serve the check
  /// (older builds validate the code at registration only).
  Future<ReferralWelcome?> checkReferralCode(String referralCode) async {
    final code = referralCode.trim();
    if (code.isEmpty) return null;
    try {
      final response = await _dio.get<dynamic>(
        '/api/v1/mobile/auth/check-referral',
        queryParameters: {'referralCode': code},
        options: Options(
          extra: const {'skipAuthRefresh': true, 'sensitiveRequest': true},
        ),
      );
      final payload = _mapFromAny(response.data);
      if (payload == null || payload.isEmpty) return null;
      final welcome = ReferralWelcome.fromJson(payload);
      return welcome.valid ? welcome : null;
    } on DioException catch (error) {
      // A paused, expired or archived campaign link is a clear answer the
      // sign-up screen shows; every other failure reads as "unknown code".
      if (error.response?.statusCode == 400 &&
          isReferralCampaignLinkInactive(error.response?.data)) {
        return const ReferralWelcome.inactiveCampaignLink();
      }
      return null;
    }
  }

  Future<MobileTenantConfig> getMobileConfig() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/config',
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
    return MobileTenantConfig.fromJson(response.data ?? const {});
  }

  Future<MarketRateTable> getMarketRates({String baseCurrency = 'USD'}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/market-data/rates',
      queryParameters: {'baseCurrency': baseCurrency.trim().toUpperCase()},
    );
    return MarketRateTable.fromJson(response.data ?? const {});
  }

  Future<PortfolioEstimate> getPortfolioEstimate({
    String currency = 'USD',
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/portfolio/summary',
      queryParameters: {'currency': currency.trim().toUpperCase()},
    );
    return PortfolioEstimate.fromJson(response.data ?? const {});
  }

  Future<Map<String, dynamic>> getReferralSummary() =>
      _getMap('/api/v1/mobile/rewards/referrals/summary');

  Future<ReferralCommunity> getReferralCommunity({String? programId}) async =>
      ReferralCommunity.fromJson(await _getMap(
        '/api/v1/mobile/rewards/referrals/community',
        queryParameters: {if (programId != null) 'programId': programId},
      ));

  Future<List<ReferralCommunityEarning>> getReferralCommunityEarnings(
          {String? programId, int page = 1}) async =>
      (await _getRows(
        '/api/v1/mobile/rewards/referrals/community/earnings',
        queryParameters: {
          if (programId != null) 'programId': programId,
          'page': page,
          'pageSize': 25,
        },
      ))
          .map(ReferralCommunityEarning.fromJson)
          .toList();

  /// The caller's reward ledger, newest first, by stage.
  Future<List<ReferralReward>> getReferralRewards({
    String? programId,
    int page = 1,
    int pageSize = 50,
  }) async {
    final rows = await _getRows(
      '/api/v1/mobile/rewards/referrals/rewards',
      queryParameters: {
        if (programId != null && programId.isNotEmpty) 'programId': programId,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return rows.map(ReferralReward.fromJson).toList();
  }

  /// The caller's referred friends with their stage and per-friend earnings.
  Future<List<ReferralFriend>> getReferralFriends({
    String? programId,
    int page = 1,
    int pageSize = 50,
  }) async {
    final rows = await _getRows(
      '/api/v1/mobile/rewards/referrals/friends',
      queryParameters: {
        if (programId != null && programId.isNotEmpty) 'programId': programId,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return rows.map(ReferralFriend.fromJson).toList();
  }

  /// The caller's referral analytics for a period: the conversion journey,
  /// totals, weekly buckets and top friends. An explicit [from]/[to] (UTC,
  /// [to] exclusive, at most 366 days) wins over [range]. A backend that
  /// does not serve the resource answers 404; the provider treats that as
  /// "no analytics", never as a failure.
  Future<ReferralMemberAnalytics> getReferralMemberAnalytics({
    String? programId,
    ReferralAnalyticsRange range = ReferralAnalyticsRange.thirtyDays,
    DateTime? from,
    DateTime? to,
  }) async {
    final response = await _dio.get<dynamic>(
      '/api/v1/mobile/rewards/referrals/analytics',
      queryParameters: {
        if (programId != null && programId.isNotEmpty) 'programId': programId,
        'range': range.wire,
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      },
    );
    return ReferralMemberAnalytics.fromJson(
      _mapFromAny(response.data) ?? const {},
    );
  }

  /// Accepts the programme terms at [termsVersion]; the summary then carries
  /// the referral code and link.
  Future<ActionResult> acceptReferralTerms(int termsVersion) => _postAction(
        '/api/v1/mobile/rewards/referrals/terms-acceptance',
        {'termsVersion': termsVersion},
        'Terms accepted',
      );

  Future<ActionResult> sendReferralInvitation({
    required String email,
    String? name,
  }) =>
      _postAction(
        '/api/v1/mobile/rewards/referrals/invitations',
        {
          'recipientEmail': email.trim(),
          if (name != null && name.trim().isNotEmpty)
            'recipientName': name.trim(),
        },
        'Invitation sent',
      );

  // ---- campaign links (contract 2026-09-15) ----

  /// The caller's own campaign links. A backend that does not serve the
  /// resource answers 404; the provider treats that as "not deployed".
  Future<List<ReferralCampaignLink>> getReferralCampaignLinks({
    String? programId,
    ReferralCampaignLinkStatus? status,
  }) async {
    final rows = await _getRows(
      '/api/v1/mobile/rewards/referrals/links',
      queryParameters: {
        if (programId != null && programId.isNotEmpty) 'programId': programId,
        if (status != null && status.wire.isNotEmpty) 'status': status.wire,
      },
    );
    return rows.map(ReferralCampaignLink.fromJson).toList();
  }

  /// Creates a link; the platform generates the code unless one was given
  /// and answers the link as created.
  Future<ReferralCampaignLink> createReferralCampaignLink(
    ReferralCampaignLinkDraft draft,
  ) async {
    final payload = await _postMap(
      '/api/v1/mobile/rewards/referrals/links',
      draft.toJson(),
    );
    return ReferralCampaignLink.fromJson(payload);
  }

  /// Pauses, resumes, archives or renames a link. Code and destination are
  /// immutable; [clearExpiry] removes the expiry.
  Future<ReferralCampaignLink> updateReferralCampaignLink(
    String linkId, {
    ReferralCampaignLinkStatus? status,
    String? name,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) async {
    final response = await _dio.patch<dynamic>(
      '/api/v1/mobile/rewards/referrals/links/${Uri.encodeComponent(linkId)}',
      data: {
        if (status != null && status.wire.isNotEmpty) 'status': status.wire,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
        if (clearExpiry) 'clearExpiresAt': true,
      },
    );
    return ReferralCampaignLink.fromJson(
        _mapFromAny(response.data) ?? const {});
  }

  /// Tells the platform a visitor opened the sign-up page with campaign
  /// [code] (addendum A). Anonymous, like the referral check, and
  /// fire-and-forget: a click is telemetry, so every failure — an older
  /// backend, a paused link, no network — is swallowed and nothing here
  /// can hold up a sign-up. [visitorId] is the app's per-install id so the
  /// platform counts one unique visitor per day.
  Future<void> recordCampaignLinkClick(
    String code, {
    required String visitorId,
    String? locale,
  }) async {
    final normalized = code.trim();
    if (normalized.isEmpty) return;
    try {
      await _dio.post<dynamic>(
        '/api/v1/mobile/rewards/referrals/links/${Uri.encodeComponent(normalized)}/clicks',
        data: {
          'visitorId': visitorId,
          if (locale != null && locale.trim().isNotEmpty)
            'locale': locale.trim(),
        },
        options: Options(
          extra: const {'skipAuthRefresh': true, 'sensitiveRequest': true},
        ),
      );
    } catch (_) {
      // Never surfaced: see above.
    }
  }

  /// What one link brought in over [range].
  Future<ReferralCampaignLinkPerformance> getReferralCampaignLinkPerformance(
    String linkId, {
    ReferralAnalyticsRange range = ReferralAnalyticsRange.thirtyDays,
  }) async {
    final response = await _dio.get<dynamic>(
      '/api/v1/mobile/rewards/referrals/links/${Uri.encodeComponent(linkId)}/performance',
      queryParameters: {'range': range.wire},
    );
    return ReferralCampaignLinkPerformance.fromJson(
      _mapFromAny(response.data) ?? const {},
    );
  }

  Future<List<Map<String, dynamic>>> getAssignedReferralVouchers() async {
    final response = await _dio.get<dynamic>(
      '/api/v1/mobile/rewards/referrals/vouchers',
    );
    final payload = response.data;
    if (payload is List) {
      return payload
          .map(_mapFromAny)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> getVoucherStatus() =>
      _getMap('/api/v1/mobile/rewards/vouchers/status');

  Future<BoomFiExchangeOverview> getExchangeOverview() async =>
      BoomFiExchangeOverview.fromJson(
        await _getMap('/api/v1/mobile/exchange/overview'),
      );

  Future<List<BoomFiTransfer>> getExchangeTransfers() async {
    final response =
        await _dio.get<dynamic>('/api/v1/mobile/exchange/transfers');
    final payload = response.data;
    if (payload is! List) return const [];
    return payload
        .map(_mapFromAny)
        .whereType<Map<String, dynamic>>()
        .map(BoomFiTransfer.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> getExchangeQuote({
    required BoomFiExchangeBalance source,
    required BoomFiExchangeBalance destination,
    required String sellAmount,
  }) =>
      _postMap('/api/v1/mobile/exchange/quote', {
        'sellCurrency': source.currency,
        'buyCurrency': destination.currency,
        'sellAmount': sellAmount,
        'depositAccountId': source.accountId,
        'settlementAccountId': destination.accountId,
        if (source.chainId != 0) 'sellChainId': source.chainId,
        if (source.tokenAddress.isNotEmpty)
          'sellTokenAddress': source.tokenAddress,
        if (destination.chainId != 0) 'buyChainId': destination.chainId,
        if (destination.tokenAddress.isNotEmpty)
          'buyTokenAddress': destination.tokenAddress,
      });

  Future<ActionResult> acceptExchangeQuote(String quoteId) => _postAction(
        '/api/v1/mobile/exchange/quote/accept',
        {'quoteId': quoteId},
        'Exchange submitted',
      );

  Future<ActionResult> decideExchangeTransfer(int id, String decision) =>
      _postAction(
        '/api/v1/mobile/exchange/transfers/$id/decision',
        {'decision': decision},
        'Transfer updated',
      );

  Future<Map<String, dynamic>> getInterlaceToEqualsQuote(
          Map<String, Object?> request) =>
      _postMap('/api/v1/mobile/exchange/interlace-to-equals/quote', request);

  Future<Map<String, dynamic>> initiateInterlaceToEquals(
          Map<String, Object?> request) =>
      _postMap('/api/v1/mobile/exchange/interlace-to-equals/initiate', request);

  Future<ActionResult> confirmInterlaceToEquals({
    required String verificationToken,
    required String otpCode,
  }) =>
      _postAction(
        '/api/v1/mobile/exchange/interlace-to-equals/confirm',
        {'verificationToken': verificationToken, 'otpCode': otpCode},
        'Transfer submitted',
      );

  Future<ActionResult> createEqualsToInterlace({
    required String idempotencyKey,
    required String budgetId,
    required String fiatCurrency,
    required double amount,
  }) =>
      _postAction(
        '/api/v1/mobile/exchange/equals-to-interlace',
        {
          'idempotencyKey': idempotencyKey,
          'budgetId': budgetId,
          'fiatCurrency': fiatCurrency,
          'amount': amount,
        },
        'Transfer submitted',
      );

  Future<ActionResult> validateVoucher(String code) => _postAction(
        '/api/v1/mobile/rewards/vouchers/validate',
        {'code': code.trim()},
        'Voucher validated',
      );

  Future<ActionResult> redeemVoucher(String code) => _postAction(
        '/api/v1/mobile/rewards/vouchers/redeem',
        {'code': code.trim()},
        'Voucher redemption started',
      );

  Future<ActionResult> redeemAssignedVoucher(String assignmentId) =>
      _postAction(
        '/api/v1/mobile/rewards/referrals/vouchers/${Uri.encodeComponent(assignmentId)}/redeem',
        const {},
        'Voucher redemption started',
      );

  Future<ActionResult> redeemAllAssignedVouchers() => _postAction(
        '/api/v1/mobile/rewards/referrals/vouchers/redeem-all',
        const {},
        'Voucher redemptions started',
      );

  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? nickname,
  }) async {
    return _withFallback(
      () async {
        final response = await _dio.put<Map<String, dynamic>>(
          '/api/v1/mobile/profile',
          data: {
            if (name != null) 'name': name,
            if (email != null) 'email': email,
            if (nickname != null) 'nickname': nickname,
          },
        );

        return UserProfile.fromJson(response.data ?? const {});
      },
      () => UserProfile.fromJson({
        'id': 'usr_1001',
        'name': name,
        'email': email,
        'nickname': nickname,
        'kycStatus': 'pending',
        'businessStatus': 'not_started',
      }),
    );
  }

  Future<KycDetailedStatus> getDetailedKycStatus() async {
    return _withFallback(
      () async {
        Response<Map<String, dynamic>> response;
        try {
          response = await _dio.get<Map<String, dynamic>>(
            '/api/v1/mobile/kyc/detailed-status',
          );
        } on DioException catch (error) {
          if (error.response?.statusCode != 404) {
            rethrow;
          }
          response = await _dio.get<Map<String, dynamic>>(
            '/api/v1/mobile/kyc/status',
          );
        }

        return KycDetailedStatus.fromJson(response.data ?? const {});
      },
      () => const KycDetailedStatus(
        hoppaStatus: 'pending',
        bankStatus: 'not_started',
        cardIssuerStatus: 'not_started',
        nextAction: 'Start SumSub verification',
      ),
    );
  }

  Future<ActionResult> verifyKyc(Map<String, Object?> payload) {
    return _postAction(
      '/api/v1/mobile/kyc/verify',
      payload,
      'KYC submitted',
    );
  }

  Future<ActionResult> createKycUrl(Map<String, Object?> payload) {
    return _postAction(
      '/api/v1/mobile/kyc/url',
      payload,
      'KYC URL created',
    );
  }

  Future<ActionResult> uploadEqualsMoneyDocument({
    required String type,
    List<String> paths = const [],
    List<UploadDocument> documents = const [],
    String? applicationId,
    String? associatedPersonId,
  }) {
    return _withFallback(
      () async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/mobile/kyc/equalsmoney/documents',
          data: await _equalsMoneyDocumentsFormData(
            type: type,
            paths: paths,
            documents: documents,
            applicationId: applicationId,
            associatedPersonId: associatedPersonId,
          ),
        );

        return ActionResult.fromJson(
          response.data,
          'EqualsMoney document uploaded',
        );
      },
      () => const ActionResult(message: 'EqualsMoney document uploaded'),
    );
  }

  Future<ActionResult> submitEqualsMoneyInformation({
    required String type,
    required String response,
    String? associatedPersonId,
  }) {
    return _postAction(
      '/api/v1/mobile/kyc/equalsmoney/information',
      {
        'type': type,
        'response': response,
        if (associatedPersonId != null && associatedPersonId.trim().isNotEmpty)
          'associatedPersonId': associatedPersonId.trim(),
      },
      'EqualsMoney information submitted',
    );
  }

  Future<FormData> _equalsMoneyDocumentsFormData({
    required String type,
    List<String> paths = const [],
    List<UploadDocument> documents = const [],
    String? applicationId,
    String? associatedPersonId,
  }) async {
    final form = FormData();
    form.fields.add(MapEntry('Type', type));
    if (applicationId != null && applicationId.trim().isNotEmpty) {
      form.fields.add(MapEntry('ApplicationId', applicationId.trim()));
    }
    if (associatedPersonId != null && associatedPersonId.trim().isNotEmpty) {
      form.fields.add(
        MapEntry('AssociatedPersonId', associatedPersonId.trim()),
      );
    }
    for (final document in documents) {
      form.files.add(MapEntry('Files', document.toMultipartFile()));
    }
    for (final path in paths) {
      form.files.add(
        MapEntry('Files', await MultipartFile.fromFile(path)),
      );
    }
    return form;
  }

  Future<ActionResult> startEqualsMoneyOnboarding({
    required List<String> requestedFeatures,
    required List<String> mainPurpose,
    required List<String> sourceOfFunds,
    required List<String> destinationOfFunds,
    required List<String> currenciesRequired,
    required String annualVolume,
    required String numberOfPayments,
    List<String> cardPurposes = const [],
    String? cardAnnualSpend,
    String? numberOfCardsRequired,
    bool atmWithdrawalsRequired = false,
    String? proofOfAddressPath,
    UploadDocument? proofOfAddress,
  }) {
    return _withFallback(
      () async {
        final formData = FormData();
        _addFormValues(formData, 'RequestedFeatures', requestedFeatures);
        _addFormValues(formData, 'MainPurpose', mainPurpose);
        _addFormValues(formData, 'SourceOfFunds', sourceOfFunds);
        _addFormValues(formData, 'DestinationOfFunds', destinationOfFunds);
        _addFormValues(formData, 'CurrenciesRequired', currenciesRequired);
        _addFormValue(formData, 'AnnualVolume', annualVolume);
        _addFormValue(formData, 'NumberOfPayments', numberOfPayments);
        _addFormValues(formData, 'CardPurposes', cardPurposes);
        _addFormValue(formData, 'CardAnnualSpend', cardAnnualSpend);
        _addFormValue(formData, 'NumberOfCardsRequired', numberOfCardsRequired);
        _addFormValue(
          formData,
          'AtmWithdrawalsRequired',
          atmWithdrawalsRequired.toString(),
        );
        if (proofOfAddress != null) {
          formData.files.add(
              MapEntry('ProofOfAddress', proofOfAddress.toMultipartFile()));
        } else if (proofOfAddressPath != null &&
            proofOfAddressPath.isNotEmpty) {
          formData.files.add(
            MapEntry(
              'ProofOfAddress',
              await MultipartFile.fromFile(proofOfAddressPath),
            ),
          );
        }

        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/mobile/banking/equalsmoney-onboarding',
          data: formData,
        );

        return ActionResult.fromJson(
          response.data,
          'EqualsMoney onboarding submitted',
        );
      },
      () => const ActionResult(message: 'EqualsMoney onboarding submitted'),
    );
  }

  Future<List<PlatformResource>> getProviders() {
    return _getList('/api/v1/mobile/banking/providers', 'providers');
  }

  Future<PlatformResource> getEqualsBankingInfo({String? currency}) async {
    final response = await _dio.get<dynamic>(
      '/api/v1/mobile/banking/equals-banking-info',
      queryParameters: {
        if (currency != null && currency.trim().isNotEmpty)
          'currency': currency.trim().toUpperCase(),
      },
    );
    final resources = _platformResourcesFromAny(response.data);

    return resources.firstOrNull ??
        PlatformResource.fromJson(response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : const {});
  }

  Future<List<PlatformResource>> getEqualsBankingInfos() async {
    final response = await _dio.get<dynamic>(
      '/api/v1/mobile/banking/receiving-accounts',
    );

    return _receivingAccountResources(response.data);
  }

  Future<List<PlatformResource>> getBudgets() async {
    try {
      return await _getList('/api/v1/mobile/banking/budgets', 'budgets');
    } on DioException catch (error) {
      if (error.response?.statusCode == 404 &&
          _isMissingEqualsMoneyAccountLink(error.response?.data)) {
        return const [];
      }

      rethrow;
    }
  }

  Future<ActionResult> createBudget({
    required String name,
    String? currency,
    List<String>? currencies,
  }) {
    final budgetCurrencies = [
      ...?currencies,
      if (currency != null) currency,
    ]
        .map((item) => item.trim().toUpperCase())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();

    return _postAction(
      '/api/v1/mobile/banking/budgets',
      {
        'name': name,
        if (budgetCurrencies.isNotEmpty) 'currencies': budgetCurrencies,
        if (budgetCurrencies.isNotEmpty) 'currency': budgetCurrencies.first,
        'amount': 1000,
        'period': 'monthly',
        'category': 'general',
      },
      'Budget created',
    );
  }

  Future<ActionResult> updateBudget({
    required String budgetId,
    required String name,
    required String currency,
  }) {
    return _patchAction(
      '/api/v1/mobile/banking/budgets/$budgetId',
      {
        'name': name,
        'currency': currency,
        'amount': 1000,
        'period': 'monthly',
        'category': 'general',
      },
      'Budget updated',
    );
  }

  Future<ActionResult> transferBudget({
    required String fromBudgetId,
    required String toBudgetId,
    required Money amount,
  }) {
    return _postAction(
      '/api/v1/mobile/banking/budgets/$fromBudgetId/transfer',
      _moneyPayload({'toBudgetId': toBudgetId}, amount),
      'Budget transfer submitted',
    );
  }

  Future<List<PlatformResource>> getTiers() {
    return _getList('/api/v1/mobile/tiers', 'tiers');
  }

  Future<PlatformResource> getCurrentTier() {
    return _getItem('/api/v1/mobile/tiers/current');
  }

  Future<PlatformResource> getCardTier(String cardTierId) {
    return _getItem('/api/v1/mobile/tiers/card-tier/$cardTierId');
  }

  Future<ActionResult> selectTier({
    required int tierId,
    String? tierCycle,
  }) async {
    final cycle = tierCycle?.trim();
    try {
      final response = await _dio.post<dynamic>(
        '/api/v1/mobile/tiers/current',
        data: {
          'tierId': tierId,
          'tierCycle': cycle == null || cycle.isEmpty ? 'monthly' : cycle,
        },
      );

      return _tierSelectionResultFromAny(
        response.data,
        tierId,
        'Tier selection submitted',
      );
    } on DioException catch (error) {
      if (_isAlreadySelectedTierError(error)) {
        return ActionResult(
          message: 'Tier already selected.',
          metadata: {
            'confirmedTierId': tierId,
            'tierId': tierId,
            'alreadySelected': true,
          },
        );
      }

      rethrow;
    }
  }

  Future<PaymentCard> getCardDetail(String cardId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/cards/$cardId',
    );
    final payload = _extractPayload(response.data, 'card');
    if (payload is Map<String, dynamic>) {
      return PaymentCard.fromJson(payload);
    }
    if (payload is Map) {
      return PaymentCard.fromJson(
        payload.map((key, value) => MapEntry(key.toString(), value)),
      );
    }

    return PaymentCard.fromJson(response.data ?? const {});
  }

  Future<CardControlCapabilities> getCardControls(String cardId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/cards/$cardId/controls',
    );
    return CardControlCapabilities.fromJson(response.data ?? const {});
  }

  Future<CardLimitsInfo> getCardLimits(String cardId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/cards/$cardId/limits',
    );
    return CardLimitsInfo.fromJson(response.data ?? const {});
  }

  Future<ActionResult> updateCardLimits(
    String cardId, {
    double? daily,
    double? weekly,
    double? monthly,
    String? currency,
  }) {
    return _patchAction(
      '/api/v1/mobile/cards/$cardId/limits',
      {
        if (daily != null) 'daily': daily,
        if (weekly != null) 'weekly': weekly,
        if (monthly != null) 'monthly': monthly,
        if (currency != null && currency.trim().isNotEmpty)
          'currency': currency.trim().toUpperCase(),
      },
      'Card limits updated',
    );
  }

  /// Turns the issuer's auto freeze on or off for a card: while on, Hoppa
  /// freezes the card again by itself ten minutes after it is unfrozen.
  Future<ActionResult> setCardAutoFreeze(String cardId, bool enabled) {
    return _patchAction(
      '/api/v1/mobile/cards/$cardId/auto-freeze',
      {'enabled': enabled},
      enabled ? 'Auto freeze is on' : 'Auto freeze is off',
    );
  }

  Future<ActionResult> enableCard(String cardId) {
    return _postAction(
      '/api/v1/mobile/cards/$cardId/enable',
      const {},
      'Card enabled',
    );
  }

  Future<ActionResult> activateCard(String cardId) {
    return _postAction(
      '/api/v1/mobile/cards/$cardId/activate',
      const {},
      'Card activated',
    );
  }

  Future<ActionResult> setCardPin(String cardId, String pin) {
    return _patchAction(
      '/api/v1/mobile/cards/$cardId/pin',
      {'pinToken': pin, 'pin': pin},
      'PIN updated',
    );
  }

  Future<ActionResult> getCardWidget(String cardId) {
    return _getAction(
      '/api/v1/mobile/cards/$cardId/widget',
      'Card widget loaded',
    );
  }

  Future<List<PlatformResource>> getCardTransactions(String cardId) {
    return _getList(
      '/api/v1/mobile/cards/$cardId/transactions',
      'transactions',
    );
  }

  Future<ActionResult> cancelCard(String cardId) {
    return _postAction(
      '/api/v1/mobile/cards/$cardId/cancel',
      const {'reason': 'mobile_user_requested'},
      'Card cancelled',
    );
  }

  Future<ActionResult> loadCard({
    required String cardId,
    required Money amount,
    String? token,
  }) {
    return _postAction(
      '/api/v1/mobile/cards/$cardId/load',
      _moneyPayload({
        'cardId': cardId,
        if (token != null && token.trim().isNotEmpty) 'Token': token.trim(),
      }, amount),
      'Card loaded',
    );
  }

  Future<ActionResult> unloadCard({
    required String cardId,
    required Money amount,
  }) {
    final numericCardId = int.tryParse(cardId);
    return _postAction(
      '/api/v1/mobile/cards/unload',
      {
        'CardId': numericCardId,
        'Currency': amount.currency,
        'Value': amount.minorUnits / 100,
      },
      'Card unloaded',
    );
  }

  Future<List<PlatformResource>> getBankingBalance({String? accountId}) async {
    if (accountId != null && accountId.isNotEmpty) {
      return _getList(
        '/api/v1/mobile/banking/accounts/$accountId/balances',
        'balances',
      );
    }

    final accountsResponse = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/banking/accounts',
    );
    final accountsPayload = _extractPayload(accountsResponse.data, 'accounts');
    if (accountsPayload is! List || accountsPayload.isEmpty) {
      return const [];
    }

    final account = AccountBalance.fromJson(
      accountsPayload.whereType<Map<String, dynamic>>().first,
    );
    final balancesResponse = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/banking/accounts/${account.id}/balances',
    );
    final balancesPayload = _extractPayload(balancesResponse.data, 'balances');
    if (balancesPayload is List) {
      return balancesPayload
          .whereType<Map<String, dynamic>>()
          .map(PlatformResource.fromJson)
          .toList();
    }
    if (balancesPayload is Map<String, dynamic>) {
      return [PlatformResource.fromJson(balancesPayload)];
    }

    return const [];
  }

  Future<ActionResult> createQuote({
    required String fromCurrency,
    required String toCurrency,
    required Money amount,
  }) {
    return _postAction(
      '/api/v1/mobile/banking/quotations',
      _moneyPayload({
        'fromCurrency': fromCurrency,
        'toCurrency': toCurrency,
      }, amount),
      'Quote created',
    );
  }

  Future<Map<String, dynamic>> createEqualsMoneyConversionQuote({
    required String accountId,
    required String budgetId,
    required String sourceCurrency,
    required String targetCurrency,
    required double amount,
  }) {
    final now = DateTime.now();
    final settlementDate =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return _postMap(
      '/api/v1/mobile/banking/orders/quote',
      {
        'sourceCurrency': {
          'amount': amount,
          'currency': {
            'budgetId': budgetId,
            'currencyCode': sourceCurrency,
          },
        },
        'targetCurrency': {
          'currency': {
            'budgetId': budgetId,
            'currencyCode': targetCurrency,
          },
        },
        'settlementDate': settlementDate,
        'type': {'from': 'balance', 'to': 'balance'},
      },
      queryParameters: {'accountId': accountId},
    );
  }

  Future<Map<String, dynamic>> executeEqualsMoneyConversion({
    required String accountId,
    required String orderId,
    required String quoteRequestId,
  }) {
    return _postMap(
      '/api/v1/mobile/banking/orders/trade',
      {
        'orderId': orderId,
        'quoteRequestId': quoteRequestId,
      },
      queryParameters: {'accountId': accountId},
    );
  }

  Future<List<PlatformResource>> getMandates() {
    return _getList('/api/v1/mobile/payments/mandates', 'mandates');
  }

  Future<List<PlatformResource>> getPayments() {
    return _getList('/api/v1/mobile/payments', 'payments');
  }

  Future<ActionResult> createPayment({
    required String merchantName,
    required Money amount,
  }) {
    return _postAction(
      '/api/v1/mobile/payments',
      _moneyPayload({
        'destinationReference': merchantName,
        'reference': merchantName,
      }, amount),
      'Payment created',
    );
  }

  Future<ActionResult> createMandate(String merchantName, {Money? amount}) {
    final mandateAmount =
        amount ?? const Money(currency: 'EUR', minorUnits: 100000);
    return _postAction(
      '/api/v1/mobile/payments/mandates',
      {
        'maxAmount': (mandateAmount.minorUnits / 100).toStringAsFixed(2),
        'currency': mandateAmount.currency,
        'description': merchantName,
        'externalReferenceId': merchantName,
      },
      'Mandate created',
    );
  }

  Future<ActionResult> revokeMandate(String mandateId) {
    return _putAction(
      '/api/v1/mobile/payments/mandates/$mandateId/revoke',
      const {'reason': 'mobile_user_requested'},
      'Mandate revoked',
    );
  }

  Future<List<PlatformResource>> getPaymentRequests() {
    return _getList(
      '/api/v1/mobile/payments/requests',
      'requests',
    );
  }

  Future<ActionResult> createPaymentRequest({
    required String counterparty,
    required Money amount,
  }) {
    return _postAction(
      '/api/v1/mobile/payments/requests',
      _stringMoneyPayload({
        'description': counterparty,
        'externalReferenceId': counterparty,
      }, amount),
      'Payment request created',
    );
  }

  Future<ActionResult> cancelPaymentRequest(String requestId) {
    return _putAction(
      '/api/v1/mobile/payments/requests/$requestId/cancel',
      const {'reason': 'mobile_user_requested'},
      'Payment request cancelled',
    );
  }

  Future<ActionResult> createPayout({
    required String destination,
    required Money amount,
  }) {
    return _postAction(
      '/api/v1/mobile/payments/payouts',
      _stringMoneyPayload({
        'destinationAddress': destination,
        'description': 'Mobile payout',
      }, amount),
      'Payout submitted',
    );
  }

  Future<ActionResult> createWithdrawal({
    required String destination,
    required Money amount,
  }) {
    return _postAction(
      '/api/v1/mobile/payments/withdrawals',
      _stringMoneyPayload({
        'destinationAddress': destination,
        'chain': amount.currency == 'BTC' ? 'Bitcoin' : 'Ethereum',
        'description': 'Mobile withdrawal',
      }, amount),
      'Withdrawal submitted',
    );
  }

  Future<ActionResult> calculateWithdrawalFee({
    required String destination,
    required Money amount,
  }) {
    return _postAction(
      '/api/v1/mobile/payments/withdrawals/fee',
      _stringMoneyPayload({
        'destinationAddress': destination,
        'chain': amount.currency == 'BTC' ? 'Bitcoin' : 'Ethereum',
      }, amount),
      'Withdrawal fee calculated',
    );
  }

  Future<List<PlatformResource>> getWallets() {
    return _getList('/api/v1/mobile/wallets', 'wallets');
  }

  Future<List<PlatformResource>> getAssets() {
    return _getList('/api/v1/mobile/assets', 'assets');
  }

  Future<List<PlatformResource>> getUserAssets() {
    return _getList('/api/v1/mobile/assets', 'assets');
  }

  Future<List<PlatformResource>> getUserWallets() {
    return _getList('/api/v1/mobile/wallets', 'wallets');
  }

  Future<List<PlatformResource>> getDepositAddresses() async {
    List<PlatformResource>? endpointAddresses;
    Object? endpointError;
    StackTrace? endpointStackTrace;

    try {
      endpointAddresses = await _getList(
        '/api/v1/mobile/crypto-addresses',
        'addresses',
      );
    } catch (error, stackTrace) {
      endpointError = error;
      endpointStackTrace = stackTrace;
    }

    final walletAddresses = await _walletDepositAddresses();
    if (endpointAddresses != null) {
      return mergeDepositAddressResources(endpointAddresses, walletAddresses);
    }
    if (walletAddresses.isNotEmpty) {
      return walletAddresses;
    }

    Error.throwWithStackTrace(endpointError!, endpointStackTrace!);
  }

  Future<List<PlatformResource>> getCryptoAddresses() {
    return getDepositAddresses();
  }

  Future<List<PlatformResource>> _walletDepositAddresses() async {
    try {
      return depositAddressesFromWallets(await getWallets());
    } catch (_) {
      return const [];
    }
  }

  Future<ActionResult> createWalletTopUp({
    required String walletId,
    required Money amount,
  }) {
    return _postAction(
      '/api/v1/mobile/transfers/wallet-topup',
      _moneyPayload({'walletId': walletId}, amount),
      'Wallet top-up submitted',
    );
  }

  Future<ActionResult> createDashboardWalletTopUp({
    required String token,
    required String walletAddress,
    required Money amount,
  }) async {
    final payload = {
      'Token': token,
      'WalletAddress': walletAddress,
      'Value': amount.minorUnits / 100,
    };

    return _postAction(
      '/api/v1/mobile/transfers/wallet-topup',
      payload,
      'Wallet top-up initiated',
    );
  }

  Future<QuantumTopUpEstimate> getQuantumTopUpEstimate({
    required Money amount,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/cards/quantum-topup/estimate',
      queryParameters: {
        'amount': (amount.minorUnits / 100).toStringAsFixed(2),
      },
    );

    return QuantumTopUpEstimate.fromJson(response.data ?? const {});
  }

  Future<ActionResult> transferCryptoToQuantumDashboard({
    required String sourceCurrency,
    required String destinationCurrency,
    required Money amount,
  }) async {
    final payload = {
      'SourceCurrency': sourceCurrency,
      'DestinationCurrency': destinationCurrency,
      'Amount': amount.minorUnits / 100,
    };

    return _postAction(
      '/api/v1/mobile/transfers/crypto-to-quantum-transfer',
      payload,
      'Crypto to Quantum transfer submitted',
    );
  }

  Future<ActionResult> transferCryptoToQuantum({
    required String asset,
    required Money amount,
  }) {
    return _postAction(
      '/api/v1/mobile/transfers/crypto-to-quantum-transfer',
      _moneyPayload({'asset': asset}, amount),
      'Crypto to Quantum transfer submitted',
    );
  }

  Future<ActionResult> exchangeQuantumUsdToCrypto({
    required String asset,
    required Money amount,
  }) async {
    final payload = {
      'Currency': asset,
      'Amount': amount.minorUnits / 100,
    };

    return _postAction(
      '/api/v1/mobile/transfers/quantum-usd-to-crypto-exchange',
      payload,
      'Quantum USD to crypto exchange submitted',
    );
  }

  Future<CryptoWithdrawalBalance> getCryptoWithdrawalAvailableBalance() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/transfers/withdrawals/available-balance',
    );
    return CryptoWithdrawalBalance.fromJson(response.data ?? const {});
  }

  Future<CryptoWithdrawalQuote> getCryptoWithdrawalFeeAndQuota({
    required String chain,
    required String address,
    required String currency,
    required String amount,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/transfers/withdrawals/fee-and-quota',
      queryParameters: {
        'chain': chain,
        'address': address,
        'currency': currency,
        'amount': amount,
      },
    );
    final quote = CryptoWithdrawalQuote.fromJson(response.data ?? const {});
    if (!quote.isSuccessful) {
      throw Exception(
        quote.message.isEmpty
            ? 'The withdrawal fee could not be calculated.'
            : quote.message,
      );
    }
    return quote;
  }

  Future<CryptoWithdrawalResult> createCryptoWithdrawal({
    required String currency,
    required String chain,
    required String amount,
    required String destinationAddress,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/transfers/withdrawals/crypto',
      data: {
        'Currency': currency,
        'Chain': chain,
        'Amount': amount,
        'DestinationAddress': destinationAddress,
        'ConfirmExchangeRate': true,
        'Description': 'Mobile crypto withdrawal',
      },
    );
    return CryptoWithdrawalResult.fromJson(response.data ?? const {});
  }

  Future<CryptoWithdrawalResult> confirmCryptoWithdrawal({
    required String verificationToken,
    required String otpCode,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/transfers/withdrawals/crypto/confirm',
      data: {
        'VerificationToken': verificationToken,
        'OtpCode': otpCode,
      },
    );
    return CryptoWithdrawalResult.fromJson(response.data ?? const {});
  }

  Future<CryptoWithdrawalOtpResend> resendCryptoWithdrawalOtp({
    required String verificationToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/transfers/withdrawals/crypto/resend',
      data: {'VerificationToken': verificationToken},
    );
    return CryptoWithdrawalOtpResend.fromJson(response.data ?? const {});
  }

  Future<ActionResult> exportTransactions() {
    return _postAction(
      '/api/v1/mobile/transactions/export',
      const {},
      'Transaction export requested',
    );
  }

  Future<TransactionStatusSummary> getTransactionStats() async {
    return _withFallback(
      () async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/v1/mobile/transactions/stats',
        );

        return TransactionStatusSummary.fromJson(response.data ?? const {});
      },
      () => const TransactionStatusSummary(
        totalCount: 42,
        completedCount: 37,
        pendingCount: 4,
        failedCount: 1,
      ),
    );
  }

  Future<PlatformResource> getTransactionDetail(String transactionId) {
    return _getItem('/api/v1/mobile/transactions/$transactionId');
  }

  Future<ActionResult> syncTransactions() {
    return _postAction(
      '/api/v1/mobile/transactions/sync',
      const {},
      'Transaction sync started',
    );
  }

  Future<List<PlatformResource>> _getList(
    String path,
    String key, {
    Options? options,
  }) async {
    final response = await _dio.get<dynamic>(path, options: options);
    final payload = _extractPayload(response.data, key);
    if (payload is List) {
      return payload
          .map(_resourceFromAny)
          .whereType<PlatformResource>()
          .toList();
    }
    if (payload is Map<String, dynamic> && payload.isNotEmpty) {
      return [PlatformResource.fromJson(payload)];
    }

    return const [];
  }

  Future<PlatformResource> _getItem(String path) async {
    final response = await _dio.get<Map<String, dynamic>>(path);

    return PlatformResource.fromJson(response.data ?? const {});
  }

  Future<Map<String, dynamic>> _getMap(String path,
      {Map<String, dynamic>? queryParameters}) async {
    final response = await _dio.get<dynamic>(path, queryParameters: queryParameters);
    return _mapFromAny(response.data) ?? const {};
  }

  /// A list endpoint's rows, whether the body is the bare array or a page
  /// envelope (`items` / `data` / `results`).
  Future<List<Map<String, dynamic>>> _getRows(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response =
        await _dio.get<dynamic>(path, queryParameters: queryParameters);
    return _rowsFromAny(response.data);
  }

  Future<Map<String, dynamic>> _postMap(
    String path,
    Object data, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _dio.post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
    );
    return _mapFromAny(response.data) ?? const {};
  }

  Future<ActionResult> _getAction(String path, String fallback) {
    return _withFallback(
      () async {
        final response = await _dio.get<dynamic>(path);

        return _actionResultFromAny(response.data, fallback);
      },
      () => ActionResult(message: fallback),
    );
  }

  Future<ActionResult> _postAction(
    String path,
    Object data,
    String fallback, {
    Options? options,
    Map<String, dynamic>? queryParameters,
  }) {
    return _withFallback(
      () async {
        final response = await _dio.post<dynamic>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
        );

        return _actionResultFromAny(response.data, fallback);
      },
      () => ActionResult(message: fallback),
    );
  }

  Future<ActionResult> _putAction(String path, Object data, String fallback) {
    return _withFallback(
      () async {
        final response = await _dio.put<dynamic>(path, data: data);

        return _actionResultFromAny(response.data, fallback);
      },
      () => ActionResult(message: fallback),
    );
  }

  Future<ActionResult> _patchAction(String path, Object data, String fallback) {
    return _withFallback(
      () async {
        final response = await _dio.patch<dynamic>(path, data: data);

        return _actionResultFromAny(response.data, fallback);
      },
      () => ActionResult(message: fallback),
    );
  }
}

Map<String, dynamic>? _mapFromAny(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

ActionResult _actionResultFromAny(Object? data, String fallback) {
  if (data == null) {
    return ActionResult(message: fallback);
  }
  if (data is Map<String, dynamic>) {
    _throwIfFailurePayload(data);
    return ActionResult.fromJson(data, fallback);
  }
  if (data is Map) {
    final normalized =
        data.map((key, value) => MapEntry(key.toString(), value));
    _throwIfFailurePayload(normalized);
    return ActionResult.fromJson(normalized, fallback);
  }

  return ActionResult(message: data.toString());
}

ActionResult _tierSelectionResultFromAny(
  Object? data,
  int requestedTierId,
  String fallback,
) {
  if (data == null) {
    return ActionResult(message: fallback);
  }
  if (data is Map<String, dynamic>) {
    return _tierSelectionResultFromMap(data, requestedTierId, fallback);
  }
  if (data is Map) {
    final normalized =
        data.map((key, value) => MapEntry(key.toString(), value));
    return _tierSelectionResultFromMap(normalized, requestedTierId, fallback);
  }

  return ActionResult(message: data.toString());
}

bool _isAlreadySelectedTierError(DioException error) {
  final responseData = error.response?.data;
  final text = [
    error.message,
    responseData is Map
        ? responseData.values.map((value) => value.toString()).join(' ')
        : responseData?.toString(),
  ].whereType<String>().join(' ').toLowerCase();

  return text.contains('already has this tier') ||
      text.contains('already has this tier or higher') ||
      text.contains('tier or higher');
}

ActionResult _tierSelectionResultFromMap(
  Map<String, dynamic> data,
  int requestedTierId,
  String fallback,
) {
  final success = _boolValue(data['success'] ?? data['Success']);
  final isSuccess = _boolValue(data['isSuccess'] ?? data['IsSuccess']);
  final selectedTierId = _intValue(
    data['tierId'] ??
        data['TierId'] ??
        data['selectedTierId'] ??
        data['SelectedTierId'],
  );

  if (_hasExplicitFailureDetail(data) ||
      ((success == false || isSuccess == false) &&
          selectedTierId != requestedTierId)) {
    throw Exception(_payloadErrorMessage(data));
  }

  final result = ActionResult.fromJson(data, fallback);
  if ((success == false || isSuccess == false) &&
      selectedTierId == requestedTierId) {
    return ActionResult(
      message: 'Tier selection received. Refreshing your tier status.',
      reference: result.reference,
      metadata: data,
    );
  }

  return result;
}

void _throwIfFailurePayload(Map<String, dynamic> data) {
  final success = _boolValue(data['success'] ?? data['Success']);
  final isSuccess = _boolValue(data['isSuccess'] ?? data['IsSuccess']);
  if (success == false || isSuccess == false) {
    throw Exception(_payloadErrorMessage(data));
  }

  final code = (data['code'] ?? data['Code'])?.toString().toLowerCase() ?? '';
  if (code.contains('failed') || code.contains('required')) {
    throw Exception(_payloadErrorMessage(data));
  }

  final error =
      data['error'] ?? data['Error'] ?? data['errors'] ?? data['Errors'];
  if (error != null) {
    throw Exception(_payloadErrorMessage(data));
  }
}

bool _hasExplicitFailureDetail(Map<String, dynamic> data) {
  return _hasNonEmptyValue(data, const [
        'errorCode',
        'ErrorCode',
        'errorMessage',
        'ErrorMessage',
        'failureReason',
        'FailureReason',
      ]) ||
      _nestedFailureReason(data['paymentDetails']) ||
      _nestedFailureReason(data['PaymentDetails']) ||
      _nestedFailureReason(data['payment']) ||
      _nestedFailureReason(data['Payment']);
}

bool _nestedFailureReason(Object? value) {
  if (value is Map<String, dynamic>) {
    return _hasNonEmptyValue(value, const [
      'failureReason',
      'FailureReason',
      'failure_reason',
    ]);
  }
  if (value is Map) {
    return _nestedFailureReason(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  return false;
}

bool _hasNonEmptyValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final text = data[key]?.toString().trim();
    if (text != null && text.isNotEmpty) {
      return true;
    }
  }

  return false;
}

String _payloadErrorMessage(Map<String, dynamic> data) {
  final text = _firstNonEmptyValue(data, const [
        'message',
        'Message',
        'errorMessage',
        'ErrorMessage',
        'failureReason',
        'FailureReason',
        'detail',
        'Detail',
        'title',
        'Title',
        'errorCode',
        'ErrorCode',
        'error',
        'Error',
      ]) ??
      _nestedFailureText(data['paymentDetails']) ??
      _nestedFailureText(data['PaymentDetails']) ??
      _nestedFailureText(data['payment']) ??
      _nestedFailureText(data['Payment']);

  return text ?? 'The action could not be completed.';
}

String? _nestedFailureText(Object? value) {
  if (value is Map<String, dynamic>) {
    return _firstNonEmptyValue(value, const [
      'failureReason',
      'FailureReason',
      'failure_reason',
    ]);
  }
  if (value is Map) {
    return _nestedFailureText(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  return null;
}

String? _firstNonEmptyValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final text = data[key]?.toString().trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
  }

  return null;
}

bool? _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }

  return null;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }

  return null;
}

Object? _extractPayload(Object? json, String key) {
  if (json == null) {
    return null;
  }
  if (json is List) {
    return json;
  }
  final Map<String, dynamic> map;
  if (json is Map<String, dynamic>) {
    map = json;
  } else if (json is Map) {
    map = json.map((key, value) => MapEntry(key.toString(), value));
  } else {
    return null;
  }

  final pascalKey =
      key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';
  final data = map['data'] ?? map['Data'];

  return map[key] ??
      map[pascalKey] ??
      map['items'] ??
      map['Items'] ??
      (data is Map<String, dynamic>
          ? data[key] ??
              data[pascalKey] ??
              data['items'] ??
              data['Items'] ??
              data['list'] ??
              data['List']
          : null) ??
      data ??
      map;
}

PlatformResource? _resourceFromAny(Object? value) {
  if (value is Map<String, dynamic>) {
    return PlatformResource.fromJson(value);
  }
  if (value is Map) {
    return PlatformResource.fromJson(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  return null;
}

List<PlatformResource> _platformResourcesFromAny(Object? value) {
  final payload = _extractPayload(value, 'equalsBankingInfo');
  if (payload is List) {
    return payload.map(_resourceFromAny).whereType<PlatformResource>().toList();
  }

  final resource = _resourceFromAny(payload);
  return resource == null ? const [] : [resource];
}

List<PlatformResource> _receivingAccountResources(Object? value) {
  final payload = _extractPayload(value, 'accounts');
  final accounts = payload is List ? payload : [payload];
  final resources = <PlatformResource>[];
  for (final item in accounts.whereType<Map>()) {
    final account = item.map((key, value) => MapEntry(key.toString(), value));
    final accountId =
        _firstNonEmptyValue(account, const ['accountId', 'AccountId']);
    if (accountId == null) continue;
    final explicitBudgetId =
        _firstNonEmptyValue(account, const ['budgetId', 'BudgetId']);
    final accountType =
        _firstNonEmptyValue(account, const ['accountType', 'AccountType']);
    final budgetId = explicitBudgetId ??
        (accountType?.toUpperCase() == 'BUDGET' ? accountId : null);
    final parentHolder = _firstNonEmptyValue(account, const [
      'userName',
      'UserName',
      'accountHolderName',
      'AccountHolderName',
    ]);
    final linked =
        account['linkedBankAccounts'] ?? account['LinkedBankAccounts'];
    final banks = linked is List ? linked.whereType<Map>().toList() : <Map>[];
    if (banks.isEmpty) {
      resources.add(PlatformResource.fromJson({
        ...account,
        if (budgetId != null) 'budgetId': budgetId,
        if (parentHolder != null) 'userName': parentHolder,
      }));
      continue;
    }

    // Some account views consume one linked bank per resource. Keep each
    // bank's own currency while retaining its exact account/budget identity.
    for (final item in banks) {
      final bank = item.map((key, value) => MapEntry(key.toString(), value));
      final currency =
          _firstNonEmptyValue(bank, const ['currency', 'Currency']);
      final holder = _firstNonEmptyValue(bank, const [
            'accountHolderName',
            'AccountHolderName',
          ]) ??
          parentHolder;
      resources.add(PlatformResource.fromJson({
        for (final entry in account.entries)
          if (entry.key.toLowerCase() != 'linkedbankaccounts' &&
              entry.key.toLowerCase() != 'currency')
            entry.key: entry.value,
        if (budgetId != null) 'budgetId': budgetId,
        if (currency != null) 'currency': currency,
        if (holder != null) 'userName': holder,
        'linkedBankAccounts': [bank],
      }));
    }
  }
  return resources;
}

Map<String, Object?> _moneyPayload(
  Map<String, Object?> payload,
  Money amount,
) {
  final majorAmount = amount.minorUnits / 100;
  return {
    ...payload,
    'amount': majorAmount,
    'currency': amount.currency,
    'minorUnits': amount.minorUnits,
    'money': {
      'currency': amount.currency,
      'minorUnits': amount.minorUnits,
    },
  };
}

Map<String, Object?> _stringMoneyPayload(
  Map<String, Object?> payload,
  Money amount,
) {
  final majorAmount = (amount.minorUnits / 100).toStringAsFixed(2);
  return {
    ...payload,
    'amount': majorAmount,
    'currency': amount.currency,
    'minorUnits': amount.minorUnits,
    'money': {
      'currency': amount.currency,
      'minorUnits': amount.minorUnits,
    },
  };
}

void _addFormValues(FormData formData, String key, List<String> values) {
  for (final value in values) {
    _addFormValue(formData, key, value);
  }
}

void _addFormValue(FormData formData, String key, String? value) {
  if (value == null || value.trim().isEmpty) {
    return;
  }

  formData.fields.add(MapEntry(key, value.trim()));
}

Future<T> _withFallback<T>(
  Future<T> Function() request,
  T Function() unusedFallback,
) async {
  return request();
}

bool _isMissingEqualsMoneyAccountLink(Object? payload) {
  if (payload is Map) {
    final code = payload['code']?.toString().toUpperCase().trim();
    final detail = payload['detail']?.toString().toLowerCase() ?? '';
    return code == 'NOT_FOUND' ||
        detail.contains('equalsmoney account link not found');
  }

  final text = payload?.toString().toLowerCase() ?? '';
  return text.contains('equalsmoney account link not found');
}

List<Map<String, dynamic>> _rowsFromAny(Object? payload) {
  Object? rows = payload;
  if (payload is Map) {
    rows = payload['items'] ??
        payload['Items'] ??
        payload['data'] ??
        payload['Data'] ??
        payload['results'] ??
        payload['Results'];
  }
  if (rows is! List) return const [];
  return rows.map(_mapFromAny).whereType<Map<String, dynamic>>().toList();
}
