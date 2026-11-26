import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/git_controller.dart';
import 'package:cockpit/app/core/ui/window_activity_controller.dart';
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
  @override
  GitRun clone(String url, String targetPath) => _unused();
}

void main() {
  test('watch failure retries with backoff instead of spinning', () async {
    var attempts = 0;
    final git = GitController(
      _NoopStatusReader(),
      _NoopCommandRunner(),
      WindowActivityController(),
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
        WindowActivityController(),
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

  test(
    'recursive watcher is detached while inactive and rearmed on resume',
    () async {
      var listens = 0;
      var cancels = 0;
      final events = StreamController<FileSystemEvent>.broadcast(
        onListen: () => listens++,
        onCancel: () => cancels++,
      );
      addTearDown(events.close);
      final activity = WindowActivityController();
      addTearDown(activity.dispose);
      final git =
          GitController(
              _NoopStatusReader(),
              _NoopCommandRunner(),
              activity,
              directoryWatch: (_) => events.stream,
            )
            ..resolvePath = ((_) => '/repo')
            ..selectedProjectId = (() => 'repo')
            ..watchProject('repo');
      addTearDown(git.dispose);
      expect(listens, 1);

      activity.blur();
      await Future<void>.delayed(Duration.zero);
      expect(cancels, 1);

      activity.focus();
      expect(listens, 2);
    },
  );

  test(
    'refresh is single-flight per project with one coalesced rerun',
    () async {
      final directory = await Directory.systemTemp.createTemp('git-flight-');
      addTearDown(() => directory.delete(recursive: true));
      await Directory('${directory.path}/.git').create();
      final reader = _BlockingStatusReader();
      final activity = WindowActivityController();
      addTearDown(activity.dispose);
      final git = GitController(reader, _NoopCommandRunner(), activity)
        ..resolvePath = ((_) => directory.path);
      addTearDown(git.dispose);

      final first = git.refresh('repo');
      git.refresh('repo');
      git.refresh('repo');
      expect(reader.runs, 1);

      reader.releaseNext();
      await Future<void>.delayed(Duration.zero);
      expect(reader.runs, 2, reason: 'burst reruns once');

      git.refresh('repo');
      git.refresh('repo');
      reader.releaseNext();
      await first;

      expect(reader.maxConcurrent, 1);
      expect(reader.runs, 2);
    },
  );
}

class _BlockingStatusReader implements GitStatusReader {
  final List<Completer<void>> _releases = [];
  var runs = 0;
  var concurrent = 0;
  var maxConcurrent = 0;

  @override
  Future<GitInfo?> read(String path) async {
    runs++;
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    final release = Completer<void>();
    _releases.add(release);
    await release.future;
    concurrent--;
    return null;
  }

  void releaseNext() => _releases.firstWhere((c) => !c.isCompleted).complete();
}
