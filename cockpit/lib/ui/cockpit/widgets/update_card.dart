import 'package:cockpit/ui/cockpit/viewmodels/update_viewmodel.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Mini card de atualização no rodapé do rail — acima do nome da máquina. Só
/// renderiza quando o [UpdateViewModel] tem uma versão nova não dispensada.
/// Clicar baixa o artefato; o X dispensa (persiste por versão).
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<UpdateViewModel>();
    final info = vm.available;
    if (info == null) return const SizedBox.shrink();

    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.read<UpdateViewModel>().download(),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.accent.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.system_update_alt,
                  size: 15,
                  color: colors.accentText,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Update available',
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.label.copyWith(
                          color: colors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'v${info.version} — click to download',
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.label.copyWith(color: colors.text3),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Dismiss',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => context.read<UpdateViewModel>().dismiss(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: colors.text3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
