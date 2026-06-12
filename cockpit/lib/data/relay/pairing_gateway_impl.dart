import 'dart:async';
import 'dart:convert';

import 'package:cockpit/config/env.dart';
import 'package:cockpit/data/relay/ephemeral_pi_rpc.dart';
import 'package:cockpit/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/domain/entities/pair_event.dart';

/// Implementação do [PairingGateway] sobre uma sessão [EphemeralPiRpc].
///
/// Dispara `/remote-pi pair` e traduz as mensagens `role: "custom"` do stdout
/// (`remote-pi:pair-code` / `remote-pi:paired`) em [PairEvent]. Cada pair-code
/// chega como DOIS eventos (`message_start` + `message_end`) com payload igual,
/// então deduplicamos por assinatura.
class PairingGatewayImpl implements PairingGateway {
  PairingGatewayImpl(PiSpawnConfig config) : _rpc = EphemeralPiRpc(config);

  final EphemeralPiRpc _rpc;
  final StreamController<PairEvent> _events =
      StreamController<PairEvent>.broadcast();

  final Set<String> _seen = <String>{};
  bool _started = false;
  bool _gotCode = false;
  bool _closed = false;
  Timer? _bootTimeout;

  @override
  Stream<PairEvent> get events => _events.stream;

  @override
  Future<void> start({Duration ttl = const Duration(seconds: 120)}) async {
    if (_started) return;
    _started = true;
    try {
      final command = jsonEncode(<String, dynamic>{
        'type': 'prompt',
        'message': '/remote-pi pair --ttl ${ttl.inSeconds}',
      });
      await _rpc.start(prompt: command, onLine: _onLine, onExit: _onExit);

      // O `/remote-pi pair` sobe o relay sozinho — dá uns segundos pra conexão
      // antes de desistir (sem pair-code = extensão ausente ou relay off).
      _bootTimeout = Timer(const Duration(seconds: 30), () {
        if (!_gotCode) {
          _emit(
            const PairFailed(
              'Could not start pairing. Check that the remote-pi extension is '
              'installed and that a relay is configured.',
            ),
          );
        }
      });
    } catch (error) {
      _emit(PairFailed('Failed to start pairing: $error'));
      await _cleanup();
    }
  }

  @override
  Future<void> cancel() => _cleanup();

  void _onLine(Map<String, dynamic> json) {
    final type = json['type'];
    if (type != 'message_start' && type != 'message_end') return;
    final message = json['message'];
    if (message is! Map || message['role'] != 'custom') return;
    final details = message['details'];
    _handleCustom(
      message['customType'] as String?,
      details is Map ? details : const <dynamic, dynamic>{},
    );
  }

  void _handleCustom(String? customType, Map<dynamic, dynamic> details) {
    if (customType == null) return;
    final signature = '$customType|${jsonEncode(details)}';
    if (!_seen.add(signature)) return; // dedup message_start/message_end

    switch (customType) {
      case 'remote-pi:pair-code':
        final uri = details['uri'];
        if (uri is! String || uri.isEmpty) return;
        _gotCode = true;
        _bootTimeout?.cancel();
        _emit(
          PairCodeReady(
            uri: uri,
            token: details['token']?.toString(),
            expiresAt: details['expiresAt']?.toString(),
            roomId: details['roomId']?.toString(),
            name: details['name']?.toString(),
          ),
        );
      case 'remote-pi:paired':
        _emit(PairDevicePaired(name: details['name']?.toString()));
    }
  }

  void _onExit(int code) {
    if (!_gotCode && !_closed) {
      _emit(PairFailed('The pairing process exited (code=$code).'));
    }
    unawaited(_cleanup());
  }

  Future<void> _cleanup() async {
    if (_closed) return;
    _closed = true;
    _bootTimeout?.cancel();
    await _rpc.dispose();
    if (!_events.isClosed) await _events.close();
  }

  void _emit(PairEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
