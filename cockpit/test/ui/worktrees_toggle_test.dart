import 'dart:io';

import 'package:cockpit/app/cockpit/data/repositories/json_workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/widgets/projects_rail.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Toggle de worktrees no card do workspace (V37): a regra do clique e a
/// persistência do estado dentro do **documento de layout** já existente.
void main() {
  group('worktreesExpandedOf', () {
    test('workspace sem layout salvo nasce expandido', () {
      // Default do rail desde sempre — recolher precisa ser escolha explícita.
      expect(worktreesExpandedOf(null), isTrue);
    });

    test('layout antigo (sem a chave) continua expandido', () {
      expect(worktreesExpandedOf(const {'v': 1, 'tree': {}}), isTrue);
    });

    test('valor de tipo errado cai no default em vez de estourar', () {
      // Doc editado à mão / gravado por versão futura não pode quebrar o boot.
      expect(worktreesExpandedOf(const {kWorktreesExpandedKey: 'no'}), isTrue);
    });

    test('lê o estado gravado', () {
      expect(
        worktreesExpandedOf(const {kWorktreesExpandedKey: false}),
        isFalse,
      );
      expect(worktreesExpandedOf(const {kWorktreesExpandedKey: true}), isTrue);
    });
  });

  group('round-trip no WorkspaceLayoutStore', () {
    late Directory tmp;
    late JsonStateStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('worktrees_toggle_test');
      store = await JsonStateStore.open(tmp.path, 'layouts');
    });

    tearDown(() async {
      JsonStateStore.resetCacheForTesting();
      await tmp.delete(recursive: true);
    });

    test('recolhido sobrevive ao save/load (sem storage paralelo)', () async {
      final layouts = JsonWorkspaceLayoutStore(store);
      await layouts.save('p1', <String, dynamic>{
        'v': 1,
        'tree': <String, dynamic>{
          'k': 'leaf',
          'id': 'l1',
          'tabs': <String>[],
          'active': 'l1',
        },
        'sessions': <String, dynamic>{},
        kWorktreesExpandedKey: false,
      });

      final reloaded = await layouts.load('p1');
      expect(worktreesExpandedOf(reloaded), isFalse);
      // O doc segue sendo o layout — o toggle é só mais um campo dele.
      expect(reloaded!['tree'], isA<Map<dynamic, dynamic>>());
    });

    test(
      'expandido sobrevive e o workspace sem doc volta ao default',
      () async {
        final layouts = JsonWorkspaceLayoutStore(store);
        await layouts.save('p1', <String, dynamic>{
          'v': 1,
          kWorktreesExpandedKey: true,
        });
        expect(worktreesExpandedOf(await layouts.load('p1')), isTrue);
        expect(worktreesExpandedOf(await layouts.load('nunca-salvo')), isTrue);
      },
    );
  });

  group('workspaceCardTap', () {
    test('não selecionado: seleciona e abre a lista', () {
      final action = workspaceCardTap(
        selected: false,
        expanded: false,
        hasWorktrees: true,
      );
      expect(action.select, isTrue);
      expect(action.expand, isTrue);
    });

    test('não selecionado e já expandido: seleciona e mantém aberto', () {
      // Selecionar nunca RECOLHE — seria perder a lista sem pedir.
      final action = workspaceCardTap(
        selected: false,
        expanded: true,
        hasWorktrees: true,
      );
      expect(action.select, isTrue);
      expect(action.expand, isTrue);
    });

    test('já selecionado: o clique só alterna', () {
      expect(
        workspaceCardTap(selected: true, expanded: true, hasWorktrees: true),
        (select: false, expand: false),
      );
      expect(
        workspaceCardTap(selected: true, expanded: false, hasWorktrees: true),
        (select: false, expand: true),
      );
    });

    test('sem worktrees: nunca mexe no estado da lista', () {
      // Sem fork não há chevron nem lista; gravar um estado aqui só sujaria o
      // layout de workspaces que nunca vão mostrar nada.
      expect(
        workspaceCardTap(selected: false, expanded: true, hasWorktrees: false),
        (select: true, expand: null),
      );
      expect(
        workspaceCardTap(selected: true, expanded: true, hasWorktrees: false),
        (select: false, expand: null),
      );
    });
  });
}
