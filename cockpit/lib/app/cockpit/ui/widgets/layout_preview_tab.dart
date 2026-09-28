import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/layout_preview_view.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// O viewer de `.ckp` **dentro do app**: liga o [LayoutPreviewView] ao
/// [CockpitViewModel] (destinos possíveis, confirmação, aplicação).
///
/// A janela de documento usa o mesmo viewer com outra ligação: lá não há
/// workspace nenhum, então o botão despacha para o app pelo socket e quem
/// resolve o destino é [promptApplyLayout], deste arquivo.
class LayoutPreviewTab extends StatelessWidget {
  const LayoutPreviewTab({super.key, required this.session});

  final FileViewerSession session;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<CockpitViewModel>();
    final tr = context.t.cockpit.layoutPreview;
    final view = session.view;
    final source = view is FileViewText ? view.text : '';

    final candidates = vm.layoutDestinations(session.path);
    // Ordem do botão: o workspace que contém o arquivo; nenhum → workspace
    // novo na pasta dele. Os outros destinos ficam no menu — nunca há destino
    // implícito.
    final actions = <LayoutApplyAction>[
      for (final p in candidates)
        LayoutApplyAction(
          label: tr.applyTo(workspace: p.name),
          onApply: () => unawaited(applyLayoutTo(context, p, session.path)),
        ),
      LayoutApplyAction(
        label: tr.applyNewWorkspace,
        onApply: () =>
            unawaited(applyLayoutToNewWorkspace(context, session.path)),
      ),
      for (final p in _otherWorkspaces(vm, candidates))
        LayoutApplyAction(
          label: tr.applyTo(workspace: p.name),
          onApply: () => unawaited(applyLayoutTo(context, p, session.path)),
        ),
    ];

    return LayoutPreviewView(
      path: session.path,
      source: source,
      hostOs: Platform.operatingSystem,
      primary: actions.first,
      alternatives: actions.sublist(1),
    );
  }

  /// Workspaces do realm ativo que não contêm o arquivo: aplicar um layout
  /// "de fora" é raro, mas é escolha legítima do usuário — só nunca é o
  /// default do botão.
  List<Project> _otherWorkspaces(CockpitViewModel vm, List<Project> shown) {
    final ids = shown.map((p) => p.id).toSet();
    return vm.rootProjects
        .where((p) => !ids.contains(p.id) && !p.isPathless)
        .toList();
  }
}

/// Aplica [ckpPath] em [target], confirmando antes quando há aba aberta.
///
/// Aplicar é destrutivo: fecha **todas** as abas do destino. Diferente do
/// "Open layout" da Files pane, aqui o destino pode ser um workspace que não
/// está na frente — a pessoa não vê o que vai fechar. Por isso a confirmação
/// nomeia o workspace e vale sempre que houver aba aberta, não só quando há
/// processo vivo.
Future<void> applyLayoutTo(
  BuildContext context,
  Project target,
  String ckpPath,
) async {
  final vm = context.read<CockpitViewModel>();
  final tr = context.t.cockpit.layoutPreview;
  final impact = vm.layoutReplaceImpactOf(target.id);
  if (impact.tabs > 0) {
    final ok = await showConfirmDialog(
      context,
      title: tr.replaceTitle(workspace: target.name),
      message: tr.replaceMessage(n: impact.tabs),
      confirmLabel: tr.replaceConfirm,
      danger: true,
    );
    if (!ok || !context.mounted) return;
  }
  final res = await vm.applyLayoutFileTo(target.id, ckpPath);
  if (!context.mounted) return;
  await _reportFailure(context, res);
}

/// Abre um workspace novo na pasta do arquivo e aplica ali. Workspace novo
/// nasce vazio: não há aba de ninguém para fechar, nada a confirmar.
Future<void> applyLayoutToNewWorkspace(
  BuildContext context,
  String ckpPath,
) async {
  final vm = context.read<CockpitViewModel>();
  final res = await vm.openWorkspaceAndApplyLayout(ckpPath);
  if (!context.mounted) return;
  await _reportFailure(context, res);
}

/// Resolve o destino e aplica — o caminho de quem clicou Apply **fora** da
/// janela principal (janela de documento). Um candidato: é ele. Nenhum:
/// workspace novo na pasta. Vários (workspaces aninhados, o mesmo path em
/// realms diferentes): pergunta, nunca chuta.
Future<void> promptApplyLayout(BuildContext context, String ckpPath) async {
  final vm = context.read<CockpitViewModel>();
  final candidates = vm.layoutDestinations(ckpPath);

  if (candidates.isEmpty) {
    await applyLayoutToNewWorkspace(context, ckpPath);
    return;
  }
  if (candidates.length == 1) {
    await applyLayoutTo(context, candidates.first, ckpPath);
    return;
  }

  final size = MediaQuery.sizeOf(context);
  final chosen = await showAppMenu<Project>(
    context,
    globalPosition: Offset(size.width / 2, size.height / 3),
    items: [for (final p in candidates) AppMenuItem(value: p, label: p.name)],
  );
  if (chosen == null || !context.mounted) return;
  await applyLayoutTo(context, chosen, ckpPath);
}

Future<void> _reportFailure(
  BuildContext context,
  Result<Object?, String> result,
) async {
  if (result case Failure(:final error)) {
    await showInfoDialog(
      context,
      title: context.t.cockpit.layoutPreview.applyFailedTitle,
      message: error,
    );
  }
}
