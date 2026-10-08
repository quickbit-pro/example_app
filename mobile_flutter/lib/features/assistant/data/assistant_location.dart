import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/assistant_departure.dart';

final assistantLocationProvider = Provider<AssistantLocationService>(
  (ref) => AssistantLocationService(),
);

class AssistantAirportSuggestion {
  const AssistantAirportSuggestion(this.departure, this.distanceKm);
  final AssistantDeparture departure;
  final double distanceKm;
}

enum AssistantLocationFailure {
  denied,
  unavailable,
  tooFar,
  timedOut,
  cancelled,
}

/// Ephemeral device-only position. Never serializable or persisted.
class AssistantCoordinates {
  const AssistantCoordinates(
      this.latitude, this.longitude, this.accuracy, this.timestamp);
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;
}

abstract interface class AssistantDeviceLocation {
  Future<bool> isEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Stream<AssistantCoordinates> positions();
}

class _DeviceLocation implements AssistantDeviceLocation {
  @override
  Future<bool> isEnabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  @override
  Stream<AssistantCoordinates> positions() => Geolocator.getPositionStream(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      ).map((position) => AssistantCoordinates(position.latitude,
          position.longitude, position.accuracy, position.timestamp));
}

class AssistantAirportIndex {
  AssistantAirportIndex._(this._airports);
  final List<_Airport> _airports;

  factory AssistantAirportIndex.fromJson(String data) {
    final rows = jsonDecode(data) as List<dynamic>;
    final airports = <_Airport>[];
    for (final row in rows) {
      if (row is! List || row.length != 5) continue;
      final rawCity = row[0];
      // Airport municipalities sometimes name two cities separated by a slash
      // (e.g. Basel / Mulhouse). Keep both while using the strict label format
      // accepted by the chat endpoint, without broadening it to arbitrary URLs.
      final city = rawCity is String
          ? rawCity
              .replaceAll(RegExp(r'\s*/\s*'), ', ')
              .replaceAll('&', ' and ')
              .replaceAll(RegExp(r' +'), ' ')
              .trim()
          : rawCity;
      final country = row[1];
      final code = row[2];
      final lat = row[3];
      final lon = row[4];
      if (city is! String ||
          !isValidAssistantDepartureCity(city) ||
          country is! String ||
          !RegExp(r'^[A-Z]{2}$').hasMatch(country) ||
          code is! String ||
          !RegExp(r'^[A-Z]{3}$').hasMatch(code) ||
          lat is! num ||
          lon is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180) {
        continue;
      }
      airports.add(_Airport(
          AssistantDeparture(
              city: city, countryCode: country, airportCode: code),
          lat.toDouble(),
          lon.toDouble()));
    }
    return AssistantAirportIndex._(airports);
  }

  AssistantAirportSuggestion? nearest(double latitude, double longitude,
      {double maxDistanceKm = 250}) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    _Airport? nearest;
    var nearestDistance = maxDistanceKm;
    for (final airport in _airports) {
      final distance =
          _distanceKm(latitude, longitude, airport.latitude, airport.longitude);
      if (distance <= nearestDistance) {
        nearest = airport;
        nearestDistance = distance;
      }
    }
    return nearest == null
        ? null
        : AssistantAirportSuggestion(nearest.departure, nearestDistance);
  }
}

class _Airport {
  const _Airport(this.departure, this.latitude, this.longitude);
  final AssistantDeparture departure;
  final double latitude;
  final double longitude;
}

double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const radians = math.pi / 180;
  final dLat = (lat2 - lat1) * radians;
  final dLon = (lon2 - lon1) * radians;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * radians) *
          math.cos(lat2 * radians) *
          math.pow(math.sin(dLon / 2), 2);
  return 6371 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
}

/// No location access is performed until [start] is called by an explicit tap.
/// The bundled airport index runs entirely on-device; no geocoding API is used.
class AssistantLocationService {
  AssistantLocationService({
    AssistantDeviceLocation? device,
    Future<AssistantAirportIndex> Function()? loadIndex,
    bool? isWeb,
    DateTime Function()? now,
  })  : _device = device ?? _DeviceLocation(),
        _loadIndex = loadIndex ??
            (() async => AssistantAirportIndex.fromJson(
                await rootBundle.loadString('assets/assistant/airports.json'))),
        _isWeb = isWeb ?? kIsWeb,
        _now = now ?? DateTime.now;

  final AssistantDeviceLocation _device;
  final Future<AssistantAirportIndex> Function() _loadIndex;
  final bool _isWeb;
  final DateTime Function() _now;

  AssistantLocationRequest start() => AssistantLocationRequest._(this);
}

class AssistantLocationRequest {
  AssistantLocationRequest._(this._service) {
    _timer = Timer(const Duration(seconds: 30), () {
      _fail(AssistantLocationFailure.timedOut);
    });
    unawaited(_run());
  }

  final AssistantLocationService _service;
  final _completion = Completer<AssistantAirportSuggestion>();
  StreamSubscription<AssistantCoordinates>? _subscription;
  Timer? _timer;
  bool _finished = false;
  Future<AssistantAirportSuggestion> get result => _completion.future;

  Future<void> _run() async {
    try {
      // On web the position stream is the permission request. Some browsers do
      // not implement the Permissions API, so do not gate them on its result.
      if (!_service._isWeb) {
        if (!await _service._device.isEnabled()) {
          _fail(AssistantLocationFailure.unavailable);
          return;
        }
        if (_finished) return;
        var permission = await _service._device.checkPermission();
        if (_finished) return;
        if (permission == LocationPermission.denied) {
          permission = await _service._device.requestPermission();
        }
        if (_finished) return;
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          _fail(AssistantLocationFailure.denied);
          return;
        }
      }
      if (_finished) return;
      final index = await _service._loadIndex();
      if (_finished) return;
      _subscription = _service._device.positions().listen((position) {
        if (_finished) return;
        final age = _service._now().difference(position.timestamp);
        if (age > const Duration(minutes: 5) ||
            age < const Duration(minutes: -2) ||
            !position.accuracy.isFinite ||
            position.accuracy < 0 ||
            position.accuracy > 50000) {
          // Wait for a fresh, useful fix rather than assigning a wrong origin.
          return;
        }
        final suggestion = index.nearest(position.latitude, position.longitude);
        if (suggestion == null) {
          _fail(AssistantLocationFailure.tooFar);
          return;
        }
        _finished = true;
        _stop();
        _completion.complete(suggestion);
      }, onError: (Object error) {
        _fail(error is PermissionDeniedException
            ? AssistantLocationFailure.denied
            : AssistantLocationFailure.unavailable);
      }, onDone: () {
        if (!_finished) _fail(AssistantLocationFailure.unavailable);
      });
      if (_finished) _stop();
    } catch (_) {
      _fail(AssistantLocationFailure.unavailable);
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((_) {}));
    }
  }

  void _fail(AssistantLocationFailure failure) {
    if (_finished) return;
    _finished = true;
    _stop();
    _completion.completeError(failure);
  }

  void cancel() => _fail(AssistantLocationFailure.cancelled);
}
