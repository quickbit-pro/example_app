import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:mobile_flutter/brands/example/example_states.dart';
import 'package:mobile_flutter/features/profile/presentation/security_sheets.dart';
import 'package:mobile_flutter/core/l10n/language_picker.dart';
import 'package:mobile_flutter/core/l10n/locale_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final english = jsonDecode(File('assets/l10n/en.json').readAsStringSync())
      as Map<String, dynamic>;
  List<String> placeholders(String s) =>
      RegExp(r'\{p\d+\}').allMatches(s).map((m) => m[0]!).toList()..sort();

  for (final language in appLanguages) {
    test('${language.code} has complete copy and preserves substitutions', () {
      final messages = jsonDecode(
              File('assets/l10n/${language.code}.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(messages.keys.toSet(), english.keys.toSet());
      for (final entry in messages.entries) {
        expect(entry.value, isA<String>(), reason: entry.key);
        expect((entry.value as String).trim(), isNotEmpty, reason: entry.key);
        expect(placeholders(entry.value), placeholders(entry.key),
            reason: '${language.code}: ${entry.key}');
        expect(entry.value, isNot(contains('9876543')), reason: entry.key);
        expect(entry.value, isNot(contains('__LINEBREAK__')),
            reason: entry.key);
      }
    });
  }

  test('fallback and substitution preserve customer data verbatim', () {
    const l10n = AppLocalizations(Locale('de'), {
      'Welcome {p0}': 'Willkommen {p0}',
    });
    expect(l10n.translate('Welcome {p0}', {'p0': 'Send {p1}'}),
        'Willkommen Send {p1}');
    expect(
        l10n.translate('IBAN {p0}', {'p0': 'BE123456789'}), 'IBAN BE123456789');
    expect(l10n.translate('New message'), 'New message');
  });

  test('language survives restart and device default can be restored',
      () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    await first
        .read(localePreferenceProvider.notifier)
        .setLocale(const Locale('ar'));
    first.dispose();
    final restored = ProviderContainer(overrides: await bootLocaleOverrides());
    expect(restored.read(localePreferenceProvider), const Locale('ar'));
    await restored.read(localePreferenceProvider.notifier).setLocale(null);
    restored.dispose();
    final deviceDefault =
        ProviderContainer(overrides: await bootLocaleOverrides());
    expect(deviceDefault.read(localePreferenceProvider), isNull);
    deviceDefault.dispose();
  });

  test('obsolete preferences safely resolve to device language', () async {
    SharedPreferences.setMockInitialValues({'app.language.v1': 'ru'});
    final container = ProviderContainer(overrides: await bootLocaleOverrides());
    expect(container.read(localePreferenceProvider), isNull);
    container.dispose();
  });

  testWidgets(
      'Arabic switches layout direction and exposes all language choices',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester
        .runAsync(() => AppLocalizations.delegate.load(const Locale('ar')));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: appLanguages.map((l) => l.locale),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: LanguagePicker()),
    )));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.byType(LanguagePicker))),
        TextDirection.rtl);
    expect(find.text('اللغة'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.text('Deutsch'), findsOneWidget);
    expect(find.text('Español'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shared error and security notes use the chosen language',
      (tester) async {
    await tester
        .runAsync(() => AppLocalizations.delegate.load(const Locale('de')));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: appLanguages.map((l) => l.locale),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: Scaffold(
          body: Column(children: [
        Expanded(
            child: ExampleErrorState(
                body:
                    'The service is temporarily unavailable. Try again shortly.',
                onRetry: () {})),
        const ExampleSheetNote(
            'Enter your email and we will send you a one-time code to choose a new password.'),
      ])),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    final catalog = jsonDecode(File('assets/l10n/de.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(
        find.text(catalog['Something went wrong'] as String), findsOneWidget);
    expect(find.text(catalog['Try again'] as String), findsOneWidget);
    expect(
        find.text(catalog[
                'Enter your email and we will send you a one-time code to choose a new password.']
            as String),
        findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
