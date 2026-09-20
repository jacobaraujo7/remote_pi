import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/entities/sound_event.dart';
import 'package:cockpit/app/core/utils/platform_kind.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Avisos de fim de turno: badge na aba, notificação do SO e chime, com as
/// preferências que a `CockpitPage` empurra do `SettingsController` app-scoped.
///
/// Extraído do `CockpitViewModel`: o VM só diz *qual sessão* terminou e *qual
/// está em foco*; a matriz foco/janela/preferência mora aqui.
class SessionNotificationsController extends ChangeNotifier {
  SessionNotificationsController(this._notifier);

  final Notifier _notifier;

  // ---- contexto injetado pelo VM dono (mesma vida page-scoped) -------------

  /// Id da aba que o usuário está olhando (aba ativa da pane focada).
  String? Function()? focusedTabId;

  /// Nome do workspace de uma sessão (vai no corpo da notificação do SO).
  String Function(String projectId)? workspaceName;

  // ---- preferências (espelham AppSettings) ---------------------------------

  bool _enabled = true;
  Map<SoundEvent, bool> _events = const <SoundEvent, bool>{};
  Map<SoundEvent, String> _overrides = const <SoundEvent, String>{};
  Map<SoundEvent, bool> _onActiveTab = const <SoundEvent, bool>{};
  double _volume = 50;

  set notificationsEnabled(bool value) => _enabled = value;

  void setSoundPrefs({
    required Map<SoundEvent, bool> events,
    required Map<SoundEvent, String> overrides,
    required Map<SoundEvent, bool> onActiveTab,
    required double volume,
  }) {
    _events = events;
    _overrides = overrides;
    _onActiveTab = onActiveTab;
    _volume = volume;
  }

  bool _soundEnabledFor(SoundEvent event) => _events[event] ?? true;

  /// A janela do app está em foco? No mobile `window_manager` não vale
  /// (`isFocused()` retorna false), e o app só roda em foreground quando visível
  /// — foreground = focado (plano 60, Wave G).
  Future<bool> get _windowFocused async =>
      isMobilePlatform || await windowManager.isFocused();

  /// Badge (ponto na aba) → só se a sessão NÃO for a aba ativa.
  /// Notificação do SO → só se a janela não estiver focada.
  /// Separar as duas responsabilidades evita badge preso: se o usuário já está
  /// na aba, não há nada a marcar — ele verá a resposta ao olhar para a janela.
  ///
  /// Chega aqui tanto o fim de turno (`idle`) quanto o pedido de ação
  /// (`waiting`: permissão/pergunta/plano) — o `onTurnFinished` do terminal
  /// dispara nos dois. O status corrente da sessão decide qual [SoundEvent] é.
  Future<void> turnFinished(PaneItem s) async {
    final actionRequired =
        s is TerminalSession && s.status == TerminalStatus.waiting;
    final event = actionRequired
        ? SoundEvent.actionRequired
        : SoundEvent.turnDone;
    final isActiveTab = _markUnseenIfHidden(s);

    if (!await _windowFocused) {
      // Janela em outro app → notificação do SO (tem som próprio).
      if (!_enabled) return;
      final workspace = workspaceName?.call(s.projectId) ?? '';
      if (actionRequired) {
        await _notifier.agentNeedsAction(
          agentName: s.title,
          workspace: workspace,
        );
      } else {
        await _notifier.agentFinished(agentName: s.title, workspace: workspace);
      }
      return;
    }
    // Janela focada → som curto pra chamar atenção. Nunca junto da notificação
    // → não se confunde com o som dela. Aba ativa não toca por padrão (o
    // usuário está olhando a resposta/prompt), a menos que ele tenha ligado
    // "tocar mesmo na aba ativa" pro evento.
    if (isActiveTab && !(_onActiveTab[event] ?? false)) return;
    await _play(event);
  }

  /// Marca a sessão como "não vista" se ela não é a aba ativa. Devolve `true`
  /// quando **é** a ativa (o chamador decide o som).
  bool _markUnseenIfHidden(PaneItem s) {
    final isActiveTab = s.id == focusedTabId?.call();
    if (!isActiveTab) {
      s.markUnseen();
      notifyListeners();
    }
    return isActiveTab;
  }

  Future<void> _play(SoundEvent event) async {
    if (!_soundEnabledFor(event)) return;
    await _notifier.play(event, customPath: _overrides[event], volume: _volume);
  }
}
