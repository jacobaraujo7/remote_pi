import 'package:cockpit/app/cockpit/domain/entities/layout_spec.dart';
import 'package:cockpit/app/cockpit/domain/services/ckp_layout_parser.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Uma opção do botão Apply: um rótulo já traduzido e o que fazer.
class LayoutApplyAction {
  const LayoutApplyAction({required this.label, required this.onApply});

  /// Texto do botão / do item de menu (ex.: "Apply to notebox").
  final String label;

  final VoidCallback onApply;
}

/// Viewer de um arquivo `.ckp` (layout de panes): mostra **o que o layout vai
/// fazer** antes de fazer.
///
/// Por que preview e não execução direta: aplicar um layout fecha as abas do
/// workspace de destino, e cada pane carrega um `command` que roda no shell.
/// Um `.ckp` é, na prática, um arquivo de comandos — abrir um que chegou de
/// fora (baixado, clonado, mandado por alguém) tem que ser inspecionar, nunca
/// executar. Por isso o duplo clique no Finder/Explorer abre esta tela, e
/// quem executa é o botão Apply, com o destino escrito nele.
///
/// Serve nos dois hosts: na aba do app e na janela de documento. O que muda é
/// só o [primary]/[alternatives] que o chamador monta.
class LayoutPreviewView extends StatelessWidget {
  const LayoutPreviewView({
    super.key,
    required this.path,
    required this.source,
    required this.hostOs,
    required this.primary,
    this.alternatives = const [],
  });

  /// Caminho absoluto do `.ckp` — a âncora dos `cwd` do layout.
  final String path;

  /// Conteúdo do arquivo (o viewer parseia o texto que a sessão já tem; não
  /// lê o disco).
  final String source;

  /// `Platform.operatingSystem` — filtra `platforms`. Parâmetro (e não leitura
  /// direta) porque widget não faz IO e o teste precisa fixar o SO.
  final String hostOs;

  /// Ação principal do botão.
  final LayoutApplyAction primary;

  /// Outros destinos, no menu ao lado do botão. Vazio = sem menu.
  final List<LayoutApplyAction> alternatives;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final parsed = CkpLayoutParser(
      hostOs,
    ).parse(source, name: layoutNameOf(path));

    return ColoredBox(
      color: colors.panel,
      child: Column(
        children: [
          Expanded(
            child: switch (parsed) {
              Success(:final value) => _LayoutBody(spec: value, dir: _dir),
              // Arquivo inválido: o erro do parser E o texto cru. Nunca uma
              // tela vazia — sem o conteúdo não dá para consertar o arquivo.
              Failure(:final error) => _InvalidBody(
                error: error,
                source: source,
              ),
            },
          ),
          _ApplyBar(
            primary: primary,
            alternatives: alternatives,
            enabled: parsed is Success<LayoutSpec, String>,
          ),
        ],
      ),
    );
  }

  /// Pasta do `.ckp`: é contra ela que os `cwd` são resolvidos (o mesmo
  /// `_dirname(ckpPath)` que o runner passa ao aplicar).
  String get _dir {
    final i = path.lastIndexOf(RegExp(r'[/\\]'));
    return i <= 0 ? path : path.substring(0, i);
  }
}

class _LayoutBody extends StatelessWidget {
  const _LayoutBody({required this.spec, required this.dir});

  final LayoutSpec spec;
  final String dir;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.layoutPreview;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        Text(spec.name, style: typo.title),
        const SizedBox(height: 4),
        Text(
          tr.subtitle(n: spec.panes.length),
          style: typo.body.copyWith(color: colors.text3),
        ),
        if (spec.autorunWorktree) ...[
          const SizedBox(height: 10),
          _Note(text: tr.autorunWorktree),
        ],
        const SizedBox(height: 16),
        for (final (i, pane) in spec.panes.indexed)
          _PaneCard(index: i, pane: pane, dir: dir),
        if (spec.skippedByPlatform.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            tr.skippedTitle,
            style: typo.label.copyWith(color: colors.text3),
          ),
          const SizedBox(height: 8),
          for (final (i, pane) in spec.skippedByPlatform.indexed)
            _PaneCard(index: i, pane: pane, dir: dir, skipped: true),
        ],
      ],
    );
  }
}

/// Um pane do layout: nome, onde nasce, pasta resolvida e — o que mais
/// importa — o comando que vai rodar.
class _PaneCard extends StatelessWidget {
  const _PaneCard({
    required this.index,
    required this.pane,
    required this.dir,
    this.skipped = false,
  });

  final int index;
  final LayoutPane pane;
  final String dir;
  final bool skipped;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.layoutPreview;

    final splitLabel = switch (pane.split) {
      LayoutSplit.tab => tr.splitTab,
      LayoutSplit.right => tr.splitRight,
      LayoutSplit.down => tr.splitDown,
    };

    return Opacity(
      opacity: skipped ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.panel2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${index + 1}',
                  style: typo.mono.copyWith(color: colors.text3, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pane.name,
                    style: typo.label.copyWith(color: colors.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _Badge(text: splitLabel),
                if (skipped) ...[
                  const SizedBox(width: 6),
                  _Badge(text: pane.platforms.join(', ')),
                ],
              ],
            ),
            const SizedBox(height: 8),
            _Field(label: tr.folder, value: _resolvedCwd, mono: true),
            const SizedBox(height: 4),
            _Field(
              label: tr.command,
              value: pane.command ?? tr.noCommand,
              mono: pane.command != null,
              emphasis: pane.command != null,
            ),
          ],
        ),
      ),
    );
  }

  /// `cwd` do pane resolvido contra a pasta do arquivo, que é exatamente o que
  /// o runner faz ao aplicar. Mostrar o caminho final (e não o relativo do
  /// YAML) é o que deixa visível quando um layout vai abrir terminais numa
  /// pasta que não é a que a pessoa imaginava.
  String get _resolvedCwd {
    final cwd = pane.cwd.trim();
    if (cwd.isEmpty || cwd == '.' || cwd == './') return dir;
    final clean = cwd.startsWith('./') ? cwd.substring(2) : cwd;
    return '$dir/$clean';
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.mono = false,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool mono;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: typo.body.copyWith(color: colors.text3, fontSize: 12),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: (mono ? typo.mono : typo.body).copyWith(
              fontSize: 12,
              color: emphasis ? colors.text : colors.text2,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        text,
        style: context.typo.mono.copyWith(fontSize: 10, color: colors.text3),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        text,
        style: context.typo.body.copyWith(fontSize: 12, color: colors.text2),
      ),
    );
  }
}

/// `.ckp` que não parseia: mensagem do parser + o arquivo como está.
class _InvalidBody extends StatelessWidget {
  const _InvalidBody({required this.error, required this.source});

  final String error;
  final String source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.panel2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.error),
          ),
          child: Text(
            error,
            style: typo.body.copyWith(color: colors.error, fontSize: 12),
          ),
        ),
        const SizedBox(height: 14),
        SelectableText(
          source,
          style: typo.mono.copyWith(fontSize: 12, color: colors.text2),
        ),
      ],
    );
  }
}

/// Rodapé com o botão Apply. O destino está **escrito no botão**; os outros
/// destinos ficam no menu ao lado, e nunca há um destino implícito.
class _ApplyBar extends StatelessWidget {
  const _ApplyBar({
    required this.primary,
    required this.alternatives,
    required this.enabled,
  });

  final LayoutApplyAction primary;
  final List<LayoutApplyAction> alternatives;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          const Spacer(),
          if (alternatives.isNotEmpty) ...[
            Builder(
              builder: (anchor) => HoverTap(
                borderRadius: BorderRadius.circular(5),
                onTap: enabled ? () => _chooseOther(anchor) : null,
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Icon(Icons.more_horiz, size: 16, color: colors.text2),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          PrimaryButton(
            onPressed: enabled ? primary.onApply : null,
            child: Text(primary.label),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseOther(BuildContext anchor) async {
    final action = await showAppMenu<LayoutApplyAction>(
      anchor,
      items: [
        for (final a in alternatives) AppMenuItem(value: a, label: a.label),
      ],
    );
    action?.onApply();
  }
}
