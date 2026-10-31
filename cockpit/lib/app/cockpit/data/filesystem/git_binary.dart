import 'dart:io';

/// Resolve o caminho do binário `git` por candidatos conhecidos e cacheia o
/// resultado. O app GUI **não herda o PATH do shell** (macOS aberto pelo
/// Finder/Dock não tem `/opt/homebrew/bin` nem `/usr/local/bin`), então não
/// podemos depender de `git` no PATH — procuramos nos locais usuais primeiro.
///
/// Compartilhado por todo o lado git do Cockpit (`GitStatusReaderImpl`,
/// `WorktreeManagerImpl`, `GitCommandRunnerImpl`, `GitDiffReaderImpl`) — antes a
/// lógica estava duplicada em cada impl.
class GitBinary {
  /// [environment], [isWindows] e [exists] existem pra teste; por padrão vêm
  /// do processo e do disco.
  GitBinary({this._environment, this._isWindows, this._exists});

  final Map<String, String>? _environment;
  final bool? _isWindows;
  final Future<bool> Function(String path)? _exists;

  String? _cached;

  /// macOS: `/usr/bin/git` (Xcode Command Line Tools, Silicon e Intel),
  /// Homebrew no Silicon (`/opt/homebrew`) e no Intel (`/usr/local`).
  static const List<String> _posixCandidates = <String>[
    '/usr/bin/git',
    '/opt/homebrew/bin/git',
    '/usr/local/bin/git',
  ];

  /// Windows: instalações do Git for Windows (máquina e usuário). O instalador
  /// costuma pôr `Git\cmd` no PATH, mas é opção desmarcável — e o PATH do app
  /// pode ser anterior à instalação.
  List<String> _windowsCandidates(Map<String, String> env) => [
    for (final base in [
      env['ProgramFiles'] ?? env['PROGRAMFILES'],
      env['ProgramW6432'],
      env['ProgramFiles(x86)'] ?? env['PROGRAMFILES(X86)'],
    ])
      if (base != null && base.isNotEmpty) '$base\\Git\\cmd\\git.exe',
    if (env['LOCALAPPDATA'] case final local? when local.isNotEmpty)
      '$local\\Programs\\Git\\cmd\\git.exe',
  ];

  /// Candidatos na ordem de tentativa, pra plataforma atual (ou injetada).
  List<String> get candidates {
    final env = _environment ?? Platform.environment;
    return (_isWindows ?? Platform.isWindows)
        ? _windowsCandidates(env)
        : _posixCandidates;
  }

  /// Caminho do binário `git` (cacheado). Cai em `'git'` (PATH) como último
  /// recurso quando nenhum candidato existe; se nem o PATH tiver, o spawn
  /// falha e quem chamou mostra "Failed to run git".
  Future<String> resolve() async {
    final cached = _cached;
    if (cached != null) return cached;
    final exists = _exists ?? (String path) => File(path).exists();
    for (final candidate in candidates) {
      if (await exists(candidate)) return _cached = candidate;
    }
    return _cached = 'git';
  }
}
