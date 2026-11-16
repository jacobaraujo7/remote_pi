import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/widgets.dart';

/// Ação compacta de edição usada nos rodapés dos previews.
class PreviewEditButton extends StatelessWidget {
  const PreviewEditButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(5),
      color: colors.panel2,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        label,
        style: context.typo.tab.copyWith(color: colors.text, fontSize: 12),
      ),
    );
  }
}
