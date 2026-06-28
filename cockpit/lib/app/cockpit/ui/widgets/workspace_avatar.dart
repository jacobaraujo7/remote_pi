import 'dart:io';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Avatar de um workspace. Por padrão é o quadrado colorido com a inicial do
/// nome; quando há [imagePath] (PNG/JPG/SVG escolhido em Workspace Settings),
/// mostra a imagem recortada no mesmo formato (SVG renderiza vetorial → nítido
/// em qualquer tamanho). Se o arquivo sumir/for ilegível, cai num **placeholder
/// de erro** (ícone de imagem quebrada) — nunca quebra a UI.
class WorkspaceAvatar extends StatelessWidget {
  const WorkspaceAvatar({
    super.key,
    required this.imagePath,
    required this.colorValue,
    required this.initial,
    this.size = 30,
    this.radius = 7,
  });

  /// Caminho absoluto da imagem ou `null` para o avatar de cor + inicial.
  final String? imagePath;
  final int colorValue;
  final String initial;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path != null && path.isNotEmpty) {
      final isSvg = path.toLowerCase().endsWith('.svg');
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        // SizedBox externo garante o mesmo footprint pra raster e vetor: o
        // SvgPicture dimensiona pelo viewBox e ignora width/height ao calcular o
        // tamanho do layout, então sem o box forçado o SVG estoura o recorte e
        // aparece maior que os PNGs. Com a caixa fixa, o BoxFit.cover preenche
        // exatamente size×size nos dois casos.
        child: SizedBox(
          width: size,
          height: size,
          // Arquivo movido/deletado/corrompido → placeholder de erro (ambos os
          // loaders têm errorBuilder, então cobre raster e vetor do mesmo jeito).
          child: isSvg
              ? SvgPicture.file(
                  File(path),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => _errorBox(context),
                )
              : Image.file(
                  File(path),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, _, _) => _errorBox(context),
                ),
        ),
      );
    }
    // Sem imagem: quadrado colorido com a inicial.
    return _box(
      context,
      child: Text(
        initial,
        style: context.typo.title.copyWith(
          fontSize: size * 0.43,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _errorBox(BuildContext context) => _box(
    context,
    child: Icon(
      Icons.broken_image_outlined,
      size: size * 0.5,
      color: Colors.white,
    ),
  );

  Widget _box(BuildContext context, {required Widget child}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(colorValue),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
