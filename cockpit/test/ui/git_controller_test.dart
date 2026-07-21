import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/git_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopStatusReader implements GitStatusReader {
  @override
  Future<GitInfo?> read(String path) async => null;
}

class _NoopCommandRunner implements GitCommandRunner {
  Never _unused() => throw UnimplementedError();

  @override
  GitMergeOutcome mergeIntoParent(
    String parentPath,
    String worktreePath,
    String worktreeBranch,
  ) => _unused();

  @override
  GitRun run(String repoPath, List<String> args) => _unused();

  @override
  GitRun syncPullPush(String repoPath) => _unused();
}

void main() {
  test('watch failure retries with backoff instead of spinning', () async {
    var attempts = 0;
    final git = GitController(
      _NoopStatusReader(),
      _NoopCommandRunner(),
      directoryWatch: (_) {
        attempts++;
        return Stream<FileSystemEvent>.error(
          const FileSystemException('directory disappeared'),
        );
      },
      watchRetryDelay: const Duration(milliseconds: 80),
    );
    addTearDown(git.dispose);
    git
      ..resolvePath = ((_) => '/missing/worktree')
      ..selectedProjectId = (() => 'fork')
      ..watchProject('fork');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(attempts, 1);

    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(attempts, 2);
  });

  test(
    'retry follows a selection that moved to the parent workspace',
    () async {
      final watched = <String>[];
      var selected = 'fork';
      final parentEvents = StreamController<FileSystemEvent>();
      addTearDown(parentEvents.close);
      final git = GitController(
        _NoopStatusReader(),
        _NoopCommandRunner(),
        directoryWatch: (path) {
          watched.add(path);
          if (path == '/gone/worktree') {
            return Stream<FileSystemEvent>.error(
              const FileSystemException('directory disappeared'),
            );
          }
          return parentEvents.stream;
        },
        watchRetryDelay: const Duration(milliseconds: 30),
      );
      addTearDown(git.dispose);
      git
        ..resolvePath = ((id) => id == 'fork' ? '/gone/worktree' : '/repo')
        ..selectedProjectId = (() => selected)
        ..watchProject('fork');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      selected = 'parent';
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(watched, ['/gone/worktree', '/repo']);
    },
  );
}
