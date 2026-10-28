import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Ponte **reativa** entre o editor de arquivo focado e o menu **File**
/// (Save/Discard/Format). O `FileViewer` focado publica aqui suas capacidades
/// (o que dá pra fazer agora) + os callbacks; o menu lê o estado para
/// habilitar/desabilitar cada item e disparar a ação. É um `ChangeNotifier`
/// app-scoped (provido no `ModularApp.provide`): o `AppRoot`/topbar fazem
/// `context.watch` para reconstruir os menus quando o estado muda; o
/// `FileViewer` faz `context.read` para publicar.
///
/// **Um dono por vez** (a aba focada): [publish] carimba um [owner] e [clear] só
/// limpa se o dono ainda for aquele — evita corrida quando se troca de aba (a
/// aba nova publica antes de a antiga limpar, e o `clear` da antiga vira no-op).
class EditorMenuBridge extends ChangeNotifier {
  bool _canSave = false;
  bool _canDiscard = false;
  bool _canFormat = false;
  bool _canToggleWordWrap = false;
  VoidCallback? _onToggleWordWrap;
  VoidCallback? _onSave;
  VoidCallback? _onDiscard;
  VoidCallback? _onFormat;
  Object? _owner;
  bool _disposed = false;

  bool get canSave => _canSave;
  bool get canDiscard => _canDiscard;
  bool get canFormat => _canFormat;

  /// Só o editor de arquivos alterna a quebra de linha (View → Toggle Word
  /// Wrap); `.http`/`.dbq` publicam sem ela.
  bool get canToggleWordWrap => _canToggleWordWrap;

  void save() => _onSave?.call();
  void discard() => _onDiscard?.call();
  void format() => _onFormat?.call();
  void toggleWordWrap() => _onToggleWordWrap?.call();

  /// Editor focado publica seu estado. Callbacks são sempre atualizados; só
  /// notifica (→ menu reconstrói) quando alguma capacidade muda.
  void publish({
    required Object owner,
    required bool canSave,
    required bool canDiscard,
    required bool canFormat,
    required VoidCallback onSave,
    required VoidCallback onDiscard,
    required VoidCallback onFormat,
    VoidCallback? onToggleWordWrap,
  }) {
    if (_disposed) return;
    _owner = owner;
    _onSave = onSave;
    _onDiscard = onDiscard;
    _onFormat = onFormat;
    _onToggleWordWrap = onToggleWordWrap;
    final canToggleWordWrap = onToggleWordWrap != null;
    if (canSave == _canSave &&
        canDiscard == _canDiscard &&
        canFormat == _canFormat &&
        canToggleWordWrap == _canToggleWordWrap) {
      return;
    }
    _canSave = canSave;
    _canDiscard = canDiscard;
    _canFormat = canFormat;
    _canToggleWordWrap = canToggleWordWrap;
    notifyListeners();
  }

  /// Nenhum editor ativo/focado. Só limpa se [owner] ainda for o dono.
  void clear(Object owner) {
    if (_disposed || _owner != owner) return;
    _owner = null;
    _onSave = _onDiscard = _onFormat = _onToggleWordWrap = null;
    if (!_canSave && !_canDiscard && !_canFormat && !_canToggleWordWrap) {
      return;
    }
    _canSave = _canDiscard = _canFormat = _canToggleWordWrap = false;
    // O clear típico vem do dispose() do FileViewer, no meio do finalizeTree
    // (árvore travada) — notificar síncrono aí crasha com "widget tree was
    // locked". Fora de idle, adia pro fim do frame.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _owner = null;
    _onSave = _onDiscard = _onFormat = _onToggleWordWrap = null;
    _canSave = _canDiscard = _canFormat = _canToggleWordWrap = false;
    super.dispose();
  }
}
