import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/signup/domain/signup_route_request.dart';

void main() {
  test('auth registration deep link extracts and preserves opaque token', () {
    const token = 'opaque.+/_-token==';
    final uri = Uri(
      path: '/auth/register',
      queryParameters: {'invitationToken': token},
    );

    final request = SignupRouteRequest.fromUri(uri);

    expect(request.invitationToken, token);
    expect(request.referralSource, 'EMAIL_INVITATION');
  });

  test('normal registration has no invitation token', () {
    final request = SignupRouteRequest.fromUri(Uri.parse('/signup'));

    expect(request.invitationToken, isNull);
    expect(request.referralCode, isNull);
    expect(request.referralSource, 'MANUAL_CODE');
  });

  test('a campaign link destination rides along when allowlisted', () {
    expect(
      SignupRouteRequest.fromUri(Uri.parse('/signup?ref=AUTUMN26&next=cards'))
          .next,
      'cards',
    );
    expect(
      SignupRouteRequest.fromUri(Uri.parse('/signup?ref=AUTUMN26&next=TopUp'))
          .next,
      'topup',
    );
    // Not on the allowlist: the default, never a crafted route.
    expect(
      SignupRouteRequest.fromUri(
              Uri.parse('/signup?ref=AUTUMN26&next=%2Fprofile%3Fx%3D1'))
          .next,
      isNull,
    );
    expect(SignupRouteRequest.fromUri(Uri.parse('/signup?next=signup')).next,
        isNull);
    expect(SignupRouteRequest.fromUri(Uri.parse('/signup')).next, isNull);
  });
}
