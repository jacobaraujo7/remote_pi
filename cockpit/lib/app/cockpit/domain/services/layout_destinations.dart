import 'package:cockpit/app/cockpit/domain/entities/project.dart';

/// Onde um `.ckp` aberto **de fora** (Files pane, Finder, Explorer) pode ser
/// aplicado (card do viewer de layout).
///
/// Um layout não diz em que workspace entra, e aplicar fecha as abas do
/// destino: o alvo não pode ser chutado. A regra é a pasta do arquivo, que é
/// também a âncora dos `cwd` do layout:
///
/// 1. o arquivo está dentro de **exatamente um** workspace aberto → é ele;
/// 2. está dentro de mais de um (workspaces aninhados, o mesmo path em realms
///    diferentes, uma worktree dentro do repo) → a UI pergunta;
/// 3. não está em nenhum → abrir um workspace novo na pasta do arquivo.
///
/// Workspaces sem pasta local (o "Cockpit" sintético e os remotos) ficam de
/// fora: o `.ckp` é um caminho do disco desta máquina.
List<Project> layoutDestinationsFor(String ckpPath, List<Project> projects) {
  final file = _normalize(ckpPath);
  final matches = projects
      .where((p) => !p.isPathless && p.path.isNotEmpty)
      .where((p) => _contains(_normalize(p.path), file))
      .toList();
  // Mais específico primeiro: uma worktree (ou um workspace aninhado) ganha do
  // repositório que a contém, que é o que a pessoa espera ao clicar num .ckp
  // de dentro dela.
  matches.sort((a, b) => b.path.length.compareTo(a.path.length));
  return List<Project>.unmodifiable(matches);
}

/// `true` se [file] está dentro da pasta [dir] (ou é ela).
bool _contains(String dir, String file) =>
    file == dir || file.startsWith(dir.endsWith('/') ? dir : '$dir/');

String _normalize(String path) {
  final unified = path.replaceAll(r'\', '/');
  if (unified.length > 1 && unified.endsWith('/')) {
    return unified.substring(0, unified.length - 1);
  }
  return unified;
}
