import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:flutter/foundation.dart';

/// [TerminalStatusServer] híbrido por plataforma:
/// - **POSIX**: socket Unix em `~/.cockpit/status.sock` (permissão do arquivo
///   já protege contra outros usuários).
/// - **Windows**: TCP loopback `127.0.0.1:<porta-efêmera>` + **token**
///   (loopback é acessível por qualquer processo local; o token valida a
///   origem). O Dart não suporta socket Unix no Windows.
///
/// Cada conexão do `cockpit-hook` manda **uma linha JSON** (`{paneId, st, sid,
/// tx, tok?}`) e fecha.
class TerminalStatusServerImpl implements TerminalStatusServer {
  TerminalStatusServerImpl();

  ServerSocket? _server;
  void Function(ClaudeStatusUpdate update)? _onUpdate;
  Future<CockpitCommandResult> Function(CockpitCommand command)? _onCommand;
  String? _token; // só no Windows/TCP

  String get _socketPath {
    final home = remotePiHome() ?? Directory.systemTemp.path;
    return '$home/.cockpit/status.sock';
  }

  @override
  Map<String, String> get hookEnv {
    final server = _server;
    if (server == null) return const <String, String>{};
    if (Platform.isWindows) {
      final env = <String, String>{'COCKPIT_STATUS_PORT': '${server.port}'};
      final token = _token;
      if (token != null) env['COCKPIT_STATUS_TOKEN'] = token;
      return env;
    }
    return <String, String>{'COCKPIT_STATUS_SOCK': _socketPath};
  }

  @override
  Future<void> start(
    void Function(ClaudeStatusUpdate update) onUpdate, {
    Future<CockpitCommandResult> Function(CockpitCommand command)? onCommand,
  }) async {
    if (_server != null) return;
    _onUpdate = onUpdate;
    _onCommand = onCommand;
    try {
      if (Platform.isWindows) {
        _token = _randomToken();
        _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      } else {
        final file = File(_socketPath);
        await file.parent.create(recursive: true);
        // Remove socket órfão do ciclo anterior (bind falha se já existe).
        if (await file.exists()) await file.delete();
        final address = InternetAddress(
          _socketPath,
          type: InternetAddressType.unix,
        );
        _server = await ServerSocket.bind(address, 0);
      }
      _server!.listen(_handleConnection, onError: (_) {});
    } catch (e) {
      if (kDebugMode) debugPrint('[status-server] bind falhou: $e');
    }
  }

  String _randomToken() {
    final r = Random.secure();
    return List<int>.generate(
      16,
      (_) => r.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _handleConnection(Socket socket) {
    // Despacha na PRIMEIRA linha (`\n`), não no fim da conexão: o `cockpit-hook`
    // (status) fecha logo após enviar, mas a CLI (`type:"cmd"`) mantém o socket
    // aberto esperando a resposta — esperar `onDone` deadlockaria o
    // request/response. Status → resposta null (só destrói); comando → escreve
    // uma linha de resposta e destrói.
    late StreamSubscription<String> sub;
    var handled = false;
    sub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) async {
            if (handled) return;
            handled = true;
            await sub.cancel();
            String? response;
            try {
              response = await _dispatch(line);
            } catch (_) {
              response = null;
            }
            if (response != null) {
              try {
                socket.add(utf8.encode('$response\n'));
                await socket.flush();
              } catch (_) {
                /* peer sumiu: ignora */
              }
            }
            socket.destroy();
          },
          onError: (_) => socket.destroy(),
          onDone: () {
            if (!handled) socket.destroy();
          },
          cancelOnError: true,
        );
  }

  /// Processa uma linha JSON. Devolve a linha de resposta a escrever de volta
  /// (comandos da CLI), ou `null` quando não há resposta (status do hook).
  Future<String?> _dispatch(String raw) async {
    final line = raw.trim();
    if (line.isEmpty) return null;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return null;
      final isCmd = decoded['type'] == 'cmd';
      // No Windows/TCP, exige o token (anti-spoof do loopback).
      if (_token != null && decoded['tok'] != _token) {
        return isCmd
            ? jsonEncode(
                const CockpitCommandResult.fail('token inválido').toJson(),
              )
            : null;
      }
      if (isCmd) return _dispatchCommand(decoded);
      // Caminho de status (default / `type` ausente): fire-and-forget.
      final paneId = (decoded['paneId'] ?? '').toString();
      final status = (decoded['st'] ?? '').toString();
      if (paneId.isEmpty || status.isEmpty) return null;
      final sid = (decoded['sid'] ?? '').toString();
      final tx = (decoded['tx'] ?? '').toString();
      _onUpdate?.call(
        ClaudeStatusUpdate(
          paneId: paneId,
          status: status,
          sessionId: sid.isEmpty ? null : sid,
          transcriptPath: tx.isEmpty ? null : tx,
        ),
      );
      return null;
    } catch (_) {
      // linha malformada: sem resposta (a CLI reporta timeout/erro de leitura).
      return null;
    }
  }

  Future<String?> _dispatchCommand(Map<dynamic, dynamic> decoded) async {
    final handler = _onCommand;
    if (handler == null) {
      return jsonEncode(
        const CockpitCommandResult.fail('comandos indisponíveis').toJson(),
      );
    }
    final tabRaw = (decoded['tabId'] ?? '').toString();
    final argsRaw = decoded['args'];
    final command = CockpitCommand(
      cmd: (decoded['cmd'] ?? '').toString(),
      tabId: tabRaw.isEmpty ? null : tabRaw,
      args: argsRaw is Map
          ? Map<String, dynamic>.from(argsRaw)
          : const <String, dynamic>{},
    );
    final result = await handler(command);
    return jsonEncode(result.toJson());
  }

  @override
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _onUpdate = null;
    _token = null;
    if (!Platform.isWindows) {
      try {
        final file = File(_socketPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
