import 'package:cockpit/app/cockpit/domain/entities/db_connection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Logo (SVG de marca, Devicon) do engine de banco — usado no painel Database
/// e no popup de engine do "+". Cada [DbEngine] tem um asset em
/// `assets/db_icons/<name>.svg`.
class DbEngineIcon extends StatelessWidget {
  const DbEngineIcon(this.engine, {super.key, this.size = 14});

  final DbEngine engine;
  final double size;

  static const _assetDir = 'assets/db_icons';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      '$_assetDir/${engine.name}.svg',
      width: size,
      height: size,
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
  }
}
