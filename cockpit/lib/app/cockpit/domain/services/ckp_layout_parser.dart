import 'package:cockpit/app/cockpit/domain/entities/layout_spec.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:yaml/yaml.dart';

/// Parser **puro** do `.ckp` (o YAML de orquestração de panes): texto entra,
/// [LayoutSpec] sai. Sem IO — quem lê o arquivo é o `CkpLayoutLoader` (data),
/// e o viewer de layout parseia o conteúdo que a sessão já tem em memória.
///
/// Valida com mensagens legíveis: o layout é ação explícita do usuário, e
/// erro nunca é silencioso.
///
/// Regras de portabilidade do `cwd`: **relativo à pasta do arquivo** e com
/// `/` — absolutos e `\` são rejeitados pra garantir que o mesmo arquivo
/// commitado rode em macOS, Linux e Windows.
class CkpLayoutParser {
  const CkpLayoutParser(this.hostOs);

  /// SO usado no filtro de `platforms` (`Platform.operatingSystem`).
  final String hostOs;

  /// [name] é o nome do layout (basename do arquivo sem extensão).
  Result<LayoutSpec, String> parse(String source, {required String name}) {
    final Object? doc;
    try {
      doc = loadYaml(source);
    } on YamlException catch (e) {
      return Failure('invalid YAML: ${e.message}');
    }
    if (doc is! Map) return const Failure('layout must be a YAML mapping');

    final rawPanes = doc['panes'];
    if (rawPanes is! List || rawPanes.isEmpty) {
      return const Failure('layout needs a non-empty "panes" list');
    }

    final autorun = doc['autorun'];
    if (autorun != null && autorun != 'worktree') {
      return Failure('invalid autorun "$autorun" (only "worktree" exists)');
    }

    final panes = <LayoutPane>[];
    final skipped = <LayoutPane>[];
    final seen = <String>{};
    for (final (i, raw) in rawPanes.indexed) {
      if (raw is! Map) return Failure('panes[$i] must be a mapping');
      final parsed = _parsePane(raw, i);
      switch (parsed) {
        case Failure(:final error):
          return Failure(error);
        case Success(:final value):
          if (!seen.add(value.name.toLowerCase())) {
            return Failure('duplicated pane name "${value.name}"');
          }
          // Pane de outro SO sai da lista aplicável, mas continua visível no
          // preview: "este arquivo tem um pane que não roda aqui" é
          // informação, não ruído.
          (_visibleOnThisOs(value.platforms) ? panes : skipped).add(value);
      }
    }

    return Success(
      LayoutSpec(
        name: name,
        autorunWorktree: autorun == 'worktree',
        panes: panes,
        skippedByPlatform: skipped,
      ),
    );
  }

  Result<LayoutPane, String> _parsePane(Map<dynamic, dynamic> m, int i) {
    final name = m['name'];
    if (name is! String || name.trim().isEmpty) {
      return Failure('panes[$i] needs a non-empty "name"');
    }

    final cwd = m['cwd'] ?? '.';
    if (cwd is! String) return Failure('panes[$i].cwd must be a string');
    if (cwd.contains(r'\')) {
      return Failure(
        'panes[$i].cwd: use forward slashes ("/") — backslashes break the '
        'file on other OSes',
      );
    }
    if (cwd.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(cwd)) {
      return Failure(
        'panes[$i].cwd must be relative to the .ckp file (absolute paths '
        'are not portable across machines)',
      );
    }

    final LayoutSplit split;
    switch (m['split']) {
      case null || 'tab':
        split = LayoutSplit.tab;
      case 'right':
        split = LayoutSplit.right;
      case 'down':
        split = LayoutSplit.down;
      case final other:
        return Failure(
          'panes[$i].split: invalid "$other" (use tab, right or down)',
        );
    }

    final command = m['command'];
    if (command != null && command is! String) {
      return Failure('panes[$i].command must be a string');
    }

    return Success(
      LayoutPane(
        name: name.trim(),
        cwd: cwd,
        split: split,
        command: (command as String?)?.trim(),
        platforms: _platforms(m['platforms']),
      ),
    );
  }

  /// Mesma semântica do `platforms` do tasks.json: string ou lista de
  /// `macos|windows|linux`; ausente/tipo errado → todos.
  List<String> _platforms(Object? v) {
    if (v is String) return [v];
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }

  bool _visibleOnThisOs(List<String> platforms) =>
      platforms.isEmpty || platforms.any((p) => p.toLowerCase() == hostOs);
}

/// Nome do layout a partir do caminho do arquivo (basename sem extensão).
String layoutNameOf(String ckpPath) {
  final base = ckpPath.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}
