import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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
    barrierColor: context.colors.scrim,
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

  void _enter(String folder) => _load(_rel.isEmpty ? folder : '$_rel/$folder');

  /// Navega para o caminho com os primeiros [depth] segmentos (0 = raiz).
  void _goToDepth(int depth) => _load(_segments.take(depth).join('/'));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final atRoot = _rel.isEmpty;
    final tr = context.t.cockpit.subfolderDialog;

    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr.title,
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          _Breadcrumb(
            projectName: widget.projectName,
            segments: _segments,
            onTapSegment: _goToDepth,
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Divider(height: 1, color: colors.border),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator(size: 20)),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
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
                              tr.empty,
                              style: context.typo.label.copyWith(
                                color: colors.text4,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 10),
            Text(
              atRoot
                  ? tr.useRoot(project: widget.projectName)
                  : tr.usePath(project: widget.projectName, rel: _rel),
              overflow: TextOverflow.ellipsis,
              style: context.typo.label.copyWith(color: colors.text3),
            ),
          ],
        ),
      ),
      actions: [
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
        PrimaryButton(
          onPressed: () => Navigator.of(context).pop(_rel),
          child: Text(tr.useThisFolder),
        ),
      ],
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
      crumbs.add(
        _crumb(context, segments[i], i + 1, isLast: i == segments.length - 1),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: crumbs),
    );
  }

  Widget _crumb(
    BuildContext context,
    String label,
    int depth, {
    required bool isLast,
  }) {
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
    return HoverTap(
      onTap: () => onTapSegment(depth),
      borderRadius: const BorderRadius.all(Radius.circular(5)),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Text(label, style: style),
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
    return HoverTap(
      onTap: onTap,
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
          if (trailing != null) Icon(trailing, size: 16, color: colors.text4),
        ],
      ),
    );
  }
}
