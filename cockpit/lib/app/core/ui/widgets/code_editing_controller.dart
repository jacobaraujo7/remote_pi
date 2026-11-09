import 'dart:async';

import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter/widgets.dart';

/// Placeholder sem valor no contexto do editor, com offsets UTF-16 `[start,end)`.
class UnresolvedCodeVariable {
  const UnresolvedCodeVariable(this.start, this.end, this.message);

  final int start;
  final int end;
  final String message;
}

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

  List<UnresolvedCodeVariable> _unresolvedVariables = const [];

  void setUnresolvedVariables(List<UnresolvedCodeVariable> value) {
    if (_unresolvedVariables.length == value.length &&
        _unresolvedVariables.asMap().entries.every((e) {
          final a = e.value;
          final b = value[e.key];
          return a.start == b.start && a.end == b.end && a.message == b.message;
        })) {
      return;
    }
    _unresolvedVariables = value;
    notifyListeners();
  }

  String? unresolvedVariableMessageAt(int offset) {
    for (final v in _unresolvedVariables) {
      if (v.start <= offset && offset < v.end) return v.message;
    }
    return null;
  }

  List<DiagnosticRange> _highlightRanges(String source) => [
    ...diagnosticRangesFor(source, _diagnostics),
    for (final v in _unresolvedVariables)
      if (v.start >= 0 && v.end <= source.length && v.start < v.end)
        DiagnosticRange(v.start, v.end, LspSeverity.warning),
  ];

  /// Diagnostics publicados pelo servidor para este documento. Setar repinta.
  List<LspDiagnostic> get diagnostics => _diagnostics;
  set diagnostics(List<LspDiagnostic> value) {
    _diagnostics = value;
    notifyListeners();
  }

  List<SemanticRange> _semanticTokens = const <SemanticRange>[];

  /// Tokens semânticos do servidor para este documento. Setar repinta.
  List<SemanticRange> get semanticTokens => _semanticTokens;
  set semanticTokens(List<SemanticRange> value) {
    _semanticTokens = value;
    notifyListeners();
  }

  /// Reposiciona os overlays de offset quando o **texto** muda.
  ///
  /// Os semantic tokens vêm do servidor com offsets absolutos, válidos só pro
  /// conteúdo que ele analisou. Sem isso, digitar deslocava todo o texto depois
  /// do cursor e os tokens continuavam apontando pros offsets antigos — a cor
  /// caía nas letras erradas até o próximo batch chegar (400ms depois, pelo
  /// debounce), e voltava a errar na tecla seguinte. Era o "highlight de outras
  /// letras mudando enquanto digito".
  ///
  /// Remapeia como o remendo léxico: token antes da edição fica; token depois
  /// desloca pelo delta; token que **cruza** a edição é descartado (não se sabe
  /// o que ele virou — o batch novo resolve).
  @override
  set value(TextEditingValue newValue) {
    final oldText = super.value.text;
    final newText = newValue.text;
    if (oldText != newText) {
      if (_semanticTokens.isNotEmpty) {
        _semanticTokens = _shiftRanges(_semanticTokens, oldText, newText);
      }
      // O identifier sob o mouse deixou de valer (offsets mudaram).
      _definitionHoverRange = null;
    }
    super.value = newValue;
  }

  static List<SemanticRange> _shiftRanges(
    List<SemanticRange> ranges,
    String oldText,
    String newText,
  ) {
    final oldLen = oldText.length;
    final newLen = newText.length;
    final maxCommon = oldLen < newLen ? oldLen : newLen;
    var prefix = 0;
    while (prefix < maxCommon &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    final maxSuffix = maxCommon - prefix;
    while (suffix < maxSuffix &&
        oldText.codeUnitAt(oldLen - 1 - suffix) ==
            newText.codeUnitAt(newLen - 1 - suffix)) {
      suffix++;
    }
    final removedEnd = oldLen - suffix;
    final delta = newLen - oldLen;

    final out = <SemanticRange>[];
    for (final r in ranges) {
      if (r.end <= prefix) {
        out.add(r); // antes da edição → intacto
      } else if (r.start >= removedEnd) {
        out.add(SemanticRange(r.start + delta, r.end + delta, r.tokenType));
      }
      // cruza a edição → descartado
    }
    return out;
  }

  /// Identifica a posição LSP do identifier que cobre [offset] (pra go-to-def).
  ({int line, int character})? identifierAtOffset(int offset) {
    final range = wordRangeAt(offset);
    if (range == null) return null;
    return offsetToLineChar(range.start);
  }

  /// Range `[start, end)` do identifier que cobre [offset] — token semântico
  /// se houver um cobrindo, senão a palavra (sequência alfanumérica) ao redor.
  /// `null` se [offset] não cai sobre um identifier.
  ({int start, int end})? wordRangeAt(int offset) {
    for (final token in _semanticTokens) {
      if (token.start <= offset && offset < token.end) {
        return (start: token.start, end: token.end);
      }
    }
    if (offset < 0 || offset > text.length) return null;
    var start = offset;
    var end = offset;
    while (start > 0 && _isIdentifierChar(text.codeUnitAt(start - 1))) {
      start--;
    }
    while (end < text.length && _isIdentifierChar(text.codeUnitAt(end))) {
      end++;
    }
    if (start == end) return null; // Vazio
    return (start: start, end: end);
  }

  static bool _isIdentifierChar(int codeUnit) {
    // [a-zA-Z0-9_]
    return (codeUnit >= 97 && codeUnit <= 122) || // a-z
        (codeUnit >= 65 && codeUnit <= 90) || // A-Z
        (codeUnit >= 48 && codeUnit <= 57) || // 0-9
        codeUnit == 95; // _
  }

  /// Converte offset pra {line, character} (base 0, LSP format).
  ({int line, int character}) offsetToLineChar(int offset) {
    if (offset < 0) return (line: 0, character: 0);
    if (offset > text.length) offset = text.length;
    var line = 0;
    var lineStart = 0;
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    final character = offset - lineStart;
    return (line: line, character: character);
  }

  ({int start, int end})? _definitionHoverRange;

  /// Range do identifier sob o mouse enquanto Cmd/Ctrl está pressionado (go-to-
  /// definition) — pintado com sublinhado sólido. `null` = nenhum hover ativo.
  ({int start, int end})? get definitionHoverRange => _definitionHoverRange;
  set definitionHoverRange(({int start, int end})? value) {
    if (value == _definitionHoverRange) return;
    _definitionHoverRange = value;
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

  // --- Memo do span pintado ------------------------------------------------
  // `buildTextSpan` roda toda vez que o EditableText reconstrói, e ele
  // reconstrói junto com QUALQUER `setState` do editor que o contém — trocar a
  // linha sob o mouse (tooltip de diagnostic), ganhar/perder foco, etc. Nesses
  // casos nada que afeta a pintura mudou, mas sem memo refazíamos o merge de
  // overlays sobre o arquivo INTEIRO (milhares de TextSpan alocados por
  // rebuild num arquivo de 5k linhas) e o `diagnosticRangesFor`, que varre o
  // texto todo. Guardar o último span + as entradas que o geraram torna esses
  // rebuilds de graça.
  //
  // O cache de parse léxico em `code_highlight.dart` é complementar, não
  // redundante: aquele evita re-tokenizar, este evita re-montar os spans.
  // --- Parse exato adiado durante digitação --------------------------------
  // O parse léxico é O(arquivo) (~47ms a 5k linhas) e cada tecla gera texto
  // novo → miss no cache → re-tokenizava tudo por caractere. Aqui, durante a
  // rajada de digitação reusamos o parse do último texto exato e remendamos só
  // a região editada ([buildApproximateCodeSpan]); o parse exato roda quando o
  // usuário para. Abaixo de [_kApproxMinChars] não vale — o parse já é barato e
  // seria complexidade sem ganho.
  static const int _kApproxMinChars = 32 * 1024;
  static const Duration _kExactParseDelay = Duration(milliseconds: 120);

  /// Último texto cujo span saiu de um parse **exato** (e cujas folhas devem
  /// estar no LRU do `code_highlight`, base pro remendo).
  String? _exactText;
  Timer? _exactTimer;

  /// Força o próximo `buildTextSpan` a parsear exato (o timer estourou).
  bool _wantExact = false;
  bool _disposed = false;

  void _scheduleExactParse() {
    _exactTimer?.cancel();
    _exactTimer = Timer(_kExactParseDelay, () {
      if (_disposed) return;
      _wantExact = true;
      // Invalida o memo: ele guarda o span APROXIMADO deste mesmo texto e o
      // devolveria de novo, engolindo o repaint exato.
      _cachedSpan = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _exactTimer?.cancel();
    super.dispose();
  }

  TextSpan? _cachedSpan;
  String? _cachedFor;
  TextStyle? _cachedStyle;
  Object? _cachedColors;
  List<LspDiagnostic>? _cachedDiagnostics;
  List<UnresolvedCodeVariable>? _cachedUnresolvedVariables;
  List<MatchSpan>? _cachedMatches;
  int? _cachedCurrentMatch;
  List<SemanticRange>? _cachedSemanticTokens;
  ({int start, int end})? _cachedHoverRange;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final colors = context.colors;
    // Identidade (não `==`) nas listas e no texto: elas só trocam de instância
    // quando de fato há conteúdo novo, e comparar item a item anularia o ganho.
    if (_cachedSpan != null &&
        identical(_cachedFor, text) &&
        _cachedStyle == style &&
        identical(_cachedColors, colors) &&
        identical(_cachedDiagnostics, _diagnostics) &&
        identical(_cachedUnresolvedVariables, _unresolvedVariables) &&
        identical(_cachedMatches, _matches) &&
        _cachedCurrentMatch == _currentMatch &&
        identical(_cachedSemanticTokens, _semanticTokens) &&
        _cachedHoverRange == _definitionHoverRange) {
      return _cachedSpan!;
    }

    final base = _exactText;
    // Caminho aproximado: texto mudou desde o último parse exato, arquivo é
    // grande, e não é o repaint pedido pelo timer. Remenda em vez de parsear.
    TextSpan? span;
    if (!_wantExact &&
        base != null &&
        !identical(base, text) &&
        text.length >= _kApproxMinChars) {
      span = buildApproximateCodeSpan(
        context,
        source: text,
        previousSource: base,
        language: language,
        baseStyle: style ?? const TextStyle(),
        diagnostics: _highlightRanges(text),
        matches: _matches,
        currentMatch: _currentMatch,
        matchColor: colors.warn.withValues(alpha: 0.28),
        currentMatchColor: colors.accent.withValues(alpha: 0.45),
        semanticTokens: _semanticTokens,
        underlineRange: _definitionHoverRange,
        underlineColor: colors.accent,
      );
      // Conseguiu aproximar → agenda o exato pro idle. Se falhou (folhas fora
      // do LRU, edição grande), cai no exato agora mesmo.
      if (span != null) _scheduleExactParse();
    }

    if (span == null) {
      _wantExact = false;
      _exactTimer?.cancel();
      span =
          buildCodeSpan(
            context,
            source: text,
            language: language,
            baseStyle: style ?? const TextStyle(),
            diagnostics: _highlightRanges(text),
            matches: _matches,
            currentMatch: _currentMatch,
            matchColor: colors.warn.withValues(alpha: 0.28),
            currentMatchColor: colors.accent.withValues(alpha: 0.45),
            semanticTokens: _semanticTokens,
            underlineRange: _definitionHoverRange,
            underlineColor: colors.accent,
          ) ??
          TextSpan(text: text, style: style);
      // Só o parse exato vira base pro próximo remendo.
      _exactText = text;
    }

    _cachedSpan = span;
    _cachedFor = text;
    _cachedStyle = style;
    _cachedColors = colors;
    _cachedDiagnostics = _diagnostics;
    _cachedUnresolvedVariables = _unresolvedVariables;
    _cachedMatches = _matches;
    _cachedCurrentMatch = _currentMatch;
    _cachedSemanticTokens = _semanticTokens;
    _cachedHoverRange = _definitionHoverRange;
    return span;
  }
}
