abstract final class AppRoutes {
  static const login = '/login';
  static const signup = '/signup';
  static const register = '/auth/register';
  static const accountClaim = '/account-claim';
  static const onboarding = '/onboarding';
  static const accountSetup = '/setup';
  static const home = '/home';
  static const accounts = '/accounts';
  static const money = '/money';
  static const transfer = '/money/transfer';
  static const pay = '/money/pay';
  static const payees = '/money/payees';
  static const cards = '/cards';
  static const orderCard = '/cards/order';
  static const activity = '/activity';
  static const kyc = '/kyc';
  static const kycStatus = '/kyc/status';
  static const business = '/business';
  static const bankingOnboarding = '/onboarding/banking';
  static const bankingServices = '/banking/services';
  static const tiers = '/tiers';
  static const payments = '/payments';
  static const peer = '/send';
  static const askAi = '/ask';
  static const peerRequest = '/send?mode=request';
  static const wallets = '/wallets';
  static const walletAssets = '/wallets/assets';
  static const walletAddresses = '/wallets/addresses';
  static const walletBalances = '/wallets/balances';
  static const walletExchange = '/wallets/exchange';
  static const crypto = '/crypto';
  static const cryptoMarket = '/crypto/market';
  static const cryptoBuy = '/crypto/buy';
  static const cryptoExchange = '/crypto/exchange';
  static const cryptoSell = '/crypto/sell';
  static const transactions = '/transactions';
  static const transactionStatus = '/transactions/status';
  static const profile = '/profile';
  static const rewards = '/rewards';
  static const rewardsFriends = '/rewards/friends';
  static const rewardsEarnings = '/rewards/earnings';
  static const notifications = '/notifications';

  /// The rewards workspace opened on one of its tabs (desktop keeps the tab
  /// in the query so a reload lands on the same one).
  static String rewardsTab(String tab) =>
      Uri(path: rewards, queryParameters: {'tab': tab}).toString();

  /// The earnings ledger preset to a delivery state; `all` is the bare route.
  static String rewardsEarningsFiltered(String status) => status == 'all'
      ? rewardsEarnings
      : Uri(path: rewardsEarnings, queryParameters: {'status': status})
          .toString();

  static String cardsWithSelection(String cardId) =>
      Uri(path: cards, queryParameters: {'cardId': cardId}).toString();

  static String cardDetail(String cardId) => '$cards/$cardId';

  static String cardTransactions(String cardId) =>
      '$cards/$cardId/transactions';

  static String transactionDetail(String transactionId) =>
      '$transactions/$transactionId';
}
