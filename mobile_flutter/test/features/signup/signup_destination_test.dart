// Where a campaign link sends the friend after sign-up (addendum A): only
// the platform's allowlist maps to a route, the sign-in hand-over carries
// it as `from`, and anything else falls back to Home.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/app/routes.dart';
import 'package:mobile_flutter/features/signup/domain/signup_destination.dart';

void main() {
  test('allowlisted words map to app routes, case and space tolerant', () {
    expect(signupDestinationRoute('home'), AppRoutes.home);
    expect(signupDestinationRoute(' Cards '), AppRoutes.cards);
    expect(signupDestinationRoute('topup'), AppRoutes.money);
    expect(signupDestinationRoute('REWARDS'), AppRoutes.rewards);
    expect(signupDestination('rewards'), 'rewards');
  });

  test('anything else is the default: sign-up, blanks, crafted paths', () {
    for (final next in [null, '', 'signup', '/profile', 'https://evil', 'login']) {
      expect(signupDestinationRoute(next), isNull, reason: '$next');
      expect(signupDestination(next), isNull, reason: '$next');
    }
  });

  test('the sign-in route carries the destination as from', () {
    expect(signInRouteAfterSignup('cards'), '/login?from=%2Fcards');
    expect(signInRouteAfterSignup('topup'), '/login?from=%2Fmoney');
    expect(signInRouteAfterSignup(null), AppRoutes.login);
    expect(signInRouteAfterSignup('signup'), AppRoutes.login);
    expect(signInRouteAfterSignup('/profile'), AppRoutes.login);
    // What the router reads back is the plain route.
    expect(
      Uri.parse(signInRouteAfterSignup('rewards')).queryParameters['from'],
      AppRoutes.rewards,
    );
  });
}
