import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_server/cockpit_server.dart';
import 'package:test/test.dart';

void main() {
  test('preserves flow control when mapping a PTY open request', () {
    final spec = ptySpawnSpecFromOpen(
      const PtyOpen(
        executable: 'powershell.exe',
        arguments: ['-NoProfile'],
        environment: {'COCKPIT_PANE_ID': 't1'},
        rows: 40,
        columns: 120,
        flowControlled: true,
      ),
      statusSocketPath: r'C:\tmp\status.sock',
    );

    expect(spec.executable, 'powershell.exe');
    expect(spec.arguments, ['-NoProfile']);
    expect(spec.rows, 40);
    expect(spec.columns, 120);
    expect(spec.flowControlled, isTrue);
    expect(spec.environment, {
      'COCKPIT_PANE_ID': 't1',
      'COCKPIT_STATUS_SOCK': r'C:\tmp\status.sock',
    });
  });

  test('keeps an unthrottled request unthrottled', () {
    final spec = ptySpawnSpecFromOpen(
      const PtyOpen(executable: 'cmd.exe', flowControlled: false),
    );

    expect(spec.flowControlled, isFalse);
    expect(spec.environment, isEmpty);
  });
}
