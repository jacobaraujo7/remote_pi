import 'dart:io';

/// Descobre a **raiz do projeto** de um arquivo subindo a árvore de diretórios
/// até achar um arquivo marcador da linguagem (ex.: `pubspec.yaml` pro Dart,
/// `package.json`/`tsconfig.json` pro TS). É o que resolve o monorepo: dado
/// `mono/cockpit/lib/main.dart`, a raiz do servidor Dart é `mono/cockpit/`
/// (onde está o `pubspec.yaml`), não `mono/`.
///
/// A chave do pool é `(linguagem, raiz)` — logo dois arquivos do mesmo pacote
/// compartilham servidor, e pacotes distintos têm servidores distintos.
class ProjectRootFinder {
  const ProjectRootFinder();

  /// Sobe a partir do diretório de [filePath] procurando qualquer um dos
  /// [markers]. Markers podem ser nome exato (`pubspec.yaml`) ou padrão de
  /// sufixo (`*.csproj`). Retorna a primeira raiz encontrada, ou `null` se
  /// nenhuma — o chamador decide o fallback (geralmente a pasta do workspace).
  String? findRoot(String filePath, List<String> markers) {
    if (markers.isEmpty) return null;
    var dir = Directory(File(filePath).parent.path);
    // Limite defensivo de profundidade pra não andar a árvore inteira.
    for (var depth = 0; depth < 64; depth++) {
      if (_hasMarker(dir, markers)) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break; // chegou na raiz do FS
      dir = parent;
    }
    return null;
  }

  bool _hasMarker(Directory dir, List<String> markers) {
    final exact = <String>{};
    final suffixes = <String>[];
    for (final m in markers) {
      if (m.startsWith('*.')) {
        suffixes.add(m.substring(1)); // '.csproj'
      } else {
        exact.add(m);
      }
    }
    // Nome exato: checagem direta (barato).
    for (final name in exact) {
      if (File('${dir.path}${Platform.pathSeparator}$name').existsSync()) {
        return true;
      }
    }
    // Sufixo (*.csproj/*.sln): precisa listar o diretório.
    if (suffixes.isNotEmpty) {
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is File) {
            final name = entity.path.split(Platform.pathSeparator).last;
            if (suffixes.any(name.endsWith)) return true;
          }
        }
      } catch (_) {
        // Sem permissão de leitura no diretório → ignora.
      }
    }
    return false;
  }
}
