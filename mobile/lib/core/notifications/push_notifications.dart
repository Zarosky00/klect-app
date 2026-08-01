import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/klect_api.dart';

/// Reads one non-empty string from an FCM data payload.
String? pushDataString(Map<String, dynamic> data, String key) {
  final value = data[key];
  return value is String && value.isNotEmpty ? value : null;
}

/// FCM device push — stage 2 of the notifications plan (stage 1 is
/// `LocalNotifications`, for realtime arrivals while the app is
/// backgrounded-but-running).
///
/// This service only registers/unregisters the device token; the actual
/// notification is composed and sent by the deployed `push-fanout` edge
/// function, which is inert server-side until `FCM_SERVICE_ACCOUNT` and
/// `PUSH_WEBHOOK_SECRET` are configured (see `docs/OPERATIONS.md` §2). Until
/// then this simply talks to Firebase and stores a token nobody delivers to
/// yet — harmless, not a bug.
class PushNotifications {
  /// Wraps the API used to persist the device token server-side.
  PushNotifications(this._api);

  final KlectApi _api;
  String? _lastToken;
  final StreamController<String> _foregroundNotificationIds =
      StreamController<String>.broadcast();
  final StreamController<String> _openedPaths =
      StreamController<String>.broadcast();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  bool _initialMessageHandled = false;

  /// Notification ids delivered while KLECT is visible.
  Stream<String> get foregroundNotificationIds =>
      _foregroundNotificationIds.stream;

  /// Deep-link paths selected from background or terminated FCM cards.
  Stream<String> get openedPaths => _openedPaths.stream;

  /// Whether this platform can receive FCM push at all.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get _platformWire =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Initialises Firebase, requests permission, and registers the current
  /// token — then keeps listening for silent token refreshes for as long as
  /// the process lives. Call once per signed-in session (e.g. from the root
  /// shell, mirroring `LocalNotifications.ensureReady`).
  ///
  /// Safe to call when Firebase isn't configured for this build (no
  /// `google-services.json`) — `Firebase.initializeApp` failures are caught
  /// and swallowed so a missing config degrades to "no push" rather than a
  /// crash.
  Future<void> ensureRegistered() async {
    if (!isSupported) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (error) {
      // No Firebase config bundled for this build — push simply stays off.
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await _ensureMessageListeners(messaging);
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return;

    final token = await messaging.getToken();
    if (token != null) await _register(token);

    // A token can rotate at any time (app reinstall, Google Play Services
    // update, etc.) — re-register whenever that happens.
    _tokenSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      _register,
    );
  }

  Future<void> _ensureMessageListeners(FirebaseMessaging messaging) async {
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      final id = pushDataString(message.data, 'notification_id');
      if (id != null && !_foregroundNotificationIds.isClosed) {
        _foregroundNotificationIds.add(id);
      }
    });
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _emitOpenedPath,
    );
    if (_initialMessageHandled) return;
    _initialMessageHandled = true;
    final initial = await messaging.getInitialMessage();
    if (initial != null) _emitOpenedPath(initial);
  }

  void _emitOpenedPath(RemoteMessage message) {
    final path = pushDataString(message.data, 'link');
    if (path != null && !_openedPaths.isClosed) {
      _openedPaths.add(path);
    }
  }

  Future<void> _register(String token) async {
    _lastToken = token;
    try {
      await _api.registerPushToken(
        token: token,
        platform: _platformWire,
        appVersion: null,
      );
    } catch (error) {
      // Registration failures (offline, RLS edge case) are not fatal — the
      // next app open or token refresh retries.
    }
  }

  /// Disables the current device's token server-side. Call on sign-out so a
  /// signed-out device does not keep receiving the previous account's push.
  Future<void> unregister() async {
    final token = _lastToken;
    if (token == null) return;
    try {
      await _api.unregisterPushToken(token);
    } catch (error) {
      // Best-effort — the row is harmless if it lingers as enabled.
    }
    _lastToken = null;
  }

  /// Releases Firebase listeners owned by this provider instance.
  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _foregroundNotificationIds.close();
    await _openedPaths.close();
  }
}
