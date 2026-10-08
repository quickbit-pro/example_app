import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/account_claim_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/account_setup_screen.dart';
import '../../features/business/presentation/business_screen.dart';
import '../../features/cards/presentation/card_detail_screen.dart';
import '../../features/cards/presentation/card_transactions_screen.dart';
import '../../features/cards/presentation/cards_screen.dart';
import '../../features/cards/presentation/order_card_screen.dart';
import '../../features/crypto/crypto.dart';
import '../../features/dashboard/dashboard.dart';
import '../../features/dashboard/presentation/home_refresh_on_navigation.dart';
import '../../features/kyc/presentation/kyc_screen.dart';
import '../../features/money/presentation/money_screen.dart';
import '../../features/platform/presentation/banking_services_screen.dart';
import '../../features/platform/application/platform_providers.dart';
import '../../features/platform/presentation/onboarding_banking_screen.dart';
import '../../features/platform/presentation/payments_screen.dart';
import '../../features/assistant/presentation/ask_ai_screen.dart';
import '../../features/peer/presentation/peer_composer.dart';
import '../../features/peer/presentation/peer_hub_screen.dart';
import '../../features/platform/presentation/tiers_screen.dart';
import '../../features/platform/presentation/transaction_status_screen.dart';
import '../../features/profile/presentation/kyc_status_overview_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/support/presentation/support_tickets_screen.dart';
import '../../features/rewards/domain/referral_copy.dart';
import '../../features/rewards/presentation/referral_earnings_screen.dart';
import '../../features/rewards/presentation/referral_friends_screen.dart';
import '../../features/rewards/presentation/rewards_screen.dart';
import '../../features/signup/presentation/signup_screen.dart';
import '../../features/signup/domain/signup_route_request.dart';
import '../../features/transactions/transactions.dart';
import '../../features/notifications/notifications.dart';
import '../../features/wallets/wallets.dart';
import '../../core/api/auth_token_provider.dart';
import '../routes.dart';
import '../shell/banking_shell.dart';
import 'app_back_navigation.dart';

/// Root navigator, used by flows that open UI without a widget context
/// (for example the browser KYC dialog started from a controller).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref
    ..onDispose(refreshNotifier.dispose)
    ..listen(authControllerProvider, (_, __) => refreshNotifier.refresh())
    ..listen(authTokenProvider, (_, __) => refreshNotifier.refresh());

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.login,
    refreshListenable: refreshNotifier,
    redirect: (context, state) => _authRedirect(ref, state),
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) {
          return _signupScreen(state.uri);
        },
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => _signupScreen(state.uri),
      ),
      GoRoute(
        path: AppRoutes.accountClaim,
        builder: (context, state) => const AccountClaimScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.accountSetup,
        builder: (context, state) => const AccountSetupScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => HomeRefreshOnNavigation(
          child: AppBackNavigation(child: BankingShell(child: child)),
        ),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: AppRoutes.accounts,
            builder: (context, state) => MoneyScreen(
              initialBudgetId: state.uri.queryParameters['budgetId'] ?? '',
              initialCurrency: state.uri.queryParameters['currency'] ?? '',
            ),
          ),
          GoRoute(
            path: AppRoutes.money,
            builder: (context, state) => MoneyScreen(
              initialBudgetId: state.uri.queryParameters['budgetId'] ?? '',
              initialCurrency: state.uri.queryParameters['currency'] ?? '',
            ),
          ),
          GoRoute(
            path: AppRoutes.transfer,
            builder: (context, state) =>
                const MoneyScreen(initialTab: MoneyTab.pay),
          ),
          GoRoute(
            path: AppRoutes.pay,
            builder: (context, state) => MoneyScreen(
              initialTab: MoneyTab.pay,
              initialBudgetId: state.uri.queryParameters['budgetId'] ?? '',
            ),
          ),
          GoRoute(
            path: AppRoutes.payees,
            builder: (context, state) =>
                const MoneyScreen(initialTab: MoneyTab.payees),
          ),
          GoRoute(
            path: AppRoutes.cards,
            builder: (context, state) => CardsScreen(
                initialCardId: state.uri.queryParameters['cardId'] ?? ''),
            routes: [
              GoRoute(
                path: 'order',
                builder: (context, state) => const OrderCardScreen(),
              ),
              GoRoute(
                path: ':cardId/transactions',
                builder: (context, state) => CardTransactionsScreen(
                  cardId: state.pathParameters['cardId']!,
                ),
              ),
              GoRoute(
                path: ':cardId',
                builder: (context, state) => CardDetailScreen(
                  cardId: state.pathParameters['cardId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.activity,
            builder: (context, state) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/support',
            builder: (context, state) => const SupportTicketsScreen(),
            routes: [
              GoRoute(
                  path: 'new',
                  builder: (context, state) => const NewSupportTicketScreen()),
              GoRoute(
                  path: ':ticketId',
                  builder: (context, state) => SupportTicketScreen(
                        key: ValueKey(state.pathParameters['ticketId']),
                        ticketId: state.pathParameters['ticketId']!,
                      )),
            ],
          ),
          GoRoute(
            path: AppRoutes.notifications,
            builder: (context, state) => const NotificationInboxScreen(),
          ),
          GoRoute(
            path: AppRoutes.kyc,
            builder: (context, state) => const KycScreen(),
          ),
          GoRoute(
            path: AppRoutes.kycStatus,
            builder: (context, state) => const HoppaKycStatusScreen(),
          ),
          GoRoute(
            path: AppRoutes.business,
            builder: (context, state) => const BusinessScreen(),
          ),
          GoRoute(
            path: AppRoutes.bankingOnboarding,
            builder: (context, state) => const OnboardingBankingScreen(),
          ),
          GoRoute(
            path: AppRoutes.bankingServices,
            builder: (context, state) => const BankingServicesScreen(),
          ),
          GoRoute(
            path: AppRoutes.tiers,
            builder: (context, state) => const TiersScreen(),
          ),
          GoRoute(
            path: AppRoutes.payments,
            builder: (context, state) => const PaymentsScreen(),
          ),
          GoRoute(
            path: AppRoutes.askAi,
            builder: (context, state) => const AskAiScreen(),
          ),
          GoRoute(
            path: AppRoutes.peer,
            builder: (context, state) => PeerHubScreen(
              initialMode: state.uri.queryParameters['mode'] == 'request'
                  ? PeerComposerMode.request
                  : PeerComposerMode.send,
            ),
          ),
          GoRoute(
            path: AppRoutes.wallets,
            builder: (context, state) =>
                const WalletsScreen(initialView: WalletView.assets),
          ),
          GoRoute(
            path: AppRoutes.walletAssets,
            builder: (context, state) =>
                const WalletsScreen(initialView: WalletView.assets),
          ),
          GoRoute(
            path: AppRoutes.walletAddresses,
            builder: (context, state) =>
                const WalletsScreen(initialView: WalletView.addresses),
          ),
          GoRoute(
            path: AppRoutes.walletBalances,
            builder: (context, state) => const MoneyScreen(),
          ),
          GoRoute(
            path: AppRoutes.walletExchange,
            builder: (context, state) =>
                const WalletsScreen(initialView: WalletView.exchange),
          ),
          GoRoute(
            path: AppRoutes.crypto,
            builder: (context, state) => const CryptoPortfolioScreen(),
          ),
          GoRoute(
            path: AppRoutes.cryptoMarket,
            builder: (context, state) => const CryptoMarketScreen(),
          ),
          GoRoute(
            path: AppRoutes.cryptoBuy,
            builder: (context, state) => const BuyCryptoScreen(),
          ),
          GoRoute(
            path: AppRoutes.cryptoExchange,
            builder: (context, state) => const CryptoTradeScreen(),
          ),
          GoRoute(
            path: AppRoutes.cryptoSell,
            builder: (context, state) => const CryptoTradeScreen(
              initialSide: CryptoTradeSide.sell,
            ),
          ),
          GoRoute(
            path: AppRoutes.transactions,
            builder: (context, state) => TransactionsScreen(
              accountId: state.uri.queryParameters['accountId'] ?? '',
              accountName: state.uri.queryParameters['accountName'] ?? '',
              budgetId: state.uri.queryParameters['budgetId'] ?? '',
              currency: state.uri.queryParameters['currency'] ?? '',
            ),
            routes: [
              GoRoute(
                path: 'status',
                builder: (context, state) => const TransactionStatusScreen(),
              ),
              GoRoute(
                path: ':transactionId',
                builder: (context, state) => TransactionDetailScreen(
                  transactionId: state.pathParameters['transactionId']!,
                  cardId: state.uri.queryParameters['cardId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: AppRoutes.rewards,
            builder: (context, state) => RewardsScreen(
              initialTab: state.uri.queryParameters['tab'],
            ),
            routes: [
              GoRoute(
                path: 'friends',
                builder: (context, state) => const ReferralFriendsScreen(),
              ),
              GoRoute(
                path: 'earnings',
                builder: (context, state) => ReferralEarningsScreen(
                  initialFilter: ReferralEarningsFilter.fromWire(
                    state.uri.queryParameters['status'],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

String? _authRedirect(Ref ref, GoRouterState state) {
  final authState = ref.read(authControllerProvider);
  final path = state.uri.path;
  final isAuthRoute = path == AppRoutes.login ||
      path == AppRoutes.signup ||
      path == AppRoutes.register ||
      path == AppRoutes.accountClaim ||
      path == AppRoutes.onboarding;

  // Do not mount a protected shell while authentication is still resolving.
  // On a browser reload at /home that used to start dashboard requests without
  // a token, cache their 401 errors, and then show the stale error after login.
  if (authState.isLoading) {
    if (isAuthRoute) return null;
    final from = Uri.encodeComponent(state.uri.toString());
    return '${AppRoutes.login}?from=$from';
  }

  final token = ref.read(authTokenProvider);
  final isAuthenticated = (authState.valueOrNull?.isAuthenticated ?? false) &&
      token != null &&
      token.isNotEmpty;

  if (!isAuthenticated && !isAuthRoute) {
    final from = Uri.encodeComponent(state.uri.toString());
    return '${AppRoutes.login}?from=$from';
  }

  if (isAuthenticated &&
      path.startsWith(AppRoutes.money) &&
      ref.read(mobileTenantConfigProvider).valueOrNull?.equalsMoneyEnabled ==
          false) {
    return AppRoutes.walletAssets;
  }

  if (isAuthenticated && isAuthRoute) {
    final from = state.uri.queryParameters['from'];
    if (from == null || from.isEmpty || from == AppRoutes.login) {
      return AppRoutes.home;
    }

    final target = Uri.tryParse(from);
    if (target == null ||
        target.hasScheme ||
        target.hasAuthority ||
        target.path == AppRoutes.login) {
      return AppRoutes.home;
    }

    return target.toString();
  }

  return null;
}

SignupScreen _signupScreen(Uri uri) {
  final request = SignupRouteRequest.fromUri(uri);
  return SignupScreen(
    invitationToken: request.invitationToken,
    initialReferralCode: request.referralCode,
    referralSource: request.referralSource,
    next: request.next,
  );
}

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
