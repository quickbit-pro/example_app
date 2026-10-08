import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/peer/application/peer_providers.dart';
import 'package:mobile_flutter/features/peer/data/peer_transfers_api.dart';
import 'package:mobile_flutter/features/peer/presentation/peer_composer.dart';
import 'package:mobile_flutter/features/peer/presentation/peer_widgets.dart';

class _Api extends PeerTransfersApi {
  _Api() : super(Dio());
  int lookups = 0;
  bool succeed = false;
  String? lastNickname;
  @override
  Future<PeerFeeInfo> feeInfo({double? amount, String? currency}) async =>
      PeerFeeInfo.fromJson({});
  @override
  Future<PeerUser> lookup(
      {String? email, String? phoneNumber, String? nickname}) async {
    lookups++;
    lastNickname = nickname;
    if (succeed) {
      return PeerUser.fromJson(
          {'userId': 'ana', 'firstName': 'Ana', 'nickname': nickname});
    }
    throw StateError('Unexpected lookup');
  }
}

void main() {
  for (final mode in PeerComposerMode.values) {
    testWidgets('nickname selects recipient for $mode', (tester) async {
      final api = _Api()..succeed = true;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            peerTransfersApiProvider.overrideWithValue(api),
            peerContactsProvider.overrideWith((ref) async => []),
            peerAvailableBalancesProvider
                .overrideWith((ref) async => {'USD': 100.0}),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: PeerComposer(mode: mode))))));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Nickname, email or phone number'),
          '@AnA_123');
      await tester.pump();
      await tester.tap(find.byTooltip('Find member'));
      await tester.pumpAndSettle();
      expect(api.lastNickname, 'ana_123');
      expect(
          find.text(
              mode == PeerComposerMode.send ? 'Sending to' : 'Requesting from'),
          findsOneWidget);
      expect(find.text('@ana_123'), findsOneWidget);
    });
  }

  test('validation errors never expose the exception class', () {
    expect(
        peerErrorText(const FormatException(
            'Enter a title, total and at least one other person.')),
        'Enter a title, total and at least one other person.');
  });

  testWidgets('empty and malformed recipients never reach lookup',
      (tester) async {
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          peerTransfersApiProvider.overrideWithValue(api),
          peerContactsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: PeerComposer(mode: PeerComposerMode.request))))));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'People you request money from can be saved as contacts for next time.'),
        findsOneWidget);
    final button = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Find member');
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    final field =
        find.widgetWithText(TextField, 'Nickname, email or phone number');
    for (final entry in {
      'ab': 'Use 3–30 letters, numbers or underscores, starting with a letter.',
      'invalid@': 'Enter a valid email address.',
      '12345':
          'Enter the full phone number including the country code, for example +44.',
    }.entries) {
      await tester.enterText(field, entry.key);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    }
    expect(api.lookups, 0);
    // The API accepts 00-prefixed international and local phone numbers too.
    for (final phone in [
      '0038640123456',
      '+38640123456',
      '040123456',
      'ana_123',
      '@Ana_123'
    ]) {
      await tester.enterText(field, phone);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(api.lookups, 5);
  });
}
