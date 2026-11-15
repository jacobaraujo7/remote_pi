import 'package:cockpit/app/cockpit/data/remote/remote_git_adapter.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit_core/cockpit_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';

core.GitStatus status(String branch, List<(String, String, String)> files) =>
    core.GitStatus(
      branch: branch,
      files: [
        for (final (x, y, p) in files)
          core.GitFileStatus(staged: x, worktree: y, path: p),
      ],
    );

void main() {
  test('untracked → changed + files (untracked)', () {
    final info = remoteGitInfo(status('main', [('?', '?', 'new.txt')]));
    expect(info.branch, 'main');
    expect(info.changedFiles['new.txt'], GitFileStatus.untracked);
    expect(info.stagedFiles, isEmpty);
    expect(info.files['new.txt'], GitFileStatus.untracked);
  });

  test('staged add e worktree modify', () {
    final info = remoteGitInfo(
      status('dev', [('A', ' ', 'added.txt'), (' ', 'M', 'edited.txt')]),
    );
    expect(info.stagedFiles['added.txt'], GitFileStatus.staged);
    expect(info.changedFiles['edited.txt'], GitFileStatus.modified);
  });

  test('mesmo arquivo staged + nova edição no worktree (MM)', () {
    final info = remoteGitInfo(status('main', [('M', 'M', 'both.txt')]));
    expect(info.stagedFiles['both.txt'], GitFileStatus.staged);
    expect(info.changedFiles['both.txt'], GitFileStatus.modified);
    expect(info.files['both.txt'], GitFileStatus.modified); // strongest
  });

  test('conflito UU', () {
    final info = remoteGitInfo(status('main', [('U', 'U', 'c.txt')]));
    expect(info.files['c.txt'], GitFileStatus.conflict);
    expect(info.changedFiles['c.txt'], GitFileStatus.conflict);
  });

  test('deletado no worktree', () {
    final info = remoteGitInfo(status('main', [(' ', 'D', 'gone.txt')]));
    expect(info.changedFiles['gone.txt'], GitFileStatus.deleted);
  });

  test('pasta untracked colapsada não vira "arquivo" com barra na chave', () {
    // Host com servidor antigo (sem `-uall`) manda a pasta colapsada. A chave
    // guardada com a barra fazia a árvore desenhar `.cockpit` como arquivo.
    final info = remoteGitInfo(status('main', [('?', '?', '.cockpit/')]));

    expect(info.files.keys, ['.cockpit']);
    expect(info.files['.cockpit'], GitFileStatus.untracked);
    expect(info.untrackedDirs, {'.cockpit'});
    // E os descendentes herdam o untracked, mesmo sem terem sido enumerados.
    expect(info.isUntracked('.cockpit/tasks.json'), isTrue);
  });

  test(
    'com -uall os arquivos vêm individualmente e não há pasta colapsada',
    () {
      final info = remoteGitInfo(
        status('main', [
          ('?', '?', '.cockpit/tasks.json'),
          ('?', '?', '.cockpit/databases.json'),
        ]),
      );
      expect(info.files.keys, [
        '.cockpit/tasks.json',
        '.cockpit/databases.json',
      ]);
      expect(info.untrackedDirs, isEmpty);
    },
  );

  test('raiz ignorada vira ignored, não "staged"', () {
    // Sem o ramo de `!!`, o `!` do index caía no classificador e a pasta
    // ignorada aparecia como mudança em staging.
    final info = remoteGitInfo(status('main', [('!', '!', 'build/')]));

    expect(info.ignored, {'build'});
    expect(info.files, isEmpty);
    expect(info.stagedFiles, isEmpty);
    expect(info.changedFiles, isEmpty);
  });

  test('line stats are unknown (null) on a remote host, not 0', () {
    final info = remoteGitInfo(status('main', [(' ', 'M', 'edited.txt')]));
    expect(info.insertions, isNull);
    expect(info.deletions, isNull);
  });
}
