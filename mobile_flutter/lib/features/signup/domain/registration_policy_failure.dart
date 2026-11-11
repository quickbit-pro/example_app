/// Only these server responses prove policy rejection before account creation.
/// A network failure or an unknown upstream outcome must keep its frozen draft.
bool canRestartRegistrationSignup(String? code, int? status) =>
    const {
          'auth.signup.registration_disabled': 403,
          'auth.signup.external_wallet_required': 400,
          'auth.signup.external_wallet_invalid': 400,
          'auth.referral.required': 400,
          'auth.signup.country_required': 400,
          'auth.signup.country_invalid': 400,
          'auth.signup.country_blocked': 403,
          'auth.signup.policy_unavailable': 503,
        }[code] ==
        status &&
    status != null;

bool shouldRefreshRegistrationPolicy(String? code, int? status) =>
    canRestartRegistrationSignup(code, status);
