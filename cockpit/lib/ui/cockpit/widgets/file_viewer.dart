import 'dart:io';

import 'package:cockpit/domain/entities/file_view.dart';
import 'package:cockpit/ui/cockpit/widgets/agent_markdown.dart';
import 'package:cockpit/ui/cockpit/widgets/code_highlight.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Corpo do viewer read-only: markdown (gpt_markdown), texto puro, ou imagem.
class FileViewer extends StatelessWidget {
  const FileViewer({super.key, required this.view});
  final FileView view;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.panel,
      child: switch (view) {
        FileViewMarkdown(:final text) => _Scroll(child: AgentMarkdown(text)),
        FileViewText(:final text, :final language) => _TextView(
          text: text,
          language: language,
        ),
        FileViewImage(:final path) => _ImageView(path: path),
        FileViewUnsupported() => Center(
          child: Text(
            'Can\'t open this file.',
            style: context.typo.body.copyWith(color: colors.text3),
          ),
        ),
      },
    );
  }
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: child,
    );
  }
}

/// Visualizador read-only de texto/código com **gutter de número de linha** à
/// esquerda (fixo na horizontal) e **scroll horizontal** pro conteúdo quando a
/// linha é longa. O texto segue selecionável; os números, não.
class _TextView extends StatefulWidget {
  const _TextView({required this.text, this.language});

  final String text;

  /// Linguagem (extensão do arquivo) pro syntax highlight; `null` = sem dica.
  final String? language;

  @override
  State<_TextView> createState() => _TextViewState();
}

class _TextViewState extends State<_TextView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typo = context.typo;
    // O viewer de código segue o tema de **syntax** (fundo próprio), não o tema
    // do app — assim One Dark/Dracula ficam escuros mesmo no app em light. O
    // tamanho vem do `typo.mono` (configurável em Configurações → Código).
    final syntax = context.syntax;
    final codeStyle = typo.mono.copyWith(color: syntax.base);
    // Spans coloridos (highlight.js → tema). `null` quando não vale destacar
    // (sem linguagem / arquivo grande) → renderiza texto puro.
    final codeSpan = buildCodeSpan(
      context,
      source: widget.text,
      language: widget.language,
      baseStyle: codeStyle,
    );
    final numStyle = typo.mono.copyWith(
      color: syntax.base.withValues(alpha: 0.4),
    );

    // Conta linhas pelos '\n' (arquivo sem newline final = última linha conta;
    // arquivo vazio = 1 linha). Mesma métrica do código → gutter alinha 1:1.
    final lineCount = '\n'.allMatches(widget.text).length + 1;

    // Dois scrollbars aninhados: a barra **horizontal** envolve tudo, então fica
    // **pinada no rodapé do viewport** (não some ao fim do conteúdo). O scroll
    // horizontal é aninhado dentro do vertical (`depth == 1`), por isso o
    // `notificationPredicate` filtra por profundidade. A vertical fica na borda.
    return ColoredBox(
      color: syntax.background,
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        notificationPredicate: (notification) => notification.depth == 1,
        child: Scrollbar(
          controller: _vertical,
          child: SingleChildScrollView(
            controller: _vertical,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gutter — números à direita, fixo (não rola na horizontal).
                Padding(
                  padding: const EdgeInsets.only(left: 14, right: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 1; i <= lineCount; i++)
                        Text('$i', style: numStyle),
                    ],
                  ),
                ),
                Container(width: 1, color: syntax.base.withValues(alpha: 0.15)),
                // Código — rola na horizontal quando a linha estoura; selecionável.
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 14, right: 16),
                    child: codeSpan == null
                        ? SelectableText(widget.text, style: codeStyle)
                        : SelectableText.rich(codeSpan),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageView extends StatelessWidget {
  const _ImageView({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final file = File(path);
    final isSvg = path.toLowerCase().endsWith('.svg');
    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isSvg
              ? SvgPicture.file(file, fit: BoxFit.contain)
              : Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => Text(
                    'Could not load the image.',
                    style: context.typo.body.copyWith(color: colors.text3),
                  ),
                ),
        ),
      ),
    );
  }
}
