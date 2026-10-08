import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_provider.dart';

final monthlyStatementsApiProvider =
    Provider((ref) => MonthlyStatementsApi(ref.watch(dioProvider)));

class MonthlyStatement {
  MonthlyStatement.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        year = json['year'] as int,
        month = json['month'] as int,
        status = json['status'] as String,
        transactionCount = json['transactionCount'] as int,
        attachmentCount = json['attachmentCount'] as int,
        error = json['error'] as String? ?? '',
        downloadPath = json['downloadPath'] as String?;
  final String id, status, error;
  final int year, month, transactionCount, attachmentCount;
  final String? downloadPath;
  bool get pending => status == 'queued' || status == 'processing';
  String get label => '$year-${month.toString().padLeft(2, '0')}';
}

class MonthlyStatementsApi {
  MonthlyStatementsApi(this.dio);
  final Dio dio;
  static const base = '/api/v1/mobile/monthly-statements';
  Options get options => Options(extra: {'sensitiveRequest': true});
  Future<List<MonthlyStatement>> list() async {
    final response = await dio.get<List<dynamic>>(base, options: options);
    return (response.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(MonthlyStatement.fromJson)
        .toList();
  }

  Future<MonthlyStatement> create(String id, int year, int month) async =>
      MonthlyStatement.fromJson((await dio.post<Map<String, dynamic>>(base,
              data: {'id': id, 'year': year, 'month': month}, options: options))
          .data!);
  static String requestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
