import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_profile_resolver.dart';
import 'package:cockpit/app/cockpit/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/executable_resolver.dart';
import 'package:cockpit/app/core/utils/login_shell.dart';

/// Roda um processo devolvendo o stdout **cru** (bytes) — ponto de injeção pros
/// testes. Bytes, não String: a saída do `wsl.exe -l -q` é UTF-16LE e deixar o
/// `Process.run` decodificar como UTF-8 destrói a lista (ver [_decodeWslList]).
typedef RawProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Descoberta de perfis por plataforma (plano 50).
///
/// - **Windows**: PowerShell (`powershell.exe`, ou `pwsh.exe` se aquele não
///   existir), cmd (`%ComSpec%`) e uma entrada por distro do `wsl.exe -l -q`.
/// - **POSIX**: o login shell real do usuário (reusa `resolveLoginShell()` da
///   issue #42) com `-l`.
///
/// Best-effort: qualquer falha (executável ausente, timeout, saída ilegível)
/// vira "esse perfil não existe", nunca exceção.
class TerminalProfileResolverImpl implements TerminalProfileResolver {
  TerminalProfileResolverImpl({
    Map<String, String>? environment,
    RawProcessRunner? runProcess,
    String? operatingSystem,
    bool? isWindowsArm,
    Future<String> Function()? loginShell,
    Future<bool> Function(String)? executableExists,
  }) : _env = environment ?? Platform.environment,
       _run = runProcess ?? _defaultRun,
       _os = operatingSystem ?? Platform.operatingSystem,
       // Arch do build (`... on "windows_arm64"`) — fonte confiável, ao
       // contrário de PROCESSOR_ARCHITECTURE (reporta emulação WOW).
       _isWindowsArm =
           isWindowsArm ?? Platform.version.toLowerCase().contains('arm'),
       _loginShell = loginShell ?? resolveLoginShell,
       _exists = executableExists ?? isExecutableAvailable;

  final Map<String, String> _env;
  final RawProcessRunner _run;
  final String _os;
  final bool _isWindowsArm;
  final Future<String> Function() _loginShell;
  final Future<bool> Function(String) _exists;

  static const _timeout = Duration(seconds: 4);

  List<TerminalProfile>? _cache;
  Future<List<TerminalProfile>>? _inFlight;

  static Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
      Process.run(exe, args, stdoutEncoding: null, stderrEncoding: null);

  bool get _isWindows => _os == 'windows';

  @override
  List<TerminalProfile> get cachedProfiles =>
      List<TerminalProfile>.unmodifiable(_cache ?? const <TerminalProfile>[]);

  @override
  TerminalProfile? profileById(String id) {
    for (final p in _cache ?? const <TerminalProfile>[]) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<TerminalProfile>> discover() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _discover().then((profiles) {
      _cache = profiles;
      _inFlight = null;
      return profiles;
    });
  }

  @override
  TerminalProfile effectiveDefault(String? configuredId) {
    if (configuredId != null && configuredId.isNotEmpty) {
      final match = profileById(configuredId);
      if (match != null) return match;
      // Configurado mas sumiu (distro removida, PowerShell ausente) → fallback.
    }
    return _platformFallback();
  }

  /// Fallback por plataforma. Preserva **exatamente** o comportamento antigo do
  /// `PtyTerminalGateway._shell()`: Windows ARM abre `cmd` (o PTY do powershell
  /// ainda é instável lá), demais Windows abrem PowerShell, POSIX abre o login
  /// shell com `-l`.
  TerminalProfile _platformFallback() {
    if (_isWindows) {
      final wanted = _isWindowsArm
          ? TerminalProfile.cmdId
          : TerminalProfile.powershellId;
      return profileById(wanted) ??
          (_isWindowsArm
              ? _cmdProfile()
              : _powershellProfile('powershell.exe'));
    }
    // POSIX: `loginShellOrFallback()` é síncrono e lê o cache do login_shell
    // (aquecido no boot); se ainda não resolveu, degrada pro $SHELL/fallback.
    return profileById(TerminalProfile.loginShellId) ??
        _loginShellProfile(loginShellOrFallback());
  }

  Future<List<TerminalProfile>> _discover() async {
    if (_isWindows) return _discoverWindows();
    return _discoverPosix();
  }

  Future<List<TerminalProfile>> _discoverPosix() async {
    final shell = await _loginShell();
    return <TerminalProfile>[_loginShellProfile(shell)];
  }

  Future<List<TerminalProfile>> _discoverWindows() async {
    final profiles = <TerminalProfile>[];

    // PowerShell clássico; se não houver, o pwsh (PowerShell 7+).
    if (await _existsSafe('powershell.exe')) {
      profiles.add(_powershellProfile('powershell.exe'));
    } else if (await _existsSafe('pwsh.exe')) {
      profiles.add(_powershellProfile('pwsh.exe'));
    }

    profiles.add(_cmdProfile());
    profiles.addAll(await _discoverWsl());
    return profiles;
  }

  /// Uma entrada por distro instalada. Sem `wsl.exe`, com erro ou lista vazia →
  /// simplesmente não há perfil WSL (sem exceção).
  Future<List<TerminalProfile>> _discoverWsl() async {
    final ProcessResult res;
    try {
      res = await _run('wsl.exe', const ['-l', '-q']).timeout(_timeout);
    } catch (_) {
      return const <TerminalProfile>[]; // wsl.exe ausente / timeout
    }
    if (res.exitCode != 0) return const <TerminalProfile>[];

    return _decodeWslList(res.stdout)
        .map(
          (distro) => TerminalProfile(
            id: '${TerminalProfile.wslPrefix}$distro',
            label: '$distro (WSL)',
            executable: 'wsl.exe',
            args: <String>['-d', distro],
          ),
        )
        .toList();
  }

  /// Decodifica e parseia a saída do `wsl.exe -l -q`.
  ///
  /// **Pegadinha central da issue #50**: o `wsl.exe` escreve em **UTF-16LE**.
  /// Decodificar como UTF-8 intercala `\x00` entre as letras e nenhum nome de
  /// distro casa. Por isso o runner devolve bytes crus: aqui juntamos os pares
  /// de bytes em code units little-endian e descartamos o BOM.
  ///
  /// Aceita `String` (runner que já decodificou) e bytes; nos bytes, detecta o
  /// UTF-16LE pela presença de NUL — se não houver, trata como UTF-8 (defensivo
  /// contra o dia em que o `wsl.exe` mudar de encoding).
  List<String> _decodeWslList(Object? stdout) {
    final String text;
    if (stdout is String) {
      text = stdout;
    } else if (stdout is List<int>) {
      text = stdout.contains(0) ? _decodeUtf16le(stdout) : _decodeUtf8(stdout);
    } else {
      return const <String>[];
    }

    return text
        .split(RegExp(r'[\r\n]+'))
        // `\x00` residual e o BOM não podem sobreviver ao trim de um nome.
        .map((l) => l.replaceAll('\x00', '').replaceAll('﻿', '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  String _decodeUtf16le(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    if (units.isNotEmpty && units.first == 0xFEFF) units.removeAt(0);
    try {
      return String.fromCharCodes(units);
    } catch (_) {
      return '';
    }
  }

  String _decodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  Future<bool> _existsSafe(String exe) async {
    try {
      return await _exists(exe).timeout(_timeout);
    } catch (_) {
      return false;
    }
  }

  TerminalProfile _powershellProfile(String exe) => TerminalProfile(
    id: TerminalProfile.powershellId,
    label: 'PowerShell',
    executable: exe,
  );

  /// `%ComSpec%` quando presente (o mapa de env do Windows é case-insensitive;
  /// nos testes é um Map comum, então tentamos as duas grafias usadas no app).
  TerminalProfile _cmdProfile() => TerminalProfile(
    id: TerminalProfile.cmdId,
    label: 'cmd',
    executable: _env['ComSpec'] ?? _env['COMSPEC'] ?? 'cmd.exe',
  );

  /// `-l` (login shell), igual ao Terminal.app/iTerm: um app GUI aberto pelo
  /// Finder herda só o PATH mínimo, e sem `-l` o shell pula o `.zprofile`
  /// (Homebrew, `path_helper`, Docker…). Ver `pty_terminal_gateway.dart`.
  TerminalProfile _loginShellProfile(String shell) => TerminalProfile(
    id: TerminalProfile.loginShellId,
    label: '${_basename(shell)} (login)',
    executable: shell,
    args: const <String>['-l'],
  );

  String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}
