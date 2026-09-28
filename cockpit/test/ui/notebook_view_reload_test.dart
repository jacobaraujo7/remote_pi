import 'dart:async';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/ui/session/document_host.dart';
import 'package:cockpit/app/cockpit/ui/session/notebook_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/notebook_view.dart';
import 'package:cockpit/app/core/domain/exceptions/file_operation_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/markdown_editing_controller.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const _dir = '/repo/notes.notebook';
const _note = '$_dir/ideia.md';

String _raw(String body) => '---\ntitle: Ideia\ntags: [agent]\n---\n\n$body';

/// Caderno em memória: o "agente" escreve em [files] e dispara [changes].
class _FakeHost implements DocumentHost {
  final files = <String, String>{_note: _raw('primeira versão')};
  final changes = StreamController<void>.broadcast();

  @override
  Future<List<FileNode>> listChildren(String path) async => [
    for (final p in files.keys)
      FileNode(name: p.split('/').last, path: p, isDirectory: false),
  ];

  @override
  Future<String?> readTextAt(String path) async => files[path];

  @override
  Future<bool> writeTextAt(String path, String content) async {
    files[path] = content;
    return true;
  }

  @override
  Stream<void> watchFolder(String path) => changes.stream;

  @override
  Future<bool> writeBytesAt(String path, Uint8List bytes) async => true;

  @override
  Future<Result<void, FileOperationError>> deletePath(String path) async =>
      const Success(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('depois de o usuário editar e salvar, a nota aberta volta a '
      'adotar o que o agente grava', (tester) async {
    final host = _FakeHost();
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: DocumentHostScope(
              host: host,
              child: NotebookView(
                session: NotebookSession(id: 'n', projectId: '', path: _dir),
                active: true,
                focused: true,
                workspaceRoot: '/repo',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final body = find.byWidgetPredicate(
      (w) => w is EditableText && w.controller is MarkdownEditingController,
    );
    String bodyText() => tester.widget<EditableText>(body).controller.text;
    expect(bodyText(), 'primeira versão');

    // Usuário edita; o autosave grava.
    await tester.enterText(body, 'versão do usuário');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(host.files[_note], contains('versão do usuário'));

    // Agente reescreve a nota: tem de aparecer sem clicar em nada.
    host.files[_note] = _raw('versão do agente');
    host.changes.add(null);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(bodyText(), 'versão do agente');
  });
}
