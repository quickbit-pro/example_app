import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/banking_models.dart';
import '../../auth/data/web_install_prompt.dart';

/// The phone wallets a card can be added to by hand.
///
/// There is no push provisioning yet, so on either platform the card has to
/// be typed into the wallet app; what differs is which app, and the words on
/// its buttons.
enum MobileWallet {
  apple(
    rowTitle: 'Add to Apple Wallet',
    rowSubtitle: 'Enter the card in the Wallet app to pay with your iPhone',
    rowSubtitleShort: 'Pay with your iPhone',
    intro:
        'Apple Wallet does not add this card automatically yet. Enter its details in the Wallet app once and it is ready for Apple Pay.',
    steps: [
      'Open the Wallet app on your iPhone and tap the + button in the top-right corner.',
      'Tap "Debit or Credit Card", then "Continue".',
      'Instead of scanning or tapping the card, choose "Enter Card Details Manually".',
      'Type your name and the card number, expiry date and security code exactly as shown in this app.',
      'Accept the issuer terms and, if asked, confirm the verification code sent to you.',
      'When Wallet says the card is ready, hold your iPhone near a contactless terminal to pay.',
    ],
    note:
        'If Wallet says the card cannot be added, its issuer has not enabled Apple Pay for it yet.',
  ),
  google(
    rowTitle: 'Add to Google Wallet',
    rowSubtitle: 'Enter the card in the Wallet app to pay with your phone',
    rowSubtitleShort: 'Pay with your phone',
    intro:
        'Google Wallet does not add this card automatically yet. Enter its details in the Wallet app once and it is ready for Google Pay.',
    steps: [
      'Open the Google Wallet app on your phone and tap "Add to Wallet".',
      'Tap "Payment card", then "New credit or debit card".',
      'Instead of using the camera, tap "Enter details manually".',
      'Type the card number, expiry date, security code and your name exactly as shown in this app, then tap "Save and continue".',
      'Accept the issuer terms and, if asked, confirm the verification code sent to you.',
      'When Wallet says the card is ready, hold your phone near a contactless terminal to pay.',
    ],
    note:
        'If Wallet says the card cannot be added, its issuer has not enabled Google Pay for it yet.',
  );

  const MobileWallet({
    required this.rowTitle,
    required this.rowSubtitle,
    required this.rowSubtitleShort,
    required this.intro,
    required this.steps,
    required this.note,
  });

  /// Translation keys; every one reads in the customer's language.
  final String rowTitle;
  final String rowSubtitle;
  final String rowSubtitleShort;
  final String intro;
  final List<String> steps;
  final String note;
}

/// The wallet this device carries, or null where there is none to add to.
///
/// Native iOS and Android, plus the web build opened on a phone. Flutter
/// reports an iPad in Safari's desktop mode as macOS, so the user-agent
/// bridge in `web/index.html` is the second opinion. A laptop gets nothing:
/// the row would be a promise the device cannot keep.
MobileWallet? mobileWalletForDevice() {
  final web = kIsWeb ? WebInstallPrompt.platform() : 'other';
  if (defaultTargetPlatform == TargetPlatform.iOS || web == 'ios') {
    return MobileWallet.apple;
  }
  if (defaultTargetPlatform == TargetPlatform.android || web == 'android') {
    return MobileWallet.google;
  }
  return null;
}

/// Walks the customer through adding [card] to [wallet] by hand.
///
/// [onShowCardDetails], when given, becomes the sheet's primary action: it
/// closes the sheet and reveals the number, expiry and CVV the wallet app
/// asks for, so the customer never has to hunt for them mid-flow. Pass null
/// when the details are already on screen.
Future<void> showAddToWalletSheet(
  BuildContext context, {
  required MobileWallet wallet,
  required PaymentCard card,
  VoidCallback? onShowCardDetails,
}) {
  final isExample = context.isExampleTheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isExample ? ExampleSurface.of(context, 1) : null,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: AddToWalletSteps(
        wallet: wallet,
        card: card,
        onShowCardDetails: onShowCardDetails == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onShowCardDetails();
              },
      ),
    ),
  );
}

class AddToWalletSteps extends StatelessWidget {
  const AddToWalletSteps({
    required this.wallet,
    required this.card,
    this.onShowCardDetails,
    super.key,
  });

  final MobileWallet wallet;
  final PaymentCard card;
  final VoidCallback? onShowCardDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    final primary =
        isExample ? ExampleInk.primary(context) : theme.colorScheme.onSurface;
    final secondary = isExample
        ? ExampleInk.secondary(context)
        : theme.colorScheme.onSurfaceVariant;
    final accent =
        isExample ? ExamplePalette.of(context).accent : theme.colorScheme.primary;
    final steps = wallet.steps;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(wallet.rowTitle),
            style: TextStyle(
              color: primary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(wallet.intro),
            style: TextStyle(fontSize: 12.5, height: 1.45, color: secondary),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StepNumber(number: i + 1, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        context.tr(steps[i]),
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text(
            context.tr(wallet.note),
            style: TextStyle(fontSize: 12, height: 1.4, color: secondary),
          ),
          const WalletBalanceNote(),
          const SizedBox(height: 18),
          if (onShowCardDetails != null)
            if (isExample)
              ExampleGlassButton(
                label: context.tr('Show card details'),
                icon: Icons.visibility_outlined,
                onPressed: onShowCardDetails,
              )
            else
              FilledButton.icon(
                onPressed: onShowCardDetails,
                icon: const Icon(Icons.visibility_outlined),
                label: Text(context.tr('Show card details')),
              ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(context.tr('Close')),
          ),
        ],
      ),
    );
  }
}

/// The wallets refuse a card with nothing on it, so say so wherever the
/// customer is about to try.
class WalletBalanceNote extends StatelessWidget {
  const WalletBalanceNote({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.isExampleTheme
        ? ExampleInk.secondary(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              context.tr(
                  'To add this card to Apple Pay or Google Wallet, its balance must be greater than 0.'),
              style: TextStyle(fontSize: 12, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// A numbered disc: the step's ordinal in the accent, on a tint of itself.
class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.number, required this.color});

  final int number;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Text(
          '$number',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      );
}
