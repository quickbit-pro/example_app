import 'signup_destination.dart';

class SignupRouteRequest {
  const SignupRouteRequest({
    this.invitationToken,
    this.referralCode,
    this.referralSource = 'MANUAL_CODE',
    this.next,
  });

  factory SignupRouteRequest.fromUri(Uri uri) {
    final invitationToken = _nonEmpty(uri.queryParameters['invitationToken']);
    final referralCode = _nonEmpty(uri.queryParameters['referralCode']) ??
        _nonEmpty(uri.queryParameters['ref']);
    return SignupRouteRequest(
      invitationToken: invitationToken,
      referralCode: referralCode,
      referralSource: invitationToken != null
          ? 'EMAIL_INVITATION'
          : referralCode == null
              ? 'MANUAL_CODE'
              : 'LINK',
      next: signupDestination(uri.queryParameters['next']),
    );
  }

  final String? invitationToken;
  final String? referralCode;
  final String referralSource;

  /// Where a campaign link asked the friend to land after sign-up
  /// (`?next=`), already reduced to the allowlist; null for the default.
  final String? next;
}

String? _nonEmpty(String? value) {
  if (value == null || value.isEmpty) return null;
  return value;
}
