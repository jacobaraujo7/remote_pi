import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter/widgets.dart';

/// `TextEditingController` que pinta o texto editável com o **mesmo** syntax
/// highlight do viewer read-only e sobrepõe os **diagnostics do LSP** (sublinhado
/// ondulado). O Flutter desenha o conteúdo de um campo via [buildTextSpan];
/// sobrescrevê-lo para devolver os spans do highlight.js + diagnostics dá tudo
/// ao vivo enquanto se digita — sem reimplementar pintura, seleção ou cursor.
class CodeEditingController extends TextEditingController {
  CodeEditingController({super.text, required this.language}) {
    // Sem seleção explícita, o TextEditingController nasce com selection inválida
    // (offset -1); ao ganhar foco, o cursor pula pro FIM do texto e o viewport
    // rola pro rodapé. Ancorar no início abre o arquivo no começo (esperado).
    selection = const TextSelection.collapsed(offset: 0);
  }

  /// Linguagem (extensão) pro highlight; `null`/desconhecida cai em texto puro.
  final String? language;

  List<LspDiagnostic> _diagnostics = const <LspDiagnostic>[];

  /// Diagnostics publicados pelo servidor para este documento. Setar repinta.
  List<LspDiagnostic> get diagnostics => _diagnostics;
  set diagnostics(List<LspDiagnostic> value) {
    _diagnostics = value;
    notifyListeners();
  }

  /// Matches da busca no arquivo (Cmd+F) + índice do match atual (-1 = nenhum).
  /// Pintados como fundo sobre o syntax highlight; o atual em cor mais forte.
  List<MatchSpan> _matches = const <MatchSpan>[];
  int _currentMatch = -1;

  /// Substitui os matches destacados e o match atual. Repinta o campo.
  void setSearchMatches(List<MatchSpan> matches, int current) {
    _matches = matches;
    _currentMatch = current;
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
    final colors = context.colors;
    final span = buildCodeSpan(
      context,
      source: text,
      language: language,
      baseStyle: style ?? const TextStyle(),
      diagnostics: diagnosticRangesFor(text, _diagnostics),
      matches: _matches,
      currentMatch: _currentMatch,
      matchColor: colors.warn.withValues(alpha: 0.28),
      currentMatchColor: colors.accent.withValues(alpha: 0.45),
    );
    return span ?? TextSpan(text: text, style: style);
  }
}
