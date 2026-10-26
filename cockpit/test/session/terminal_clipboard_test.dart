import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements TerminalGateway {
  final writes = <int>[];
  final _output = StreamController<List<int>>();
  @override
  SpawnDirectory? get spawnDirectory => null;
  @override
  int? get rootProcessId => null;
  @override
  int? get wslProcessId => null;
  @override
  Stream<List<int>> get output => _output.stream;
  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const {},
  }) {}
  @override
  void write(List<int> data) => writes.addAll(data);
  @override
  void resize(int rows, int columns) {}
  @override
  void acknowledgeOutput() {}
  @override
  Future<void> kill() => _output.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pasteboard = MethodChannel('pasteboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Gateway gateway;
  late TerminalSession session;
  late List<String> files;
  late List<String> reads;
  String? text;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    gateway = _Gateway();
    files = [];
    reads = [];
    text = null;
    messenger.setMockMethodCallHandler(pasteboard, (call) async {
      reads.add(call.method);
      return switch (call.method) {
        'files' => files,
        'image' => null,
        _ => throw StateError('Unexpected clipboard read: ${call.method}'),
      };
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return text == null ? null : {'text': text};
      }
      return null;
    });
    session = TerminalSession(
      id: 'clipboard-test',
      projectId: 'test',
      workingDirectory: r'C:\work',
      gateway: gateway,
      profile: const TerminalProfile(
        id: 'powershell',
        label: 'PowerShell',
        executable: 'powershell.exe',
      ),
    );
  });

  tearDown(() async {
    await session.dispose();
    messenger.setMockMethodCallHandler(pasteboard, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'Explorer file list is pasted before image or text alternatives',
    () async {
      files = [r'C:\work\first file.txt', r'C:\work\ação.png'];
      text = 'alternative clipboard text';
      await session.pasteFromClipboard();
      expect(
        utf8.decode(gateway.writes),
        "'C:\\work\\first file.txt' 'C:\\work\\ação.png' ",
      );
      expect(reads, ['files']);
    },
  );

  test('file paste and drop use the same path payload', () async {
    files = [r'C:\work\file.txt'];
    await session.pasteFromClipboard();
    final pasted = List<int>.of(gateway.writes);
    gateway.writes.clear();
    session.pasteFilePaths(files);
    expect(gateway.writes, pasted);
  });

  test('file paths respect bracketed paste mode', () async {
    files = [r'C:\work\file.txt'];
    session.terminal.write('\x1b[?2004h');
    await session.pasteFromClipboard();
    expect(
      utf8.decode(gateway.writes),
      "\x1b[200~'C:\\work\\file.txt' \x1b[201~",
    );
  });

  test('text paste still works when the file list is empty', () async {
    files = [''];
    text = 'regular text';
    await session.pasteFromClipboard();
    expect(utf8.decode(gateway.writes), text);
  });

  test('Windows image fallback is preserved without files or text', () async {
    await session.pasteFromClipboard();
    expect(gateway.writes, [0x16]);
  });
}
