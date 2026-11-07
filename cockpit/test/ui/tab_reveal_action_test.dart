import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/neovim_session.dart';
import 'package:cockpit/app/cockpit/ui/session/notebook_session.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/task_output_session.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/contracts/neovim_gateway.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopGateway implements TerminalGateway {
  @override
  SpawnDirectory? get spawnDirectory => null;

  @override
  int? get rootProcessId => null;

  @override
  int? get wslProcessId => null;

  final _out = StreamController<List<int>>();

  @override
  Stream<List<int>> get output => _out.stream;

  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const <String, String>{},
  }) {}

  @override
  void write(List<int> data) {}

  @override
  void resize(int rows, int columns) {}

  @override
  void acknowledgeOutput() {}

  @override
  Future<void> kill() async {
    await _out.close();
  }
}

class _FakeNeovimGateway extends Fake implements NeovimGateway {}

String? resolveRevealTarget(PaneItem? s) => switch (s) {
  final FileViewerSession v => v.scratch ? null : v.path,
  final NotebookSession n => n.path,
  final OrchestrationSession o => o.path,
  final NeovimSession n => n.lastPath.isNotEmpty
      ? n.lastPath
      : (n.currentDirectory ?? n.workingDirectory),
  final TerminalSession t => t.currentDirectory ?? t.workingDirectory,
  final TaskOutputSession task => task.workingDirectory,
  _ => null,
};

void main() {
  setUp(() {
    LocaleSettings.setLocale(AppLocale.ptBr);
  });

  group('resolveRevealTarget', () {
    test('para FileViewerSession normal devolve o caminho do arquivo', () {
      final session = FileViewerSession(
        id: 'f1',
        projectId: 'p1',
        path: '/workspace/lib/main.dart',
        view: const FileViewText(''),
      );
      expect(resolveRevealTarget(session), '/workspace/lib/main.dart');
    });

    test('para FileViewerSession scratch devolve null (nao salvo em disco)', () {
      final session = FileViewerSession(
        id: 'f2',
        projectId: 'p1',
        path: 'scratch:1',
        scratch: true,
        view: const FileViewText(''),
      );
      expect(resolveRevealTarget(session), isNull);
    });

    test('para TerminalSession devolve workingDirectory ou currentDirectory', () {
      final session = TerminalSession(
        id: 't1',
        projectId: 'p1',
        workingDirectory: '/workspace/backend',
        gateway: _NoopGateway(),
        profile: const TerminalProfile(
          id: 'login-shell',
          label: 'sh',
          executable: '/bin/sh',
        ),
      );
      expect(resolveRevealTarget(session), '/workspace/backend');
    });

    test('para NeovimSession devolve lastPath quando presente', () {
      final session = NeovimSession(
        id: 'n1',
        projectId: 'p1',
        workingDirectory: '/workspace',
        terminalGateway: _NoopGateway(),
        neovimGateway: _FakeNeovimGateway(),
        serverAddress: '127.0.0.1:1234',
        executable: '/usr/bin/nvim',
        lastPath: '/workspace/lib/test.dart',
        engine: TerminalEngine.xterm,
      );
      expect(resolveRevealTarget(session), '/workspace/lib/test.dart');
    });

    test('para NotebookSession devolve o path do caderno', () {
      final session = NotebookSession(
        id: 'nb1',
        projectId: 'p1',
        path: '/workspace/notes',
      );
      expect(resolveRevealTarget(session), '/workspace/notes');
    });
  });

  group('i18n de revelar arquivo', () {
    test('strings estao presentes em pt-BR', () {
      LocaleSettings.setLocale(AppLocale.ptBr);
      expect(t.cockpit.paneView.revealInExplorer, 'Abrir local no Explorer');
      expect(t.cockpit.paneView.revealInFinder, 'Abrir local no Finder');
      expect(t.cockpit.paneView.revealInFileManager, 'Abrir no gerenciador de arquivos');
    });

    test('strings estao presentes em en', () {
      LocaleSettings.setLocale(AppLocale.en);
      expect(t.cockpit.paneView.revealInExplorer, 'Open in Explorer');
      expect(t.cockpit.paneView.revealInFinder, 'Open in Finder');
      expect(t.cockpit.paneView.revealInFileManager, 'Open in file manager');
    });
  });
}
