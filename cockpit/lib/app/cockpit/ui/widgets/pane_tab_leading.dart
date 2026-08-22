import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PaneTabLeading extends StatelessWidget {
  final PaneItem? item;
  final IconData defaultIcon;
  final Color iconColor;
  final double size;

  const PaneTabLeading({
    super.key,
    required this.item,
    required this.defaultIcon,
    required this.iconColor,
    this.size = 13.0,
  });

  @override
  Widget build(BuildContext context) {
    final session = item;
    if (session is TerminalSession) {
      final harness = session.activeHarness;
      if (harness != null) {
        final spec = HarnessCatalog.getSpec(harness);
        if (spec != null) {
          final colorFilter = spec.isMonochrome
              ? ColorFilter.mode(iconColor, BlendMode.srcIn)
              : null;
          return SvgPicture.asset(
            spec.assetPath,
            width: size,
            height: size,
            colorFilter: colorFilter,
          );
        }
      }
    }

    return Icon(
      defaultIcon,
      size: size,
      color: iconColor,
    );
  }
}
