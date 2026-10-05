import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/git_controller.dart';
import 'package:cockpit/app/core/ui/window_activity_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Never _unused() => throw UnimplementedError();

class _NoopStatusReader implements GitStatusReader {
  @override
  dynamic noSuchMethod(Invocation invocation) => _unused();
}

class _NoopCommandRunner implements GitCommandRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) => _unused();
}

FileSystemEvent _create(String path) => FileSystemCreateEvent(path, false);

void main() {
  late StreamController<FileSystemEvent> events;
  late WindowActivityController activity;
  late GitController git;
  var bumps = 0;

  setUp(() {
    bumps = 0;
    events = StreamController<FileSystemEvent>.broadcast();
    activity = WindowActivityController();
    git = GitController(
      _NoopStatusReader(),
      _NoopCommandRunner(),
      activity,
      directoryWatch: (_) => events.stream,
      fileTreeDebounce: const Duration(milliseconds: 40),
      fileTreeMaxLatency: const Duration(milliseconds: 150),
    );
    git
      ..resolvePath = ((_) => '/ws')
      ..selectedProjectId = (() => 'ws')
      ..onStructuralFsChange = (() => bumps++)
      ..watchProject('ws');
  });

  tearDown(() async {
    git.dispose();
    await events.close();
  });

  test('rajada contínua de creates ainda bumpa a árvore (teto)', () async {
    // Eventos a cada 20 ms por 400 ms: um debounce puro de 40 ms seria
    // rearmado sempre e nunca dispararia. Com o teto de 150 ms, dispara.
    for (var i = 0; i < 20; i++) {
      events.add(_create('/ws/build/f$i'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(bumps, greaterThanOrEqualTo(2));
  });

  test('evento isolado bumpa uma vez após o debounce', () async {
    events.add(_create('/ws/novo.txt'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(bumps, 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(bumps, 1);
  });

  test('voltar o foco da janela relê a árvore', () async {
    activity.blur();
    expect(bumps, 0);
    activity.focus();
    expect(bumps, 1);
  });
}
