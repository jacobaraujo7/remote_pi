import 'package:cockpit/app/core/domain/entities/sound_event.dart';

/// Notificações nativas do SO + sons in-app. Contrato no domínio; a impl
/// (plugin) mora em `data/notifications/`.
abstract class Notifier {
  /// Inicializa o backend (pede permissão no boot).
  Future<void> init();

  /// Notifica que um agente terminou um turno.
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  });

  /// Notifica que um agente parou esperando ação do usuário (permissão,
  /// pergunta, plano).
  Future<void> agentNeedsAction({
    required String agentName,
    required String workspace,
  });

  /// Notifica que o processo de um agente morreu inesperadamente.
  Future<void> agentCrashed({
    required String agentName,
    required String workspace,
  });

  /// Toca o som in-app de [event]. Usado quando a janela está focada — chama
  /// atenção sem banner do SO (distinto do som da notificação do SO, que toca
  /// só desfocada). [customPath] = áudio escolhido pelo usuário; se ausente ou
  /// falhar ao abrir, toca o som embarcado do evento. [volume] em % (0–100).
  Future<void> play(SoundEvent event, {String? customPath, double volume});
}
