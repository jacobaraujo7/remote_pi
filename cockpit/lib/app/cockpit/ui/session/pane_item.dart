import 'package:flutter/foundation.dart';
import '../../domain/entities/terminal_owner.dart';
export '../../domain/entities/terminal_owner.dart';

/// Base de uma aba do multiplexador — um agente (`AgentSession`) ou um terminal
/// (`TerminalSession`). A VM guarda todas as abas como [PaneItem]; a UI decide
/// como renderizar pelo tipo concreto.
abstract class PaneItem extends ChangeNotifier {
  String get id;
  String get projectId;

  /// Normal tabs remain workspace-owned unless explicitly created by an app.
  TerminalOwner get owner => const TerminalOwner.workspace();

  /// Título **dinâmico** da aba — derivado automaticamente (OSC-title do
  /// terminal, nome do agente, nome do arquivo). Segue vivo mesmo quando há
  /// rótulo manual; a UI só não o exibe nesse caso (ver [displayTitle]).
  String get title;
  String get workingDirectory;

  // --- Rótulo manual + trava de título ---------------------------------------
  // Um nome estável definido pelo usuário (duplo-clique na aba ou "Rename").
  // Enquanto setado, TRAVA o nome exibido: nada automático (OSC-title,
  // inferência por conteúdo) pode sobrescrevê-lo — ele vive num campo separado
  // do [title] dinâmico, que continua sendo atualizado por baixo. É a
  // identidade estável usada pela orquestração (`cockpit list-panes` → `label`).

  String? _manualLabel;

  /// Rótulo manual, ou `null` quando a aba usa o título automático.
  String? get manualLabel => _manualLabel;

  /// `true` quando há rótulo manual — o título dinâmico deixa de ser exibido.
  bool get titleLocked => _manualLabel != null;

  /// Nome exibido na aba e na CLI: o rótulo manual vence o título dinâmico.
  String get displayTitle => _manualLabel ?? title;

  /// Define o rótulo manual e ativa a trava. Vazio é ignorado.
  void setManualLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed == _manualLabel) return;
    _manualLabel = trimmed;
    notifyListeners();
  }

  /// Descarta o rótulo manual — a aba volta a seguir o título automático.
  void clearManualLabel() {
    if (_manualLabel == null) return;
    _manualLabel = null;
    notifyListeners();
  }

  /// Semeia o rótulo na restauração (Hive) **sem** notificar — a aba ainda não
  /// está montada. `null`/vazio limpa a trava.
  void restoreManualLabel(String? label) {
    final trimmed = label?.trim();
    _manualLabel = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// `true` enquanto a aba está processando trabalho (acende o spinner na aba).
  /// Default `false`; agentes e terminais sobrescrevem.
  bool get isWorking => false;

  /// Resultado novo não visto; default `false`. Agentes e terminais (com claude)
  /// sobrescrevem.
  bool get unseenFinish => false;

  /// Marca/limpa o badge de "resultado não visto". No-op por default.
  void markUnseen() {}
  void clearUnseen() {}
}
