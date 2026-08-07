/// Notificações nativas do SO. Contrato no domínio; a impl mora em
/// `data/notifications/`.
abstract class Notifier {
  /// Inicializa o backend (pede permissão).
  Future<void> init();

  /// Notifica que um agente terminou um turno.
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  });
}
