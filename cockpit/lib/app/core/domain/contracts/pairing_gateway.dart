import 'package:cockpit/app/core/domain/entities/pair_event.dart';

/// Uma sessão **efêmera** de pareamento de aparelho.
///
/// Sobe um `pi --mode rpc --no-session` (com a extensão remote-pi), injeta um
/// `REMOTE_PI_DIRECT_CONFIG` de pareamento e dispara `/remote-pi pair`. Os
/// eventos custom do remote-pi chegam tipados por [events]; [cancel] mata o
/// processo (sem órfão) e limpa a pasta temporária.
///
/// Uma instância = uma tentativa de pareamento (processo próprio). Contrato no
/// domínio; a impl (Process/filesystem) mora em `data/`.
abstract class PairingGateway {
  /// Stream dos eventos de pareamento ([PairCodeReady], [PairDevicePaired],
  /// [PairFailed]). Broadcast; fecha quando a sessão encerra.
  Stream<PairEvent> get events;

  /// Sobe o processo e dispara o pareamento com a validade [ttl]. Falhas viram
  /// um [PairFailed] em [events] (não lança).
  Future<void> start({Duration ttl});

  /// Encerra a sessão: mata o processo e remove a pasta temporária.
  Future<void> cancel();
}

/// Cria uma [PairingGateway] **nova por chamada** (cada tentativa de pareamento
/// sobe seu próprio processo efêmero). Contrato no domínio; a impl (que conhece
/// o `PiSpawnConfig`) mora em `data/`.
///
/// É um **tipo nomeado** de propósito (em vez de `PairingGateway Function()`):
/// assim o `ConnectivityViewModel` pode ser auto-injetado via `.new` — o parser
/// de parâmetros do `auto_injector` não lida com dois `T Function()` seguidos.
abstract class PairingGatewayFactory {
  PairingGateway create();
}
