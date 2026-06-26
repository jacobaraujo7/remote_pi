import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/material.dart'
    show
        Scrollbar,
        ScrollbarOrientation,
        TextField,
        InputDecoration,
        InputBorder,
        TextInputType;
import 'package:flutter/widgets.dart';

/// Área **editável** de código com gutter de número de linha — a contraparte
/// edit do `_TextView` (read-only) do file_viewer. Mesmo layout: um scroll
/// vertical externo embrulha `Row[gutter fixo, divisor, scroll horizontal(campo)]`.
/// O campo é um [EditableText] com `maxLines: null` (cresce até a altura total,
/// sem scroll interno) dentro de `IntrinsicWidth` + scroll horizontal, então a
/// linha longa **não quebra** e o gutter alinha 1:1 — igual ao viewer.
///
/// Não cuida de dirty/save: só edição + pintura. O dono ([FileViewer]) escuta o
/// [controller] para o estado sujo e dispara o save.
class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final CodeEditingController controller;
  final FocusNode focusNode;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    // Recontar linhas (gutter) a cada digitação que muda o nº de '\n'.
    widget.controller.addListener(_onChanged);
  }

  int _lineCount = 1;

  void _onChanged() {
    final n = '\n'.allMatches(widget.controller.text).length + 1;
    if (n != _lineCount && mounted) setState(() => _lineCount = n);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typo = context.typo;
    final syntax = context.syntax;
    final codeStyle = typo.mono.copyWith(color: syntax.base);
    final numStyle = typo.mono.copyWith(
      color: syntax.base.withValues(alpha: 0.4),
    );
    final lineCount = '\n'.allMatches(widget.controller.text).length + 1;
    _lineCount = lineCount;

    // Clicar em qualquer ponto do editor (gutter, padding, espaço abaixo da
    // última linha) foca o campo — como num editor de verdade. Cliques sobre o
    // próprio TextField ganham a arena de gestos e posicionam o cursor; os
    // demais caem aqui. `translucent` pra não roubar o tap do campo.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
      },
      child: ColoredBox(
        color: syntax.background,
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          notificationPredicate: (n) => n.depth == 1,
          child: Scrollbar(
            controller: _vertical,
            child: SingleChildScrollView(
              controller: _vertical,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Container(
                    width: 1,
                    color: syntax.base.withValues(alpha: 0.15),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Largura mínima = viewport (menos o padding H). Sem isso, o
                        // IntrinsicWidth colapsa o campo a ~0 quando o arquivo está
                        // vazio (recém-criado) → sem área pra clicar/digitar.
                        final minWidth = (constraints.maxWidth - 30).clamp(
                          0.0,
                          double.infinity,
                        );
                        return SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(left: 14, right: 16),
                          // `TextField` (e não `EditableText` cru) pra ganhar os
                          // gestos de seleção do desktop: arrastar com o mouse,
                          // duplo-clique, Cmd+A. O highlight vem do `buildTextSpan`
                          // do controller; a decoração é zerada (sem borda/fundo).
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: minWidth),
                            child: IntrinsicWidth(
                              child: TextField(
                                controller: widget.controller,
                                focusNode: widget.focusNode,
                                style: codeStyle,
                                cursorColor: syntax.base,
                                maxLines: null,
                                minLines: null,
                                // Scroll vertical é do contêiner externo; o campo
                                // cresce até a altura total (sem scroll interno) pra
                                // o gutter alinhar 1:1.
                                expands: false,
                                keyboardType: TextInputType.multiline,
                                decoration: const InputDecoration(
                                  isCollapsed: true,
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
