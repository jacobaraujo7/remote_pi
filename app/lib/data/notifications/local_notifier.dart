import 'dart:io' show Platform;

import 'package:app/data/preferences/preferences.dart';
import 'package:app/domain/contracts/notifier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificações nativas via `flutter_local_notifications` (Android/iOS).
class LocalNotifier implements Notifier {
  static const _channel = MethodChannel('app.remote_pi/notifications');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Preferences _prefs;
  int _id = 0;

  LocalNotifier(this._prefs);

  @override
  Future<void> init() async {
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    // If the user denied the system permission, reflect that in the toggle
    // so the UI shows the correct state and the warning message.
    final permitted = await hasPermission();
    if (permitted == false) {
      await _prefs.setNotificationsEnabled(false);
    }
  }

  @override
  Future<bool?> hasPermission() async {
    if (Platform.isAndroid) {
      return _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
    }
    if (Platform.isIOS) {
      try {
        final result = await _channel.invokeMethod<bool>('hasPermission');
        return result;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  }) async {
    if (!_prefs.notificationsEnabled) return;
    final subtitle = workspace.isEmpty ? agentName : '$agentName · $workspace';
    await _plugin.show(
      id: _id++,
      title: 'Agent finished',
      body: subtitle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'agent_turn',
          'Agent Turns',
          channelDescription: 'Notifications when an agent finishes a turn',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
