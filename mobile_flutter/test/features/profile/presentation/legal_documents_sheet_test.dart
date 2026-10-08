import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/profile/presentation/legal_documents_sheet.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  testWidgets(
      'library updates after config loads, retains documents after opening and handles errors',
      (tester) async {
    final config = Completer<MobileTenantConfig>();
    String? opened;
    var succeeds = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      opened = (call.arguments as Map)['url'] as String?;
      if (!succeeds) throw PlatformException(code: 'unavailable');
      return true;
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          mobileTenantConfigProvider.overrideWith((ref) => config.future),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showLegalDocumentsSheet(context),
                        child: const Text('Open documents')))))));
    await tester.tap(find.text('Open documents'));
    await tester.pumpAndSettle();
    expect(find.text('Loading additional company documents…'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    config.complete(MobileTenantConfig.fromJson({
      'company': {
        'eCommunicationNoticeUrl': 'https://example.test/glba.pdf',
      }
    }));
    await tester.pumpAndSettle();
    expect(find.text('GLBA Disclosure'), findsOneWidget);
    await tester.ensureVisible(find.text('E-Sign Agreement'));
    await tester.tap(find.text('E-Sign Agreement'));
    await tester.pumpAndSettle();
    expect(opened, 'https://docs.hoppa.global/01%20E-sign%20Consent.pdf');
    expect(find.text('Legal documents'), findsOneWidget);
    succeeds = false;
    await tester.tap(find.text('E-Sign Agreement'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open E-Sign Agreement.'),
        findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });
}
