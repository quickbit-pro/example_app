import 'package:dio/dio.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_api.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_preferences_api.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_preferences.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_history_storage.dart';
import 'package:mobile_flutter/features/assistant/presentation/ask_ai_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/core/widgets/keyboard_focus_visibility.dart';
import 'package:mobile_flutter/features/cards/presentation/set_card_pin_sheet.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/presentation/payments_screen.dart';
import 'package:mobile_flutter/features/rewards/presentation/referral_actions.dart';
import 'package:mobile_flutter/features/support/presentation/support_tickets_screen.dart';
import 'package:mobile_flutter/flavors.dart';

const _branding = AppBranding(
  appName: 'EXAMPLE',
  brandId: 'example',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'EXAMPLE',
);

const _card = PaymentCard(
  id: 'card-1',
  label: 'EXAMPLE Card',
  last4: '4242',
  network: 'Mastercard',
  currency: 'USD',
  status: CardStatus.active,
  balance: Money(currency: 'USD', minorUnits: 10000),
  spendThisMonth: Money(currency: 'USD', minorUnits: 0),
  limit: Money(currency: 'USD', minorUnits: 0),
  virtual: true,
);

class _AssistantApi extends AssistantApi {
  _AssistantApi() : super(Dio());
  @override
  Future<AssistantUsage> usage({CancelToken? cancelToken}) async =>
      AssistantUsage(
        enabled: true,
        dailyLimit: 50,
        used: 0,
        remaining: 50,
        resetsAt: DateTime.utc(2030),
        maxMessageCharacters: 1500,
      );
}

class _PreferencesApi extends AssistantPreferencesApi {
  _PreferencesApi() : super(Dio());
  @override
  Future<AssistantPreferences> load({CancelToken? cancelToken}) async =>
      const AssistantPreferences();
}

Widget host(Widget home) => ProviderScope(
      overrides: [
        paymentsProvider.overrideWith((ref) async => const []),
        mandatesProvider.overrideWith((ref) async => const []),
        paymentRequestsProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        theme: buildAppThemes(_branding).dark,
        builder: (context, child) => KeyboardFocusVisibility(child: child!),
        home: home,
      ),
    );

Widget launcher(void Function(BuildContext) open) => Scaffold(
      body: Builder(
          builder: (context) => TextButton(
                onPressed: () => open(context),
                child: const Text('Open'),
              )),
    );

Future<void> setup(WidgetTester tester, Widget home,
    {bool settle = true}) async {
  tester.view.physicalSize = const Size(375, 667);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host(home));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> keyboard(WidgetTester tester, bool resize,
    {bool settle = true}) async {
  if (resize) {
    tester.view.physicalSize = const Size(375, 367);
  } else {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  }
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (settle) await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void visible(WidgetTester tester, Finder field) {
  final rect = tester.getRect(field);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(367));
  expect(field.hitTestable(), findsOneWidget);
}

void main() {
  for (final resize in [false, true]) {
    testWidgets('assistant composer stays visible resize=$resize',
        (tester) async {
      await setup(
          tester,
          ProviderScope(overrides: [
            assistantApiProvider.overrideWithValue(_AssistantApi()),
            assistantPreferencesApiProvider
                .overrideWithValue(_PreferencesApi()),
            assistantHistoryOwnerProvider.overrideWith((ref) => null),
            appConfigProvider.overrideWithValue(const AppConfig(
              flavor: AppFlavor.dev,
              apiBaseUrl: 'https://example.invalid',
              branding: _branding,
            )),
          ], child: const AskAiScreen()),
          settle: false);
      final input = find.byType(TextField);
      await tester.enterText(input, 'Help me plan my trip');
      await keyboard(tester, resize, settle: false);
      visible(tester, input);
      expect(find.text('Help me plan my trip'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('card PIN form scrolls above keyboard resize=$resize',
        (tester) async {
      await setup(
          tester, launcher((context) => showSetCardPinSheet(context, _card)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final pin = find.widgetWithText(TextField, 'New PIN');
      await tester.enterText(pin, '482915');
      await keyboard(tester, resize);
      visible(tester, pin);
      final confirm = find.widgetWithText(TextField, 'Confirm PIN');
      await tester.ensureVisible(confirm);
      await tester.enterText(confirm, '482915');
      await tester.pumpAndSettle();
      visible(tester, confirm);
      await tester.ensureVisible(find.text('Save PIN'));
      expect(find.text('Save PIN').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Set card PIN'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('referral invitation remains usable resize=$resize',
        (tester) async {
      await setup(tester, launcher(showReferralInvitationDialog));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final email = find.byKey(const Key('referral_invitation_email'));
      await tester.ensureVisible(email);
      await tester.enterText(email, 'friend@example.test');
      await keyboard(tester, resize);
      visible(tester, email);
      expect(find.text('Send invitation').hitTestable(), findsOneWidget);
      // Close without sending an invitation.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('payment entry sheet scrolls above keyboard resize=$resize',
        (tester) async {
      await setup(tester, const PaymentsScreen());
      await tester.tap(find.text('Create payment'));
      await tester.pumpAndSettle();
      final amount = find.widgetWithText(TextField, 'Amount');
      await tester.enterText(amount, '42.00');
      await keyboard(tester, resize);
      visible(tester, amount);
      final action = find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Create payment'));
      await tester.ensureVisible(action.last);
      expect(action.last.hitTestable(), findsOneWidget);
      expect(find.text('42.00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('support subject remains visible resize=$resize',
        (tester) async {
      await setup(tester, const NewSupportTicketScreen());
      final subject = find.widgetWithText(TextFormField, 'Subject');
      await tester.ensureVisible(subject);
      await tester.enterText(subject, 'Card delivery question');
      await keyboard(tester, resize);
      visible(tester, subject);
      expect(find.text('Card delivery question'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
