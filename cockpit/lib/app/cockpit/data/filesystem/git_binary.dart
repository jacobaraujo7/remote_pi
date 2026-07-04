import 'dart:io';

/// Resolve o caminho do binário `git` por candidatos conhecidos e cacheia o
/// resultado. O app macOS **não herda o PATH do shell**, então não podemos
/// depender de `git` no PATH — procuramos nos locais usuais primeiro.
///
/// Compartilhado por todo o lado git do Cockpit (`GitStatusReaderImpl`,
/// `WorktreeManagerImpl`, `GitCommandRunnerImpl`, `GitDiffReaderImpl`) — antes a
/// lógica estava duplicada em cada impl.
class GitBinary {
  GitBinary();

  String? _cached;

  static const List<String> _candidates = <String>[
    '/usr/bin/git',
    '/opt/homebrew/bin/git',
    '/usr/local/bin/git',
  ];

  /// Caminho do binário `git` (cacheado). Cai em `'git'` (PATH) como último
  /// recurso quando nenhum candidato existe.
  Future<String> resolve() async {
    final cached = _cached;
    if (cached != null) return cached;
    for (final candidate in _candidates) {
      if (await File(candidate).exists()) return _cached = candidate;
    }
    return _cached = 'git';
  }
}
