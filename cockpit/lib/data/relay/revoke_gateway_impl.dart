import 'dart:async';
import 'dart:convert';

import 'package:cockpit/config/env.dart';
import 'package:cockpit/data/relay/ephemeral_pi_rpc.dart';
import 'package:cockpit/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/domain/exceptions/relay_error.dart';
import 'package:cockpit/domain/result.dart';

/// Implementação do [RevokeGateway] sobre uma sessão [EphemeralPiRpc].
///
/// Comando one-shot: manda `/remote-pi revoke <shortId>` e espera o `notify` de
/// confirmação. O remote-pi não emite custom event no revoke (diferente do
/// pair) — sinaliza por `extension_ui_request`/`notify`:
/// - sucesso → `[remote-pi] Revoked: <name> …` (info)
/// - falha   → warning (`No peer matching`, `Revoke requires the relay`, …)
class RevokeGatewayImpl implements RevokeGateway {
  RevokeGatewayImpl(this._config);

  final PiSpawnConfig _config;

  @override
  Future<Result<void, RelayError>> revoke(
    String shortId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final rpc = EphemeralPiRpc(_config);
    final completer = Completer<Result<void, RelayError>>();

    void finish(Result<void, RelayError> result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    try {
      final command = jsonEncode(<String, dynamic>{
        'type': 'prompt',
        'message': '/remote-pi revoke $shortId',
      });
      await rpc.start(
        prompt: command,
        onLine: (json) => _onLine(json, finish),
        onExit: (code) => finish(
          Failure(
            RelayError('The process exited before confirming (code=$code).'),
          ),
        ),
      );
    } catch (error, stackTrace) {
      await rpc.dispose();
      return Failure(
        RelayError('Failed to revoke: $error', cause: error, stackTrace: stackTrace),
      );
    }

    final timer = Timer(
      timeout,
      () => finish(
        const Failure(
          RelayError(
            'Timed out revoking. Check the connection to the relay.',
          ),
        ),
      ),
    );

    final result = await completer.future;
    timer.cancel();
    await rpc.dispose();
    return result;
  }

  void _onLine(
    Map<String, dynamic> json,
    void Function(Result<void, RelayError>) finish,
  ) {
    if (json['type'] != 'extension_ui_request' || json['method'] != 'notify') {
      return;
    }
    final message = (json['message'] as String?) ?? '';
    if (message.contains('Revoked:')) {
      finish(const Success(null));
      return;
    }
    // Warnings do remote-pi durante o revoke = falha (peer inexistente, relay
    // off, shortid ambíguo, setup pendente…).
    if (json['notifyType'] == 'warning' && message.contains('remote-pi')) {
      finish(Failure(RelayError(_clean(message))));
    }
  }

  String _clean(String message) =>
      message.replaceFirst('[remote-pi] ', '').trim();
}
