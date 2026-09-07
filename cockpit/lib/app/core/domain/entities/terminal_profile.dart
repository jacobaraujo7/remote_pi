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
  /// Formato: `powershell` | `cmd` | `wsl:<distro>` | `posix:<path>` |
  /// `login-shell` (legado, migrado automaticamente) | `custom:<uuid>`.
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

  /// Perfil "o HOST decide": executável vazio = o servidor abre o shell de
  /// login do usuário DELE.
  ///
  /// É o default de workspace remoto. O cliente não tem como saber qual shell
  /// existe do outro lado, e impor o seu é um erro de categoria — um cliente
  /// Windows pedia `powershell.exe` num host macOS, o spawn falhava e a aba
  /// ficava eternamente vazia, sem erro visível.
  static const TerminalProfile hostLoginShell = TerminalProfile(
    id: loginShellId,
    label: 'login shell',
    executable: '',
  );

  /// Prefixo de [id] dos perfis de distro WSL.
  static const String wslPrefix = 'wsl:';

  /// Prefixo de [id] dos perfis POSIX descobertos via `/etc/shells`.
  /// Formato: `'posix:/bin/zsh'`, `'posix:/usr/local/bin/fish'`, …
  static const String posixPrefix = 'posix:';

  /// [id] do perfil de login shell POSIX (macOS/Linux).
  static const String loginShellId = 'login-shell';

  /// [id] do perfil Windows PowerShell 5.1 — o `powershell.exe` que vem no SO.
  /// **Não** renomear: é o que a config de padrão guarda desde a wave 1.
  static const String powershellId = 'powershell';

  /// [id] do perfil PowerShell 7+ (`pwsh.exe`), instalado à parte. Perfil
  /// próprio, e não substituto do [powershellId]: quem tem os dois quer escolher.
  static const String pwshId = 'pwsh';

  /// [id] do perfil cmd (Windows).
  static const String cmdId = 'cmd';

  /// Retorna o nome da distro WSL se este perfil for de uma distro WSL, caso contrário null.
  String? get wslDistro =>
      id.startsWith(wslPrefix) ? id.substring(wslPrefix.length) : null;

  @override
  String toString() => 'TerminalProfile($id, $executable ${args.join(' ')})';
}
