import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/dio_provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/locale_preference_provider.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../data/kyc_api.dart';
import '../data/sumsub_kyc_adapter.dart';
import '../data/sumsub_web_launcher.dart';

final kycApiProvider = Provider<KycApi>((ref) {
  return KycApi(ref.watch(dioProvider));
});

final sumsubKycAdapterProvider = Provider<SumsubKycAdapter>((ref) {
  final preferred = ref.watch(localePreferenceProvider) ??
      WidgetsBinding.instance.platformDispatcher.locale;
  final supported = appLanguages.any((l) => l.code == preferred.languageCode);
  return SumsubKycAdapter(locale: supported ? preferred : const Locale('en'));
});

final occupationCodesProvider = FutureProvider<List<OccupationCode>>((ref) {
  return ref.watch(kycApiProvider).getOccupationCodes();
});

/// How the verification was launched. On web the hosted Sumsub page opens
/// in a new tab; the screen then offers to reopen it or check the status.
enum KycLaunchOutcome { submitted, openedInNewTab, popupBlocked }

/// The hosted verification link for the current attempt, kept so the screen
/// can reopen it from a button (a direct click is never popup-blocked).
final hostedKycLinkProvider = StateProvider<Uri?>((ref) => null);

final kycControllerProvider =
    AsyncNotifierProvider<KycController, KycLaunchOutcome?>(
  KycController.new,
);

class KycController extends AsyncNotifier<KycLaunchOutcome?> {
  @override
  Future<KycLaunchOutcome?> build() async => null;

  Future<void> startKyc(Map<String, Object?> applicantProfile) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final api = ref.read(kycApiProvider);
      await api.startOnboarding();

      if (kIsWeb) {
        // Browsers prefer Hoppa's hosted Sumsub page: no domain whitelist,
        // no embedded SDK. Fall back to the WebSDK when it is unavailable.
        final hosted = await _hostedKycUrl(api, applicantProfile);
        if (hosted != null) {
          ref.read(hostedKycLinkProvider.notifier).state = hosted;
          ref.invalidate(dashboardProvider);
          ref.invalidate(onboardingProvider);
          ref.invalidate(kycDetailedStatusProvider);
          // New tab so the customer keeps the app open; browsers allow this
          // shortly after the button press, otherwise the screen offers a
          // button that opens it from a direct click.
          final opened = await launchUrl(
            hosted,
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: '_blank',
          );
          return opened
              ? KycLaunchOutcome.openedInNewTab
              : KycLaunchOutcome.popupBlocked;
        }
      }

      final token =
          await api.createSumsubToken(applicantProfile: applicantProfile);
      Future<String> refreshToken() async {
        final refreshedToken = await ref
            .read(kycApiProvider)
            .createSumsubToken(applicantProfile: applicantProfile);
        return refreshedToken.token;
      }

      if (kIsWeb) {
        // Browsers host the Sumsub WebSDK; the native SDK has no web build.
        await launchSumsubWeb(
          accessToken: token.token,
          onTokenExpiration: refreshToken,
        );
      } else {
        await ref.read(sumsubKycAdapterProvider).startVerification(
              accessToken: token.token,
              onTokenExpiration: refreshToken,
            );
      }
      await ref.read(kycApiProvider).markKycSubmitted();
      ref.invalidate(dashboardProvider);
      ref.invalidate(onboardingProvider);
      ref.invalidate(kycDetailedStatusProvider);
      return KycLaunchOutcome.submitted;
    });
  }

  Future<Uri?> _hostedKycUrl(
    KycApi api,
    Map<String, Object?> applicantProfile,
  ) async {
    try {
      return await api.createHostedKycUrl(applicantProfile: applicantProfile);
    } on DioException catch (error) {
      // No hosted page (endpoint missing, provider refused, network) means
      // we use the embedded SDK instead of stranding the customer.
      debugPrint(
        'Hosted KYC URL unavailable (${error.response?.statusCode}): '
        '${error.response?.data ?? error.message}',
      );
      return null;
    }
  }
}
