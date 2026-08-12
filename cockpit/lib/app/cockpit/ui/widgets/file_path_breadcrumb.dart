import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Breadcrumb de um caminho de arquivo no rodape dos viewers (estilo VS Code).
/// Mostra o caminho relativo ao workspace quando disponivel e rola na horizontal.
class FilePathBreadcrumb extends StatelessWidget {
  const FilePathBreadcrumb({
    super.key,
    required this.path,
    required this.fileName,
  });

  /// Caminho ja resolvido (relativo ou absoluto), sem barra inicial.
  final String path;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final segs = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segs.isEmpty) segs.add(fileName);

    final crumbs = <Widget>[];
    for (var index = 0; index < segs.length; index++) {
      final isLast = index == segs.length - 1;
      if (index > 0) {
        crumbs.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(Icons.chevron_right, size: 14, color: colors.text4),
          ),
        );
      }
      if (isLast) {
        crumbs
          ..add(FileTypeIcon.file(fileName, size: 13))
          ..add(const SizedBox(width: 5));
      }
      crumbs.add(
        Text(
          segs[index],
          style: typo.label.copyWith(
            fontSize: 12,
            color: isLast ? colors.text2 : colors.text4,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: crumbs),
    );
  }
}
