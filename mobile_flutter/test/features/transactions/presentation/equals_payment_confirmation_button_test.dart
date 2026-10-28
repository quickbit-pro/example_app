import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/data/equals_payment_confirmation_api.dart';
import 'package:mobile_flutter/features/transactions/presentation/equals_payment_confirmation_button.dart';

class FakeApi extends EqualsPaymentConfirmationApi {
  FakeApi() : super(Dio());
  int calls = 0;
  final pending = Completer<Uint8List>();
  @override
  Future<Uint8List> download(String id, {CancelToken? cancelToken}) {
    calls++;
    return pending.future;
  }
}

void main() {
  testWidgets(
      'fits a phone and prevents duplicate downloads; unavailable PDF can be retried',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          equalsPaymentConfirmationApiProvider.overrideWithValue(api)
        ],
        child: MaterialApp(
            home: Scaffold(
                body: EqualsPaymentConfirmationButton(
                    transaction: LedgerTransaction.fromJson({
          'id': 91191,
          'type': 'payout',
          'metadata': {'provider': 'equalsmoney', 'paymentId': 9433626}
        }))))));
    await tester.tap(find.text('Payment confirmation PDF'));
    await tester.pump();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(api.calls, 1);
    api.pending.completeError(DioException(
        requestOptions: RequestOptions(),
        response: Response(requestOptions: RequestOptions(), statusCode: 404)));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Payment confirmation is not available for this transaction yet.'),
        findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });
}
