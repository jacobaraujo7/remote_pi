import 'dart:async';

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

class _FakeReader implements GitHeadBaselineReader {
  _FakeReader({Map<String, String>? blobs})
    : blobs = blobs ?? <String, String>{};

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

FileViewerSession _session({
  String path = '/repo/a.txt',
  bool scratch = false,
}) {
  return FileViewerSession(
    id: 's1',
    projectId: '/repo',
    path: path,
    view: const FileViewText('a\nb\n', language: 'txt'),
    scratch: scratch,
  );
}

ScmLineDecorationCoordinator _coord(
  FileViewerSession session,
  ScmBaselineCache cache, {
  String? Function(String path)? resolveGitRoot,
  Duration debounce = const Duration(milliseconds: 120),
}) {
  return ScmLineDecorationCoordinator(
    session: session,
    cache: cache,
    calculator: const ScmLineDecorationCalculator(),
    resolveGitRoot: resolveGitRoot ?? ((_) => '/repo'),
    debounce: debounce,
  );
}

/// [Future] event-loop callbacks + timers (debounce / `Future(() => …)`).
void _flush(FakeAsync async) {
  async.flushMicrotasks();
  async.elapse(Duration.zero);
  async.flushMicrotasks();
}

void main() {
  test('debounce coalesces rapid buffer edits into one publish', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/repo/a.txt': 'a\nb\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session();
      final coord = _coord(session, cache);
      final ctrl = CodeEditingController(text: 'a\nb\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);
      expect(session.scmDecorations, ScmLineDecorations.empty);

      ctrl.text = 'a\nb\nc\n';
      ctrl.text = 'a\nb\nc\nd\n';
      async.elapse(const Duration(milliseconds: 50));
      expect(session.scmDecorations, ScmLineDecorations.empty);

      async.elapse(const Duration(milliseconds: 80));
      _flush(async);
      expect(session.scmDecorations.addedLines, isNotEmpty);

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('unsaved buffer differs from HEAD → decorations without save', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/repo/a.txt': 'hello\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session();
      final coord = _coord(session, cache, debounce: Duration.zero);
      final ctrl = CodeEditingController(
        text: 'hello\nworld\n',
        language: 'txt',
      );
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);

      expect(session.scmDecorations.addedLines, contains(2));

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('undo back to HEAD clears decorations', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/repo/a.txt': 'hello\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session();
      final coord = _coord(session, cache);
      final ctrl = CodeEditingController(text: 'hello\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);
      expect(session.scmDecorations.isEmpty, isTrue);

      ctrl.text = 'hello\nworld\n';
      async.elapse(const Duration(milliseconds: 120));
      _flush(async);
      expect(session.scmDecorations.isEmpty, isFalse);

      ctrl.text = 'hello\n';
      async.elapse(const Duration(milliseconds: 120));
      _flush(async);
      expect(session.scmDecorations, ScmLineDecorations.empty);

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('stale async result is discarded after newer buffer revision', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/repo/a.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session();
      final coord = _coord(session, cache);
      final ctrl = CodeEditingController(text: 'a\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);

      ctrl.text = 'a\nb\n';
      async.elapse(const Duration(milliseconds: 120));
      // Bump revision before the scheduled calculate Future publishes.
      ctrl.text = 'a\n';
      _flush(async);
      async.elapse(const Duration(milliseconds: 120));
      _flush(async);
      expect(session.scmDecorations, ScmLineDecorations.empty);

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('git revision change reloads baseline and recalculates', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/repo/a.txt': 'v1\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session();
      final coord = _coord(session, cache, debounce: Duration.zero);
      final ctrl = CodeEditingController(text: 'v1\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);
      expect(session.scmDecorations.isEmpty, isTrue);

      fake.head = 'bbb';
      fake.blobs['/repo/a.txt'] = 'v2\n';
      coord.onGitRevisionChanged();
      _flush(async);

      // Buffer ainda é v1; HEAD agora é v2 → diferença.
      expect(session.scmDecorations.isEmpty, isFalse);
      expect(fake.readCalls, greaterThanOrEqualTo(2));

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('external content adoption schedules recalculation', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/repo/a.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session();
      final coord = _coord(session, cache);
      final ctrl = CodeEditingController(text: 'a\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);

      ctrl.value = const TextEditingValue(text: 'a\nb\n');
      coord.onExternalContentAdopted();
      async.elapse(const Duration(milliseconds: 120));
      _flush(async);
      expect(session.scmDecorations.addedLines, contains(2));

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('preview reuse / path change clears then reloads for new path', () {
    fakeAsync((async) {
      final fake = _FakeReader(
        blobs: {'/repo/old.txt': 'old\n', '/repo/new.txt': 'new\n'},
      );
      final cache = ScmBaselineCache(fake);
      final session = _session(path: '/repo/old.txt');
      final coord = _coord(session, cache, debounce: Duration.zero);
      final ctrl = CodeEditingController(text: 'old\nx\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);
      expect(session.scmDecorations.isEmpty, isFalse);

      session.path = '/repo/new.txt';
      ctrl.text = 'new\n';
      session.setScmDecorations(ScmLineDecorations.empty);
      coord.onSessionPathChanged();
      _flush(async);

      expect(session.scmDecorations, ScmLineDecorations.empty);

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('retarget notifies coordinator and clears stale markers', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/repo/a.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session(path: '/repo/a.txt');
      final coord = _coord(session, cache, debounce: Duration.zero);
      final ctrl = CodeEditingController(text: 'a\nb\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);
      expect(session.scmDecorations.addedLines, isNotEmpty);

      // b.txt não tem blob no fake → inelegível.
      session.retarget('/repo/b.txt');
      _flush(async);
      expect(session.scmDecorations, ScmLineDecorations.empty);

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('dispose cancels pending debounce and keeps empty decorations', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/repo/a.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session();
      final coord = _coord(session, cache);
      final ctrl = CodeEditingController(text: 'a\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);

      ctrl.text = 'a\nb\n';
      coord.dispose();
      async.elapse(const Duration(milliseconds: 200));
      _flush(async);
      expect(session.scmDecorations, ScmLineDecorations.empty);

      ctrl.dispose();
      session.dispose();
    });
  });

  test('outside git root publishes empty and never reads baseline', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/outside/a.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session(path: '/outside/a.txt');
      final coord = _coord(
        session,
        cache,
        resolveGitRoot: (_) => null,
        debounce: Duration.zero,
      );
      final ctrl = CodeEditingController(text: 'a\nb\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);

      expect(session.scmDecorations, ScmLineDecorations.empty);
      expect(fake.readCalls, 0);

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('multi-root resolve picks the owning root for baseline lookup', () {
    fakeAsync((async) {
      final fake = _FakeReader(blobs: {'/ws/b/file.txt': 'root-b\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session(path: '/ws/b/file.txt');
      String? resolvedRoot;
      final coord = _coord(
        session,
        cache,
        resolveGitRoot: (path) {
          if (path.startsWith('/ws/a')) {
            resolvedRoot = '/ws/a';
            return '/ws/a';
          }
          if (path.startsWith('/ws/b')) {
            resolvedRoot = '/ws/b';
            return '/ws/b';
          }
          return null;
        },
        debounce: Duration.zero,
      );
      final ctrl = CodeEditingController(
        text: 'root-b\nextra\n',
        language: 'txt',
      );
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);
      _flush(async);

      expect(resolvedRoot, '/ws/b');
      expect(session.scmDecorations.addedLines, contains(2));

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });

  test('stale baseline miss must not wipe decorations from a newer reload', () {
    // Boot race: attach lê baseline com root ainda errada (demora e volta
    // null); git.refresh dispara reload novo que publica; o miss atrasado
    // NÃO pode chamar clear por cima.
    fakeAsync((async) {
      final fake = _GatedReader(blobs: {'/repo/a.txt': 'a\n'});
      final cache = ScmBaselineCache(fake);
      final session = _session();
      final coord = _coord(session, cache, debounce: Duration.zero);
      final ctrl = CodeEditingController(text: 'a\nb\n', language: 'txt');
      session.attachScmCoordinator(coord);
      coord.attachController(ctrl);

      // 1º readTrackedText ficou parado no gate (miss atrasado).
      async.flushMicrotasks();
      expect(fake.gates, hasLength(1));

      // Refresh Git → novo reload (2º read) completa e publica.
      fake.head = 'bbb';
      coord.onGitRevisionChanged();
      async.flushMicrotasks();
      // Libera só o 2º gate (reload novo); o 1º continua pendente.
      expect(fake.gates, hasLength(2));
      fake.gates[1].complete();
      _flush(async);
      expect(session.scmDecorations.addedLines, contains(2));

      // Miss atrasado completa com null — epoch velho → não limpa.
      fake.gates[0].complete();
      _flush(async);
      expect(session.scmDecorations.addedLines, contains(2));

      coord.dispose();
      ctrl.dispose();
      session.dispose();
    });
  });
}

/// Reader que segura cada [readTrackedText] num [Completer] (teste de race).
class _GatedReader implements GitHeadBaselineReader {
  _GatedReader({required this.blobs});

  String? head = 'aaa';
  final Map<String, String> blobs;
  final List<Completer<void>> gates = <Completer<void>>[];

  @override
  Future<String?> resolveHeadIdentity(String repoPath) async => head;

  @override
  Future<GitHeadBaseline?> readTrackedText(
    String repoPath,
    String absPath,
  ) async {
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    // 1º read (atrasado): simula root/HEAD ainda inválidos no boot.
    if (identical(gate, gates.first)) return null;
    final id = head;
    final text = blobs[absPath];
    if (id == null || text == null) return null;
    return GitHeadBaseline(headIdentity: id, content: text);
  }
}
