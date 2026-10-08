import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's per-install visitor id (addendum A of the campaign links
/// contract): a random UUID created once and kept in the app's preferences
/// — `SharedPreferences` on the phone, `localStorage` on the web — so the
/// platform can count a campaign link's unique visitors per day without
/// ever seeing an address. It identifies an installation, never a person:
/// it is sent only with campaign link clicks and is not tied to an account.
class VisitorIdStore {
  const VisitorIdStore({Random? random}) : _random = random;

  static const preferenceKey = 'app.visitorId.v1';

  final Random? _random;

  /// The stored id, or a new one stored for next time. A value that is not
  /// a UUID (a corrupted store, an older format) is replaced.
  Future<String> getOrCreate() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(preferenceKey);
    if (existing != null && isVisitorId(existing)) return existing;
    final created = newVisitorId(_random ?? Random.secure());
    await preferences.setString(preferenceKey, created);
    return created;
  }

  /// Whether [value] has the shape this store writes.
  static bool isVisitorId(String value) => _uuidPattern.hasMatch(value);

  /// A version-4 UUID from [random]: 36 characters, well inside the
  /// platform's 64-character limit.
  static String newVisitorId(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
}

final visitorIdStoreProvider =
    Provider<VisitorIdStore>((ref) => const VisitorIdStore());
