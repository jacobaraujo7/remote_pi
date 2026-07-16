/// Um **perfil de terminal**: como abrir um terminal. Genérico por design — o
/// gateway de PTY não sabe o que é "WSL" ou "PowerShell", só recebe
/// `{executable, args}`. Toda descoberta/rotulagem mora no
/// `TerminalProfileResolver` (ver plano 50).
class TerminalProfile {
  const TerminalProfile({
    required this.id,
    required this.label,
    required this.executable,
    this.args = const <String>[],
    this.builtIn = true,
    this.iconKey,
  });

  /// Identidade **estável** — é o que a config (Hive) guarda como padrão.
  /// Nunca persistimos o objeto inteiro: perfis são re-descobertos a cada boot
  /// e a config referencia por [id].
  ///
  /// Formato: `powershell` | `cmd` | `wsl:<distro>` | `login-shell` |
  /// `custom:<uuid>`.
  final String id;

  /// Rótulo de exibição (`PowerShell`, `Ubuntu (WSL)`, `zsh (login)`).
  final String label;

  /// Executável do PTY (`powershell.exe`, `wsl.exe`, `/bin/zsh`, …).
  final String executable;

  /// Argumentos (`['-d','Ubuntu']`, `['-l']`, …).
  final List<String> args;

  /// Detectado pelo resolver (não editável) vs. definido pelo usuário (fatia 4).
  final bool builtIn;

  /// Opcional — ícone no dropdown do `+` (fatia 3).
  final String? iconKey;

  /// Prefixo de [id] dos perfis de distro WSL.
  static const String wslPrefix = 'wsl:';

  /// [id] do perfil de login shell POSIX (macOS/Linux).
  static const String loginShellId = 'login-shell';

  /// [id] do perfil PowerShell (Windows).
  static const String powershellId = 'powershell';

  /// [id] do perfil cmd (Windows).
  static const String cmdId = 'cmd';

  @override
  String toString() => 'TerminalProfile($id, $executable ${args.join(' ')})';
}
