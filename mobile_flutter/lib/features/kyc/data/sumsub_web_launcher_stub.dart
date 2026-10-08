import 'sumsub_kyc_adapter.dart';

/// Non-web platforms use the native Sumsub SDK instead.
Future<SumsubVerificationResult> launchSumsubWeb({
  required String accessToken,
  required Future<String> Function() onTokenExpiration,
}) =>
    throw UnsupportedError('The Sumsub WebSDK is only available in browsers.');
