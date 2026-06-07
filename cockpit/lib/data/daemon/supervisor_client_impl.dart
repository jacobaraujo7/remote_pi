import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/domain/entities/daemon_info.dart';
import 'package:cockpit/domain/exceptions/daemon_error.dart';
import 'package:cockpit/domain/result.dart';

/// Implementação do [DaemonSupervisor].
///
/// **Controle** via o UDS `~/.pi/remote/supervisor.sock` (JSON-por-linha, 1 req
/// → 1 reply → close; espelha `pi-extension/src/daemon/client.ts`). **Criação**
/// via shell-out `remote-pi create` (faz o write do config local + registra +
/// sobe — o op `register` do UDS não escreve config).
class SupervisorClientImpl implements DaemonSupervisor {
  SupervisorClientImpl();

  Future<String>? _resolvedCli;

  String? get _home => Platform.environment['HOME'];

  String? _sockPath() {
    final home = _home;
    return home == null ? null : '$home/.pi/remote/supervisor.sock';
  }

  @override
  Future<bool> isOnline() async {
    final path = _sockPath();
    if (path == null || !await File(path).exists()) return false;
    try {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(seconds: 1));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Result<List<DaemonInfo>, DaemonError>> list() async {
    final result = await _call(<String, dynamic>{'op': 'list'});
    return result.map((data) {
      final raw = data['daemons'];
      if (raw is! List) return const <DaemonInfo>[];
      return raw.whereType<Map>().map(_toDaemon).toList(growable: false);
    });
  }

  @override
  Future<Result<void, DaemonError>> start(String id) => _unit('start', id: id);
  @override
  Future<Result<void, DaemonError>> stop(String id) => _unit('stop', id: id);
  @override
  Future<Result<void, DaemonError>> restart(String id) =>
      _unit('restart', id: id);

  @override
  Future<Result<void, DaemonError>> startAll() => _unit('start_all');
  @override
  Future<Result<void, DaemonError>> stopAll() => _unit('stop_all');
  @override
  Future<Result<void, DaemonError>> restartAll() => _unit('restart_all');

  @override
  Future<Result<void, DaemonError>> unregister(String id) =>
      _unit('unregister', id: id);

  @override
  Future<Result<void, DaemonError>> create(String cwd, {String? name}) async {
    try {
      final exe = await _cli();
      final args = <String>[
        'create',
        cwd,
        if (name != null && name.trim().isNotEmpty) ...['--name', name.trim()],
      ];
      final result = await Process.run(exe, args);
      if (result.exitCode != 0) {
        final err = (result.stderr as String? ?? '').trim();
        final out = (result.stdout as String? ?? '').trim();
        final msg = err.isNotEmpty ? err : (out.isNotEmpty ? out : 'Falha ao criar o daemon.');
        return Failure(DaemonError(msg));
      }
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        DaemonError('Falha ao criar o daemon: $error', cause: error, stackTrace: stackTrace),
      );
    }
  }

  // ---- UDS internals --------------------------------------------------------

  Future<Result<void, DaemonError>> _unit(String op, {String? id}) async {
    final result = await _call(<String, dynamic>{'op': op, 'id': ?id});
    return result.fold(
      (_) => const Success(null),
      (error) => Failure(error),
    );
  }

  /// Abre o UDS, manda uma linha JSON, lê uma linha de reply, fecha. Devolve o
  /// `data` em caso de `{ok:true}`; `{ok:false}` ou falha de socket viram erro.
  Future<Result<Map<String, dynamic>, DaemonError>> _call(
    Map<String, dynamic> request,
  ) async {
    final path = _sockPath();
    if (path == null) {
      return const Failure(DaemonError('HOME não encontrado no ambiente.'));
    }
    if (!await File(path).exists()) {
      return const Failure(
        DaemonError('Supervisor offline (socket ausente).'),
      );
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(seconds: 2));
      socket.write('${jsonEncode(request)}\n');
      await socket.flush();
      final line = await _readLine(socket).timeout(const Duration(seconds: 6));
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return const Failure(DaemonError('Resposta inválida do supervisor.'));
      }
      if (decoded['ok'] == true) {
        final data = decoded['data'];
        return Success(data is Map<String, dynamic> ? data : const {});
      }
      return Failure(
        DaemonError((decoded['error'] as String?) ?? 'Erro do supervisor.'),
      );
    } on SocketException {
      return const Failure(DaemonError('Não foi possível falar com o supervisor.'));
    } on TimeoutException {
      return const Failure(DaemonError('Tempo esgotado ao falar com o supervisor.'));
    } catch (error, stackTrace) {
      return Failure(
        DaemonError('Falha no supervisor: $error', cause: error, stackTrace: stackTrace),
      );
    } finally {
      socket?.destroy();
    }
  }

  Future<String> _readLine(Socket socket) {
    final completer = Completer<String>();
    final buffer = StringBuffer();
    late StreamSubscription<String> sub;
    sub = socket.cast<List<int>>().transform(utf8.decoder).listen(
      (chunk) {
        buffer.write(chunk);
        final text = buffer.toString();
        final nl = text.indexOf('\n');
        if (nl >= 0 && !completer.isCompleted) {
          completer.complete(text.substring(0, nl));
          unawaited(sub.cancel());
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          final text = buffer.toString();
          completer.complete(text.isEmpty ? '' : text);
        }
      },
    );
    return completer.future;
  }

  DaemonInfo _toDaemon(Map<dynamic, dynamic> json) {
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    return DaemonInfo(
      id: json['id']?.toString() ?? '',
      cwd: json['cwd']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      state: daemonStateFromWire(json['state'] as String?),
      pid: asInt(json['pid']),
      uptimeSeconds: asInt(json['uptime_s']),
      restartCount: asInt(json['restart_count']),
    );
  }

  // ---- CLI resolution -------------------------------------------------------

  Future<String> _cli() => _resolvedCli ??= _resolveCli();

  static Future<String> _resolveCli() async {
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
