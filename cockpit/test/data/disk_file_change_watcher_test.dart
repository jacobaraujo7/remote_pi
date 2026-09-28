import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/disk_file_change_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

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
