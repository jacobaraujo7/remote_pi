import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_response_folds.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Corpo da resposta com numeração de linhas e folds estruturais. A seleção
/// usa o editor em modo somente leitura; copiar/salvar no rodapé usa o texto
/// original, inclusive as linhas escondidas.
class HttpResponseCodeView extends StatefulWidget {
  const HttpResponseCodeView({
    super.key,
    required this.text,
    required this.language,
    required this.foldSyntax,
    required this.foldedStarts,
  });

  final String text;
  final String? language;
  final HttpResponseFoldSyntax? foldSyntax;
  final Set<int> foldedStarts;

  @override
  State<HttpResponseCodeView> createState() => _HttpResponseCodeViewState();
}

class _HttpResponseCodeViewState extends State<HttpResponseCodeView> {
  late final CodeEditingController _source;
  late final CodeEditingController _folded;
  late HttpResponseFolds _projection;
  final FocusNode _focus = FocusNode();
  ({int oldLine, int newLine, int tick})? _scrollAnchor;
  int _foldTick = 0;

  @override
  void initState() {
    super.initState();
    _projection = HttpResponseFolds.build(
      widget.text,
      widget.foldSyntax,
      widget.foldedStarts,
    );
    _source = CodeEditingController(
      text: widget.text,
      language: widget.language,
    );
    _folded = CodeEditingController(
      text: _projection.text,
      language: widget.language,
    );
  }

  @override
  void dispose() {
    _source.dispose();
    _folded.dispose();
    _focus.dispose();
    super.dispose();
  }

  static int _lineStart(String text, int line) {
    var offset = 0;
    for (var i = 0; i < line; i++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) return text.length;
      offset = next + 1;
    }
    return offset;
  }

  void _toggle(int sourceLine) {
    final oldLine = widget.foldedStarts.isEmpty
        ? sourceLine
        : _projection.visibleBySource[sourceLine] ?? 0;
    if (!widget.foldedStarts.remove(sourceLine)) {
      widget.foldedStarts.add(sourceLine);
    }
    _projection = HttpResponseFolds.build(
      widget.text,
      widget.foldSyntax,
      widget.foldedStarts,
    );
    _folded.text = _projection.text;
    final newLine = widget.foldedStarts.isEmpty
        ? sourceLine
        : _projection.visibleBySource[sourceLine] ?? 0;
    final target = widget.foldedStarts.isEmpty ? _source : _folded;
    target.selection = TextSelection.collapsed(
      offset: _lineStart(target.text, newLine),
    );
    _scrollAnchor = (oldLine: oldLine, newLine: newLine, tick: ++_foldTick);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final folded = widget.foldedStarts.isNotEmpty;
    return CodeEditor(
      controller: folded ? _folded : _source,
      focusNode: _focus,
      readOnly: true,
      compactGutter: true,
      scrollAnchor: _scrollAnchor,
      lineNumbers: folded ? _projection.lineNumbers : null,
      foldActions: {
        for (final sourceLine in _projection.foldEnds.keys)
          if (!folded || _projection.visibleBySource.containsKey(sourceLine))
            (folded
                ? _projection.visibleBySource[sourceLine]!
                : sourceLine): () =>
                _toggle(sourceLine),
      },
      foldedLines: {
        for (final sourceLine in widget.foldedStarts)
          if (_projection.visibleBySource.containsKey(sourceLine))
            _projection.visibleBySource[sourceLine]!,
      },
    );
  }
}
