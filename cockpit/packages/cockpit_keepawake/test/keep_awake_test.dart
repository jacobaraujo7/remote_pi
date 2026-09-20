import 'dart:io';

import 'package:cockpit_keepawake/cockpit_keepawake.dart';
import 'package:test/test.dart';

void main() {
  group('PowerSource parsing', () {
    test('pmset AC', () {
      expect(
        MacPowerSourceProbe.parsePmsetBatt(
          "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1) 100%",
        ),
        PowerSource.ac,
      );
    });
    test('pmset battery', () {
      expect(
        MacPowerSourceProbe.parsePmsetBatt(
          "Now drawing from 'Battery Power'\n",
        ),
        PowerSource.battery,
      );
    });
    test('pmset garbage', () {
      expect(MacPowerSourceProbe.parsePmsetBatt(''), PowerSource.unknown);
    });

    test('linux sysfs: mains online', () async {
      final root = Directory.systemTemp.createTempSync('ps');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/AC').createSync();
      File('${root.path}/AC/type').writeAsStringSync('Mains\n');
      File('${root.path}/AC/online').writeAsStringSync('1\n');
      Directory('${root.path}/BAT0').createSync();
      File('${root.path}/BAT0/type').writeAsStringSync('Battery\n');
      expect(
        await LinuxPowerSourceProbe(root: root.path).read(),
        PowerSource.ac,
      );
      File('${root.path}/AC/online').writeAsStringSync('0\n');
      expect(
        await LinuxPowerSourceProbe(root: root.path).read(),
        PowerSource.battery,
      );
    });

    test('linux sysfs: no supplies = desktop on AC', () async {
      final root = Directory.systemTemp.createTempSync('ps');
      addTearDown(() => root.deleteSync(recursive: true));
      expect(
        await LinuxPowerSourceProbe(root: root.path).read(),
        PowerSource.ac,
      );
    });
  });

  group('KeepAwake commands', () {
    test('mac caffeinate ties to pid', () {
      expect(MacKeepAwake().command(4242), ['caffeinate', '-i', '-w', '4242']);
    });
    test('linux inhibit watches pid', () {
      final cmd = LinuxKeepAwake().command(4242);
      expect(cmd.first, 'systemd-inhibit');
      expect(cmd, contains('--what=sleep:idle'));
      expect(cmd.last, contains('kill -0 4242'));
    });
    test('unsupported never activates', () async {
      const k = UnsupportedKeepAwake();
      expect(k.isSupported, isFalse);
      expect(await k.acquire(), isFalse);
      expect(k.isActive, isFalse);
    });
  });

  group('KeepAwake on this platform', () {
    test('acquire/release round-trip', () async {
      final k = KeepAwake.platform();
      if (!k.isSupported) return;
      final ok = await k.acquire();
      expect(ok, isTrue);
      expect(k.isActive, isTrue);
      expect(await k.acquire(), isTrue); // idempotente
      await k.release();
      expect(k.isActive, isFalse);
      await k.release(); // no-op
    });
  }, testOn: 'mac-os || windows');
}
