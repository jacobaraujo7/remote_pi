import 'package:cockpit/app/cockpit/domain/contracts/git_head_baseline_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_head_baseline.dart';
import 'package:cockpit/app/cockpit/domain/entities/scm_line_decorations.dart';
import 'package:cockpit/app/cockpit/domain/services/scm_baseline_cache.dart';
import 'package:cockpit/app/cockpit/domain/services/scm_line_decoration_calculator.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/scm_line_decoration_coordinator.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Espelha a política de `_ensureScmCoordinator` / `openFile` / `openChangedFile`
/// / `_restoreSession(viewer)` do `CockpitViewModel` sem montar o VM inteiro
/// (31 deps).
class _FakeReader implements GitHeadBaselineReader {
  _FakeReader(this.blobs);

  String? head = 'aaa';
  final Map<String, String> blobs;
  int readCalls = 0;

  @override
  Future<String?> resolveHeadIdentity(String repoPath) async => head;

  @override
  Future<GitHeadBaseline?> readTrackedText(
    String repoPath,
    String absPath,
  ) async {
    readCalls++;
    final id = head;
    final text = blobs[absPath];
    if (id == null || text == null) return null;
    return GitHeadBaseline(headIdentity: id, content: text);
  }
}

void _flush(FakeAsync async) {
  async.flushMicrotasks();
  async.elapse(Duration.zero);
  async.flushMicrotasks();
}

/// Mesma regra do VM: textual editável, não-scratch → attach uma vez.
void ensureScmCoordinator(
  FileViewerSession session, {
  required ScmBaselineCache cache,
  required String? Function(String path) resolveGitRoot,
}) {
  final editable =
      session.view is FileViewText ||
      session.view is FileViewMarkdown ||
      session.view is FileViewSvg;
  if (session.scratch || !editable) {
    session.clearScmDecorations();
    return;
  }
  if (session.scmCoordinator != null) return;
  session.attachScmCoordinator(
    ScmLineDecorationCoordinator(
      session: session,
      cache: cache,
      calculator: const ScmLineDecorationCalculator(),
      resolveGitRoot: resolveGitRoot,
      debounce: Duration.zero,
    ),
  );
}

void main() {
  test('abertura normal de arquivo textual anexa um coordenador', () {
    fakeAsync((async) {
      final fake = _FakeReader({'/repo/a.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      final session = FileViewerSession(
        id: 'v1',
        projectId: 'p',
        path: '/repo/a.txt',
        view: const FileViewText('a\nb\n', language: 'txt'),
      );

      ensureScmCoordinator(
        session,
        cache: cache,
        resolveGitRoot: (_) => '/repo',
      );
      expect(session.scmCoordinator, isNotNull);

      final ctrl = CodeEditingController(text: 'a\nb\n', language: 'txt');
      session.scmCoordinator!.attachController(ctrl);
      _flush(async);
      expect(session.scmDecorations.addedLines, contains(2));

      session.dispose();
      ctrl.dispose();
    });
  });

  test('arquivo já aberto: ensure não duplica o coordenador', () {
    final fake = _FakeReader({'/repo/a.txt': 'a\n'});
    final cache = ScmBaselineCache(fake);
    final session = FileViewerSession(
      id: 'v1',
      projectId: 'p',
      path: '/repo/a.txt',
      view: const FileViewText('a\n', language: 'txt'),
    );

    ensureScmCoordinator(session, cache: cache, resolveGitRoot: (_) => '/repo');
    final first = session.scmCoordinator;
    ensureScmCoordinator(session, cache: cache, resolveGitRoot: (_) => '/repo');
    expect(session.scmCoordinator, same(first));

    session.dispose();
  });

  test('restauração de sessão: ensure anexa coordenador como na abertura', () {
    fakeAsync((async) {
      final fake = _FakeReader({'/repo/a.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      // Espelha `_restoreSession(viewer)`: cria a sessão e só depois ensure
      // (antes do FileViewer montar / attachController).
      final session = FileViewerSession(
        id: 'v-restored',
        projectId: 'p',
        path: '/repo/a.txt',
        view: const FileViewText('a\nb\n', language: 'txt'),
      );
      expect(session.scmCoordinator, isNull);

      ensureScmCoordinator(
        session,
        cache: cache,
        resolveGitRoot: (_) => '/repo',
      );
      expect(session.scmCoordinator, isNotNull);

      final ctrl = CodeEditingController(text: 'a\nb\n', language: 'txt');
      session.scmCoordinator!.attachController(ctrl);
      _flush(async);
      expect(session.scmDecorations.addedLines, contains(2));

      session.dispose();
      ctrl.dispose();
    });
  });

  test('attachScmCoordinator notifica para bind tardio do controller', () {
    fakeAsync((async) {
      final fake = _FakeReader({'/repo/a.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      final session = FileViewerSession(
        id: 'v1',
        projectId: 'p',
        path: '/repo/a.txt',
        view: const FileViewText('a\nb\n', language: 'txt'),
      );

      var notified = 0;
      session.addListener(() => notified++);

      ensureScmCoordinator(
        session,
        cache: cache,
        resolveGitRoot: (_) => '/repo',
      );
      expect(notified, greaterThan(0));
      expect(session.scmCoordinator, isNotNull);

      // Simula FileViewer que só liga o controller ao receber o notify.
      final ctrl = CodeEditingController(text: 'a\nb\n', language: 'txt');
      session.scmCoordinator!.attachController(ctrl);
      _flush(async);
      expect(session.scmDecorations.addedLines, contains(2));

      session.dispose();
      ctrl.dispose();
    });
  });

  test(
    'abertura via Source Control não injeta sets — só o coordenador publica',
    () {
      fakeAsync((async) {
        final fake = _FakeReader({'/repo/a.txt': 'base\n'});
        final cache = ScmBaselineCache(fake);
        final session = FileViewerSession(
          id: 'v1',
          projectId: 'p',
          path: '/repo/a.txt',
          view: const FileViewText('base\nedit\n', language: 'txt'),
          isPreview: false,
        );

        // openChangedFile → openFile(isPreview: false) → ensure + attach.
        expect(session.scmDecorations, ScmLineDecorations.empty);
        ensureScmCoordinator(
          session,
          cache: cache,
          resolveGitRoot: (_) => '/repo',
        );
        final ctrl = CodeEditingController(
          text: 'base\nedit\n',
          language: 'txt',
        );
        session.scmCoordinator!.attachController(ctrl);
        _flush(async);

        expect(session.scmDecorations.addedLines, contains(2));
        // Sem API de injeção pontual: só setScmDecorations do coordenador.
        expect(session.scmDecorations.modifiedLines, isEmpty);

        session.dispose();
        ctrl.dispose();
      });
    },
  );

  test('múltiplas Git roots: resolveGitRoot escolhe a root dona', () {
    fakeAsync((async) {
      final fake = _FakeReader({
        '/ws/a/f.txt': 'from-a\n',
        '/ws/b/f.txt': 'from-b\n',
      });
      final cache = ScmBaselineCache(fake);
      final session = FileViewerSession(
        id: 'v1',
        projectId: 'p',
        path: '/ws/b/f.txt',
        view: const FileViewText('from-b\nx\n', language: 'txt'),
      );
      final roots = <String>[];
      ensureScmCoordinator(
        session,
        cache: cache,
        resolveGitRoot: (path) {
          final root = path.startsWith('/ws/a')
              ? '/ws/a'
              : path.startsWith('/ws/b')
              ? '/ws/b'
              : null;
          if (root != null) roots.add(root);
          return root;
        },
      );
      final ctrl = CodeEditingController(text: 'from-b\nx\n', language: 'txt');
      session.scmCoordinator!.attachController(ctrl);
      _flush(async);

      expect(roots, contains('/ws/b'));
      expect(roots, isNot(contains('/ws/a')));
      expect(session.scmDecorations.addedLines, contains(2));

      session.dispose();
      ctrl.dispose();
    });
  });

  test('arquivo fora de repositório permanece sem decorações', () {
    fakeAsync((async) {
      final fake = _FakeReader({'/tmp/x.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      final session = FileViewerSession(
        id: 'v1',
        projectId: 'p',
        path: '/tmp/x.txt',
        view: const FileViewText('a\nb\n', language: 'txt'),
      );
      ensureScmCoordinator(session, cache: cache, resolveGitRoot: (_) => null);
      final ctrl = CodeEditingController(text: 'a\nb\n', language: 'txt');
      session.scmCoordinator!.attachController(ctrl);
      _flush(async);

      expect(session.scmDecorations, ScmLineDecorations.empty);
      expect(fake.readCalls, 0);

      session.dispose();
      ctrl.dispose();
    });
  });

  test('preview reuse limpa decorações antes de recarregar o path novo', () {
    fakeAsync((async) {
      final fake = _FakeReader({
        '/repo/old.txt': 'old\n',
        '/repo/new.txt': 'new\n',
      });
      final cache = ScmBaselineCache(fake);
      final session = FileViewerSession(
        id: 'v1',
        projectId: 'p',
        path: '/repo/old.txt',
        view: const FileViewText('old\nx\n', language: 'txt'),
        isPreview: true,
      );
      ensureScmCoordinator(
        session,
        cache: cache,
        resolveGitRoot: (_) => '/repo',
      );
      final ctrl = CodeEditingController(text: 'old\nx\n', language: 'txt');
      session.scmCoordinator!.attachController(ctrl);
      _flush(async);
      expect(session.scmDecorations.isEmpty, isFalse);

      // Espelha openFile preview reuse.
      session.path = '/repo/new.txt';
      session.view = const FileViewText('new\n', language: 'txt');
      session.setScmDecorations(ScmLineDecorations.empty);
      ensureScmCoordinator(
        session,
        cache: cache,
        resolveGitRoot: (_) => '/repo',
      );
      expect(session.scmCoordinator, isNotNull);
      ctrl.text = 'new\n';
      session.scmCoordinator!.onSessionPathChanged();
      _flush(async);
      expect(session.scmDecorations, ScmLineDecorations.empty);

      session.dispose();
      ctrl.dispose();
    });
  });

  test('scratch / Untitled limpa coordenador e decorações', () {
    final fake = _FakeReader({});
    final cache = ScmBaselineCache(fake);
    final session = FileViewerSession(
      id: 'v1',
      projectId: 'p',
      path: '',
      view: const FileViewText('x\n', language: 'dbq'),
      scratch: true,
      scratchTitle: 'Untitled-1.dbq',
    );
    session.setScmDecorations(
      const ScmLineDecorations(
        addedLines: {1},
        modifiedLines: {},
        removalBoundaries: {},
      ),
    );
    ensureScmCoordinator(session, cache: cache, resolveGitRoot: (_) => '/repo');
    expect(session.scmCoordinator, isNull);
    expect(session.scmDecorations, ScmLineDecorations.empty);
    session.dispose();
  });
}
