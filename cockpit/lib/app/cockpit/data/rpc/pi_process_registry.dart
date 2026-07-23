import 'dart:io';

import 'package:cockpit/app/core/data/process/owned_process_registry.dart';
import 'package:cockpit/app/core/utils/user_home.dart';

/// Registro persistente de PIDs de processos `pi --mode rpc` ativos.
///
/// Problema: hot restart do `flutter run` reinicia a isolate Dart mas NÃO mata
/// os child processes criados com `Process.start`. Sem `dispose`, os `pi`
/// continuam rodando como órfãos — ao re-spawnar, há dois peers no mesh com o
/// mesmo nome.
///
/// Solução em dois níveis, chamada por [cleanOrphans] no boot:
///
/// 1. **Registry (arquivo)** — [register] escreve o PID no boot; [unregister]
///    remove na saída limpa. Cobre cold restarts e crashes onde o processo pai
///    (Cockpit) morreu e as PIDs não são mais filhos dele.
///
/// 2. **PPID scan** — antes de qualquer spawn, busca todos os processos `pi`
///    cujo PPID == PID do Cockpit. Esses são exatamente os órfãos do hot
///    restart: o processo macOS do Cockpit continua vivo mas a isolate anterior
///    não liberou os filhos.
///
/// Ambos matam com SIGKILL (sem espera) — adequado para órfãos de
/// desenvolvimento; a saída limpa de produção usa [dispose] → [kill].
class PiProcessRegistry {
  PiProcessRegistry._();

  static String get _legacyPath {
    final home = userHome() ?? '';
    return '$home/.pi/cockpit/agent-pids';
  }

  static final OwnedProcessRegistry _registry = OwnedProcessRegistry(
    category: 'agents',
    legacyFiles: [_legacyPath],
  );

  /// Mata todos os pi órfãos do ciclo anterior e limpa o registro.
  /// Deve ser chamado UMA VEZ por boot (em [setupDependencies]), antes de
  /// qualquer spawn.
  static Future<void> cleanOrphans() async {
    // Roda as duas buscas em paralelo para minimizar latência no boot.
    final results = await Future.wait([
      _registry.cleanOrphans().then((_) => const <int>[]),
      _orphanedPiChildren(),
    ]);
    final toKill = <int>{...results[1]};
    for (final p in toKill) {
      try {
        Process.killPid(p, ProcessSignal.sigkill); // imediato, sem corrida
      } catch (_) {}
    }
  }

  /// Encontra todos os processos chamados exatamente `pi` cujo PPID é este
  /// processo Cockpit. Esses são os órfãos deixados pelo hot restart: a isolate
  /// Dart foi reciclada mas o processo macOS (e seus filhos) sobreviveu.
  static Future<List<int>> _orphanedPiChildren() async {
    if (!Platform.isMacOS && !Platform.isLinux) return const <int>[];
    try {
      // pgrep -x pi: apenas processos com nome EXATAMENTE "pi"
      final pgrepResult = await Process.run('pgrep', ['-x', 'pi']);
      final stdout = (pgrepResult.stdout as String).trim();
      if (stdout.isEmpty) return const <int>[];

      final myCockpitPid = pid; // dart:io — PID do processo macOS deste app
      final piPids = stdout
          .split('\n')
          .map((l) => int.tryParse(l.trim()))
          .whereType<int>()
          .toList();

      // Verifica o PPID de cada pi: só inclui os que são filhos diretos de mim.
      final orphans = <int>[];
      for (final piPid in piPids) {
        final psResult = await Process.run('ps', [
          '-o',
          'ppid=',
          '-p',
          '$piPid',
        ]);
        if (psResult.exitCode != 0) continue;
        final ppid = int.tryParse((psResult.stdout as String).trim());
        if (ppid == myCockpitPid) orphans.add(piPid);
      }
      return orphans;
    } catch (_) {
      return const <int>[];
    }
  }

  /// Registra [pid] no arquivo. Chamado logo após o spawn bem-sucedido.
  static Future<void> register(int pid) async {
    await _registry.register(pid);
  }

  /// Remove [pid] do arquivo. Chamado na saída limpa do processo.
  static Future<void> unregister(int pid) async {
    await _registry.unregister(pid);
  }
}
