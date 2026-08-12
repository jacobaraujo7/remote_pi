import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/data/filesystem/git_head_baseline_reader_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reader = GitHeadBaselineReaderImpl(GitBinary());
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
    repo = await Directory.systemTemp.createTemp('cockpit_head_baseline_');
    await git(['init']);
    await git(['config', 'user.email', 'test@example.com']);
    await git(['config', 'user.name', 'Test']);
    await write('tracked.txt', 'line1\nline2\n');
    await git(['add', '.']);
    await git(['commit', '-m', 'init']);
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('tracked file → blob de HEAD', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final baseline = await reader.readTrackedText(
      repo.path,
      '${repo.path}/tracked.txt',
    );
    expect(baseline, isNotNull);
    expect(baseline!.content, 'line1\nline2\n');
    expect(baseline.headIdentity, isNotEmpty);
  });

  test('staged changes não alteram o baseline (ainda HEAD)', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await write('tracked.txt', 'STAGED\n');
    await git(['add', 'tracked.txt']);
    final baseline = await reader.readTrackedText(
      repo.path,
      '${repo.path}/tracked.txt',
    );
    expect(baseline!.content, 'line1\nline2\n');
  });

  test('unstaged changes não alteram o baseline', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await write('tracked.txt', 'DIRTY\n');
    final baseline = await reader.readTrackedText(
      repo.path,
      '${repo.path}/tracked.txt',
    );
    expect(baseline!.content, 'line1\nline2\n');
  });

  test('untracked → null', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await write('new.txt', 'x\n');
    final baseline = await reader.readTrackedText(
      repo.path,
      '${repo.path}/new.txt',
    );
    expect(baseline, isNull);
  });

  test('ignored → null', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await write('.gitignore', 'ignored.txt\n');
    await git(['add', '.gitignore']);
    await git(['commit', '-m', 'ignore']);
    await write('ignored.txt', 'nope\n');
    final baseline = await reader.readTrackedText(
      repo.path,
      '${repo.path}/ignored.txt',
    );
    expect(baseline, isNull);
  });

  test('commit muda a identidade de HEAD e o conteúdo', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final before = await reader.resolveHeadIdentity(repo.path);
    await write('tracked.txt', 'after\n');
    await git(['add', 'tracked.txt']);
    await git(['commit', '-m', 'change']);
    final after = await reader.resolveHeadIdentity(repo.path);
    expect(after, isNot(equals(before)));
    final baseline = await reader.readTrackedText(
      repo.path,
      '${repo.path}/tracked.txt',
    );
    expect(baseline!.content, 'after\n');
    expect(baseline.headIdentity, after);
  });

  test('checkout restaura o blob de HEAD', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final firstHead = await reader.resolveHeadIdentity(repo.path);
    await write('tracked.txt', 'branchy\n');
    await git(['checkout', '-b', 'feature']);
    await git(['add', 'tracked.txt']);
    await git(['commit', '-m', 'feature']);
    await git(['checkout', '-']);
    final baseline = await reader.readTrackedText(
      repo.path,
      '${repo.path}/tracked.txt',
    );
    expect(baseline!.headIdentity, firstHead);
    expect(baseline.content, 'line1\nline2\n');
  });

  test('falha ao ler HEAD (pasta sem git) → null', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final orphan = await Directory.systemTemp.createTemp('cockpit_no_git_');
    addTearDown(() async {
      if (await orphan.exists()) await orphan.delete(recursive: true);
    });
    await File('${orphan.path}/x.txt').writeAsString('x\n');
    expect(await reader.resolveHeadIdentity(orphan.path), isNull);
    expect(
      await reader.readTrackedText(orphan.path, '${orphan.path}/x.txt'),
      isNull,
    );
  });

  test('binário → null', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await File(
      '${repo.path}/bin.dat',
    ).writeAsBytes([0, 1, 2, 0, 255, 0, 10, 0]);
    await git(['add', 'bin.dat']);
    await git(['commit', '-m', 'bin']);
    final baseline = await reader.readTrackedText(
      repo.path,
      '${repo.path}/bin.dat',
    );
    expect(baseline, isNull);
  });
}
