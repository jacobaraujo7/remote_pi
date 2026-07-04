import 'package:flutter/foundation.dart';

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
  VoidCallback? _onSave;
  VoidCallback? _onDiscard;
  VoidCallback? _onFormat;
  Object? _owner;

  bool get canSave => _canSave;
  bool get canDiscard => _canDiscard;
  bool get canFormat => _canFormat;

  void save() => _onSave?.call();
  void discard() => _onDiscard?.call();
  void format() => _onFormat?.call();

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
  }) {
    _owner = owner;
    _onSave = onSave;
    _onDiscard = onDiscard;
    _onFormat = onFormat;
    if (canSave == _canSave &&
        canDiscard == _canDiscard &&
        canFormat == _canFormat) {
      return;
    }
    _canSave = canSave;
    _canDiscard = canDiscard;
    _canFormat = canFormat;
    notifyListeners();
  }

  /// Nenhum editor ativo/focado. Só limpa se [owner] ainda for o dono.
  void clear(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _onSave = _onDiscard = _onFormat = null;
    if (!_canSave && !_canDiscard && !_canFormat) return;
    _canSave = _canDiscard = _canFormat = false;
    notifyListeners();
  }
}
