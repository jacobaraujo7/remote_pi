import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution.dart';
import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution_cache.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/context_menu_gesture.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

typedef DotnetNodeMenu =
    void Function(
      BuildContext context,
      Offset position,
      String path,
      String name,
      bool isFolder,
    );

/// Árvore lógica da solução. A lista é virtualizada; pastas de projeto
/// carregam filhos do disco só quando expandidas.
class DotnetSolutionTree extends StatefulWidget {
  const DotnetSolutionTree({
    super.key,
    required this.snapshot,
    required this.refreshToken,
    required this.collapseGen,
    required this.listChildren,
    required this.onOpenFile,
    this.selectedPath,
    this.onTapFile,
    this.onSelectFile,
    this.onNodeMenu,
  });

  final DotnetSolutionSnapshot snapshot;
  final int refreshToken;
  final int collapseGen;
  final String? selectedPath;
  final Future<List<FileNode>> Function(String path) listChildren;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String>? onTapFile;
  final ValueChanged<String>? onSelectFile;
  final DotnetNodeMenu? onNodeMenu;

  @override
  State<DotnetSolutionTree> createState() => _DotnetSolutionTreeState();
}

class _DotnetSolutionTreeState extends State<DotnetSolutionTree> {
  final Map<String, List<FileNode>> _disk = {};
  final Set<String> _loadingDirs = {};
  late int _seenCollapse = widget.collapseGen;
  DateTime? _lastTap;
  String? _lastId;

  DotnetSolutionCache get _cache => DotnetSolutionCache.instance;

  @override
  void initState() {
    super.initState();
    _seed();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pumpLoads());
  }

  @override
  void didUpdateWidget(DotnetSolutionTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.path != widget.snapshot.path) {
      _disk.clear();
      _loadingDirs.clear();
      _seed();
    }
    if (oldWidget.refreshToken != widget.refreshToken) {
      _disk.clear();
      _loadingDirs.clear();
    }
    if (widget.collapseGen != _seenCollapse) {
      _seenCollapse = widget.collapseGen;
      _cache.collapse(widget.snapshot.path);
    }
    if (oldWidget.selectedPath != widget.selectedPath) {
      _cache.setSelectedNode(widget.snapshot.path, null);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _pumpLoads());
  }

  void _seed() {
    final path = widget.snapshot.path;
    if (_cache.hasExpansion(path)) return;
    final ids = <String>{};
    void walk(DotnetNode node) {
      if (node.kind == DotnetNodeKind.solution ||
          node.kind == DotnetNodeKind.solutionFolder) {
        ids.add(node.id);
        for (final child in node.children) {
          walk(child);
        }
      }
    }

    walk(widget.snapshot.root);
    _cache.seedExpansion(path, ids);
  }

  void _pumpLoads() {
    if (!mounted) return;
    final dirs = <String>{};
    _collect(widget.snapshot.root, dirs);
    for (final dir in dirs) {
      if (_disk.containsKey(dir) || _loadingDirs.contains(dir)) continue;
      _loadingDirs.add(dir);
      widget.listChildren(dir).then((children) {
        if (!mounted) return;
        setState(() {
          _disk[dir] = children;
          _loadingDirs.remove(dir);
        });
        _pumpLoads();
      });
    }
  }

  void _collect(DotnetNode node, Set<String> dirs) {
    final open = _cache.expansion(widget.snapshot.path).contains(node.id);
    if (!open) return;
    final directory = node.directory;
    if (directory != null && directory.isNotEmpty) dirs.add(directory);
    for (final child in node.children) {
      _collect(child, dirs);
    }
    if (directory == null) return;
    for (final file in _disk[directory] ?? const <FileNode>[]) {
      if (!file.isDirectory || _skipDisk(file.name, node)) continue;
      if (_takenNames(node).contains(file.name.toLowerCase())) continue;
      final id = 'disk:${file.path}';
      if (!_cache.expansion(widget.snapshot.path).contains(id)) continue;
      dirs.add(file.path);
      _collectDisk(file.path, dirs);
    }
  }

  void _collectDisk(String dir, Set<String> dirs) {
    for (final file in _disk[dir] ?? const <FileNode>[]) {
      if (!file.isDirectory || _skipName(file.name)) continue;
      final id = 'disk:${file.path}';
      if (!_cache.expansion(widget.snapshot.path).contains(id)) continue;
      dirs.add(file.path);
      _collectDisk(file.path, dirs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _flatten(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      itemExtent: 26,
      itemCount: rows.length,
      itemBuilder: (context, index) => _buildRow(context, rows[index]),
    );
  }

  List<_SolutionRow> _flatten(BuildContext context) {
    final tr = context.t;
    final rows = <_SolutionRow>[];
    final expanded = _cache.expansion(widget.snapshot.path);
    void addNode(DotnetNode node, int depth) {
      final open = expanded.contains(node.id);
      final expandable = _expandable(node);
      rows.add(
        _SolutionRow(
          id: node.id,
          depth: depth,
          kind: node.kind,
          label: node.name,
          suffix: _suffix(node, tr),
          expandable: expandable,
          expanded: open,
          openPath: node.path,
          menuPath: _menuPath(node),
          menuIsFolder: _menuIsFolder(node),
          menuName: node.name,
          fileName: _iconName(node),
        ),
      );
      if (!expandable || !open) return;
      final directory = node.directory;
      final taken = directory == null ? const <String>{} : _takenNames(node);
      final disk = <FileNode>[
        if (directory != null)
          for (final file in _disk[directory] ?? const <FileNode>[])
            if (!_skipDisk(file.name, node) &&
                !taken.contains(file.name.toLowerCase()))
              file,
      ];
      final siblings =
          <_Sibling>[
            for (final child in node.children) _Sibling.logical(child),
            for (final file in disk) _Sibling.disk(file),
          ]..sort(
            (a, b) => compareSolutionNames(
              aIsFile: a.isFile,
              aName: a.name,
              bIsFile: b.isFile,
              bName: b.name,
            ),
          );
      for (final sibling in siblings) {
        final child = sibling.node;
        if (child != null) {
          addNode(child, depth + 1);
          continue;
        }
        _addDisk(sibling.file!, depth + 1, rows, expanded);
      }
    }

    addNode(widget.snapshot.root, 0);
    return rows;
  }

  void _addDisk(
    FileNode file,
    int depth,
    List<_SolutionRow> rows,
    Set<String> expanded,
  ) {
    if (_skipName(file.name)) return;
    if (file.isDirectory) {
      final id = 'disk:${file.path}';
      final open = expanded.contains(id);
      rows.add(
        _SolutionRow(
          id: id,
          depth: depth,
          kind: DotnetNodeKind.folder,
          label: file.name,
          expandable: true,
          expanded: open,
          menuPath: file.path,
          menuIsFolder: true,
          menuName: file.name,
          fileName: file.name,
        ),
      );
      if (!open) return;
      final children = [...(_disk[file.path] ?? const <FileNode>[])]
        ..sort(
          (a, b) => compareSolutionNames(
            aIsFile: !a.isDirectory,
            aName: a.name,
            bIsFile: !b.isDirectory,
            bName: b.name,
          ),
        );
      for (final child in children) {
        _addDisk(child, depth + 1, rows, expanded);
      }
      return;
    }
    rows.add(
      _SolutionRow(
        id: 'disk:${file.path}',
        depth: depth,
        kind: DotnetNodeKind.file,
        label: file.name,
        expandable: false,
        expanded: false,
        openPath: file.path,
        menuPath: file.path,
        menuName: file.name,
        fileName: file.name,
      ),
    );
  }

  Widget _buildRow(BuildContext context, _SolutionRow row) {
    final colors = context.colors;
    final selectedId = _cache.selectedNode(widget.snapshot.path);
    final selected = selectedId != null
        ? selectedId == row.id
        : row.openPath != null && row.openPath == widget.selectedPath;
    final icon = row.kind == DotnetNodeKind.folder || _groupFolder(row.kind)
        ? FileTypeIcon.folder(row.fileName ?? row.label, open: row.expanded)
        : FileTypeIcon.file(row.fileName ?? row.label);
    final line = HoverTap(
      color: selected ? colors.panel2 : Colors.transparent,
      hoverColor: colors.panel,
      borderRadius: BorderRadius.circular(5),
      onTap: () => _handleTap(row),
      padding: EdgeInsets.only(left: 6 + row.depth * 14.0, right: 6),
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: row.expandable
                  ? Icon(
                      row.expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right,
                      size: 15,
                      color: colors.text4,
                    )
                  : null,
            ),
            const SizedBox(width: 2),
            icon,
            const SizedBox(width: 7),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      row.label,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.body.copyWith(
                        fontSize: 13,
                        color: selected ? colors.text : colors.text2,
                      ),
                    ),
                  ),
                  if (row.suffix != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      row.suffix!,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.body.copyWith(
                        fontSize: 12,
                        color: colors.text4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final menuPath = row.menuPath;
    final onMenu = widget.onNodeMenu;
    if (menuPath == null || onMenu == null) return line;
    return ContextMenuGesture(
      longPressOnMobile: false,
      onMenu: (position) => onMenu(
        context,
        position,
        menuPath,
        row.menuName ?? row.label,
        row.menuIsFolder,
      ),
      child: line,
    );
  }

  void _handleTap(_SolutionRow row) {
    final path = widget.snapshot.path;
    final now = DateTime.now();
    final doubleTap =
        _lastId == row.id &&
        _lastTap != null &&
        now.difference(_lastTap!).inMilliseconds < 350;
    _lastTap = now;
    _lastId = row.id;
    if (row.expandable) {
      if (doubleTap &&
          row.openPath != null &&
          row.kind == DotnetNodeKind.project) {
        widget.onOpenFile(row.openPath!);
        return;
      }
      _cache.toggleExpanded(path, row.id);
      _cache.setSelectedNode(path, row.id);
      setState(() {});
      _pumpLoads();
      return;
    }
    final openPath = row.openPath;
    if (openPath == null) {
      _cache.setSelectedNode(path, row.id);
      setState(() {});
      return;
    }
    if (doubleTap) {
      widget.onOpenFile(openPath);
      return;
    }
    _cache.setSelectedNode(path, null);
    widget.onSelectFile?.call(openPath);
    widget.onTapFile?.call(openPath);
  }

  bool _expandable(DotnetNode node) => node.showsChevron;

  bool _groupFolder(DotnetNodeKind kind) {
    return kind == DotnetNodeKind.solution ||
        kind == DotnetNodeKind.solutionFolder;
  }

  String? _suffix(DotnetNode node, Translations tr) {
    if (node.projectCount <= 0) return null;
    if (node.kind != DotnetNodeKind.solution &&
        node.kind != DotnetNodeKind.solutionFolder) {
      return null;
    }
    return tr.cockpit.fileTreePanel.projectCount(n: node.projectCount);
  }

  String? _menuPath(DotnetNode node) {
    if (node.kind == DotnetNodeKind.project) return node.directory ?? node.path;
    if (node.kind == DotnetNodeKind.folder) return node.directory ?? node.path;
    if (node.kind == DotnetNodeKind.file) return node.path;
    return null;
  }

  bool _menuIsFolder(DotnetNode node) {
    if (node.kind == DotnetNodeKind.project) return node.directory != null;
    if (node.kind == DotnetNodeKind.folder) {
      return node.directory != null || node.path == null;
    }
    return false;
  }

  String _iconName(DotnetNode node) {
    final path = node.path;
    if (path != null && path.isNotEmpty) return _base(path);
    return node.name;
  }

  Set<String> _takenNames(DotnetNode node) {
    return {for (final child in node.children) child.name.toLowerCase()};
  }

  bool _skipDisk(String name, DotnetNode node) {
    if (_skipName(name)) return true;
    if (node.kind != DotnetNodeKind.project) return false;
    final path = node.path;
    if (path == null) return false;
    return name.toLowerCase() == _base(path).toLowerCase();
  }

  bool _skipName(String name) {
    final lower = name.toLowerCase();
    return lower == 'bin' || lower == 'obj';
  }
}

class _Sibling {
  const _Sibling.logical(this.node) : file = null;
  const _Sibling.disk(this.file) : node = null;

  final DotnetNode? node;
  final FileNode? file;

  bool get isFile =>
      node != null ? node!.kind == DotnetNodeKind.file : !file!.isDirectory;

  String get name => node?.name ?? file!.name;
}

class _SolutionRow {
  const _SolutionRow({
    required this.id,
    required this.depth,
    required this.kind,
    required this.label,
    required this.expandable,
    required this.expanded,
    this.suffix,
    this.openPath,
    this.menuPath,
    this.menuIsFolder = false,
    this.menuName,
    this.fileName,
  });

  final String id;
  final int depth;
  final DotnetNodeKind kind;
  final String label;
  final String? suffix;
  final bool expandable;
  final bool expanded;
  final String? openPath;
  final String? menuPath;
  final bool menuIsFolder;
  final String? menuName;
  final String? fileName;
}

String _base(String path) {
  final slash = path.lastIndexOf('/');
  if (slash < 0) return path;
  return path.substring(slash + 1);
}
