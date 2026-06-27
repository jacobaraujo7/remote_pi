// Testes do núcleo do multiplexador: a árvore de splits (puro, sem Flutter).

import 'package:cockpit/app/cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/app/cockpit/domain/entities/install_result.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';
import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/setup_viewmodel.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icon.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icon_map.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('split tree', () {
    test('leaves enumera todas as folhas', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.vertical,
        a: const LeafPane(id: 'p1', tabs: ['a'], active: 'a'),
        b: const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
        frac: 0.5,
      );
      expect(leaves(tree).map((l) => l.id), ['p1', 'p2']);
    });

    test('splitLeaf transforma a folha num split', () {
      const tree = LeafPane(id: 'p1', tabs: ['a'], active: 'a');
      final out = splitLeaf(
        tree,
        'p1',
        SplitDir.vertical,
        const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
      );
      expect(out, isA<SplitPane>());
      expect(leaves(out).length, 2);
    });

    test('removeLeaf faz o irmão expandir', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.vertical,
        a: const LeafPane(id: 'p1', tabs: ['a'], active: 'a'),
        b: const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
        frac: 0.5,
      );
      final out = removeLeaf(tree, 'p1');
      expect(out, isA<LeafPane>());
      expect((out as LeafPane).id, 'p2');
    });

    test('updateLeaf altera só a folha alvo', () {
      const tree = LeafPane(id: 'p1', tabs: ['a'], active: 'a');
      final out = updateLeaf(
        tree,
        'p1',
        (p) => p.copyWith(tabs: ['a', 'b'], active: 'b'),
      );
      expect((out as LeafPane).tabs, ['a', 'b']);
      expect(out.active, 'b');
    });

    test('setFrac ajusta a proporção do split certo', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.horizontal,
        a: const LeafPane(id: 'p1', tabs: ['a'], active: 'a'),
        b: const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
        frac: 0.5,
      );
      final out = setFrac(tree, 's1', 0.3) as SplitPane;
      expect(out.frac, 0.3);
    });

    test('splitLeaf before:true põe o novo pane antes (a)', () {
      const tree = LeafPane(id: 'p1', tabs: ['a'], active: 'a');
      final out =
          splitLeaf(
                tree,
                'p1',
                SplitDir.vertical,
                const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
                splitId: 'sx',
                before: true,
              )
              as SplitPane;
      expect(out.id, 'sx');
      expect((out.a as LeafPane).id, 'p2');
      expect((out.b as LeafPane).id, 'p1');
    });

    test('splitLeaf splitId customizado e novo pane depois por padrão', () {
      const tree = LeafPane(id: 'p1', tabs: ['a'], active: 'a');
      final out =
          splitLeaf(
                tree,
                'p1',
                SplitDir.vertical,
                const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
                splitId: 'unico-1',
              )
              as SplitPane;
      expect(out.id, 'unico-1');
      expect((out.b as LeafPane).id, 'p2');
    });

    test('reorderTabs move pra frente (ajuste pós-remoção)', () {
      // ['a','b','c','d'], soltar 'a' no slot 3 → vai pra antes de 'd'.
      expect(reorderTabs(['a', 'b', 'c', 'd'], 'a', 3), ['b', 'c', 'a', 'd']);
    });

    test('reorderTabs move pra trás', () {
      expect(reorderTabs(['a', 'b', 'c', 'd'], 'd', 1), ['a', 'd', 'b', 'c']);
    });

    test('reorderTabs no slot da própria posição é no-op', () {
      expect(reorderTabs(['a', 'b', 'c'], 'b', 1), ['a', 'b', 'c']);
      expect(reorderTabs(['a', 'b', 'c'], 'b', 2), ['a', 'b', 'c']);
    });

    test('reorderTabs pro fim', () {
      expect(reorderTabs(['a', 'b', 'c'], 'a', 3), ['b', 'c', 'a']);
    });

    test('reorderTabs id ausente devolve inalterado', () {
      expect(reorderTabs(['a', 'b'], 'z', 0), ['a', 'b']);
    });

    test('paneNodeToJson/FromJson faz round-trip da árvore', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.horizontal,
        a: const LeafPane(id: 'p1', tabs: ['a', 'b'], active: 'b'),
        b: SplitPane(
          id: 's2',
          dir: SplitDir.vertical,
          a: const LeafPane(id: 'p2', tabs: ['c'], active: 'c'),
          b: const LeafPane(id: 'p3', tabs: ['d', 'e'], active: 'd'),
          frac: 0.4,
        ),
        frac: 0.6,
      );
      final back = paneNodeFromJson(paneNodeToJson(tree));
      expect(back, isA<SplitPane>());
      final s = back as SplitPane;
      expect(s.dir, SplitDir.horizontal);
      expect(s.frac, 0.6);
      expect((s.a as LeafPane).tabs, ['a', 'b']);
      expect((s.a as LeafPane).active, 'b');
      final s2 = s.b as SplitPane;
      expect(s2.id, 's2');
      expect(s2.dir, SplitDir.vertical);
      expect(s2.frac, 0.4);
      expect((s2.b as LeafPane).tabs, ['d', 'e']);
      // Mesma topologia de folhas, na mesma ordem.
      expect(leaves(back).map((l) => l.id), ['p1', 'p2', 'p3']);
    });

    test('paneNodeFromJson reconstrói uma folha simples', () {
      final json = paneNodeToJson(
        const LeafPane(id: 'p1', tabs: ['x'], active: 'x'),
      );
      final back = paneNodeFromJson(json);
      expect(back, isA<LeafPane>());
      expect((back as LeafPane).id, 'p1');
      expect(back.tabs, ['x']);
    });

    test('mover a última aba esvazia a folha → irmão expande', () {
      final tree = SplitPane(
        id: 's1',
        dir: SplitDir.vertical,
        a: const LeafPane(id: 'p1', tabs: ['a'], active: 'a'),
        b: const LeafPane(id: 'p2', tabs: ['b'], active: 'b'),
        frac: 0.5,
      );
      final docked = updateLeaf(
        tree,
        'p2',
        (p) => p.copyWith(tabs: [...p.tabs, 'a'], active: 'a'),
      );
      final out = removeLeaf(docked, 'p1');
      expect(out, isA<LeafPane>());
      expect((out as LeafPane).tabs, ['b', 'a']);
      expect(out.active, 'a');
    });
  });

  group('file icons', () {
    test('extensão simples resolve pelo último segmento', () {
      expect(fileIconName('main.dart'), 'dart');
      expect(fileIconName('styles.scss'), 'sass');
      expect(fileIconName('script.sh'), 'console');
    });

    test('extensão é case-insensitive', () {
      expect(fileIconName('PHOTO.PNG'), 'image');
    });

    test('extensão composta vence a simples (mais longa primeiro)', () {
      expect(fileIconName('app.module.ts'), 'angular');
      expect(fileIconName('foo.test.tsx'), 'test-jsx');
    });

    test('nome exato tem prioridade sobre extensão', () {
      expect(fileIconName('package.json'), 'nodejs');
      expect(fileIconName('.gitignore'), 'git');
      expect(fileIconName('Dockerfile'), 'docker');
    });

    test('desconhecido cai no ícone padrão', () {
      expect(fileIconName('weird'), kDefaultFileIcon);
      expect(fileIconName('no.such.ext'), kDefaultFileIcon);
    });

    test('pasta resolve e normaliza variantes (._- e __x__)', () {
      expect(folderIconName('src'), folderIconName('.src'));
      expect(folderIconName('test'), folderIconName('__tests__'));
      expect(folderIconName('node_modules'), isNot(kDefaultFolderIcon));
    });

    test('pasta aberta usa o ícone aberto', () {
      final closed = folderIconName('src');
      final open = folderIconName('src', open: true);
      expect(open, isNot(closed));
      expect(folderIconName('xyz-unknown'), kDefaultFolderIcon);
      expect(folderIconName('xyz-unknown', open: true), kDefaultFolderOpenIcon);
    });
  });

  group('agent setup gate', () {
    test('trio satisfeito → agentReady', () async {
      final vm = SetupViewModel(_FakeEnv(), _FakeInstaller());
      await vm.recheckAll();
      expect(vm.pi, CheckStatus.ok);
      expect(vm.extension, CheckStatus.ok);
      expect(vm.supervisor, CheckStatus.ok);
      expect(vm.agentReady, isTrue);
    });

    test('um passo faltando bloqueia', () async {
      final vm = SetupViewModel(_FakeEnv(ext: false), _FakeInstaller());
      await vm.recheckAll();
      expect(vm.extension, CheckStatus.missing);
      expect(vm.agentReady, isFalse);
    });

    test('pi ou supervisor faltando também bloqueia', () async {
      final a = SetupViewModel(_FakeEnv(pi: false), _FakeInstaller());
      await a.recheckAll();
      expect(a.pi, CheckStatus.missing);
      expect(a.agentReady, isFalse);

      final b = SetupViewModel(_FakeEnv(sup: false), _FakeInstaller());
      await b.recheckAll();
      expect(b.supervisor, CheckStatus.missing);
      expect(b.agentReady, isFalse);
    });
  });
}

class _FakeEnv implements EnvironmentProbe {
  _FakeEnv({this.pi = true, this.ext = true, this.sup = true});
  final bool pi;
  final bool ext;
  final bool sup;
  @override
  Future<bool> piInstalled() async => pi;
  @override
  Future<bool> extensionInstalled() async => ext;
  @override
  Future<bool> supervisorInstalled() async => sup;
}

class _FakeInstaller implements EnvironmentInstaller {
  @override
  Future<InstallResult> installExtension() async =>
      const InstallResult.success();
  @override
  Future<InstallResult> installSupervisor() async =>
      const InstallResult.success();
}
