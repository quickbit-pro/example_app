import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/dio_provider.dart';
import '../core/models/banking_models.dart';
import '../core/models/platform_models.dart';
import '../core/privacy/private_mode_provider.dart';
import '../core/theme/theme_preference_provider.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/auth/application/biometric_providers.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/biometric_authenticator.dart';
import '../features/banking/application/banking_providers.dart';
import '../features/cards/domain/card_control_capabilities.dart';
import '../features/cards/domain/card_limits.dart';
import '../features/dashboard/data/dashboard_providers.dart';
import '../features/dashboard/domain/dashboard_models.dart';
import '../features/notifications/application/notification_inbox_providers.dart';
import '../features/onboarding/application/account_setup_providers.dart';
import '../features/platform/application/platform_providers.dart';
import '../features/rewards/domain/rewards_models.dart';
import '../flavors.dart';

/// Fixture data is intentionally synthetic. No real account, card number,
/// balance, session, credential, merchant image URL, or API host is included.
const previewCards = [
  PaymentCard(
    id: 'preview-physical',
    label: 'Everyday card',
    last4: '4821',
    network: 'Mastercard',
    currency: 'USD',
    status: CardStatus.active,
    balance: Money(currency: 'USD', minorUnits: 245000),
    spendThisMonth: Money(currency: 'USD', minorUnits: 72850),
    limit: Money(currency: 'USD', minorUnits: 500000),
    virtual: false,
  ),
  PaymentCard(
    id: 'preview-virtual',
    label: 'Online card',
    last4: '9016',
    network: 'Mastercard',
    currency: 'USD',
    status: CardStatus.active,
    balance: Money(currency: 'USD', minorUnits: 35000),
    spendThisMonth: Money(currency: 'USD', minorUnits: 8950),
    limit: Money(currency: 'USD', minorUnits: 100000),
    virtual: true,
  ),
];

const previewDashboard = DashboardSnapshot(
  profile: UserProfile(
    id: 'preview-customer',
    name: 'Alex Morgan',
    email: 'alex@example.invalid',
    accountType: 'personal',
    kycStatus: 'approved',
    businessStatus: 'not_started',
    onboardingStatus: 'complete',
  ),
  accounts: [
    AccountBalance(
      id: 'preview-usd',
      name: 'US Dollar',
      iban: '',
      balance: Money(currency: 'USD', minorUnits: 648050),
      available: Money(currency: 'USD', minorUnits: 648050),
      provider: 'Equals Money',
      status: 'active',
    ),
    AccountBalance(
      id: 'preview-eur',
      name: 'Euro',
      iban: '',
      balance: Money(currency: 'EUR', minorUnits: 218000),
      available: Money(currency: 'EUR', minorUnits: 218000),
      provider: 'Equals Money',
      status: 'active',
    ),
  ],
  cards: previewCards,
  transactions: [],
  onboarding: [],
);

const previewPortfolio = PortfolioEstimate(
  baseCurrency: 'USD',
  total: 15482.75,
  valuedAt: null,
  isPartial: false,
  isStale: false,
  missingCurrencies: [],
  valuationRates: {'EUR': 1.1, 'BTC': 60000, 'USDT': 1},
);

final previewHome = HoppaDashboardSnapshot(
  customerName: 'Alex Morgan',
  accounts: const [
    HoppaFiatAccount(
      id: 'preview-usd',
      name: 'US Dollar',
      currency: 'USD',
      balance: 6480.50,
      available: 6480.50,
      iban: '',
      tint: Color(0xFF621A96),
      provider: 'Equals Money',
      isPrimary: true,
    ),
    HoppaFiatAccount(
      id: 'preview-eur',
      name: 'Euro',
      currency: 'EUR',
      balance: 2180,
      available: 2180,
      iban: '',
      tint: Color(0xFF0D7477),
      provider: 'Equals Money',
    ),
  ],
  holdings: const [
    HoppaCryptoHolding(
      symbol: 'BTC',
      name: 'Bitcoin',
      amount: .075,
      fiatValue: 4500,
      price: 60000,
      changePercent: 2.4,
      tint: Color(0xFFF7931A),
    ),
    HoppaCryptoHolding(
      symbol: 'USDT',
      name: 'Tether',
      amount: 904.25,
      fiatValue: 904.25,
      price: 1,
      changePercent: .01,
      tint: Color(0xFF26A17B),
    ),
  ],
  activities: [
    HoppaActivity(
      id: 'preview-coffee',
      title: 'Morning coffee',
      subtitle: 'Card payment',
      amount: -4.80,
      currency: 'USD',
      kind: HoppaActivityKind.card,
      timeLabel: 'Today',
      statusLabel: 'Completed',
      bookedAt: DateTime(2026, 9, 8, 9),
    ),
    HoppaActivity(
      id: 'preview-transfer',
      title: 'Account top-up',
      subtitle: 'Bank transfer',
      amount: 1250,
      currency: 'USD',
      kind: HoppaActivityKind.transfer,
      timeLabel: 'Yesterday',
      statusLabel: 'Completed',
      bookedAt: DateTime(2026, 9, 7, 12),
    ),
    HoppaActivity(
      id: 'preview-subscription',
      title: 'Music subscription',
      subtitle: 'Card payment',
      amount: -12.99,
      currency: 'USD',
      kind: HoppaActivityKind.card,
      timeLabel: 'Mon',
      statusLabel: 'Completed',
      bookedAt: DateTime(2026, 9, 6, 10),
    ),
  ],
  cards: previewCards,
  onboardingProgress: 1,
  marketSentiment: 'Neutral',
  requiresKyc: false,
  accountReady: true,
  exchangeEnabled: true,
  outflowsEnabled: true,
  referralsEnabled: true,
  vouchersEnabled: true,
  isBusinessAccount: false,
  portfolioEstimate: previewPortfolio,
);

List<Override> customerPreviewOverrides(AppBranding branding) => [
      appConfigProvider.overrideWithValue(AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'https://preview.invalid',
        branding: branding,
      )),
      dioProvider.overrideWith((ref) {
        final dio = Dio(BaseOptions(baseUrl: 'https://preview.invalid'));
        dio.httpClientAdapter = PreviewNoNetworkAdapter();
        ref.onDispose(dio.close);
        return dio;
      }),
      authControllerProvider.overrideWith(PreviewAuthController.new),
      privateModeProvider.overrideWith(_PreviewPrivateMode.new),
      themePreferenceProvider.overrideWith(_PreviewThemePreference.new),
      dashboardProvider.overrideWith((ref) async => previewDashboard),
      hoppaDashboardProvider.overrideWith((ref) async => previewHome),
      refreshHoppaDashboardProvider.overrideWith((ref) => () async {}),
      accountsProvider.overrideWith((ref) async => previewDashboard.accounts),
      cardsProvider.overrideWith((ref) async => previewCards),
      transactionsProvider.overrideWith((ref) async => []),
      portfolioEstimateProvider.overrideWith((ref) async => previewPortfolio),
      mobileTenantConfigProvider.overrideWith((ref) async => MobileTenantConfig(
            companyName: branding.appName,
            brandName: branding.appName,
            supportEmail: branding.supportEmail,
            referralsEnabled: true,
            referralRegistrationMode: 'optional',
            vouchersEnabled: true,
            existingAccountClaimEnabled: true,
            boomFiExchangeEnabled: true,
            walletOutflowsEnabled: true,
            equalsMoneyEnabled: true,
          )),
      currentTierProvider.overrideWith((ref) async => const PlatformResource(
            id: 'preview-standard',
            title: 'Standard',
            subtitle: 'Personal account',
            metadata: {'id': 'preview-standard', 'name': 'Standard'},
          )),
      unreadNotificationCountProvider.overrideWith((ref) async => 2),
      notificationInboxProvider.overrideWith((ref) async => []),
      authSessionsProvider.overrideWith((ref) async => []),
      accountSecurityProvider.overrideWith((ref) async => const AccountSecurity(
            twoFactorEnabled: true,
            recoveryCodesRemaining: 8,
            duressPasswordSet: false,
          )),
      biometricEnrollmentProvider
          .overrideWith((ref) async => const BiometricEnrollment(
                enabled: false,
                hasToken: false,
                email: '',
                userName: '',
                refreshToken: '',
              )),
      biometricCapabilityProvider
          .overrideWith((ref) async => const BiometricCapability(
                available: false,
                types: [],
                reason: BiometricUnavailableReason.unsupportedDevice,
              )),
      accountSetupDismissedProvider.overrideWith((ref) => true),
      accountSetupPromptedProvider.overrideWith((ref) => true),
      for (final card in previewCards) ...[
        cardDetailProvider(card.id).overrideWith((ref) async => card),
        cardTransactionsProvider(card.id).overrideWith((ref) async => []),
        cardLimitsProvider(card.id)
            .overrideWith((ref) async => const CardLimitsInfo(
                  currency: 'USD',
                  canUpdate: false,
                  capSource: 'none',
                )),
        cardControlCapabilitiesProvider(card.id).overrideWith(
            (ref) async => CardControlCapabilities.fromJson(const {})),
      ],
    ];

/// Hard network boundary: even a newly introduced screen provider cannot
/// accidentally use the API URL from an imported customer config.
class PreviewNoNetworkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.cancel,
      message:
          'This styling preview uses sample data. Live actions are disabled.',
    );
  }

  @override
  void close({bool force = false}) {}
}

class PreviewAuthController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState();

  @override
  Future<void> login(
      {required String email,
      required String password,
      bool persistForBiometric = false}) async {
    state = AsyncError(
      StateError(
          'This is a styling preview. Select Home to view sample accounts.'),
      StackTrace.current,
    );
  }

  @override
  Future<void> logout({bool clearBiometric = false}) async {
    state = const AsyncData(AuthState());
  }
}

class _PreviewPrivateMode extends PrivateModeController {
  @override
  Future<bool> build() async {
    Money.maskAmounts = false;
    return false;
  }

  @override
  Future<void> set(bool enabled) async {
    Money.maskAmounts = enabled;
    state = AsyncData(enabled);
  }
}

class _PreviewThemePreference extends ThemePreferenceController {
  @override
  Future<ThemeMode?> build() async => null;

  @override
  Future<void> setMode(ThemeMode? mode) async {
    state = AsyncData(mode);
  }
}
