import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Alça horizontal compartilhada pelos subpainéis redimensionáveis do Cockpit.
/// Arrastar para cima/baixo delega somente o delta; o painel dono decide clamp,
/// persistência e direção do redimensionamento.
class PanelResizeHandle extends StatelessWidget {
  const PanelResizeHandle({
    super.key,
    required this.onResizeDelta,
    this.onResizeEnd,
  });

  final ValueChanged<double> onResizeDelta;
  final VoidCallback? onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (details) => onResizeDelta(details.delta.dy),
        onVerticalDragEnd: (_) => onResizeEnd?.call(),
        child: SizedBox(
          height: 9,
          child: Center(
            child: Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
