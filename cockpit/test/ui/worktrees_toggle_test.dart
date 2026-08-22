import 'dart:io';

import 'package:cockpit/app/cockpit/data/repositories/json_workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/widgets/projects_rail.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Toggle de worktrees no card do workspace (V37): a persistência do estado
/// dentro do **documento de layout** já existente. A regra do clique (card
/// seleciona, chevron alterna) é coberta em `projects_rail_context_menu_test`.
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

  group('worktreeChevronIcon', () {
    test('aponta para a direita quando recolhido', () {
      expect(worktreeChevronIcon(false), Icons.chevron_right);
    });

    test('aponta para baixo quando expandido', () {
      expect(worktreeChevronIcon(true), Icons.keyboard_arrow_down);
    });
  });
}
