// The per-install visitor id (addendum A): created once, kept in the app's
// preferences, reused on every later sign-up page visit, and replaced when
// the stored value is not one of ours.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/signup/data/visitor_id_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('creates a v4 UUID once and hands the same one back afterwards',
      () async {
    SharedPreferences.setMockInitialValues({});
    const store = VisitorIdStore();
    final first = await store.getOrCreate();
    expect(VisitorIdStore.isVisitorId(first), isTrue, reason: first);
    expect(first.length, 36);
    expect(await store.getOrCreate(), first);
    expect(await const VisitorIdStore().getOrCreate(), first,
        reason: 'the id belongs to the install, not the object');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(VisitorIdStore.preferenceKey), first);
  });

  test('a stored id survives a restart', () async {
    SharedPreferences.setMockInitialValues({
      VisitorIdStore.preferenceKey: '5b2f7c3e-1c7a-4c1e-9f3d-2a6e8b4d9c10',
    });
    expect(await const VisitorIdStore().getOrCreate(),
        '5b2f7c3e-1c7a-4c1e-9f3d-2a6e8b4d9c10');
  });

  test('a value that is not ours is replaced, never sent', () async {
    SharedPreferences.setMockInitialValues({
      VisitorIdStore.preferenceKey: 'not-a-uuid; drop table',
    });
    final id = await const VisitorIdStore().getOrCreate();
    expect(VisitorIdStore.isVisitorId(id), isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(VisitorIdStore.preferenceKey), id);
  });

  test('ids are random and carry the v4 version and variant bits', () {
    final a = VisitorIdStore.newVisitorId(Random(1));
    final b = VisitorIdStore.newVisitorId(Random(2));
    expect(a, isNot(b));
    expect(a[14], '4');
    expect('89ab', contains(a[19]));
    expect(VisitorIdStore.isVisitorId(a), isTrue);
  });
}
