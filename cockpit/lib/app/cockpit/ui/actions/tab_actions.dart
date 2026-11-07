import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import '../session/orchestration_session.dart';
import 'package:cockpit/app/cockpit/ui/session/neovim_session.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cockpit/i18n/strings.g.dart';

SettingsController? _settingsController(BuildContext context) {
  try {
    return context.read<SettingsController>();
  } catch (_) {
    return null;
  }
}

/// Fecha [item] pedindo confirmacao quando ha edicao nao salva ou fechamento
/// de terminal com confirmacao habilitada.
///
/// Regra unica do fechamento de aba: o X do titulo, o menu de contexto e o
/// atalho ⌘W/Ctrl+W passam todos por aqui, para nao divergirem.
///
/// Devolve `true` se a aba pode ser fechada (e [onClose] ja foi chamado).
Future<bool> requestCloseTab(
  BuildContext context,
  PaneItem? item,
  VoidCallback onClose, {
  bool skipTerminalConfirmation = false,
  SettingsController? settingsController,
}) async {
  if (item is OrchestrationSession) {
    final file = item.filePresentation;
    if (file?.dirty == true) {
      final allowed = await requestCloseTab(context, file!.viewer, () {
        if (identical(item.filePresentation, file)) {
          item.closeFile(discard: true);
        }
      });
      if (!allowed || !context.mounted) return false;
    }
    final tr = context.t.orchestration;
    final confirmed = await showConfirmDialog(
      context,
      title: item.title,
      message: '${tr.closeTerminal}: ${item.terminals.sessions.length}',
      confirmLabel: tr.closeTerminal,
      danger: true,
    );
    if (!confirmed || !context.mounted) return false;
    final result = await item.prepareClose();
    if (result is Failure || !context.mounted) return false;
    onClose();
    return true;
  }
  if (item is NeovimSession) {
    final modified = await item.hasModifiedBuffers();
    if (!context.mounted) return false;
    if (modified case Success(value: true)) {
      final tr = context.t.cockpit.neovim;
      final confirmed = await showConfirmDialog(
        context,
        title: tr.unsavedTitle,
        message: tr.unsavedMessage,
        confirmLabel: tr.closeAnyway,
        danger: true,
      );
      if (!context.mounted || !confirmed) return false;
    }
    onClose();
    return true;
  }
  if (item is TerminalSession && !skipTerminalConfirmation) {
    final settings = settingsController ?? _settingsController(context);
    if (settings == null || settings.settings.confirmCloseTerminal) {
      final res = await showConfirmCloseTerminalDialog(context);
      if (!context.mounted || res == null || !res.confirmed) return false;
      if (res.doNotAskAgain) {
        settings?.setConfirmCloseTerminal(false);
      }
    }
    onClose();
    return true;
  }
  if (item is! FileViewerSession || !item.dirty) {
    onClose();
    return true;
  }
  final choice = await showCloseDirtyDialog(context, fileName: item.title);
  if (!context.mounted) return false;
  switch (choice) {
    case CloseDirtyChoice.cancel:
      return false;
    case CloseDirtyChoice.dontSave:
      onClose();
      return true;
    case CloseDirtyChoice.save:
      // Salva o buffer atual; so fecha se gravou (erro de IO mantem aberto).
      final ok = await item.saveDraft?.call() ?? false;
      if (!context.mounted || !ok) return false;
      onClose();
      return true;
  }
}

/// ⌘W / Ctrl+W: fecha a aba ativa da pane focada, com a mesma confirmacao do
/// X do titulo.
///
/// No-op quando nao ha aba (o placeholder de pane vazia nao e fechavel): sem
/// isso o atalho apagaria a unica pane e deixaria o workspace sem nada.
Future<void> closeActiveTab(BuildContext context) async {
  final vm = context.read<CockpitViewModel>();
  final owner = vm.activeOrchestration;
  final file = owner?.filePresentation;
  if (owner != null && file != null && owner.fileVisible) {
    await requestCloseTab(context, file.viewer, () {
      if (identical(owner.filePresentation, file)) {
        owner.closeFile(discard: true);
      }
    });
    return;
  }
  final ownedTab = owner?.terminals.keyboardTabId;
  if (owner != null && ownedTab != null) {
    final settings = _settingsController(context);
    if (settings == null || settings.settings.confirmCloseTerminal) {
      final res = await showConfirmCloseTerminalDialog(context);
      if (!context.mounted || res == null || !res.confirmed) return;
      if (res.doNotAskAgain) {
        settings?.setConfirmCloseTerminal(false);
      }
    }
    await owner.closeTerminal(ownedTab);
    return;
  }
  final target = vm.focusedTab();
  if (target == null) return;
  final (paneId, tabId, item) = target;
  await requestCloseTab(context, item, () => vm.closeTab(paneId, tabId));
}

/// Atalhos locais do terminal para nova aba e fechamento de aba.
///
/// Definidos como `ownerShortcuts` no escopo do widget de terminal (flterm/xterm)
/// para que o motor de terminal intercepte as teclas e nao envie bytes de controle
/// ao PTY (ex: Ctrl+T / 0x14 que gerava '^T' no prompt, ou Ctrl+W / 0x17).
Map<ShortcutActivator, VoidCallback> terminalOwnerShortcuts({
  required VoidCallback onNewTerminal,
  required VoidCallback onCloseTab,
}) => <ShortcutActivator, VoidCallback>{
  const SingleActivator(LogicalKeyboardKey.keyT, meta: true): onNewTerminal,
  const SingleActivator(LogicalKeyboardKey.keyT, control: true): onNewTerminal,
  const SingleActivator(LogicalKeyboardKey.keyW, meta: true): onCloseTab,
  const SingleActivator(LogicalKeyboardKey.keyW, control: true): onCloseTab,
  const SingleActivator(LogicalKeyboardKey.keyW, meta: true, shift: true):
      onCloseTab,
  const SingleActivator(LogicalKeyboardKey.keyW, control: true, shift: true):
      onCloseTab,
};

