import 'package:cockpit/app/cockpit/domain/services/file_editor_facade.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<FileEditorEngine> calls;
  late FileEditorFacade facade;

  FileOpenRequest request(
    String path, {
    bool remote = false,
    bool source = false,
    bool notebook = false,
  }) => FileOpenRequest(
    path: path,
    projectId: 'project',
    paneId: 'pane',
    isRemote: remote,
    asSource: source,
    isNotebook: notebook,
  );

  setUp(() {
    calls = [];
    facade = FileEditorFacade(
      FileEditorRegistry({
        FileEditorEngine.cockpit: (request) async {
          calls.add(FileEditorEngine.cockpit);
          return FileOpenOutcome.opened;
        },
        FileEditorEngine.neovim: (request) async {
          calls.add(FileEditorEngine.neovim);
          return FileOpenOutcome.opened;
        },
      }),
    )..engine = FileEditorEngine.neovim;
  });

  test('routes ordinary local text through the selected engine', () async {
    await facade.open(request('/repo/lib/main.dart'));
    expect(calls, [FileEditorEngine.neovim]);
  });

  test('keeps remote and specialized content in Cockpit', () async {
    for (final value in [
      request('/repo/main.dart', remote: true),
      request('/repo/request.http'),
      request('/repo/query.dbq'),
      request('/repo/board.kanban'),
      request('/repo/logo.svg'),
      request('/repo/image.png'),
      request('/repo/project.notebook', notebook: true),
    ]) {
      calls.clear();
      await facade.open(value);
      expect(calls, [FileEditorEngine.cockpit]);
    }
  });

  test('source action sends specialized text to selected engine', () async {
    await facade.open(request('/repo/board.kanban', source: true));
    expect(calls, [FileEditorEngine.neovim]);
  });

  test('falls back exactly once when external engine cannot open', () async {
    facade = FileEditorFacade(
      FileEditorRegistry({
        FileEditorEngine.cockpit: (request) async {
          calls.add(FileEditorEngine.cockpit);
          return FileOpenOutcome.opened;
        },
        FileEditorEngine.neovim: (request) async {
          calls.add(FileEditorEngine.neovim);
          return FileOpenOutcome.notHandled;
        },
      }),
    )..engine = FileEditorEngine.neovim;

    final result = await facade.open(request('/repo/main.dart'));
    expect(result.engine, FileEditorEngine.cockpit);
    expect(result.outcome, FileOpenOutcome.opened);
    expect(calls, [FileEditorEngine.neovim, FileEditorEngine.cockpit]);
  });
}
