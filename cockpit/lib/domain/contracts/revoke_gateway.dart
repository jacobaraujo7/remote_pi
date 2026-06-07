import 'package:cockpit/domain/exceptions/relay_error.dart';
import 'package:cockpit/domain/result.dart';

/// Revoga um aparelho pareado via `pi --mode rpc` (não pelo CLI `remote-pi`).
///
/// Sobe um pi efêmero (com a extensão remote-pi) e manda
/// `/remote-pi revoke <shortId>` — que **auto-liga o relay** e remove o peer
/// (manda `bye` pro aparelho). Sucesso é detectado pelo `notify` `Revoked: …`;
/// warnings viram [RelayError]. Contrato no domínio; a impl (Process) em `data/`.
abstract class RevokeGateway {
  Future<Result<void, RelayError>> revoke(
    String shortId, {
    Duration timeout,
  });
}
