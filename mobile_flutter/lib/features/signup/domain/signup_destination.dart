import '../../../app/routes.dart';

/// Where a campaign link sends the friend after sign-up (addendum A of the
/// campaign links contract). The `next` word comes from the share URL
/// (`?ref=CODE&next=cards`) or from the referral check; only the platform's
/// allowlist is honoured and everything else lands on Home, so a crafted
/// link can never route a new customer anywhere the app did not choose.
const signupDestinationRoutes = <String, String>{
  'home': AppRoutes.home,
  'cards': AppRoutes.cards,
  'topup': AppRoutes.money,
  'rewards': AppRoutes.rewards,
};

/// The normalised destination word, or null when [next] is blank or not on
/// the allowlist (`signup` is the plain sign-up page: nothing to honour).
String? signupDestination(String? next) {
  final word = next?.trim().toLowerCase() ?? '';
  return signupDestinationRoutes.containsKey(word) ? word : null;
}

/// The route to open once the new customer is signed in, or null for the
/// default (Home) when nothing allowlisted was asked for.
String? signupDestinationRoute(String? next) {
  final word = signupDestination(next);
  return word == null ? null : signupDestinationRoutes[word];
}

/// The sign-in route the completed sign-up hands over to. The router already
/// honours `from` once the customer is signed in, so an allowlisted
/// destination rides along there and a reload of the sign-in page keeps it.
String signInRouteAfterSignup(String? next) {
  final route = signupDestinationRoute(next);
  if (route == null) return AppRoutes.login;
  return Uri(
    path: AppRoutes.login,
    queryParameters: {'from': route},
  ).toString();
}
