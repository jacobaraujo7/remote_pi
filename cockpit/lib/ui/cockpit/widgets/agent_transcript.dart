import 'dart:convert';
import 'dart:typed_data';

import 'package:cockpit/ui/cockpit/session/agent_entry.dart';
import 'package:cockpit/ui/cockpit/widgets/agent_markdown.dart';
import 'package:cockpit/ui/core/file_icons/file_icons.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';

/// Teto de largura do conteúdo do chat — em panes largas a conversa não estica
/// de ponta a ponta (folgado; alinhado à esquerda).
const double _kChatMaxWidth = 920;

/// Corpo do pane: o stream do agente (texto, raciocínio, tool calls, infos),
/// estilizado conforme o design (rp-p / rp-think / rp-tool / rp-usermsg).
class AgentTranscript extends StatelessWidget {
  const AgentTranscript({
    super.key,
    required this.entries,
    required this.controller,
    this.bottomPadding = 8,
  });

  final List<AgentEntry> entries;
  final ScrollController controller;

  /// Espaço extra no fim da lista para a conversa não ficar atrás do composer
  /// flutuante.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Mande um prompt para o agente começar.',
          style: context.typo.body.copyWith(color: context.colors.text3),
        ),
      );
    }
    // A scrollbar e a lista ocupam a largura inteira (scrollbar na borda do
    // pane); o **conteúdo** é centralizado com teto de largura via padding
    // horizontal calculado. Cada turno (pergunta do usuário + resposta) é uma
    // seção: a pergunta vira um **header sticky** que fica pinado no topo
    // enquanto a resposta rola, trocando ao chegar no próximo turno.
    return LayoutBuilder(
      builder: (context, constraints) {
        final extra = (constraints.maxWidth - _kChatMaxWidth) / 2;
        final hpad = extra > 26 ? extra : 26.0;
        final hPadding = EdgeInsets.symmetric(horizontal: hpad);
        final turns = _groupIntoTurns(entries);
        return Scrollbar(
          controller: controller,
          thumbVisibility: true,
          child: ScrollConfiguration(
            // Evita a scrollbar automática duplicar a nossa (sempre visível).
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: CustomScrollView(
              controller: controller,
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 26)),
                for (final turn in turns)
                  if (turn.header == null)
                    SliverPadding(
                      padding: hPadding,
                      sliver: _bodySliver(turn.body),
                    )
                  else
                    SliverStickyHeader.builder(
                      builder: (context, state) => Padding(
                        padding: hPadding,
                        child: _PinnedUserHeader(
                          entry: turn.header!,
                          pinned: state.isPinned,
                        ),
                      ),
                      sliver: SliverPadding(
                        padding: hPadding,
                        sliver: _bodySliver(turn.body),
                      ),
                    ),
                SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Agrupa as entradas em turnos: cada [UserEntry] abre um turno (header) e as
  /// entradas seguintes (até o próximo usuário) são o corpo. Entradas antes do
  /// primeiro usuário viram um turno sem header.
  List<({UserEntry? header, List<AgentEntry> body})> _groupIntoTurns(
    List<AgentEntry> entries,
  ) {
    final turns = <({UserEntry? header, List<AgentEntry> body})>[];
    UserEntry? header;
    var body = <AgentEntry>[];
    for (final entry in entries) {
      if (entry is UserEntry) {
        if (header != null || body.isNotEmpty) {
          turns.add((header: header, body: body));
        }
        header = entry;
        body = <AgentEntry>[];
      } else {
        body.add(entry);
      }
    }
    turns.add((header: header, body: body));
    return turns;
  }

  Widget _bodySliver(List<AgentEntry> body) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => _EntryView(key: ValueKey(body[i]), entry: body[i]),
        childCount: body.length,
      ),
    );
  }
}

/// Header sticky de um turno: a mensagem do usuário. Quando **pinada** ganha um
/// fundo opaco (mascara o conteúdo rolando atrás) + borda inferior; solta, é só
/// o balão normal (sem mudar de tamanho → sem "pulo").
class _PinnedUserHeader extends StatelessWidget {
  const _PinnedUserHeader({required this.entry, required this.pinned});
  final UserEntry entry;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = _UserMessage(text: entry.text, images: entry.images);
    if (!pinned) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: child,
    );
  }
}

class _EntryView extends StatelessWidget {
  const _EntryView({super.key, required this.entry});
  final AgentEntry entry;

  @override
  Widget build(BuildContext context) {
    return switch (entry) {
      UserEntry(:final text, :final images) => _UserMessage(
        text: text,
        images: images,
      ),
      AssistantTextEntry(:final text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: text.isEmpty
            ? Text(
                '…',
                style: context.typo.body.copyWith(
                  color: context.colors.text3,
                ),
              )
            : AgentMarkdown(text),
      ),
      ThinkingEntry(:final text) => _ThinkingBlock(text: text),
      ToolEntry() => _ToolCard(tool: entry as ToolEntry),
      InfoEntry(:final text, :final isError) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: context.typo.label.copyWith(
            color: isError ? context.colors.error : context.colors.text3,
          ),
        ),
      ),
      WorkedEntry(:final duration) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 13, color: context.colors.text3),
            const SizedBox(width: 7),
            Text(
              'Trabalhou por ${_formatWorked(duration)}',
              style: context.typo.label.copyWith(color: context.colors.text3),
            ),
          ],
        ),
      ),
    };
  }
}

/// Formata a duração de um turno: `12s` → `3m 05s` → `1h 02m`.
String _formatWorked(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  final m = d.inMinutes;
  if (m < 60) return '${m}m ${(s % 60).toString().padLeft(2, '0')}s';
  return '${d.inHours}h ${(m % 60).toString().padLeft(2, '0')}m';
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.text, this.images = const <Uint8List>[]});
  final String text;
  final List<Uint8List> images;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasText = text.trim().isNotEmpty;
    // Balão flexível (encolhe pro conteúdo), alinhado à **esquerda** e limitado
    // a 75% da largura da coluna. O padding no topo dá respiro quando vira
    // header pinado (não cola no topo). Imagens anexadas no topo.
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, constraints) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.75),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.panel2,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < images.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: (i < images.length - 1 || hasText) ? 8 : 0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: Image.memory(images[i], fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  if (hasText) _MessageText(text: text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Texto do balão do usuário com as menções `@<path>` viradas em badges (só o
/// nome + extensão do arquivo, com o ícone de tipo).
class _MessageText extends StatelessWidget {
  const _MessageText({required this.text});
  final String text;

  // `@` no começo ou após espaço (evita casar e-mails tipo `foo@bar.com`).
  static final RegExp _mention = RegExp(r'(?<![^\s])@(\S+)');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = context.typo.body.copyWith(fontSize: 13.5, color: colors.text);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _mention.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _FileBadge(name: _basename(m.group(1)!)),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }

  String _basename(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }
}

/// Badge inline de um arquivo mencionado: ícone de tipo + nome.extensão.
class _FileBadge extends StatelessWidget {
  const _FileBadge({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
      decoration: BoxDecoration(
        color: colors.panel3,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FileTypeIcon.file(name, size: 13),
          const SizedBox(width: 5),
          Text(
            name,
            style: context.typo.label.copyWith(fontSize: 12, color: colors.text),
          ),
        ],
      ),
    );
  }
}

/// Limite de altura do conteúdo expandido (raciocínio / resultado de tool);
/// passou disso, rola por dentro.
const double _kExpandMaxHeight = 240;

/// Caixa expansível: header clicável (com chevron) + corpo colapsável que,
/// quando aberto, respeita [_kExpandMaxHeight] e rola se ultrapassar.
class _Expandable extends StatefulWidget {
  const _Expandable({
    required this.header,
    required this.body,
    required this.canExpand,
    required this.decoration,
    this.bodyPadding = const EdgeInsets.fromLTRB(12, 0, 12, 10),
  });

  final Widget header;
  final Widget body;
  final bool canExpand;
  final BoxDecoration decoration;
  final EdgeInsets bodyPadding;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canExpand = widget.canExpand;
    return Container(
      width: double.infinity,
      decoration: widget.decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: canExpand
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(7),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Expanded(child: widget.header),
                  if (canExpand)
                    AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: colors.text3,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && canExpand)
            Padding(
              padding: widget.bodyPadding,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _kExpandMaxHeight),
                child: SingleChildScrollView(child: widget.body),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThinkingBlock extends StatelessWidget {
  const _ThinkingBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _Expandable(
        canExpand: text.trim().isNotEmpty,
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(7),
        ),
        bodyPadding: const EdgeInsets.fromLTRB(34, 0, 14, 12),
        header: Row(
          children: [
            Icon(Icons.psychology_outlined, size: 14, color: colors.text3),
            const SizedBox(width: 8),
            Text(
              'raciocínio',
              style: context.typo.label.copyWith(
                color: colors.text3,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        body: SelectableText(
          text,
          style: context.typo.body.copyWith(
            fontSize: 13,
            color: colors.text3,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool});
  final ToolEntry tool;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = tool.isError ? colors.error : colors.ok;
    final argsText = tool.args.isEmpty ? '' : jsonEncode(tool.args);
    final hasResult = tool.done && tool.resultText.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Expandable(
        canExpand: hasResult,
        decoration: BoxDecoration(
          color: colors.panel2,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(7),
        ),
        header: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tool.done
                    ? accent.withValues(alpha: 0.10)
                    : colors.accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: tool.done
                  ? Icon(
                      tool.isError ? Icons.close : Icons.check,
                      size: 14,
                      color: accent,
                    )
                  : SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: colors.accent,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Text(
              tool.toolName,
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                argsText,
                overflow: TextOverflow.ellipsis,
                style: context.typo.mono.copyWith(
                  fontSize: 12,
                  color: colors.text2,
                ),
              ),
            ),
          ],
        ),
        body: SelectableText(
          _clip(tool.resultText, 20000),
          style: context.typo.mono.copyWith(
            fontSize: 11.5,
            color: colors.text3,
          ),
        ),
      ),
    );
  }

  String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}\n… (truncado)';
}
