import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_attachments.dart';
import 'package:cockpit/app/cockpit/domain/services/terminal_attachment_service.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_metrics_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_scrollback_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/core/data/diagnostics/performance_diagnostics.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/core/terminal/secret_redactor.dart';
import 'package:cockpit/app/cockpit/domain/services/terminal_harness_monitor.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/terminal/pty_output_scheduler.dart';
import 'package:cockpit/app/core/utils/quiet_period_debouncer.dart';
import 'package:cockpit/app/core/utils/bounded_text_buffer.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_input.dart';
import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart';

/// Status de um `claude` (ou outro harness) rodando dentro de uma aba de
/// terminal, reportado pelo `cockpit-hook` via socket (ver
/// [TerminalStatusServer]).
enum TerminalStatus { idle, working, waiting }

/// Uma aba de terminal: um shell num PTY ([TerminalGateway]) ligado a um
/// emulador [Terminal] do xterm. O `TerminalView` (na PaneView) renderiza
/// `terminal`. Mata o PTY no `dispose` (sem órfão).
class TerminalSession extends PaneItem {
  TerminalSession({
    required this.id,
    this.owner = const TerminalOwner.workspace(),
    required this.projectId,
    required this.workingDirectory,
    required this._gateway,
    required this.profile,
    this.attachmentService,
    this.attachmentProjectRoot = '',
    this.attachmentsRemote = false,
    String? title,
    Map<String, String> spawnEnv = const <String, String>{},
    Iterable<String> redactSecrets = const <String>[],
    TerminalScrollbackStore? scrollbackStore,
    String? replay,
    String? startupCommand,
    TerminalEngine engine = TerminalEngine.xterm,
    this._monitor,
  }) : _scrollback = scrollbackStore,
       _redactor = SecretRedactor(redactSecrets),
       _title = title ?? 'New terminal' {
    // O `ShiftEnterInputHandler` (antes do padrão) faz Shift+Enter virar quebra
    // de linha nos harnesses (claude, codex, pi) em vez de submeter; ele lê o
    // estado do kitty keyboard protocol que `_kitty` rastreia pela saída do PTY.
    terminal = createTerminalController(
      engine,
      xtermInputHandler: CascadeInputHandler([
        ShiftEnterInputHandler(_kitty),
        defaultInputHandler,
      ]),
    );
    if (PerformanceDiagnostics.instance.enabled) {
      _firstOutputClock = Stopwatch()..start();
    }

    // Replay do scrollback salvo (restauração): entra na fila ANTES de subir o
    // shell, então a saída viva nasce logo abaixo. No Ghostty a fila só é
    // aplicada após o primeiro resize da view, evitando interpretar posições
    // gravadas numa grade provisória de 80 colunas. O `\x1bc` que limpa estado
    // residual já vem embutido em `replay` (montado na VM).
    if (replay != null && replay.isNotEmpty) terminal.restore(replay);

    // Sobe o shell e liga os dois lados. O `.cast<List<int>>()` re-vincula o
    // tipo do stream (o PTY emite Uint8List) para o `utf8.decoder` aceitar e
    // decodificar em streaming (trata multibyte partido entre chunks).
    _gateway.start(
      workingDirectory: workingDirectory,
      profile: profile,
      rows: 25,
      columns: 80,
      extraEnv: spawnEnv,
    );
    // A pasta do workspace pode ter sumido entre dois boots (o layout salvo
    // ainda aponta pra lá). O gateway abre no ancestral mais próximo em vez de
    // falhar, mas isso precisa ficar VISÍVEL: senão o usuário digita achando
    // que está na pasta do projeto.
    final spawned = _gateway.spawnDirectory;
    if (spawned != null && spawned.fellBack) {
      // Fora da árvore de widgets não há `context`: o `t` global é o acesso
      // certo aqui (ver a regra de i18n no CLAUDE.md).
      terminal.write(
        '\x1b[33m'
        '${t.cockpit.terminal.cwdFallbackWarning(requested: spawned.requested, path: spawned.path)}'
        '\x1b[0m\r\n',
      );
    }
    // Coalesce + backpressure (plan/57): um `terminal.write` por frame e
    // `acknowledgeOutput` com cap, pra TUI busy não saturar o isolate principal.
    _coalescer = PtyOutputCoalescer(
      onAcknowledge: _gateway.acknowledgeOutput,
      onFlush: (batch) {
        final firstOutputClock = _firstOutputClock;
        if (firstOutputClock != null) {
          _firstOutputClock = null;
          PerformanceDiagnostics.instance.record(
            PerfMetric.terminalFirstOutput,
            {PerfField.durationUs: firstOutputClock.elapsedMicroseconds},
            force: true,
          );
        }
        _kitty.feed(batch); // observa push/pop do kitty antes de renderizar.
        terminal.write(batch);
        _record(batch); // grava o scrollback pra replay no próximo boot.
        _trackCwd(batch); // rastreia o cwd vivo (OSC 7) pra restaurar nele.
        // Saída do PTY costuma coincidir com spawn/troca de processo em
        // foreground — reavalia o ícone sem esperar o timer de baseline.
        _kickHarnessMonitor();
      },
    );
    _coalescer.visible = false; // a view ainda não foi montada
    // Redação dos valores do `.env.cockpit` ANTES do coalescer: cobre tela,
    // scrollback gravado e `read-tab` de uma vez. Sem segredos é passthrough.
    final decoded = _gateway.output.cast<List<int>>().transform(
      const Utf8Decoder(allowMalformed: true),
    );
    // Sempre pelo filtro (passthrough quando vazio): o workspace remoto só
    // conhece seus segredos depois do spawn, via [updateRedaction].
    _sub = decoded
        .map(_redactor.feed)
        .where((s) => s.isNotEmpty)
        .listen(
          _coalescer.add,
          onDone: () {
            final tail = _redactor.flush();
            if (tail.isNotEmpty) _coalescer.add(tail);
            // Fim do stream = processo encerrado (o PTY local fecha a porta no
            // exit; o sidecar fecha no `PtyExitEvent`). No `dispose` fomos nós
            // que matamos — aí não é notícia pra ninguém.
            if (!_disposed) {
              _processEnded = true;
              notifyListeners();
              onProcessExit?.call();
            }
          },
        );
    terminal.onOutput = (data) {
      final text = utf8.decode(data, allowMalformed: true);
      _maybeInterrupt(text);
      _gateway.write(data);
      // Enter (e equivalentes) = comando submetido → processo pode nascer já.
      if (text.contains('\r') || text.contains('\n')) {
        _kickHarnessMonitor(burst: true);
      }
    };
    terminal.onResize = (columns, rows) {
      _viewportColumns = columns;
      _viewportRows = rows;
      if (!_firstViewportResize.isCompleted) _firstViewportResize.complete();
      _gateway.resize(rows, columns);
    };
    // Programas mudam o título da janela via OSC 0/2 (ex.: shell mostra o cwd,
    // `vim`/`ssh` mostram o arquivo/host). Refletimos isso no nome da aba.
    terminal.onTitleChanged = (osc) {
      rename(_shortTitle(osc));
      _kickHarnessMonitor();
    };

    // Restauração de aba que rodava um harness (ex.: `claude --resume <sid>`):
    // digita o comando no shell novo. Espera o shell de login (`-l`, que lê
    // `.zprofile`/`.zshrc`) montar o prompt antes de enviar, senão a entrada se
    // perde no meio da init. O `\r` submete. NÃO entra no scrollback do replay
    // (o `_record` já roda; mas o comando é re-derivável, então tudo bem).
    if (startupCommand != null && startupCommand.isNotEmpty) {
      _startupTimer = Timer(const Duration(milliseconds: 600), () {
        _gateway.write(utf8.encode('$startupCommand\r'));
        _kickHarnessMonitor(burst: true);
      });
    }

    _monitor?.registerSession(
      sessionId: id,
      rootPid: () => _gateway.rootProcessId,
      wslDistro: profile.wslDistro,
      onHarnessChanged: (newHarness) {
        if (_activeHarness != newHarness) {
          _activeHarness = newHarness;
          notifyListeners();
        }
      },
    );
  }

  /// Disparado quando o turno entra em `idle` ou `waiting` (terminou ou precisa
  /// de aprovação). A VM usa pra notificar o workspace — espelha o `onTurnEnd`
  /// do [AgentSession].
  VoidCallback? onTurnFinished;

  /// Disparado quando o shell muda de diretório (capturado por OSC 7). A VM usa
  /// pra persistir o cwd vivo no layout — assim o restore sobe o shell onde o
  /// usuário parou, não no cwd inicial da aba.
  VoidCallback? onCwdChanged;

  /// Disparado quando o processo do PTY termina por conta própria (não pelo
  /// [dispose]). Uma aba de shell fica na tela mostrando o terminal morto; a do
  /// Neovim é assinada pela VM e fecha junto com o `:q`.
  VoidCallback? onProcessExit;

  bool _disposed = false;
  bool _processEnded = false;
  bool get hasExited => _processEnded;

  int? _viewportColumns;
  int? _viewportRows;
  final Completer<void> _firstViewportResize = Completer<void>();

  /// Última grade medida pela view, sem recorrer ao tamanho inicial da PTY.
  ({int columns, int rows})? get viewportSize {
    final columns = _viewportColumns;
    final rows = _viewportRows;
    if (columns == null || rows == null) return null;
    return (columns: columns, rows: rows);
  }

  /// Reaplica à PTY a grade efetivamente medida pela view.
  ///
  /// TUIs podem nascer na grade provisória 80x25 antes do primeiro layout. Ao
  /// reativar uma aba, a view também pode ter sido redimensionada enquanto
  /// estava desmontada. Esperar a primeira medida e repeti-la elimina ambos os
  /// casos sem depender de um segundo resize do usuário.
  Future<void> synchronizeViewport() async {
    if (_viewportColumns == null || _viewportRows == null) {
      await _firstViewportResize.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
    }
    final columns = _viewportColumns;
    final rows = _viewportRows;
    if (columns != null && rows != null) _gateway.resize(rows, columns);
  }

  TerminalStatus _status = TerminalStatus.idle;
  TerminalStatus get status => _status;

  HarnessKind? _activeHarness;
  HarnessKind? _remoteHookHarness;
  HarnessKind? get activeHarness => _activeHarness ?? _remoteHookHarness;

  /// A remote PID cannot be probed in this client's namespace. An owned
  /// terminal's own hook can supply identity without inventing it from config.
  void observeRemoteHookHarness(AgentHarness? harness) {
    if (!attachmentsRemote) return;
    final next = switch (harness) {
      AgentHarness.claude => HarnessKind.claudeCode,
      AgentHarness.codex => HarnessKind.codex,
      AgentHarness.pi => HarnessKind.pi,
      null => null,
    };
    if (_remoteHookHarness == next) return;
    _remoteHookHarness = next;
    notifyListeners();
  }

  /// PID do shell/PTY local. Ausente quando o terminal roda em host remoto.
  int? get rootProcessId => _gateway.rootProcessId;
  bool get processMetricsAreRemote => _gateway is RemoteProcessMetricsGateway;
  Future<ProcessMetricsSnapshot> readRemoteProcessMetrics() =>
      (_gateway as RemoteProcessMetricsGateway).readRemoteProcessMetrics();

  /// Linux PID in the selected WSL distro. Never inferred from the Windows
  /// `wsl.exe` PID because the two namespaces are unrelated.
  int? get wslProcessId => _gateway.wslProcessId;

  /// `true` enquanto o harness está processando um turno (acende o spinner).
  @override
  bool get isWorking => _status == TerminalStatus.working;

  /// Perfil que subiu esta aba (login shell, PowerShell, `Ubuntu (WSL)`…).
  /// Guardado pra fatia 3 (dropdown do `+`) e pra restauração da aba no perfil
  /// em que ela nasceu.
  @override
  final TerminalOwner owner;

  final TerminalProfile profile;

  /// Session-id e transcript do agente rodando nesta aba, capturados dos hooks.
  /// Servem pra retomar a sessão no restore da aba e pra ler o `.jsonl`.
  String? claudeSessionId;
  String? transcriptPath;

  int? reportedContextTokens;
  int? reportedContextWindow;
  DateTime? reportedContextAt;

  void clearGraphMetrics() {
    if (reportedContextAt == null) return;
    reportedContextTokens = null;
    reportedContextWindow = null;
    reportedContextAt = null;
    notifyListeners();
  }

  void applyGraphMetrics(int tokens, int window) {
    if (tokens < 0 || window <= 0) return;
    reportedContextTokens = tokens;
    reportedContextWindow = window;
    reportedContextAt = DateTime.now();
    notifyListeners();
  }

  /// Qual harness emitiu o [claudeSessionId]. Sem isso o restore montaria
  /// sempre `claude --resume <id>` — que falha com "No conversation found" se o
  /// id veio do Codex.
  AgentHarness agentHarness = AgentHarness.claude;

  bool _unseen = false;
  @override
  bool get unseenFinish => _unseen;

  @override
  void markUnseen() {
    if (_unseen) return;
    _unseen = true;
    notifyListeners();
  }

  @override
  void clearUnseen() {
    if (!_unseen) return;
    _unseen = false;
    notifyListeners();
  }

  Timer? _notifyDebounce;

  /// `true` entre o início do turno (`UserPromptSubmit`) e o seu fim (`Stop` →
  /// idle). Um `working` de atividade mid-turn (Pre/PostToolUse) só é válido com
  /// um turno ativo — se chega sem turno ativo logo após um `idle`, é um hook
  /// tardio/reordenado do turno que já acabou e é descartado (senão o spinner
  /// fica girando pra sempre).
  bool _turnActive = false;
  DateTime? _lastIdleAt;

  /// Janela em que um `working` mid-turn órfão (sem turno ativo) pós-`idle` é
  /// tratado como reordenação. Generosa (a real reordenação chega em ms); turnos
  /// novos legítimos vêm como `UserPromptSubmit` (isTurnStart), que nunca é
  /// filtrado — então a janela não atrapalha follow-ups enfileirados.
  static const Duration _staleWorkingGuard = Duration(seconds: 5);

  /// Aplica um status reportado pelo `cockpit hook` (via [TerminalStatusServer]).
  /// [sessionId]/[transcriptPath]/[harness] são capturados pra persistência —
  /// é o que permite retomar a aba no harness certo.
  /// [isTurnStart] = evento `UserPromptSubmit` (início de turno).
  void applyClaudeStatus({
    required TerminalStatus status,
    bool isTurnStart = false,
    String? sessionId,
    String? transcriptPath,
    AgentHarness? harness,
  }) {
    // O harness anda junto do id: trocar um sem o outro montaria um comando de
    // resume com o id do harness errado.
    if (sessionId != null && sessionId.isNotEmpty && harness != null) {
      agentHarness = harness;
    }
    if (sessionId != null && sessionId.isNotEmpty) claudeSessionId = sessionId;
    if (transcriptPath != null && transcriptPath.isNotEmpty) {
      this.transcriptPath = transcriptPath;
    }

    // Ciclo de vida do turno a partir da semântica do evento.
    if (isTurnStart) _turnActive = true;
    if (status == TerminalStatus.idle) _turnActive = false;

    // Guard anti-spinner-eterno: descarta um `working` mid-turn que chega SEM
    // turno ativo e logo após um `idle` — é o Pre/PostToolUse do turno que
    // acabou, entregue fora de ordem depois do `Stop`.
    if (status == TerminalStatus.working &&
        !isTurnStart &&
        !_turnActive &&
        _lastIdleAt != null &&
        DateTime.now().difference(_lastIdleAt!) < _staleWorkingGuard) {
      return;
    }

    _setStatus(status);
  }

  /// Detecta o **interrupt** do harness na entrada do usuário. O Claude Code
  /// (e demais harnesses) interrompem o turno com um `ESC` cru; e o Claude
  /// Code **não emite `Stop` num interrupt do usuário** — só quando o turno
  /// termina sozinho. Sem isto, o último hook recebido seria um `working`
  /// (Pre/PostToolUse) e o spinner giraria pra sempre. Um `ESC` cru (`\x1b`
  /// sozinho, sem sequência de seta/função) enquanto `working` zera o status
  /// otimista. Se não era interrupt de fato, o `_staleWorkingGuard` descarta o
  /// `working` mid-turn tardio, e um `UserPromptSubmit` legítimo reacende.
  void _maybeInterrupt(String data) {
    if (data == '\x1b' && _status == TerminalStatus.working) {
      _turnActive = false;
      _notifyDebounce?.cancel();
      _status = TerminalStatus.idle;
      _lastIdleAt = DateTime.now();
      notifyListeners();
    }
  }

  void _setStatus(TerminalStatus next) {
    if (next == _status) return;
    _status = next;
    if (next == TerminalStatus.idle) _lastIdleAt = DateTime.now();
    notifyListeners();
    // Debounce ~50ms antes de notificar: absorve flicker idle→working numa
    // repintura de TUI (mesma técnica do iTerm2). Só notifica em idle/waiting.
    _notifyDebounce?.cancel();
    if (next == TerminalStatus.idle || next == TerminalStatus.waiting) {
      _notifyDebounce = Timer(const Duration(milliseconds: 50), () {
        if (_status == next) onTurnFinished?.call();
      });
    }
  }

  /// Encurta títulos longos pra caber melhor na aba. Caminhos viram o último
  /// segmento; `~` é mantido; o resto vai como veio (a aba ainda faz ellipsis).
  String _shortTitle(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !t.contains('/')) return t;
    final segments = t.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? t : segments.last;
  }

  @override
  final String id;
  @override
  final String projectId;
  @override
  final String workingDirectory;

  final TerminalGateway _gateway;
  final TerminalHarnessMonitor? _monitor;
  final KittyKeyboardTracker _kitty = KittyKeyboardTracker();

  /// Troca os valores do `.env.cockpit` por `***` na saída (ver
  /// [SecretRedactor]). Vazio quando o workspace não tem segredos.
  final SecretRedactor _redactor;

  /// Segredos conhecidos depois do spawn (workspace remoto: o `.env.cockpit`
  /// é lido no host pelo gateway, já com a aba viva).
  void updateRedaction(Iterable<String> secrets) => _redactor.update(secrets);
  late final PtyOutputCoalescer _coalescer;
  Stopwatch? _firstOutputClock;

  // --- Persistência do scrollback (replay no próximo boot) --------------------
  // Grava a saída DECODIFICADA (após o `Utf8Decoder` em streaming → sem cortar
  // multibyte). Ring em memória: ao passar de `_kMaxRecordChars`, descarta ~25%
  // da frente de uma vez (trim amortizado). Só main-screen — enquanto em
  // alt-screen (TUI: vim/lazygit), a saída é efêmera e NÃO entra no registro.
  final TerminalScrollbackStore? _scrollback;
  late final BoundedTextBuffer _record0 = BoundedTextBuffer(
    maxLength: _kMaxRecordChars,
  );
  int _altDepth = 0;
  late final QuietPeriodDebouncer _saveDebounce = QuietPeriodDebouncer(
    delay: const Duration(seconds: 1),
    onQuiet: () => unawaited(_flush()),
  );
  Timer? _startupTimer;
  final List<Timer> _harnessKickTimers = <Timer>[];
  DateTime? _lastHarnessKickAt;

  /// ~2.5 MB ≈ 10000 linhas (casa com `maxLines`). Acima disso, corta a frente.
  static const int _kMaxRecordChars = 2500000;
  static final RegExp _altScreenSeq = RegExp(r'\x1b\[\?(1049|1047|47)([hl])');

  /// OSC 7 (`ESC ] 7 ; file://host/path BEL|ST`) — o shell reporta o cwd a cada
  /// prompt. Captura o path (grupo 1) até o terminador (BEL `\x07` ou ST `\x1b\`).
  static final RegExp _osc7 = RegExp(
    r'\x1b\]7;file://[^/]*(/[^\x07\x1b]*)(?:\x07|\x1b\\)',
  );

  /// Diretório atual do shell, rastreado por OSC 7. `null` até o 1º prompt (ou
  /// se o shell não emitir OSC 7). A VM persiste isso pra restaurar o cwd.
  String? _cwd;
  String? get currentDirectory => _cwd;
  String _title;
  late final CockpitTerminalController terminal;
  StreamSubscription<String>? _sub;

  @override
  String get title => _title;

  void rename(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == _title) return;
    _title = trimmed;
    notifyListeners();
  }

  /// Insere [text] diretamente no PTY como se o usuário tivesse digitado/colado
  /// (ex.: caminho de arquivo arrastado até o terminal).
  void insertText(String text) => _gateway.write(utf8.encode(text));

  /// Envia bytes CRUS ao PTY (sequências de controle: ESC, setas, F-keys,
  /// Ctrl+C...). Usado pela barra de teclas do mobile — plano 60, Wave F.
  void sendKeys(List<int> bytes) => _gateway.write(bytes);

  /// Copia a seleção do terminal pro clipboard. No-op sem seleção.
  ///
  /// Existe para o botão de copiar da barra de teclas do mobile: lá não há
  /// atalho de teclado nem menu de contexto, então o único caminho é este.
  /// Usa o mesmo `Pasteboard` do paste (e não o `Clipboard` do Flutter) pra a
  /// aba ficar com um clipboard só, coerente nos dois sentidos.
  void copySelection() {
    final text = terminal.selectedText();
    if (text.isEmpty) return;
    Pasteboard.writeText(text);
  }

  final TerminalAttachmentService? attachmentService;
  final String attachmentProjectRoot;
  final bool attachmentsRemote;
  TerminalAttachmentFeedback? attachmentFeedback;
  Future<void> _attachmentQueue = Future<void>.value();

  void clearAttachmentFeedback() {
    if (_disposed) return;
    attachmentFeedback = null;
    notifyListeners();
  }

  void _reportAttachment(TerminalAttachmentFeedback feedback) {
    if (_disposed) return;
    attachmentFeedback = feedback;
    if (kDebugMode && feedback.notice != TerminalAttachmentNotice.importing) {
      DiagnosticsLog.instance.log(
        'terminal-attachments',
        'tab=$id engine=${terminal.engine.name} result=${feedback.notice.name}',
      );
    }
    notifyListeners();
  }

  /// Capture the target now, never look up the active terminal after an await.
  Future<void> _enqueueAttachment(
    Future<TerminalClipboardContent> Function() read,
  ) {
    final service = attachmentService;
    if (_disposed || service == null) return Future<void>.value();
    final target = TerminalAttachmentTarget(
      // The system workspace has no project path. Keep its imports in the
      // terminal's own spawn directory, captured with the target at the gesture.
      projectRoot: attachmentProjectRoot.isNotEmpty
          ? attachmentProjectRoot
          : (_gateway.spawnDirectory?.path ?? workingDirectory),
      profile: profile,
      remote: attachmentsRemote,
      isWindows: defaultTargetPlatform == TargetPlatform.windows,
      harness: activeHarness,
    );
    // Start the clipboard read at the gesture, before waiting for earlier copies.
    final content = read().then<(TerminalClipboardContent?, Object?)>(
      (value) => (value, null),
      onError: (Object error) => (null, error),
    );
    _attachmentQueue = _attachmentQueue.then((_) async {
      if (_disposed) return;
      try {
        final (snapshot, error) = await content;
        if (_disposed) return;
        if (error != null) throw error;
        if (kDebugMode) {
          DiagnosticsLog.instance.log(
            'terminal-attachments',
            'tab=$id engine=${terminal.engine.name} profile=${profile.id} '
                'harness=${target.harness?.name ?? "none"} remote=${target.remote} '
                'files=${snapshot!.files.length} imageBytes=${snapshot.image?.length ?? 0} '
                'textLength=${snapshot.text?.length ?? 0}',
          );
        }
        await service.deliver(
          content: snapshot!,
          target: target,
          isAlive: () => !_disposed,
          nativeTargetIsCurrent: () => activeHarness == target.harness,
          paste: (text) {
            if (!_disposed) terminal.paste(text);
          },
          sendKeys: (keys) {
            if (!_disposed) _gateway.write(keys);
          },
          feedback: _reportAttachment,
        );
      } catch (error) {
        _reportAttachment(
          TerminalAttachmentFeedback(
            TerminalAttachmentNotice.failed,
            detail: '$error',
          ),
        );
      }
    });
    return _attachmentQueue;
  }

  Future<void> pasteFromClipboard() =>
      _enqueueAttachment(() => attachmentService!.clipboard.read());

  Future<void> importDroppedPaths(List<String> paths) => _enqueueAttachment(
    () async => TerminalClipboardContent(files: List.unmodifiable(paths)),
  );

  /// Acumula a saída no registro de scrollback, rastreando alt-screen (não grava
  /// estado de TUI) e limitando o tamanho. Agenda o flush em disco (~1s).
  void _record(String data) {
    if (_scrollback == null) return;

    // Atualiza a profundidade de alt-screen a partir das sequências no chunk.
    // Faz isso ANTES de decidir gravar: se o chunk entra em alt-screen no meio,
    // o prefixo (main-screen) ainda é scrollback legítimo, mas pra simplicidade
    // e robustez gravamos o chunk inteiro só quando começa e termina em
    // main-screen — o `\x1bc` no replay cobre qualquer resíduo.
    final wasMain = _altDepth == 0;
    for (final m in _altScreenSeq.allMatches(data)) {
      if (m.group(2) == 'h') {
        _altDepth++;
      } else if (_altDepth > 0) {
        _altDepth--;
      }
    }
    // tocou alt-screen → descarta chunk.
    if (!wasMain || _altDepth != 0) return;

    _record0.add(data);
    _saveDebounce.trigger();
  }

  /// Pede ao monitor uma reavaliação imediata do harness. Com [burst], agenda
  /// retries curtos para cobrir a corrida entre submit e o filho aparecer em
  /// `/proc` (fork+exec ainda em andamento no 1º poll).
  void _kickHarnessMonitor({bool burst = false}) {
    final monitor = _monitor;
    if (monitor == null) return;

    final now = DateTime.now();
    final last = _lastHarnessKickAt;
    if (!burst &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 40)) {
      return;
    }
    _lastHarnessKickAt = now;
    monitor.requestPoll(sessionId: id, urgent: burst);

    if (!burst) return;
    for (final t in _harnessKickTimers) {
      t.cancel();
    }
    _harnessKickTimers
      ..clear()
      ..addAll([
        for (final delay in const [
          Duration(milliseconds: 40),
          Duration(milliseconds: 120),
          Duration(milliseconds: 280),
        ])
          Timer(delay, () => monitor.requestPoll(sessionId: id, urgent: true)),
      ]);
  }

  /// Atualiza apenas a prioridade de observação do harness. O PTY e os
  /// processos nunca são pausados quando a aba/workspace fica oculto.
  void setVisible(bool visible) {
    _coalescer.visible = visible;
    _monitor?.setSessionVisible(id, visible);
  }

  /// Atualiza [_cwd] a partir de OSC 7 no chunk. Pega a ÚLTIMA ocorrência (o
  /// prompt mais recente). Notifica a VM quando muda → persiste no layout.
  void _trackCwd(String data) {
    String? path;
    for (final m in _osc7.allMatches(data)) {
      path = m.group(1);
    }
    if (path == null) return;
    final decoded = Uri.decodeFull(path);
    if (decoded == _cwd) return;
    _cwd = decoded;
    onCwdChanged?.call();
  }

  /// Scrollback gravado até agora (main-screen apenas), no mesmo formato que
  /// vai pro store. O reinício da aba usa como `replay` da sessão nova sem
  /// esperar o flush em disco.
  String get scrollbackSnapshot => _record0.toString();

  Future<void> _flush() async {
    final store = _scrollback;
    if (store == null) return;
    await store.save(
      projectId: projectId,
      sessionId: id,
      contents: _record0.toString(),
    );
  }

  Future<void>? _stopProcess;

  /// Stop without disposing the controller while its view is mounted. The
  /// owning app can abort closing on failure and safely retry later.
  Future<void> stopProcess() {
    final pending = _stopProcess;
    if (pending != null) return pending;
    late final Future<void> operation;
    operation = Future<void>.sync(_gateway.kill).catchError((
      Object e,
      StackTrace st,
    ) {
      if (identical(_stopProcess, operation)) _stopProcess = null;
      Error.throwWithStackTrace(e, st);
    });
    _stopProcess = operation;
    return operation;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _monitor?.unregisterSession(id);
    _notifyDebounce?.cancel();
    _saveDebounce.dispose();
    _startupTimer?.cancel();
    for (final t in _harnessKickTimers) {
      t.cancel();
    }
    _harnessKickTimers.clear();
    unawaited(
      _flush(),
    ); // best-effort: persiste o estado final (inclui app-quit).
    await _sub?.cancel();
    _coalescer.dispose();
    await stopProcess();
    terminal.dispose();
    super.dispose();
  }
}
