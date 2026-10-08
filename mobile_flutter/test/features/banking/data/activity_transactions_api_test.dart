import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';

Map<String, Object?> _transaction(String id, {bool crypto = false}) => {
      'id': id,
      'type': crypto ? 'crypto_withdrawal' : 'card_payment',
      'amount': crypto ? '0.000123' : '12.50',
      'currency': crypto ? 'USDC' : 'USD',
      'isPrimary': crypto,
      'transactionDate': '2026-09-06T08:00:00Z',
    };

Map<String, Object?> _page(int page, List<Map<String, Object?>> rows) => {
      'data': rows,
      'pagination': {
        'page': page,
        'pageSize': 100,
        'total': 101,
        'totalPages': 2,
        'hasNext': page < 2,
      },
    };

void main() {
  test('matches card fee ledger counterparts across history pages', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) {
        final page = options.queryParameters['page'] as int;
        return _page(page, [
          {
            'id': page == 1 ? 'database-fee' : 'card-fee',
            'type': page == 1 ? 'fees' : 'card_fee',
            'source': page == 1 ? 'database' : 'card_fee',
            'cardId': page == 1 ? null : 569,
            'amount': page == 1 ? -2 : 2,
            'currency': 'USD',
            'status': page == 1 ? 'completed' : 'success',
            'isPrimary': true,
            'externalTransactionId': 'same-charge',
          }
        ]);
      });
    final rows = await MobileBankingApi(dio).getActivityTransactions();
    expect(rows.map((row) => row.id), ['card-fee']);
    expect(rows.single.amount.decimalAmount, -2);
  });

  test('monthly Home history follows pages through the month boundary',
      () async {
    final requests = <int>[];
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      final page = options.queryParameters['page'] as int;
      requests.add(page);
      return {
        'data': [
          {
            ..._transaction('page-$page'),
            'transactionDate': page == 1
                ? '2026-09-06T08:00:00Z'
                : page == 2
                    ? '2026-08-15T08:00:00Z'
                    : '2026-08-01T08:00:00Z'
          },
        ],
        'pagination': {'page': page, 'hasNext': true},
      };
    });
    final transactions = await MobileBankingApi(dio)
        .getActivityTransactions(since: DateTime.utc(2026, 8, 8));
    expect(requests, [1, 2, 3]);
    // Keep the boundary page for the Recent list; the chart filters dates.
    expect(transactions.map((row) => row.id), ['page-1', 'page-2', 'page-3']);
  });

  test('monthly history does not treat an undated row as the month boundary',
      () async {
    var calls = 0;
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      calls++;
      return _page(calls, [
        {
          ..._transaction('row-$calls'),
          if (calls == 1) 'transactionDate': null
        },
      ]);
    });
    await MobileBankingApi(dio)
        .getActivityTransactions(since: DateTime.utc(2026, 8, 8));
    expect(calls, 2);
  });

  test('complete Activity follows server pages and includes older crypto',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      requests.add(options);
      final page = options.queryParameters['page'] as int;
      expect(options.queryParameters['pageSize'], 100);
      expect(options.queryParameters['sortBy'], 'date');
      expect(options.queryParameters['sortOrder'], 'desc');
      expect(options.queryParameters.containsKey('types'), isFalse);
      expect(options.queryParameters.containsKey('sources'), isFalse);
      return _page(
          page,
          page == 1
              ? [for (var i = 0; i < 100; i++) _transaction('card-$i')]
              : [
                  _transaction('card-99'),
                  _transaction('older-crypto', crypto: true)
                ]);
    });

    final transactions = await MobileBankingApi(dio).getActivityTransactions();

    expect(requests.length, 2);
    expect(transactions.length, 101);
    expect(transactions.last.id, 'older-crypto');
    expect(transactions.last.amount.currency, 'USDC');
    expect(transactions.last.amount.decimalAmount, -0.000123);
    expect(transactions.last.isPrimary, isTrue);
    expect(transactions.first.isPrimary, isFalse);
  });

  test('bounded Home transaction reads keep one request', () async {
    var calls = 0;
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      calls++;
      expect(options.queryParameters.containsKey('page'), isFalse);
      expect(options.queryParameters.containsKey('pageSize'), isFalse);
      return _page(1, [_transaction('recent')]);
    });

    final transactions = await MobileBankingApi(dio).getTransactions();

    expect(calls, 1);
    expect(transactions.single.id, 'recent');
  });

  test('account scope is retained on every Activity page', () async {
    final pages = <int>[];
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      expect(options.queryParameters['accountId'], 'account-17');
      final page = options.queryParameters['page'] as int;
      pages.add(page);
      return _page(page, [_transaction('scoped-$page')]);
    });

    await MobileBankingApi(dio)
        .getActivityTransactions(accountId: ' account-17 ');

    expect(pages, [1, 2]);
  });

  test('card scope uses the server cardIds filter on every Activity page',
      () async {
    final pages = <int>[];
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      expect(options.queryParameters['cardIds'], '17');
      expect(options.queryParameters.containsKey('cardId'), isFalse);
      expect(options.queryParameters.containsKey('sources'), isFalse);
      final page = options.queryParameters['page'] as int;
      pages.add(page);
      return _page(page, [
        {..._transaction('card-17-$page'), 'cardId': 17},
      ]);
    });

    final transactions =
        await MobileBankingApi(dio).getActivityTransactions(cardId: ' 17 ');

    expect(pages, [1, 2]);
    expect(transactions.map((item) => item.cardId), ['17', '17']);
  });

  test('blank card scope leaves the complete Activity request unfiltered',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      expect(options.queryParameters.containsKey('cardIds'), isFalse);
      return {
        'transactions': [_transaction('all-cards')]
      };
    });

    final transactions =
        await MobileBankingApi(dio).getActivityTransactions(cardId: ' ');

    expect(transactions.single.id, 'all-cards');
  });

  test('a later page failure does not return a misleading partial history',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      if (options.queryParameters['page'] == 2) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'The next page could not be loaded',
        );
      }
      return _page(1, [_transaction('first')]);
    });

    await expectLater(
      MobileBankingApi(dio).getActivityTransactions(),
      throwsA(isA<DioException>()),
    );
  });

  test('a server repeating a page fails instead of looping or doubling totals',
      () async {
    var calls = 0;
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      calls++;
      return _page(1, [_transaction('repeated')]);
    });

    await expectLater(
      MobileBankingApi(dio).getActivityTransactions(),
      throwsStateError,
    );
    expect(calls, 2);
  });

  test('unpaginated compatibility responses complete after their real rows',
      () async {
    var calls = 0;
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      calls++;
      return {
        'transactions': [_transaction('legacy')]
      };
    });

    final transactions = await MobileBankingApi(dio).getActivityTransactions();

    expect(calls, 1);
    expect(transactions.single.id, 'legacy');
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final Map<String, Object?> Function(RequestOptions) respond;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode(respond(options)),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
}
