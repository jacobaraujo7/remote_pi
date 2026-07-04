import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/data/filesystem/git_diff_reader_impl.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reader = GitDiffReaderImpl(GitBinary());
  late Directory repo;

  Future<ProcessResult> git(List<String> args) =>
      Process.run('git', args, workingDirectory: repo.path);

  Future<bool> gitAvailable() async {
    try {
      return (await Process.run('git', ['--version'])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> write(String rel, String content) =>
      File('${repo.path}/$rel').writeAsString(content);

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('cockpit_diff_test_');
    await git(['init']);
    await git(['config', 'user.email', 'test@example.com']);
    await git(['config', 'user.name', 'Test']);
    await write('a.txt', 'line1\nline2\nline3\n');
    await git(['add', '.']);
    await git(['commit', '-m', 'init']);
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('modified file → hunks com added e removed', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await write('a.txt', 'line1\nCHANGED\nline3\n');
    final diff = await reader.read(repo.path, '${repo.path}/a.txt');
    expect(diff.kind, FileDiffKind.modified);
    expect(diff.hunks, isNotEmpty);
    final lines = diff.hunks.expand((h) => h.lines).toList();
    expect(
      lines.any((l) => l.kind == DiffLineKind.removed && l.text == 'line2'),
      isTrue,
    );
    expect(
      lines.any((l) => l.kind == DiffLineKind.added && l.text == 'CHANGED'),
      isTrue,
    );
    // Números de linha: removed tem oldLine, added tem newLine.
    final removed = lines.firstWhere((l) => l.kind == DiffLineKind.removed);
    expect(removed.oldLine, isNotNull);
    expect(removed.newLine, isNull);
  });

  test('untracked file → tudo adicionado', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await write('new.txt', 'x\ny\n');
    final diff = await reader.read(repo.path, '${repo.path}/new.txt');
    expect(diff.kind, FileDiffKind.added);
    final lines = diff.hunks.expand((h) => h.lines).toList();
    expect(lines.length, 2);
    expect(lines.every((l) => l.kind == DiffLineKind.added), isTrue);
  });

  test('deleted file → tudo removido', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await File('${repo.path}/a.txt').delete();
    final diff = await reader.read(repo.path, '${repo.path}/a.txt');
    expect(diff.kind, FileDiffKind.deleted);
    final lines = diff.hunks.expand((h) => h.lines).toList();
    expect(lines.every((l) => l.kind == DiffLineKind.removed), isTrue);
  });

  test('arquivo intocado → unchanged', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final diff = await reader.read(repo.path, '${repo.path}/a.txt');
    expect(diff.kind, FileDiffKind.unchanged);
    expect(diff.hunks, isEmpty);
  });

  test('binário → FileDiffKind.binary', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await File(
      '${repo.path}/bin.dat',
    ).writeAsBytes([0, 1, 2, 0, 255, 0, 10, 0]);
    final diff = await reader.read(repo.path, '${repo.path}/bin.dat');
    expect(diff.kind, FileDiffKind.binary);
  });
}
