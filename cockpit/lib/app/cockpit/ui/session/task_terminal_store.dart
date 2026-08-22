import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_scrollback_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/json_log_highlighter.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/utils/quiet_period_debouncer.dart';

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
  TaskTerminalStore(this._localRunner, this._scrollback) {
    registerRunner(_localRunner);
  }

  final TaskRunnerGateway _localRunner;
  final TerminalScrollbackStore _scrollback;

  /// Runners que o store observa. Além do local, cada workspace REMOTO tem seu
  /// próprio [TaskRunnerGateway] (um `RemoteTaskRunner` por host, criado sob
  /// demanda) — sem registrá-lo aqui, o output das tasks remotas não alimenta o
  /// terminal e a aba fica vazia (plano 60, Wave D).
  final _runners = <TaskRunnerGateway>{};
  final _runSubs = <StreamSubscription<TaskRun>>[];

  /// Passa a observar os runs/output de [runner] (idempotente). Chamado no boot
  /// para o runner local e a cada `RemoteTaskRunner` novo.
  void registerRunner(TaskRunnerGateway runner) {
    if (!_runners.add(runner)) return;
    _runSubs.add(runner.runs().listen((run) => _onRun(runner, run)));
  }

  /// `projectId` sintético sob o qual os logs de task vivem no scrollback store
  /// (`.../terminal_scrollback/__tasks__/<taskId>.log`). Não colide com ids de
  /// projeto reais.
  static const String _kTasksProject = '__tasks__';

  /// Teto do histórico persistido por task (~256 KB de output decodificado).
  static const int _kMaxRecordChars = 256 * 1024;

  final _terminals = <String, CockpitTerminalController>{};
  final _outSubs = <String, StreamSubscription<String>>{};
  final _lastPid = <String, int?>{};

  /// Runner que produziu o último run de cada task — roteia `resize` (e futuros
  /// comandos) pro runner certo (local vs host remoto).
  final _runnerOf = <String, TaskRunnerGateway>{};
  final _record = <String, StringBuffer>{};

  /// Realce de logs JSON estruturados, um por task (stateful: guarda a cauda
  /// de linha entre chunks). Aplicado aqui — o único ponto onde o output do
  /// runner encontra o terminal — vale pro runner local E pros remotos.
  final _highlighters = <String, JsonLogHighlighter>{};
  final _flushDebouncers = <String, QuietPeriodDebouncer>{};

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
    term.onResize = (columns, rows) =>
        (_runnerOf[taskId] ?? _localRunner).resize(taskId, rows, columns);
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

  void _onRun(TaskRunnerGateway runner, TaskRun run) {
    if (!run.isActive) {
      if (!run.isTransitioning) _drainHighlighter(run.taskId);
      return;
    }
    // Só (re)liga quando é um run NOVO (pid mudou) — building↔running do mesmo
    // processo não re-subscreve.
    if (_lastPid[run.taskId] == run.pid) return;
    _lastPid[run.taskId] = run.pid;
    _runnerOf[run.taskId] = runner;

    final term = terminalFor(run.taskId);
    // Restart (já houve run): limpa tela + scrollback e volta o cursor ao topo
    // — o novo run começa do zero (mesma sequência do comando `clear`). O
    // histórico salvo também zera, pra refletir só o run atual.
    if (_outSubs.containsKey(run.taskId)) {
      term.write('\x1b[H\x1b[2J\x1b[3J');
      _record[run.taskId]?.clear();
      _highlighters.remove(run.taskId);
    }
    _outSubs.remove(run.taskId)?.cancel();
    final highlighter = _highlighters[run.taskId] ??= JsonLogHighlighter();
    _outSubs[run.taskId] = runner.output(run.taskId).listen((data) {
      // Log JSON sai colorido pela paleta ANSI do tema; o resto passa intacto.
      final painted = highlighter.process(data);
      if (painted.isEmpty) return; // linha incompleta retida
      term.write(painted);
      _append(run.taskId, painted);
    });
  }

  /// Fim do run: a última linha pode ter ficado retida no highlighter esperando
  /// um `\n` que o processo não chegou a emitir — solta crua pra não sumir.
  void _drainHighlighter(String taskId) {
    final pending = _highlighters.remove(taskId)?.flushPending();
    if (pending == null || pending.isEmpty) return;
    _terminals[taskId]?.write(pending);
    _append(taskId, pending);
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
    _flushDebouncers
        .putIfAbsent(
          taskId,
          () => QuietPeriodDebouncer(
            delay: const Duration(seconds: 1),
            onQuiet: () => unawaited(_flush(taskId)),
          ),
        )
        .trigger();
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
    for (final debouncer in _flushDebouncers.values) {
      debouncer.cancel();
    }
    await Future.wait(_record.keys.map(_flush));
  }

  void dispose() {
    for (final sub in _runSubs) {
      sub.cancel();
    }
    _runSubs.clear();
    for (final debouncer in _flushDebouncers.values) {
      debouncer.dispose();
    }
    _flushDebouncers.clear();
    for (final s in _outSubs.values) {
      s.cancel();
    }
    _outSubs.clear();
    _highlighters.clear();
    for (final terminal in _terminals.values) {
      terminal.dispose();
    }
    _terminals.clear();
  }
}
