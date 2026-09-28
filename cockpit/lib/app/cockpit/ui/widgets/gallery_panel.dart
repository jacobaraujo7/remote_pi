import 'package:cockpit/app/cockpit/domain/entities/gallery_template.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Aba **Gallery** do painel direito: vitrine dos documentos especiais do
/// Cockpit (`.dbq`, `.kanban`, `.ckp`, `.http`, `.env.cockpit`). Cada card = ícone colorido +
/// título + descrição; clicar cria o arquivo na raiz do workspace e abre a
/// tab (o "como" mora no [onCreate], que o VM implementa).
class GalleryPanel extends StatelessWidget {
  const GalleryPanel({super.key, required this.onCreate});

  /// Chamado com o template do card clicado.
  final ValueChanged<GalleryTemplate> onCreate;

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.gallery;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(
            tr.intro,
            style: context.typo.label.copyWith(color: context.colors.text3),
          ),
        ),
        for (final template in GalleryTemplate.values)
          _GalleryCard(
            key: ValueKey('gallery-${template.name}'),
            template: template,
            title: _titleOf(tr, template),
            description: _descriptionOf(tr, template),
            onTap: () => onCreate(template),
          ),
      ],
    );
  }

  static String _titleOf(
    Translations$cockpit$gallery$en tr,
    GalleryTemplate t,
  ) => switch (t) {
    GalleryTemplate.dbQuery => tr.dbQuery.title,
    GalleryTemplate.kanban => tr.kanban.title,
    GalleryTemplate.layout => tr.layout.title,
    GalleryTemplate.httpRequest => tr.httpRequest.title,
    GalleryTemplate.html => tr.html.title,
    GalleryTemplate.panel => tr.panel.title,
    GalleryTemplate.tasks => tr.tasks.title,
    GalleryTemplate.notebook => tr.notebook.title,
    GalleryTemplate.workspaceEnv => tr.workspaceEnv.title,
    GalleryTemplate.diagram => tr.diagram.title,
  };

  static String _descriptionOf(
    Translations$cockpit$gallery$en tr,
    GalleryTemplate t,
  ) => switch (t) {
    GalleryTemplate.dbQuery => tr.dbQuery.description,
    GalleryTemplate.kanban => tr.kanban.description,
    GalleryTemplate.layout => tr.layout.description,
    GalleryTemplate.httpRequest => tr.httpRequest.description,
    GalleryTemplate.html => tr.html.description,
    GalleryTemplate.panel => tr.panel.description,
    GalleryTemplate.tasks => tr.tasks.description,
    GalleryTemplate.notebook => tr.notebook.description,
    GalleryTemplate.workspaceEnv => tr.workspaceEnv.description,
    GalleryTemplate.diagram => tr.diagram.description,
  };
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    super.key,
    required this.template,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final GalleryTemplate template;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSvg = template.iconAsset.endsWith('.svg');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HoverTap(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: isSvg
                    ? SvgPicture.asset(template.iconAsset)
                    : Image.asset(template.iconAsset),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: context.typo.label.copyWith(
                              color: colors.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          template.opensParent
                              ? template.relativeDir
                              : template.relativeDir.isEmpty
                              ? '.${template.extension}'
                              : template.relativePath,
                          style: context.typo.label.copyWith(
                            fontSize: 10,
                            color: colors.text3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: context.typo.label.copyWith(
                        fontSize: 11,
                        color: colors.text3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
