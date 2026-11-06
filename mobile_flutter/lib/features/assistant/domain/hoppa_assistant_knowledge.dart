import '../../../app/routes.dart';
import 'assistant_knowledge.dart';

/// Hoppa app guidance used by both Help and matching Ask AI questions.
/// Keep account-specific amounts, eligibility and timing in the live app.
const hoppaAssistantTopics = <AssistantTopic>[
  AssistantTopic(
    id: 'topup',
    prompt: 'How do I add money to my card?',
    keywords: [
      'add money',
      'load',
      'top up',
      'topup',
      'top-up',
      'fund my card'
    ],
    answer:
        'Open Cards, select your card and tap Manage balance. Choose the option to load or add money to the card, enter an amount and review the details before confirming. Check the available balance, minimum amount and any fees shown in the app. Balance changes are unavailable while the card is frozen.',
    route: AppRoutes.cards,
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'declined',
    prompt: 'Why was my card payment declined?',
    keywords: [
      'declined',
      'decline',
      'payment failed',
      'card not working',
      'cannot pay'
    ],
    answer:
        'Open Cards and select the card. Check that it is active and unfrozen, has enough available balance and has suitable spending limits. Review any card controls or merchant restrictions. Open the payment in the card activity to check its details. If you still need help, create a support ticket with the date, amount and merchant name. Never include your full card number, PIN or security code.',
    route: AppRoutes.cards,
    routeLabel: 'Check my card',
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
        'Open Identity verification in Settings and follow the instructions to submit the requested documents and selfie. Check the verification status in the app for progress or requests for more information. If a check needs attention, follow the displayed instructions or contact Support. Approval and feature availability depend on your account status.',
    route: AppRoutes.kyc,
    routeLabel: 'Open identity verification',
  ),
  AssistantTopic(
    id: 'support',
    prompt: 'How do I contact Hoppa support?',
    keywords: ['support', 'help', 'human', 'contact', 'ticket', 'agent'],
    answer:
        'Open Settings, then Support tickets under Help & legal. Choose New support ticket, describe the issue and submit it. Return to the ticket to read and send replies. Replies are not immediate. Include useful details such as the date, amount and transaction reference, but never passwords, PINs, full card numbers or security codes.',
    route: '/support',
    routeLabel: 'Open Support tickets',
  ),
  AssistantTopic(
    id: 'freeze',
    prompt: 'My card is lost or stolen. What should I do?',
    keywords: ['lost', 'stolen', 'freeze', 'block', 'unfreeze', 'frozen'],
    answer:
        'Open Cards, select the affected card and use Freeze. If the card is lost or stolen, keep it frozen and contact Support for help with the next steps. Review recent card activity and report payments you do not recognise. If you find the card and it is safe to use, you can unfreeze it from the card screen.',
    route: AppRoutes.cards,
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'limits',
    prompt: 'How do I change my card spending limits?',
    keywords: [
      'limit',
      'limits',
      'spending',
      'daily',
      'weekly',
      'monthly',
      'cap'
    ],
    answer:
        'Open your card and look for Limit or Spending limits under Card controls. Where available, adjust the daily, weekly or monthly amount and save. The app shows the allowed limits for your card and tier. Contact Support if you cannot change a limit you need help with.',
    route: AppRoutes.cards,
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'send',
    prompt: 'How do I send or request money?',
    keywords: [
      'send money',
      'transfer',
      'friend',
      'member',
      'request money',
      'p2p',
      'pay someone'
    ],
    answer:
        'Open Send & request from Home. Find the other member using their nickname, email or phone number, choose the available currency and enter the amount. Review the recipient, amount and any fee before confirming. To ask another member to pay you, choose the request option and follow the steps.',
    route: AppRoutes.peer,
    routeLabel: 'Open Send & request',
  ),
  AssistantTopic(
    id: 'fees',
    prompt: 'Where can I check fees and tiers?',
    keywords: [
      'fee',
      'fees',
      'cost',
      'price',
      'charge',
      'subscription',
      'tier',
      'tiers'
    ],
    answer:
        'Open Tiers to review the available plans. Card fees depend on the card type and tier; review the details before ordering. For transfers and exchanges, check the fee and final amount on the review screen before confirming. Ask AI cannot guarantee a fee for your account.',
    route: AppRoutes.tiers,
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
        'Open Settings to manage your password, two-factor authentication and biometric unlock. Keep recovery codes private and stored safely. Review Devices & sessions and sign out devices you no longer use or do not recognise. If you suspect unauthorised access, contact Support. Never share passwords, PINs or one-time security codes in chat.',
    route: AppRoutes.profile,
    routeLabel: 'Open Settings',
  ),
  AssistantTopic(
    id: 'crypto',
    prompt: 'Where can I manage crypto and exchanges?',
    keywords: [
      'crypto',
      'usdc',
      'usdt',
      'exchange',
      'wallet',
      'deposit',
      'withdraw'
    ],
    answer:
        'Open Crypto from Accounts to see your available assets and actions. Choose Exchange to review the quote before confirming. For an on-chain deposit or send, use the asset and network shown in the app and check the destination carefully. Available assets, networks, fees and limits are shown in the relevant screen.',
    route: AppRoutes.walletAssets,
    routeLabel: 'Open Crypto',
  ),
  AssistantTopic(
    id: 'order',
    prompt: 'How do I order a card?',
    keywords: [
      'order',
      'new card',
      'get a card',
      'physical card',
      'virtual card'
    ],
    answer:
        'Open Cards and choose Order card. Select an available card type and complete the requested details, including a shipping address if required. Review the fees and requirements before confirming. If no card types are available, check your verification status and tier or contact Support.',
    route: AppRoutes.orderCard,
    routeLabel: 'Order a card',
  ),
  AssistantTopic(
    id: 'activate',
    prompt: 'How do I activate a delivered card?',
    keywords: ['activate', 'activation', 'delivered', 'received my card'],
    answer:
        'After your card arrives, open Cards and select it. If Activate card is available, choose it and follow the confirmation steps. If activation fails or the option is missing, check the status shown on the card and contact Support.',
    route: AppRoutes.cards,
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'pin',
    prompt: 'Where can I set my card PIN?',
    keywords: ['pin', 'set pin', 'change pin'],
    answer:
        'Open your card and look for Set PIN in its controls. Follow the secure steps in the app if this feature is available for your card. Never type your PIN in Ask AI or a support ticket.',
    route: AppRoutes.cards,
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'unload',
    prompt: 'How do I move money off my card?',
    keywords: [
      'unload',
      'move money off',
      'back to balance',
      'money back',
      'off my card'
    ],
    answer:
        'Open your card and tap Manage balance. Choose Unload card or Move money off card if available, enter the amount and review the details. The app shows your available balance and any restrictions. You cannot move money while the card is frozen.',
    route: AppRoutes.cards,
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'auto-freeze',
    prompt: 'What does auto freeze do?',
    keywords: [
      'auto freeze',
      'auto-freeze',
      'autofreeze',
      'automatically',
      '10 minutes'
    ],
    answer:
        'Auto freeze is a control on your card. When enabled, the card freezes again 10 minutes after you unfreeze it. Open the card to unfreeze it when you need to pay, or manage Auto freeze under Card controls.',
    route: AppRoutes.cards,
    routeLabel: 'Go to Cards',
  ),
  AssistantTopic(
    id: 'activity',
    prompt: 'Where can I check a transaction or pending payment?',
    keywords: [
      'transaction',
      'pending',
      'payment status',
      'history',
      'receipt',
      'activity'
    ],
    answer:
        'Open Transactions to find the payment and view its details and status. For card payments, you can also open the card and review Recent transactions or View all. A pending status does not confirm that a payment has completed. If the status is unclear or you need help, contact Support with the transaction reference.',
    route: AppRoutes.transactions,
    routeLabel: 'Open Transactions',
  ),
  AssistantTopic(
    id: 'dispute',
    prompt: 'What if I do not recognise a card payment?',
    keywords: [
      'do not recognise',
      'do not recognize',
      'unrecognised',
      'unrecognized',
      'unauthorised',
      'unauthorized',
      'dispute',
      'fraud'
    ],
    answer:
        'Freeze the affected card from Cards and review its recent activity. Create a support ticket describing the payment, including its date, amount and merchant or transaction reference. Support can help investigate and explain the available next steps. Do not share your full card number, PIN or security code.',
    route: '/support',
    routeLabel: 'Open Support tickets',
  ),
  AssistantTopic(
    id: 'rewards',
    prompt: 'Where can I find referrals and vouchers?',
    keywords: [
      'reward',
      'rewards',
      'referral',
      'referrals',
      'invite',
      'voucher',
      'vouchers',
      'redeem'
    ],
    answer:
        'Open Rewards to view the referral and voucher features available for your account. Check the displayed terms before sharing an invite or redeeming a voucher. Referral progress and earnings appear in Rewards; eligibility and availability depend on the current programme and your account.',
    route: AppRoutes.rewards,
    routeLabel: 'Open Rewards',
  ),
];

/// Match complete words so 'shipping' never matches 'PIN'. Exact FAQ prompts
/// take precedence over keywords shared by several topics.
AssistantTopic? matchHoppaAssistantTopic(String question) {
  final normalized = question.toLowerCase().trim();
  for (final topic in hoppaAssistantTopics) {
    if (topic.prompt.toLowerCase() == normalized) return topic;
  }
  AssistantTopic? best;
  var bestScore = 0;
  for (final topic in hoppaAssistantTopics) {
    var score = 0;
    for (final keyword in topic.keywords) {
      if (RegExp('\\b${RegExp.escape(keyword)}\\b').hasMatch(normalized)) {
        score += keyword.length;
      }
    }
    if (score > bestScore) {
      best = topic;
      bestScore = score;
    }
  }
  return best;
}
