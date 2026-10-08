import 'package:dio/dio.dart';

import '../domain/referral_invitation.dart';

abstract interface class ReferralInvitationRepository {
  Future<ReferralInvitationPreview> preview(String token);
}

class DioReferralInvitationRepository implements ReferralInvitationRepository {
  const DioReferralInvitationRepository(this._dio);

  final Dio _dio;

  @override
  Future<ReferralInvitationPreview> preview(String token) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v2/referral-invitations/preview',
        queryParameters: {'token': token},
        options: Options(
          extra: const {
            'skipAuthRefresh': true,
            'sensitiveRequest': true,
          },
        ),
      );
      return ReferralInvitationPreview.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw ReferralInvitationFailure(_failureType(error));
    } on FormatException {
      throw const ReferralInvitationFailure(
        ReferralInvitationFailureType.invalid,
      );
    }
  }
}

ReferralInvitationFailureType _failureType(DioException error) {
  final status = error.response?.statusCode;
  final marker = _responseMarker(error.response?.data);
  if (status == 409 ||
      status == 410 ||
      marker.contains('expired') ||
      marker.contains('consumed') ||
      marker.contains('already_used') ||
      marker.contains('already used')) {
    return ReferralInvitationFailureType.expired;
  }
  if (status == 400 || status == 404 || status == 422) {
    return ReferralInvitationFailureType.invalid;
  }
  return ReferralInvitationFailureType.network;
}

String _responseMarker(Object? data) {
  if (data is! Map) return '';
  return [
    data['code'],
    data['Code'],
    data['message'],
    data['Message'],
  ].whereType<Object>().join(' ').toLowerCase();
}
