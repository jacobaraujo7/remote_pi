/// Motivos de falha ao exportar o preview de markdown como PDF (plano 73).
enum PdfExportErrorKind {
  /// A página do preview ainda não carregou (ou a webview sumiu no meio).
  notReady,

  /// Preparar a página para impressão falhou (render dos diagramas, JS).
  renderFailed,

  /// O sistema não gerou o arquivo (operação de impressão falhou/abortou).
  writeFailed,
}

/// Falha tipada da exportação para PDF.
///
/// O widget só produz o [kind]; a frase nasce na UI
/// (`pdfExportErrorMessage`). [detail] é texto de terceiros (erro do JS/da
/// plataforma) e é exibido **cru**, sem tradução.
class PdfExportError implements Exception {
  const PdfExportError(this.kind, {this.detail});

  final PdfExportErrorKind kind;
  final String? detail;

  @override
  String toString() =>
      'PdfExportError($kind${detail == null ? '' : ': $detail'})';
}
