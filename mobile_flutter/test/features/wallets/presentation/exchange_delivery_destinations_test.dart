import 'dart:async';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_flow_dialog.dart';
class FlowApi extends MobilePlatformApi {
 FlowApi():super(Dio());
 String? address; Map<String,dynamic>? bank;
 @override Future<List<Map<String,dynamic>>> getExchangeDestinations() async=>[];
 @override Future<List<PlatformResource>> getEqualsBankingInfos() async=>[];
 @override Future<Map<String,dynamic>> getExchangeQuote({required BoomFiExchangeBalance source,required BoomFiExchangeBalance destination,required String sellAmount,Map<String,dynamic>? bankWithdrawal,String? interlaceDestinationAddress}) async {
  address=interlaceDestinationAddress;bank=bankWithdrawal;
  return {'session':'q','expiry':DateTime.now().add(const Duration(minutes:5)).toIso8601String(),'buy_amount':'11.8','buy_currency':destination.currency};
 }
}
const wallet=HoppaWalletAsset(symbol:'USDC',name:'USD Coin',network:'Ethereum',amount:0,fiatValue:0,address:'0x1111111111111111111111111111111111111111',tint:Colors.blue,walletId:'owned');
void main(){
 testWidgets('loads real address resources independently of addressless asset balances', (tester) async {
  tester.view.physicalSize=const Size(1200,1800);tester.view.devicePixelRatio=1;addTearDown(tester.view.reset);
  final loaded=Completer<List<PlatformResource>>();final api=FlowApi();
  final overview=BoomFiExchangeOverview.fromJson({'balances':{'balances':[
   {'account_id':1,'currency':'EUR','amount':'20'}, {'account_id':2,'currency':'USDC','amount':'0','chain':{'id':1,'name':'Ethereum'}}]}});
  await tester.pumpWidget(ProviderScope(overrides:[
   userWalletsProvider.overrideWith((ref)=>loaded.future),
   mobilePlatformApiProvider.overrideWithValue(api),payeesProvider.overrideWith((ref) async=>[])
  ],child:MaterialApp(home:Scaffold(body:ExchangeFlowDialog(flow:ExchangeFlow.convert,overview:overview,outflowsEnabled:true,
   wallets:const [HoppaWalletAsset(symbol:'USDC',name:'USDC',network:'',amount:0,fiatValue:0,address:'',tint:Colors.blue,walletId:'balance')])))));
  await tester.pump();
  expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,isNull);
  expect(find.text('Loading your crypto card deposit addresses…'),findsOneWidget);
  loaded.complete([
   PlatformResource(id:'owned',title:'USDC',subtitle:'',metadata:{'balances':[{'currency':'USDC','available':'0'}], 'addresses':[for(final chain in ['MATIC','ETH']) {'currency':'USDC','chain':chain,'address':wallet.address}]}),
  ]);
  await tester.pumpAndSettle();
  expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,isNotNull);
  expect(find.text('USDT is not enabled for conversion on your Exchange account.'),findsOneWidget);
  await tester.tap(find.byType(SwitchListTile));await tester.pumpAndSettle();
  expect(find.textContaining('USDC · ETH ·'),findsOneWidget);
  await tester.enterText(find.byType(TextField),'10');await tester.tap(find.text('Get quote'));await tester.pumpAndSettle();
  expect(api.address,wallet.address);expect(tester.takeException(),isNull);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('unavailable network cannot enable delivery and address failures can retry', (tester) async {
  tester.view.physicalSize=const Size(1200,1800);tester.view.devicePixelRatio=1;addTearDown(tester.view.reset);
  var attempt=0;
  final overview=BoomFiExchangeOverview.fromJson({'balances':{'balances':[
   {'account_id':1,'currency':'EUR','amount':'20'}, {'account_id':2,'currency':'USDC','amount':'0','chain':{'id':1399811149,'name':'Solana'}}]}});
  await tester.pumpWidget(ProviderScope(overrides:[
   depositAddressesProvider.overrideWith((ref) async {
    if(attempt++==0) throw Exception('Unavailable');
    return [PlatformResource(id:'eth',title:'USDC',subtitle:'ETH',metadata:{'asset':'USDC','network':'ETH','address':wallet.address})];
   }),mobilePlatformApiProvider.overrideWithValue(FlowApi()),payeesProvider.overrideWith((ref) async=>[])
  ],child:MaterialApp(home:Scaffold(body:ExchangeFlowDialog(flow:ExchangeFlow.convert,overview:overview,outflowsEnabled:true)))));
  await tester.pumpAndSettle();expect(find.text('Retry deposit addresses'),findsOneWidget);
  await tester.ensureVisible(find.text('Retry deposit addresses'));await tester.tap(find.text('Retry deposit addresses'));await tester.pumpAndSettle();
  expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,isNull);
  expect(find.textContaining('No crypto card deposit address matches'),findsOneWidget);
  expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
 });

 for(final enabled in [false,true]){
 testWidgets('card delivery is optional and reviewed: $enabled',(tester) async {
  tester.view.physicalSize=const Size(1200,1400);tester.view.devicePixelRatio=1;addTearDown(tester.view.reset);
  final api=FlowApi();final overview=BoomFiExchangeOverview.fromJson({'balances':{'balances':[
   {'account_id':1,'currency':'EUR','amount':'20'}, {'account_id':2,'currency':'USDC','amount':'0','chain':{'id':1,'name':'Ethereum'}}]}});
  await tester.pumpWidget(ProviderScope(overrides:[exchangeCardDepositAddressesProvider.overrideWith((ref) async => const [wallet]),mobilePlatformApiProvider.overrideWithValue(api),payeesProvider.overrideWith((ref) async=>[])],child:MaterialApp(home:Scaffold(body:ExchangeFlowDialog(flow:ExchangeFlow.convert,overview:overview,outflowsEnabled:true,wallets:const[wallet])))));
  await tester.pumpAndSettle();
  expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,isFalse);
  if(enabled){await tester.tap(find.byType(SwitchListTile));await tester.pumpAndSettle();}
  await tester.enterText(find.byType(TextField),'10');await tester.tap(find.text('Get quote'));await tester.pumpAndSettle();
  expect(api.address,enabled?wallet.address:null);
  expect(find.textContaining('After settlement:'),enabled?findsOneWidget:findsNothing);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Confirm exchange')).onPressed,isNull);
  expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
 });
 }
 testWidgets('saved Equals recipients populate bank details and filter unusable accounts',(tester) async {
  tester.view.physicalSize=const Size(1200,1500);tester.view.devicePixelRatio=1;addTearDown(tester.view.reset);
  final api=FlowApi();final overview=BoomFiExchangeOverview.fromJson({'balances':{'balances':[
   {'account_id':2,'currency':'USDC','amount':'20','chain':{'id':1,'name':'Ethereum'}},{'account_id':1,'currency':'EUR','amount':'0'}]}});
  await tester.pumpWidget(ProviderScope(overrides:[exchangeCardDepositAddressesProvider.overrideWith((ref) async => const [wallet]),mobilePlatformApiProvider.overrideWithValue(api),payeesProvider.overrideWith((ref) async=>[
   const Payee(id:'p1',name:'Jane Doe',firstName:'Jane',lastName:'Doe',accountReference:'DE89370400440532013000',bankName:'Example Bank',provider:'EqualsMoney',currency:'EUR'),
   const Payee(id:'p2',name:'Disabled recipient',accountReference:'DE89370400440532013000',provider:'EqualsMoney',currency:'EUR',status:'disabled'),
   const Payee(id:'p3',name:'Masked recipient',accountReference:'********3000',provider:'EqualsMoney',currency:'EUR'),
  ])],child:MaterialApp(home:Scaffold(body:ExchangeFlowDialog(flow:ExchangeFlow.convert,overview:overview,outflowsEnabled:true)))));
  await tester.pumpAndSettle();await tester.tap(find.text('New payee'));await tester.pumpAndSettle();
  expect(find.textContaining('Disabled recipient'),findsNothing);expect(find.textContaining('Masked recipient'),findsNothing);
  await tester.tap(find.textContaining('Jane Doe').last);await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first,'10');await tester.tap(find.text('Get quote'));await tester.pumpAndSettle();
  expect(api.bank?['accountNumber'],'DE89370400440532013000');expect(api.bank?['firstName'],'Jane');expect(api.bank?['country'],'DE');
  expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
 });
}
