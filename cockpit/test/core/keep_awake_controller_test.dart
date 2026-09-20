import 'package:cockpit/app/core/ui/keep_awake_controller.dart';
import 'package:cockpit_keepawake/cockpit_keepawake.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeKeepAwake implements KeepAwake {
  bool active = false;
  bool fail = false;
  int releases = 0;
  @override
  bool get isSupported => true;
  @override
  bool get isActive => active;
  @override
  Future<bool> acquire() async => fail ? false : active = true;
  @override
  Future<void> release() async {
    active = false;
    releases++;
  }
}

class _FakeProbe extends PowerSourceProbe {
  _FakeProbe(this.source);
  PowerSource source;
  @override
  Future<PowerSource> read() async => source;
}

void main() {
  test('toggle liga, lê energia e desliga', () async {
    final k = _FakeKeepAwake();
    final probe = _FakeProbe(PowerSource.battery);
    final ctl = KeepAwakeController(keepAwake: k, powerProbe: probe);
    var notified = 0;
    ctl.addListener(() => notified++);

    await ctl.toggle();
    expect(ctl.isActive, isTrue);
    expect(ctl.onBattery, isTrue);
    expect(notified, greaterThanOrEqualTo(1));

    await ctl.toggle();
    expect(ctl.isActive, isFalse);
    expect(ctl.onBattery, isFalse);
    expect(k.releases, 1);
    ctl.dispose();
  });

  test('acquire que falha deixa desligado', () async {
    final k = _FakeKeepAwake()..fail = true;
    final ctl = KeepAwakeController(
      keepAwake: k,
      powerProbe: _FakeProbe(PowerSource.ac),
    );
    await ctl.enable();
    expect(ctl.isActive, isFalse);
    ctl.dispose();
  });

  test('dispose solta a assertion', () async {
    final k = _FakeKeepAwake();
    final ctl = KeepAwakeController(
      keepAwake: k,
      powerProbe: _FakeProbe(PowerSource.ac),
    );
    await ctl.enable();
    ctl.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(k.active, isFalse);
  });

  test('sem suporte: nunca ativa', () async {
    final ctl = KeepAwakeController(keepAwake: const UnsupportedKeepAwake());
    expect(ctl.isSupported, isFalse);
    await ctl.enable();
    expect(ctl.isActive, isFalse);
    ctl.dispose();
  });
}
