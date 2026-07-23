import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/utils/user_home.dart';

/// Persiste PIDs de processos filhos sem misturar instâncias do Cockpit.
///
/// Cada categoria grava um arquivo por PID proprietário:
///
/// ```text
/// ~/.pi/cockpit/process-pids/<category>/<ownerPid>.pids
/// ```
///
/// No boot, a instância limpa o próprio arquivo (hot restart) e arquivos de
/// proprietários que já morreram (crash/cold restart). Arquivos pertencentes a
/// outros Cockpits ainda vivos são preservados.
class OwnedProcessRegistry {
  OwnedProcessRegistry({
    required this.category,
    String? rootPath,
    int? ownerPid,
    Future<bool> Function(int pid)? isProcessAlive,
    FutureOr<void> Function(int pid)? killProcess,
    List<String> legacyFiles = const [],
  }) : assert(RegExp(r'^[a-z0-9_-]+$').hasMatch(category)),
       rootPath = rootPath ?? _defaultRootPath(),
       ownerPid = ownerPid ?? pid,
       _isProcessAlive = isProcessAlive ?? _defaultIsProcessAlive,
       _killProcess = killProcess ?? _defaultKillProcess {
    _legacyFiles.addAll(legacyFiles);
  }

  final String category;
  final String rootPath;
  final int ownerPid;
  final Future<bool> Function(int pid) _isProcessAlive;
  final FutureOr<void> Function(int pid) _killProcess;
  final List<String> _legacyFiles = [];

  Future<void> _ioChain = Future<void>.value();

  String get _categoryPath => '$rootPath${Platform.pathSeparator}$category';

  String _pathFor(int owner) =>
      '$_categoryPath${Platform.pathSeparator}$owner.pids';

  /// Registra um processo filho desta instância.
  Future<void> register(int childPid) => _serialize(() async {
    try {
      final file = File(_pathFor(ownerPid));
      await file.parent.create(recursive: true);
      await file.writeAsString('$childPid\n', mode: FileMode.append);
    } catch (_) {
      // Registry é uma proteção best-effort; falha de IO não impede o spawn.
    }
  });

  /// Remove um processo que já encerrou normalmente.
  Future<void> unregister(int childPid) => _serialize(() async {
    await _removePid(File(_pathFor(ownerPid)), childPid);
  });

  /// Limpa filhos do ciclo anterior sem tocar em outras instâncias vivas.
  Future<void> cleanOrphans() => _serialize(() async {
    await _cleanLegacyFiles();

    final dir = Directory(_categoryPath);
    if (!await dir.exists()) return;

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final owner = _ownerFromPath(entity.path);
        if (owner == null) continue;

        final shouldClean =
            owner == ownerPid || !await _safeIsProcessAlive(owner);
        if (!shouldClean) continue;

        await _reapFile(entity);
      }
    } catch (_) {
      // Diretório removido/indisponível durante a varredura: best-effort.
    }
  });

  Future<void> _cleanLegacyFiles() async {
    for (final path in _legacyFiles) {
      await _reapFile(File(path));
    }
  }

  Future<void> _reapFile(File file) async {
    try {
      if (!await file.exists()) return;
      final children = await _readPids(file);
      // Remove antes do kill para nunca atingir um PID reutilizado num boot
      // futuro caso o processo já tenha encerrado entre a leitura e o sinal.
      await file.delete();
      for (final child in children) {
        try {
          await _killProcess(child);
        } catch (_) {}
      }
    } catch (_) {
      // Arquivo concorrente/corrompido não pode derrubar o bootstrap.
    }
  }

  Future<void> _removePid(File file, int childPid) async {
    try {
      if (!await file.exists()) return;
      final kept = (await _readPids(file)).where((p) => p != childPid).toList();
      if (kept.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString('${kept.join('\n')}\n');
      }
    } catch (_) {}
  }

  Future<List<int>> _readPids(File file) async => (await file.readAsLines())
      .map((line) => int.tryParse(line.trim()))
      .whereType<int>()
      .toSet()
      .toList();

  int? _ownerFromPath(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final match = RegExp(r'^(\d+)\.pids$').firstMatch(name);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<bool> _safeIsProcessAlive(int processPid) async {
    try {
      return await _isProcessAlive(processPid);
    } catch (_) {
      // Em dúvida, preserva: matar processo de outra instância é pior que
      // deixar um órfão para uma limpeza posterior.
      return true;
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _ioChain.then((_) => operation());
    _ioChain = result.catchError((_) {});
    return result;
  }

  static String _defaultRootPath() {
    final home = userHome() ?? '';
    return '$home${Platform.pathSeparator}.pi${Platform.pathSeparator}'
        'cockpit${Platform.pathSeparator}process-pids';
  }

  static Future<bool> _defaultIsProcessAlive(int processPid) async {
    if (processPid == pid) return true;
    if (Platform.isWindows) {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $processPid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      if (result.exitCode != 0) return true;
      final output = (result.stdout as String).trim();
      return RegExp('"$processPid"(?:,|\\s)').hasMatch(output);
    }

    final result = await Process.run('ps', ['-p', '$processPid', '-o', 'pid=']);
    if (result.exitCode != 0) return false;
    return (result.stdout as String).trim() == '$processPid';
  }

  static void _defaultKillProcess(int processPid) {
    Process.killPid(processPid, ProcessSignal.sigkill);
  }
}
