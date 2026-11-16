import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';

/// Lê e classifica um arquivo para o viewer (markdown / texto / imagem /
/// não-suportado). Contrato no domínio; impl (dart:io) em `data/filesystem/`.
abstract class FileReader {
  // Board Markdown embeds PNG previews. Match the remote FileService read budget.
  static const boardByteLimit = 8 * 1024 * 1024;
  static bool isBoard(String path) => path.toLowerCase().endsWith('.canvas') || path.toLowerCase().endsWith('.board');
  static int readLimit(String path) =>
      isBoard(path) ? boardByteLimit : 2 * 1024 * 1024;

  Future<FileView> read(String path);

  /// Grava [content] em [path] com o [encoding] informado, sobrescrevendo.
  /// Retorna `true` no sucesso, `false` se o IO falhar (sem permissão, disco
  /// cheio, path sumiu). Não há merge nem trava: escrita simultânea do agente
  /// é last-write-wins (escopo MVP).
  ///
  /// Passe o [encoding] da [FileView] original para preservar o encoding do
  /// arquivo no disco (evita diffs artificiais em arquivos não-UTF-8).
  /// Arquivos novos (scratch) usam [utf8] como padrão.
  Future<bool> write(String path, String content, {Encoding encoding = utf8});
}
