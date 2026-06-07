import 'package:cockpit/domain/contracts/notifier.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificações nativas via `flutter_local_notifications` (macOS first).
class LocalNotifier implements Notifier {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  int _id = 0;

  @override
  Future<void> init() async {
    const settings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        // Desktop app está sempre em foreground: sem esses flags o
        // UNUserNotificationCenter suprime o banner silenciosamente.
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      ),
      linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
    );
    await _plugin.initialize(settings);
  }

  @override
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  }) async {
    final subtitle = workspace.isEmpty ? agentName : '$agentName · $workspace';
    await _plugin.show(
      _id++,
      'Agente terminou',
      subtitle,
      const NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(),
      ),
    );
  }
}
