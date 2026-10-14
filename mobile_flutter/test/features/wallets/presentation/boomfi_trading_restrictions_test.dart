import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_flow_dialog.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_account_details.dart';

class RestrictionApi extends MobilePlatformApi {
 RestrictionApi(this.restricted):super(Dio());
 final bool restricted;
 @override Future<List<Map<String,dynamic>>> getExchangeDestinations() async=>[];
 @override Future<Map<String,dynamic>> getExchangeSettlementAccounts() async=>{
  'kycStatus':'accepted','restrictedTradingCurrencies':restricted?['USDT']:[],
  'accounts':[{'chainId':1,'currencies':['USDT'],'ready':true,'reference':'deposit-1-227-usdt-1','address':'0x1111111111111111111111111111111111111111'}]
 };
}
Map<String,dynamic> overview(bool restricted,String key)=>{
 key:restricted?['USDT']:[],
 'balances':{'balances':[
  {'account_id':1,'currency':'EUR','amount':'20'},
  {'account_id':2,'currency':'USDT','amount':'12','chain':{'id':1,'name':'Ethereum'}},
  {'account_id':3,'currency':'USDC','amount':'10','chain':{'id':1,'name':'Ethereum'}}
 ]}
};
void main(){
 for(final key in ['restricted_trading_currencies','restrictedTradingCurrencies','RestrictedTradingCurrencies']){
  test('parses restrictions without hiding balances: $key',(){
   final data=BoomFiExchangeOverview.fromJson(overview(true,key));
   expect(data.canTrade('usdt'),isFalse);expect(data.canTrade('USDC'),isTrue);
   expect(data.displayBalances.where((b)=>b.currency=='USDT').single.amount,12);
  });
 }
 for(final restricted in [false,true]){
  for(final flow in [ExchangeFlow.convert,ExchangeFlow.withdraw]){
   testWidgets('USDT choice restricted=$restricted flow=$flow',(tester)async{
    tester.view.physicalSize=const Size(1200,1700);tester.view.devicePixelRatio=1;addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides:[mobilePlatformApiProvider.overrideWithValue(RestrictionApi(restricted)),
     exchangeCardDepositAddressesProvider.overrideWith((ref)async=>[]),payeesProvider.overrideWith((ref)async=>[])],
     child:MaterialApp(home:Scaffold(body:ExchangeFlowDialog(flow:flow,overview:BoomFiExchangeOverview.fromJson(overview(restricted,'restricted_trading_currencies')),outflowsEnabled:true)))));
    await tester.pumpAndSettle();
    final usdtChoices=tester.widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>)).expand((d)=>d.items??const <DropdownMenuItem<String>>[]).where((i)=>i.value?.contains(':USDT:')??false);
    expect(usdtChoices.isNotEmpty,!restricted||flow==ExchangeFlow.withdraw);
    expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
   });
  }
  testWidgets('USDT deposit visibility restricted=$restricted',(tester)async{
   tester.view.physicalSize=const Size(1200,1700);tester.view.devicePixelRatio=1;addTearDown(tester.view.reset);
   await tester.pumpWidget(ProviderScope(overrides:[mobilePlatformApiProvider.overrideWithValue(RestrictionApi(restricted))],child:const MaterialApp(home:Scaffold(body:ExchangeAccountDetails()))));
   await tester.pumpAndSettle();
   expect(find.byKey(const ValueKey('deposit-currency-USDT')),restricted?findsNothing:findsOneWidget);
   expect(find.byKey(const ValueKey('deposit-currency-USDC')),findsOneWidget);
   expect(find.textContaining('If you deposit USDT here'),findsNothing);
   expect(find.byKey(const ValueKey('deposit-address-USDT')),restricted?findsNothing:findsOneWidget);
   expect(find.byKey(const ValueKey('copy-deposit-USDT')),restricted?findsNothing:findsOneWidget);
   expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
  });
 }
}
