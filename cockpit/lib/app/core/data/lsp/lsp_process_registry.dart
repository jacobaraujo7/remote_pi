import 'package:cockpit/app/core/data/process/owned_process_registry.dart';
import 'package:cockpit/app/core/utils/user_home.dart';

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

  static String get _legacyPath {
    final home = userHome() ?? '';
    return '$home/.pi/cockpit/lsp-pids';
  }

  static final OwnedProcessRegistry _registry = OwnedProcessRegistry(
    category: 'lsp',
    legacyFiles: [_legacyPath],
  );

  /// Mata os PIDs remanescentes do ciclo anterior e limpa o registro. Deve ser
  /// chamado UMA VEZ por boot, antes de qualquer spawn.
  static Future<void> cleanOrphans() async {
    await _registry.cleanOrphans();
  }

  /// Registra [pid] no arquivo. Chamado logo após o spawn bem-sucedido.
  static Future<void> register(int pid) async {
    await _registry.register(pid);
  }

  /// Remove [pid] do arquivo. Chamado na saída limpa do servidor.
  static Future<void> unregister(int pid) async {
    await _registry.unregister(pid);
  }
}
