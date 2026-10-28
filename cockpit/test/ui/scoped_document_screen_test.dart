import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/contracts/file_change_watcher.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/document/document_window_app.dart';
import 'package:cockpit/app/cockpit/ui/document/worktree_document_host.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_viewer.dart';
import 'package:cockpit/app/cockpit/ui/widgets/layout_preview_view.dart';
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class _Settings extends SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

class _Files implements FileService {
  Uint8List bytes = Uint8List.fromList(utf8.encode('remote source'));
  Future<Uint8List>? pending;
  Object? error;
  final writes = <Uint8List>[];
  @override
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024}) async {
    if (error case final problem?) throw problem;
    if (pending case final reading?) return await reading;
    return bytes;
  }

  @override
  Future<void> write(String path, Uint8List value) async {
    writes.add(value);
    bytes = value;
  }

  @override
  Future<String> home() async => '/source';
  @override
  Future<List<FileEntry>> list(String path) async => [];
}

class _Changes implements FileChangeWatcher {
  final controller = StreamController<void>.broadcast();
  @override
  Stream<void> watchFile(String path) => controller.stream;
  @override
  Stream<void> watchFolder(String path) => controller.stream;
}

WorktreeDocumentHost _host(_Files files, _Changes changes) =>
    WorktreeDocumentHost(
      workspaceRoot: '/source',
      changes: changes,
      files: files,
      remote: true,
      available: () => true,
    );

Widget _app(Widget child) => ModularApp(
  module: createModule(register: (_) {}),
  provide: (scope) => scope
    ..addChangeNotifier<SettingsController>(
      () => SettingsController(_Settings()),
    )
    ..addChangeNotifier<EditorMenuBridge>(() => EditorMenuBridge()),
  child: TranslationProvider(
    child: ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      builder: (context, body) {
        final tokens = buildTokens(
          brightness: Brightness.dark,
          settings: const AppSettings(),
        );
        return CockpitTheme(
          colors: tokens.colors,
          typo: tokens.typo,
          syntax: tokens.syntax,
          terminal: tokens.terminal,
          child: body!,
        );
      },
      home: Scaffold(child: child),
    ),
  ),
);

Future<void> _settleRead(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets(
    'menu notification queued during teardown is cancelled by dispose',
    (tester) async {
      final bridge = EditorMenuBridge();
      final owner = Object();
      var saves = 0;
      bridge.publish(
        owner: owner,
        canSave: true,
        canDiscard: true,
        canFormat: true,
        onSave: () => saves++,
        onDiscard: () {},
        onFormat: () {},
      );
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            bridge.clear(owner);
            bridge.dispose();
            return const SizedBox();
          },
        ),
      );
      await tester.pump();
      bridge.save();
      expect(saves, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'remote HTML uses the explicit host without any global VM binding',
    (tester) async {
      final files = _Files()
        ..bytes = Uint8List.fromList(utf8.encode('<h1>remote</h1>'));
      final changes = _Changes();
      FileViewerSession? session;
      await tester.pumpWidget(
        _app(
          DocumentScreen(
            path: '/source/page.html',
            host: _host(files, changes),
            projectId: 'original-worktree',
            sessionId: 'owned-document',
            revealLine: 1,
            onSession: (value) => session = value,
          ),
        ),
      );
      await _settleRead(tester);
      final viewer = tester.widget<FileViewer>(find.byType(FileViewer));
      expect(viewer.allowLocalFileSystem, isFalse);
      expect(session!.projectId, 'original-worktree');
      expect(session!.id, 'owned-document');
      expect((session!.view as FileViewText).text, '<h1>remote</h1>');
      expect(session!.revealLine, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await changes.controller.close();
    },
  );

  testWidgets(
    'switching hosts at the same path discards the old pending read',
    (tester) async {
      final oldRead = Completer<Uint8List>();
      final firstFiles = _Files()..pending = oldRead.future;
      final secondFiles = _Files()
        ..bytes = Uint8List.fromList(utf8.encode('second host'));
      final changes = _Changes();
      FileViewerSession? session;
      DocumentScreen screen(WorktreeDocumentHost host) => DocumentScreen(
        path: '/same/note.txt',
        host: host,
        sessionId: 'document',
        onSession: (value) => session = value,
      );
      final current = ValueNotifier(screen(_host(firstFiles, changes)));
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<DocumentScreen>(
            valueListenable: current,
            builder: (context, value, _) => value,
          ),
        ),
      );
      await tester.pump();
      current.value = screen(_host(secondFiles, changes));
      await _settleRead(tester);
      expect((session!.view as FileViewText).text, 'second host');
      final secondSession = session;
      oldRead.complete(Uint8List.fromList(utf8.encode('stale first host')));
      await _settleRead(tester);
      expect(session, same(secondSession));
      expect((session!.view as FileViewText).text, 'second host');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      current.dispose();
      await changes.controller.close();
    },
  );

  testWidgets('read failure retains last valid content and retry recovers', (
    tester,
  ) async {
    final files = _Files();
    final changes = _Changes();
    FileViewerSession? session;
    await tester.pumpWidget(
      _app(
        DocumentScreen(
          path: '/source/note.txt',
          host: _host(files, changes),
          onSession: (value) => session = value,
        ),
      ),
    );
    await _settleRead(tester);
    final original = session;
    files.error = const FileException(FileErrorKind.io, 'source offline');
    changes.controller.add(null);
    await _settleRead(tester);
    expect(session, same(original));
    expect((session!.view as FileViewText).text, 'remote source');
    expect(find.textContaining('source offline'), findsOneWidget);
    files.error = null;
    files.bytes = Uint8List.fromList(utf8.encode('recovered source'));
    await tester.tap(find.text('Retry'));
    await _settleRead(tester);
    expect((session!.view as FileViewText).text, 'recovered source');
    expect(find.textContaining('source offline'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await changes.controller.close();
  });

  testWidgets(
    'saving through the captured host preserves the source encoding',
    (tester) async {
      final files = _Files()..bytes = Uint8List.fromList(latin1.encode('café'));
      final changes = _Changes();
      FileViewerSession? session;
      await tester.pumpWidget(
        _app(
          DocumentScreen(
            path: '/source/note.txt',
            host: _host(files, changes),
            onSession: (value) => session = value,
          ),
        ),
      );
      await _settleRead(tester);
      await tester.enterText(find.byType(EditableText).first, 'café2');
      await tester.pump();
      expect(session!.dirty, isTrue);
      expect(await tester.runAsync(() => session!.saveDraft!()), isTrue);
      await _settleRead(tester);
      expect(files.writes.single, latin1.encode('café2'));
      expect(session!.dirty, isFalse);
      await tester.enterText(find.byType(EditableText).first, 'café 🙂');
      await tester.pump();
      expect(await tester.runAsync(() => session!.saveDraft!()), isTrue);
      await _settleRead(tester);
      expect(utf8.decode(files.writes.last), 'café 🙂');
      expect((session!.view as FileViewText).encoding, utf8);
      expect(session!.dirty, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await changes.controller.close();
    },
  );

  testWidgets('scoped layout previews cannot apply a global workspace layout', (
    tester,
  ) async {
    final files = _Files()
      ..bytes = Uint8List.fromList(
        utf8.encode('panes:\n  - name: Worker\n    command: echo test\n'),
      );
    final changes = _Changes();
    await tester.pumpWidget(
      _app(
        DocumentScreen(path: '/source/work.ckp', host: _host(files, changes)),
      ),
    );
    await _settleRead(tester);
    expect(
      tester.widget<LayoutPreviewView>(find.byType(LayoutPreviewView)).primary,
      isNull,
    );
    expect(find.text('Worker'), findsOneWidget);
    expect(find.byType(PrimaryButton), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await changes.controller.close();
  });
}
