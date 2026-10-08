import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_provider.dart';
import 'app_theme.dart';

/// Retain both palettes across theme preference, privacy and session updates.
/// A change to the tenant branding is the only reason to rebuild them.
final appThemesProvider = Provider<AppThemes>((ref) {
  final branding =
      ref.watch(appConfigProvider.select((config) => config.branding));
  return buildAppThemes(branding);
});
