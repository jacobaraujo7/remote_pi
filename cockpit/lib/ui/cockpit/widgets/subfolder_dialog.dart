import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Pergunta em qual pasta dentro do projeto o agente vai atuar. Permite
/// **navegar** pela árvore (entrar nas subpastas e voltar), sempre a partir da
/// raiz do projeto — nunca acima dela. Devolve o caminho **relativo** escolhido
/// (`''` = raiz), ou `null` se cancelar.
///
/// [loadSubfolders] devolve as subpastas imediatas de um caminho relativo
/// (vazio = raiz). O dialog chama sob demanda a cada navegação.
Future<String?> showSubfolderDialog(
  BuildContext context, {
  required String projectName,
  required Future<List<String>> Function(String relativePath) loadSubfolders,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SubfolderDialog(
      projectName: projectName,
      loadSubfolders: loadSubfolders,
    ),
  );
}

class _SubfolderDialog extends StatefulWidget {
  const _SubfolderDialog({
    required this.projectName,
    required this.loadSubfolders,
  });

  final String projectName;
  final Future<List<String>> Function(String relativePath) loadSubfolders;

  @override
  State<_SubfolderDialog> createState() => _SubfolderDialogState();
}

class _SubfolderDialogState extends State<_SubfolderDialog> {
  /// Caminho relativo atual (vazio = raiz). Segmentos separados por `/`.
  String _rel = '';
  List<String> _children = const <String>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(_rel);
  }

  /// Segmentos do caminho atual (`[]` = raiz).
  List<String> get _segments =>
      _rel.isEmpty ? const <String>[] : _rel.split('/');

  Future<void> _load(String rel) async {
    setState(() {
      _loading = true;
      _rel = rel;
    });
    final children = await widget.loadSubfolders(rel);
    if (!mounted) return;
    setState(() {
      _children = children;
      _loading = false;
    });
  }

  void _enter(String folder) =>
      _load(_rel.isEmpty ? folder : '$_rel/$folder');

  /// Navega para o caminho com os primeiros [depth] segmentos (0 = raiz).
  void _goToDepth(int depth) =>
      _load(_segments.take(depth).join('/'));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final atRoot = _rel.isEmpty;

    return Dialog(
      backgroundColor: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.border2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
              child: Text(
                'Where to work?',
                style: context.typo.title.copyWith(
                  fontSize: 15,
                  color: colors.text,
                ),
              ),
            ),
            // Breadcrumb navegável (raiz → … → pasta atual).
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: _Breadcrumb(
                projectName: widget.projectName,
                segments: _segments,
                onTapSegment: _goToDepth,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      children: [
                        // ".." volta um nível (some na raiz).
                        if (!atRoot)
                          _FolderRow(
                            icon: Icons.arrow_upward,
                            label: '..',
                            onTap: () => _goToDepth(_segments.length - 1),
                          ),
                        for (final folder in _children)
                          _FolderRow(
                            icon: Icons.folder_outlined,
                            label: folder,
                            trailing: Icons.chevron_right,
                            onTap: () => _enter(folder),
                          ),
                        if (_children.isEmpty && !atRoot)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 14,
                            ),
                            child: Text(
                              'No subfolders here.',
                              style: context.typo.label
                                  .copyWith(color: colors.text4),
                            ),
                          ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      atRoot
                          ? 'Use the root of ${widget.projectName}'
                          : 'Use ${widget.projectName}/$_rel',
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.label.copyWith(color: colors.text3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                    ),
                    onPressed: () => Navigator.of(context).pop(_rel),
                    child: const Text('Use this folder'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trilha clicável: `projeto / seg1 / seg2`. Tocar num segmento navega até ele.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.projectName,
    required this.segments,
    required this.onTapSegment,
  });

  final String projectName;
  final List<String> segments;
  final void Function(int depth) onTapSegment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final crumbs = <Widget>[
      _crumb(context, projectName, 0, isLast: segments.isEmpty),
    ];
    for (var i = 0; i < segments.length; i++) {
      crumbs.add(Icon(Icons.chevron_right, size: 14, color: colors.text4));
      crumbs.add(_crumb(context, segments[i], i + 1,
          isLast: i == segments.length - 1));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: crumbs),
    );
  }

  Widget _crumb(BuildContext context, String label, int depth,
      {required bool isLast}) {
    final colors = context.colors;
    final style = context.typo.label.copyWith(
      color: isLast ? colors.text : colors.text3,
      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
    );
    if (isLast) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(label, style: style),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: () => onTapSegment(depth),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Text(label, style: style),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final IconData? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 16, color: colors.text3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.body.copyWith(
                    fontSize: 13.5,
                    color: colors.text,
                  ),
                ),
              ),
              if (trailing != null)
                Icon(trailing, size: 16, color: colors.text4),
            ],
          ),
        ),
      ),
    );
  }
}
