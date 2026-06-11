import 'dart:io';

/// Resolve o caminho de um executável (`pi`, `node`, `remote-pi`, …) de forma
/// robusta — apps GUI não herdam a PATH do shell.
///
/// Estratégia preferida:
/// - **macOS/Linux**: `which <name>` rodado num **shell de login** (`$SHELL -lc`),
///   que carrega o profile do usuário e enxerga a PATH real (npm global, nvm,
///   Homebrew, etc.) — bem mais seguro que adivinhar prefixos.
/// - **Windows**: `where <name>`, que já resolve PATHEXT (`pi.cmd`/`pi.exe`/…).
///
/// Fallbacks (quando o which/where não acha): os caminhos conhecidos abaixo e,
/// por fim, o próprio [name] (deixa o SO resolver no spawn).
///
/// - [unixCandidates]: caminhos absolutos testados em ordem (macOS/Linux).
/// - [unixHomeRelative]: caminhos relativos a `$HOME` (ex.: `.local/bin/pi`).
/// - [windowsExtraDirs]: diretórios absolutos extras a sondar no Windows
///   (ex.: `C:\Program Files\nodejs`), além da PATH e de `%APPDATA%\npm`.
Future<String> resolveExecutable(
  String name, {
  List<String> unixCandidates = const [],
  List<String> unixHomeRelative = const [],
  List<String> windowsExtraDirs = const [],
}) async {
  if (Platform.isWindows) {
    final viaWhere = await _windowsWhere(name);
    if (viaWhere != null) return viaWhere;

    // Fallback: varre PATH×PATHEXT, %APPDATA%\npm e diretórios extras.
    final fromPath = await _searchWindowsPath(name);
    if (fromPath != null) return fromPath;
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      for (final ext in const ['cmd', 'exe', 'bat']) {
        final shim = '$appData\\npm\\$name.$ext';
        if (await File(shim).exists()) return shim;
      }
    }
    for (final dir in windowsExtraDirs) {
      for (final ext in const ['exe', 'cmd', 'bat']) {
        final candidate = '$dir\\$name.$ext';
        if (await File(candidate).exists()) return candidate;
      }
    }
    return name;
  }

  // macOS/Linux: `which` via shell de login (PATH completa do usuário).
  final viaWhich = await _unixWhich(name);
  if (viaWhich != null) return viaWhich;

  // Fallback: caminhos conhecidos.
  for (final candidate in unixCandidates) {
    if (await File(candidate).exists()) return candidate;
  }
  final home = Platform.environment['HOME'];
  if (home != null) {
    for (final rel in unixHomeRelative) {
      final candidate = '$home/$rel';
      if (await File(candidate).exists()) return candidate;
    }
  }
  return name;
}

/// `which <name>` num shell de **login** do usuário (`-lc`). Carrega
/// `.zprofile`/`.bash_profile`/`.profile` (ou equivalente) pra herdar a PATH real
/// (nvm/npm/brew), que o processo GUI não tem. Devolve o 1º caminho existente,
/// ou `null`.
///
/// **Por que login e não interativo** (`-lc`, não `-lic`): um shell interativo
/// sem tty quebra em alguns sistemas (Linux ARM: "bash: cannot set terminal
/// process group / no job control"). O modo login basta pra carregar a PATH.
Future<String?> _unixWhich(String name) async {
  final shell = Platform.environment['SHELL'] ?? '/bin/sh';
  try {
    final res = await Process.run(shell, ['-lc', 'which $name'])
        .timeout(const Duration(seconds: 4));
    if (res.exitCode != 0) return null;
    for (final line in (res.stdout as String? ?? '').split('\n')) {
      final p = line.trim();
      // Ignora ruído de shell interativo; aceita só um caminho real.
      if (p.startsWith('/') && await File(p).exists()) return p;
    }
  } catch (_) {
    // shell ausente / timeout / erro → cai pros fallbacks.
  }
  return null;
}

/// `where <name>` no Windows — resolve PATHEXT e devolve o 1º caminho existente.
Future<String?> _windowsWhere(String name) async {
  try {
    final res = await Process.run('where', [name], runInShell: true)
        .timeout(const Duration(seconds: 4));
    if (res.exitCode != 0) return null;
    for (final line in (res.stdout as String? ?? '').split('\n')) {
      final p = line.trim();
      if (p.isNotEmpty && await File(p).exists()) return p;
    }
  } catch (_) {
    // where indisponível / timeout → cai pros fallbacks.
  }
  return null;
}

/// Varre cada diretório do `PATH` testando `name` + cada extensão do `PATHEXT`
/// (`.COM;.EXE;.BAT;.CMD;…`). Devolve o caminho absoluto do primeiro hit, ou
/// `null`. Específico de Windows.
Future<String?> _searchWindowsPath(String name) async {
  final pathEnv = Platform.environment['PATH'] ?? '';
  final pathExt = (Platform.environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD')
      .split(';')
      .where((e) => e.isNotEmpty)
      .toList();
  for (final dir in pathEnv.split(';')) {
    if (dir.isEmpty) continue;
    for (final ext in pathExt) {
      final candidate = '$dir\\$name$ext';
      if (await File(candidate).exists()) return candidate;
    }
  }
  return null;
}
