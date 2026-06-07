import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cockpit/config/env.dart';
import 'package:cockpit/data/rpc/jsonl_line_splitter.dart';

/// Sessão **efêmera e dedicada** de `pi --mode rpc --no-session` para comandos
/// pontuais do remote-pi (pareamento, revoke). Roda numa pasta temporária única
/// (evita colisão de cwd-lock) com `REMOTE_PI_DIRECT_CONFIG` de pareamento — o
/// que faz `localConfigExists` virar true e o `/remote-pi <cmd>` auto-ligar o
/// relay. Carrega a extensão remote-pi (SEM `--no-extensions`).
///
/// Não interpreta o protocolo: entrega cada objeto JSON do stdout via [onLine];
/// quem usa decide o que é resposta/evento. [dispose] mata o processo (sem
/// órfão) e remove a pasta temp — idempotente.
class EphemeralPiRpc {
  EphemeralPiRpc(this._config);

  final PiSpawnConfig _config;

  Process? _process;
  Directory? _tempDir;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _disposed = false;

  /// Sobe o processo e manda [prompt] (uma linha JSON, ex.: o comando `prompt`).
  /// [onLine] recebe cada objeto JSON do stdout; [onExit] (opcional) o exit
  /// code. Lança em falha de spawn.
  Future<void> start({
    required String prompt,
    required void Function(Map<String, dynamic> json) onLine,
    void Function(int code)? onExit,
  }) async {
    final dir = await Directory.systemTemp.createTemp('remote-pi-rpc-');
    _tempDir = dir;

    final env = <String, String>{
      ...Platform.environment,
      'REMOTE_PI_DIRECT_CONFIG': jsonEncode(<String, dynamic>{
        'agent_name': _randomName(),
        'workspace': 'pareamento',
      }),
    };

    final process = await Process.start(
      _config.executable,
      _args(),
      workingDirectory: dir.path,
      environment: env,
    );
    _process = process;

    _stdoutSub = process.stdout.transform(const JsonlLineSplitter()).listen(
      (line) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic>) onLine(decoded);
        } catch (_) {
          // Linha não-JSON — ignora (não derruba o comando).
        }
      },
      onError: (_) {},
    );
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {}, onError: (_) {});

    if (onExit != null) unawaited(process.exitCode.then(onExit));

    process.stdin.write('$prompt\n');
    await process.stdin.flush();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        await process.stdin.close(); // shutdown gracioso (code 0)
      } catch (_) {}
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigterm);
      }
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    final dir = _tempDir;
    _tempDir = null;
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// `--mode rpc --no-session` (sem persistir sessão), SEM `--no-extensions`
  /// (precisamos da extensão remote-pi pros slash commands).
  List<String> _args() => <String>[
    '--mode', 'rpc',
    '--no-session',
    if (_config.provider != null && _config.provider!.isNotEmpty) ...[
      '--provider',
      _config.provider!,
    ],
    if (_config.model != null && _config.model!.isNotEmpty) ...[
      '--model',
      _config.model!,
    ],
  ];

  static String _randomName() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    final suffix = List<String>.generate(
      6,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return 'pareamento-$suffix';
  }
}
