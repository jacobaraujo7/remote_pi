/// Resolve o caminho que o usuário clicou no terminal (Cmd/Ctrl+clique) para
/// um caminho absoluto a abrir.
///
/// O cwd da aba nem sempre é a pasta a que o texto se refere: um agente rodando
/// em `app/` cita `plan/03-protocol.md` relativo à raiz do monorepo, e um `cd`
/// sem OSC 7 deixa o cwd velho. Por isso, quando dá pra olhar o disco
/// ([exists]), o caminho relativo é tentado no cwd e depois em cada pasta acima
/// dele até a raiz do workspace (e nas próprias raízes), e vence o primeiro que
/// existe. Sem acerto — ou sem [exists], caso do workspace remoto — fica o
/// cwd + caminho, como sempre foi.
abstract final class TerminalPathResolver {
  static final _windowsDrive = RegExp(r'^[a-zA-Z]:[\\/]');

  static String? resolve(
    String token, {
    required String? cwd,
    String? home,
    List<String> roots = const [],
    bool Function(String path)? exists,
  }) {
    var t = token.trim();
    if (t.isEmpty) return null;
    if (t == '~' || t.startsWith('~/')) {
      if (home == null) return null;
      t = t == '~' ? home : '$home/${t.substring(2)}';
    }
    if (_isAbsolute(t)) return _normalize(t);

    final hasCwd = cwd != null && cwd.isNotEmpty;
    if (exists != null) {
      for (final base in _bases(hasCwd ? _normalize(cwd) : null, roots)) {
        final candidate = _normalize('$base/$t');
        if (exists(candidate)) return candidate;
      }
    }
    if (!hasCwd) return null;
    return _normalize('$cwd/$t');
  }

  /// cwd, as pastas acima dele que ainda estão dentro de uma raiz, e as
  /// raízes. Sem repetição, nesta ordem.
  static Iterable<String> _bases(String? cwd, List<String> roots) sync* {
    final normalizedRoots = [for (final r in roots) _normalize(r)];
    final seen = <String>{};
    if (cwd != null) {
      final containing = [
        for (final r in normalizedRoots)
          if (_isUnder(cwd, r)) r,
      ];
      var dir = cwd;
      while (true) {
        if (seen.add(dir)) yield dir;
        // Sem raiz que contenha o cwd, não sobe: fora do workspace, só o cwd.
        if (!containing.any((r) => dir != r && _isUnder(dir, r))) break;
        final cut = dir.lastIndexOf('/');
        if (cut <= 0) break;
        dir = dir.substring(0, cut);
      }
    }
    for (final r in normalizedRoots) {
      if (seen.add(r)) yield r;
    }
  }

  static bool _isUnder(String path, String root) =>
      path == root || path.startsWith(root.endsWith('/') ? root : '$root/');

  static bool _isAbsolute(String path) =>
      path.startsWith('/') || _windowsDrive.hasMatch(path);

  /// Colapsa segmentos `.` e `..` de um caminho POSIX-ish (mantém a raiz `/`).
  static String _normalize(String path) {
    final isAbs = path.startsWith('/');
    final out = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (out.isNotEmpty && out.last != '..') {
          out.removeLast();
        } else if (!isAbs) {
          out.add('..');
        }
      } else {
        out.add(part);
      }
    }
    final joined = out.join('/');
    return isAbs ? '/$joined' : joined;
  }
}
