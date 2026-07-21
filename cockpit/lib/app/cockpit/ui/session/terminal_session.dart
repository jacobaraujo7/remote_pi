import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_scrollback_store.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
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
    required this.projectId,
    required this.workingDirectory,
    required TerminalGateway gateway,
    required this.profile,
    String? title,
    Map<String, String> spawnEnv = const <String, String>{},
    TerminalScrollbackStore? scrollbackStore,
    String? replay,
    String? startupCommand,
    TerminalEngine engine = TerminalEngine.xterm,
  }) : _gateway = gateway,
       _scrollback = scrollbackStore,
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
    _sub = _gateway.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((data) {
          _kitty.feed(data); // observa push/pop do kitty antes de renderizar.
          terminal.write(data);
          _record(data); // grava o scrollback pra replay no próximo boot.
          _trackCwd(data); // rastreia o cwd vivo (OSC 7) pra restaurar nele.
        });
    terminal.onOutput = (data) {
      final text = utf8.decode(data, allowMalformed: true);
      _maybeInterrupt(text);
      _gateway.write(data);
    };
    terminal.onResize = (columns, rows) => _gateway.resize(rows, columns);
    // Programas mudam o título da janela via OSC 0/2 (ex.: shell mostra o cwd,
    // `vim`/`ssh` mostram o arquivo/host). Refletimos isso no nome da aba.
    terminal.onTitleChanged = (osc) => rename(_shortTitle(osc));

    // Restauração de aba que rodava um harness (ex.: `claude --resume <sid>`):
    // digita o comando no shell novo. Espera o shell de login (`-l`, que lê
    // `.zprofile`/`.zshrc`) montar o prompt antes de enviar, senão a entrada se
    // perde no meio da init. O `\r` submete. NÃO entra no scrollback do replay
    // (o `_record` já roda; mas o comando é re-derivável, então tudo bem).
    if (startupCommand != null && startupCommand.isNotEmpty) {
      _startupTimer = Timer(const Duration(milliseconds: 600), () {
        _gateway.write(utf8.encode('$startupCommand\r'));
      });
    }
  }

  /// Disparado quando o turno entra em `idle` ou `waiting` (terminou ou precisa
  /// de aprovação). A VM usa pra notificar o workspace — espelha o `onTurnEnd`
  /// do [AgentSession].
  VoidCallback? onTurnFinished;

  /// Disparado quando o shell muda de diretório (capturado por OSC 7). A VM usa
  /// pra persistir o cwd vivo no layout — assim o restore sobe o shell onde o
  /// usuário parou, não no cwd inicial da aba.
  VoidCallback? onCwdChanged;

  TerminalStatus _status = TerminalStatus.idle;
  TerminalStatus get status => _status;

  /// `true` enquanto o harness está processando um turno (acende o spinner).
  @override
  bool get isWorking => _status == TerminalStatus.working;

  /// Perfil que subiu esta aba (login shell, PowerShell, `Ubuntu (WSL)`…).
  /// Guardado pra fatia 3 (dropdown do `+`) e pra restauração da aba no perfil
  /// em que ela nasceu.
  final TerminalProfile profile;

  /// Session-id e transcript do `claude` rodando nesta aba, capturados do OSC.
  /// Em memória nesta feature; servem à feature futura de persistir/retomar a
  /// sessão (`claude --resume <sid>`, ler o `.jsonl`).
  String? claudeSessionId;
  String? transcriptPath;

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

  /// Aplica um status reportado pelo `cockpit-hook` (via [TerminalStatusServer]).
  /// [sessionId]/[transcriptPath] são capturados pra futura persistência.
  /// [isTurnStart] = evento `UserPromptSubmit` (início de turno).
  void applyClaudeStatus({
    required TerminalStatus status,
    bool isTurnStart = false,
    String? sessionId,
    String? transcriptPath,
  }) {
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
  final KittyKeyboardTracker _kitty = KittyKeyboardTracker();

  // --- Persistência do scrollback (replay no próximo boot) --------------------
  // Grava a saída DECODIFICADA (após o `Utf8Decoder` em streaming → sem cortar
  // multibyte). Ring em memória: ao passar de `_kMaxRecordChars`, descarta ~25%
  // da frente de uma vez (trim amortizado). Só main-screen — enquanto em
  // alt-screen (TUI: vim/lazygit), a saída é efêmera e NÃO entra no registro.
  final TerminalScrollbackStore? _scrollback;
  final StringBuffer _record0 = StringBuffer();
  int _altDepth = 0;
  Timer? _saveDebounce;
  Timer? _startupTimer;

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

  /// Cola do clipboard no terminal, com suporte a **imagem**.
  ///
  /// Se há uma imagem no clipboard, manda o byte de Ctrl+V (`\x16`) pro harness
  /// em primeiro plano (claude/codex/pi) — todos eles, ao receber `\x16`, leem a
  /// imagem do clipboard e a anexam (claude mostra `[Image #1]`, o pi grava num
  /// `.png` temporário). Sem imagem, faz o paste de texto normal (respeitando o
  /// bracketed paste mode).
  ///
  /// Por que existe: o `TerminalView` só cola texto (via `Clipboard`, que não lê
  /// imagem) e, no macOS, o caminho de IME engole o Ctrl+V cru (vira `pageDown`),
  /// então o `\x16` nunca era gerado e a imagem nunca chegava ao harness.
  Future<void> pasteFromClipboard() async {
    final image = await Pasteboard.image;
    if (image != null && image.isNotEmpty) {
      _gateway.write(const [
        0x16,
      ]); // Ctrl+V: o harness lê a imagem do clipboard.
      return;
    }
    final text = await Pasteboard.text;
    if (text != null && text.isNotEmpty) terminal.paste(text);
  }

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

    _record0.write(data);
    if (_record0.length > _kMaxRecordChars) {
      final s = _record0.toString();
      _record0
        ..clear()
        ..write(s.substring(s.length - (_kMaxRecordChars * 3 ~/ 4)));
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), _flush);
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

  Future<void> _flush() async {
    final store = _scrollback;
    if (store == null) return;
    await store.save(
      projectId: projectId,
      sessionId: id,
      contents: _record0.toString(),
    );
  }

  @override
  Future<void> dispose() async {
    _notifyDebounce?.cancel();
    _saveDebounce?.cancel();
    _startupTimer?.cancel();
    unawaited(
      _flush(),
    ); // best-effort: persiste o estado final (inclui app-quit).
    await _sub?.cancel();
    await _gateway.kill();
    terminal.dispose();
    super.dispose();
  }
}
