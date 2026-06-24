import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:cockpit/app/core/domain/exceptions/relay_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Fronteira de conectividade do Cockpit: lê/define o relay global e gerencia os
/// aparelhos pareados.
///
/// Tudo é delegado ao binário `remote-pi` (shell-out) e ao config compartilhado
/// `~/.pi/remote/config.json` — o Cockpit **nunca** implementa crypto nem fala o
/// protocolo do relay direto. Contrato no domínio; a impl (Process/filesystem)
/// mora em `data/`.
///
/// Escopo: relay global + listar aparelhos (via CLI `remote-pi`). Revogar e
/// parear rodam por `pi --mode rpc` (ver [RevokeGateway] / [PairingGateway]) —
/// ficam fora deste contrato.
abstract class RelayGateway {
  /// URL do relay configurada em `~/.pi/remote/config.json` (`null` = nenhuma).
  Future<Result<String?, RelayError>> currentRelay();

  /// Define a URL do relay global (`remote-pi set-relay <url>`).
  Future<Result<void, RelayError>> setRelay(String url);

  /// Lista os aparelhos pareados (`remote-pi devices`).
  Future<Result<List<PairedDevice>, RelayError>> listDevices();

  /// Checa se o relay em [url] está no ar: `GET <url>/health` (espera HTTP 200).
  /// `Success` = saudável; `Failure(RelayError)` = inacessível/erro, com motivo.
  Future<Result<void, RelayError>> checkHealth(String url);
}
