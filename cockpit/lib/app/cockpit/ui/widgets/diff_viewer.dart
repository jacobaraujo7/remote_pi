import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';
import 'package:cockpit/app/cockpit/ui/session/diff_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_path_breadcrumb.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Extensão (minúscula) de [path] para alimentar o syntax highlight, ou `null`
/// quando não há extensão reconhecível.
String? _languageOf(String path) {
  final special = filenameLanguageOf(path);
  if (special != null) return special;
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toLowerCase();
}

/// Visualizador de diff read-only em três modos. Os hunks vêm parseados na
/// [DiffViewerSession]; o conteúdo completo é carregado sob demanda.
class DiffViewer extends StatelessWidget {
  const DiffViewer({
    super.key,
    required this.session,
    required this.loadModifiedContent,
    this.displayPath,
  });

  final DiffViewerSession session;
  final Future<String> Function(DiffViewerSession) loadModifiedContent;

  /// Caminho relativo ao workspace, resolvido pelo dono da pane.
  final String? displayPath;

  @override
  Widget build(BuildContext context) {
    // Reconstrói quando o diff da sessão muda (preview reuse).
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _DiffBody(
              diff: session.diff,
              language: _languageOf(session.path),
              mode: session.viewMode,
              modifiedContent: session.modifiedContent,
              modifiedContentError: session.modifiedContentError,
              loadingModifiedContent: session.loadingModifiedContent,
            ),
          ),
          _DiffFooter(
            path: displayPath ?? session.path,
            fileName: session.title,
            mode: session.viewMode,
            onSelect: _selectMode,
          ),
        ],
      ),
    );
  }

  void _selectMode(DiffViewMode mode) {
    session.setViewMode(mode);
    if (mode != DiffViewMode.modifiedContent ||
        session.diff.kind == FileDiffKind.deleted ||
        session.diff.kind == FileDiffKind.binary ||
        session.modifiedContent != null ||
        session.loadingModifiedContent) {
      return;
    }
    final diff = session.diff;
    session.startModifiedContentLoad();
    loadModifiedContent(session)
        .then((content) {
          session.completeModifiedContentLoad(diff, content);
        })
        .catchError((Object error) {
          session.failModifiedContentLoad(diff, error);
        });
  }
}

class _DiffFooter extends StatelessWidget {
  const _DiffFooter({
    required this.path,
    required this.fileName,
    required this.mode,
    required this.onSelect,
  });

  final String path;
  final String fileName;
  final DiffViewMode mode;
  final ValueChanged<DiffViewMode> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: context.colors.bg,
      border: Border(top: BorderSide(color: context.colors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: FilePathBreadcrumb(path: path, fileName: fileName),
        ),
        const SizedBox(width: 8),
        Builder(
          builder: (anchor) => HoverTap(
            key: const Key('diff-view-mode-select'),
            onTap: () async {
              final selected = await showAppMenu<DiffViewMode>(
                anchor,
                items: [
                  for (final value in DiffViewMode.values)
                    AppMenuItem(
                      value: value,
                      label: _modeLabel(context, value),
                      selected: value == mode,
                    ),
                ],
              );
              if (selected != null) onSelect(selected);
            },
            border: Border.all(color: context.colors.border),
            borderRadius: BorderRadius.circular(4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_modeLabel(context, mode), style: context.typo.label),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down, size: 14),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

String _modeLabel(BuildContext context, DiffViewMode mode) {
  final tr = context.t.cockpit.fileTreePanel;
  return switch (mode) {
    DiffViewMode.sideBySide => tr.diffSideBySide,
    DiffViewMode.inline => tr.diffInline,
    DiffViewMode.modifiedContent => tr.diffModifiedContent,
  };
}

/// Largura mínima de cada coluna; linhas longas ampliam o conteúdo rolável.
const double _minSideWidth = 260;

/// Uma linha do split: lado esquerdo (antigo) e direito (novo), qualquer um pode
/// faltar (add só-direita, remove só-esquerda).
class _Row {
  const _Row({this.left, this.right});
  final DiffLine? left;
  final DiffLine? right;
}

// ---------------------------------------------------------------------------
// Item list — union selada de hunk-header e diff-row para o ListView.builder
// ---------------------------------------------------------------------------

sealed class _Item {}

final class _HunkHeaderItem extends _Item {
  _HunkHeaderItem(this.header);
  final String header;
}

final class _RowItem extends _Item {
  _RowItem(this.row);
  final _Row row;
}

/// Converte hunks em uma lista plana de [_Item]s (header + linhas pares).
/// Separado do widget para poder ser computado uma única vez por diff,
/// não a cada `build()`.
List<_Item> _buildDiffItems(List<DiffHunk> hunks) {
  final items = <_Item>[];
  for (final hunk in hunks) {
    items.add(_HunkHeaderItem(hunk.header));
    for (final row in _rowsOf(hunk)) {
      items.add(_RowItem(row));
    }
  }
  return items;
}

List<_Item> _inlineItems(List<DiffHunk> hunks) => [
  for (final hunk in hunks) ...[
    _HunkHeaderItem(hunk.header),
    for (final line in hunk.lines)
      _RowItem(
        line.kind == DiffLineKind.removed
            ? _Row(left: line)
            : _Row(right: line),
      ),
  ],
];

double _measuredSideWidth(BuildContext context, FileDiff diff) =>
    _measuredTextWidth(context, [
      for (final hunk in diff.hunks)
        for (final line in hunk.lines) line.text,
    ]);

double _measuredTextWidth(BuildContext context, Iterable<String> lines) {
  var longest = '';
  for (final line in lines) {
    if (line.length > longest.length) longest = line;
  }
  if (longest.isEmpty) return _minSideWidth;
  final painter = TextPainter(
    text: TextSpan(
      text: longest,
      style: context.typo.mono.copyWith(fontSize: 12.5),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width + 60;
  painter.dispose();
  return width.clamp(_minSideWidth, double.infinity);
}

/// Alinha as linhas de um hunk em pares esquerda/direita. Runs de removed são
/// zipados com os added seguintes (removed→left, added→right); sobras viram
/// linhas de um lado só; contexto aparece nos dois lados.
List<_Row> _rowsOf(DiffHunk hunk) {
  final rows = <_Row>[];
  final removed = <DiffLine>[];
  final added = <DiffLine>[];

  void flush() {
    final n = removed.length > added.length ? removed.length : added.length;
    for (var i = 0; i < n; i++) {
      rows.add(
        _Row(
          left: i < removed.length ? removed[i] : null,
          right: i < added.length ? added[i] : null,
        ),
      );
    }
    removed.clear();
    added.clear();
  }

  for (final line in hunk.lines) {
    switch (line.kind) {
      case DiffLineKind.removed:
        removed.add(line);
      case DiffLineKind.added:
        added.add(line);
      case DiffLineKind.context:
        flush();
        rows.add(_Row(left: line, right: line));
    }
  }
  flush();
  return rows;
}

// ---------------------------------------------------------------------------
// _DiffBody — StatefulWidget para cachear _items entre rebuilds
// ---------------------------------------------------------------------------

class _DiffBody extends StatefulWidget {
  const _DiffBody({
    required this.diff,
    required this.language,
    required this.mode,
    required this.modifiedContent,
    required this.modifiedContentError,
    required this.loadingModifiedContent,
  });

  final FileDiff diff;
  final String? language;
  final DiffViewMode mode;
  final String? modifiedContent;
  final String? modifiedContentError;
  final bool loadingModifiedContent;

  @override
  State<_DiffBody> createState() => _DiffBodyState();
}

class _DiffBodyState extends State<_DiffBody> {
  /// Lista plana de itens (hunk headers + rows). Recalculada só quando o diff
  /// muda, não a cada `build()`.
  late List<_Item> _items;
  late List<_Item> _inline;
  final ScrollController _horizontal = ScrollController();
  late final ScrollController _leftHorizontal;
  late final ScrollController _rightHorizontal;
  late final ScrollController _leftVertical;
  late final ScrollController _rightVertical;
  bool _syncingScroll = false;

  @override
  void dispose() {
    _horizontal.dispose();
    _leftHorizontal.dispose();
    _rightHorizontal.dispose();
    _leftVertical.dispose();
    _rightVertical.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _leftHorizontal = ScrollController();
    _rightHorizontal = ScrollController();
    _leftVertical = ScrollController();
    _rightVertical = ScrollController();
    _leftHorizontal.addListener(
      () => _syncScroll(_leftHorizontal, _rightHorizontal),
    );
    _rightHorizontal.addListener(
      () => _syncScroll(_rightHorizontal, _leftHorizontal),
    );
    _leftVertical.addListener(() => _syncScroll(_leftVertical, _rightVertical));
    _rightVertical.addListener(
      () => _syncScroll(_rightVertical, _leftVertical),
    );
    _items = _buildDiffItems(widget.diff.hunks);
    _inline = _inlineItems(widget.diff.hunks);
  }

  void _syncScroll(ScrollController source, ScrollController target) {
    if (_syncingScroll || !source.hasClients || !target.hasClients) return;
    if (!target.position.hasContentDimensions) return;
    final offset = source.offset.clamp(
      target.position.minScrollExtent,
      target.position.maxScrollExtent,
    );
    if ((target.offset - offset).abs() < 0.5) return;
    _syncingScroll = true;
    try {
      target.jumpTo(offset);
    } finally {
      _syncingScroll = false;
    }
  }

  @override
  void didUpdateWidget(_DiffBody old) {
    super.didUpdateWidget(old);
    if (!identical(old.diff, widget.diff)) {
      _items = _buildDiffItems(widget.diff.hunks);
      _inline = _inlineItems(widget.diff.hunks);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.diff;
    final language = widget.language;
    final colors = context.colors;

    if (diff.kind == FileDiffKind.binary) {
      return _messageBody(
        context,
        diff,
        context.t.cockpit.fileTreePanel.diffBinaryFile,
      );
    }
    if (diff.kind == FileDiffKind.error) {
      return _messageBody(
        context,
        diff,
        context.t.cockpit.fileTreePanel.diffError(
          detail: diff.errorDetail ?? '',
        ),
      );
    }
    if (diff.kind == FileDiffKind.unchanged || diff.hunks.isEmpty) {
      return _messageBody(
        context,
        diff,
        context.t.cockpit.fileTreePanel.diffNoChanges,
      );
    }

    if (widget.mode == DiffViewMode.modifiedContent) {
      if (diff.kind == FileDiffKind.deleted) {
        return _centered(
          context,
          context.t.cockpit.fileTreePanel.diffDeletedContent,
        );
      }
      if (widget.modifiedContentError case final error?) {
        return _centered(
          context,
          context.t.cockpit.fileTreePanel.diffError(detail: error),
        );
      }
      if (widget.loadingModifiedContent || widget.modifiedContent == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return _modifiedBody(context, widget.modifiedContent!);
    }
    if (widget.mode == DiffViewMode.sideBySide) {
      return _sideBySideBody(context, diff, language);
    }

    return ColoredBox(
      color: colors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avail = constraints.maxWidth;
          final measured = _measuredSideWidth(context, diff);
          // Inline tem dois gutters numéricos e o marcador +/- em vez de um.
          final width = avail.clamp(measured + 60, double.infinity);

          // Seleção contínua entre linhas (copiar blocos de código do diff).
          // Os números de linha ficam fora da seleção (SelectionContainer.disabled
          // em _Side). A SelectionArea fica DENTRO do scroll horizontal de
          // propósito: em volta dele a seleção escorrega ao rolar com Interface
          // size != 14 — ver [SelectableScroll].
          //
          // O scroll vertical é feito pelo ListView.builder, que virtualiza:
          // só os widgets visíveis (~30) são construídos, em vez de todos os N
          // do diff. Isso elimina a lentidão na abertura de diffs grandes.
          return _scrollable(
            width: width,
            child: SelectionArea(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: _inline.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _singleRevisionHeader(context, diff, width);
                  }
                  final item = _inline[i - 1];
                  return switch (item) {
                    _HunkHeaderItem(:final header) => _HunkHeader(
                      text: header,
                      width: width,
                    ),
                    _RowItem(:final row) => _Side(
                      line: row.left ?? row.right,
                      side: row.left?.kind == DiffLineKind.removed
                          ? _SideKind.old
                          : _SideKind.newSide,
                      lineNo: row.left?.oldLine ?? row.right?.newLine,
                      width: width,
                      language: language,
                      inline: true,
                    ),
                  };
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sideBySideBody(
    BuildContext context,
    FileDiff diff,
    String? language,
  ) {
    return ColoredBox(
      color: context.colors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = (constraints.maxWidth - 1) / 2;
          final contentWidth = viewportWidth.clamp(
            _measuredSideWidth(context, diff),
            double.infinity,
          );
          return Row(
            children: [
              Expanded(
                child: _sidePane(
                  context,
                  diff: diff,
                  side: _SideKind.old,
                  contentWidth: contentWidth,
                  horizontal: _leftHorizontal,
                  vertical: _leftVertical,
                  language: language,
                ),
              ),
              ColoredBox(
                color: context.colors.border,
                child: const SizedBox(width: 1),
              ),
              Expanded(
                child: _sidePane(
                  context,
                  diff: diff,
                  side: _SideKind.newSide,
                  contentWidth: contentWidth,
                  horizontal: _rightHorizontal,
                  vertical: _rightVertical,
                  language: language,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sidePane(
    BuildContext context, {
    required FileDiff diff,
    required _SideKind side,
    required double contentWidth,
    required ScrollController horizontal,
    required ScrollController vertical,
    required String? language,
  }) {
    final tr = context.t.cockpit.fileTreePanel;
    final ref = side == _SideKind.old
        ? diff.afterRevision == null
              ? 'HEAD'
              : diff.beforeRevision == null
              ? tr.diffEmptyTree
              : tr.diffOriginal(ref: _shortRef(diff.beforeRevision!))
        : diff.afterRevision == null
        ? tr.diffWorkingTree
        : tr.diffModified(ref: _shortRef(diff.afterRevision!));
    return Scrollbar(
      controller: horizontal,
      thumbVisibility: true,
      thickness: 12,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: contentWidth,
          child: SelectionArea(
            child: ListView.builder(
              controller: vertical,
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _items.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _RevisionSideHeader(text: ref, width: contentWidth);
                }
                final item = _items[i - 1];
                return switch (item) {
                  _HunkHeaderItem(:final header) => _HunkHeader(
                    text: header,
                    width: contentWidth,
                  ),
                  _RowItem(:final row) => SizedBox(
                    height: 22,
                    child: _Side(
                      line: side == _SideKind.old ? row.left : row.right,
                      side: side,
                      lineNo: side == _SideKind.old
                          ? row.left?.oldLine
                          : row.right?.newLine,
                      width: contentWidth,
                      language: language,
                    ),
                  ),
                };
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageBody(BuildContext context, FileDiff diff, String text) {
    if (diff.afterRevision == null) return _centered(context, text);
    return ColoredBox(
      color: context.colors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = (constraints.maxWidth - 1) / 2;
          return Column(
            children: [
              _revisionHeader(context, diff, side),
              Expanded(child: _centered(context, text)),
            ],
          );
        },
      ),
    );
  }

  Widget _modifiedBody(BuildContext context, String content) {
    final lines = content.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return ColoredBox(
      color: context.colors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.clamp(
            _measuredTextWidth(context, lines),
            double.infinity,
          );
          return _scrollable(
            width: width,
            child: SelectionArea(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: lines.length + 1,
                itemBuilder: (context, i) => i == 0
                    ? _singleRevisionHeader(
                        context,
                        widget.diff,
                        width,
                        modifiedOnly: true,
                      )
                    : _Side(
                        line: DiffLine(
                          kind: DiffLineKind.context,
                          text: lines[i - 1],
                          newLine: i,
                        ),
                        side: _SideKind.newSide,
                        lineNo: i,
                        width: width,
                        language: widget.language,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _scrollable({required double width, required Widget child}) =>
      Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        thickness: 12,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: width, child: child),
        ),
      );

  static Widget _singleRevisionHeader(
    BuildContext context,
    FileDiff diff,
    double width, {
    bool modifiedOnly = false,
  }) {
    final tr = context.t.cockpit.fileTreePanel;
    final before = diff.beforeRevision == null
        ? diff.afterRevision == null
              ? 'HEAD'
              : tr.diffEmptyTree
        : tr.diffOriginal(ref: _shortRef(diff.beforeRevision!));
    final after = diff.afterRevision == null
        ? tr.diffWorkingTree
        : tr.diffModified(ref: _shortRef(diff.afterRevision!));
    return _HunkHeader(
      text: modifiedOnly ? after : '$before → $after',
      width: width,
    );
  }

  static Widget _revisionHeader(
    BuildContext context,
    FileDiff diff,
    double sideWidth,
  ) {
    final tr = context.t.cockpit.fileTreePanel;
    final historical = diff.afterRevision != null;
    return _RevisionHeader(
      beforeRef: historical
          ? diff.beforeRevision == null
                ? tr.diffEmptyTree
                : tr.diffOriginal(ref: _shortRef(diff.beforeRevision!))
          : 'HEAD',
      afterRef: historical
          ? tr.diffModified(ref: _shortRef(diff.afterRevision!))
          : tr.diffWorkingTree,
      sideWidth: sideWidth,
    );
  }

  static Widget _centered(BuildContext context, String text) => Center(
    child: Text(
      text,
      style: context.typo.label.copyWith(color: context.colors.text3),
    ),
  );
}

String _shortRef(String ref) => ref.length <= 8 ? ref : ref.substring(0, 8);

class _RevisionHeader extends StatelessWidget {
  const _RevisionHeader({
    required this.beforeRef,
    required this.afterRef,
    required this.sideWidth,
  });

  final String beforeRef;
  final String afterRef;
  final double sideWidth;

  @override
  Widget build(BuildContext context) {
    final style = context.typo.mono.copyWith(
      fontSize: 10.5,
      color: context.colors.text2,
    );
    return Container(
      color: context.colors.panel,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: sideWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                beforeRef,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
          Container(width: 1, height: 18, color: context.colors.border),
          SizedBox(
            width: sideWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                afterRef,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HunkHeader extends StatelessWidget {
  const _HunkHeader({required this.text, required this.width});
  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: colors.panel3,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.typo.mono.copyWith(fontSize: 11.5, color: colors.text3),
      ),
    );
  }
}

class _RevisionSideHeader extends StatelessWidget {
  const _RevisionSideHeader({required this.text, required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 26,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    color: context.colors.panel,
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.typo.mono.copyWith(
        fontSize: 10.5,
        color: context.colors.text2,
      ),
    ),
  );
}

enum _SideKind { old, newSide }

class _Side extends StatelessWidget {
  const _Side({
    required this.line,
    required this.side,
    required this.lineNo,
    required this.width,
    required this.language,
    this.inline = false,
  });

  final DiffLine? line;
  final _SideKind side;
  final int? lineNo;
  final double width;
  final String? language;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;

    Color bg = Colors.transparent;
    final l = line;
    if (l != null && l.kind != DiffLineKind.context) {
      bg = side == _SideKind.old
          ? colors.gitDeleted.withValues(alpha: 0.14)
          : colors.gitStaged.withValues(alpha: 0.14);
    }

    final baseStyle = typo.mono.copyWith(fontSize: 12.5, color: colors.text);
    final text = l?.text ?? '';
    // Syntax highlight por linha (o highlight.js reseta estado a cada linha —
    // aceitável para diff). `null` → renderiza texto puro.
    final span = text.isEmpty
        ? null
        : buildCodeSpan(
            context,
            source: text,
            language: language,
            baseStyle: baseStyle,
          );

    Widget gutter(int? number, {String? column}) => SelectionContainer.disabled(
      child: Container(
        width: 44,
        padding: const EdgeInsets.only(right: 8, top: 1, bottom: 1),
        alignment: Alignment.centerRight,
        child: Text(
          number?.toString() ?? '',
          key: column != null && number != null
              ? ValueKey('diff-inline-$column-$number')
              : null,
          style: typo.mono.copyWith(fontSize: 11.5, color: colors.text4),
        ),
      ),
    );

    final marker = switch (l?.kind) {
      DiffLineKind.removed => '-',
      DiffLineKind.added => '+',
      _ => ' ',
    };

    return SizedBox(
      width: width,
      child: ColoredBox(
        color: bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Números e marcador ficam fora da seleção para copiar só o código.
            if (inline) ...[
              gutter(l?.oldLine, column: 'old'),
              gutter(l?.newLine, column: 'new'),
              SelectionContainer.disabled(
                child: SizedBox(
                  width: 16,
                  child: Text(
                    marker,
                    style: baseStyle.copyWith(
                      color: switch (l?.kind) {
                        DiffLineKind.removed => colors.gitDeleted,
                        DiffLineKind.added => colors.gitStaged,
                        _ => colors.text4,
                      },
                    ),
                  ),
                ),
              ),
            ] else
              gutter(lineNo),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: span == null
                    ? Text(
                        text,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: baseStyle,
                      )
                    : Text.rich(
                        span,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
