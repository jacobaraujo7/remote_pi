// ignore_for_file: avoid_print

// Windows PTY lifecycle microbenchmark. Run from packages/cockpit_engine:
//   dart run tool/benchmark_pty_lifecycle.dart [terminal-count]
// Point COCKPIT_PTY_DYLIB at the built cockpit_pty.dll.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit_engine/cockpit_engine.dart';

Future<void> main(List<String> args) async {
  final count = args.isEmpty ? 10 : int.tryParse(args.single);
  if (!Platform.isWindows || count == null || count < 1 || count > 30) {
    stderr.writeln('Windows required; terminal count must be 1..30.');
    exitCode = 2;
    return;
  }

  final service = NativeTerminalService();
  final openUs = <int>[];
  final resizeUs = <int>[];
  final sessions = <PtySessionInfo>[];
  final clock = Stopwatch();

  try {
    for (var i = 0; i < count; i++) {
      clock
        ..reset()
        ..start();
      sessions.add(
        await service.open(
          const PtySpawnSpec(executable: 'cmd.exe', arguments: ['/Q']),
        ),
      );
      clock.stop();
      openUs.add(clock.elapsedMicroseconds);
    }

    final command = Uint8List.fromList(utf8.encode('ping -t 127.0.0.1\r\n'));
    for (final session in sessions) {
      await service.write(session.id, command);
    }

    // Compare retained output twice: this proves the shells are producing
    // output during the measurement without depending on the OS language.
    await Future<void>.delayed(const Duration(seconds: 8));
    final firstLengths = {
      for (final session in await service.sessions())
        session.id: session.scrollbackLength,
    };
    await Future<void>.delayed(const Duration(seconds: 2));
    final active = (await service.sessions())
        .where(
          (session) =>
              session.isAlive &&
              session.scrollbackLength > (firstLengths[session.id] ?? 0),
        )
        .length;

    for (final session in sessions) {
      clock
        ..reset()
        ..start();
      await service.resize(session.id, 36, 120);
      clock.stop();
      resizeUs.add(clock.elapsedMicroseconds);
    }

    clock
      ..reset()
      ..start();
    await service.dispose();
    clock.stop();

    print('terminals=$count activeOutput=$active');
    print('openUs=$openUs');
    print('resizeUs=$resizeUs');
    print('disposeUs=' + clock.elapsedMicroseconds.toString());
  } finally {
    // Also cleans up partial runs after a spawn or write error.
    await service.dispose();
  }
}
