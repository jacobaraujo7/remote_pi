import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/core/utils/path_utils.dart';

/// Decide em qual workspace o `cockpit open <path>` deve abrir o arquivo.
///
/// ## Por que não basta a aba emissora
///
/// O app usa o `COCKPIT_TAB_ID` do processo que chamou a CLI. Só que nem todo
/// agente roda os comandos no PTY da própria aba: o Codex sobe **um** daemon
/// (`codex app-server`) como filho da primeira instância e as demais apenas se
/// conectam a ele. Os comandos de todas as sessões herdam o ambiente desse
/// daemon, ou seja, o `COCKPIT_TAB_ID` da primeira aba. Resultado: um artefato
/// gerado no 10º workspace abria no 1º.
///
/// ## Regra
///
/// 1. Workspace da aba emissora contém o arquivo → ele (comportamento
///    histórico, inclusive a folha ao lado do terminal).
/// 2. Senão, o workspace local de caminho mais específico que contém o arquivo
///    (worktree aninhado vence o pai).
/// 3. Senão, a aba emissora (arquivo fora de qualquer workspace, ex.: `/tmp`).
///
/// Aba emissora remota fica sempre com ela: o caminho é do host, não do disco
/// local, e não dá para compará-lo com os workspaces locais.
String? resolveOpenTargetProject({
  required String path,
  required String? callerProjectId,
  required Iterable<Project> projects,
  required bool caseInsensitive,
}) {
  Project? byId(String? id) {
    if (id == null) return null;
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool contains(Project p) {
    if (p.kind != WorkspaceKind.project || p.path.isEmpty) return false;
    return caseInsensitive
        ? isUnderPath(path.toLowerCase(), p.path.toLowerCase())
        : isUnderPath(path, p.path);
  }

  final caller = byId(callerProjectId);
  if (caller != null && (caller.isRemoteTerminal || contains(caller))) {
    return caller.id;
  }

  Project? best;
  for (final p in projects) {
    if (!contains(p)) continue;
    if (best == null ||
        normalizePath(p.path).length > normalizePath(best.path).length) {
      best = p;
    }
  }
  return best?.id ?? callerProjectId;
}
