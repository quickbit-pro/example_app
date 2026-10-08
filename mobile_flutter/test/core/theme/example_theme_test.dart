import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_colors.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';

void main() {
  test('EXAMPLE profile uses Twilight tokens without changing generic builds',
      () {
    const common = (
      primarySeedHex: '112233',
      accentSeedHex: '445566',
      loginBackgroundHex: '',
      themeMode: 'dark',
      fontFamily: '',
      logoAsset: '',
      radiusScale: '1',
      supportEmail: 'support@example.com',
      supportPhone: '',
      legalEntity: '',
    );
    final generic = buildAppThemes(AppBranding(
      appName: 'Generic',
      primarySeedHex: common.primarySeedHex,
      accentSeedHex: common.accentSeedHex,
      loginBackgroundHex: common.loginBackgroundHex,
      themeMode: common.themeMode,
      fontFamily: common.fontFamily,
      logoAsset: common.logoAsset,
      radiusScale: common.radiusScale,
      supportEmail: common.supportEmail,
      supportPhone: common.supportPhone,
      legalEntity: common.legalEntity,
    ));
    final example = buildAppThemes(AppBranding(
      appName: 'EXAMPLE',
      brandId: 'example',
      primarySeedHex: common.primarySeedHex,
      accentSeedHex: common.accentSeedHex,
      loginBackgroundHex: common.loginBackgroundHex,
      themeMode: common.themeMode,
      fontFamily: common.fontFamily,
      logoAsset: common.logoAsset,
      radiusScale: common.radiusScale,
      supportEmail: common.supportEmail,
      supportPhone: common.supportPhone,
      legalEntity: common.legalEntity,
    ));

    expect(example.dark.scaffoldBackgroundColor, ExampleColors.appBackground);
    expect(example.dark.colorScheme.primary, ExampleColors.violet);
    expect(generic.dark.colorScheme.primary, isNot(ExampleColors.violet));
  });
}
