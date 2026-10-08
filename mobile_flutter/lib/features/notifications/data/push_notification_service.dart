import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import 'firebase_configuration.dart';

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(ref.watch(dioProvider));
  ref.onDispose(service.dispose);
  return service;
});

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!FirebaseConfiguration.isConfigured) return;
  await Firebase.initializeApp(options: FirebaseConfiguration.current);
}

class PushNotificationService {
  PushNotificationService(this._dio);

  final Dio _dio;
  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _active = false;
  bool _listenersReady = false;
  bool _initialMessageHandled = false;

  void Function(RemoteMessage message)? onForegroundMessage;
  void Function(String route)? onOpenRoute;

  static Future<bool>? _initialization;

  static Future<bool> initializeFirebase() =>
      _initialization ??= _initializeFirebase().then((ready) {
        if (!ready) _initialization = null;
        return ready;
      });

  static Future<bool> _initializeFirebase() async {
    if (!FirebaseConfiguration.isConfigured) return false;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: FirebaseConfiguration.current);
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Firebase initialization failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<void> activate() async {
    if (_active || !FirebaseConfiguration.isConfigured) return;
    if (!await initializeFirebase()) return;

    _active = true;
    _messaging ??= FirebaseMessaging.instance;
    _attachListeners();

    try {
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _waitForApnsToken();
      }
      final token = await _messaging!.getToken();
      if (token != null && token.isNotEmpty) await _registerToken(token);
      await _handleInitialMessage();
    } catch (error, stackTrace) {
      debugPrint('Push notification activation failed: $error\n$stackTrace');
    }
  }

  Future<void> deactivate() async {
    if (!_active || _messaging == null) return;
    _active = false;
    try {
      final token = await _messaging!.getToken();
      if (token != null && token.isNotEmpty) {
        await _dio.post<void>(
          '/api/v1/mobile/notifications/devices/unregister',
          data: {'token': token},
        );
      }
    } catch (error) {
      debugPrint('Push device unregister failed: $error');
    }
  }

  void _attachListeners() {
    if (_listenersReady || _messaging == null) return;
    _listenersReady = true;
    _tokenSubscription = _messaging!.onTokenRefresh.listen((token) {
      if (_active) unawaited(_registerToken(token));
    });
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
      if (_active) onForegroundMessage?.call(message);
    });
    _openedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (_active) _openMessage(message);
    });
  }

  Future<void> _registerToken(String token) async {
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    await _dio.post<void>(
      '/api/v1/mobile/notifications/devices',
      data: {
        'token': token,
        'platform': platform,
        'locale':
            WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
      },
    );
  }

  Future<void> _waitForApnsToken() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      if (await _messaging!.getAPNSToken() != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _handleInitialMessage() async {
    if (_initialMessageHandled || _messaging == null) return;
    _initialMessageHandled = true;
    final message = await _messaging!.getInitialMessage();
    if (message != null && _active) _openMessage(message);
  }

  void _openMessage(RemoteMessage message) {
    final route = message.data['route']?.trim();
    if (route != null) openRoute(route);
  }

  void openRoute(String route) {
    if (_isAllowedRoute(route)) onOpenRoute?.call(route);
  }

  bool _isAllowedRoute(String route) {
    if (!route.startsWith('/') || route.startsWith('//')) return false;
    return const [
      '/home',
      '/activity',
      '/accounts',
      '/cards',
      '/kyc',
      '/business',
      '/onboarding/banking',
      '/wallets',
      '/transactions',
      '/notifications',
      '/support',
    ].any((prefix) => route == prefix || route.startsWith('$prefix/'));
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}
