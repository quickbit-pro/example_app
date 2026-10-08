import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import '../data/referral_invitation_repository.dart';
import '../domain/referral_invitation.dart';

final referralInvitationRepositoryProvider =
    Provider<ReferralInvitationRepository>((ref) {
  return DioReferralInvitationRepository(ref.watch(dioProvider));
});

final referralInvitationPreviewProvider = FutureProvider.autoDispose
    .family<ReferralInvitationPreview, String>((ref, token) {
  return ref.watch(referralInvitationRepositoryProvider).preview(token);
});
