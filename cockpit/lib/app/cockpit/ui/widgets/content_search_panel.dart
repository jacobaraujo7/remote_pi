import 'dart:async';

import 'package:cockpit/app/cockpit/domain/entities/content_search.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Assinatura da busca por conteúdo (injetada pela página → VM).
typedef ContentSearchFn =
    Stream<FileMatches> Function(
      String term, {
      bool caseSensitive,
      bool wholeWord,
      bool regex,
    });

/// Painel de **find-in-files** fixado no rodapé da coluna de arquivos
/// (Cmd+Shift+F). Campo + toggles Aa/ab/.* e resultados agrupados por arquivo,
/// com highlight dos matches. Clicar numa linha abre o arquivo na linha (via
/// [onOpenResult]). A busca é incremental (stream) e com debounce.
class ContentSearchPanel extends StatefulWidget {
  const ContentSearchPanel({
    super.key,
    required this.search,
    required this.onOpenResult,
    required this.focusSignal,
    this.fill = false,
    this.resultsHeight = 0,
    this.onResizeDelta,
    this.onResizeEnd,
  });

  final ContentSearchFn search;

  /// Abre o resultado: caminho relativo + linha (base 1).
  final void Function(String relativePath, int line) onOpenResult;

  /// Sobe a cada Cmd+Shift+F → foca o campo (e expande o painel).
  final ValueListenable<int> focusSignal;

  /// `true` = aba de busca (ocupa toda a área do painel: sem alça de arraste,
  /// resultados em [Expanded]). `false` = modo rodapé fixo (alça + altura fixa).
  final bool fill;

  /// Altura (px) da área de resultados — controlada/persistida pela página.
  /// Ignorada quando [fill] é `true`.
  final double resultsHeight;

  /// Arraste da alça superior (dy bruto; a página inverte/clampa e persiste).
  /// Null em modo [fill].
  final ValueChanged<double>? onResizeDelta;

  /// Fim do arraste → a página persiste a altura final. Null em modo [fill].
  final VoidCallback? onResizeEnd;

  @override
  State<ContentSearchPanel> createState() => _ContentSearchPanelState();
}

class _ContentSearchPanelState extends State<ContentSearchPanel> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _regex = false;

  Timer? _debounce;
  StreamSubscription<FileMatches>? _sub;
  final List<FileMatches> _results = <FileMatches>[];
  final Set<String> _collapsed = <String>{};
  bool _searching = false;
  bool _invalidRegex = false;

  @override
  void initState() {
    super.initState();
    widget.focusSignal.addListener(_onFocusSignal);
  }

  @override
  void dispose() {
    widget.focusSignal.removeListener(_onFocusSignal);
    _debounce?.cancel();
    _sub?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusSignal() {
    _focus.requestFocus();
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _ctrl.text.length,
    );
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _runSearch);
  }

  void _toggle(void Function() mutate) {
    setState(mutate);
    _runSearch(); // toggle re-dispara já (sem debounce)
  }

  void _runSearch() {
    _sub?.cancel();
    final term = _ctrl.text;
    setState(() {
      _results.clear();
      _collapsed.clear();
      _invalidRegex = false;
      _searching = term.trim().isNotEmpty;
    });
    if (term.trim().isEmpty) return;

    _sub =
        widget
            .search(
              term,
              caseSensitive: _caseSensitive,
              wholeWord: _wholeWord,
              regex: _regex,
            )
            .listen(
              (file) {
                if (!mounted) return;
                setState(() => _results.add(file));
              },
              onError: (_) {
                if (!mounted) return;
                setState(() {
                  _invalidRegex = _regex;
                  _searching = false;
                });
              },
              onDone: () {
                if (!mounted) return;
                setState(() => _searching = false);
              },
            );
  }

  int get _totalMatches =>
      _results.fold(0, (sum, f) => sum + f.matchCount);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Aba (fill): ocupa a área toda, sem alça nem borda-topo; resultados
    // expandem. Rodapé: alça de arraste + altura fixa dos resultados.
    if (widget.fill) {
      return Column(
        children: [
          _header(context),
          _field(context),
          Expanded(child: _resultsList(context)),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _resizeHandle(context),
          _header(context),
          _field(context),
          SizedBox(
            height: widget.resultsHeight,
            child: _resultsList(context),
          ),
        ],
      ),
    );
  }

  /// Alça de arraste no topo do painel: arrastar pra cima aumenta a área de
  /// resultados; pra baixo diminui. A página clampa e persiste.
  Widget _resizeHandle(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (d) => widget.onResizeDelta?.call(d.delta.dy),
        onVerticalDragEnd: (_) => widget.onResizeEnd?.call(),
        child: SizedBox(
          height: 9,
          child: Center(
            child: Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: Row(
        children: [
          Text(
            'SEARCH',
            style: typo.label.copyWith(
              fontSize: 10,
              letterSpacing: 1.1,
              color: colors.text3,
            ),
          ),
          const SizedBox(width: 8),
          if (_ctrl.text.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: colors.panel2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_totalMatches in ${_results.length}',
                style: typo.label.copyWith(fontSize: 10.5, color: colors.text3),
              ),
            ),
          const Spacer(),
          if (_searching)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(size: 12),
            ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  _ctrl.clear();
                  _runSearch();
                },
              },
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                placeholder: Text(
                  'Search in files',
                  style: context.typo.body.copyWith(
                    fontSize: 13,
                    color: colors.text4,
                  ),
                ),
                style: context.typo.body.copyWith(
                  fontSize: 13,
                  color: colors.text,
                ),
                border: Border.all(
                  color: _invalidRegex ? colors.error : colors.border,
                ),
                borderRadius: BorderRadius.circular(6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                onChanged: (_) => _onQueryChanged(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _OptionToggle(
            label: 'Aa',
            tooltip: 'Match case',
            active: _caseSensitive,
            onTap: () => _toggle(() => _caseSensitive = !_caseSensitive),
          ),
          _OptionToggle(
            label: 'ab',
            tooltip: 'Whole word',
            active: _wholeWord,
            underline: true,
            onTap: () => _toggle(() => _wholeWord = !_wholeWord),
          ),
          _OptionToggle(
            label: '.*',
            tooltip: 'Use regular expression',
            active: _regex,
            onTap: () => _toggle(() => _regex = !_regex),
          ),
        ],
      ),
    );
  }

  Widget _resultsList(BuildContext context) {
    final colors = context.colors;
    if (_results.isEmpty) {
      final hasQuery = _ctrl.text.trim().isNotEmpty;
      final String message;
      if (_invalidRegex) {
        message = 'Invalid regular expression.';
      } else if (!hasQuery) {
        message = 'Type to search across files.';
      } else if (_searching) {
        message = 'Searching…';
      } else {
        message = 'No results.';
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            message,
            style: context.typo.label.copyWith(
              color: _invalidRegex ? colors.error : colors.text4,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _results.length,
      itemBuilder: (context, i) => _fileGroup(context, _results[i]),
    );
  }

  Widget _fileGroup(BuildContext context, FileMatches file) {
    final colors = context.colors;
    final typo = context.typo;
    final collapsed = _collapsed.contains(file.relativePath);
    final name = file.relativePath.split('/').last;
    final dir = file.relativePath.contains('/')
        ? file.relativePath.substring(0, file.relativePath.lastIndexOf('/'))
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoverTap(
          hoverColor: colors.panel,
          borderRadius: BorderRadius.circular(5),
          onTap: () => setState(() {
            if (collapsed) {
              _collapsed.remove(file.relativePath);
            } else {
              _collapsed.add(file.relativePath);
            }
          }),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Icon(
                collapsed ? Icons.chevron_right : Icons.keyboard_arrow_down,
                size: 15,
                color: colors.text4,
              ),
              const SizedBox(width: 2),
              FileTypeIcon.file(name, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: typo.body.copyWith(fontSize: 12.5, color: colors.text),
                ),
              ),
              if (dir.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    dir,
                    overflow: TextOverflow.ellipsis,
                    style: typo.label.copyWith(fontSize: 11, color: colors.text4),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.panel2,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${file.matchCount}',
                  style: typo.label.copyWith(fontSize: 10, color: colors.text3),
                ),
              ),
            ],
          ),
        ),
        if (!collapsed)
          for (final line in file.matches)
            _matchRow(context, file.relativePath, line),
      ],
    );
  }

  Widget _matchRow(BuildContext context, String relativePath, LineMatch line) {
    final colors = context.colors;
    final typo = context.typo;
    final numStyle = typo.mono.copyWith(
      fontSize: 11.5,
      color: colors.text4,
    );
    final baseStyle = typo.mono.copyWith(fontSize: 11.5, color: colors.text2);

    return HoverTap(
      hoverColor: colors.panel,
      onTap: () => widget.onOpenResult(relativePath, line.lineNumber),
      padding: const EdgeInsets.only(left: 14, right: 8, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${line.lineNumber}',
              textAlign: TextAlign.right,
              style: numStyle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              _highlightSpan(line, baseStyle, colors),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói os spans da linha, destacando os intervalos casados.
  TextSpan _highlightSpan(
    LineMatch line,
    TextStyle base,
    AppColors colors,
  ) {
    final text = line.text;
    final spans = <TextSpan>[];
    var cursor = 0;
    final hlStyle = base.copyWith(
      color: colors.text,
      backgroundColor: colors.warn.withValues(alpha: 0.28),
      fontWeight: FontWeight.w600,
    );
    for (final r in line.ranges) {
      final start = r.start.clamp(0, text.length);
      final end = r.end.clamp(start, text.length);
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start), style: base));
      }
      spans.add(TextSpan(text: text.substring(start, end), style: hlStyle));
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: base));
    }
    return TextSpan(children: spans);
  }
}

/// Toggle compacto (Aa / ab / .*) do painel de busca.
class _OptionToggle extends StatelessWidget {
  const _OptionToggle({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.underline = false,
  });

  final String label;
  final String tooltip;
  final bool active;
  final bool underline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.accent.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: context.typo.mono.copyWith(
              fontSize: 11.5,
              color: active ? colors.accentText : colors.text3,
              decoration: underline ? TextDecoration.underline : null,
            ),
          ),
        ),
      ),
    );
  }
}
