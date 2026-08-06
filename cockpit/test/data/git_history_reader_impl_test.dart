import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/data/filesystem/git_history_reader_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitHistoryParser', () {
    test('parses parents, decorations and metadata without graph art', () {
      const output =
          'aaaaaaaaaaaaaaaa\u001fbbbbbbbbbbbbbbbb cccccccccccccccc\u001f'
          'HEAD -> main, tag: v1.0\u001fAda Lovelace\u001f'
          '2026-08-05T12:30:00+00:00\u001fMerge feature\u001e\n'
          'bbbbbbbbbbbbbbbb\u001f\u001f\u001fGrace Hopper\u001f'
          '2026-08-04T10:00:00+00:00\u001fInitial commit\u001e';

      final commits = GitHistoryParser.parse(output);

      expect(commits, hasLength(2));
      expect(commits.first.hash, 'aaaaaaaaaaaaaaaa');
      expect(commits.first.shortHash, 'aaaaaaaa');
      expect(commits.first.parents, ['bbbbbbbbbbbbbbbb', 'cccccccccccccccc']);
      expect(commits.first.refs, ['HEAD -> main', 'tag: v1.0']);
      expect(commits.first.isHead, isTrue);
      expect(commits.first.author, 'Ada Lovelace');
      expect(commits.first.authoredAt, DateTime.parse('2026-08-05T12:30:00Z'));
      expect(commits.last.hash, 'bbbbbbbbbbbbbbbb');
      expect(commits.last.parents, isEmpty);
    });

    test('ignores incomplete records and accepts empty output', () {
      expect(GitHistoryParser.parse(''), isEmpty);
      expect(GitHistoryParser.parse('bad\u001fdata\u001e'), isEmpty);
    });
  });

  group('GitHistoryReaderImpl', () {
    final reader = GitHistoryReaderImpl(GitBinary());
    late Directory repo;

    Future<ProcessResult> git(List<String> args) =>
        Process.run('git', args, workingDirectory: repo.path);

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('cockpit_history_test_');
      await git(['init']);
      await git(['config', 'user.email', 'test@example.com']);
      await git(['config', 'user.name', 'Test']);
      await File('${repo.path}/initial.txt').writeAsString('initial\n');
      await git(['add', '.']);
      await git(['commit', '-m', 'initial']);
      await git(['branch', 'side']);
      await File('${repo.path}/current.txt').writeAsString('current\n');
      await git(['add', '.']);
      await git(['commit', '-m', 'current branch commit']);
      await git(['checkout', 'side']);
      await File('${repo.path}/side.txt').writeAsString('side\n');
      await git(['add', '.']);
      await git(['commit', '-m', 'side branch commit']);
      await git(['checkout', '-']);
    });

    tearDown(() async {
      if (await repo.exists()) await repo.delete(recursive: true);
    });

    test('reads only the checked-out branch and its changed files', () async {
      final history = await reader.read(repo.path);
      final commits = history.fold(
        (commits) => commits,
        (error) => fail(error.detail ?? 'could not read history'),
      );
      expect(
        commits.map((commit) => commit.subject),
        contains('current branch commit'),
      );
      expect(
        commits.map((commit) => commit.subject),
        isNot(contains('side branch commit')),
      );

      final current = commits.firstWhere(
        (commit) => commit.subject == 'current branch commit',
      );
      final files = (await reader.readFiles(repo.path, current.hash)).fold(
        (files) => files,
        (error) => fail(error.detail ?? 'could not read changed files'),
      );
      expect(files.map((file) => file.path), contains('current.txt'));
    });
  });

  group('GitHistoryFileChangeParser', () {
    test('parses regular and renamed files from NUL-delimited output', () {
      const output =
          'M\u0000lib/main.dart\u0000R100\u0000old.dart\u0000new.dart\u0000';

      final changes = GitHistoryFileChangeParser.parse(output);

      expect(changes, hasLength(2));
      expect(changes.first.status, 'M');
      expect(changes.first.path, 'lib/main.dart');
      expect(changes.last.status, 'R100');
      expect(changes.last.previousPath, 'old.dart');
      expect(changes.last.path, 'new.dart');
      expect(changes.last.displayPath, 'old.dart → new.dart');
    });
  });
}
