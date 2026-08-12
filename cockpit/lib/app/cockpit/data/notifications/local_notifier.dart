import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/core/domain/entities/sound_event.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:media_kit/media_kit.dart';

/// Notificações nativas via `flutter_local_notifications` (macOS/Windows/Linux)
/// + chime in-app via `media_kit` (cross-platform).
class LocalNotifier implements Notifier {
  /// AppUserModelID do Cockpit no Windows. Mesmo valor do `app_id` do
  /// empacotamento (`windows/packaging/exe/make_config.yaml`) e do bundle id
  /// do macOS — identifica o app na central de notificações.
  static const String _windowsAppUserModelId = 'work.jacobmoura.cockpit';

  /// GUID fixo que o Windows usa pra registrar o callback de ativação do
  /// notificador (COM CLSID). Gerado uma única vez — **NÃO pode mudar entre
  /// releases**, senão o Windows trata como um notificador novo e perde o
  /// registro/histórico do usuário.
  static const String _windowsNotifierGuid =
      '88faed92-a013-44b2-a814-7dd1aebf7d59';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  int _id = 0;

  /// Player dedicado ao chime curto, reusado a cada toque (re-`open` reinicia).
  Player? _chime;

  @override
  Future<void> init() async {
    _chime = Player();
    final settings = InitializationSettings(
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
      linux: LinuxInitializationSettings(
        defaultActionName: t.cockpit.notifications.open,
      ),
      // Sem este bloco a plataforma Windows nunca é inicializada e todo
      // `show()` lança LateInitializationError (issue #91).
      windows: WindowsInitializationSettings(
        appName: 'Cockpit',
        appUserModelId: _windowsAppUserModelId,
        guid: _windowsNotifierGuid,
      ),
    );
    await _plugin.initialize(settings: settings);
  }

  @override
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  }) => _show(t.cockpit.notifications.agentFinished, agentName, workspace);

  @override
  Future<void> agentNeedsAction({
    required String agentName,
    required String workspace,
  }) => _show(t.cockpit.notifications.agentNeedsAction, agentName, workspace);

  @override
  Future<void> agentCrashed({
    required String agentName,
    required String workspace,
  }) => _show(t.cockpit.notifications.agentCrashed, agentName, workspace);

  Future<void> _show(String title, String agentName, String workspace) async {
    final subtitle = workspace.isEmpty ? agentName : '$agentName · $workspace';
    await _plugin.show(
      id: _id++,
      title: title,
      body: subtitle,
      notificationDetails: const NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(),
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> play(
    SoundEvent event, {
    String? customPath,
    double volume = 50,
  }) async {
    try {
      await _chime?.setVolume(volume.clamp(0, 100));
    } catch (_) {
      // volume é best-effort; toca no que estiver
    }
    // Custom primeiro; se o arquivo sumiu ou o media_kit não abre, cai no
    // embarcado — nunca fica mudo em silêncio por causa de um override podre.
    if (customPath != null && customPath.isNotEmpty) {
      try {
        if (await File(customPath).exists()) {
          await _chime?.open(Media(customPath));
          return;
        }
      } catch (_) {
        // cai no default abaixo
      }
    }
    try {
      await _chime?.open(Media('asset:///assets/sounds/${event.defaultAsset}'));
    } catch (_) {
      // som é best-effort: nunca quebra o fluxo do evento.
    }
  }
}
