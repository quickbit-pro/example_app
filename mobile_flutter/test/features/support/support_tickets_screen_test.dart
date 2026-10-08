import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/support/data/support_tickets_api.dart';
import 'package:mobile_flutter/features/notifications/presentation/notification_inbox_screen.dart';
import 'package:mobile_flutter/features/support/presentation/support_tickets_screen.dart';

const ticketId = '019d0000-0000-7000-8000-000000000001';
SupportTicketDetail detail({String status = 'awaiting_user'}) =>
    SupportTicketDetail.fromJson({
      'ticket': {
        'id': ticketId,
        'subject': 'Card delivery',
        'status': status,
        'revision': 'revision-1',
        'updatedAt': '2026-09-08T10:00:00Z',
      },
      'messages': [
        {
          'isAdmin': false,
          'body': 'Where is my card?',
          'createdAt': '2026-09-07T10:00:00Z'
        },
        {
          'isAdmin': true,
          'body': 'Your card is on the way.',
          'createdAt': '2026-09-08T10:00:00Z'
        },
      ],
    });

class FakeSupportApi extends SupportTicketsApi {
  FakeSupportApi() : super(Dio());
  bool fail = true;
  int submissions = 0;
  String? replyBody;
  String? revision;
  @override
  Future<void> reply(String id, String body, String revision) async {
    submissions++;
    if (fail) {
      throw DioException(
        requestOptions: RequestOptions(),
        response:
            Response(requestOptions: RequestOptions(), statusCode: 409, data: {
          'message':
              'This ticket has changed. Refresh it before submitting your reply. Your draft has been kept.'
        }),
      );
    }
    replyBody = body;
    this.revision = revision;
  }
}

Future<void> pump(WidgetTester tester, Widget screen,
    {FakeSupportApi? api, String status = 'awaiting_user'}) async {
  tester.view.physicalSize = const Size(390, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: [
    supportTicketProvider(ticketId)
        .overrideWith((ref) async => detail(status: status)),
    if (api != null) supportTicketsApiProvider.overrideWithValue(api),
  ], child: MaterialApp(home: screen)));
  await tester.pumpAndSettle();
}

void main() {
  test('Support notifications open the ticket in both inbox surfaces', () {
    expect(safeNotificationRoute('/support/$ticketId'), '/support/$ticketId');
    expect(
        notificationDestinationLabel('/support/$ticketId'), 'Support tickets');
    expect(safeNotificationRoute('https://example.test/support'), '/home');
  });
  testWidgets('Ticket shows dated correspondence and asynchronous expectations',
      (tester) async {
    await pump(tester, const SupportTicketScreen(ticketId: ticketId));
    expect(find.text('Support team'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Awaiting your reply'), findsOneWidget);
    expect(find.textContaining('Replies are not immediate.'), findsOneWidget);
    expect(find.text('Your card is on the way.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Failed reply keeps draft through refresh; successful reply clears it',
      (tester) async {
    final api = FakeSupportApi();
    await pump(tester, const SupportTicketScreen(ticketId: ticketId), api: api);
    await tester.enterText(
        find.byType(TextFormField), ' Please share the tracking number. ');
    await tester.ensureVisible(find.text('Submit reply'));
    await tester.tap(find.text('Submit reply'));
    await tester.pumpAndSettle();
    expect(api.submissions, 1);
    expect(find.textContaining('Your draft has been kept.'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        contains('tracking number'));
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        contains('tracking number'));
    api.fail = false;
    await tester.ensureVisible(find.text('Submit reply'));
    await tester.tap(find.text('Submit reply'));
    await tester.pumpAndSettle();
    expect(api.replyBody, 'Please share the tracking number.');
    expect(api.revision, 'revision-1');
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Resolved ticket explains reopening by reply', (tester) async {
    await pump(tester, const SupportTicketScreen(ticketId: ticketId),
        status: 'resolved');
    expect(find.textContaining('submit a reply to reopen it'), findsOneWidget);
    await tester.ensureVisible(find.text('Submit reply & reopen'));
    expect(find.text('Submit reply & reopen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('New ticket validates empty subject and message', (tester) async {
    await pump(tester, const NewSupportTicketScreen());
    await tester.ensureVisible(find.text('Submit ticket'));
    await tester.tap(find.text('Submit ticket'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a subject.'), findsOneWidget);
    expect(find.text('Enter a message.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
