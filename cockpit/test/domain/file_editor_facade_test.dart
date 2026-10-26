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
    bool previewTab = true,
  }) => FileOpenRequest(
    path: path,
    projectId: 'project',
    paneId: 'pane',
    isRemote: remote,
    isPreview: previewTab,
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

  test(
    'previews supported visual types and edits their source in Neovim',
    () async {
      for (final path in [
        '/repo/README.md',
        '/repo/page.mdx',
        '/repo/readme.markdown',
        '/repo/page.html',
        '/repo/page.htm',
        '/repo/logo.svg',
        '/repo/tool.panel',
        '/repo/board.kanban',
        '/repo/layout.ckp',
      ]) {
        calls.clear();
        await facade.open(request(path));
        expect(calls, [FileEditorEngine.cockpit], reason: path);
        calls.clear();
        await facade.open(request(path, source: true));
        expect(calls, [FileEditorEngine.neovim], reason: path);
      }
    },
  );

  test(
    'pinned Markdown, SVG and HTML opens still use Cockpit preview',
    () async {
      for (final path in [
        '/repo/README.MD',
        '/repo/logo.SVG',
        '/repo/page.HTML',
      ]) {
        calls.clear();
        await facade.open(request(path, previewTab: false));
        expect(calls, [FileEditorEngine.cockpit], reason: path);
      }
    },
  );

  test('HTML and panel need an inline preview', () async {
    facade.inlinePreviewAvailable = false;
    for (final path in ['/repo/page.html', '/repo/tool.panel']) {
      calls.clear();
      await facade.open(request(path));
      expect(calls, [FileEditorEngine.neovim]);
    }
    calls.clear();
    await facade.open(request('/repo/README.md'));
    expect(calls, [FileEditorEngine.cockpit]);
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
