import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// De onde a máquina está puxando energia agora. Usado pela UI pra avisar
/// que o modo acordado está queimando bateria.
enum PowerSource { ac, battery, unknown }

/// Lê a fonte de energia atual. Cada plataforma tem seu jeito; qualquer falha
/// devolve [PowerSource.unknown] em vez de lançar (é informação de conforto,
/// nunca pode derrubar o toggle).
abstract class PowerSourceProbe {
  const PowerSourceProbe();

  factory PowerSourceProbe.platform() {
    if (Platform.isMacOS) return const MacPowerSourceProbe();
    if (Platform.isWindows) return const WindowsPowerSourceProbe();
    if (Platform.isLinux) return const LinuxPowerSourceProbe();
    return const UnknownPowerSourceProbe();
  }

  Future<PowerSource> read();
}

class UnknownPowerSourceProbe extends PowerSourceProbe {
  const UnknownPowerSourceProbe();
  @override
  Future<PowerSource> read() async => PowerSource.unknown;
}

/// macOS: `pmset -g batt` imprime `Now drawing from 'AC Power'` ou
/// `'Battery Power'` na primeira linha.
class MacPowerSourceProbe extends PowerSourceProbe {
  const MacPowerSourceProbe();

  @override
  Future<PowerSource> read() async {
    try {
      final r = await Process.run('pmset', const ['-g', 'batt']);
      if (r.exitCode != 0) return PowerSource.unknown;
      return parsePmsetBatt(r.stdout as String);
    } on ProcessException {
      return PowerSource.unknown;
    }
  }

  static PowerSource parsePmsetBatt(String out) {
    final head = out.split('\n').first;
    if (head.contains("'AC Power'")) return PowerSource.ac;
    if (head.contains("'Battery Power'")) return PowerSource.battery;
    return PowerSource.unknown;
  }
}

/// Linux: sysfs. Qualquer supply do tipo `Mains` com `online=1` = tomada;
/// existindo só baterias = bateria; sem supply nenhum (desktop sem ACPI de
/// bateria) = tomada.
class LinuxPowerSourceProbe extends PowerSourceProbe {
  const LinuxPowerSourceProbe({this.root = '/sys/class/power_supply'});
  final String root;

  @override
  Future<PowerSource> read() async {
    try {
      final dir = Directory(root);
      if (!dir.existsSync()) return PowerSource.unknown;
      var sawBattery = false;
      for (final e in dir.listSync()) {
        final type = _readTrim('${e.path}/type');
        if (type == 'Mains') {
          if (_readTrim('${e.path}/online') == '1') return PowerSource.ac;
        } else if (type == 'Battery') {
          sawBattery = true;
        }
      }
      return sawBattery ? PowerSource.battery : PowerSource.ac;
    } on FileSystemException {
      return PowerSource.unknown;
    }
  }

  static String? _readTrim(String path) {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync().trim() : null;
  }
}

/// Windows: `GetSystemPowerStatus().ACLineStatus` (0 = bateria, 1 = tomada,
/// 255 = desconhecido). O `win32` abre `kernel32.dll` de forma tardia, então
/// importar aqui não custa nada fora do Windows; o guard evita a chamada.
class WindowsPowerSourceProbe extends PowerSourceProbe {
  const WindowsPowerSourceProbe();

  @override
  Future<PowerSource> read() async {
    if (!Platform.isWindows) return PowerSource.unknown;
    final status = calloc<win32.SYSTEM_POWER_STATUS>();
    try {
      if (win32.GetSystemPowerStatus(status) == 0) return PowerSource.unknown;
      return switch (status.ref.ACLineStatus) {
        0 => PowerSource.battery,
        1 => PowerSource.ac,
        _ => PowerSource.unknown,
      };
    } finally {
      calloc.free(status);
    }
  }
}
