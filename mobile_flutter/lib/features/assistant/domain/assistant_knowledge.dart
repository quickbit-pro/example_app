/// Local app help shown when the backend explicitly disables the concierge.
/// These maintained answers support app navigation without a model request.
class AssistantTopic {
  const AssistantTopic({
    required this.id,
    required this.prompt,
    required this.keywords,
    required this.answer,
    this.route,
    this.routeLabel,
  });

  final String id;

  /// Suggestion chip text.
  final String prompt;
  final List<String> keywords;
  final String answer;

  /// Optional deep link the answer can open.
  final String? route;
  final String? routeLabel;
}

const assistantTopics = <AssistantTopic>[
  AssistantTopic(
    id: 'send',
    prompt: 'How do I send money to a friend?',
    keywords: [
      'send',
      'transfer',
      'friend',
      'member',
      'request',
      'p2p',
      'pay someone'
    ],
    answer:
        'Open Send & request from Home. Enter the other member\'s nickname, email or phone number, choose USD, USDC or USDT, add the amount and a note, then confirm with your fingerprint, face or password. The first 10 transfers each day are free; after that a 1% fee applies. You can also request money the same way and the other member gets a notification.',
    route: '/send',
    routeLabel: 'Open Send & request',
  ),
  AssistantTopic(
    id: 'limits',
    prompt: 'How do I change my card limits?',
    keywords: ['limit', 'spending', 'daily', 'weekly', 'monthly', 'cap'],
    answer:
        'Open your card and tap Limit, or use Spending limits under Card controls. Set daily, weekly and monthly amounts; each one is capped by your tier, and the slider stops at that ceiling. Limits apply as soon as you save them.',
    route: '/cards',
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'topup',
    prompt: 'How do I load my card?',
    keywords: [
      'load',
      'top up',
      'topup',
      'top-up',
      'add money',
      'fund',
      'minimum'
    ],
    answer:
        'Open your card, tap Manage balance and choose Add to card. Money moves from your USD balance onto the card; the minimum load is USD 10.00. To move money back, use Unload card on the same screen.',
    route: '/cards',
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'kyc',
    prompt: 'How do I verify my identity?',
    keywords: [
      'verify',
      'verification',
      'kyc',
      'identity',
      'document',
      'passport',
      'selfie'
    ],
    answer:
        'Go to Settings and open Identity verification. You will be taken to our verification partner to scan an ID document and take a selfie; most checks finish within minutes. Cards and transfers unlock once the check is approved.',
    route: '/kyc',
    routeLabel: 'Start verification',
  ),
  AssistantTopic(
    id: 'freeze',
    prompt: 'My card is lost. What should I do?',
    keywords: ['lost', 'stolen', 'freeze', 'block', 'unfreeze', 'frozen'],
    answer:
        'Freeze the card straight away: open the card and tap Freeze. Payments are blocked until you unfreeze it, and nothing else changes. If the card is gone for good, contact support to replace it.',
    route: '/cards',
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'auto-freeze',
    prompt: 'What does auto freeze do?',
    keywords: [
      'auto freeze',
      'auto-freeze',
      'autofreeze',
      'automatic',
      'automatically',
      '10 minutes'
    ],
    answer:
        'Auto freeze is a switch under Card controls on each card. While it is on, the card freezes itself again 10 minutes after you unfreeze it, so it is only open for the payment you meant to make. Unfreeze it from the card page whenever you need it next.',
    route: '/cards',
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'fees',
    prompt: 'What fees do you charge?',
    keywords: ['fee', 'fees', 'cost', 'price', 'charge', 'subscription'],
    answer:
        'Card issue and monthly fees depend on your tier and card type; they are shown before you order a card. Member transfers are free for the first 10 a day, then 1%. Exchange quotes show the rate and fee before you confirm.',
    route: '/tiers',
    routeLabel: 'See tiers',
  ),
  AssistantTopic(
    id: 'security',
    prompt: 'How do I secure my account?',
    keywords: [
      'secure',
      'security',
      '2fa',
      'two-factor',
      'password',
      'biometric',
      'fingerprint',
      'duress',
      'device',
      'session'
    ],
    answer:
        'In Settings you can turn on two-factor authentication with recovery codes, enable fingerprint or face unlock, set a duress password that locks the account if it is ever used, change your password, and sign out other devices under Devices & sessions.',
    route: '/profile',
    routeLabel: 'Open Settings',
  ),
  AssistantTopic(
    id: 'crypto',
    prompt: 'How do I exchange USD to crypto?',
    keywords: [
      'crypto',
      'usdc',
      'usdt',
      'exchange',
      'bitcoin',
      'btc',
      'wallet',
      'deposit',
      'withdraw'
    ],
    answer:
        'Open Crypto from Accounts and tap Exchange to crypto or Exchange to USD. Only USDC and USDT can be exchanged with the USD balance, and the quote shows what you receive before you confirm. Deposit and Send move stablecoins on-chain.',
    route: '/wallets/assets',
    routeLabel: 'Open Crypto',
  ),
];

/// Picks the best topic for a free-text question, or null when nothing in
/// the help content matches.
AssistantTopic? matchAssistantTopic(String question) {
  final normalized = question.toLowerCase();
  AssistantTopic? best;
  var bestScore = 0;
  for (final topic in assistantTopics) {
    var score = 0;
    for (final keyword in topic.keywords) {
      if (normalized.contains(keyword)) score += keyword.length;
    }
    if (score > bestScore) {
      best = topic;
      bestScore = score;
    }
  }
  return best;
}
