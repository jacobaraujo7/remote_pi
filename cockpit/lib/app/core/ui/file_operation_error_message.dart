import 'package:cockpit/app/core/domain/exceptions/file_operation_error.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';

/// Traduz um [FileOperationError] para a frase mostrada ao usuário.
///
/// Mesma regra do `automationErrorMessage`: `data/` e ViewModel devolvem o tipo,
/// e o texto nasce aqui. O `switch` é exaustivo sobre o enum, então um
/// [FileOperationErrorKind] novo sem tradução quebra a compilação em vez de
/// vazar inglês em produção.
String fileOperationErrorMessage(
  BuildContext context,
  FileOperationError error,
) {
  final tr = context.t.fileOperation.error;
  final name = error.name ?? '';
  final detail = error.detail?.trim() ?? '';

  return switch (error.kind) {
    FileOperationErrorKind.alreadyExists => tr.alreadyExists(name: name),
    FileOperationErrorKind.notFound => tr.notFound(name: name),
    FileOperationErrorKind.invalidPath => tr.invalidPath,
    FileOperationErrorKind.emptyName => tr.emptyName,
    FileOperationErrorKind.nameHasSlash => tr.nameHasSlash,
    FileOperationErrorKind.invalidName => tr.invalidName,
    FileOperationErrorKind.noWorkspace => tr.noWorkspace,
    FileOperationErrorKind.cannotMoveIntoItself => tr.cannotMoveIntoItself,
    FileOperationErrorKind.clipboardEmpty => tr.clipboardEmpty,
    FileOperationErrorKind.notScratchTab => tr.notScratchTab,
    FileOperationErrorKind.remoteDropUnsupported => tr.remoteDropUnsupported,
    FileOperationErrorKind.writeFailed => tr.writeFailed,
    FileOperationErrorKind.formatterEmptyCommand => tr.formatterEmptyCommand,
    FileOperationErrorKind.formatterMissingPlaceholder =>
      tr.formatterMissingPlaceholder,
    FileOperationErrorKind.formatterTimeout => tr.formatterTimeout,
    FileOperationErrorKind.formatterExitCode => tr.formatterExitCode(
      code: error.exitCode ?? 0,
    ),
    // Falha sem texto útil do SO cai na frase genérica do formatador.
    FileOperationErrorKind.formatterFailed =>
      detail.isEmpty ? tr.formatterFailed : detail,
    FileOperationErrorKind.osFailure =>
      detail.isEmpty ? tr.formatterFailed : tr.osFailure(detail: detail),
  };
}
