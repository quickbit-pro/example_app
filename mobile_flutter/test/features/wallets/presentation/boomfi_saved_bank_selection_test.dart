import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_flow_dialog.dart';

class SavedBankApi extends MobilePlatformApi {
  SavedBankApi() : super(Dio());
  Map<String,dynamic>? bank;
  @override
  Future<List<Map<String,dynamic>>> getExchangeDestinations() async => [
    {'id':77,'type':'Fiat','enabled':true,'currencies':['EUR'],'name':'My Revolut','bankName':'Revolut Bank UAB','accountNumberHint':'********2555'},
    {'id':88,'type':'Fiat','enabled':false,'currencies':['EUR'],'name':'Disabled bank'},
  ];
  @override
  Future<List<PlatformResource>> getEqualsBankingInfos() async => [];
  @override
  Future<Map<String,dynamic>> getExchangeQuote({required BoomFiExchangeBalance source, required BoomFiExchangeBalance destination, required String sellAmount, Map<String,dynamic>? bankWithdrawal, String? interlaceDestinationAddress}) async {
    bank=bankWithdrawal;
    return {'session':'quote-test','expiry':DateTime.now().add(const Duration(minutes:5)).toIso8601String()};
  }
}
void main() {
  testWidgets('saved masked bank is selectable and quoted by ID', (tester) async {
    tester.view.physicalSize=const Size(1200,1000);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final api=SavedBankApi();
    final overview=BoomFiExchangeOverview.fromJson({'balances':{'balances':[
      {'account_id':139,'currency':'USDC','amount':'12.582916','chain':{'id':1,'name':'Ethereum'}},
      {'account_id':142,'currency':'EUR','amount':'0'}
    ]}});
    await tester.pumpWidget(ProviderScope(overrides:[mobilePlatformApiProvider.overrideWithValue(api)],child:MaterialApp(home:Scaffold(body:ExchangeFlowDialog(flow:ExchangeFlow.convert,overview:overview,outflowsEnabled:true)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New payee')); await tester.pumpAndSettle();
    expect(find.textContaining('Disabled bank'),findsNothing);
    await tester.tap(find.textContaining('My Revolut').last);await tester.pumpAndSettle();
    expect(find.text('IBAN'),findsNothing);
    await tester.enterText(find.byType(TextField),'5');
    await tester.tap(find.text('Get quote'));await tester.pumpAndSettle();
    expect(api.bank,{'externalAccountId':77});
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
