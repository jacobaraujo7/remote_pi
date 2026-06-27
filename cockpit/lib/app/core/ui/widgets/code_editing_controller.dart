import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter/widgets.dart';

/// `TextEditingController` que pinta o texto editável com o **mesmo** syntax
/// highlight do viewer read-only e sobrepõe os **diagnostics do LSP** (sublinhado
/// ondulado). O Flutter desenha o conteúdo de um campo via [buildTextSpan];
/// sobrescrevê-lo para devolver os spans do highlight.js + diagnostics dá tudo
/// ao vivo enquanto se digita — sem reimplementar pintura, seleção ou cursor.
class CodeEditingController extends TextEditingController {
  CodeEditingController({super.text, required this.language});

  /// Linguagem (extensão) pro highlight; `null`/desconhecida cai em texto puro.
  final String? language;

  List<LspDiagnostic> _diagnostics = const <LspDiagnostic>[];

  /// Diagnostics publicados pelo servidor para este documento. Setar repinta.
  List<LspDiagnostic> get diagnostics => _diagnostics;
  set diagnostics(List<LspDiagnostic> value) {
    _diagnostics = value;
    notifyListeners();
  }

  /// Severidade mais grave que toca a linha (base 0), ou `null`. Usado no gutter.
  LspSeverity? severityForLine(int line) {
    LspSeverity? result;
    for (final d in _diagnostics) {
      if (line >= d.range.start.line && line <= d.range.end.line) {
        if (result == null || d.severity.index < result.index) {
          result = d.severity;
        }
      }
    }
    return result;
  }

  /// Mensagens dos diagnostics que tocam a linha (base 0). Usado no tooltip.
  List<String> messagesForLine(int line) {
    final out = <String>[];
    for (final d in _diagnostics) {
      if (line >= d.range.start.line && line <= d.range.end.line) {
        final src = d.source == null ? '' : '[${d.source}] ';
        out.add('$src${d.message}');
      }
    }
    return out;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final span = buildCodeSpan(
      context,
      source: text,
      language: language,
      baseStyle: style ?? const TextStyle(),
      diagnostics: diagnosticRangesFor(text, _diagnostics),
    );
    return span ?? TextSpan(text: text, style: style);
  }
}
