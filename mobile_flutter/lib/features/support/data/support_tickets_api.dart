import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';

final supportTicketsApiProvider = Provider<SupportTicketsApi>(
  (ref) => SupportTicketsApi(ref.watch(dioProvider)),
);
final supportTicketListProvider =
    FutureProvider.autoDispose.family<SupportTicketPage, int>((ref, offset) {
  return ref.watch(supportTicketsApiProvider).list(offset);
});
final supportTicketProvider =
    FutureProvider.autoDispose.family<SupportTicketDetail, String>((ref, id) {
  return ref.watch(supportTicketsApiProvider).get(id);
});

class SupportTicket {
  SupportTicket.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        subject = json['subject'] as String,
        status = json['status'] as String,
        revision = json['revision'] as String,
        updatedAt = DateTime.parse(json['updatedAt'] as String);
  final String id;
  final String subject;
  final String status;
  final String revision;
  final DateTime updatedAt;
  String get reference => '#${id.substring(id.length - 8).toUpperCase()}';
  String get statusLabel => switch (status) {
        'awaiting_support' => 'Awaiting support',
        'awaiting_user' => 'Awaiting your reply',
        'resolved' => 'Resolved',
        _ => 'Submitted',
      };
}

class SupportMessage {
  SupportMessage.fromJson(Map<String, dynamic> json)
      : isAdmin = json['isAdmin'] as bool,
        body = json['body'] as String,
        createdAt = DateTime.parse(json['createdAt'] as String);
  final bool isAdmin;
  final String body;
  final DateTime createdAt;
}

class SupportTicketDetail {
  SupportTicketDetail.fromJson(Map<String, dynamic> json)
      : ticket = SupportTicket.fromJson(json['ticket'] as Map<String, dynamic>),
        messages = (json['messages'] as List)
            .map(
                (item) => SupportMessage.fromJson(item as Map<String, dynamic>))
            .toList();
  final SupportTicket ticket;
  final List<SupportMessage> messages;
}

class SupportTicketPage {
  SupportTicketPage.fromJson(Map<String, dynamic> json)
      : items = (json['items'] as List)
            .map((item) => SupportTicket.fromJson(item as Map<String, dynamic>))
            .toList(),
        totalCount = json['totalCount'] as int;
  final List<SupportTicket> items;
  final int totalCount;
}

class SupportTicketsApi {
  const SupportTicketsApi(this._dio);
  final Dio _dio;
  static const _path = '/api/v1/mobile/support-tickets';
  Future<SupportTicketPage> list(int offset) async =>
      SupportTicketPage.fromJson((await _dio.get<Map<String, dynamic>>(
        _path,
        queryParameters: {'offset': offset, 'limit': 30},
      ))
          .data!);
  Future<SupportTicketDetail> get(String id) async =>
      SupportTicketDetail.fromJson((await _dio.get<Map<String, dynamic>>(
        '$_path/${Uri.encodeComponent(id)}',
      ))
          .data!);
  Future<SupportTicketDetail> create(String subject, String body) async =>
      SupportTicketDetail.fromJson((await _dio.post<Map<String, dynamic>>(
        _path,
        data: {'subject': subject, 'body': body},
        options: Options(extra: {'sensitiveRequest': true}),
      ))
          .data!);
  Future<void> reply(String id, String body, String revision) async {
    await _dio.post<void>(
      '$_path/${Uri.encodeComponent(id)}/replies',
      data: {'body': body, 'revision': revision},
      options: Options(extra: {'sensitiveRequest': true}),
    );
  }
}
