import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_idensic_mobile_sdk_plugin/flutter_idensic_mobile_sdk_plugin.dart';

class SumsubVerificationResult {
  const SumsubVerificationResult({
    required this.success,
    required this.status,
    this.errorType,
    this.errorMessage,
  });

  final bool success;
  final String status;
  final String? errorType;
  final String? errorMessage;
}

class SumsubKycAdapter {
  const SumsubKycAdapter({this.locale = const Locale('en')});

  final Locale locale;

  Future<SumsubVerificationResult> startVerification({
    required String accessToken,
    required Future<String> Function() onTokenExpiration,
  }) async {
    if (accessToken.isEmpty) {
      throw ArgumentError.value(
        accessToken,
        'accessToken',
        'Must not be empty',
      );
    }

    final sdk = SNSMobileSDK.init(accessToken, onTokenExpiration)
        .withLocale(locale)
        .withDebug(kDebugMode)
        .withHandlers(
      onStatusChanged: (newStatus, oldStatus) {
        debugPrint('SumSub status changed: $oldStatus -> $newStatus');
      },
      onEvent: (event) {
        debugPrint('SumSub event: $event');
      },
    ).withLogHandler((level, message) {
      debugPrint('SumSub [$level] $message');
    }).build();

    final result = await sdk.launch();
    final verificationResult = SumsubVerificationResult(
      success: result.success,
      status: result.status.name,
      errorType: result.errorType?.name,
      errorMessage: result.errorMsg,
    );

    if (!result.success) {
      final details = [
        'status=${verificationResult.status}',
        if (verificationResult.errorType != null)
          'error=${verificationResult.errorType}',
        if (verificationResult.errorMessage != null)
          verificationResult.errorMessage,
      ].join(', ');
      throw StateError('SumSub SDK did not complete successfully: $details');
    }

    return verificationResult;
  }
}
