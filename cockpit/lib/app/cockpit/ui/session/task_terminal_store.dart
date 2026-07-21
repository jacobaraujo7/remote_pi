import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_scrollback_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';

/// Mantém **um emulador [Terminal] por task**, alimentado continuamente pelo
/// output do runner — independente de haver ou não uma aba aberta. É isso que
/// preserva o estado em runtime: a aba de visualização ([TaskOutputSession]) só
/// renderiza o terminal que vive aqui; fechá-la não perde o buffer, e o runner
/// segue.
///
/// **Persistência entre restarts**: o output decodificado é gravado em disco
/// (via [TerminalScrollbackStore], namespace [_kTasksProject], chave = `taskId`)
/// e re-semeado no terminal recriado — assim o restore reabre a aba mostrando o
/// último output (read-only). A task em si **não** roda de novo (o processo
/// morreu); só o histórico volta.
///
/// App-scoped (bind no `cockpit_module`); criado já no mount da `CockpitViewModel`
/// (que o injeta), então escuta desde o boot.
class TaskTerminalStore {
  TaskTerminalStore(this._runner, this._scrollback) {
    _sub = _runner.runs().listen(_onRun);
  }

  final TaskRunnerGateway _runner;
  final TerminalScrollbackStore _scrollback;
  StreamSubscription<TaskRun>? _sub;

  /// `projectId` sintético sob o qual os logs de task vivem no scrollback store
  /// (`.../terminal_scrollback/__tasks__/<taskId>.log`). Não colide com ids de
  /// projeto reais.
  static const String _kTasksProject = '__tasks__';

  /// Teto do histórico persistido por task (~256 KB de output decodificado).
  static const int _kMaxRecordChars = 256 * 1024;

  final _terminals = <String, CockpitTerminalController>{};
  final _outSubs = <String, StreamSubscription<String>>{};
  final _lastPid = <String, int?>{};
  final _record = <String, StringBuffer>{};
  final _flushTimers = <String, Timer>{};

  /// Terminal da task (cria um vazio na primeira vez — read-only na UI). O
  /// `onResize` é ligado ao pty pra o output refluir ao tamanho do viewer; na
  /// primeira criação, semeia de forma assíncrona o output salvo em disco.
  /// Terminal já existente da task, sem criar um vazio (leitura via CLI
  /// `cockpit read-task` — criar aqui registraria um buffer fantasma).
  TerminalEngine _defaultEngine = TerminalEngine.ghostty;

  /// Vale só para buffers criados depois da troca; tasks já existentes mantêm
  /// o controller e o estado em memória.
  void setDefaultEngine(TerminalEngine engine) => _defaultEngine = engine;

  CockpitTerminalController? existingTerminal(String taskId) =>
      _terminals[taskId];

  CockpitTerminalController terminalFor(
    String taskId, {
    TerminalEngine? engine,
  }) => _terminals.putIfAbsent(taskId, () {
    final term = createTerminalController(engine ?? _defaultEngine);
    term.onResize = (columns, rows) => _runner.resize(taskId, rows, columns);
    unawaited(_seed(taskId, term));
    return term;
  });

  /// Reproduz o output salvo no terminal recém-criado (restore). `\x1bc` (RIS)
  /// limpa qualquer modo residual em que a task morreu. No-op se um run já
  /// começou a escrever (corrida com o `_onRun`) ou não há nada salvo.
  Future<void> _seed(String taskId, CockpitTerminalController term) async {
    final raw = await _scrollback.load(
      projectId: _kTasksProject,
      sessionId: taskId,
    );
    if (raw == null || raw.isEmpty) return;
    if (_outSubs.containsKey(taskId)) return; // run vivo já alimenta o terminal
    if (_record[taskId]?.isNotEmpty ?? false) return;
    term.restore('\x1bc$raw');
    (_record[taskId] ??= StringBuffer()).write(raw);
  }

  void _onRun(TaskRun run) {
    if (!run.isActive) return;
    // Só (re)liga quando é um run NOVO (pid mudou) — building↔running do mesmo
    // processo não re-subscreve.
    if (_lastPid[run.taskId] == run.pid) return;
    _lastPid[run.taskId] = run.pid;

    final term = terminalFor(run.taskId);
    // Restart (já houve run): limpa tela + scrollback e volta o cursor ao topo
    // — o novo run começa do zero (mesma sequência do comando `clear`). O
    // histórico salvo também zera, pra refletir só o run atual.
    if (_outSubs.containsKey(run.taskId)) {
      term.write('\x1b[H\x1b[2J\x1b[3J');
      _record[run.taskId]?.clear();
    }
    _outSubs.remove(run.taskId)?.cancel();
    _outSubs[run.taskId] = _runner
        .output(run.taskId)
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((data) {
          term.write(data);
          _append(run.taskId, data);
        });
  }

  /// Acumula o output no buffer da task (ring trim amortizado) e agenda um flush
  /// debounced pra disco.
  void _append(String taskId, String data) {
    final buf = _record.putIfAbsent(taskId, StringBuffer.new);
    buf.write(data);
    if (buf.length > _kMaxRecordChars) {
      final s = buf.toString();
      _record[taskId] = StringBuffer(
        s.substring(s.length - (_kMaxRecordChars * 3 ~/ 4)),
      );
    }
    _flushTimers[taskId]?.cancel();
    _flushTimers[taskId] = Timer(
      const Duration(seconds: 1),
      () => unawaited(_flush(taskId)),
    );
  }

  Future<void> _flush(String taskId) async {
    final buf = _record[taskId];
    if (buf == null || buf.isEmpty) return;
    await _scrollback.save(
      projectId: _kTasksProject,
      sessionId: taskId,
      contents: buf.toString(),
    );
  }

  /// Grava agora o output pendente de todas as tasks — chamado no quit do app
  /// (o debounce de 1s pode não ter disparado ainda).
  Future<void> flushAll() async {
    for (final t in _flushTimers.values) {
      t.cancel();
    }
    _flushTimers.clear();
    await Future.wait(_record.keys.map(_flush));
  }

  void dispose() {
    _sub?.cancel();
    for (final t in _flushTimers.values) {
      t.cancel();
    }
    _flushTimers.clear();
    for (final s in _outSubs.values) {
      s.cancel();
    }
    _outSubs.clear();
    for (final terminal in _terminals.values) {
      terminal.dispose();
    }
    _terminals.clear();
  }
}
