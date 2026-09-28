/// Motivos de falha das operações de arquivo do workspace (criar, renomear,
/// mover, colar, lixeira, salvar scratch) e do formatador externo.
enum FileOperationErrorKind {
  alreadyExists,
  notFound,
  invalidPath,
  emptyName,
  nameHasSlash,
  invalidName,
  noWorkspace,
  cannotMoveIntoItself,
  clipboardEmpty,
  notScratchTab,

  /// Drop de arquivos do SO num workspace remoto (upload por SSH não existe).
  remoteDropUnsupported,
  writeFailed,
  // Formatador externo (LSP "Language" → comando de formatação)
  formatterEmptyCommand,
  formatterMissingPlaceholder,
  formatterTimeout,
  formatterExitCode,
  formatterFailed,

  /// Falha crua do SO/processo — o texto vem em [FileOperationError.detail].
  osFailure,
}

/// Falha de operação de arquivo **sem texto de usuário embutido**.
///
/// Mesmo contrato do `AutomationError`: `data/` e ViewModel só descrevem *o
/// que* houve ([kind]) mais os dados variáveis ([name], [detail], [exitCode]);
/// a frase nasce na UI, em `fileOperationErrorMessage` (`core/ui`). Ver a seção
/// de i18n no `cockpit/CLAUDE.md`.
class FileOperationError implements Exception {
  const FileOperationError(
    this.kind, {
    this.name,
    this.detail,
    this.exitCode,
    this.cause,
  });

  final FileOperationErrorKind kind;

  /// Nome do arquivo/pasta envolvido, quando a frase o cita.
  final String? name;

  /// Texto cru de terceiros (stderr do formatador, mensagem do SO). Nunca
  /// traduzido — entra interpolado na frase traduzida.
  final String? detail;

  final int? exitCode;

  final Object? cause;

  @override
  String toString() =>
      'FileOperationError($kind'
      '${name == null ? '' : ', name: $name'}'
      '${detail == null ? '' : ', detail: $detail'})';
}
