/// Aplicativo externo que pode ser lançado para abrir uma pasta (IDE ou Finder).
class LaunchableApp {
  const LaunchableApp({required this.id, required this.name, this.iconPath});

  /// Identificador estável usado para persistir a última escolha do usuário.
  /// Valores conhecidos: `'cursor'`, `'windsurf'`, `'antigravity'`, `'vscode'`,
  /// `'finder'`.
  final String id;

  /// Nome legível exibido no dropdown.
  final String name;

  /// Caminho para um PNG extraído do bundle do app (64×64). Pode ser `null` se
  /// a extração falhou — o widget cai no ícone Material de fallback.
  final String? iconPath;
}
