import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/ui/widgets/git_process_dialog.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/widgets.dart';
import 'package:cockpit/app/core/utils/native_folder_picker.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Fluxos de workspace do shell (criar, configurar, fechar, git ops, realms).
///
/// Moram fora da `CockpitPage` porque não são apresentação: são orquestração de
/// dialog + ViewModel. Recebem o `BuildContext` da página — logo `context.read`
/// alcança os ViewModels page-scoped e `context.mounted` é o mesmo guard que o
/// `mounted` do `State` (ver a regra de context assíncrono no CLAUDE.md).

CockpitViewModel _vm(BuildContext context) => context.read<CockpitViewModel>();

/// Garante um projeto selecionado (pede uma pasta se não houver). Retorna
/// `true` se há projeto pronto para uso.
Future<bool> ensureProject(BuildContext context) async {
  if (_vm(context).selectedProject != null) return true;
  return addProject(context);
}

Future<bool> addProject(BuildContext context) async {
  final vm = _vm(context);
  final path = await NativeFolderPicker.pick(
    dialogTitle: context.t.cockpit.cockpitPage.chooseProjectFolderDialogTitle,
    initialDirectory: vm.selectedProject?.path,
  );
  if (path == null) return false;
  await vm.addProject(path);
  return true;
}

/// Fluxo "Criar Workspace": escolhe a pasta, abre o dialog de configurações
/// (nome pré-preenchido com o da pasta + cor sugerida, ambos editáveis) e cria.
Future<bool> createWorkspace(BuildContext context) async {
  final vm = _vm(context);
  final path = await NativeFolderPicker.pick(
    dialogTitle: context.t.cockpit.cockpitPage.chooseWorkspaceFolderDialogTitle,
    initialDirectory: vm.selectedProject?.path,
  );
  if (path == null || !context.mounted) return false;
  final suggestedName = path.split('/').where((p) => p.isNotEmpty).lastOrNull;
  final suggestedColor =
      kWorkspacePalette[vm.rootProjects.length % kWorkspacePalette.length];
  final result = await showWorkspaceSettingsDialog(
    context,
    name: suggestedName ?? path,
    colorValue: suggestedColor,
    path: path,
  );
  if (result == null) return false;
  await vm.addProject(
    path,
    name: result.name,
    colorValue: result.colorValue,
    imagePath: result.imagePath,
  );
  return true;
}

/// "Configurações" do workspace: editar nome + cor do avatar.
Future<void> configureProject(BuildContext context, Project project) async {
  final vm = _vm(context);
  final result = await showWorkspaceSettingsDialog(
    context,
    name: project.name,
    colorValue: project.colorValue,
    path: project.path,
    imagePath: project.imagePath,
  );
  if (result == null) return;
  await vm.updateProject(
    project.id,
    name: result.name,
    colorValue: result.colorValue,
    imagePath: result.imagePath,
  );
  if (!context.mounted || result.name == project.name) return;
  await showInfoDialog(
    context,
    title: context.t.cockpit.cockpitPage.workspaceRenamedTitle,
    message: context.t.cockpit.cockpitPage.workspaceRenamedMessage(
      name: result.name,
    ),
  );
}

/// "Fechar" o workspace (confirma → remove da lista local + encerra agentes).
/// **Não deleta** a pasta no disco — só sai do cockpit.
Future<void> deleteProject(BuildContext context, Project project) async {
  final vm = _vm(context);
  final ok = await showConfirmDialog(
    context,
    title: context.t.cockpit.cockpitPage.closeWorkspaceTitle,
    message: context.t.cockpit.cockpitPage.closeWorkspaceMessage(
      name: project.name,
    ),
    confirmLabel: context.t.cockpit.cockpitPage.closeAction,
    danger: true,
  );
  if (!ok) return;
  await vm.removeProject(project.id);
}

/// Rótulo da operação git: nome do workspace em single-root; basename da root
/// em multi-root (a root já veio escolhida do submenu do kebab).
String gitOpLabel(Project project, String rootPath) =>
    rootPath == project.path ? project.name : rootPath.split('/').last;

/// Sync (pull → push) do workspace, com o processo ao vivo num dialog.
Future<void> syncProject(
  BuildContext context,
  Project project,
  String rootPath,
) => _gitOpDialog(
  context,
  project,
  rootPath,
  run: (vm) => vm.gitSync(rootPath),
  title: (label) => context.t.cockpit.cockpitPage.syncTitle(label: label),
);

Future<void> pullProject(
  BuildContext context,
  Project project,
  String rootPath,
) => _gitOpDialog(
  context,
  project,
  rootPath,
  run: (vm) => vm.gitPull(rootPath),
  title: (label) => context.t.cockpit.cockpitPage.pullTitle(label: label),
);

Future<void> pushProject(
  BuildContext context,
  Project project,
  String rootPath,
) => _gitOpDialog(
  context,
  project,
  rootPath,
  run: (vm) => vm.gitPush(rootPath),
  title: (label) => context.t.cockpit.cockpitPage.pushTitle(label: label),
);

/// Forma comum de sync/pull/push: roda o comando, mostra a saída ao vivo e
/// re-lê o estado git do workspace no fim.
Future<void> _gitOpDialog(
  BuildContext context,
  Project project,
  String rootPath, {
  required GitRun Function(CockpitViewModel vm) run,
  required String Function(String label) title,
}) async {
  final vm = _vm(context);
  final process = run(vm);
  await showGitProcessDialog(
    context,
    title: title(gitOpLabel(project, rootPath)),
    output: process.output,
    success: process.exitCode.then((c) => c == 0),
  );
  await vm.refreshGitProject(project.id);
}

/// "New realm…" do dropdown do footer: pede o nome e já troca pro realm novo
/// (nasce vazio — o rail mostra o estado vazio pra adicionar workspaces).
Future<void> createRealm(BuildContext context) async {
  final vm = _vm(context);
  final name = await showRealmNameDialog(
    context,
    title: context.t.cockpit.cockpitPage.newRealmTitle,
    confirmLabel: context.t.common.create,
    takenNames: vm.realms.map((r) => r.name).toSet(),
  );
  if (name == null || !context.mounted) return;
  final realm = await vm.createRealm(name);
  await vm.switchRealm(realm.id);
}

Future<void> manageRealms(BuildContext context) =>
    showRealmManagerDialog(context, vm: _vm(context));

/// Destinos de "Move to realm" do kebab: todos os realms menos o atual do
/// workspace; destino que já tem o mesmo path vem desabilitado. Com um realm
/// só, lista vazia → item nem aparece.
List<RealmTarget> moveTargets(CockpitViewModel vm, String projectId) {
  if (vm.realms.length < 2) return const [];
  final matches = vm.projects.where((p) => p.id == projectId);
  if (matches.isEmpty) return const [];
  final project = matches.first;
  return [
    for (final realm in vm.realms)
      if (realm.id != project.realmId)
        (
          id: realm.id,
          name: realm.name,
          enabled: !vm.pathExistsInRealm(project.path, realm.id),
        ),
  ];
}
