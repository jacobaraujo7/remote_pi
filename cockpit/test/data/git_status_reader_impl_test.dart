import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/data/filesystem/git_status_reader_impl.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reader = GitStatusReaderImpl(GitBinary());
  late Directory repo;

  Future<ProcessResult> git(List<String> args, {String? cwd}) =>
      Process.run('git', args, workingDirectory: cwd ?? repo.path);

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
    repo = await Directory.systemTemp.createTemp('cockpit_git_test_');
    await git(['init']);
    await git(['config', 'user.email', 'test@example.com']);
    await git(['config', 'user.name', 'Test']);
    await write('README.md', 'hello');
    await Directory('${repo.path}/lib').create();
    await write('lib/app.dart', 'void main() {}');
    await git(['add', '.']);
    await git(['commit', '-m', 'init']);
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('pasta não-git → null', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final plain = await Directory.systemTemp.createTemp('cockpit_plain_');
    addTearDown(() => plain.delete(recursive: true));
    expect(await reader.read(plain.path), isNull);
  });

  test('árvore limpa → branch sem arquivos sujos', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final info = await reader.read(repo.path);
    expect(info, isNotNull);
    expect(info!.isDirty, isFalse);
    expect(info.files, isEmpty);
    expect(info.ahead, 0);
    expect(info.behind, 0);
  });

  test('classifica modified / staged / untracked / deleted', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    // modified working tree (não staged).
    await write('README.md', 'changed');
    // staged: arquivo novo adicionado ao index.
    await write('staged.txt', 'new');
    await git(['add', 'staged.txt']);
    // untracked: novo, fora do index.
    await write('lib/fresh.dart', '// novo');
    // deleted: rastreado e removido do disco.
    await File('${repo.path}/lib/app.dart').delete();

    final info = await reader.read(repo.path);
    expect(info, isNotNull);
    final files = info!.files;
    expect(files['README.md'], GitFileStatus.modified);
    expect(files['staged.txt'], GitFileStatus.staged);
    expect(files['lib/fresh.dart'], GitFileStatus.untracked);
    expect(files['lib/app.dart'], GitFileStatus.deleted);
    expect(info.dirtyCount, files.length);
  });

  test('paths com espaço são parseados (separador -z é NUL)', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await write('a file.txt', 'x');
    final info = await reader.read(repo.path);
    expect(info!.files['a file.txt'], GitFileStatus.untracked);
  });

  test('pasta nova (untracked) colapsada → cobre descendentes', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    // Diretório totalmente novo → git colapsa em "?? novo/".
    await Directory('${repo.path}/novo/sub').create(recursive: true);
    await write('novo/a.txt', '1');
    await write('novo/sub/b.txt', '2');

    final info = await reader.read(repo.path);
    expect(info, isNotNull);
    expect(info!.untrackedDirs, contains('novo'));
    // A própria pasta colapsada entra como untracked (colore a linha + ancestrais).
    expect(info.files['novo'], GitFileStatus.untracked);
    // Descendentes não enumerados, mas cobertos por isUntracked.
    expect(info.isUntracked('novo/a.txt'), isTrue);
    expect(info.isUntracked('novo/sub/b.txt'), isTrue);
    expect(info.isUntracked('lib/app.dart'), isFalse);
  });

  test('coleta raízes ignoradas (.gitignore) sem contar como sujo', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    await write('.gitignore', 'build/\n*.log\n');
    await git(['add', '.gitignore']);
    await git(['commit', '-m', 'gitignore']);
    await Directory('${repo.path}/build').create();
    await write('build/out.bin', 'x');
    await write('debug.log', 'noise');

    final info = await reader.read(repo.path);
    expect(info, isNotNull);
    // Pasta colapsada → 'build' (sem barra); arquivo solto → 'debug.log'.
    expect(info!.ignored, containsAll(<String>{'build', 'debug.log'}));
    // Ignorados não entram em files nem contam como sujo.
    expect(info.files.containsKey('build/out.bin'), isFalse);
    expect(info.isDirty, isFalse);
    // Cobertura sob a raiz colapsada.
    expect(info.isIgnored('build/out.bin'), isTrue);
    expect(info.isIgnored('debug.log'), isTrue);
    expect(info.isIgnored('lib/app.dart'), isFalse);
  });

  test('ahead/behind vs upstream local', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    // Cria um "remoto" como clone bare e configura upstream.
    final bare = await Directory.systemTemp.createTemp('cockpit_bare_');
    addTearDown(() => bare.delete(recursive: true));
    await git(['clone', '--bare', repo.path, bare.path]);
    await git(['remote', 'add', 'origin', bare.path]);
    final branch = (await git([
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ])).stdout.toString().trim();
    await git(['push', '-u', 'origin', branch]);

    // Um commit local não-pushed → ahead 1, behind 0.
    await write('ahead.txt', '1');
    await git(['add', '.']);
    await git(['commit', '-m', 'ahead']);

    final info = await reader.read(repo.path);
    expect(info!.ahead, 1);
    expect(info.behind, 0);
  });
}
