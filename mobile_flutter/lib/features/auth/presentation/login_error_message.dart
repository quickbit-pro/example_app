import 'package:dio/dio.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/widgets/app_states.dart';

String loginErrorMessage(Object error, AppLocalizations translations) {
  if (error is DioException) {
    final path = Uri.parse(error.requestOptions.path).path;
    if (error.response?.statusCode == 401 &&
        path == '/api/v1/mobile/auth/login') {
      return translations.translate('Email or password is incorrect.');
    }
    final data = error.response?.data;
    if (error.response?.statusCode == 429 &&
        data is Map &&
        data['code'] == 'auth.locked_out') {
      // Older API responses carry the remaining minutes in their title.
      // Prefer the standard header when it is available.
      final retryAfter =
          int.tryParse(error.response?.headers.value('retry-after') ?? '');
      final titleMinutes = RegExp(r'Try again in (\d+) minutes\.')
          .firstMatch(data['title']?.toString() ?? '')
          ?.group(1);
      final minutes = retryAfter != null && retryAfter > 0
          ? (retryAfter / 60).ceil()
          : int.tryParse(titleMinutes ?? '');
      if (minutes != null && minutes > 0) {
        return translations.translate(
            'Too many failed sign-in attempts. Try again in {p0} min.',
            {'p0': minutes});
      }
      return translations.translate(
          'Too many failed sign-in attempts. Please wait before trying again.');
    }
  }
  return translations.translate(friendlyErrorMessage(error));
}
