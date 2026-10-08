import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/features/transactions/data/monthly_statements_api.dart';
import 'package:mobile_flutter/features/transactions/presentation/monthly_statements.dart';

class FakeApi extends MonthlyStatementsApi {
  FakeApi() : super(Dio());
  List<MonthlyStatement> jobs = [];
  final ids = <String>[];
  bool fail = false;
  Completer<MonthlyStatement>? held;
  MonthlyStatement job(String id, {String status = 'queued'}) =>
      MonthlyStatement.fromJson({
        'id': id,
        'year': 2026,
        'month': 8,
        'status': status,
        'transactionCount': 12,
        'attachmentCount': 3,
        'error': '',
        'downloadPath':
            status == 'ready' ? '/api/v1/statement-download?token=test' : null
      });
  @override
  Future<List<MonthlyStatement>> list() async => jobs;
  @override
  Future<MonthlyStatement> create(String id, int year, int month) async {
    ids.add(id);
    if (held != null) return held!.future;
    if (fail) {
      fail = false;
      throw Exception('timeout');
    }
    final value = job(id);
    jobs = [value];
    return value;
  }
}

Future<ProviderContainer> mount(WidgetTester tester, FakeApi api) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
      overrides: [monthlyStatementsApiProvider.overrideWithValue(api)]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child:
          const MaterialApp(home: Scaffold(body: MonthlyStatementButton()))));
  await tester.tap(find.byType(MonthlyStatementButton));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
      'monthly export persists after closing and exposes ready download',
      (tester) async {
    final api = FakeApi();
    await mount(tester, api);
    await tester.ensureVisible(find.text('Create monthly ZIP'));
    await tester.tap(find.text('Create monthly ZIP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Queued for preparation'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    api.jobs = [api.job(api.ids.single, status: 'ready')];
    await tester.tap(find.byType(MonthlyStatementButton));
    await tester.pumpAndSettle();
    expect(find.text('Download ZIP'), findsOneWidget);
    expect(find.text('12 transactions · 3 invoices'), findsOneWidget);
    expect(api.ids, hasLength(1));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
  testWidgets(
      'ambiguous create retries same id and account switch hides late result',
      (tester) async {
    final api = FakeApi()..fail = true;
    final container = await mount(tester, api);
    await tester.ensureVisible(find.text('Create monthly ZIP'));
    await tester.tap(find.text('Create monthly ZIP'));
    await tester.pumpAndSettle();
    expect(find.text('Retry export request'), findsOneWidget);
    api.held = Completer();
    await tester.tap(find.text('Retry export request'));
    await tester.pump();
    expect(api.ids[0], api.ids[1]);
    container.read(authSessionGenerationProvider.notifier).state++;
    await tester.pump();
    api.held!.complete(api.job(api.ids[1], status: 'ready'));
    await tester.pumpAndSettle();
    expect(find.text('Download ZIP'), findsNothing);
    expect(find.byType(MonthlyStatementsDialog), findsNothing);
  });
}
