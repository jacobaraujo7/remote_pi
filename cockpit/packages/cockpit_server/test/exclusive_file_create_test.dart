import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_engine/cockpit_engine.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_remote/cockpit_remote.dart';
import 'package:cockpit_server/cockpit_server.dart';
import 'package:test/test.dart';

class _Unused implements TerminalService, FileService, GitService, DbService {
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _LegacyFiles extends _Unused {
  int writes = 0;
  @override
  Future<void> write(String path, List<int> bytes) async {
    writes++;
    await File(path).writeAsBytes(bytes);
  }
}

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cockpit-remote-create-');
    LocalEndpoint.debugForceTcp = true;
  });
  tearDown(() async {
    LocalEndpoint.debugForceTcp = null;
    await temporary.delete(recursive: true);
  });
  Future<RemoteFileService> connect(FileService files) async {
    final unused = _Unused();
    final server = RemoteServer(unused, files, unused, unused);
    final path = '${temporary.path}/server.sock';
    await server.bind(path);
    addTearDown(server.close);
    final connection = await RemoteConnection.connect(path);
    addTearDown(connection.close);
    return RemoteFileService(connection);
  }

  test(
    'hook metrics and own identity survive the actual server/client transport',
    () async {
      final unused = _Unused();
      final server = RemoteServer(
        unused,
        const NativeFileService(),
        unused,
        unused,
      );
      final path = '${temporary.path}/hooks.sock';
      await server.bind(path);
      addTearDown(server.close);
      final connection = await RemoteConnection.connect(path);
      addTearDown(connection.close);
      final received = RemoteTerminalService(
        connection,
      ).turnStatus.take(2).toList();
      Future<void> send(Map<String, Object?> payload) async {
        final endpoint = await LocalEndpoint.connect(server.statusSocketPath!);
        endpoint.socket.write(
          '${jsonEncode({...payload, 'tok': server.statusToken})}\n',
        );
        await endpoint.socket.flush();
        endpoint.socket.destroy();
      }

      await send({'paneId': 'own', 'type': 'metric', 'ct': -1, 'cw': 100});
      await send({
        'paneId': 'own',
        'type': 'metric',
        'ct': 42,
        'cw': 100,
        'sid': 'session',
      });
      await send({
        'paneId': 'own',
        'st': 'working',
        'hn': 'claude',
        'gi': 'self',
        'gm': 'peer',
      });
      final updates = await received.timeout(const Duration(seconds: 5));
      expect(updates.first.status, 'metric');
      expect(updates.first.contextTokens, 42);
      expect(updates.first.contextWindow, 100);
      expect(updates.last.graphSelfName, 'self');
      expect(updates.last.graphRecipient, 'peer');
    },
  );

  test(
    'exclusive creation crosses the real TCP/protocol/client path without overwrite',
    () async {
      final files = await connect(const NativeFileService());
      final path = '${temporary.path}/agents.orchestration';
      expect(await files.createNew(path, utf8.encode('original')), isTrue);
      expect(await files.createNew(path, utf8.encode('replacement')), isFalse);
      expect(utf8.decode(await files.read(path)), 'original');
      // Existing ordinary write semantics remain available and unchanged.
      await files.write(path, utf8.encode('explicit edit'));
      expect(await File(path).readAsString(), 'explicit edit');
    },
  );
  test(
    'older backend rejects creation without falling back to ordinary write',
    () async {
      final legacy = _LegacyFiles();
      final files = await connect(legacy);
      await expectLater(
        files.createNew('${temporary.path}/new', utf8.encode('text')),
        throwsA(isA<FileException>()),
      );
      expect(legacy.writes, 0);
      expect(await File('${temporary.path}/new').exists(), isFalse);
    },
  );
}
