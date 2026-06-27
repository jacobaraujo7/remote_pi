import 'package:cockpit/app/core/domain/entities/setup_check.dart';

/// Permissões do SO necessárias ao Cockpit (macOS first). Contrato no domínio;
/// a impl (plugin de notificação + heurística de disco) mora em `data/`.
///
/// Em SOs onde a permissão não existe/não se aplica, os métodos devolvem
/// [CheckStatus.notApplicable].
abstract class SystemPermissions {
  /// Estado atual da permissão de notificações.
  Future<CheckStatus> notificationStatus();

  /// Pede a permissão de notificações e dispara uma notificação de teste.
  /// Devolve o estado resultante.
  Future<CheckStatus> requestNotifications();
}
