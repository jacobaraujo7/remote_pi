import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';
import 'package:cockpit/app/cockpit/ui/session/diff_viewer_session.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Extensão (minúscula) de [path] para alimentar o syntax highlight, ou `null`
/// quando não há extensão reconhecível.
String? _languageOf(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toLowerCase();
}

/// Visualizador de **diff** read-only, split (estilo VSCode): esquerda = versão
/// antiga (linhas removidas em vermelho), direita = nova (adicionadas em verde),
/// contexto nos dois lados. Sem ações — só leitura. O conteúdo vem parseado na
/// [DiffViewerSession].
class DiffViewer extends StatelessWidget {
  const DiffViewer({super.key, required this.session});

  final DiffViewerSession session;

  @override
  Widget build(BuildContext context) {
    // Reconstrói quando o diff da sessão muda (preview reuse).
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) =>
          _DiffBody(diff: session.diff, language: _languageOf(session.path)),
    );
  }
}

/// Largura mínima de cada coluna do split — abaixo disso, rola na horizontal.
const double _minSideWidth = 260;

/// Uma linha do split: lado esquerdo (antigo) e direito (novo), qualquer um pode
/// faltar (add só-direita, remove só-esquerda).
class _Row {
  const _Row({this.left, this.right});
  final DiffLine? left;
  final DiffLine? right;
}

class _DiffBody extends StatelessWidget {
  const _DiffBody({required this.diff, required this.language});

  final FileDiff diff;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (diff.kind == FileDiffKind.binary) {
      return _centered(context, 'Binary file — no text diff.');
    }
    if (diff.kind == FileDiffKind.unchanged || diff.hunks.isEmpty) {
      return _centered(context, 'No changes.');
    }

    final rows = <_Row>[];
    final headers = <int>{}; // índices onde começa um hunk (pra pintar header)
    final headerText = <int, String>{};
    for (final hunk in diff.hunks) {
      headers.add(rows.length);
      headerText[rows.length] = hunk.header;
      rows.addAll(_rowsOf(hunk));
    }

    return ColoredBox(
      color: colors.bg,
      // Seleção contínua entre linhas (copiar blocos de código do diff). Os
      // números de linha ficam fora da seleção (SelectionContainer.disabled).
      child: SelectionArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Cada coluna preenche metade da largura disponível, respeitando um
            // mínimo (abaixo do qual rola na horizontal).
            final avail = constraints.maxWidth;
            final side = ((avail - 1) / 2).clamp(
              _minSideWidth,
              double.infinity,
            );
            final total = side * 2 + 1;

            final children = <Widget>[];
            for (var i = 0; i < rows.length; i++) {
              final hdr = headerText[i];
              if (hdr != null) {
                children.add(_HunkHeader(text: hdr, width: total));
              }
              children.add(
                _DiffRow(row: rows[i], sideWidth: side, language: language),
              );
            }

            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: total,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _centered(BuildContext context, String text) => Center(
    child: Text(
      text,
      style: context.typo.label.copyWith(color: context.colors.text3),
    ),
  );

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

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.row,
    required this.sideWidth,
    required this.language,
  });
  final _Row row;
  final double sideWidth;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Side(
            line: row.left,
            side: _SideKind.old,
            lineNo: row.left?.oldLine,
            width: sideWidth,
            language: language,
          ),
          Container(width: 1, color: colors.border),
          _Side(
            line: row.right,
            side: _SideKind.newSide,
            lineNo: row.right?.newLine,
            width: sideWidth,
            language: language,
          ),
        ],
      ),
    );
  }
}

enum _SideKind { old, newSide }

class _Side extends StatelessWidget {
  const _Side({
    required this.line,
    required this.side,
    required this.lineNo,
    required this.width,
    required this.language,
  });

  final DiffLine? line;
  final _SideKind side;
  final int? lineNo;
  final double width;
  final String? language;

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

    return SizedBox(
      width: width,
      child: ColoredBox(
        color: bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gutter de número de linha — fora da seleção (não polui o copy).
            SelectionContainer.disabled(
              child: Container(
                width: 44,
                padding: const EdgeInsets.only(right: 8, top: 1, bottom: 1),
                alignment: Alignment.centerRight,
                child: Text(
                  lineNo?.toString() ?? '',
                  style: typo.mono.copyWith(
                    fontSize: 11.5,
                    color: colors.text4,
                  ),
                ),
              ),
            ),
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
