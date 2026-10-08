import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set once the customer chose "later" on the account setup screen so Home
/// stops redirecting for the rest of the session (the banner stays).
final accountSetupDismissedProvider = StateProvider<bool>((ref) => false);

/// Set after Home has auto-opened the setup screen once this session.
final accountSetupPromptedProvider = StateProvider<bool>((ref) => false);

enum IdentityStage { verified, inReview, required }

/// Maps the profile's KYC status string onto the three states the setup
/// checklist cares about.
IdentityStage identityStageFor(String kycStatus) {
  final normalized =
      kycStatus.toLowerCase().replaceAll('_', '-').replaceAll(' ', '-').trim();
  const ready = {
    'approved',
    'verified',
    'complete',
    'completed',
    'active',
    'ready'
  };
  const review = {
    'submitted',
    'review',
    'in-review',
    'manual-review',
    'reviewing',
    'waiting',
    'wait-for-review',
    'processing',
  };
  if (ready.contains(normalized)) return IdentityStage.verified;
  if (review.contains(normalized)) return IdentityStage.inReview;
  return IdentityStage.required;
}
