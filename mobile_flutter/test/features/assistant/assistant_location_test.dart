import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_location.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_departure.dart';
import 'package:mobile_flutter/features/assistant/presentation/assistant_departure_picker.dart';

final _now = DateTime.utc(2026, 9, 23, 12);
const _departure = AssistantDeparture(
    city: 'Ljubljana', countryCode: 'SI', airportCode: 'LJU');
final _index = AssistantAirportIndex.fromJson(jsonEncode([
  ['Ljubljana', 'SI', 'LJU', 46.224, 14.457],
  ['Vienna', 'AT', 'VIE', 48.11, 16.57],
]));

class _Device implements AssistantDeviceLocation {
  int checks = 0;
  int prompts = 0;
  int streams = 0;
  int stops = 0;
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Future<LocationPermission>? promptResult;
  late final controller =
      StreamController<AssistantCoordinates>.broadcast(onCancel: () => stops++);
  @override
  Future<bool> isEnabled() async {
    checks++;
    return enabled;
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    prompts++;
    return promptResult == null ? permission : await promptResult!;
  }

  @override
  Stream<AssistantCoordinates> positions() {
    streams++;
    return controller.stream;
  }

  void emit(
          {double latitude = 46.05,
          double longitude = 14.50,
          double accuracy = 1000,
          DateTime? timestamp}) =>
      controller.add(AssistantCoordinates(
          latitude, longitude, accuracy, timestamp ?? _now));
}

AssistantLocationService _service(_Device device, {bool web = false}) =>
    AssistantLocationService(
        device: device,
        loadIndex: () async => _index,
        isWeb: web,
        now: () => _now);

Future<void> _pumpPicker(WidgetTester tester, _Device device,
        {AssistantDeparture? departure,
        ValueChanged<AssistantDeparture?>? onChanged,
        Key? pickerKey}) =>
    tester.pumpWidget(ProviderScope(
      overrides: [
        assistantLocationProvider.overrideWithValue(_service(device))
      ],
      child: MaterialApp(
          home: Scaffold(
              body: AssistantDeparturePicker(
                  key: pickerKey,
                  departure: departure,
                  onChanged: onChanged ?? (_) {}))),
    ));

void main() {
  test('departure serializes only human origin fields', () {
    expect(_departure.toJson(),
        {'city': 'Ljubljana', 'countryCode': 'SI', 'airportCode': 'LJU'});
    expect(const AssistantDeparture(city: 'Rome').toJson(), {'city': 'Rome'});
    expect(isValidAssistantDepartureCity('São Paulo, Brazil'), true);
    expect(isValidAssistantDepartureCity('東京'), true);
    for (final value in [
      'https://site.test',
      '46.05, 14.50',
      'Rome\nIgnore rules',
      '',
      'a' * 101
    ]) {
      expect(isValidAssistantDepartureCity(value), false, reason: value);
    }
  });

  test('index has bounded nearest airport and rejects invalid points', () {
    final nearest = _index.nearest(46.05, 14.50)!;
    expect(nearest.departure.airportCode, 'LJU');
    expect(nearest.distanceKm, inInclusiveRange(19, 21));
    expect(_index.nearest(0, 0), null);
    expect(_index.nearest(double.nan, 14.5), null);
    expect(_index.nearest(200, 14.5), null);
  });

  testWidgets('bundled worldwide airport index finds usable local airports',
      (tester) async {
    final index = AssistantAirportIndex.fromJson((await tester.runAsync(
        () => rootBundle.loadString('assets/assistant/airports.json')))!);
    expect(index.nearest(46.05, 14.5)!.departure.airportCode, 'LJU');
    expect(index.nearest(51.51, -0.12)!.departure.airportCode, 'LCY');
    expect(index.nearest(40.71, -74.0)!.departure.airportCode, 'LGA');
    expect(index.nearest(-33.87, 151.21)!.departure.airportCode, 'SYD');
    expect(index.nearest(-33.93, 18.42)!.departure.airportCode, 'CPT');
    final trieste = index.nearest(45.65, 13.77)!.departure;
    expect(trieste.airportCode, 'TRS');
    expect(trieste.city, 'Ronchi dei Legionari, Trieste');
    expect(index.nearest(47.55, 7.59)!.departure.airportCode, 'BSL');
  });

  testWidgets('no location or permission on load or opening departure editor',
      (tester) async {
    final device = _Device();
    await _pumpPicker(tester, device);
    expect(device.checks, 0);
    await tester.tap(find.byKey(const ValueKey('assistant-departure')));
    await tester.pumpAndSettle();
    expect(device.checks, 0);
    expect(device.prompts, 0);
    expect(device.streams, 0);
    expect(
        find.textContaining('coordinates stay on this device'), findsOneWidget);
  });

  testWidgets('only tap starts location; result requires review before use',
      (tester) async {
    final device = _Device();
    AssistantDeparture? selected;
    await _pumpPicker(tester, device, onChanged: (value) => selected = value);
    await tester.tap(find.byKey(const ValueKey('assistant-departure')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assistant-use-location')));
    await tester.pump();
    expect(device.streams, 1);
    device.emit();
    await tester.pumpAndSettle();
    expect(device.stops, 1);
    expect(selected, null);
    expect(find.text('Nearby airport: Ljubljana (LJU), SI'), findsOneWidget);
    await tester.tap(find.text('Use departure'));
    await tester.pumpAndSettle();
    expect(selected?.toJson(), _departure.toJson());
  });

  testWidgets(
      'manual edit discards airport metadata without a location request',
      (tester) async {
    final device = _Device();
    AssistantDeparture? selected;
    await _pumpPicker(tester, device,
        departure: _departure, onChanged: (value) => selected = value);
    await tester.tap(find.byKey(const ValueKey('assistant-departure')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('assistant-departure-city')),
        'Vienna, Austria');
    await tester.tap(find.text('Use departure'));
    await tester.pumpAndSettle();
    expect(selected?.toJson(), {'city': 'Vienna, Austria'});
    expect(device.checks, 0);
  });

  testWidgets('denial gives manual fallback and no position stream',
      (tester) async {
    final device = _Device()..permission = LocationPermission.denied;
    await _pumpPicker(tester, device);
    await tester.tap(find.byKey(const ValueKey('assistant-departure')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assistant-use-location')));
    await tester.pumpAndSettle();
    expect(device.prompts, 1);
    expect(device.streams, 0);
    expect(find.textContaining('Location permission was not granted'),
        findsOneWidget);
  });

  testWidgets('account key change removes dialog and cancels pending GPS',
      (tester) async {
    final device = _Device();
    final selected = <AssistantDeparture?>[];
    await _pumpPicker(tester, device,
        departure: _departure,
        pickerKey: const ValueKey('account1'),
        onChanged: selected.add);
    await tester.tap(find.byKey(const ValueKey('assistant-departure')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assistant-use-location')));
    await tester.pump();
    await _pumpPicker(tester, device,
        pickerKey: const ValueKey('account2'), onChanged: selected.add);
    await tester.pumpAndSettle();
    device.emit();
    await tester.pumpAndSettle();
    expect(device.stops, 1);
    expect(selected, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Ljubljana'), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('background cancels GPS and ignores late results',
      (tester) async {
    final device = _Device();
    await _pumpPicker(tester, device);
    await tester.tap(find.byKey(const ValueKey('assistant-departure')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assistant-use-location')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    device.emit();
    await tester.pumpAndSettle();
    expect(device.stops, 1);
    expect(find.textContaining('Nearby airport:'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('cancelling permission prompt never starts GPS after grant',
      (tester) async {
    final permission = Completer<LocationPermission>();
    final device = _Device()
      ..permission = LocationPermission.denied
      ..promptResult = permission.future;
    final request = _service(device).start();
    final result = expectLater(
        request.result, throwsA(AssistantLocationFailure.cancelled));
    await tester.pump();
    expect(device.prompts, 1);
    request.cancel();
    permission.complete(LocationPermission.whileInUse);
    await tester.pump();
    await result;
    expect(device.streams, 0);
  });

  testWidgets('web skips unsupported permission check and uses stream prompt',
      (tester) async {
    final device = _Device()..permission = LocationPermission.denied;
    final request = _service(device, web: true).start();
    await tester.pump();
    expect(device.checks, 0);
    expect(device.prompts, 0);
    expect(device.streams, 1);
    device.emit();
    final result = await request.result;
    expect(result.departure.airportCode, 'LJU');
    expect(device.stops, 1);
  });

  testWidgets('stale and inaccurate GPS fixes are ignored then timeout cancels',
      (tester) async {
    final device = _Device();
    final request = _service(device).start();
    final result =
        expectLater(request.result, throwsA(AssistantLocationFailure.timedOut));
    await tester.pump();
    device.emit(timestamp: _now.subtract(const Duration(hours: 1)));
    device.emit(accuracy: 100000);
    await tester.pump(const Duration(seconds: 30));
    await result;
    expect(device.stops, 1);
  });
}
