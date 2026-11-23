import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';

const _skipDirs = <String>{
  '.git',
  '.hg',
  '.svn',
  'bin',
  'obj',
  'node_modules',
  '.dart_tool',
  '.idea',
  'packages',
  'testresults',
};

/// Acha `.sln` e `.slnx` sem ler conteúdo. Profundidade e quantidade têm teto
/// pra a abertura do workspace não varrer a árvore inteira.
Future<List<DotnetSolutionRef>> detectDotnetSolutions(
  String root,
  Future<List<FileNode>> Function(String path) listChildren,
) async {
  if (root.isEmpty) return const [];
  final found = <DotnetSolutionRef>[];
  final pending = <(String, int)>[(root, 0)];
  final seen = <String>{};
  var listed = 0;

  while (pending.isNotEmpty && found.length < 32 && listed < 400) {
    final (dir, depth) = pending.removeAt(0);
    if (!seen.add(dir)) continue;
    listed++;
    List<FileNode> children;
    try {
      children = await listChildren(dir);
    } on Object {
      continue;
    }
    for (final node in children) {
      if (found.length >= 32) break;
      if (node.isDirectory) {
        if (depth >= 6) continue;
        if (_skipDirs.contains(node.name.toLowerCase())) continue;
        pending.add((node.path, depth + 1));
        continue;
      }
      final lower = node.name.toLowerCase();
      if (!lower.endsWith('.sln') && !lower.endsWith('.slnx')) continue;
      final dot = node.name.lastIndexOf('.');
      found.add(
        DotnetSolutionRef(
          path: node.path,
          name: dot <= 0 ? node.name : node.name.substring(0, dot),
          depth: depth,
        ),
      );
    }
  }

  found.sort((a, b) {
    final byDepth = a.depth.compareTo(b.depth);
    if (byDepth != 0) return byDepth;
    return a.path.compareTo(b.path);
  });
  return found;
}
