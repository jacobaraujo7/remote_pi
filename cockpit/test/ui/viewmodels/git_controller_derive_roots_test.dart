import 'dart:io';

import 'package:cockpit/app/cockpit/ui/viewmodels/git_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('derive_roots_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  String ws(String name) => '${tmp.path.replaceAll('\\', '/')}/$name';

  /// Cria um repo fake: `<dir>/.git/` como diretório.
  void makeRepo(String dir) {
    Directory('$dir/.git').createSync(recursive: true);
  }

  /// Cria um worktree linkado fake: `<dir>/.git` como ARQUIVO `gitdir: ...`,
  /// como o git escreve em `git worktree add`.
  void makeLinkedWorktree(String dir, String gitdir) {
    Directory(dir).createSync(recursive: true);
    File('$dir/.git').writeAsStringSync('gitdir: $gitdir\n');
  }

  test('raiz com .git → single-root', () {
    final root = ws('single');
    makeRepo(root);
    expect(GitController.deriveRoots(root), [root]);
  });

  test('raiz sem git e sem filhas-repo → pasta comum', () {
    final root = ws('plain');
    Directory('$root/docs').createSync(recursive: true);
    expect(GitController.deriveRoots(root), [root]);
  });

  test('multi-root: filhas com .git viram roots, ordenadas', () {
    final root = ws('multi');
    makeRepo('$root/zeta');
    makeRepo('$root/alpha');
    expect(GitController.deriveRoots(root), ['$root/alpha', '$root/zeta']);
  });

  test('worktree de repo-irmão NÃO vira root (caso massivo)', () {
    // Layout real que duplicava forks: 2 repos + os worktrees deles como
    // pastas irmãs dentro do mesmo workspace.
    final root = ws('massivo');
    makeRepo('$root/backend');
    makeRepo('$root/front');
    makeLinkedWorktree(
      '$root/backend-BTN-5175',
      '$root/backend/.git/worktrees/backend-BTN-5175',
    );
    makeLinkedWorktree(
      '$root/front-BTN-5175',
      '$root/front/.git/worktrees/front-BTN-5175',
    );

    expect(GitController.deriveRoots(root), ['$root/backend', '$root/front']);
  });

  test('worktree de repo de FORA do workspace segue sendo root', () {
    final outside = ws('outside-repo');
    makeRepo(outside);
    final root = ws('wt-only');
    makeRepo('$root/normal');
    makeLinkedWorktree('$root/wt', '$outside/.git/worktrees/wt');

    expect(GitController.deriveRoots(root), ['$root/normal', '$root/wt']);
  });

  test('gitdir relativo resolve contra a filha antes de comparar', () {
    final root = ws('relative');
    makeRepo('$root/repo');
    makeLinkedWorktree('$root/wt', '../repo/.git/worktrees/wt');

    expect(GitController.deriveRoots(root), ['$root/repo']);
  });
}
