import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/diagnostics/diagnostics_log.dart';
import '../data/diagnostics/performance_diagnostics.dart';
import 'login_shell.dart';

/// Saída de um comando rodado por [runShellCommand].
class ShellCommandResult {
  const ShellCommandResult({
    required this.code,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  final int code;
  final String stdout;
  final String stderr;

  /// `true` quando o processo foi morto por estourar o timeout (o [code] é
  /// 124, como no `timeout(1)` do coreutils).
  final bool timedOut;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'stdout': stdout,
    'stderr': stderr,
    'timedOut': timedOut,
  };
}

/// Roda [command] como uma linha de shell (pipes, aspas e globs valem) e
/// coleta stdout/stderr até o fim ou até [timeout], quando o processo é morto.
///
/// POSIX usa o **shell de login** do usuário com `-lc`, para que o PATH do
/// `.zprofile`/`.profile` valha (o app GUI nasce com PATH mínimo). Windows usa
/// `cmd /c`. Nunca lança: falha de spawn vira `code 127` com a mensagem em
/// `stderr`.
Future<ShellCommandResult> runShellCommand(
  String command, {
  String? cwd,
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final String exe;
  final List<String> args;
  if (Platform.isWindows) {
    exe = Platform.environment['ComSpec'] ?? 'cmd.exe';
    args = ['/d', '/s', '/c', command];
  } else {
    exe = loginShellOrFallback();
    args = ['-lc', command];
  }
  final Process proc;
  final spawnClock = Stopwatch()..start();
  try {
    proc = await Process.start(
      exe,
      args,
      workingDirectory: (cwd != null && cwd.isNotEmpty) ? cwd : null,
      environment: environment,
      includeParentEnvironment: true,
    );
  } on ProcessException catch (e) {
    DiagnosticsLog.instance.warn('spawn', 'shell spawn failed: $exe', error: e);
    PerformanceDiagnostics.instance.record(PerfMetric.spawn, {
      PerfField.durationUs: spawnClock.elapsedMicroseconds,
      PerfField.failed: 1,
    }, force: true);
    return ShellCommandResult(code: 127, stdout: '', stderr: e.message);
  }
  PerformanceDiagnostics.instance.record(PerfMetric.spawn, {
    PerfField.durationUs: spawnClock.elapsedMicroseconds,
    PerfField.failed: 0,
  });
  if (spawnClock.elapsed > const Duration(seconds: 2)) {
    DiagnosticsLog.instance.warn(
      'spawn',
      'slow shell spawn: ${spawnClock.elapsedMilliseconds} ms ($exe)',
    );
  }
  final out = StringBuffer();
  final err = StringBuffer();
  final outDone = proc.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .forEach(out.write);
  final errDone = proc.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .forEach(err.write);
  var timedOut = false;
  final code = await proc.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      proc.kill(ProcessSignal.sigkill);
      return 124;
    },
  );
  // Depois do kill os pipes fecham sozinhos; sem o kill, já fecharam.
  await Future.wait([
    outDone,
    errDone,
  ]).timeout(const Duration(seconds: 2), onTimeout: () => const <void>[]);
  return ShellCommandResult(
    code: code,
    stdout: out.toString(),
    stderr: err.toString(),
    timedOut: timedOut,
  );
}
