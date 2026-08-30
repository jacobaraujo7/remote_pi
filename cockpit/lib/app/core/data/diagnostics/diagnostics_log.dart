import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/utils/user_home.dart';
import 'package:flutter/foundation.dart';

/// Log de diagnóstico em arquivo + detector de encerramento sujo.
///
/// **Por que arquivo, e não só `debugPrint`**: um app GUI aberto pelo Finder/
/// Dock não tem stdout visível — todo `debugPrint` em produção cai no vazio. Sem
/// isso, "o Cockpit fechou sozinho" chega como relato sem nenhuma pista.
///
/// **Por que fora da pasta relocável**: mora em `~/.cockpit/logs/`, o mesmo lugar
/// fixo do ponteiro `storage_root`. O log precisa existir *antes* de o
/// `StorageLocation` resolver (falha de boot é justamente o que queremos
/// registrar), e log de crash não deve viajar junto quando o usuário troca a
/// pasta de dados.
///
/// **Por que escrita síncrona**: os eventos são raros (erro/boot/exit) e o
/// processo pode morrer no instante seguinte — `writeAsStringSync` garante que o
/// registro chegou ao disco antes disso. Escrita assíncrona se perderia
/// exatamente no caso que mais interessa.
class DiagnosticsLog {
  DiagnosticsLog._();

  static final DiagnosticsLog instance = DiagnosticsLog._();

  /// Quantos dias de log guardar. Passa disso, o arquivo é apagado no boot.
  static const int retentionDays = 7;

  /// Teto por arquivo. Um loop de erro poderia encher o disco do usuário; ao
  /// estourar, para de acrescentar (mantendo o começo, que tem a causa raiz).
  static const int maxFileBytes = 5 * 1024 * 1024;

  Directory? _dir;
  File? _sessionFile;
  String? _appVersion;
  bool _truncated = false;

  /// Sessão anterior que não registrou saída limpa — `null` quando o último
  /// encerramento foi normal (ou é a primeira execução). Lido uma vez no
  /// [init]; é o sinal que cobre morte nativa (SIGPIPE, segfault), que nenhum
  /// handler Dart consegue capturar.
  DirtySession? previousCrash;

  /// Pasta dos logs. `null` quando não há home resolvível (ambiente mínimo) —
  /// nesse caso o log inteiro vira no-op em vez de derrubar o boot.
  Directory? get directory => _dir;

  /// Arquivo do dia corrente.
  File? get currentFile {
    final dir = _dir;
    if (dir == null) return null;
    return File('${dir.path}/cockpit-${_stamp(DateTime.now())}.log');
  }

  /// Prepara a pasta, rotaciona logs velhos, detecta encerramento sujo da
  /// sessão anterior e marca esta sessão como em andamento.
  ///
  /// Nunca lança: diagnóstico que quebra o boot é pior que diagnóstico ausente.
  ///
  /// [baseDir] existe só para teste — em produção o caminho é sempre
  /// `~/.cockpit/logs`, que não pode depender de configuração (é justamente
  /// onde se olha quando o resto do app não subiu).
  Future<void> init({
    required String appVersion,
    @visibleForTesting String? baseDir,
  }) async {
    _appVersion = appVersion;
    _truncated = false;
    try {
      final home = baseDir ?? userHome();
      if (home == null) return;
      final dir = Directory(baseDir != null ? home : '$home/.cockpit/logs');
      await dir.create(recursive: true);
      _dir = dir;
      _sessionFile = File('${dir.path}/session.json');

      await _rotate(dir);
      previousCrash = await _readDirtySession();
      await _markSessionStart();

      if (previousCrash != null) {
        log(
          'boot',
          'sessão anterior terminou sem saída limpa '
              '(pid ${previousCrash!.pid}, versão ${previousCrash!.appVersion}, '
              'iniciada em ${previousCrash!.startedAt.toIso8601String()})',
        );
      }
      log('boot', 'Cockpit $appVersion — ${_platformLine()}');
    } on Object catch (e) {
      debugPrint('[diagnostics] init falhou: $e');
    }
  }

  /// Registra uma linha de contexto (não-erro).
  void log(String tag, String message) => _append('[$tag] $message');

  /// Registra um erro com stack trace. [tag] identifica a origem (`flutter`,
  /// `zone`, `isolate`, `platform`) para dar pra separar depois.
  void logError(String tag, Object error, StackTrace? stack) {
    final buffer = StringBuffer('[$tag] $error');
    if (stack != null) buffer.write('\n$stack');
    _append(buffer.toString());
  }

  /// Marca esta sessão como encerrada normalmente. Precisa ser chamado em
  /// **todo** caminho de saída intencional — inclusive nos `exit(0)` manuais
  /// (reset de fábrica, troca de pasta de dados), senão o próximo boot acusa
  /// falso positivo de crash.
  void markCleanExit() {
    try {
      final file = _sessionFile;
      if (file != null && file.existsSync()) file.deleteSync();
      _append('[exit] encerramento limpo');
    } on Object catch (_) {
      /* best-effort: marcador some no rotate seguinte */
    }
  }

  /// Conteúdo do log de hoje, para exibir na UI / anexar numa issue. Devolve as
  /// últimas [maxLines] linhas — o começo do arquivo raramente importa para um
  /// erro que acabou de acontecer.
  Future<String> tail({int maxLines = 200}) async {
    try {
      final file = currentFile;
      if (file == null || !await file.exists()) return '';
      final lines = const LineSplitter().convert(await file.readAsString());
      if (lines.length <= maxLines) return lines.join('\n');
      return lines.sublist(lines.length - maxLines).join('\n');
    } on Object catch (_) {
      return '';
    }
  }

  void _append(String entry) {
    final line = '${DateTime.now().toIso8601String()} $entry\n';
    // Espelha no console ANTES de olhar o arquivo: em `flutter run` é onde
    // o dev vê primeiro, e é o ÚNICO canal quando não há arquivo — caso do
    // iOS/iPad, onde o log fica dentro do sandbox e a UI de "revelar pasta"
    // não leva a lugar nenhum. Com o `return` antes daqui, um cliente sem
    // arquivo perdia TODO o diagnóstico, inclusive rodando em debug — que é
    // exatamente quando alguém está tentando enxergar.
    debugPrint(line.trimRight());
    final file = currentFile;
    if (file == null) return;
    try {
      if (_truncated) return;
      if (file.existsSync() && file.lengthSync() > maxFileBytes) {
        _truncated = true;
        file.writeAsStringSync(
          '${DateTime.now().toIso8601String()} [diagnostics] '
          'teto de $maxFileBytes bytes atingido; parando de registrar hoje\n',
          mode: FileMode.append,
        );
        return;
      }
      file.writeAsStringSync(line, mode: FileMode.append);
    } on Object catch (_) {
      /* disco cheio / permissão: diagnóstico nunca derruba o app */
    }
  }

  /// Apaga logs mais velhos que [retentionDays].
  Future<void> _rotate(Directory dir) async {
    final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('cockpit-') || !name.endsWith('.log')) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } on Object catch (_) {
        /* arquivo travado: tenta de novo no próximo boot */
      }
    }
  }

  /// Marcador de sessão viva. A ausência dele no boot seguinte = saída limpa;
  /// a presença = o processo morreu sem passar por [markCleanExit].
  Future<void> _markSessionStart() async {
    final file = _sessionFile;
    if (file == null) return;
    await file.writeAsString(
      jsonEncode({
        'pid': pid,
        'appVersion': _appVersion,
        'startedAt': DateTime.now().toIso8601String(),
        'platform': _platformLine(),
        // Em debug o processo é morto o tempo todo pelo ferramental (hot
        // restart, stop da IDE), e nada disso é crash. Quem grava a sessão é
        // quem sabe em que build ela rodou.
        'debug': kDebugMode,
      }),
    );
  }

  Future<DirtySession?> _readDirtySession() async {
    final file = _sessionFile;
    try {
      if (file == null || !await file.exists()) return null;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return DirtySession(
        pid: (map['pid'] as num?)?.toInt() ?? 0,
        appVersion: map['appVersion'] as String? ?? 'desconhecida',
        startedAt:
            DateTime.tryParse(map['startedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        platform: map['platform'] as String? ?? '',
        debug: map['debug'] as bool? ?? false,
      );
    } on Object catch (_) {
      return null; // marcador ilegível → trata como saída limpa
    }
  }

  static String _platformLine() =>
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  static String _stamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Sessão anterior encerrada sem marcador de saída limpa.
class DirtySession {
  const DirtySession({
    required this.pid,
    required this.appVersion,
    required this.startedAt,
    required this.platform,
    this.debug = false,
  });

  final int pid;
  final String appVersion;
  final DateTime startedAt;
  final String platform;

  /// A sessão morta rodava um build de **debug**.
  ///
  /// Ali o processo é encerrado à força a cada hot restart e a cada stop da
  /// IDE, então "morreu sem saída limpa" é o caso normal, não o excepcional.
  /// Continua indo para o log — só não vira aviso na cara de quem está
  /// desenvolvendo.
  final bool debug;
}
