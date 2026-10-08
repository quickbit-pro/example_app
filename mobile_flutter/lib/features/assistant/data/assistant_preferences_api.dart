import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import '../domain/assistant_preferences.dart';

final assistantPreferencesApiProvider = Provider<AssistantPreferencesApi>(
  (ref) => AssistantPreferencesApi(ref.watch(dioProvider)),
);

class AssistantPreferencesApi {
  const AssistantPreferencesApi(this._dio);
  final Dio _dio;

  Future<AssistantPreferences> load({CancelToken? cancelToken}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/assistant/preferences',
      cancelToken: cancelToken,
      options: Options(extra: {
        'sensitiveRequest': true,
        'transientReadRetried': true,
      }),
    );
    return AssistantPreferences.fromJson(response.data ?? const {});
  }
}
