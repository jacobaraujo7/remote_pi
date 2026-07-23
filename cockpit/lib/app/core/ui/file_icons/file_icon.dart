import 'package:cockpit/app/core/ui/file_icons/file_icon_map.g.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Resolve o nome do ícone (material-icon-theme) de um arquivo a partir do nome
/// completo. Espelha a precedência do VSCode: nome exato → extensão composta
/// mais longa → extensão final → ícone padrão.
///
/// Ex.: `app.module.ts` casa `module.ts` (angular) antes de `ts`; `.gitignore`
/// casa pelo nome exato; `photo.PNG` é case-insensitive.
/// Extensões do Cockpit que o material-icon-theme não conhece (o mapa `.g` é
/// gerado — overrides manuais moram aqui). `.dbq` = arquivo de query da DB
/// tab (plano 51).
const Map<String, String> _extensionOverrides = {'dbq': 'database'};

String fileIconName(String fileName) {
  final lower = fileName.toLowerCase();
  final byName = kFileNameIcons[lower];
  if (byName != null) return byName;
  final lastDot = lower.lastIndexOf('.');
  if (lastDot > 0) {
    final byOverride = _extensionOverrides[lower.substring(lastDot + 1)];
    if (byOverride != null) return byOverride;
  }

  final parts = lower.split('.');
  for (var k = 1; k < parts.length; k++) {
    final ext = parts.sublist(k).join('.');
    final byExt = kFileExtensionIcons[ext];
    if (byExt != null) return byExt;
  }
  return kDefaultFileIcon;
}

/// Resolve o ícone de uma pasta pelo nome (normalizado), variando entre os
/// estados aberta/fechada.
String folderIconName(String folderName, {bool open = false}) {
  final key = _normalizeFolder(folderName);
  final map = open ? kFolderOpenIcons : kFolderIcons;
  return map[key] ?? (open ? kDefaultFolderOpenIcon : kDefaultFolderIcon);
}

/// Normaliza o nome da pasta igual ao gerador do mapa: minúsculo, sem o
/// envelope `__x__` e sem prefixos `.`/`_`/`-` (variantes que o
/// material-icon-theme registra apontando pro mesmo ícone).
String _normalizeFolder(String name) {
  var s = name.toLowerCase();
  if (s.length > 4 && s.startsWith('__') && s.endsWith('__')) {
    s = s.substring(2, s.length - 2);
  }
  var i = 0;
  while (i < s.length && (s[i] == '.' || s[i] == '_' || s[i] == '-')) {
    i++;
  }
  return s.substring(i);
}

const String _kAssetDir = 'assets/file_icons';

/// Ícone colorido (SVG do material-icon-theme) de um arquivo ou pasta. Mantém
/// as cores originais do tema — **não** recebe tint (a seleção da linha é
/// sinalizada pelo fundo/cor do texto, não pelo ícone).
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon.file(this.name, {super.key, this.size = 16})
    : _isFolder = false,
      _open = false;

  const FileTypeIcon.folder(
    this.name, {
    super.key,
    bool open = false,
    this.size = 16,
  }) : _isFolder = true,
       _open = open;

  /// Nome do arquivo ou da pasta (basename, não o caminho).
  final String name;
  final double size;
  final bool _isFolder;
  final bool _open;

  @override
  Widget build(BuildContext context) {
    final icon = _isFolder
        ? folderIconName(name, open: _open)
        : fileIconName(name);
    return SvgPicture.asset(
      '$_kAssetDir/$icon.svg',
      width: size,
      height: size,
      // Reserva o espaço enquanto o asset decodifica (sem "pulo" na linha).
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
  }
}
