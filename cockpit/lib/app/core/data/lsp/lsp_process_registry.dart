import 'dart:io';

/// Registro persistente de PIDs dos language servers (LSP) ativos.
///
/// Mesmo problema do [PiProcessRegistry]: hot restart / crash do app não mata os
/// child processes do `Process.start`, deixando `dart language-server`,
/// `jdtls`, `node`… órfãos. A diferença é que aqui os servers são **vários
/// binários distintos**, então o `pgrep -x <nome>` do pi (que assume um único
/// nome) não serve — usamos **só o registry-file**: cada PID spawnado é gravado
/// e, no boot, os remanescentes são mortos e o arquivo zerado.
class LspProcessRegistry {
  LspProcessRegistry._();

  static String get _path {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.pi/cockpit/lsp-pids';
  }

  /// Mata os PIDs remanescentes do ciclo anterior e limpa o registro. Deve ser
  /// chamado UMA VEZ por boot, antes de qualquer spawn.
  static Future<void> cleanOrphans() async {
    try {
      final file = File(_path);
      if (!await file.exists()) return;
      final pids = (await file.readAsLines())
          .map((l) => int.tryParse(l.trim()))
          .whereType<int>();
      await file.delete();
      for (final p in pids) {
        try {
          Process.killPid(p, ProcessSignal.sigkill);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Registra [pid] no arquivo. Chamado logo após o spawn bem-sucedido.
  static Future<void> register(int pid) async {
    try {
      final file = File(_path);
      await file.parent.create(recursive: true);
      await file.writeAsString('$pid\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Remove [pid] do arquivo. Chamado na saída limpa do servidor.
  static Future<void> unregister(int pid) async {
    try {
      final file = File(_path);
      if (!await file.exists()) return;
      final kept = (await file.readAsLines())
          .where((l) => l.trim() != '$pid')
          .toList();
      if (kept.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString('${kept.join('\n')}\n');
      }
    } catch (_) {}
  }
}
