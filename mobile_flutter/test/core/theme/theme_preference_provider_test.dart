import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/theme/theme_preference_provider.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a new customer starts with the dark app default', () async {
    final overrides = await bootThemeModeOverrides();
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    expect(overrides, isEmpty);
    expect(await container.read(themePreferenceProvider.future), isNull);
    expect(AppBranding.fromEnvironment().materialThemeMode, ThemeMode.dark);
  });

  test('saved light remains available before and after preference hydration',
      () async {
    SharedPreferences.setMockInitialValues({'app.themeMode.v1': 'light'});
    final container =
        ProviderContainer(overrides: await bootThemeModeOverrides());
    addTearDown(container.dispose);

    expect(container.read(bootThemeModeProvider), ThemeMode.light);
    expect(
        await container.read(themePreferenceProvider.future), ThemeMode.light);
  });

  test('saved system preference remains an explicit choice', () async {
    SharedPreferences.setMockInitialValues({'app.themeMode.v1': 'system'});
    final container =
        ProviderContainer(overrides: await bootThemeModeOverrides());
    addTearDown(container.dispose);

    expect(container.read(bootThemeModeProvider), ThemeMode.system);
    expect(
        await container.read(themePreferenceProvider.future), ThemeMode.system);
  });

  test('clearing an explicit light choice restores the dark default', () async {
    SharedPreferences.setMockInitialValues({'app.themeMode.v1': 'light'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(themePreferenceProvider.future);

    await container.read(themePreferenceProvider.notifier).setMode(null);

    expect(container.read(themePreferenceProvider).valueOrNull, isNull);
    expect(
        (await SharedPreferences.getInstance()).getString('app.themeMode.v1'),
        isNull);
    expect(AppBranding.fromEnvironment().materialThemeMode, ThemeMode.dark);
  });
}
