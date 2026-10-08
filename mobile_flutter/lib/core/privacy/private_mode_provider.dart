import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/banking_models.dart';

/// Private Mode masks every amount in the app. The preference persists across
/// launches and is applied through [Money.maskAmounts] so all formatting paths
/// respect it.
class PrivateModeController extends AsyncNotifier<bool> {
  static const _key = 'app.privateMode.v1';

  @override
  Future<bool> build() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getBool(_key) ?? false;
    Money.maskAmounts = value;
    return value;
  }

  Future<void> set(bool enabled) async {
    Money.maskAmounts = enabled;
    state = AsyncData(enabled);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, enabled);
  }

  Future<void> toggle() => set(!(state.valueOrNull ?? false));
}

final privateModeProvider = AsyncNotifierProvider<PrivateModeController, bool>(
  PrivateModeController.new,
);
