import 'package:cockpit/app/cockpit/data/remote/remote_task_gateway.dart';
import 'package:cockpit/app/cockpit/data/tasks/tasks_json_loader.dart';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final profile in <String?>[
    null,
    'development',
    'production',
    'inherited',
  ]) {
    test('remote spawn resolves task and profile env for $profile', () async {
      final terminal = _Terminal();
      final runner = RemoteTaskRunner(() async => terminal);
      addTearDown(runner.disposeAll);
      final task = const TasksJsonLoader().parseContent('''{
        "tasks": [{
          "label": "api", "command": "npm", "args": ["run", "dev"],
          "env": {"API_URL": "https://api.example.com", "LOG_LEVEL": "info"},
          "profiles": [
            {"name": "development", "env": {"API_URL": "http://localhost:3000"}},
            {"name": "production", "env": {"LOG_LEVEL": "error"}},
            {"name": "inherited"}
          ]
        }]
      }''', '/repo').single;
      await runner.start(task, profileName: profile, argsOverride: ['custom']);
      expect(terminal.spec!.environment, {
        'API_URL': profile == 'development'
            ? 'http://localhost:3000'
            : 'https://api.example.com',
        'LOG_LEVEL': profile == 'production' ? 'error' : 'info',
        'TERM': 'xterm-256color',
      });
      expect(terminal.spec!.arguments.last, 'exec npm custom');
    });
  }
}

class _Terminal implements TerminalService {
  PtySpawnSpec? spec;

  @override
  Future<PtySessionInfo> open(PtySpawnSpec spec) async {
    this.spec = spec;
    return const PtySessionInfo(
      id: 'session',
      pid: 1,
      executable: '/bin/sh',
      rows: 24,
      columns: 80,
      scrollbackLength: 0,
    );
  }

  @override
  Stream<PtyEvent> attach(String sessionId, {int fromOffset = 0}) =>
      const Stream.empty();

  @override
  Future<void> kill(String sessionId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
