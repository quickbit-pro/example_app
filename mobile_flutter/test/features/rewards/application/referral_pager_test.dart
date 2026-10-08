import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/application/referral_pager.dart';

void main() {
  group('ReferralPager', () {
    test('seeds from a full first page and appends the next', () async {
      final calls = <int>[];
      final pager = ReferralPager<int>(
        pageSize: 5,
        initial: [1, 2, 3, 4, 5],
        fetch: (page, size) async {
          calls.add(page);
          return page == 2 ? [6, 7, 8, 9, 10] : [11];
        },
      );

      expect(pager.loaded, isTrue);
      expect(pager.hasMore, isTrue);
      expect(calls, isEmpty);

      await pager.loadMore();
      expect(pager.items, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(pager.hasMore, isTrue);

      await pager.loadMore();
      expect(pager.items.length, 11);
      // A short page is the last one; nothing more is asked for.
      expect(pager.hasMore, isFalse);
      await pager.loadMore();
      expect(calls, [2, 3]);
    });

    test('a short first page ends the list at once', () {
      final pager = ReferralPager<int>(
        pageSize: 5,
        initial: [1, 2],
        fetch: (page, size) async => fail('no request expected'),
      );
      expect(pager.loaded, isTrue);
      expect(pager.hasMore, isFalse);
    });

    test('load fetches the first page only when nothing was seeded',
        () async {
      var fetched = 0;
      final pager = ReferralPager<int>(
        pageSize: 2,
        fetch: (page, size) async {
          fetched += 1;
          return [1, 2];
        },
      );
      expect(pager.loaded, isFalse);
      await pager.load();
      expect(fetched, 1);
      expect(pager.items, [1, 2]);
      expect(pager.hasMore, isTrue);
      await pager.load();
      expect(fetched, 1);
    });

    test('a failed later page keeps the rows and can be retried', () async {
      var fail = true;
      final pager = ReferralPager<int>(
        pageSize: 2,
        initial: [1, 2],
        fetch: (page, size) async {
          if (fail) throw StateError('offline');
          return [3];
        },
      );
      final notifications = <void>[];
      pager.addListener(() => notifications.add(null));

      await pager.loadMore();
      expect(pager.items, [1, 2]);
      expect(pager.moreError, isA<StateError>());
      expect(pager.error, isNull);
      expect(pager.loadingMore, isFalse);

      fail = false;
      await pager.loadMore();
      expect(pager.items, [1, 2, 3]);
      expect(pager.moreError, isNull);
      expect(pager.hasMore, isFalse);
      expect(notifications, isNotEmpty);
    });

    test('refresh replaces the rows with a fresh first page', () async {
      var generation = 0;
      final pager = ReferralPager<int>(
        pageSize: 2,
        initial: [1, 2],
        fetch: (page, size) async => page == 1 ? [10 + generation] : [],
      );
      await pager.loadMore();
      expect(pager.items, [1, 2]);
      expect(pager.hasMore, isFalse);

      generation = 1;
      await pager.refresh();
      expect(pager.items, [11]);
      expect(pager.loaded, isTrue);
      expect(pager.hasMore, isFalse);
    });

    test('a failed first page is an error, not an empty list', () async {
      final pager = ReferralPager<int>(
        pageSize: 2,
        fetch: (page, size) async => throw StateError('offline'),
      );
      await pager.load();
      expect(pager.loaded, isFalse);
      expect(pager.error, isA<StateError>());
      expect(pager.items, isEmpty);
    });
  });
}
