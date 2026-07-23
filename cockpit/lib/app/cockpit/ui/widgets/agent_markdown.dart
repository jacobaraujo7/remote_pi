import 'dart:async';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
// `gpt_markdown` é um pacote Material: estiliza headings/links/code via
// `Theme.of(context)` Material + uma `GptMarkdownThemeData` (ThemeExtension do
// Material). Sob `ShadcnApp` não há Theme Material → ele cai no ThemeData()
// claro (títulos escuros). Por isso embrulhamos só o markdown num Theme Material
// (prefixo `m.`) com as nossas cores. O resto do app segue shadcn.
import 'package:flutter/material.dart' as m;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/markdown_frontmatter.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Renderiza o Markdown (GFM + code) da resposta do agente, com a identidade
/// visual do Cockpit. Tolerante a markdown parcial (serve pro streaming).
class AgentMarkdown extends StatelessWidget {
  const AgentMarkdown(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    // Frontmatter YAML (agent.md / SKILL.md): split ANTES do render — feature
    // que morava no fork do gpt_markdown (PR #139, não absorvido upstream) e
    // foi portada pra cá quando voltamos ao pacote do pub.dev.
    final split = MarkdownFrontmatter.split(
      data.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    );
    final frontmatter = split.frontmatter;
    final body = frontmatter == null ? data : split.body.trim();
    final colors = context.colors;
    final typo = context.typo;
    final brightness = Theme.of(context).brightness;
    // Tema Material só pro gpt_markdown: headings/links/cores com a paleta do
    // Cockpit (senão o pacote usa o ThemeData() claro → títulos escuros). A
    // seleção de texto é provida pelos chamadores (transcript / file viewer),
    // que envolvem o scrollable num `SelectionArea` — assim o auto-scroll segue
    // o arraste da seleção.
    final base = brightness == Brightness.dark
        ? m.ThemeData.dark()
        : m.ThemeData.light();
    return m.Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          surface: colors.panel,
          onSurface: colors.text,
          onSurfaceVariant: colors.text2,
          error: colors.error,
        ),
        extensions: [
          GptMarkdownThemeData(
            brightness: brightness,
            h1: typo.display.copyWith(color: colors.text, fontSize: 22),
            h2: typo.display.copyWith(color: colors.text, fontSize: 18),
            h3: typo.title.copyWith(color: colors.text, fontSize: 16),
            h4: typo.title.copyWith(color: colors.text, fontSize: 14.5),
            h5: typo.title.copyWith(color: colors.text, fontSize: 13.5),
            h6: typo.title.copyWith(color: colors.text2, fontSize: 12.5),
            linkColor: colors.accentText,
            linkHoverColor: colors.accent,
            hrLineColor: colors.border2,
            highlightColor: colors.panel3,
          ),
        ],
      ),
      child: m.Column(
        mainAxisSize: m.MainAxisSize.min,
        crossAxisAlignment: m.CrossAxisAlignment.start,
        children: [
          if (frontmatter != null)
            MarkdownFrontmatterTable(
              frontmatter: frontmatter,
              style: typo.body.copyWith(color: colors.text),
            ),
          GptMarkdown(
            body,
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
        ],
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
                style: typo.mono.copyWith(color: colors.text, height: 1.5),
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
    return AppTooltip(
      message: 'Copy code',
      child: HoverTap(
        onTap: _copy,
        borderRadius: BorderRadius.circular(5),
        padding: const EdgeInsets.all(4),
        child: Icon(
          _copied ? Icons.check : Icons.copy,
          size: 14,
          color: _copied ? colors.ok : colors.text3,
        ),
      ),
    );
  }
}
