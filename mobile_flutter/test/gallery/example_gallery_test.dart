// Visual gallery for the EXAMPLE Twilight redesign.
//
// Renders screens with fixture data at the design canvas viewports and writes
// PNGs with `flutter test --update-goldens test/gallery`. Compare against the
// `Example App.dc.html` artboards.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/app/shell/banking_shell.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_flutter/features/auth/application/biometric_providers.dart';
import 'package:mobile_flutter/features/auth/data/biometric_authenticator.dart';
import 'package:mobile_flutter/features/auth/presentation/account_claim_screen.dart';
import 'package:mobile_flutter/features/auth/presentation/login_screen.dart';
import 'package:mobile_flutter/features/notifications/domain/app_notification.dart';
import 'package:mobile_flutter/features/crypto/presentation/crypto_trade_screen.dart';
import 'package:mobile_flutter/features/onboarding/presentation/account_setup_screen.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/business/application/business_providers.dart';
import 'package:mobile_flutter/features/business/presentation/business_screen.dart';
import 'package:mobile_flutter/features/cards/domain/card_control_capabilities.dart';
import 'package:mobile_flutter/features/cards/presentation/card_detail_screen.dart';
import 'package:mobile_flutter/features/cards/presentation/cards_screen.dart';
import 'package:mobile_flutter/features/assistant/presentation/ask_ai_screen.dart';
import 'package:mobile_flutter/features/cards/domain/card_limits.dart';
import 'package:mobile_flutter/features/cards/presentation/card_limits_sheet.dart';
import 'package:mobile_flutter/features/profile/presentation/profile_screen.dart';
import 'package:mobile_flutter/features/rewards/presentation/rewards_screen.dart';
import 'package:mobile_flutter/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:mobile_flutter/features/transactions/presentation/transactions_screen.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/dashboard/data/dashboard_providers.dart';
import 'package:mobile_flutter/features/money/presentation/money_screen.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/wallets_screen.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/dashboard/presentation/dashboard_screen.dart';
import 'package:mobile_flutter/features/notifications/notifications.dart';
import 'package:mobile_flutter/features/peer/application/peer_providers.dart';
import 'package:mobile_flutter/features/peer/data/peer_transfers_api.dart';
import 'package:mobile_flutter/features/peer/presentation/peer_composer.dart';
import 'package:mobile_flutter/features/peer/presentation/peer_hub_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _outDir = String.fromEnvironment(
  'GALLERY_DIR',
  defaultValue: '/tmp/example-gallery',
);

const _branding = AppBranding(
  appName: 'EXAMPLE',
  brandId: 'example',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: 'Roboto',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'EXAMPLE',
);

const _tenant = MobileTenantConfig(
  companyName: 'EXAMPLE',
  brandName: 'EXAMPLE',
  referralsEnabled: true,
  referralRegistrationMode: 'open',
  vouchersEnabled: true,
  existingAccountClaimEnabled: true,
  boomFiExchangeEnabled: true,
  walletOutflowsEnabled: true,
  equalsMoneyEnabled: true,
  supportEmail: 'support@example.com',
);

final _cards = [
  const PaymentCard(
    id: 'card-1',
    label: 'EXAMPLE Metal',
    last4: '4271',
    network: 'Mastercard',
    currency: 'USD',
    status: CardStatus.active,
    balance: Money(currency: 'USD', minorUnits: 456235),
    spendThisMonth: Money(currency: 'USD', minorUnits: 77400),
    limit: Money(currency: 'USD', minorUnits: 1000000),
    virtual: false,
  ),
  const PaymentCard(
    id: 'card-2',
    label: 'Online subscriptions',
    last4: '8830',
    network: 'Mastercard',
    currency: 'USD',
    status: CardStatus.active,
    balance: Money(currency: 'USD', minorUnits: 24000),
    spendThisMonth: Money(currency: 'USD', minorUnits: 47900),
    limit: Money(currency: 'USD', minorUnits: 500000),
    virtual: true,
  ),
  const PaymentCard(
    id: 'card-3',
    label: 'Travel card',
    last4: '5512',
    network: 'Mastercard',
    currency: 'USD',
    status: CardStatus.frozen,
    balance: Money(currency: 'USD', minorUnits: 0),
    spendThisMonth: Money(currency: 'USD', minorUnits: 33100),
    limit: Money(currency: 'USD', minorUnits: 500000),
    virtual: true,
  ),
];

final _transactions = [
  LedgerTransaction(
    id: 'tx-1',
    title: 'MACROCENTER LARA',
    subtitle: 'Card payment · Completed',
    amount: const Money(currency: 'USD', minorUnits: -17425),
    bookedAt: DateTime(2026, 9, 1, 15, 24),
    type: TransactionType.card,
    status: 'completed',
    metadata: const {'merchantCategory': 'Groceries', 'card': '•••• 4271'},
  ),
  LedgerTransaction(
    id: 'tx-2',
    title: 'USDC → EUR convert',
    subtitle: 'Exchange · Completed',
    amount: const Money(currency: 'EUR', minorUnits: 45920),
    bookedAt: DateTime(2026, 8, 31, 9, 15),
    type: TransactionType.transfer,
    status: 'completed',
  ),
  LedgerTransaction(
    id: 'tx-3',
    title: 'Withdrawal to USD Account',
    subtitle: 'Pending',
    amount: const Money(currency: 'USD', minorUnits: -30000),
    bookedAt: DateTime(2026, 8, 27, 12, 0),
    type: TransactionType.payment,
    status: 'pending',
  ),
  LedgerTransaction(
    id: 'tx-4',
    title: 'Salary',
    subtitle: 'Top up · Completed',
    amount: const Money(currency: 'USD', minorUnits: 285000),
    bookedAt: DateTime(2026, 8, 28, 9, 0),
    type: TransactionType.topUp,
    status: 'completed',
  ),
  LedgerTransaction(
    id: 'tx-5',
    title: 'Uber',
    subtitle: 'Card payment · Declined',
    amount: const Money(currency: 'USD', minorUnits: -2460),
    bookedAt: DateTime(2026, 8, 26, 22, 10),
    type: TransactionType.card,
    status: 'declined',
  ),
  LedgerTransaction(
    id: 'tx-6',
    title: 'Transfer to Ayşe K.',
    subtitle: 'Transfer · Completed',
    amount: const Money(currency: 'USD', minorUnits: -42000),
    bookedAt: DateTime(2026, 8, 25, 18, 40),
    type: TransactionType.transfer,
    status: 'completed',
  ),
];

final _dashboard = DashboardSnapshot(
  profile: const UserProfile(
    id: 'u1',
    name: 'Naem Kaya',
    email: 'naem@example.com',
    accountType: 'personal',
    kycStatus: 'approved',
    interlaceKycApproved: true,
    businessStatus: 'not_started',
    onboardingStatus: 'complete',
  ),
  accounts: const [
    AccountBalance(
      id: 'usd',
      name: 'USD Account',
      iban: 'GB29EQMN60161331926578',
      balance: Money(currency: 'USD', minorUnits: 456235),
      available: Money(currency: 'USD', minorUnits: 456235),
      provider: 'Equals Money',
      status: 'active',
    ),
    AccountBalance(
      id: 'eur',
      name: 'Euro Account',
      iban: 'DE89370400440532015678',
      balance: Money(currency: 'EUR', minorUnits: 623475),
      available: Money(currency: 'EUR', minorUnits: 623475),
      provider: 'Equals Money',
      status: 'active',
    ),
  ],
  cards: _cards,
  transactions: _transactions,
  onboarding: const [],
);

const _hoppa = HoppaDashboardSnapshot(
  customerName: 'Naem Kaya',
  accounts: [
    HoppaFiatAccount(
      id: 'usd',
      name: 'USD Account',
      currency: 'USD',
      balance: 4562.35,
      available: 4562.35,
      iban: 'GB29EQMN60161331921234',
      tint: Colors.blue,
      provider: 'Equals Money',
      isPrimary: true,
    ),
    HoppaFiatAccount(
      id: 'eur',
      name: 'Euro Account',
      currency: 'EUR',
      balance: 6234.75,
      available: 6234.75,
      iban: 'DE89370400440532015678',
      tint: Colors.blue,
      provider: 'Equals Money',
    ),
    HoppaFiatAccount(
      id: 'boom-usd',
      name: 'USD balance',
      currency: 'USD',
      balance: 4778,
      available: 4778,
      iban: '',
      tint: Colors.teal,
      provider: 'BoomFi',
    ),
  ],
  holdings: [
    HoppaCryptoHolding(
      symbol: 'BTC',
      name: 'Bitcoin',
      amount: .0641,
      fiatValue: 4318.90,
      price: 67377,
      changePercent: 4.2,
      tint: Colors.orange,
    ),
    HoppaCryptoHolding(
      symbol: 'ETH',
      name: 'Ethereum',
      amount: 1.184,
      fiatValue: 2742.60,
      price: 2316,
      changePercent: 2.8,
      tint: Colors.blueGrey,
    ),
    HoppaCryptoHolding(
      symbol: 'USDC',
      name: 'USD Coin',
      amount: 1420,
      fiatValue: 1420,
      price: 1,
      changePercent: 0,
      tint: Colors.blue,
    ),
    HoppaCryptoHolding(
      symbol: 'USDT',
      name: 'Tether',
      amount: 505.75,
      fiatValue: 505.75,
      price: 1,
      changePercent: 0,
      tint: Colors.green,
    ),
  ],
  activities: [
    HoppaActivity(
      id: 'tx-1',
      title: 'MACROCENTER LARA',
      subtitle: 'Card payment · USD Account',
      amount: -174.25,
      currency: 'USD',
      kind: HoppaActivityKind.card,
      timeLabel: 'Today, 15:24',
      statusLabel: 'Completed',
    ),
    HoppaActivity(
      id: 'tx-2',
      title: 'Spotify',
      subtitle: 'Subscription · Virtual card',
      amount: -9.99,
      currency: 'USD',
      kind: HoppaActivityKind.card,
      timeLabel: 'Today, 09:15',
      statusLabel: 'Completed',
    ),
    HoppaActivity(
      id: 'tx-3',
      title: 'Amazon',
      subtitle: 'Shopping · Virtual card',
      amount: -89.99,
      currency: 'USD',
      kind: HoppaActivityKind.card,
      timeLabel: 'Yesterday, 21:42',
      statusLabel: 'Completed',
    ),
    HoppaActivity(
      id: 'tx-4',
      title: 'Salary',
      subtitle: 'Transfer in · USD Account',
      amount: 2850,
      currency: 'USD',
      kind: HoppaActivityKind.deposit,
      timeLabel: 'Aug 28, 2026',
      statusLabel: 'Completed',
    ),
  ],
  cards: [],
  onboardingProgress: 1,
  marketSentiment: 'positive',
  requiresKyc: false,
  accountReady: true,
  exchangeEnabled: true,
  outflowsEnabled: true,
  referralsEnabled: true,
  vouchersEnabled: true,
  isBusinessAccount: false,
  portfolioEstimate: PortfolioEstimate(
    baseCurrency: 'USD',
    total: 24562.35,
    valuedAt: null,
    isPartial: false,
    isStale: false,
    missingCurrencies: [],
    providerTotals: [],
  ),
);

HoppaDashboardSnapshot get _hoppaWithCards => HoppaDashboardSnapshot(
      customerName: _hoppa.customerName,
      accounts: _hoppa.accounts,
      holdings: _hoppa.holdings,
      activities: _hoppa.activities,
      cards: _cards,
      onboardingProgress: 1,
      marketSentiment: 'positive',
      requiresKyc: false,
      accountReady: true,
      exchangeEnabled: true,
      outflowsEnabled: true,
      referralsEnabled: true,
      vouchersEnabled: true,
      isBusinessAccount: false,
      portfolioEstimate: _hoppa.portfolioEstimate,
    );

const _peerAna = PeerUser(
  userId: 'u-2',
  firstName: 'Ana',
  lastName: 'Kovač',
  initials: 'AK',
  avatarColor: Color(0xFF27D7C2),
  maskedEmail: 'an***@example.com',
);

const _peerBo = PeerUser(
  userId: 'u-3',
  firstName: 'Bo',
  lastName: 'Lee',
  initials: 'BL',
  avatarColor: Color(0xFFF2B94B),
  maskedPhone: '+********456',
);

const _peerMia = PeerUser(
  userId: 'u-4',
  firstName: 'Mia',
  lastName: 'Novak',
  initials: 'MN',
  avatarColor: Color(0xFFFF6474),
);

final _peerRequests = PeerRequests(
  received: [
    PeerPaymentRequest(
      id: 'r-1',
      sent: false,
      otherUser: _peerAna,
      amount: 42.5,
      currency: 'USD',
      note: 'Dinner on Friday',
      status: 'pending',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      expiresAt: DateTime.now().add(const Duration(days: 6)),
    ),
  ],
  sent: [
    PeerPaymentRequest(
      id: 'r-2',
      sent: true,
      otherUser: _peerBo,
      amount: 10,
      currency: 'USDC',
      status: 'pending',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      expiresAt: DateTime.now().add(const Duration(days: 5)),
    ),
  ],
  history: [
    PeerPaymentRequest(
      id: 'r-3',
      sent: true,
      otherUser: _peerMia,
      amount: 60,
      currency: 'USD',
      note: 'Concert tickets',
      status: 'accepted',
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
      expiresAt: DateTime.now().add(const Duration(days: 3)),
      respondedAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ],
);

final _peerRecent = [
  PeerTransfer(
    id: 't-1',
    sent: true,
    otherUser: _peerBo,
    amount: 25,
    currency: 'USD',
    status: 'completed',
    fee: 0,
    note: 'Tickets',
    createdAt: DateTime.now().subtract(const Duration(hours: 5)),
  ),
  PeerTransfer(
    id: 't-2',
    sent: false,
    otherUser: _peerAna,
    amount: 8,
    currency: 'USDT',
    status: 'completed',
    fee: 0,
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  PeerTransfer(
    id: 't-3',
    sent: false,
    otherUser: _peerMia,
    amount: 60,
    currency: 'USD',
    status: 'completed',
    fee: 0,
    note: 'Concert tickets',
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
];

final _peerContacts = [
  PeerContact(id: 'c-1', user: _peerAna, addedAt: DateTime(2026, 8, 1)),
  PeerContact(id: 'c-2', user: _peerBo, addedAt: DateTime(2026, 8, 9)),
  PeerContact(
      id: 'c-3',
      user: _peerMia,
      addedAt: DateTime(2026, 8, 20),
      nickname: 'Mia N.'),
];

const _peerFee = PeerFeeInfo(
  freeTransfersPerDay: 10,
  transfersUsedToday: 2,
  freeTransfersRemaining: 8,
  feePercent: 1,
  feeAmount: 0,
  feeCurrency: 'USD',
  feeApplies: false,
  isRateLimited: false,
  rateLimitSecondsRemaining: 0,
  dailySendLimit: 50,
  sendsRemainingToday: 48,
  minAmount: 0.01,
  maxAmount: 1000000,
  currencies: ['USD', 'USDC', 'USDT'],
);

const _cardLimits = CardLimitsInfo(
  currency: 'USD',
  canUpdate: true,
  capSource: 'card_type',
  daily: 250,
  monthly: 3000,
  capDaily: 500,
  capWeekly: 2000,
  capMonthly: 6000,
  tierName: 'Pro',
);

List<Override> _overrides() => [
      cardLimitsProvider('card-1').overrideWith((ref) async => _cardLimits),
      peerRequestsProvider.overrideWith((ref) async => _peerRequests),
      peerRecentProvider.overrideWith((ref) async => _peerRecent),
      peerContactsProvider.overrideWith((ref) async => _peerContacts),
      peerTransfersEnabledProvider.overrideWith((ref) async => true),
      peerAvailableBalancesProvider.overrideWith(
        (ref) async => {'USD': 1240.18, 'USDC': 310.5, 'USDT': 0},
      ),
      peerFeeInfoProvider.overrideWith((ref) async => _peerFee),
      appConfigProvider.overrideWithValue(
        const AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'https://example.invalid',
          branding: _branding,
        ),
      ),
      mobileTenantConfigProvider.overrideWith((ref) async => _tenant),
      dashboardProvider.overrideWith((ref) async => _dashboard),
      hoppaDashboardProvider.overrideWith((ref) async => _hoppaWithCards),
      cardsProvider.overrideWith((ref) async => _cards),
      tiersProvider.overrideWith((ref) async => _tiers),
      currentTierProvider.overrideWith((ref) async => _tiers.first),
      accountsProvider.overrideWith((ref) async => _dashboard.accounts),
      payeesProvider.overrideWith(
        (ref) async => const [
          Payee(
            id: 'p1',
            name: 'Lara Mihelič',
            accountReference: 'SI56 0000 4410',
            firstName: 'Lara',
            lastName: 'Mihelič',
            paymentType: 'SEPA',
            paymentMethod: 'SEPA',
            currency: 'EUR',
            bankName: 'NLB',
            provider: 'Equals Money',
            status: 'active',
          ),
        ],
      ),
      businessOnboardingStatusProvider.overrideWith((ref) async => const {}),
      businessOnboardingOptionsProvider.overrideWith(
        (ref) async => const BusinessOnboardingOptions(industries: []),
      ),
      transactionsProvider.overrideWith((ref) async => _transactions),
      activityTransactionsProvider.overrideWith((ref) async => _transactions),
      unreadNotificationCountProvider.overrideWith((ref) async => 3),
      cardDetailProvider.overrideWith(
        (ref, id) async => _cards.firstWhere((card) => card.id == id),
      ),
      cardTransactionsProvider.overrideWith((ref, id) async => const []),
      cardControlCapabilitiesProvider.overrideWith(
        (ref, id) async => const CardControlCapabilities(
          canFreeze: true,
          canRevealSecureData: true,
          canSetPin: true,
          canUpdateLimits: true,
          canMerchantLock: false,
          canControlOnlinePayments: false,
          canControlContactless: false,
          canControlAtm: false,
          canControlInternational: false,
          isMerchantLocked: false,
          lockedMerchantName: '',
          supportedActions: [],
          limits: {},
        ),
      ),
      rewardsSnapshotProvider.overrideWith(
        (ref) async => const RewardsSnapshot(
          config: _tenant,
          referralSummary: {
            'ReferralCode': 'EXAMPLE28',
            'ReferralPath': 'https://example.com/r/EXAMPLE28',
            'CurrentLevel': {'Name': 'Pro'},
            'Progress': {'CurrentValue': 3, 'NextThreshold': 5},
            'Referrals': {'Invited': 8, 'Successful': 3, 'InProgress': 2},
            'Commissions': {'Available': 1, 'Currency': 'USD'},
          },
          assignedVouchers: [],
          voucherStatus: {'enabled': true},
        ),
      ),
      kycDetailedStatusProvider.overrideWith(
        (ref) async => const KycDetailedStatus(
          hoppaStatus: 'approved',
          bankStatus: 'approved',
          cardIssuerStatus: 'approved',
          nextAction: '',
          equalsMoneyAccountId: 'eq-1',
          equalsMoneyApproved: true,
          equalsMoneyStatus: 'active',
        ),
      ),
      budgetsProvider.overrideWith(
        (ref) async => const [
          PlatformResource(
            id: 'b1',
            title: 'Account balance',
            subtitle: 'Equals Money',
            metadata: {
              'id': 'b1',
              'name': 'Account balance',
              'provider': 'EqualsMoney',
              'balances': [
                {'currency': 'USD', 'amount': 4562.35},
                {'currency': 'EUR', 'amount': 6234.75},
              ],
            },
          ),
          PlatformResource(
            id: 'b2',
            title: 'Operations budget',
            subtitle: 'Equals Money',
            metadata: {
              'id': 'b2',
              'name': 'Operations budget',
              'provider': 'EqualsMoney',
              'balances': [
                {'currency': 'GBP', 'amount': 1860},
                {'currency': 'EUR', 'amount': 120},
              ],
            },
          ),
          PlatformResource(
            id: 'b3',
            title: 'Travel budget',
            subtitle: 'Equals Money',
            metadata: {
              'id': 'b3',
              'name': 'Travel budget',
              'provider': 'EqualsMoney',
              'balances': [
                {'currency': 'EUR', 'amount': 940},
              ],
            },
          ),
        ],
      ),
      hoppaWalletAssetsProvider.overrideWith(
        (ref) async => const [
          HoppaWalletAsset(
            symbol: 'BTC',
            name: 'Bitcoin',
            network: 'Bitcoin',
            amount: .0641,
            fiatValue: 4318.90,
            address: 'bc1qxy',
            tint: Colors.orange,
            walletId: 'w1',
          ),
          HoppaWalletAsset(
            symbol: 'ETH',
            name: 'Ethereum',
            network: 'Ethereum',
            amount: 1.184,
            fiatValue: 2742.60,
            address: '0xabc',
            tint: Colors.blueGrey,
            walletId: 'w2',
          ),
          HoppaWalletAsset(
            symbol: 'USDC',
            name: 'USD Coin',
            network: 'Ethereum (ERC-20)',
            amount: 1420,
            fiatValue: 1420,
            address: '0xdef',
            tint: Colors.blue,
            walletId: 'w3',
          ),
          HoppaWalletAsset(
            symbol: 'USDT',
            name: 'Tether',
            network: 'Tron (TRC-20)',
            amount: 505.75,
            fiatValue: 505.75,
            address: 'Txyz',
            tint: Colors.green,
            walletId: 'w4',
          ),
        ],
      ),
      hoppaWalletAddressesProvider.overrideWith((ref) async => const []),
      hoppaWalletBalancesProvider.overrideWith((ref) async => const []),
      exchangeOverviewProvider.overrideWith(
        (ref) async => const BoomFiExchangeOverview(
          accountId: 1,
          accountName: 'Naem Kaya',
          accountEnabled: true,
          accountState: 'active',
          balances: [
            BoomFiExchangeBalance(
              accountId: 1,
              currency: 'USDC',
              amount: 1860,
              pendingAmount: 0,
              chainId: 1,
              chainName: 'Ethereum',
              tokenAddress: '0x1',
            ),
            BoomFiExchangeBalance(
              accountId: 1,
              currency: 'EUR',
              amount: 720.40,
              pendingAmount: 0,
              chainId: 0,
              chainName: '',
              tokenAddress: '',
            ),
            BoomFiExchangeBalance(
              accountId: 1,
              currency: 'USDT',
              amount: 31.68,
              pendingAmount: 0,
              chainId: 1,
              chainName: 'Ethereum',
              tokenAddress: '0x2',
            ),
          ],
          settlementAccounts: [],
          subAccounts: [],
          fiatFundingCurrencies: ['EUR'],
        ),
      ),
      exchangeTransfersProvider.overrideWith((ref) async => const []),
      notificationInboxProvider.overrideWith(
        (ref) async => [
          AppNotification(
            id: 'n1',
            eventType: 'payment',
            title: 'Payment submitted',
            body:
                '€1,250.00 to Lara Mihelič is on its way. Reference Invoice 2026-091.',
            route: '/transactions',
            createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
            readAt: null,
          ),
          AppNotification(
            id: 'n2',
            eventType: 'card',
            title: 'Card •••• 4271 used online',
            body: '\$84.20 at Amazon. Not you? Freeze the card from My Card.',
            route: '/cards',
            createdAt: DateTime.now().subtract(const Duration(hours: 3)),
            readAt: null,
          ),
          AppNotification(
            id: 'n3',
            eventType: 'reward',
            title: 'Referral reward earned',
            body: 'Your invite was accepted.',
            route: '/rewards',
            createdAt: DateTime.now().subtract(const Duration(hours: 6)),
            readAt: null,
          ),
          AppNotification(
            id: 'n4',
            eventType: 'transfer',
            title: 'Salary received',
            body: '+\$2,850.00 from Northwind Ltd into USD Account.',
            route: '/transactions',
            createdAt:
                DateTime.now().subtract(const Duration(days: 1, hours: 4)),
            readAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
          AppNotification(
            id: 'n5',
            eventType: 'kyc',
            title: 'Identity verified',
            body: 'Your KYC review is complete. Banking features are unlocked.',
            route: '/kyc',
            createdAt: DateTime.now().subtract(const Duration(days: 4)),
            readAt: DateTime.now().subtract(const Duration(days: 4)),
          ),
        ],
      ),
      biometricCapabilityProvider.overrideWith(
        (ref) async => const BiometricCapability(
          available: true,
          types: [BiometricType.face],
          reason: BiometricUnavailableReason.none,
        ),
      ),
      biometricEnrollmentProvider.overrideWith(
        (ref) async => const BiometricEnrollment(
          enabled: true,
          hasToken: true,
          email: 'naem@example.com',
          userName: 'Naem Kaya',
          refreshToken: 'x',
        ),
      ),
    ];

Future<void> _loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final entity in dir.listSync()) {
    final name = entity.uri.pathSegments.last;
    if (entity is File && name.startsWith('Roboto-') && name.endsWith('.ttf')) {
      final bytes = entity.readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
  }
  await loader.load();
  final icons = File('${dir.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await iconLoader.load();
  }
}

Widget _app(String initialLocation, {required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => BankingShell(child: child),
        routes: [
          GoRoute(
            path: '/ask',
            builder: (context, state) => const AskAiScreen(),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/cards',
            builder: (context, state) => const CardsScreen(),
            routes: [
              GoRoute(
                path: ':cardId',
                builder: (context, state) => CardDetailScreen(
                  cardId: state.pathParameters['cardId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/activity',
            builder: (context, state) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/transactions/:transactionId',
            builder: (context, state) => TransactionDetailScreen(
              transactionId: state.pathParameters['transactionId']!,
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/money',
            builder: (context, state) => const MoneyScreen(),
          ),
          GoRoute(
            path: '/wallets/assets',
            builder: (context, state) =>
                const WalletsScreen(initialView: WalletView.assets),
          ),
          GoRoute(
            path: '/wallets/exchange',
            builder: (context, state) =>
                const WalletsScreen(initialView: WalletView.exchange),
          ),
          GoRoute(
            path: '/rewards',
            builder: (context, state) => const RewardsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationInboxScreen(),
          ),
          GoRoute(
            path: '/business',
            builder: (context, state) => const BusinessScreen(),
          ),
          GoRoute(
            path: '/setup',
            builder: (context, state) => const AccountSetupScreen(),
          ),
          GoRoute(
            path: '/crypto/buy',
            builder: (context, state) => const CryptoTradeScreen(),
          ),
          GoRoute(
            path: '/money/pay',
            builder: (context, state) =>
                const MoneyScreen(initialTab: MoneyTab.pay),
          ),
        ],
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/signup-review',
        builder: (context, state) => const SignupScreen(initialStep: 3),
      ),
      GoRoute(
        path: '/account-claim',
        builder: (context, state) => const AccountClaimScreen(),
      ),
      GoRoute(
        path: '/send',
        builder: (context, state) => const PeerHubScreen(),
      ),
      GoRoute(
        path: '/card-limits',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Card')),
          body: CardLimitsSheet(card: _cards.first),
        ),
      ),
      GoRoute(
        path: '/send-compose',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Send money')),
          body: const Padding(
            padding: EdgeInsets.all(16),
            child: PeerComposer(initialRecipient: _peerAna),
          ),
        ),
      ),
    ],
  );
  final themes = buildAppThemes(_branding);
  return ProviderScope(
    overrides: overrides,
    child: RepaintBoundary(
      key: const ValueKey('gallery'),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: themes.light,
        darkTheme: themes.dark,
        themeMode: ThemeMode.dark,
        routerConfig: router,
      ),
    ),
  );
}

Future<void> _snap(
  WidgetTester tester,
  String name,
  Size size,
  Widget app,
) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(app);
  // Some screens run indefinite animations (biometric prompts, shimmer), so
  // advance a fixed amount of time instead of waiting for the tree to settle.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  await expectLater(
    find.byKey(const ValueKey('gallery')),
    matchesGoldenFile(Uri.file('$_outDir/$name.png')),
  );
}

const _tiers = [
  PlatformResource(
    id: 'tier-1',
    title: 'Standard',
    subtitle: 'active',
    metadata: {
      'tierId': 1,
      'tierName': 'Standard',
      'monthlyFee': '0 USD',
      'cardLimit': '5,000 USD / month',
    },
  ),
  PlatformResource(
    id: 'tier-2',
    title: 'Premium',
    subtitle: 'active',
    metadata: {
      'tierId': 2,
      'tierName': 'Premium',
      'monthlyFee': '9 USD',
      'cardLimit': '25,000 USD / month',
    },
  ),
];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });

  final cases = <(String, String, Size)>[
    ('home_393', '/home', const Size(393, 852)),
    ('home_834', '/home', const Size(834, 1194)),
    ('home_1440', '/home', const Size(1440, 900)),
    ('cards_393', '/cards', const Size(393, 852)),
    ('cards_1440', '/cards', const Size(1440, 900)),
    ('card_393', '/cards/card-1', const Size(393, 852)),
    ('card_1440', '/cards/card-1', const Size(1440, 900)),
    ('transactions_393', '/activity', const Size(393, 852)),
    ('transactions_1440', '/activity', const Size(1440, 900)),
    ('transaction_393', '/transactions/tx-1', const Size(393, 852)),
    ('settings_393', '/profile', const Size(393, 852)),
    ('settings_1440', '/profile', const Size(1440, 900)),
    ('rewards_393', '/rewards', const Size(393, 852)),
    ('rewards_1440', '/rewards', const Size(1440, 900)),
    ('money_393', '/money', const Size(393, 852)),
    ('money_1440', '/money', const Size(1440, 900)),
    ('crypto_393', '/wallets/assets', const Size(393, 852)),
    ('exchange_393', '/wallets/exchange', const Size(393, 852)),
    ('crypto_1440', '/wallets/assets', const Size(1440, 900)),
    ('exchange_1440', '/wallets/exchange', const Size(1440, 900)),
    ('notifications_393', '/notifications', const Size(393, 852)),
    ('notifications_1440', '/notifications', const Size(1440, 900)),
    ('pay_1440', '/money/pay', const Size(1440, 900)),
    ('login_393', '/login', const Size(393, 852)),
    ('login_1440', '/login', const Size(1440, 900)),
    ('signup_393', '/signup', const Size(393, 852)),
    ('claim_393', '/account-claim', const Size(393, 852)),
    ('claim_1440', '/account-claim', const Size(1440, 900)),
    ('signup_1440', '/signup', const Size(1440, 900)),
    ('signup_review_393', '/signup-review', const Size(393, 852)),
    ('signup_review_1440', '/signup-review', const Size(1440, 900)),
    ('exchange_crypto_393', '/crypto/buy', const Size(393, 852)),
    ('exchange_crypto_1440', '/crypto/buy', const Size(1440, 900)),
    ('setup_393', '/setup', const Size(393, 852)),
    ('setup_1440', '/setup', const Size(1440, 900)),
    ('business_393', '/business', const Size(393, 852)),
    ('business_1440', '/business', const Size(1440, 900)),
    ('peer_393', '/send', const Size(393, 852)),
    ('peer_1440', '/send', const Size(1440, 900)),
    ('peer_compose_393', '/send-compose', const Size(393, 852)),
    ('card_limits_393', '/card-limits', const Size(393, 852)),
    ('ask_393', '/ask', const Size(393, 852)),
    ('ask_1440', '/ask', const Size(1440, 900)),
    ('card_1440_limits', '/cards/card-1', const Size(1440, 900)),
  ];
  for (final (name, route, size) in cases) {
    testWidgets(
      name,
      (tester) async {
        await _snap(tester, name, size, _app(route, overrides: _overrides()));
      },
      // Only runs when a target directory is supplied:
      //   flutter test --update-goldens --dart-define=GALLERY_DIR=/path/out test/gallery
      skip: !const bool.hasEnvironment('GALLERY_DIR'),
    );
  }
}
