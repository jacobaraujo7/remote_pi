import 'dart:io';

import 'package:cockpit/app/core/domain/contracts/system_permissions.dart';
import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Implementa as checagens de permissão do macOS. Em outros SOs as permissões
/// retornam [CheckStatus.notApplicable] (decisão: macOS-first).
class SystemPermissionsImpl implements SystemPermissions {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _testId = 9000;

  MacOSFlutterLocalNotificationsPlugin? get _macNotif => _plugin
      .resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin
      >();

  // ---- notificações ---------------------------------------------------------
  @override
  Future<CheckStatus> notificationStatus() async {
    if (!Platform.isMacOS) return CheckStatus.notApplicable;
    try {
      await _ensureInitialized();
      final options = await _macNotif?.checkPermissions();
      return (options?.isEnabled ?? false)
          ? CheckStatus.ok
          : CheckStatus.missing;
    } catch (_) {
      return CheckStatus.missing;
    }
  }

  @override
  Future<CheckStatus> requestNotifications() async {
    if (!Platform.isMacOS) return CheckStatus.notApplicable;
    try {
      await _ensureInitialized();
      final granted =
          await _macNotif?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      if (granted) await _showTest();
      // Re-checa: o request pode ter sido respondido antes (estado já decidido).
      return granted ? CheckStatus.ok : await notificationStatus();
    } catch (_) {
      return CheckStatus.missing;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> _showTest() async {
    await _ensureInitialized();
    await _plugin.show(
      _testId++,
      'Cockpit',
      'Notifications enabled — you will see agent alerts here.',
      const NotificationDetails(macOS: DarwinNotificationDetails()),
    );
  }
}
