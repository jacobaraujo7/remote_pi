import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/domain/contracts/relay_gateway.dart';
import 'package:cockpit/domain/entities/paired_device.dart';
import 'package:cockpit/domain/exceptions/relay_error.dart';
import 'package:cockpit/domain/result.dart';

/// Implementação via **shell-out** do `remote-pi` + leitura do config global
/// `~/.pi/remote/config.json`.
///
/// macOS não herda o PATH do shell, então o binário é resolvido em caminhos
/// conhecidos (mesmo padrão do `pi` em `config/env.dart`). A resolução é
/// memoizada — só faz os `exists()` uma vez.
class RelayGatewayImpl implements RelayGateway {
  RelayGatewayImpl();

  Future<String>? _resolvedExe;

  String? get _home => Platform.environment['HOME'];

  @override
  Future<Result<String?, RelayError>> currentRelay() async {
    final home = _home;
    if (home == null) {
      return const Failure(RelayError('HOME não encontrado no ambiente.'));
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
        RelayError('Falha ao ler o relay configurado.', cause: e, stackTrace: s),
      );
    }
  }

  @override
  Future<Result<void, RelayError>> setRelay(String url) =>
      _run(<String>['set-relay', url], 'Falha ao definir o relay.');

  @override
  Future<Result<List<PairedDevice>, RelayError>> listDevices() async {
    final result = await _capture(
      <String>['devices'],
      'Falha ao listar os aparelhos pareados.',
    );
    return result.map(_parseDevices);
  }

  @override
  Future<Result<void, RelayError>> checkHealth(String url) async {
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(base);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty) {
      return const Failure(
        RelayError('URL inválida — use http:// ou https://.'),
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
      return Failure(RelayError('O relay respondeu HTTP ${response.statusCode}.'));
    } on TimeoutException {
      return const Failure(RelayError('Tempo esgotado ao contatar o relay.'));
    } on SocketException {
      return const Failure(
        RelayError('Não foi possível conectar ao relay (host/porta).'),
      );
    } on HandshakeException {
      return const Failure(RelayError('Falha de TLS ao contatar o relay.'));
    } catch (error) {
      return Failure(RelayError('Falha ao contatar o relay: $error'));
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
    return captured.fold(
      (_) => const Success(null),
      (error) => Failure(error),
    );
  }

  /// Roda o comando e devolve o stdout (trim) em caso de sucesso. Falha de spawn
  /// ou `exitCode != 0` viram [RelayError] com a mensagem do stderr, se houver.
  Future<Result<String, RelayError>> _capture(
    List<String> args,
    String onError,
  ) async {
    try {
      final exe = await _exe();
      final result = await Process.run(exe, args);
      if (result.exitCode != 0) {
        final err = (result.stderr as String? ?? '').trim();
        return Failure(RelayError(err.isEmpty ? onError : '$onError\n$err'));
      }
      return Success((result.stdout as String? ?? '').trim());
    } catch (e, s) {
      return Failure(RelayError(onError, cause: e, stackTrace: s));
    }
  }

  /// Parseia a saída do `remote-pi devices`. Formato por linha:
  /// `• <shortId> — <label>` (bullet opcional; separador em-dash ou hífen).
  List<PairedDevice> _parseDevices(String stdout) {
    final devices = <PairedDevice>[];
    for (final raw in const LineSplitter().convert(stdout)) {
      var line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('•')) line = line.substring(1).trim();
      final sep = line.contains(' — ')
          ? ' — '
          : (line.contains(' - ') ? ' - ' : null);
      if (sep == null) continue;
      final idx = line.indexOf(sep);
      final shortId = line.substring(0, idx).trim();
      if (shortId.isEmpty) continue;
      final label = line.substring(idx + sep.length).trim();
      devices.add(PairedDevice(shortId: shortId, label: label));
    }
    return devices;
  }

  Future<String> _exe() => _resolvedExe ??= _resolveExecutable();

  static Future<String> _resolveExecutable() async {
    const candidates = <String>[
      '/opt/homebrew/bin/remote-pi',
      '/usr/local/bin/remote-pi',
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    final home = Platform.environment['HOME'];
    if (home != null) {
      final local = '$home/.local/bin/remote-pi';
      if (await File(local).exists()) return local;
    }
    return 'remote-pi';
  }
}
