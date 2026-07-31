import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// One action selected from a system notification.
class LocalNotificationAction {
  /// Creates an action response.
  const LocalNotificationAction({required this.id, this.payload});

  /// Stable action id.
  final String id;

  /// Notification payload, if any.
  final String? payload;
}

/// System-tray notifications for realtime arrivals while the app is
/// **backgrounded but running** (stage 1 of the notifications plan).
///
/// This is *not* push: when the process dies, so does the realtime socket.
/// Real FCM push stays gated on the user's Firebase project — the deployed
/// `push-fanout` edge function is already wired for it. The channel ids here
/// (`social` / `calls`) deliberately match the `channel_id`s that function
/// sends, so when FCM arrives both paths land in the same user-visible
/// channels with the same user preferences.
class LocalNotifications {
  /// Creates the service. `onSelect` receives the deep-link path stored in
  /// the notification payload when the user taps it.
  LocalNotifications({required this._onSelect});

  final void Function(String path) _onSelect;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<LocalNotificationAction> _actions =
      StreamController<LocalNotificationAction>.broadcast();
  bool _ready = false;

  /// Action selections from notifications whose buttons open the app UI.
  Stream<LocalNotificationAction> get actions => _actions.stream;

  /// Everyday social traffic: likes, saves, reposts, comments, follows,
  /// messages. Mirrors push-fanout's `channel_id: 'social'`.
  static const AndroidNotificationChannel socialChannel =
      AndroidNotificationChannel(
        'social',
        'Activity',
        description: 'Likes, saves, comments, follows and messages',
        importance: Importance.high,
      );

  /// Incoming calls — maximum importance so the heads-up survives Do Not
  /// Disturb exemptions the user grants. Mirrors push-fanout's
  /// `channel_id: 'calls'`.
  static const AndroidNotificationChannel callsChannel =
      AndroidNotificationChannel(
        'calls',
        'Calls',
        description: 'Incoming and missed calls',
        importance: Importance.max,
      );

  /// Whether this platform has a system tray we can post to.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Initialises the plugin, creates the Android channels and asks for the
  /// Android 13+ / iOS notification permission. Safe to call repeatedly.
  ///
  /// Call this once while the app is **foregrounded** (the shell does) — a
  /// permission prompt cannot appear once we are already backgrounded, which
  /// is the only time we post.
  Future<void> ensureReady() async {
    if (_ready || !isSupported) return;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final actionId = response.actionId;
        if (actionId != null && actionId.isNotEmpty) {
          _actions.add(
            LocalNotificationAction(id: actionId, payload: response.payload),
          );
          return;
        }
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _onSelect(payload);
      },
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.createNotificationChannel(socialChannel);
      await android.createNotificationChannel(callsChannel);
      await android.requestNotificationsPermission();
    }
    _ready = true;
  }

  /// The deep-link path of the notification that cold-started the app, if
  /// that is how we were launched. Consumed once by the shell.
  Future<String?> takeLaunchPayload() async {
    if (!isSupported) return null;
    await ensureReady();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    final payload = details.notificationResponse?.payload;
    return (payload == null || payload.isEmpty) ? null : payload;
  }

  /// Posts one notification. [isCall] routes it to the calls channel.
  /// [payload] is the in-app path to open on tap.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    bool isCall = false,
    String? payload,
  }) async {
    if (!isSupported) return;
    await ensureReady();
    final channel = isCall ? callsChannel : socialChannel;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: isCall ? Priority.max : Priority.high,
          category: isCall
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.social,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  /// Posts the Android incoming-call surface with exactly Accept and Decline.
  Future<void> showIncomingCall({
    required int id,
    required String callId,
    required String callerName,
    required bool isVideo,
  }) async {
    if (!isSupported) return;
    await ensureReady();
    await _plugin.show(
      id: id,
      title: callerName,
      body: isVideo ? 'Incoming video call' : 'Incoming audio call',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          callsChannel.id,
          callsChannel.name,
          channelDescription: callsChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              'call_accept',
              'Accept',
              showsUserInterface: true,
              cancelNotification: false,
              semanticAction: SemanticAction.call,
            ),
            AndroidNotificationAction(
              'call_decline',
              'Decline',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      payload: callId,
    );
  }

  /// Removes one delivered notification.
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
