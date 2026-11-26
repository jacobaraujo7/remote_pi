import 'dart:io' show Platform;

import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';

/// Rótulo "Abrir no Finder / Explorer / gerenciador de arquivos" conforme a
/// plataforma. Compartilhado pela árvore de arquivos e pelo menu da aba.
String fileManagerLabel(BuildContext context) {
  final tr = context.t.cockpit.fileTreePanel;
  if (Platform.isMacOS) return tr.openInFinder;
  if (Platform.isWindows) return tr.openInExplorer;
  return tr.openInFileManager;
}
