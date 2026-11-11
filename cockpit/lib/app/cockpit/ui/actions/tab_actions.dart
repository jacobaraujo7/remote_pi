import 'dart:io' show Platform;

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

/// Fecha [item] pedindo confirmação quando há edição não salva ou um agente
/// rodando no terminal.
///
/// Regra única do fechamento de aba: o X do título, o menu de contexto e o
/// atalho ⌘W/Ctrl+W passam todos por aqui, para não divergirem — um caminho
/// que esquecesse o diálogo descartaria trabalho em silêncio.
///
/// Devolve `true` se a aba pode ser fechada (e [onClose] já foi chamado).
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
    final ok = await confirmCloseTerminal(
      context,
      item,
      settingsController: settingsController,
    );
    if (!ok || !context.mounted) return false;
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
      // Salva o buffer atual; só fecha se gravou (erro de IO mantém aberto).
      final ok = await item.saveDraft?.call() ?? false;
      if (!context.mounted || !ok) return false;
      onClose();
      return true;
  }
}

/// ⌘W / Ctrl+W: fecha a aba ativa da pane focada, com a mesma confirmação do
/// X do título.
///
/// No-op quando não há aba (o placeholder de pane vazia não é fechável): sem
/// isso o atalho apagaria a única pane e deixaria o workspace sem nada.
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
    final ok = await confirmCloseTerminal(
      context,
      owner.terminals.session(ownedTab),
    );
    if (!ok || !context.mounted) return;
    await owner.closeTerminal(ownedTab);
    return;
  }
  final target = vm.focusedTab();
  if (target == null) return;
  final (paneId, tabId, item) = target;
  await requestCloseTab(context, item, () => vm.closeTab(paneId, tabId));
}

/// Confirma o fechamento de [terminal]. Só pergunta quando há um agente
/// (claude, codex, pi) rodando na aba e a preferência está ligada: shell ocioso
/// fecha direto, sem diálogo. Devolve `false` se o usuário cancelou.
Future<bool> confirmCloseTerminal(
  BuildContext context,
  TerminalSession? terminal, {
  SettingsController? settingsController,
}) async {
  if (terminal?.activeHarness == null) return true;
  final settings = settingsController ?? context.read<SettingsController>();
  if (!settings.settings.confirmCloseTerminal) return true;
  final res = await showConfirmCloseTerminalDialog(context);
  if (!context.mounted || res == null || !res.confirmed) return false;
  if (res.doNotAskAgain) settings.setConfirmCloseTerminal(false);
  return true;
}

/// Atalhos locais do terminal para nova aba e fechamento de aba.
///
/// Definidos como `ownerShortcuts` no escopo do widget de terminal (flterm/xterm)
/// para que o motor intercepte as teclas e não envie bytes de controle ao PTY.
/// Ctrl+T / Ctrl+W só fora do macOS (lá o atalho do app é ⌘): no shell são o
/// transpose e o apagar-palavra do readline, e o Ctrl+W do vim/nano/less. Mesmo
/// precedente do Ctrl+F em `adaptive_terminal_pane.dart`.
Map<ShortcutActivator, VoidCallback> terminalOwnerShortcuts({
  required VoidCallback onNewTerminal,
  required VoidCallback onCloseTab,
  bool? isMacOS,
}) => <ShortcutActivator, VoidCallback>{
  const SingleActivator(LogicalKeyboardKey.keyT, meta: true): onNewTerminal,
  const SingleActivator(LogicalKeyboardKey.keyW, meta: true): onCloseTab,
  if (!(isMacOS ?? Platform.isMacOS)) ...{
    const SingleActivator(LogicalKeyboardKey.keyT, control: true):
        onNewTerminal,
    const SingleActivator(LogicalKeyboardKey.keyW, control: true): onCloseTab,
  },
};
