import '../domain/exceptions/pdf_export_error.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';

/// Frase de um [PdfExportError] para a UI (plano 73).
///
/// Mora na feature, e não no `core/ui`, porque o erro é do domínio do cockpit
/// (o core não importa de feature). O `switch` é exaustivo sobre o enum: um
/// `kind` novo sem frase não compila. O [PdfExportError.detail] é texto de
/// terceiros (erro do JS/da plataforma) e vai cru, depois da frase.
String pdfExportErrorMessage(BuildContext context, PdfExportError e) {
  final tr = context.t.cockpit.fileViewer.pdfError;
  final message = switch (e.kind) {
    PdfExportErrorKind.notReady => tr.notReady,
    PdfExportErrorKind.renderFailed => tr.renderFailed,
    PdfExportErrorKind.writeFailed => tr.writeFailed,
  };
  final detail = e.detail;
  return detail == null || detail.isEmpty ? message : '$message\n$detail';
}
