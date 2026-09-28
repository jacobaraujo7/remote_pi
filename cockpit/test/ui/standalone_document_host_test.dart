import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/disk_file_change_watcher.dart';
import 'package:cockpit/app/cockpit/ui/document/document_windows.dart';
import 'package:cockpit/app/cockpit/ui/document/standalone_document_host.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('doc-host-'));
  tearDown(() => tmp.delete(recursive: true));

  test(
    'raiz = pasta com .git acima do arquivo; sem repo, a pasta do arquivo',
    () async {
      final repo = await Directory('${tmp.path}/repo').create();
      await Directory('${repo.path}/.git').create();
      final deep = await Directory(
        '${repo.path}/docs/notes',
      ).create(recursive: true);
      final file = File('${deep.path}/x.md')..writeAsStringSync('# x');
      expect(StandaloneDocumentHost.findWorkspaceRoot(file.path), repo.path);
      final loose = File('${tmp.path}/loose.md')..writeAsStringSync('');
      expect(StandaloneDocumentHost.findWorkspaceRoot(loose.path), tmp.path);

      final host = StandaloneDocumentHost(
        workspaceRoot: repo.path,
        changes: const DiskFileChangeWatcher(),
      );
      expect(host.displayPath('', file.path), 'docs/notes/x.md');
      expect(host.displayPath('', loose.path), loose.path);
    },
  );

  test('filesystem: lista (pastas primeiro), lê, grava e apaga', () async {
    final host = StandaloneDocumentHost(
      workspaceRoot: tmp.path,
      changes: const DiskFileChangeWatcher(),
    );
    await Directory('${tmp.path}/b-dir').create();
    await File('${tmp.path}/a.txt').writeAsString('a');
    final kids = await host.listChildren(tmp.path);
    expect(kids.map((k) => k.name), ['b-dir', 'a.txt']);
    expect(await host.readTextAt('${tmp.path}/a.txt'), 'a');
    expect(await host.readTextAt('${tmp.path}/nope'), isNull);
    expect(await host.writeTextAt('${tmp.path}/a.txt', 'b'), isTrue);
    expect(await host.readTextAt('${tmp.path}/a.txt'), 'b');
    expect(
      await host.deletePath('${tmp.path}/a.txt'),
      isA<Success<void, Object>>(),
    );
    expect(
      await host.deletePath('${tmp.path}/a.txt'),
      isA<Failure<void, Object>>(),
    );
  });

  test('LSP e SCM são no-ops seguros', () async {
    final host = StandaloneDocumentHost(
      workspaceRoot: '',
      changes: const DiskFileChangeWatcher(),
    );
    await host.lspOpenDocument('/x', '', '');
    expect(await host.lspFormat('/x', 'a'), isEmpty);
    expect((await host.lspSemanticTokensFull('/x')).tokens, isEmpty);
    expect(await host.lspDiagnostics.isEmpty, isTrue);
    expect(host.projectRootOf(''), isNull);
  });

  test('argumentos da janela de documento fazem round-trip', () {
    final args = DocumentWindows.argumentsFor('/tmp/board.kanban');
    expect(
      DocumentWindows.pathFromArguments(['multi_window', '3', args]),
      '/tmp/board.kanban',
    );
    expect(DocumentWindows.pathFromArguments(const []), isNull);
    expect(
      DocumentWindows.pathFromArguments(['multi_window', '3', 'not json']),
      isNull,
    );
  });
}
