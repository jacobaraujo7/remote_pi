import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/domain/contracts/terminal_profile_resolver.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/executable_resolver.dart';
import 'package:cockpit/app/core/utils/login_shell.dart';

/// Roda um processo devolvendo o stdout **cru** (bytes) — ponto de injeção pros
/// testes. Bytes, não String: a saída do `wsl.exe -l -q` é UTF-16LE e deixar o
/// `Process.run` decodificar como UTF-8 destrói a lista (ver [_decodeWslList]).
typedef RawProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Lê `/etc/shells` e devolve as linhas não-comentadas — ponto de injeção pro
/// testes. Cada linha é um caminho absoluto de shell (ex.: `/bin/zsh`).
typedef EtcShellsReader = Future<List<String>> Function();

/// Basenames de shells voltados para uso interativo em terminal.
///
/// Shells de sistema (`sh`, `dash`, `csh`, `tcsh`) não são incluídos:
/// são adequados para scripts mas raramente usados como shell de usuário.
const Set<String> _kInteractiveShells = {
  'bash', 'zsh', 'fish',
  'ksh', 'ksh93', 'mksh', // KornShell e variantes modernas
  'elvish', // Elvish
  'nu', 'nushell', // Nushell
  'xonsh', // Xonsh
  'ion', // Ion (Redox)
  'pwsh', // PowerShell Core no Linux/macOS
};

/// Caminhos adicionais a sondar além do `/etc/shells`.
///
/// Shells instalados via Homebrew tipicamente ficam em `/opt/homebrew/bin`
/// (Apple Silicon) ou `/usr/local/bin` (Intel) e **não** são adicionados
/// automaticamente ao `/etc/shells` — o usuário precisa fazê-lo
/// manualmente (`echo /opt/homebrew/bin/fish | sudo tee -a /etc/shells`).
/// Sondar esses caminhos garante que fish e bash modernos apareçam mesmo
/// sem o passo manual.
const List<String> _kDefaultExtraProbePaths = [
  '/opt/homebrew/bin/fish', // fish · Homebrew Apple Silicon
  '/usr/local/bin/fish', // fish · Homebrew Intel
  '/opt/homebrew/bin/bash', // bash moderno · Homebrew Apple Silicon
  '/usr/local/bin/bash', // bash moderno · Homebrew Intel
];

/// Descoberta de perfis por plataforma (plano 50).
///
/// - **Windows**: PowerShell 7 (`pwsh.exe`) e Windows PowerShell (
///   `powershell.exe`) — **cada um é um perfil**, quando instalado —, cmd
///   (`%ComSpec%`) e uma entrada por distro do `wsl.exe -l -q`.
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
    EtcShellsReader? readEtcShells,
    List<String>? extraProbePaths,
    List<String>? customPaths,
  }) : _env = environment ?? Platform.environment,
       _run = runProcess ?? _defaultRun,
       _os = operatingSystem ?? Platform.operatingSystem,
       // Arch do build (`... on "windows_arm64"`) — fonte confiável, ao
       // contrário de PROCESSOR_ARCHITECTURE (reporta emulação WOW).
       _isWindowsArm =
           isWindowsArm ?? Platform.version.toLowerCase().contains('arm'),
       _loginShell = loginShell ?? resolveLoginShell,
       _exists = executableExists ?? isExecutableAvailable,
       _readEtcShells = readEtcShells ?? _defaultReadEtcShells,
       _extraProbePaths = extraProbePaths ?? _kDefaultExtraProbePaths,
       _initialCustomPaths = customPaths ?? const [];

  final Map<String, String> _env;
  final RawProcessRunner _run;
  final String _os;
  final bool _isWindowsArm;
  final Future<String> Function() _loginShell;
  final Future<bool> Function(String) _exists;
  final EtcShellsReader _readEtcShells;
  final List<String> _extraProbePaths;
  final List<String> _initialCustomPaths;

  static const _timeout = Duration(seconds: 4);

  List<TerminalProfile>? _cache;
  Future<List<TerminalProfile>>? _inFlight;

  static Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
      Process.run(exe, args, stdoutEncoding: null, stderrEncoding: null);

  /// Lê `/etc/shells` e devolve os caminhos não-comentados.
  ///
  /// `/etc/shells` é o inventário oficial dos shells de login no POSIX:
  /// cada linha não-comentada é o caminho absoluto de um shell válido.
  /// Falha silenciosa (arquivo ausente, permissão negada) → lista vazia.
  static Future<List<String>> _defaultReadEtcShells() async {
    try {
      final file = File('/etc/shells');
      if (!await file.exists()) return const [];
      final lines = await file.readAsLines();
      return lines
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

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
  void addCustomProfile(TerminalProfile profile) {
    final cache = _cache;
    // discover() ainda não rodou → no-op (o perfil chegará via _initialCustomPaths
    // se o caller construiu o resolver com o path já na lista; adições runtime
    // só fazem sentido depois do aquecimento, que ocorre no boot).
    if (cache == null) return;
    if (cache.any((p) => p.id == profile.id)) return; // idempotente
    _cache = [...cache, profile];
  }

  @override
  void removeCustomProfile(String id) {
    final cache = _cache;
    if (cache == null) return;
    _cache = cache.where((p) => p.id != id).toList();
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
          (_isWindowsArm ? _cmdProfile() : _powershellProfile());
    }
    // POSIX: o login shell é sempre o primeiro da lista (ver _discoverPosix).
    // `loginShellOrFallback()` é síncrono: lê o cache aquecido no boot.
    final cache = _cache;
    return (cache != null && cache.isNotEmpty)
        ? cache.first
        : _posixShellProfile(loginShellOrFallback());
  }

  Future<List<TerminalProfile>> _discover() async {
    if (_isWindows) return _discoverWindows();
    return _discoverPosix();
  }

  Future<List<TerminalProfile>> _discoverPosix() async {
    final loginShell = await _loginShell();
    final etcShells = await _readEtcShells();

    final seen = <String>{};
    final allPaths = <String>[];

    // 1. Login shell do usuário sempre primeiro — independente do basename.
    if (loginShell.isNotEmpty) {
      seen.add(loginShell);
      allPaths.add(loginShell);
    }

    // 2. /etc/shells filtrado para shells interativos conhecidos.
    //    sh, dash, csh, tcsh e similares são shells de script: aparecem
    //    no /etc/shells mas raramente são usados como terminal do dia-a-dia.
    for (final path in etcShells) {
      if (_isInteractiveShell(path) && seen.add(path)) allPaths.add(path);
    }

    // 3. Caminhos extras — shells instalados via gestor de pacotes (ex.:
    //    fish/bash via Homebrew) que não ficam automaticamente em /etc/shells.
    for (final path in _extraProbePaths) {
      if (_isInteractiveShell(path) && seen.add(path)) allPaths.add(path);
    }

    // 4. Caminhos definidos manualmente pelo usuário — bypass do filtro de
    //    shells interativos (o usuário já sabe o que está fazendo). Apenas
    //    deduplicamos; a existência no disco é verificada no loop abaixo.
    for (final path in _initialCustomPaths) {
      if (seen.add(path)) allPaths.add(path);
    }

    // Filtra para apenas os que existem como executáveis no disco.
    final profiles = <TerminalProfile>[];
    for (final path in allPaths) {
      if (await _existsSafe(path)) profiles.add(_posixShellProfile(path));
    }

    // Ultra-fallback: /etc/shells pode não existir em containers mínimos.
    if (profiles.isEmpty) {
      final shell = loginShell.isNotEmpty ? loginShell : '/bin/sh';
      return [_posixShellProfile(shell)];
    }
    return profiles;
  }

  /// Retorna true para shells voltados ao uso interativo (bash, zsh, fish, …).
  /// sh, dash, csh, tcsh e demais shells de sistema são excluídos.
  static bool _isInteractiveShell(String path) {
    final name = path.split('/').last;
    return _kInteractiveShells.contains(name);
  }

  Future<List<TerminalProfile>> _discoverWindows() async {
    final profiles = <TerminalProfile>[];

    // PowerShell 7+ e Windows PowerShell 5.1 são perfis SEPARADOS, não um o
    // substituto do outro: quem tem os dois instalados quer escolher entre eles.
    // (Antes o `pwsh` só entrava se o `powershell.exe` faltasse — como este
    // último sempre existe no Windows, o 7 nunca era oferecido.)
    //
    // O 7 vem primeiro por ser o moderno, mas o PADRÃO de quem nunca escolheu
    // continua o 5.1 (ver `_platformFallback`): trocar o shell de quem já usa
    // seria surpresa. O 7 fica a um clique no seletor.
    if (await _existsSafe('pwsh.exe')) {
      profiles.add(_pwshProfile());
    }
    if (await _existsSafe('powershell.exe')) {
      profiles.add(_powershellProfile());
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

  /// PowerShell 7+ (`pwsh.exe`), instalado à parte pelo usuário.
  TerminalProfile _pwshProfile() => const TerminalProfile(
    id: TerminalProfile.pwshId,
    label: 'PowerShell 7',
    executable: 'pwsh.exe',
  );

  /// Windows PowerShell 5.1 — o que vem no SO. O rótulo diz "Windows" (a mesma
  /// distinção que o Windows Terminal faz) porque com os dois instalados um
  /// "PowerShell" solto não diria qual.
  TerminalProfile _powershellProfile() => const TerminalProfile(
    id: TerminalProfile.powershellId,
    label: 'Windows PowerShell',
    executable: 'powershell.exe',
  );

  /// `%ComSpec%` quando presente (o mapa de env do Windows é case-insensitive;
  /// nos testes é um Map comum, então tentamos as duas grafias usadas no app).
  TerminalProfile _cmdProfile() => TerminalProfile(
    id: TerminalProfile.cmdId,
    label: 'cmd',
    executable: _env['ComSpec'] ?? _env['COMSPEC'] ?? 'cmd.exe',
  );

  /// Um perfil para um shell POSIX descoberto via `/etc/shells` (ou login shell).
  ///
  /// `-l` (login shell), igual ao Terminal.app/iTerm: um app GUI aberto pelo
  /// Finder herda só o PATH mínimo, e sem `-l` o shell pula o `.zprofile`
  /// (Homebrew, `path_helper`, Docker…). Ver `pty_terminal_gateway.dart`.
  TerminalProfile _posixShellProfile(String path) => TerminalProfile(
    id: '${TerminalProfile.posixPrefix}$path',
    label: _basename(path),
    executable: path,
    args: const <String>['-l'],
  );

  String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}
