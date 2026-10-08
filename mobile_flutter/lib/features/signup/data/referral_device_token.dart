import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'visitor_id_store.dart';

/// A resettable installation signal for disclosed referral-abuse review.
/// Kept separate from click analytics; it is never a verified device identity.
class ReferralDeviceTokenStore {
  const ReferralDeviceTokenStore();
  static const key = 'referral.review.installation.v1';
  Future<String?> getOrCreate() async {
    try {
      return await _read().timeout(const Duration(milliseconds: 500));
    } catch (_) {
      return null;
    }
  }

  Future<String?> _read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(key);
      if (stored != null && VisitorIdStore.isVisitorId(stored)) return stored;
      final token = VisitorIdStore.newVisitorId(Random.secure());
      final saved = await preferences.setString(key, token);
      return saved ? token : null;
    } catch (_) {
      // A blocked local store means unavailable signal, not failed signup.
      return null;
    }
  }
}

final referralDeviceTokenStoreProvider = Provider<ReferralDeviceTokenStore>(
    (ref) => const ReferralDeviceTokenStore());
