import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../data/diagnostics/diagnostics_log.dart';
import '../data/diagnostics/performance_diagnostics.dart';
import '../domain/entities/terminal_profile.dart';
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

/// Executável + argumentos que rodam UMA linha de comando num shell.
class ShellInvocation {
  const ShellInvocation(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

/// Como invocar [command] no shell do [profile] — o **perfil de terminal
/// padrão** das configurações, pra o `exec` de um `.panel`/CLI rodar no mesmo
/// shell que o `+` abre. Sem perfil, o default da plataforma (Windows: `cmd`;
/// POSIX: login shell).
///
/// O perfil é classificado pelo id (ou pelo nome do executável, pra perfis
/// `custom:`), porque cada família recebe uma linha de jeito diferente:
/// - **cmd**: `/d /s /c <linha>`.
/// - **PowerShell** (5.1 ou 7): `-EncodedCommand` (base64 UTF-16LE), que
///   dispensa citar a linha e vem com preâmbulo que força saída em UTF-8 —
///   a mesma decisão D1 do caminho remoto (`windowsPowerShellCommand`).
///   `-NonInteractive` evita prompt pendurado; `-ExecutionPolicy Bypass` deixa
///   o `$PROFILE` carregar numa máquina com política `Restricted` (o default
///   do Windows cliente), em vez de cuspir erro no stderr.
/// - **WSL**: `-d <distro> -- sh -lc <linha>`.
/// - **Login shell / outros POSIX**: `-lc <linha>`.
ShellInvocation shellInvocationFor(
  String command, {
  TerminalProfile? profile,
  bool? isWindows,
  Map<String, String>? environment,
}) {
  final windows = isWindows ?? Platform.isWindows;
  final env = environment ?? Platform.environment;
  // Sem perfil, ou perfil "o host decide" (executável vazio, o default dos
  // workspaces remotos): o shell da plataforma.
  if (profile == null || profile.executable.isEmpty) {
    return windows
        ? ShellInvocation(env['ComSpec'] ?? 'cmd.exe', [
            '/d',
            '/s',
            '/c',
            command,
          ])
        : ShellInvocation(loginShellOrFallback(), ['-lc', command]);
  }
  final exe = profile.executable;
  switch (_shellFamilyOf(profile)) {
    case _ShellFamily.cmd:
      return ShellInvocation(exe, ['/d', '/s', '/c', command]);
    case _ShellFamily.powershell:
      return ShellInvocation(exe, [
        '-NoLogo',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        _encodeUtf16Le(_powerShellUtf8Preamble + command),
      ]);
    case _ShellFamily.wsl:
      return ShellInvocation(exe, [
        ...profile.args,
        '--',
        'sh',
        '-lc',
        command,
      ]);
    case _ShellFamily.posix:
      return ShellInvocation(exe, ['-lc', command]);
  }
}

enum _ShellFamily { cmd, powershell, wsl, posix }

_ShellFamily _shellFamilyOf(TerminalProfile profile) {
  if (profile.id == TerminalProfile.cmdId) return _ShellFamily.cmd;
  if (profile.id == TerminalProfile.powershellId ||
      profile.id == TerminalProfile.pwshId) {
    return _ShellFamily.powershell;
  }
  if (profile.wslDistro != null) return _ShellFamily.wsl;
  if (profile.id == TerminalProfile.loginShellId) return _ShellFamily.posix;
  // `custom:<uuid>` — decide pelo nome do executável.
  final name = profile.executable
      .replaceAll('\\', '/')
      .split('/')
      .last
      .toLowerCase()
      .replaceFirst(RegExp(r'\.exe$'), '');
  return switch (name) {
    'cmd' => _ShellFamily.cmd,
    'powershell' || 'pwsh' => _ShellFamily.powershell,
    'wsl' => _ShellFamily.wsl,
    _ => _ShellFamily.posix,
  };
}

/// Sem isso o PowerShell escreve na codepage local (CP850/CP1252) e o decode
/// UTF-8 de [runShellCommand] estraga acentos — "n�o é reconhecido".
const _powerShellUtf8Preamble =
    '[Console]::OutputEncoding = [Text.UTF8Encoding]::new()\n';

/// `-EncodedCommand` exige base64 de **UTF-16LE**, não de UTF-8.
String _encodeUtf16Le(String script) {
  final units = script.codeUnits;
  final bytes = Uint8List(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    bytes[i * 2] = units[i] & 0xFF;
    bytes[i * 2 + 1] = (units[i] >> 8) & 0xFF;
  }
  return base64.encode(bytes);
}

/// Roda [command] como uma linha de shell (pipes, aspas e globs valem) e
/// coleta stdout/stderr até o fim ou até [timeout], quando o processo é morto.
///
/// O shell é o do [profile] (ver [shellInvocationFor]); sem perfil, POSIX usa
/// o **shell de login** do usuário com `-lc`, para que o PATH do
/// `.zprofile`/`.profile` valha (o app GUI nasce com PATH mínimo), e Windows
/// usa `cmd /c`. Nunca lança: falha de spawn vira `code 127` com a mensagem em
/// `stderr`.
Future<ShellCommandResult> runShellCommand(
  String command, {
  String? cwd,
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 60),
  TerminalProfile? profile,
}) async {
  final invocation = shellInvocationFor(command, profile: profile);
  final exe = invocation.executable;
  final args = invocation.arguments;
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
