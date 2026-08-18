import 'dart:async' show StreamController;

import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/remote_host.dart';
import 'package:cockpit/app/cockpit/ui/actions/workspace_actions.dart';
import 'package:cockpit/app/cockpit/ui/remote/add_remote_host_dialog.dart';
import 'package:cockpit/app/cockpit/ui/remote/remote_folder_picker.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/git_process_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/widgets.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/utils/platform_kind.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Fluxos de workspace **remoto** (plano 58): menu do "+", cadastro de host,
/// picker de pasta no host e o kebab do slot remoto (git ops, worktree, config).

CockpitViewModel _vm(BuildContext context) => context.read<CockpitViewModel>();

/// Nome exibido do workspace remoto [wsId]; cai no próprio id se sumiu da lista.
String _labelOf(CockpitViewModel vm, String wsId) {
  for (final p in vm.remoteWorkspaces) {
    if (p.id == wsId) return p.name;
  }
  return wsId;
}

Project? _remoteWorkspace(CockpitViewModel vm, String wsId) {
  for (final p in vm.remoteWorkspaces) {
    if (p.id == wsId) return p;
  }
  return null;
}

RemoteHost? _hostById(CockpitViewModel vm, String hostId) {
  for (final h in vm.remoteHosts.hosts) {
    if (h.id == hostId) return h;
  }
  return null;
}

/// Menu do "+" da rail: Local vs Remoto, ancorado no botão. No mobile não há
/// workspace local, então vai direto pro fluxo de host (plano 59).
Future<void> newWorkspaceMenu(
  BuildContext context,
  CockpitViewModel vm,
  BuildContext anchor,
) async {
  if (isMobilePlatform) {
    await newRemoteWorkspace(context, vm, anchor);
    return;
  }
  final tr = context.t.cockpit.remoteHost;
  final choice = await showAppMenu<String>(
    anchor,
    items: [
      AppMenuItem(
        value: 'local',
        label: tr.newLocal,
        icon: Icons.folder_outlined,
      ),
      AppMenuItem(
        value: 'remote',
        label: tr.newRemote,
        icon: Icons.cloud_outlined,
      ),
    ],
  );
  if (choice == null || !anchor.mounted || !context.mounted) return;
  if (choice == 'local') {
    await createWorkspace(context);
  } else {
    await newRemoteWorkspace(context, vm, anchor);
  }
}

/// "New remote workspace": escolhe (ou adiciona) o host → conecta → picker de
/// pasta remota → abre a pasta como workspace.
Future<void> newRemoteWorkspace(
  BuildContext context,
  CockpitViewModel vm,
  BuildContext anchor,
) async {
  final host = await _pickOrAddHost(context, vm, anchor);
  if (host == null || !context.mounted) return;
  await openRemoteFolder(context, vm, host.id);
}

/// Escolhe um host existente ou adiciona um novo. Sem hosts, vai direto pro
/// dialog de adicionar.
Future<RemoteHost?> _pickOrAddHost(
  BuildContext context,
  CockpitViewModel vm,
  BuildContext anchor,
) async {
  final hosts = vm.remoteHosts.hosts;
  if (hosts.isEmpty) return _addRemoteHost(context, vm);

  final tr = context.t.cockpit.remoteHost;
  final picked = await showAppMenu<String>(
    anchor,
    items: [
      for (final h in hosts)
        AppMenuItem(value: h.id, label: h.name, icon: Icons.cloud_outlined),
      const AppMenuItem<String>.divider(),
      AppMenuItem(value: '__new__', label: tr.newHostEntry, icon: Icons.add),
    ],
  );
  if (picked == null || !context.mounted) return null;
  if (picked == '__new__') return _addRemoteHost(context, vm);
  return _hostById(vm, picked);
}

/// Coleta user@host + nome, persiste e devolve o host criado (ou null).
Future<RemoteHost?> _addRemoteHost(
  BuildContext context,
  CockpitViewModel vm,
) async {
  final draft = await showAddRemoteHostDialog(context);
  if (draft == null) return null;
  await vm.addRemoteHost(
    name: draft.name,
    sshTarget: draft.sshTarget,
    port: draft.port,
    auth: draft.auth,
    password: draft.password,
  );
  for (final h in vm.remoteHosts.hosts) {
    if (h.sshTarget == draft.sshTarget) return h;
  }
  return null;
}

/// Conecta (SSH), navega o filesystem remoto e abre a pasta escolhida como
/// workspace. O picker abre IMEDIATAMENTE em loading e faz o túnel SSH + HOME
/// lá dentro (plano 60, Wave A) — em host lento não fica "nada acontecendo".
Future<void> openRemoteFolder(
  BuildContext context,
  CockpitViewModel vm,
  String hostId,
) async {
  final host = _hostById(vm, hostId);
  if (host == null) return;
  final path = await showRemoteFolderPicker(
    context,
    hostName: host.name,
    connect: () async {
      final service = await vm.remoteHosts.fileServiceFor(host);
      String initialPath;
      try {
        final home = await service.home();
        initialPath = home.isNotEmpty ? home : '/';
      } catch (_) {
        initialPath = '/';
      }
      return (service: service, initialPath: initialPath);
    },
  );
  if (path == null || !context.mounted) return;
  await vm.createRemoteWorkspace(hostId, path);
}

/// Menu de 3 pontinhos do workspace remoto (plano 58, Camada A): git ops via
/// `git.run` no host, worktree, renomear e fechar.
Future<void> handleRemoteWorkspaceAction(
  BuildContext context,
  String wsId,
  String action,
) async {
  final vm = _vm(context);
  // Move to realm: 'realm|<realmId>' (submenu), igual ao workspace local.
  if (action.startsWith('realm|')) {
    await vm.moveWorkspaceToRealm(wsId, action.substring('realm|'.length));
    return;
  }
  final label = _labelOf(vm, wsId);
  final page = context.t.cockpit.cockpitPage;
  switch (action) {
    case 'pull':
      await _runRemoteGitDialog(context, wsId, const [
        'pull',
      ], title: page.pullTitle(label: label));
    case 'push':
      await _runRemoteGitDialog(context, wsId, const [
        'push',
      ], title: page.pushTitle(label: label));
    case 'sync':
      // pull e, se OK, push — mesma semântica do sync local, num só dialog.
      await _runRemoteGitDialog(
        context,
        wsId,
        const ['pull'],
        then: const ['push'],
        title: page.syncTitle(label: label),
      );
    case 'worktree':
      await _createRemoteWorktreeFlow(context, wsId);
    case 'config':
      await _configureRemoteWorkspace(context, wsId);
    case 'close':
      await vm.removeRemoteWorkspace(wsId);
  }
}

/// "Create worktree" de um workspace remoto: mesmo dialog do local, mas o
/// `git worktree add` roda no host.
Future<void> _createRemoteWorktreeFlow(
  BuildContext context,
  String wsId,
) async {
  final vm = _vm(context);
  final namespace = await vm.remoteWorktreeNamespace(wsId);
  final label = _labelOf(vm, wsId);
  if (!context.mounted) return;
  await showWorktreeCreateDialog(
    context,
    rootName: label,
    namespace: namespace,
    hasPostCheckout: false,
    onCreate:
        (
          name, {
          baseRef,
          copyIgnored = false,
          copyUntracked = false,
          fetchRemote = true,
        }) => vm.createRemoteWorktree(wsId, name),
  );
}

/// Configurações do workspace remoto: mesmo dialog do local (nome + cor +
/// imagem de fundo), persistido no pin. `path` vai vazio porque é a pasta LOCAL
/// (usada só pelo picker de imagem, que roda no cliente); a pasta do host, e o
/// host em si, vão em `remote` para o dialog exibir de onde o workspace vem.
Future<void> _configureRemoteWorkspace(
  BuildContext context,
  String wsId,
) async {
  final vm = _vm(context);
  final project = _remoteWorkspace(vm, wsId);
  if (project == null) return;
  final hostId = project.remoteHostId;
  final host = hostId == null ? null : _hostById(vm, hostId);
  final result = await showWorkspaceSettingsDialog(
    context,
    name: project.name,
    colorValue: project.colorValue,
    path: '',
    imagePath: project.imagePath,
    remote: host == null
        ? null
        // Nome do host + alvo ssh: o nome é como o usuário o chama, o alvo é
        // o endereço real (dois hosts podem ter apelidos parecidos).
        : (
            host: '${host.name}  (${host.sshTarget})',
            path: project.remotePath ?? '',
          ),
  );
  if (result == null) return;
  await vm.updateRemoteWorkspace(
    wsId,
    name: result.name,
    colorValue: result.colorValue,
    imagePath: result.imagePath,
  );
}

/// Roda `git <args>` (e opcionalmente `git <then>` se o 1º passar) no host do
/// workspace remoto [wsId], mostrando o dialog de processo. Como o `git.run`
/// remoto não é streaming, emite a saída de cada passo de uma vez.
Future<void> _runRemoteGitDialog(
  BuildContext context,
  String wsId,
  List<String> args, {
  List<String>? then,
  required String title,
}) async {
  final vm = _vm(context);
  final controller = StreamController<String>();
  final success = () async {
    try {
      final first = await vm.remoteGitRun(wsId, args);
      if (first.stdout.isNotEmpty) controller.add(first.stdout);
      if (first.stderr.isNotEmpty) controller.add(first.stderr);
      if (first.code != 0 || then == null) return first.code == 0;
      final second = await vm.remoteGitRun(wsId, then);
      if (second.stdout.isNotEmpty) controller.add(second.stdout);
      if (second.stderr.isNotEmpty) controller.add(second.stderr);
      return second.code == 0;
    } catch (e) {
      controller.add('$e');
      return false;
    } finally {
      await controller.close();
    }
  }();
  await showGitProcessDialog(
    context,
    title: title,
    output: controller.stream,
    success: success,
  );
  await vm.refreshActiveRemoteGit();
}
