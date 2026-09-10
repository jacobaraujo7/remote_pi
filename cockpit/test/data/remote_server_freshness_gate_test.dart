import 'package:cockpit/app/cockpit/data/remote/remote_host_connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe que lança não fecha o gate e o retry pode concluir', () async {
    final gate = ServerFreshnessProbeGate();
    var attempts = 0;

    await expectLater(
      gate.run(() async {
        attempts++;
        throw StateError('transport dropped');
      }),
      throwsStateError,
    );
    expect(gate.completed, isFalse);

    expect(
      await gate.run(() async {
        attempts++;
        return true;
      }),
      isTrue,
    );
    expect(gate.completed, isTrue);
    expect(attempts, 2);
  });

  test('probe concluído roda uma vez só', () async {
    final gate = ServerFreshnessProbeGate();
    var attempts = 0;

    expect(
      await gate.run(() async {
        attempts++;
        return false;
      }),
      isFalse,
    );
    expect(
      await gate.run(() async {
        attempts++;
        return true;
      }),
      isFalse,
    );
    expect(attempts, 1);
  });
}
