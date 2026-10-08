import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/profile/presentation/nickname_editor.dart';

class _Api extends MobilePlatformApi {
  _Api() : super(Dio());
  final calls = <String?>[];
  bool taken = false;
  Completer<UserProfile>? pending;

  @override
  Future<UserProfile> updateProfile(
      {String? name, String? email, String? nickname}) async {
    calls.add(nickname);
    if (taken) {
      final options = RequestOptions(path: '/profile');
      throw DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 409,
            data: {'title': 'That nickname is already taken. Choose another.'},
          ));
    }
    return pending?.future ??
        Future.value(UserProfile.fromJson({'nickname': nickname}));
  }
}

Future<void> _open(WidgetTester tester, _Api api, {String? nickname}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
    child: MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showNicknameEditor(context, nickname),
                      child: const Text('Edit')),
                ))),
  ));
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'invalid and taken names keep the editor open, corrected name saves',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    api.taken = true;
    await tester.enterText(find.byType(TextField), '@ANA');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('That nickname is already taken. Choose another.'),
        findsOneWidget);
    expect(find.byType(NicknameEditor), findsOneWidget);
    api.taken = false;
    await tester.enterText(find.byType(TextField), '@ANA_123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.calls, ['ana', 'ana_123']);
    expect(find.byType(NicknameEditor), findsNothing);
  });

  testWidgets(
      'existing nickname can be removed and duplicate saves are disabled',
      (tester) async {
    final api = _Api()..pending = Completer<UserProfile>();
    await _open(tester, api, nickname: 'ana');
    expect(find.text('ana'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(api.calls, ['']);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    api.pending!.complete(UserProfile.fromJson({}));
    await tester.pumpAndSettle();
    expect(find.byType(NicknameEditor), findsNothing);
  });
}
