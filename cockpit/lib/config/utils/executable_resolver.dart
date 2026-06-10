import 'dart:io';

/// Resolve o caminho de um executável (`pi`, `node`, …) de forma robusta — apps
/// GUI não herdam a PATH do shell, então procuramos em caminhos conhecidos.
///
/// - [unixCandidates]: caminhos absolutos testados em ordem (macOS/Linux).
/// - [unixHomeRelative]: caminhos relativos a `$HOME` (ex.: `.local/bin/pi`).
/// - [windowsExtraDirs]: diretórios absolutos extras a sondar no Windows
///   (ex.: `C:\Program Files\nodejs`), além da PATH e de `%APPDATA%\npm`.
///
/// Fallback (nada encontrado) = o próprio [name], deixando o SO resolver via PATH.
Future<String> resolveExecutable(
  String name, {
  List<String> unixCandidates = const [],
  List<String> unixHomeRelative = const [],
  List<String> windowsExtraDirs = const [],
}) async {
  if (Platform.isWindows) {
    final fromPath = await _searchWindowsPath(name);
    if (fromPath != null) return fromPath;
    // Shims do npm (ex.: `pi.cmd`) ficam em %APPDATA%\npm.
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
