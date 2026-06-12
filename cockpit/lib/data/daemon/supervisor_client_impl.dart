import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/data/daemon/win_named_pipe.dart';
import 'package:cockpit/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/domain/contracts/cron_gateway.dart';
import 'package:cockpit/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/domain/entities/cron_job.dart';
import 'package:cockpit/domain/entities/daemon_info.dart';
import 'package:cockpit/domain/exceptions/daemon_error.dart';
import 'package:cockpit/domain/result.dart';

/// Implementação do [DaemonSupervisor] + [CronGateway] (mesmo control-plane).
///
/// **Controle** via o UDS `~/.pi/remote/supervisor.sock` (JSON-por-linha, 1 req
/// → 1 reply → close; espelha `pi-extension/src/daemon/client.ts`). **Criação**
/// via shell-out `remote-pi create` (faz o write do config local + registra +
/// sobe — o op `register` do UDS não escreve config). Cron (plan/39) usa as ops
/// `cron_*` no mesmo socket.
class SupervisorClientImpl implements DaemonSupervisor, CronGateway {
  SupervisorClientImpl();

  Future<({String exe, List<String> prefixArgs})?>? _resolvedCli;

  // Windows não seta HOME; o equivalente é USERPROFILE.
  String? get _home =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  String? _sockPath() {
    final home = _home;
    return home == null ? null : '$home/.pi/remote/supervisor.sock';
  }

  @override
  Future<bool> isOnline() async {
    // Windows: o supervisor escuta num named pipe (não há arquivo de socket).
    // Uma transação `list` que volta != null prova que o pipe está aceitando.
    if (Platform.isWindows) {
      final reply = await winPipeTransact(
        supervisorPipeName(),
        '${jsonEncode(<String, dynamic>{'op': 'list'})}\n',
        timeout: const Duration(seconds: 1),
      );
      return reply != null;
    }
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
      final result = await _runCli(<String>[
        'create',
        cwd,
        if (name != null && name.trim().isNotEmpty) ...['--name', name.trim()],
      ]);
      if (result == null) {
        return const Failure(
          DaemonError('Could not find remote-pi (install the extension).'),
        );
      }
      if (result.exitCode != 0) {
        final err = (result.stderr as String? ?? '').trim();
        final out = (result.stdout as String? ?? '').trim();
        final msg = err.isNotEmpty ? err : (out.isNotEmpty ? out : 'Failed to create the daemon.');
        return Failure(DaemonError(msg));
      }
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        DaemonError('Failed to create the daemon: $error', cause: error, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void, DaemonError>> setAgentName(String cwd, String name) async {
    // O nome é a fonte da verdade no registry global `~/.pi/remote/daemons.json`
    // (`{cwd, name}`) — o supervisor o injeta no spawn via REMOTE_PI_DIRECT_CONFIG.
    // Não há config local por-pasta nem op/CLI de rename, então editamos o
    // registry direto; o `restart{id}` (no VM) respawna com o nome novo.
    final home = _home;
    if (home == null) {
      return const Failure(DaemonError('HOME not found in the environment.'));
    }
    try {
      final file = File('$home/.pi/remote/daemons.json');
      if (!await file.exists()) {
        return const Failure(
          DaemonError('Daemon registry not found.'),
        );
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['daemons'] is! List) {
        return const Failure(DaemonError('Invalid daemon registry.'));
      }
      var found = false;
      for (final item in decoded['daemons'] as List) {
        if (item is Map && item['cwd'] == cwd) {
          item['name'] = name;
          found = true;
          break;
        }
      }
      if (!found) {
        return const Failure(
          DaemonError('Daemon not found in the registry.'),
        );
      }
      // Mesmo formato do saveRegistry do pi-extension (2 espaços + LF final).
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
      );
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        DaemonError('Failed to rename the agent: $error', cause: error, stackTrace: stackTrace),
      );
    }
  }

  @override
  Future<Result<void, DaemonError>> restartSupervisor() async {
    // Delega ao CLI `remote-pi restart-supervisor` — ele cuida do detalhe por
    // plataforma (launchctl no macOS, systemctl no Linux, serviço no Windows).
    // Centraliza a lógica de SO no remote-pi em vez de duplicá-la aqui.
    try {
      final result = await _runCli(const ['restart-supervisor']);
      if (result == null) {
        return const Failure(
          DaemonError('Could not find remote-pi (install the extension).'),
        );
      }
      final out = (result.stdout as String? ?? '');
      final err = (result.stderr as String? ?? '');
      // O CLI imprime o help e sai 0 quando o comando não existe — não dá pra
      // confiar só no exitCode. Detecta o banner de uso e trata como indisponível.
      if ('$out\n$err'.contains('Usage: remote-pi')) {
        return const Failure(
          DaemonError(
            'This remote-pi does not have the `restart-supervisor` command yet. '
            'Update remote-pi.',
          ),
        );
      }
      if (result.exitCode != 0) {
        final e = err.trim();
        final o = out.trim();
        final msg = e.isNotEmpty
            ? e
            : (o.isNotEmpty ? o : 'Failed to restart the supervisor.');
        return Failure(DaemonError(msg));
      }
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        DaemonError('Failed to restart the supervisor: $error', cause: error, stackTrace: stackTrace),
      );
    }
  }

  // ---- cron (plan/39) -------------------------------------------------------

  @override
  Future<Result<List<CronJob>, DaemonError>> listCron() async {
    final result = await _call(<String, dynamic>{'op': 'cron_list'});
    return result.map((data) {
      final raw = data['jobs'];
      if (raw is! List) return const <CronJob>[];
      return raw.whereType<Map>().map(_toCronJob).toList(growable: false);
    });
  }

  @override
  Future<Result<void, DaemonError>> addCron({
    required String daemonId,
    required String schedule,
    required String prompt,
    String? tz,
    bool skipIfBusy = true,
    bool wake = false,
    bool catchup = false,
  }) => _voidCall(<String, dynamic>{
    'op': 'cron_add',
    'daemon_id': daemonId,
    'schedule': schedule,
    'prompt': prompt,
    'tz': ?tz,
    'skip_if_busy': skipIfBusy,
    'wake': wake,
    'catchup': catchup,
  });

  @override
  Future<Result<void, DaemonError>> removeCron(String jobId) =>
      _voidCall(<String, dynamic>{'op': 'cron_remove', 'job_id': jobId});

  @override
  Future<Result<void, DaemonError>> setCronEnabled(String jobId, bool enabled) =>
      _voidCall(<String, dynamic>{
        'op': 'cron_enable',
        'job_id': jobId,
        'enabled': enabled,
      });

  @override
  Future<Result<String, DaemonError>> runCron(String jobId) async {
    final result = await _call(<String, dynamic>{
      'op': 'cron_run',
      'job_id': jobId,
    });
    return result.map((data) => data['result']?.toString() ?? 'unknown');
  }

  @override
  Future<Result<List<CronLogEntry>, DaemonError>> cronLog({
    String? jobId,
    int? tail,
  }) async {
    final result = await _call(<String, dynamic>{
      'op': 'cron_log',
      'job_id': ?jobId,
      'tail': ?tail,
    });
    return result.map((data) {
      final raw = data['entries'];
      if (raw is! List) return const <CronLogEntry>[];
      return raw.whereType<Map>().map(_toCronLog).toList(growable: false);
    });
  }

  CronJob _toCronJob(Map<dynamic, dynamic> j) {
    bool b(Object? v, bool fallback) => v is bool ? v : fallback;
    return CronJob(
      id: j['id']?.toString() ?? '',
      daemonId: j['daemon_id']?.toString() ?? '',
      schedule: j['schedule']?.toString() ?? '',
      prompt: j['prompt']?.toString() ?? '',
      enabled: b(j['enabled'], true),
      skipIfBusy: b(j['skip_if_busy'], true),
      wake: b(j['wake'], false),
      catchup: b(j['catchup'], false),
      tz: j['tz']?.toString(),
      createdAt: j['created_at']?.toString(),
      lastRun: j['last_run']?.toString(),
      lastStatus: j['last_status']?.toString(),
      nextRun: j['next_run']?.toString(),
    );
  }

  CronLogEntry _toCronLog(Map<dynamic, dynamic> e) {
    final ts = e['ts'];
    return CronLogEntry(
      tsMs: ts is num ? ts.toInt() : 0,
      jobId: e['job_id']?.toString() ?? '',
      daemonId: e['daemon_id']?.toString() ?? '',
      schedule: e['schedule']?.toString() ?? '',
      fired: e['fired'] == true,
      result: cronResultFromWire(e['result'] as String?),
      promptPreview: e['prompt_preview']?.toString() ?? '',
    );
  }

  // ---- UDS internals --------------------------------------------------------

  /// `_call` que descarta o `data` — pra ops cujo sucesso é só `{ok:true}`.
  Future<Result<void, DaemonError>> _voidCall(Map<String, dynamic> req) async {
    final result = await _call(req);
    return result.fold((_) => const Success(null), (error) => Failure(error));
  }

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
    try {
      final line = await _transact('${jsonEncode(request)}\n');
      if (line == null) {
        return const Failure(
          DaemonError('Could not reach the supervisor.'),
        );
      }
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return const Failure(DaemonError('Invalid response from the supervisor.'));
      }
      if (decoded['ok'] == true) {
        final data = decoded['data'];
        return Success(data is Map<String, dynamic> ? data : const {});
      }
      return Failure(
        DaemonError((decoded['error'] as String?) ?? 'Supervisor error.'),
      );
    } on TimeoutException {
      return const Failure(DaemonError('Timed out talking to the supervisor.'));
    } catch (error, stackTrace) {
      return Failure(
        DaemonError('Supervisor failure: $error', cause: error, stackTrace: stackTrace),
      );
    }
  }

  /// Transação 1-req → 1-reply com o supervisor. Windows usa named pipe; POSIX
  /// usa o UDS. Devolve a linha de resposta (sem `\n`) ou `null` se offline.
  Future<String?> _transact(String requestLine) async {
    if (Platform.isWindows) {
      return winPipeTransact(supervisorPipeName(), requestLine);
    }
    final path = _sockPath();
    if (path == null || !await File(path).exists()) return null;
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(seconds: 2));
      socket.write(requestLine);
      await socket.flush();
      return await _readLine(socket).timeout(const Duration(seconds: 6));
    } on SocketException {
      return null;
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

  /// Como invocar o `remote-pi`: binário no POSIX, `node <index.js>` no Windows.
  Future<({String exe, List<String> prefixArgs})?> _cli() =>
      _resolvedCli ??= resolveRemotePiCommand();

  /// Roda o `remote-pi <args>` resolvido por plataforma, com o `node` na PATH
  /// (shim usa `#!/usr/bin/env node`) e `runInShell` no Windows.
  Future<ProcessResult?> _runCli(List<String> args) async {
    final cmd = await _cli();
    if (cmd == null) return null;
    return Process.run(
      cmd.exe,
      [...cmd.prefixArgs, ...args],
      runInShell: Platform.isWindows,
      environment: await envWithNodeOnPath(),
    );
  }
}
