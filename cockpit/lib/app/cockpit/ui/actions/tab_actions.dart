import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/neovim_session.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cockpit/i18n/strings.g.dart';

/// Fecha [item] pedindo confirmação quando há edição não salva.
///
/// Regra única do fechamento de aba: o X do título, o menu de contexto e o
/// atalho ⌘W/Ctrl+W passam todos por aqui, para não divergirem — um caminho
/// que esquecesse o diálogo descartaria trabalho em silêncio.
///
/// Devolve `true` se a aba pode ser fechada (e [onClose] já foi chamado).
Future<bool> requestCloseTab(
  BuildContext context,
  PaneItem? item,
  VoidCallback onClose,
) async {
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
  final target = vm.focusedTab();
  if (target == null) return;
  final (paneId, tabId, item) = target;
  await requestCloseTab(context, item, () => vm.closeTab(paneId, tabId));
}
