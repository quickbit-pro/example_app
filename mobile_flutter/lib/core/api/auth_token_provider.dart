import 'package:flutter_riverpod/flutter_riverpod.dart';

final authTokenProvider = StateProvider<String?>((ref) => null);

final refreshTokenProvider = StateProvider<String?>((ref) => null);

/// Changes whenever a user session starts or ends. Session-bound API clients
/// watch this value so data cached by the previous session is discarded.
final authSessionGenerationProvider = StateProvider<int>((ref) => 0);
