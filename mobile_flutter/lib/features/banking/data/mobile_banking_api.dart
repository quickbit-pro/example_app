import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/models/banking_models.dart';
import '../../../core/models/card_discount.dart';
import '../../../core/models/deduplicate_card_fees.dart';

class MobileBankingApi {
  const MobileBankingApi(this._dio);

  final Dio _dio;

  Future<UserProfile> getProfile() async {
    return UserProfile.fromJson(await _getProfilePayload());
  }

  Future<Map<String, dynamic>> _getProfilePayload() async {
    return _withFallback(
      () async {
        final response =
            await _dio.get<Map<String, dynamic>>('/api/v1/mobile/me');

        return response.data ?? const {};
      },
      () => const {},
    );
  }

  Future<List<AccountBalance>> getAccounts() async {
    return _withFallback(
      () async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/v1/mobile/banking/accounts',
        );
        final data = await Future.wait(
          _extractList(response.data, 'accounts').map(_enrichAccountBalances),
        );

        return data.map(AccountBalance.fromJson).toList();
      },
      () => const <AccountBalance>[],
    );
  }

  Future<Map<String, dynamic>> _enrichAccountBalances(
    Map<String, dynamic> account,
  ) async {
    final parsed = AccountBalance.fromJson(account);
    final alreadyHasBalances = parsed.currencyBalances.isNotEmpty ||
        parsed.available.minorUnits != 0 ||
        parsed.balance.minorUnits != 0;
    if (alreadyHasBalances || parsed.id.trim().isEmpty) return account;
    final scopeId = parsed.budgetId.trim().isNotEmpty
        ? parsed.budgetId.trim()
        : parsed.id.trim();

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/mobile/banking/accounts/${Uri.encodeComponent(scopeId)}/balances',
      );
      final payload = _payloadValue(response.data, 'balances');
      // The upstream balance endpoint returns an aggregate even when the
      // proxy receives an account ID. Attach only rows with an exact scope;
      // supported currency or a shared owner cannot establish ownership.
      if (payload is! List) return account;
      final ownBalances = payload.whereType<Map>().where((row) {
        final rowBudget = row['budgetId'] ?? row['BudgetId'];
        final rowScope = rowBudget ?? row['accountId'] ?? row['AccountId'];
        if (rowScope?.toString().trim().toLowerCase() !=
            scopeId.toLowerCase()) {
          return false;
        }
        final provider = (row['provider'] ?? row['Provider'])?.toString() ?? '';
        return provider.isEmpty ||
            parsed.provider.isEmpty ||
            _accountProviderKey(provider) ==
                _accountProviderKey(parsed.provider);
      }).toList();
      if (ownBalances.isEmpty) return account;
      return {...account, 'currencyBalances': ownBalances};
    } on DioException catch (error) {
      if (const {400, 401, 404}.contains(error.response?.statusCode)) {
        return account;
      }
      rethrow;
    }
  }

  Future<List<PaymentCard>> getCards() async {
    return _withFallback(
      () async {
        final Response<Map<String, dynamic>> response;
        try {
          response =
              await _dio.get<Map<String, dynamic>>('/api/v1/mobile/cards');
        } on DioException catch (error) {
          if (_isMissingCardAccount(error)) return const <PaymentCard>[];
          rethrow;
        }
        var data = _extractList(response.data, 'cards');
        if (data.isEmpty) return const <PaymentCard>[];

        data = await _enrichMissingCardArtwork(
          _dio,
          data,
          response.data,
        );

        return data.map(PaymentCard.fromJson).toList();
      },
      () => const <PaymentCard>[],
    );
  }

  Future<List<LedgerTransaction>> getTransactions({
    String? accountId,
    int? limit,
  }) async {
    return _withFallback(
      () async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/v1/mobile/transactions',
          queryParameters: {
            if (accountId != null && accountId.trim().isNotEmpty)
              'accountId': accountId.trim(),
            if (limit != null) 'limit': limit,
            'sortBy': 'date',
            'sortOrder': 'desc',
          },
        );
        final data = _extractList(response.data, 'transactions');

        return deduplicateCardFees(
            data.map(LedgerTransaction.fromJson).toList());
      },
      () => const <LedgerTransaction>[],
    );
  }

  /// Activity history. Home stops once a page crosses [since], retaining the
  /// complete boundary page so its Recent list can still show older activity.
  /// Follow the server's paging contract without filtering out crypto or
  /// related ledger rows; callers decide which rows contribute to a summary.
  Future<List<LedgerTransaction>> getActivityTransactions({
    String? accountId,
    String? cardId,
    DateTime? since,
    String? type,
  }) async {
    final transactions = <LedgerTransaction>[];
    final seenIds = <String>{};
    var page = 1;

    while (true) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/mobile/transactions',
        queryParameters: {
          if (accountId != null && accountId.trim().isNotEmpty)
            'accountId': accountId.trim(),
          if (cardId != null && cardId.trim().isNotEmpty)
            'cardIds': cardId.trim(),
          if (type != null) 'types': type,
          'page': page,
          'pageSize': 100,
          'sortBy': 'date',
          'sortOrder': 'desc',
        },
      );
      final rows = _extractList(response.data, 'transactions');
      final previousCount = transactions.length;
      for (final row in rows) {
        final transaction = LedgerTransaction.fromJson(row);
        // Adjacent pages can overlap when fresh activity arrives between
        // requests. Never count a server transaction ID twice.
        if (transaction.id.isEmpty || seenIds.add(transaction.id)) {
          transactions.add(transaction);
        }
      }

      final pagination = _activityPagination(response.data);
      final responsePage = _activityPageNumber(
        pagination['page'] ?? pagination['Page'],
      );
      final totalPages = _activityPageNumber(
        pagination['totalPages'] ?? pagination['TotalPages'],
      );
      final hasNext = pagination['hasNext'] ?? pagination['HasNext'];
      final more =
          hasNext is bool ? hasNext : totalPages != null && page < totalPages;
      if (responsePage != null && responsePage != page) {
        throw StateError('Transaction history pagination did not advance.');
      }
      if (!more ||
          (since != null &&
              transactions.any(
                  (row) => row.hasBookedAt && row.bookedAt.isBefore(since)))) {
        return deduplicateCardFees(transactions);
      }
      // A malformed/repeated page must not silently turn into a partial
      // balance summary or an endless request loop.
      if (rows.isEmpty || transactions.length == previousCount) {
        throw StateError('Transaction history pagination did not advance.');
      }
      page += 1;
    }
  }

  /// First-deposit progress uses lifetime history, independent of Home's
  /// rolling activity window and the amount still available to spend.
  Future<bool> hasCompletedDeposit() async {
    for (final type in const ['deposit', 'crypto_deposit']) {
      final history = await getActivityTransactions(type: type);
      if (history.any((row) =>
          row.rawType.toLowerCase().contains('deposit') &&
          row.amount.isPositive &&
          const {
            'complete',
            'completed',
            'cleared',
            'settled',
            'success',
            'successful',
            'succeeded',
            'posted'
          }.contains(row.status.toLowerCase().trim()))) {
        return true;
      }
    }
    return false;
  }

  Future<List<Payee>> getPayees() async {
    return _withFallback(
      () async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/v1/mobile/banking/payees',
        );
        final data = _extractList(response.data, 'payees');

        return data.map(Payee.fromJson).toList();
      },
      () => const <Payee>[],
    );
  }

  Future<void> fundTestAccount({
    required String accountId,
    required Money amount,
  }) async {
    await _dio.post<void>(
      '/api/v1/mobile/banking/accounts/fund-test',
      data: {
        'accountId': accountId,
        'AccountId': accountId,
        'amount': (amount.minorUnits / 100).toStringAsFixed(2),
        'Amount': (amount.minorUnits / 100).toStringAsFixed(2),
        'currency': amount.currency,
        'Currency': amount.currency,
      },
    );
  }

  Future<List<OnboardingTask>> getOnboardingTasks() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/onboarding/status',
    );
    return _onboardingTasksFromStatus(response.data);
  }

  List<OnboardingTask> _onboardingTasksFromStatus(
    Map<String, dynamic>? status,
  ) {
    final data = _extractList(status, 'tasks');
    if (data.isNotEmpty) {
      return data.map(OnboardingTask.fromJson).toList();
    }
    final requiredActions = status?['requiredActions'];
    if (requiredActions is List) {
      return requiredActions
          .map(
            (action) => OnboardingTask.fromJson({
              'id': action.toString(),
              'title': action.toString(),
              'description': '',
              'status': 'pending',
              'route': _onboardingRoute(action.toString()),
            }),
          )
          .toList();
    }

    return const [];
  }

  Future<DashboardSnapshot> getDashboard() async {
    // None of these requests needs another's response, so they all go out
    // together. The profile carries the onboarding status block; only a
    // backend without it costs the separate onboarding request.
    final results = await Future.wait<Object>([
      _getProfilePayload(),
      _emptyListWhenUnavailable(getAccounts),
      _emptyListWhenUnavailable(getCards),
      _emptyListWhenUnavailable(() => getActivityTransactions(
          since: DateTime.now().subtract(const Duration(days: 30)))),
    ]);
    final profilePayload = results[0] as Map<String, dynamic>;
    final profile = UserProfile.fromJson(profilePayload);
    final embeddedOnboarding = profilePayload['onboarding'];
    final onboardingTasks = embeddedOnboarding is Map<String, dynamic>
        ? _onboardingTasksFromStatus(embeddedOnboarding)
        : await _emptyListWhenUnavailable(getOnboardingTasks);

    return DashboardSnapshot(
      profile: profile,
      accounts: results[1] as List<AccountBalance>,
      cards: results[2] as List<PaymentCard>,
      transactions: results[3] as List<LedgerTransaction>,
      onboarding: _withFirstLoginTasks(
        profile: profile,
        tasks: onboardingTasks,
      ),
    );
  }

  Future<void> freezeCard(String cardId, bool freeze) async {
    await _withFallback(
      () async {
        await _dio.post<void>(
          '/api/v1/mobile/cards/$cardId/${freeze ? 'freeze' : 'unfreeze'}',
          data: {
            'reason': freeze ? 'mobile_user_freeze' : 'mobile_user_unfreeze',
          },
        );
      },
      () {},
    );
  }

  Future<CardDiscount> validateCardDiscount(String code) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/cards/discount-codes/validate',
      data: {'code': code.trim().toUpperCase()},
    );
    return CardDiscount.fromJson(response.data ?? const {});
  }

  Future<void> orderCard({
    required String label,
    required bool virtual,
    String currency = 'USD',
    int? cardTypeId,
    String? productCode,
    String? phoneCode,
    String? phone,
    String? addressLine1,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? budgetId,
    String? discountCode,
    Map<String, dynamic>? legalAgreements,
  }) async {
    await _withFallback(
      () async {
        final address = _addressPayload(
          line1: addressLine1,
          city: city,
          state: state,
          country: country,
          postalCode: postalCode,
        );
        final payload = {
          'nickname': label,
          'cardName': label,
          'cardTypeId': cardTypeId ?? (virtual ? 1 : 2),
          'externalCardId': _newExternalCardId(cardTypeId),
          'productCode': productCode ?? (virtual ? 'virtual' : 'physical'),
          'currency': currency,
          if (budgetId != null && budgetId.trim().isNotEmpty)
            'budgetId': budgetId.trim(),
          if (phoneCode != null && phoneCode.trim().isNotEmpty)
            'phoneCode': phoneCode.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          if (address != null) 'billingAddress': address,
          if (address != null) 'deliveryAddress': address,
          if (discountCode != null && discountCode.trim().isNotEmpty)
            'discountCode': discountCode.trim().toUpperCase(),
          if (legalAgreements != null) 'legalAgreements': legalAgreements,
        };
        debugPrint('Ordering card via /api/v1/mobile/cards: $payload');
        await _dio.post<void>(
          '/api/v1/mobile/cards',
          data: payload,
        );
      },
      () {},
    );
  }

  Future<void> loadCard({
    required String cardId,
    required Money amount,
    String? token,
  }) async {
    await _withFallback(
      () async {
        await _dio.post<void>(
          '/api/v1/mobile/cards/$cardId/load',
          data: _moneyPayload(
            amount,
            extra: {
              if (token != null && token.trim().isNotEmpty)
                'Token': token.trim(),
            },
          ),
        );
      },
      () {},
    );
  }

  Future<void> topUpCard({
    required String cardId,
    required Money amount,
    String? token,
  }) async {
    await loadCard(cardId: cardId, amount: amount, token: token);
  }

  /// Starts a card-payment purchase of [token] (USDC/USDT) through the
  /// provider's Transak integration. The response carries the hosted
  /// checkout URL (`transakUrl`) and the order reference.
  Future<Map<String, dynamic>> buyCryptoWithCard({
    required String token,
    required String walletAddress,
    required double usdAmount,
  }) async {
    final response = await _dio.post<dynamic>(
      '/api/v1/mobile/wallets/top-up',
      data: {
        'Token': token,
        'WalletAddress': walletAddress,
        'Value': usdAmount,
      },
    );
    final value = response.data;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  Future<void> createPayee({
    required String paymentType,
    required String currency,
    required String paymentMethod,
    required String countryCode,
    required String firstName,
    required String lastName,
    required String accountNumber,
    String? displayName,
    String? bankName,
    String? routingCodeType,
    String? routingCodeValue,
    String? addressLine1,
    String? city,
    String? postalCode,
    String? comments,
    String? verificationMethod,
  }) async {
    await _withFallback(
      () async {
        await _dio.post<void>(
          '/api/v1/mobile/banking/payees',
          data: _payeePayload(
            paymentType: paymentType,
            currency: currency,
            paymentMethod: paymentMethod,
            countryCode: countryCode,
            firstName: firstName,
            lastName: lastName,
            accountNumber: accountNumber,
            displayName: displayName,
            bankName: bankName,
            routingCodeType: routingCodeType,
            routingCodeValue: routingCodeValue,
            bankCountry: countryCode,
            bankAddressLine1: addressLine1,
            bankCity: city,
            bankPostalCode: postalCode,
            payeeCountry: countryCode,
            payeeAddressLine1: addressLine1,
            payeeCity: city,
            payeePostalCode: postalCode,
            comments: comments,
            verificationMethod: verificationMethod,
          ),
        );
      },
      () {},
    );
  }

  Future<PayoutOtpInitiation> initiatePayeeCreation({
    required String paymentType,
    required String currency,
    required String paymentMethod,
    required String countryCode,
    required String firstName,
    required String lastName,
    required String accountNumber,
    String? userName,
    String? displayName,
    String? bankName,
    String? routingCodeType,
    String? routingCodeValue,
    String? bankCountry,
    String? bankAddressLine1,
    String? bankAddressLine2,
    String? bankCity,
    String? bankState,
    String? bankPostalCode,
    String? payeeCountry,
    String? payeeAddressLine1,
    String? payeeAddressLine2,
    String? payeeCity,
    String? payeeState,
    String? payeePostalCode,
    String? comments,
    String? verificationMethod,
  }) async {
    final payload = _payeePayload(
      paymentType: paymentType,
      currency: currency,
      paymentMethod: paymentMethod,
      countryCode: countryCode,
      firstName: firstName,
      lastName: lastName,
      accountNumber: accountNumber,
      userName: userName,
      displayName: displayName,
      bankName: bankName,
      routingCodeType: routingCodeType,
      routingCodeValue: routingCodeValue,
      bankCountry: bankCountry,
      bankAddressLine1: bankAddressLine1,
      bankAddressLine2: bankAddressLine2,
      bankCity: bankCity,
      bankState: bankState,
      bankPostalCode: bankPostalCode,
      payeeCountry: payeeCountry,
      payeeAddressLine1: payeeAddressLine1,
      payeeAddressLine2: payeeAddressLine2,
      payeeCity: payeeCity,
      payeeState: payeeState,
      payeePostalCode: payeePostalCode,
      comments: comments,
      verificationMethod: verificationMethod,
    );

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/banking/payees',
      data: payload,
    );
    return PayoutOtpInitiation.fromJson(_extractMap(response.data, 'payee'));
  }

  Future<void> confirmPayeeCreation({
    required String verificationToken,
  }) async {
    await _dio.post<void>(
      '/api/v1/mobile/banking/payees/confirm',
      data: {
        'verificationToken': verificationToken,
      },
    );
  }

  Future<void> createTransfer({
    required String fromAccountId,
    required String payeeId,
    required Money amount,
    required String reference,
  }) async {
    await _withFallback(
      () async {
        await _dio.post<void>(
          '/api/v1/mobile/banking/transfers',
          data: {
            'sourceAccountId': fromAccountId,
            'fromAccountId': fromAccountId,
            'payeeId': payeeId,
            'amount': amount.minorUnits / 100,
            'currency': amount.currency,
            'reference': reference,
          },
        );
      },
      () {},
    );
  }

  Future<void> createPayment({
    required String fromAccountId,
    required String payeeId,
    required Money amount,
    required String reference,
  }) async {
    await _withFallback(
      () async {
        await _dio.post<void>(
          '/api/v1/mobile/banking/transfers',
          data: {
            'sourceAccountId': fromAccountId,
            'fromAccountId': fromAccountId,
            'payeeId': payeeId,
            'destinationId': payeeId,
            'transferType': 'payee',
            'amount': amount.minorUnits / 100,
            'currency': amount.currency,
            'reference': reference,
          },
        );
      },
      () {},
    );
  }

  Future<PayoutQuote> createPayoutQuote({
    required String payeeId,
    required double amount,
    required String sourceCurrency,
    required String targetCurrency,
    String? lastQuoteId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/banking/quotations',
      data: {
        'PayeeId': int.tryParse(payeeId) ?? payeeId,
        'FromCurrency': sourceCurrency,
        'Amount': amount,
        'FeeMethod': 'INCLUDED',
        if (lastQuoteId != null && lastQuoteId.trim().isNotEmpty)
          'LastQuoteId': lastQuoteId.trim(),
        if (lastQuoteId != null && lastQuoteId.trim().isNotEmpty)
          'QuoteId': lastQuoteId.trim(),
      },
    );

    return PayoutQuote.fromJson(_extractMap(response.data, 'quote'))
        .withFallback(
      sourceAmount: amount,
      sourceCurrency: sourceCurrency,
      targetCurrency: targetCurrency,
    );
  }

  Future<PayoutCheck> checkPayout({
    required String payeeId,
    required String quotationId,
    required double amount,
    required String currency,
    String? balanceId,
    String? memo,
    String? reason,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/banking/payouts/check',
      data: {
        'PayeeId': int.tryParse(payeeId) ?? payeeId,
        'QuotationId': quotationId,
        'Amount': amount.toStringAsFixed(2),
        'Currency': currency,
        if (balanceId != null && balanceId.trim().isNotEmpty)
          'BalanceId': balanceId.trim(),
        if (memo != null && memo.trim().isNotEmpty) 'Memo': memo.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'Reason': reason.trim(),
      },
    );

    return PayoutCheck.fromJson(_extractMap(response.data, 'check'));
  }

  Future<PayoutOtpInitiation> initiatePayoutOtp({
    required String checkId,
    required String payeeId,
    required double amount,
    required String currency,
    String? balanceId,
    String? quoteRequestId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/banking/payouts/initiate',
      data: {
        'CheckId': checkId,
        if (quoteRequestId != null && quoteRequestId.trim().isNotEmpty)
          'QuoteRequestId': quoteRequestId.trim(),
        'PayeeId': int.tryParse(payeeId) ?? payeeId,
        'Amount': amount.toStringAsFixed(2),
        'Currency': currency,
        if (balanceId != null && balanceId.trim().isNotEmpty)
          'BalanceId': balanceId.trim(),
      },
    );

    return PayoutOtpInitiation.fromJson(_extractMap(response.data, 'otp'));
  }

  Future<OtpVerification> verifyPayoutOtp({
    required String verificationToken,
    required String otpCode,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/banking/otp/verify',
      data: {
        'VerificationToken': verificationToken,
        'OtpCode': otpCode,
      },
    );

    return OtpVerification.fromJson(_extractMap(response.data, 'otp'));
  }

  Future<PayoutOtpInitiation> resendPayoutOtp({
    required String verificationToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/banking/otp/resend',
      data: {
        'VerificationToken': verificationToken,
      },
    );

    return PayoutOtpInitiation.fromJson(_extractMap(response.data, 'otp'));
  }

  Future<void> confirmPayout({
    required String checkId,
    required String payeeId,
    required double amount,
    required String currency,
    String? balanceId,
    required String verificationToken,
    String? quoteRequestId,
  }) async {
    await _dio.post<void>(
      '/api/v1/mobile/banking/payouts',
      data: {
        'CheckId': checkId,
        if (quoteRequestId != null && quoteRequestId.trim().isNotEmpty)
          'QuoteRequestId': quoteRequestId.trim(),
        'VerificationToken': verificationToken,
        'PayeeId': int.tryParse(payeeId) ?? payeeId,
        'Amount': amount.toStringAsFixed(2),
        'Currency': currency,
        if (balanceId != null && balanceId.trim().isNotEmpty)
          'BalanceId': balanceId.trim(),
      },
    );
  }

  Future<void> submitBusinessProfile({
    required String legalName,
    required String registrationNumber,
    required String country,
    required String activity,
  }) async {
    await _withFallback(
      () async {
        await _dio.patch<void>(
          '/api/v1/mobile/business-onboarding/profile',
          data: {
            'businessName': legalName,
            'legalName': legalName,
            'registrationNumber': registrationNumber,
            'countryCode': country,
            'country': country,
            'industryCode': activity,
            'activity': activity,
          },
        );
      },
      () {},
    );
  }

  Future<Map<String, dynamic>> getBusinessOnboardingStatus() async {
    final response = await _dio.get<dynamic>(
      '/api/v1/mobile/business-onboarding/status',
    );
    final value = response.data;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  Future<Map<String, dynamic>> getBusinessOnboardingOptions() async {
    final response = await _dio.get<dynamic>(
      '/api/v1/mobile/business-onboarding/options',
    );
    final value = response.data;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  Future<Map<String, dynamic>> getBusinessCompliance() async {
    final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/mobile/business-onboarding/compliance');
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> businessCompliance(
      String operation, Map<String, dynamic> body) async {
    final suffix = operation.isEmpty ? '' : '/$operation';
    final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/mobile/business-onboarding/compliance$suffix',
        data: body);
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> createBusinessAssociatedPeople(
    List<Map<String, Object?>> people,
  ) async {
    return _withFallback(
      () async {
        final response = await _dio.post<dynamic>(
          '/api/v1/mobile/business-onboarding/associated-people',
          data: {
            'People': people.map(_equalsAssociatedPersonPayload).toList(),
          },
        );

        final value = response.data;
        if (value is List) {
          return {'associatedPeople': value};
        }
        if (value is Map) {
          return value.map((key, item) => MapEntry(key.toString(), item));
        }
        return const <String, dynamic>{};
      },
      () => {
        'associatedPeople': [
          for (var i = 0; i < people.length; i++) {'id': 'person_$i'},
        ],
      },
    );
  }

  Future<Map<String, dynamic>> submitDirectEqualsBusinessApplication(
    Map<String, Object?> payload,
  ) async {
    return _withFallback(
      () async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/v1/mobile/business-onboarding/application',
          data: _equalsBusinessApplicationPayload(payload),
        );

        return response.data ?? const <String, dynamic>{};
      },
      () => {'success': true},
    );
  }

  Future<Map<String, dynamic>> uploadBusinessOnboardingDocument({
    required String purpose,
    String? path,
    Uint8List? bytes,
    String? fileName,
    String? associatedPersonId,
  }) async {
    if ((path == null || path.trim().isEmpty) && bytes == null) {
      throw ArgumentError('A document path or bytes are required.');
    }
    return _withFallback(
      () async {
        final formData = FormData.fromMap({
          'Purpose': purpose,
          'File': bytes != null
              ? MultipartFile.fromBytes(
                  bytes,
                  filename: fileName?.trim().isNotEmpty == true
                      ? fileName!.trim()
                      : 'document',
                )
              : await MultipartFile.fromFile(path!),
        });
        final endpoint = associatedPersonId == null ||
                associatedPersonId.trim().isEmpty
            ? '/api/v1/mobile/business-onboarding/application/documents'
            : '/api/v1/mobile/business-onboarding/associated-people/${Uri.encodeComponent(associatedPersonId.trim())}/documents';

        final response =
            await _dio.post<Map<String, dynamic>>(endpoint, data: formData);
        return response.data ?? <String, dynamic>{};
      },
      () => <String, dynamic>{},
    );
  }

  Future<void> submitDirectEqualsBusinessApplicationForReview() async {
    await _withFallback(
      () async {
        await _dio.post<void>(
          '/api/v1/mobile/business-onboarding/application/submit',
          data: const <String, Object?>{},
        );
      },
      () {},
    );
  }
}

String _accountProviderKey(String provider) =>
    switch (provider.trim().toLowerCase()) {
      '1' || 'interlace' => 'interlace',
      '2' || 'equalsmoney' || 'equals money' => 'equalsmoney',
      '3' || 'unifiedswitch' => 'unifiedswitch',
      final value => value,
    };

bool _cardNeedsArtwork(Map<String, dynamic> card) {
  final parsed = PaymentCard.fromJson(card);
  return parsed.artworkUrl.isEmpty || parsed.network.isEmpty;
}

Map<String, dynamic> _unwrapCardMap(Map<String, dynamic> card) {
  for (final key in const ['card', 'Card', 'data', 'Data']) {
    final nested = card[key];
    if (nested is Map) {
      return nested.map((key, value) => MapEntry(key.toString(), value));
    }
  }
  return card;
}

Future<List<Map<String, dynamic>>> _enrichMissingCardArtwork(
  Dio dio,
  List<Map<String, dynamic>> cards,
  Object? cardsPayload,
) async {
  var enriched = cards;
  var tierId = _cardTierId(cardsPayload);
  if (tierId == null) {
    try {
      final currentTier =
          await dio.get<dynamic>('/api/v1/mobile/tiers/current');
      tierId = _currentTierId(currentTier.data);
    } catch (_) {
      // The generic tier response below remains a final metadata fallback.
    }
  }
  if (tierId != null) {
    try {
      final tier = await dio.get<dynamic>(
        '/api/v1/mobile/tiers/card-tier/$tierId',
      );
      enriched = _enrichCardsWithTierArtwork(enriched, tier.data);
    } catch (_) {
      // The generic tier response below may still contain artwork metadata.
    }
  }

  if (enriched.every((card) => !_cardNeedsArtwork(card))) {
    return enriched;
  }

  try {
    final tiers = await dio.get<dynamic>('/api/v1/mobile/tiers');
    enriched = _enrichCardsWithTierArtwork(enriched, tiers.data);
  } catch (_) {
    // Keep the issued card data and use the visual fallback when unavailable.
  }
  return enriched;
}

int? _currentTierId(Object? payload) {
  if (payload is! Map) return null;
  final map = payload.map((key, value) => MapEntry(key.toString(), value));
  final id = _firstIntValue(
    map,
    const ['selectedTierId', 'SelectedTierId', 'tierId', 'TierId', 'id', 'Id'],
  );
  if (id != null) return id;
  for (final key in const ['data', 'Data', 'result', 'Result']) {
    final nested = _currentTierId(map[key]);
    if (nested != null) return nested;
  }
  return null;
}

int? _cardTierId(Object? payload) {
  if (payload is! Map) return null;
  final map = payload.map((key, value) => MapEntry(key.toString(), value));
  for (final key in const ['tierInfo', 'TierInfo']) {
    final tierInfo = map[key];
    if (tierInfo is Map) {
      final normalized = tierInfo.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final id = _firstIntValue(
        normalized,
        const ['tierId', 'TierId', 'id', 'Id'],
      );
      if (id != null) return id;
    }
  }
  for (final key in const ['data', 'Data', 'result', 'Result']) {
    final id = _cardTierId(map[key]);
    if (id != null) return id;
  }
  return null;
}

Set<int> _cardArtworkIds(Map<String, dynamic> card) {
  final source = _unwrapCardMap(card);
  final result = <int>{};
  for (final key in const [
    'cardTypeId',
    'CardTypeId',
    'cardTypeTierId',
    'CardTypeTierId',
    'cardTypeSecondaryId',
    'CardTypeSecondaryId',
  ]) {
    final parsed = int.tryParse(source[key]?.toString() ?? '');
    if (parsed != null) result.add(parsed);
  }
  final nested = source['cardType'] ?? source['CardType'];
  if (nested is Map) {
    for (final key in const ['id', 'Id', 'cardTypeId', 'CardTypeId']) {
      final parsed = int.tryParse(nested[key]?.toString() ?? '');
      if (parsed != null) result.add(parsed);
    }
  }
  return result;
}

List<Map<String, dynamic>> _enrichCardsWithTierArtwork(
  List<Map<String, dynamic>> cards,
  Object? tierPayload,
) {
  final metadata = <Map<String, dynamic>>[];
  _collectCardArtwork(tierPayload, metadata);
  if (metadata.isEmpty) return cards;

  return cards.map((card) {
    if (!_cardNeedsArtwork(card) &&
        PaymentCard.fromJson(card).backArtworkUrl.isNotEmpty) {
      return card;
    }
    final cardTypeIds = _cardArtworkIds(card);
    if (cardTypeIds.isEmpty) return card;
    for (final candidate in metadata) {
      final candidateIds = <int>{};
      for (final key in const [
        'cardTypeId',
        'CardTypeId',
        'cardTypeTierId',
        'CardTypeTierId',
        'cardTypeSecondaryId',
        'CardTypeSecondaryId',
        'id',
        'Id',
      ]) {
        final value = _firstIntValue(candidate, [key]);
        if (value != null) candidateIds.add(value);
      }
      if (candidateIds.intersection(cardTypeIds).isNotEmpty) {
        final source = _unwrapCardMap(card);
        final existing = source['cardTypeMetadata'] ??
            source['CardTypeMetadata'] ??
            source['cardType'] ??
            source['CardType'];
        final metadata = <String, dynamic>{
          ...candidate,
          if (existing is Map)
            for (final entry in existing.entries)
              if (entry.value != null &&
                  entry.value.toString().trim().isNotEmpty)
                entry.key.toString(): entry.value,
        };
        return {...source, 'cardTypeMetadata': metadata};
      }
    }
    return card;
  }).toList();
}

void _collectCardArtwork(Object? value, List<Map<String, dynamic>> output) {
  if (value is List) {
    for (final item in value) {
      _collectCardArtwork(item, output);
    }
    return;
  }
  if (value is! Map) return;
  final map = value.map((key, item) => MapEntry(key.toString(), item));

  // Tier responses keep the orderable card type ID on the tier association,
  // while the artwork is nested under cardType with a different internal ID.
  // Preserve both identifiers so issued cards can be matched to their design.
  final nestedCardType = map['cardType'] ?? map['CardType'];
  if (nestedCardType is Map) {
    final nested = nestedCardType.map(
      (key, item) => MapEntry(key.toString(), item),
    );
    if (_firstNonEmptyText(nested, const [
          'cardImageUrl',
          'CardImageUrl',
          'cardPreviewUrl',
          'CardPreviewUrl',
          'cardThumbnailUrl',
          'CardThumbnailUrl',
          'cardBackImageUrl',
          'CardBackImageUrl',
          'cardBackThumbnailUrl',
          'CardBackThumbnailUrl',
          'cardBackPreviewUrl',
          'CardBackPreviewUrl',
        ]) !=
        null) {
      output.add({
        ...nested,
        if (map['cardTypeId'] != null) 'cardTypeId': map['cardTypeId'],
        if (map['CardTypeId'] != null) 'CardTypeId': map['CardTypeId'],
        if (map['cardTypeSecondaryId'] != null)
          'cardTypeSecondaryId': map['cardTypeSecondaryId'],
        if (map['CardTypeSecondaryId'] != null)
          'CardTypeSecondaryId': map['CardTypeSecondaryId'],
      });
    }
  }
  if (_firstNonEmptyText(map, const [
        'cardImageUrl',
        'CardImageUrl',
        'cardPreviewUrl',
        'CardPreviewUrl',
        'cardThumbnailUrl',
        'CardThumbnailUrl',
        'cardBackImageUrl',
        'CardBackImageUrl',
        'cardBackThumbnailUrl',
        'CardBackThumbnailUrl',
        'cardBackPreviewUrl',
        'CardBackPreviewUrl',
      ]) !=
      null) {
    output.add(map);
  }
  for (final item in map.values) {
    _collectCardArtwork(item, output);
  }
}

String? _firstNonEmptyText(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

int? _firstIntValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.round();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

Map<String, Object?> _equalsAssociatedPersonPayload(
  Map<String, Object?> person,
) {
  final addresses = person['addresses'];
  final rawAddress = addresses is List && addresses.isNotEmpty
      ? addresses.first
      : person['address'];
  final address = rawAddress is Map
      ? rawAddress.map((key, value) => MapEntry(key.toString(), value))
      : const <String, Object?>{};
  final streetName = _stringValue(address['streetName']);
  final buildingNumber = _stringValue(address['buildingNumber']);
  final buildingName = _stringValue(address['buildingName']);
  final city = _stringValue(address['city'] ?? address['townCity']);

  return _withoutEmptyValues({
    'firstName': person['firstName'],
    'lastName': person['lastName'],
    'dateOfBirth': person['dateOfBirth'],
    'emailAddress': person['emailAddress'],
    'nationalities': person['nationalities'],
    'taxId': person['taxId'],
    'phoneNumber': person['phoneNumber'],
    if (address.isNotEmpty)
      'address': _withoutEmptyValues({
        'addressLine1': _stringValue(address['addressLine1']).isNotEmpty
            ? address['addressLine1']
            : [buildingNumber, buildingName, streetName]
                .where((part) => part.isNotEmpty)
                .join(' '),
        'addressLine2': address['addressLine2'],
        'streetName': address['streetName'],
        'buildingNumber': address['buildingNumber'],
        'buildingName': address['buildingName'],
        'townCity': city,
        'postcode': address['postcode'],
        'countryCode': address['countryCode'],
        'region': address['region'],
        'city': city,
      }),
  });
}

Map<String, Object?> _equalsBusinessApplicationPayload(
  Map<String, Object?> payload,
) {
  final industry = _stringMap(payload['industry']);
  final features = _stringMap(payload['featureInformation']);
  final addresses = payload['addresses'];
  final people = payload['associatedPeople'];

  return _withoutEmptyValues({
    'Market': payload['market'] ?? payload['Market'],
    'BusinessType': payload['businessType'] ?? payload['type'],
    'CountryOfIncorporation': payload['countryOfIncorporation'],
    'RegionOfIncorporation': payload['regionOfIncorporation'],
    'RegisteredName': payload['registeredName'],
    'RegistrationNumber': payload['registrationNumber'],
    'TradingNames': payload['tradingNames'],
    'BusinessOverview': payload['businessOverview'],
    'IndustryMain': payload['industryMain'] ?? industry['main'],
    'IndustrySub': payload['industrySub'] ?? industry['sub'],
    'EmployeeCount': payload['employeeCount'],
    'IncorporationDate': payload['incorporationDate'],
    'PhoneNumber': payload['phoneNumber'],
    'TaxId': payload['taxId'],
    'Website': payload['website'],
    'BusinessPromotionDescription': payload['businessPromotionDescription'],
    'RequestedFeatures':
        payload['requestedFeatures'] ?? features['requestedFeatures'],
    'CardsInformation':
        payload['cardsInformation'] ?? features['cardsInformation'],
    'PaymentsInformation':
        payload['paymentsInformation'] ?? features['paymentsInformation'],
    if (addresses is List)
      'Addresses': addresses
          .whereType<Map>()
          .map((address) => _pascalCaseBusinessAddress(_stringMap(address)))
          .toList(),
    if (people is List)
      'AssociatedPeople': people
          .whereType<Map>()
          .map((person) => _pascalCaseAssociatedPersonLink(_stringMap(person)))
          .toList(),
  });
}

Map<String, Object?> _pascalCaseBusinessAddress(Map<String, Object?> address) {
  return _withoutEmptyValues({
    'AddressType': address['addressType'],
    'StreetName': address['streetName'],
    'BuildingNumber': address['buildingNumber'],
    'BuildingName': address['buildingName'],
    'Postcode': address['postcode'],
    'City': address['city'],
    'Region': address['region'],
    'CountryCode': address['countryCode'],
  });
}

Map<String, Object?> _pascalCaseAssociatedPersonLink(
  Map<String, Object?> person,
) {
  final ownership = person['ownershipPercentage'];
  return _withoutEmptyValues({
    'AssociatedPersonId': person['associatedPersonId'],
    'AssociationType': person['associationType'],
    'JobTitle': person['jobTitle'],
    'OwnershipPercentage': ownership is num ? ownership.round() : ownership,
  });
}

Map<String, Object?> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String _stringValue(Object? value) => value?.toString().trim() ?? '';

Map<String, Object?> _withoutEmptyValues(Map<String, Object?> values) {
  return Map.fromEntries(values.entries.where((entry) {
    final value = entry.value;
    return value != null && (value is! String || value.trim().isNotEmpty);
  }));
}

List<OnboardingTask> _withFirstLoginTasks({
  required UserProfile profile,
  required List<OnboardingTask> tasks,
}) {
  if (tasks.isNotEmpty || profile.isKycReady) {
    return tasks;
  }

  return const [
    OnboardingTask(
      id: 'complete_kyc',
      title: 'Complete KYC',
      description: 'Verify your identity to activate your account.',
      status: OnboardingTaskStatus.pending,
      route: '/kyc',
    ),
  ];
}

Future<List<T>> _emptyListWhenUnavailable<T>(
  Future<List<T>> Function() request,
) async {
  try {
    return await request();
  } on DioException catch (error) {
    final status = error.response?.statusCode;
    if (status == 400 || status == 401 || status == 404) {
      return const [];
    }

    rethrow;
  }
}

Map<String, Object?> _moneyPayload(
  Money amount, {
  Map<String, Object?> extra = const {},
}) {
  return {
    ...extra,
    'amount': amount.minorUnits / 100,
    'currency': amount.currency,
    'minorUnits': amount.minorUnits,
  };
}

Map<String, Object?> _payeePayload({
  required String paymentType,
  required String currency,
  required String paymentMethod,
  required String countryCode,
  required String firstName,
  required String lastName,
  required String accountNumber,
  String? userName,
  String? displayName,
  String? bankName,
  String? routingCodeType,
  String? routingCodeValue,
  String? bankCountry,
  String? bankAddressLine1,
  String? bankAddressLine2,
  String? bankCity,
  String? bankState,
  String? bankPostalCode,
  String? payeeCountry,
  String? payeeAddressLine1,
  String? payeeAddressLine2,
  String? payeeCity,
  String? payeeState,
  String? payeePostalCode,
  String? comments,
  String? verificationMethod,
}) {
  final routingCodes = routingCodeType != null &&
          routingCodeType.trim().isNotEmpty &&
          routingCodeValue != null &&
          routingCodeValue.trim().isNotEmpty
      ? [
          {
            'routingCodeType': routingCodeType.trim(),
            'routingCodeValue': routingCodeValue.trim(),
          },
        ]
      : const <Map<String, String>>[];
  final bankAddress = _addressPayload(
    line1: bankAddressLine1,
    line2: bankAddressLine2,
    city: bankCity,
    state: bankState,
    country: bankCountry ?? countryCode,
    postalCode: bankPostalCode,
  );
  final payeeAddress = _addressPayload(
    line1: payeeAddressLine1,
    line2: payeeAddressLine2,
    city: payeeCity,
    state: payeeState,
    country: payeeCountry ?? countryCode,
    postalCode: payeePostalCode,
  );
  final accountHolder = userName?.trim().isNotEmpty == true
      ? userName!.trim()
      : '$firstName $lastName'.trim();
  final resolvedName = displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : accountHolder;

  return {
    'name': resolvedName,
    'paymentType': paymentType,
    'currency': currency,
    'paymentMethod': paymentMethod,
    'countryCode': countryCode,
    'country': countryCode,
    'displayName': resolvedName,
    'firstName': firstName,
    'lastName': lastName,
    'userName': accountHolder,
    'accountNumber': accountNumber,
    'iban': accountNumber,
    if (routingCodeType != null &&
        routingCodeType.trim().toLowerCase() == 'bic')
      'bic': routingCodeValue,
    if (routingCodeType != null &&
        routingCodeType.trim().toLowerCase() == 'sort_code')
      'bankCode': routingCodeValue,
    'routingNumber': routingCodeValue,
    'routingCodeList': routingCodes,
    'routingCodes': routingCodes,
    if (bankName != null && bankName.trim().isNotEmpty)
      'bankName': bankName.trim(),
    if (payeeAddress != null) 'payeeAddress': payeeAddress,
    if (bankAddress != null) 'bankAddress': bankAddress,
    if (comments != null && comments.trim().isNotEmpty)
      'comments': comments.trim(),
    if (verificationMethod != null && verificationMethod.trim().isNotEmpty)
      'verificationMethod': verificationMethod.trim(),
  };
}

String _onboardingRoute(String action) {
  final normalized = action.toLowerCase();
  if (normalized == 'start_onboarding') {
    return '/kyc';
  }
  if (normalized.contains('payee')) {
    return '/money/payees';
  }
  if (normalized.contains('transfer')) {
    return '/money/pay';
  }
  if (normalized.contains('payment') || normalized.contains('mandate')) {
    return '/payments';
  }
  if (normalized.contains('wallet')) {
    return '/wallets';
  }
  if (normalized.contains('asset')) {
    return '/wallets/assets';
  }
  if (normalized.contains('deposit') || normalized.contains('address')) {
    return '/wallets/addresses';
  }
  if (normalized.contains('balance')) {
    return '/wallets/balances';
  }
  if (normalized.contains('provider') ||
      normalized.contains('budget') ||
      normalized.contains('equals')) {
    return '/onboarding/banking';
  }
  if (normalized.contains('sync') ||
      normalized.contains('export') ||
      normalized.contains('transaction')) {
    return '/transactions/status';
  }
  if (normalized.contains('kyc')) {
    return '/kyc';
  }
  if (normalized.contains('kyb') || normalized.contains('business')) {
    return '/business';
  }
  if (normalized.contains('card')) {
    return '/cards/order';
  }
  if (normalized.contains('tier')) {
    return '/tiers';
  }
  if (normalized.contains('bank')) {
    return '/onboarding/banking';
  }

  return '/home';
}

String _newExternalCardId(int? cardTypeId) {
  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  final suffix = cardTypeId == null ? 'card' : 'type-$cardTypeId';
  return 'mobile-$timestamp-$suffix';
}

Map<String, String>? _addressPayload({
  String? line1,
  String? line2,
  String? city,
  String? state,
  String? country,
  String? postalCode,
}) {
  final values = {
    'line1': line1?.trim() ?? '',
    'addressLine1': line1?.trim() ?? '',
    'addressLine2': line2?.trim() ?? '',
    'city': city?.trim() ?? '',
    'state': state?.trim() ?? '',
    'country': country?.trim().toUpperCase() ?? '',
    'postalCode': postalCode?.trim() ?? '',
  };
  if (values.values.every((value) => value.isEmpty)) {
    return null;
  }

  return Map.fromEntries(
    values.entries.where((entry) => entry.value.isNotEmpty),
  );
}

bool _isMissingCardAccount(DioException error) {
  if (error.response?.statusCode != 404) return false;
  Object? body = error.response?.data;
  // Older proxies put the upstream JSON error inside ProblemDetails.detail.
  for (var depth = 0; depth < 2; depth++) {
    if (body is String) {
      try {
        body = jsonDecode(body);
      } on FormatException {
        return false;
      }
    }
    if (body is! Map) return false;
    final code = body['code'] ?? body['Code'];
    if (code == 'ACCOUNT_NOT_FOUND') return true;
    body = body['detail'] ?? body['Detail'];
  }
  return false;
}

Future<T> _withFallback<T>(
  Future<T> Function() request,
  T Function() unusedFallback,
) async {
  return request();
}

Map<String, dynamic> _activityPagination(Map<String, dynamic>? json) {
  if (json == null) return const {};
  final data = json['data'] ?? json['Data'];
  final value = json['pagination'] ??
      json['Pagination'] ??
      (data is Map ? data['pagination'] ?? data['Pagination'] : null);
  return value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : const {};
}

int? _activityPageNumber(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

List<Map<String, dynamic>> _extractList(
    Map<String, dynamic>? json, String key) {
  final payload = _payloadValue(json, key);
  if (payload is List) {
    return payload.whereType<Map<String, dynamic>>().toList();
  }

  return const [];
}

Map<String, dynamic> _extractMap(Map<String, dynamic>? json, String key) {
  final payload = _payloadValue(json, key);
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  if (payload is Map) {
    return payload.map((key, value) => MapEntry(key.toString(), value));
  }

  return json ?? const {};
}

Object? _payloadValue(Map<String, dynamic>? json, String key) {
  if (json == null) {
    return null;
  }

  final pascalKey =
      key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';
  final data = json['data'] ?? json['Data'];

  return json[key] ??
      json[pascalKey] ??
      json['items'] ??
      json['Items'] ??
      (data is Map<String, dynamic>
          ? data[key] ??
              data[pascalKey] ??
              data['items'] ??
              data['Items'] ??
              data['list'] ??
              data['List']
          : null) ??
      data;
}
