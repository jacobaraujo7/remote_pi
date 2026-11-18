import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/disk_file_change_watcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

/// Contra o disco real: o que se testa é justamente o comportamento do
/// watcher do SO (rename atômico, stream que morre), que um fake esconderia.
void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('fcw-'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// Só eventos: o poll fica longe, pra provar que o watch da pasta basta.
  const eventsOnly = DiskFileChangeWatcher(
    debounce: Duration(milliseconds: 50),
    pollInterval: Duration(hours: 1),
  );

  /// Deixa o FSEvents armar antes da primeira escrita (é assíncrono).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  /// Grava como o Claude Code: arquivo temporário + rename por cima.
  void atomicWrite(String path, String content) {
    final tmpFile = File('$path.tmp.${DateTime.now().microsecondsSinceEpoch}')
      ..writeAsStringSync(content);
    tmpFile.renameSync(path);
  }

  test(
    'real tree signatures survive cancellation and detect hidden edits',
    () async {
      final file = File('${tmp.path}/source.dart')..writeAsStringSync('before');
      var ready = Completer<void>();
      final native = StreamController<FileSystemEvent>.broadcast();
      final stream = DiskFileChangeWatcher(
        recursiveWatchSupported: true,
        treeSafetyPollInterval: const Duration(hours: 1),
        directoryWatch: (_, _) {
          ready.complete(); // the initial metadata snapshot has completed
          return native.stream;
        },
      ).watchTree(tmp.path);
      var hits = 0;
      var subscription = stream.listen((_) => hits++);
      await ready.future;
      await subscription.cancel();
      ready = Completer<void>();
      subscription = stream.listen((_) => hits++);
      await ready.future;
      await Future<void>.delayed(Duration.zero);
      expect(
        hits,
        0,
        reason: 'same metadata must produce the same hash across isolates',
      );
      await subscription.cancel();
      file.writeAsStringSync('changed while hidden');
      ready = Completer<void>();
      subscription = stream.listen((_) => hits++);
      await ready.future;
      await Future<void>.delayed(Duration.zero);
      expect(hits, 1);
      await subscription.cancel();
      await native.close();
    },
  );

  test(
    'tree has no work while detached and validates only once on reattach',
    () {
      fakeAsync((clock) {
        var snapshots = 0;
        var signature = 'initial';
        var hits = 0;
        final native = StreamController<FileSystemEvent>.broadcast();
        final watcher = DiskFileChangeWatcher(
          recursiveWatchSupported: true,
          directoryWatch: (_, _) => native.stream,
          treeSnapshot: (_) {
            snapshots++;
            return signature;
          },
        );
        final stream = watcher.watchTree(tmp.path);
        var subscription = stream.listen((_) => hits++);
        clock.flushMicrotasks();
        expect(snapshots, 1);
        expect(hits, 0);
        unawaited(subscription.cancel());
        clock.flushMicrotasks();
        expect(native.hasListener, isFalse);
        clock.elapse(const Duration(minutes: 5));
        expect(snapshots, 1, reason: 'no poll/isolate while hidden');
        subscription = stream.listen((_) => hits++);
        clock.flushMicrotasks();
        expect(snapshots, 2);
        expect(hits, 0, reason: 'unchanged content reuses cached search');
        unawaited(subscription.cancel());
        clock.flushMicrotasks();
        signature = 'changed while hidden';
        clock.elapse(const Duration(minutes: 5));
        expect(snapshots, 2);
        subscription = stream.listen((_) => hits++);
        clock.flushMicrotasks();
        expect(snapshots, 3);
        expect(hits, 1);
        unawaited(subscription.cancel());
        unawaited(native.close());
        clock.flushMicrotasks();
        expect(clock.periodicTimerCount, 0);
        expect(clock.nonPeriodicTimerCount, 0);
      });
    },
  );

  test('healthy recursive native watch uses only the 60s safety poll', () {
    fakeAsync((clock) {
      var snapshots = 0;
      var signature = 'initial';
      var hits = 0;
      final native = StreamController<FileSystemEvent>.broadcast();
      final watcher = DiskFileChangeWatcher(
        recursiveWatchSupported: true,
        directoryWatch: (_, _) => native.stream,
        treeSnapshot: (_) {
          snapshots++;
          return signature;
        },
      );
      final subscription = watcher.watchTree(tmp.path).listen((_) => hits++);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 59));
      expect(
        snapshots,
        1,
        reason: 'healthy native watch must not poll every 10s',
      );
      signature = 'missed native event';
      clock.elapse(const Duration(seconds: 1));
      expect(snapshots, 2);
      expect(hits, 1);
      signature = 'native event';
      native.add(FileSystemModifyEvent('${tmp.path}/file.dart', false, true));
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 121));
      expect(snapshots, 3);
      expect(hits, 2);
      unawaited(subscription.cancel());
      unawaited(native.close());
      clock.flushMicrotasks();
      expect(clock.periodicTimerCount, 0);
    });
  });

  test('unsupported recursive watching keeps the 10s fallback', () {
    fakeAsync((clock) {
      var snapshots = 0;
      final native = StreamController<FileSystemEvent>.broadcast();
      final watcher = DiskFileChangeWatcher(
        recursiveWatchSupported: false,
        directoryWatch: (_, _) => native.stream,
        treeSnapshot: (_) => '${++snapshots}',
      );
      final subscription = watcher.watchTree(tmp.path).listen((_) {});
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));
      expect(snapshots, 1);
      clock.elapse(const Duration(seconds: 1));
      expect(snapshots, 2);
      unawaited(subscription.cancel());
      unawaited(native.close());
      clock.flushMicrotasks();
    });
  });

  test(
    'native failure enables fallback and rearm restores the slow safety poll',
    () {
      fakeAsync((clock) {
        var snapshots = 0;
        var available = false;
        final native = StreamController<FileSystemEvent>.broadcast();
        final watcher = DiskFileChangeWatcher(
          recursiveWatchSupported: true,
          retryMin: const Duration(seconds: 30),
          retryMax: const Duration(seconds: 30),
          directoryWatch: (_, _) {
            if (!available) throw const FileSystemException('unavailable');
            return native.stream;
          },
          treeSnapshot: (_) => '${++snapshots}',
        );
        final subscription = watcher.watchTree(tmp.path).listen((_) {});
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 20));
        expect(
          snapshots,
          3,
          reason: 'fallback polls at 10s while native watch fails',
        );
        available = true;
        clock.elapse(const Duration(seconds: 10));
        expect(native.hasListener, isTrue);
        final recovered = snapshots;
        clock.elapse(const Duration(seconds: 59));
        expect(snapshots, recovered);
        clock.elapse(const Duration(seconds: 1));
        expect(snapshots, recovered + 1);
        available = false;
        native.addError(const FileSystemException('lost watch'));
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 10));
        expect(snapshots, recovered + 2);
        unawaited(subscription.cancel());
        unawaited(native.close());
        clock.flushMicrotasks();
        expect(clock.periodicTimerCount, 0);
        expect(clock.nonPeriodicTimerCount, 0);
      });
    },
  );

  test(
    'a cancelled initial snapshot cannot overwrite the resumed baseline',
    () {
      fakeAsync((clock) {
        final pending = Completer<String>();
        var snapshots = 0;
        var hits = 0;
        final native = StreamController<FileSystemEvent>.broadcast();
        final stream = DiskFileChangeWatcher(
          recursiveWatchSupported: true,
          directoryWatch: (_, _) => native.stream,
          treeSnapshot: (_) => ++snapshots == 1 ? pending.future : 'new',
        ).watchTree(tmp.path);
        var subscription = stream.listen((_) => hits++);
        unawaited(subscription.cancel());
        clock.flushMicrotasks();
        subscription = stream.listen((_) => hits++);
        clock.flushMicrotasks();
        expect(
          hits,
          1,
          reason: 'an unestablished baseline cannot validate old results',
        );
        pending.complete('old');
        clock.flushMicrotasks();
        unawaited(subscription.cancel());
        clock.flushMicrotasks();
        subscription = stream.listen((_) => hits++);
        clock.flushMicrotasks();
        expect(
          hits,
          1,
          reason: 'late initial snapshot must not replace the new signature',
        );
        unawaited(subscription.cancel());
        unawaited(native.close());
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'tree observes nested content, atomic replacement, addition and deletion',
    () async {
      final nested = Directory('${tmp.path}/lib/nested')
        ..createSync(recursive: true);
      final file = File('${nested.path}/source.dart')
        ..writeAsStringSync('before');
      const watcher = DiskFileChangeWatcher(
        debounce: Duration(milliseconds: 30),
        treePollInterval: Duration(milliseconds: 150),
      );
      final events = _Events(watcher.watchTree(tmp.path));
      await settle();
      file.writeAsStringSync('after with new content');
      await events.next();
      atomicWrite(file.path, 'atomic update');
      await events.next();
      final added = File('${nested.path}/added.dart')..writeAsStringSync('new');
      await events.next();
      await added.delete();
      await events.next();
      await events.cancel();
    },
  );

  test(
    'tree ignores build and hidden directories and stops on cancellation',
    () async {
      final nested = Directory('${tmp.path}/lib')..createSync();
      final ignored = Directory('${tmp.path}/build')..createSync();
      final git = Directory('${tmp.path}/.git')..createSync();
      const watcher = DiskFileChangeWatcher(
        debounce: Duration(milliseconds: 30),
        treePollInterval: Duration(milliseconds: 100),
      );
      var hits = 0;
      final subscription = watcher.watchTree(tmp.path).listen((_) => hits++);
      await settle();
      File('${ignored.path}/output').writeAsStringSync('ignored');
      File('${git.path}/index').writeAsStringSync('ignored');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(hits, 0);
      await subscription.cancel();
      File('${nested.path}/source').writeAsStringSync('after cancellation');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(hits, 0);
    },
  );

  test('escrita no lugar avisa', () async {
    final f = File('${tmp.path}/board.kanban')..writeAsStringSync('v0');
    final it = _Events(eventsOnly.watchFile(f.path));
    await settle();
    f.writeAsStringSync('v1');
    await it.next();
    await it.cancel();
  });

  test('rename atômico seguido de outros: todos avisam (o File.watch morria '
      'no primeiro)', () async {
    final f = File('${tmp.path}/board.kanban')..writeAsStringSync('v0');
    final it = _Events(eventsOnly.watchFile(f.path));
    await settle();
    for (var i = 1; i <= 3; i++) {
      atomicWrite(f.path, 'v$i');
      await it.next();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    f.writeAsStringSync('in-place depois do rename');
    await it.next();
    await it.cancel();
  });

  test('ignora arquivos vizinhos na mesma pasta', () async {
    final f = File('${tmp.path}/a.md')..writeAsStringSync('a');
    var hits = 0;
    final sub = eventsOnly.watchFile(f.path).listen((_) => hits++);
    await settle();
    File('${tmp.path}/b.md').writeAsStringSync('b');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(hits, 0);
    await sub.cancel();
  });

  test('poll pega a mudança e não avisa à toa', () async {
    final f = File('${tmp.path}/x.html')..writeAsStringSync('<p>0</p>');
    // Pasta que ainda não existe: o watch do SO falha, sobra o poll.
    final missing = '${tmp.path}/later/x.html';
    const pollOnly = DiskFileChangeWatcher(
      debounce: Duration(milliseconds: 50),
      pollInterval: Duration(milliseconds: 100),
      retryMin: Duration(hours: 1),
    );
    var hits = 0;
    final sub = pollOnly.watchFile(missing).listen((_) => hits++);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(hits, 0, reason: 'nada mudou, nada a avisar');
    await Directory('${tmp.path}/later').create();
    f.copySync(missing);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // A cópia pode ser vista pela metade num poll e inteira no seguinte.
    expect(hits, greaterThanOrEqualTo(1));
    final settled = hits;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(hits, settled, reason: 'parado, o poll não repete aviso');
    await sub.cancel();
  });

  test('re-arma quando a pasta some e volta', () async {
    final dir = await Directory('${tmp.path}/nb.notebook').create();
    const w = DiskFileChangeWatcher(
      debounce: Duration(milliseconds: 50),
      pollInterval: Duration(hours: 1),
      retryMin: Duration(milliseconds: 100),
      retryMax: Duration(milliseconds: 200),
    );
    final it = _Events(w.watchFolder(dir.path));
    await settle();
    await dir.delete(recursive: true);
    await it.next(); // a própria remoção é mudança
    await dir.create();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    File('${dir.path}/nota.md').writeAsStringSync('# oi');
    await it.next();
    await it.cancel();
  });

  test('pasta: nota nova e nota reescrita avisam', () async {
    final dir = await Directory('${tmp.path}/notes.notebook').create();
    final it = _Events(eventsOnly.watchFolder(dir.path));
    await settle();
    File('${dir.path}/a.md').writeAsStringSync('# a');
    await it.next();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    atomicWrite('${dir.path}/a.md', '# a editada');
    await it.next();
    await it.cancel();
  });
}

/// Assina NA HORA (o `StreamIterator` só assinaria no primeiro `moveNext`,
/// depois da escrita, e o watcher tiraria a foto inicial já com o conteúdo
/// novo) e entrega um aviso por vez, com prazo.
class _Events {
  _Events(Stream<void> stream) {
    _sub = stream.listen((_) {
      if (_waiting case final c?) {
        _waiting = null;
        c.complete();
      } else {
        _pending++;
      }
    });
  }

  late final StreamSubscription<void> _sub;
  int _pending = 0;
  Completer<void>? _waiting;

  Future<void> next() {
    if (_pending > 0) {
      _pending--;
      return Future<void>.value();
    }
    final c = _waiting = Completer<void>();
    return c.future.timeout(const Duration(seconds: 5));
  }

  Future<void> cancel() => _sub.cancel();
}
