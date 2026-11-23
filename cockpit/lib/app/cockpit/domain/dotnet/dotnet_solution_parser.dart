import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution.dart';
import 'package:xml/xml.dart';

const _solutionFolderGuid = '2150E333-8FDC-42A3-9474-1A3956D46DE8';

final _projectLine = RegExp(
  r'Project\("\{([0-9A-Fa-f-]+)\}"\)\s*=\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*"\{([0-9A-Fa-f-]+)\}"',
);

final _nestedLine = RegExp(r'\{([0-9A-Fa-f-]+)\}\s*=\s*\{([0-9A-Fa-f-]+)\}');

/// Lê solução e projetos a partir do texto. XML inválido não estoura: a
/// solução volta `null` e um projeto ilegível continua na árvore, vazio.
class DotnetSolutionParser {
  const DotnetSolutionParser();

  List<String> projectFiles({
    required String solutionPath,
    required String solutionText,
  }) {
    final lower = solutionPath.toLowerCase();
    if (lower.endsWith('.slnx')) {
      return _slnxProjectFiles(solutionPath, solutionText);
    }
    return _slnProjectFiles(solutionPath, solutionText);
  }

  DotnetSolutionSnapshot? parse({
    required String solutionPath,
    required String solutionText,
    required Map<String, String> projectTexts,
  }) {
    final lower = solutionPath.toLowerCase();
    if (lower.endsWith('.slnx')) {
      return _parseSlnx(solutionPath, solutionText, projectTexts);
    }
    if (lower.endsWith('.sln')) {
      return _parseSln(solutionPath, solutionText, projectTexts);
    }
    return null;
  }
}

class _Entry {
  _Entry({
    required this.guid,
    required this.type,
    required this.name,
    required this.path,
    required this.items,
  });

  final String guid;
  final String type;
  final String name;
  final String path;
  final List<String> items;

  bool get isFolder => type.toUpperCase() == _solutionFolderGuid;
}

List<String> _slnProjectFiles(String solutionPath, String text) {
  return [
    for (final entry in _slnEntries(text))
      if (!entry.isFolder && entry.path.isNotEmpty)
        resolveAgainst(solutionPath, entry.path),
  ];
}

List<String> _slnxProjectFiles(String solutionPath, String text) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(_stripBom(text));
  } on XmlException {
    return const [];
  }
  if (doc.rootElement.name.local != 'Solution') return const [];
  final paths = <String>[];
  void walk(XmlElement element) {
    for (final child in element.childElements) {
      if (child.name.local == 'Project') {
        final path = child.getAttribute('Path');
        if (path != null && path.isNotEmpty) {
          paths.add(resolveAgainst(solutionPath, path));
        }
      } else if (child.name.local == 'Folder') {
        walk(child);
      }
    }
  }

  walk(doc.rootElement);
  return paths;
}

DotnetSolutionSnapshot? _parseSln(
  String solutionPath,
  String text,
  Map<String, String> projectTexts,
) {
  final cleaned = _stripBom(text);
  if (!_looksLikeSln(cleaned)) return null;
  final entries = _slnEntries(cleaned);
  final parents = _nestedParents(cleaned);
  final byGuid = <String, _Node>{};
  for (final entry in entries) {
    final absolute = entry.path.isEmpty
        ? null
        : resolveAgainst(solutionPath, entry.path);
    final node = entry.isFolder
        ? _folderNode(entry, solutionPath)
        : _projectNode(
            name: entry.name.isEmpty ? _basename(entry.path) : entry.name,
            projectPath: absolute ?? resolveAgainst(solutionPath, entry.path),
            text: absolute == null ? '' : projectTexts[absolute] ?? '',
          );
    byGuid[entry.guid.toUpperCase()] = node;
  }

  final root = _Node(
    id: 'sln:$solutionPath',
    kind: DotnetNodeKind.solution,
    name: _solutionName(solutionPath),
  );
  for (final entry in entries) {
    final node = byGuid[entry.guid.toUpperCase()];
    if (node == null) continue;
    final parentGuid = parents[entry.guid.toUpperCase()];
    final parent = parentGuid == null ? null : byGuid[parentGuid];
    (parent ?? root).children.add(node);
  }
  return DotnetSolutionSnapshot(
    path: solutionPath,
    name: root.name,
    fingerprint: '',
    projectPaths: _slnProjectFiles(solutionPath, cleaned),
    root: root.freeze(),
  );
}

bool _looksLikeSln(String text) {
  return text.contains('Microsoft Visual Studio Solution File') ||
      _projectLine.hasMatch(text);
}

List<_Entry> _slnEntries(String text) {
  final entries = <_Entry>[];
  final lines = text.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lines.length; i++) {
    final match = _projectLine.firstMatch(lines[i].trim());
    if (match == null) continue;
    final items = <String>[];
    var inItems = false;
    while (i + 1 < lines.length && lines[i + 1].trim() != 'EndProject') {
      i++;
      final line = lines[i].trim();
      if (line.startsWith('ProjectSection(SolutionItems)')) {
        inItems = true;
        continue;
      }
      if (line.startsWith('EndProjectSection')) {
        inItems = false;
        continue;
      }
      if (!inItems) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      items.add(line.substring(eq + 1).trim());
    }
    entries.add(
      _Entry(
        type: match.group(1)!,
        name: match.group(2)!,
        path: match.group(3)!,
        guid: match.group(4)!,
        items: items,
      ),
    );
  }
  return entries;
}

Map<String, String> _nestedParents(String text) {
  final parents = <String, String>{};
  var inside = false;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.startsWith('GlobalSection(NestedProjects)')) {
      inside = true;
      continue;
    }
    if (!inside) continue;
    if (line.startsWith('EndGlobalSection')) break;
    final match = _nestedLine.firstMatch(line);
    if (match == null) continue;
    parents[match.group(1)!.toUpperCase()] = match.group(2)!.toUpperCase();
  }
  return parents;
}

_Node _folderNode(_Entry entry, String solutionPath) {
  final node = _Node(
    id: 'folder:${entry.guid.toUpperCase()}',
    kind: DotnetNodeKind.solutionFolder,
    name: entry.name.isEmpty ? 'Folder' : entry.name,
  );
  for (final item in entry.items) {
    if (item.isEmpty) continue;
    final absolute = resolveAgainst(solutionPath, item);
    node.children.add(
      _Node(
        id: 'item:$absolute',
        kind: DotnetNodeKind.file,
        name: _basename(item),
        path: absolute,
      ),
    );
  }
  return node;
}

DotnetSolutionSnapshot? _parseSlnx(
  String solutionPath,
  String text,
  Map<String, String> projectTexts,
) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(_stripBom(text));
  } on XmlException {
    return null;
  }
  if (doc.rootElement.name.local != 'Solution') return null;
  final root = _Node(
    id: 'sln:$solutionPath',
    kind: DotnetNodeKind.solution,
    name: _solutionName(solutionPath),
  );
  _fillSlnx(doc.rootElement, root, solutionPath, projectTexts);
  return DotnetSolutionSnapshot(
    path: solutionPath,
    name: root.name,
    fingerprint: '',
    projectPaths: _slnxProjectFiles(solutionPath, text),
    root: root.freeze(),
  );
}

void _fillSlnx(
  XmlElement element,
  _Node parent,
  String solutionPath,
  Map<String, String> projectTexts,
) {
  for (final child in element.childElements) {
    final local = child.name.local;
    if (local == 'Folder') {
      final raw = child.getAttribute('Name') ?? 'Folder';
      final trimmed = raw
          .replaceAll('\\', '/')
          .replaceAll(RegExp(r'^/+|/+$'), '');
      final name = trimmed.isEmpty ? raw : trimmed.split('/').last;
      final folder = _Node(
        id: 'folder:${parent.id}/$name/${parent.children.length}',
        kind: DotnetNodeKind.solutionFolder,
        name: name,
      );
      parent.children.add(folder);
      _fillSlnx(child, folder, solutionPath, projectTexts);
    } else if (local == 'Project') {
      final relative = child.getAttribute('Path') ?? '';
      if (relative.isEmpty) continue;
      final absolute = resolveAgainst(solutionPath, relative);
      parent.children.add(
        _projectNode(
          name: _fileStem(_basename(relative)),
          projectPath: absolute,
          text: projectTexts[absolute] ?? '',
        ),
      );
    } else if (local == 'File') {
      final relative = child.getAttribute('Path') ?? '';
      if (relative.isEmpty) continue;
      final absolute = resolveAgainst(solutionPath, relative);
      parent.children.add(
        _Node(
          id: 'item:$absolute',
          kind: DotnetNodeKind.file,
          name: _basename(relative),
          path: absolute,
        ),
      );
    }
  }
}

_Node _projectNode({
  required String name,
  required String projectPath,
  required String text,
}) {
  final directory = _parentOf(projectPath);
  final node = _Node(
    id: 'proj:$projectPath',
    kind: DotnetNodeKind.project,
    name: name.isEmpty ? _fileStem(_basename(projectPath)) : name,
    path: projectPath,
    directory: directory,
  );
  _addExplicitItems(node, projectPath, directory, text);
  return node;
}

void _addExplicitItems(
  _Node project,
  String projectPath,
  String projectDir,
  String text,
) {
  if (text.trim().isEmpty) return;
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(_stripBom(text));
  } on XmlException {
    return;
  }
  if (doc.rootElement.name.local != 'Project') return;
  for (final name in ['Compile', 'Content', 'None']) {
    for (final element in doc.findAllElements(name)) {
      final include = element.getAttribute('Include');
      if (include == null || include.isEmpty) continue;
      if (include.contains('*')) continue;
      final absolute = resolveAgainst(projectPath, include);
      final link = element.getAttribute('Link') ?? _childText(element, 'Link');
      final inside =
          absolute == projectDir || absolute.startsWith('$projectDir/');
      if ((link == null || link.isEmpty) && inside) continue;
      final display = (link == null || link.isEmpty)
          ? _basename(absolute)
          : link;
      _addLinked(project, projectDir, display, absolute);
    }
  }
  for (final element in doc.findAllElements('Folder')) {
    final include = element.getAttribute('Include');
    if (include == null || include.isEmpty) continue;
    _addLinked(project, projectDir, include, null);
  }
}

void _addLinked(
  _Node project,
  String projectDir,
  String display,
  String? file,
) {
  final parts = display
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  if (parts.isEmpty) return;
  var siblings = project.children;
  final built = <String>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    final last = i == parts.length - 1;
    built.add(part);
    if (!last || file == null) {
      final existing = siblings
          .where(
            (node) =>
                node.kind == DotnetNodeKind.folder &&
                node.name.toLowerCase() == part.toLowerCase(),
          )
          .firstOrNull;
      if (existing != null) {
        siblings = existing.children;
        continue;
      }
      final relative = built.join('/');
      final folder = _Node(
        id: '${project.id}/link/$relative',
        kind: DotnetNodeKind.folder,
        name: part,
        directory: file == null || !last
            ? resolveAgainst('$projectDir/placeholder', relative)
            : null,
      );
      // Pasta virtual de um arquivo linkado de fora não aponta pro disco.
      if (file != null) folder.directory = null;
      siblings.add(folder);
      siblings = folder.children;
      continue;
    }
    siblings.add(
      _Node(
        id: '${project.id}/link/${built.join('/')}',
        kind: DotnetNodeKind.file,
        name: part,
        path: file,
      ),
    );
  }
}

String? _childText(XmlElement element, String name) {
  for (final child in element.childElements) {
    if (child.name.local == name) {
      final text = child.innerText.trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

class _Node {
  _Node({
    required this.id,
    required this.kind,
    required this.name,
    this.path,
    this.directory,
  });

  final String id;
  final DotnetNodeKind kind;
  final String name;
  final String? path;
  String? directory;
  final List<_Node> children = [];

  DotnetNode freeze() {
    final ordered = [...children]
      ..sort(
        (a, b) => compareSolutionNames(
          aIsFile: a.kind == DotnetNodeKind.file,
          aName: a.name,
          bIsFile: b.kind == DotnetNodeKind.file,
          bName: b.name,
        ),
      );
    final count =
        kind == DotnetNodeKind.solution || kind == DotnetNodeKind.solutionFolder
        ? _countProjects(this)
        : 0;
    return DotnetNode(
      id: id,
      kind: kind,
      name: name,
      path: path,
      directory: directory,
      projectCount: count,
      children: [for (final child in ordered) child.freeze()],
    );
  }
}

int _countProjects(_Node node) {
  var count = node.kind == DotnetNodeKind.project ? 1 : 0;
  for (final child in node.children) {
    count += _countProjects(child);
  }
  return count;
}

String _stripBom(String text) {
  if (text.startsWith('\uFEFF')) return text.substring(1);
  return text;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  if (slash < 0) return normalized;
  return normalized.substring(slash + 1);
}

String _fileStem(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return name;
  return name.substring(0, dot);
}

String _solutionName(String path) => _fileStem(_basename(path));

String _parentOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  if (slash <= 0) return '';
  return normalized.substring(0, slash);
}

/// Junta [relative] ao diretório de [anchorFile], sempre com `/`.
String resolveAgainst(String anchorFile, String relative) {
  final rel = relative.replaceAll('\\', '/').trim();
  if (rel.startsWith('/') || _isWindowsAbs(rel)) return _normalize(rel);
  final parent = _parentOf(anchorFile.replaceAll('\\', '/'));
  final combined = parent.isEmpty ? rel : '$parent/$rel';
  return _normalize(combined);
}

bool _isWindowsAbs(String path) {
  return path.length >= 3 &&
      path[1] == ':' &&
      (path[2] == '/' || path[2] == '\\');
}

String _normalize(String path) {
  final windows = _isWindowsAbs(path);
  final absolute = path.startsWith('/') || windows;
  final parts = <String>[];
  final raw = windows ? path.substring(2) : path;
  for (final part in raw.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty && parts.last != '..') {
        parts.removeLast();
      } else if (!absolute) {
        parts.add('..');
      }
      continue;
    }
    parts.add(part);
  }
  final joined = parts.join('/');
  if (windows) return '${path.substring(0, 2)}/$joined';
  return absolute ? '/$joined' : joined;
}
