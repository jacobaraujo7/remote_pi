import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/settings/domain/contracts/relay_gateway.dart';
import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:cockpit/app/core/domain/exceptions/relay_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Implementação via **shell-out** do `remote-pi` + leitura do config global
/// `~/.pi/remote/config.json`.
///
/// O `remote-pi` é resolvido via [resolveRemotePiCommand]: binário no PATH/
/// prefixos conhecidos no POSIX; `node <index.js>` no Windows (onde não está no
/// PATH). A resolução é memoizada — só faz os `exists()` uma vez.
class RelayGatewayImpl implements RelayGateway {
  RelayGatewayImpl();

  Future<({String exe, List<String> prefixArgs})?>? _resolvedCmd;

  // Windows não seta HOME; o equivalente é USERPROFILE.
  String? get _home => remotePiHome();

  @override
  Future<Result<String?, RelayError>> currentRelay() async {
    final home = _home;
    if (home == null) {
      return const Failure(RelayError('HOME not found in the environment.'));
    }
    try {
      final file = File('$home/.pi/remote/config.json');
      if (!await file.exists()) return const Success(null);
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return const Success(null);
      final relay = json['relay'];
      return Success(relay is String && relay.isNotEmpty ? relay : null);
    } catch (e, s) {
      return Failure(
        RelayError(
          'Failed to read the configured relay.',
          cause: e,
          stackTrace: s,
        ),
      );
    }
  }

  @override
  Future<Result<void, RelayError>> setRelay(String url) =>
      _run(<String>['set-relay', url], 'Failed to set the relay.');

  @override
  Future<Result<List<PairedDevice>, RelayError>> listDevices() async {
    // Lê os pares direto de `~/.pi/remote/peers.json` (mesma fonte do
    // `/remote-pi`). Não há subcomando `remote-pi devices` na CLI, e ler o
    // arquivo funciona igual em macOS/Linux/Windows.
    final home = _home;
    if (home == null) {
      return const Failure(RelayError('HOME not found in the environment.'));
    }
    try {
      final file = File('$home/.pi/remote/peers.json');
      if (!await file.exists()) return const Success(<PairedDevice>[]);
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return const Success(<PairedDevice>[]);
      final peers = json['peers'];
      if (peers is! List) return const Success(<PairedDevice>[]);

      final devices = <PairedDevice>[];
      for (final p in peers.whereType<Map>()) {
        final epk = p['remote_epk'];
        if (epk is! String || epk.isEmpty) continue;
        final name = p['name'];
        // shortId = remote_epk (o que `/remote-pi revoke <epk>` aceita);
        // label = nome legível do pareamento (ex.: "iPhone").
        devices.add(
          PairedDevice(
            shortId: epk,
            label: name is String && name.isNotEmpty ? name : epk,
          ),
        );
      }
      return Success(devices);
    } catch (e, s) {
      return Failure(
        RelayError('Failed to list paired devices.', cause: e, stackTrace: s),
      );
    }
  }

  @override
  Future<Result<void, RelayError>> checkHealth(String url) async {
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(base);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty) {
      return const Failure(
        RelayError('Invalid URL — use http:// or https://.'),
      );
    }

    const timeout = Duration(seconds: 8);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('$base/health'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      if (response.statusCode == 200) return const Success(null);
      return Failure(
        RelayError('The relay responded HTTP ${response.statusCode}.'),
      );
    } on TimeoutException {
      return const Failure(RelayError('Timed out contacting the relay.'));
    } on SocketException {
      return const Failure(
        RelayError('Could not connect to the relay (host/port).'),
      );
    } on HandshakeException {
      return const Failure(RelayError('TLS failure contacting the relay.'));
    } catch (error) {
      return Failure(RelayError('Failed to contact the relay: $error'));
    } finally {
      client.close(force: true);
    }
  }

  // ---- internals ------------------------------------------------------------

  /// Roda o comando e descarta a saída (só interessa o `exitCode`).
  Future<Result<void, RelayError>> _run(
    List<String> args,
    String onError,
  ) async {
    final captured = await _capture(args, onError);
    return captured.fold((_) => const Success(null), (error) => Failure(error));
  }

  /// Roda o comando e devolve o stdout (trim) em caso de sucesso. Falha de spawn
  /// ou `exitCode != 0` viram [RelayError] com a mensagem do stderr, se houver.
  Future<Result<String, RelayError>> _capture(
    List<String> args,
    String onError,
  ) async {
    try {
      final cmd = await _cmd();
      if (cmd == null) {
        return Failure(
          RelayError(
            '$onError\nCould not find remote-pi (install the extension).',
          ),
        );
      }
      final result = await Process.run(
        cmd.exe,
        [...cmd.prefixArgs, ...args],
        runInShell: Platform.isWindows,
        environment: await envWithNodeOnPath(),
      );
      if (result.exitCode != 0) {
        final err = (result.stderr as String? ?? '').trim();
        return Failure(RelayError(err.isEmpty ? onError : '$onError\n$err'));
      }
      return Success((result.stdout as String? ?? '').trim());
    } catch (e, s) {
      return Failure(RelayError(onError, cause: e, stackTrace: s));
    }
  }

  Future<({String exe, List<String> prefixArgs})?> _cmd() =>
      _resolvedCmd ??= resolveRemotePiCommand();
}
