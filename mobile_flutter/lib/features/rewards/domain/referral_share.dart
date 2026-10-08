import 'dart:ui' show Locale;

import '../../../app/routes.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import 'rewards_models.dart';

/// Looks up app copy for the invitation; `AppLocalizations.translate` in the
/// app, English when nothing is supplied.
typedef ReferralShareTranslator = String Function(
  String key, [
  Map<String, Object?> values,
]);

String _english(String key, [Map<String, Object?> values = const {}]) =>
    const AppLocalizations(Locale('en'), {}).translate(key, values);

// Uri.tryParse accepts two concatenated origins as a different host. Reject
// that legacy link shape before falling back to the app's signup address.
final _concatenatedWebOrigins = RegExp(
  r'^https?://[^/?#]+https?://',
  caseSensitive: false,
);

/// The link a friend opens to sign up with [referralCode], or null when no
/// usable address exists and the invitation has to carry the code alone.
///
/// The platform returns `referralPath` as an absolute link once a tenant has
/// a sign-up URL configured; that is used verbatim. Older platforms and
/// tenants without the setting still return the dashboard's relative route
/// (`/registration?referralCode=CODE`), which means nothing to a friend, so
/// the app then points at its own sign-up screen instead: on web under the
/// address it is served from ([currentWebUri], i.e. `Uri.base`) and on native
/// builds under the configured public web app address ([webAppUrl]). Both are
/// hash routes because the web build uses the default hash URL strategy.
String? resolveReferralShareLink({
  required String referralCode,
  String? referralPath,
  Uri? currentWebUri,
  String? webAppUrl,
}) {
  final path = referralPath?.trim() ?? '';
  if (!_concatenatedWebOrigins.hasMatch(path) &&
      _isAbsoluteWebUri(Uri.tryParse(path))) {
    return path;
  }
  final code = referralCode.trim();
  if (code.isEmpty) return null;
  final base = _appBase(currentWebUri) ??
      _appBase(Uri.tryParse(webAppUrl?.trim() ?? ''));
  if (base == null) return null;
  return '$base#${AppRoutes.signup}?ref=${Uri.encodeQueryComponent(code)}';
}

bool _isAbsoluteWebUri(Uri? uri) =>
    uri != null &&
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.host.isNotEmpty;

/// `https://host/base/` for the app served at [uri]: origin plus the directory
/// part of the path, without the current query or hash route.
String? _appBase(Uri? uri) {
  if (uri == null || !_isAbsoluteWebUri(uri)) return null;
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: true);
  // `index.html` or similar is a file, not a directory the app lives under.
  if (segments.isNotEmpty && segments.last.contains('.')) {
    segments.removeLast();
  }
  final directory = segments.isEmpty ? '' : '${segments.join('/')}/';
  return '${uri.origin}/$directory';
}

/// The message a member sends when inviting a friend: who is inviting, what
/// the friend gets under the current offer, and the link plus the code so the
/// invitation still works when the link is not tappable.
String buildReferralShareText({
  required String appName,
  required String referralCode,
  String? link,
  ReferralOffer? offer,
  ReferralShareTranslator translate = _english,
}) {
  final code = referralCode.trim();
  final name = appName.trim();
  final String opener;
  if (offer != null && offer.hasWelcome) {
    final currency = offer.welcomeCurrency.trim().toUpperCase();
    final values = <String, Object?>{
      'p0': name,
      'p1': _plainAmount(currency, offer.welcomeAmount),
      'p2': currency,
    };
    final minimum = offer.minimumTopup ?? 0;
    if (offer.requiresTopup && minimum > 0) {
      opener = translate(
        'Join me on {p0} and get {p1} on your {p2} balance after your first top-up of {p3} or more.',
        {...values, 'p3': _plainAmount(currency, minimum)},
      );
    } else if (offer.requiresTopup) {
      opener = translate(
        'Join me on {p0} and get {p1} on your {p2} balance after your first top-up.',
        values,
      );
    } else {
      opener = translate(
        'Join me on {p0} and get {p1} on your {p2} balance when you sign up.',
        values,
      );
    }
  } else {
    opener = translate('Join me on {p0}.', {'p0': name});
  }
  final resolvedLink = link?.trim() ?? '';
  final action = resolvedLink.isEmpty
      ? translate('Enter code {p0} when you register.', {'p0': code})
      : translate(
          'Sign up with my link: {p0} — or enter code {p1} when you register.',
          {'p0': resolvedLink, 'p1': code},
        );
  return '$opener $action';
}

/// Money for a message that leaves the device: never masked by Private Mode,
/// and without the ".00" that "$3" does not want.
String _plainAmount(String currency, double amount) =>
    Money.formatPlainAmount(currency, amount)
        .replaceFirst(RegExp(r'\.00(?=\D|$)'), '');
