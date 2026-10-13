import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications only; no server (PRD: Technical approach).
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'morning_check',
    'Morning check',
    channelDescription: 'Your daily verdict once Coros has last night\'s data',
    importance: Importance.high,
    priority: Priority.high,
    color: _accent,
  );
  static const _accent = Color(0xFF97EB78);

  static Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
    );
    _ready = true;
  }

  /// Android 13+ asks the user; returns whether notifications are allowed.
  static Future<bool> requestPermission() async {
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  static const morningId = 1;
  static const weeklyId = 2;

  /// One notification per kind: a later morning check replaces the earlier one, and the
  /// weekly summary has its own slot so it never hides the morning verdict.
  static Future<void> show({required String title, required String body, int id = morningId}) async {
    await _init();
    await _plugin.show(id: id, title: title, body: body, notificationDetails: const NotificationDetails(android: _channel));
  }
}
