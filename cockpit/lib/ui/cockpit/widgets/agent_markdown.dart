import 'dart:async';

import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Renderiza o Markdown (GFM + code) da resposta do agente, com a identidade
/// visual do Cockpit. Tolerante a markdown parcial (serve pro streaming).
class AgentMarkdown extends StatelessWidget {
  const AgentMarkdown(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    // `SelectionArea` torna todo o texto renderizado (corpo, code inline e os
    // blocos ```) selecionável com o mouse — vale pro agente e pro file viewer,
    // que compartilham este widget.
    return SelectionArea(
      child: GptMarkdown(
        data,
        style: typo.body.copyWith(color: colors.text),
        // `code` inline — fundo sutil, mono.
        highlightBuilder: (context, text, style) => Text(
          text,
          style: typo.mono.copyWith(
            fontSize: 12,
            color: colors.text,
            backgroundColor: colors.panel3,
          ),
        ),
        // Blocos ``` — card escuro com header (linguagem + copiar).
        codeBuilder: (context, name, code, closed) =>
            _CodeBlock(language: name, code: code),
      ),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.language, required this.code});

  final String language;
  final String code;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  // Controller próprio pra a Scrollbar horizontal ficar sempre visível
  // (thumbVisibility exige um controller compartilhado com o scroll view).
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language.isEmpty
                        ? 'code'
                        : widget.language.toUpperCase(),
                    style: typo.mono.copyWith(
                      fontSize: 10,
                      color: colors.text3,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                _CopyButton(code: widget.code),
              ],
            ),
          ),
          // Scroll horizontal com barra **sempre visível** pra código que
          // estoura a largura (linhas longas) — antes a barra não aparecia.
          Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Text(
                widget.code,
                style: typo.mono.copyWith(
                  color: colors.text,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.code});
  final String code;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      iconSize: 14,
      tooltip: 'Copy code',
      onPressed: _copy,
      icon: Icon(
        _copied ? Icons.check : Icons.copy,
        color: _copied ? colors.ok : colors.text3,
      ),
    );
  }
}
